import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DrivingEvent {
  final LatLng position;
  final String type; // 'speeding' or 'distraction'
  final String description;
  final String time;

  DrivingEvent({
    required this.position,
    required this.type,
    required this.description,
    required this.time,
  });
}

class TripData {
  final String id;
  final String date;
  final String time;
  final double score;
  final double distanceKm;
  final double durationMinutes;
  final List<LatLng> route;
  final List<DrivingEvent> events;

  TripData({
    required this.id,
    required this.date,
    required this.time,
    required this.score,
    required this.distanceKm,
    required this.durationMinutes,
    required this.route,
    required this.events,
  });
}

class TripVisualizationPage extends StatefulWidget {
  final TripData trip;

  const TripVisualizationPage({super.key, required this.trip});

  @override
  State<TripVisualizationPage> createState() => _TripVisualizationPageState();
}

class _TripVisualizationPageState extends State<TripVisualizationPage> {
  final MapController _mapController = MapController();
  DrivingEvent? _selectedEvent;

  @override
  Widget build(BuildContext context) {
    // Generate safety color based on score
    final Color scoreColor = widget.trip.score >= 90
        ? const Color(0xFF34C759)
        : widget.trip.score >= 75
            ? Colors.orangeAccent
            : const Color(0xFFFF3B30);

    final markers = <Marker>[];

    // Start Marker (Green Dot)
    if (widget.trip.route.isNotEmpty) {
      markers.add(
        Marker(
          point: widget.trip.route.first,
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF34C759), width: 2),
            ),
            child: const Icon(Icons.play_arrow, color: Color(0xFF34C759), size: 16),
          ),
        ),
      );

      // End Marker (Red Dot)
      markers.add(
        Marker(
          point: widget.trip.route.last,
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFF3B30), width: 2),
            ),
            child: const Icon(Icons.stop, color: const Color(0xFFFF3B30), size: 16),
          ),
        ),
      );
    }

    // Add Driving Event Markers
    for (final e in widget.trip.events) {
      final isSpeeding = e.type == 'speeding';
      markers.add(
        Marker(
          point: e.position,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedEvent = e;
              });
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSpeeding
                        ? Colors.orangeAccent.withValues(alpha: 0.25)
                        : const Color(0xFFFF3B30).withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSpeeding ? Colors.orangeAccent : const Color(0xFFFF3B30),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSpeeding
                            ? Colors.orangeAccent.withValues(alpha: 0.2)
                            : const Color(0xFFFF3B30).withValues(alpha: 0.2),
                        blurRadius: 8,
                      )
                    ],
                  ),
                  child: Icon(
                    isSpeeding ? Icons.speed : Icons.phone_android,
                    color: isSpeeding ? Colors.orangeAccent : const Color(0xFFFF3B30),
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Trip Analytics Summary",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            Text(
              "${widget.trip.date} • ${widget.trip.time}",
              style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: const Color(0xFF0F0F1A),
      body: Stack(
        children: [
          // Map Viewport
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.trip.route.isNotEmpty
                  ? widget.trip.route[widget.trip.route.length ~/ 2]
                  : const LatLng(28.5244, 77.2066),
              initialZoom: 13.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.roadsos',
              ),
              if (widget.trip.route.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.trip.route,
                      strokeWidth: 4.0,
                      color: Colors.blueAccent.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),

          // Safety Event Detail Card (Float overlay)
          if (_selectedEvent != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111122).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedEvent!.type == 'speeding'
                        ? Colors.orangeAccent.withValues(alpha: 0.5)
                        : const Color(0xFFFF3B30).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _selectedEvent!.type == 'speeding'
                            ? Colors.orangeAccent.withValues(alpha: 0.15)
                            : const Color(0xFFFF3B30).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _selectedEvent!.type == 'speeding' ? Icons.speed : Icons.phone_android,
                        color: _selectedEvent!.type == 'speeding'
                            ? Colors.orangeAccent
                            : const Color(0xFFFF3B30),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _selectedEvent!.type == 'speeding'
                                    ? "Speeding Event"
                                    : "Distracted Driving (Phone)",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _selectedEvent = null),
                                child: const Icon(Icons.close, color: Colors.white54, size: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedEvent!.description,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Occurred at ${_selectedEvent!.time}",
                            style: const TextStyle(fontSize: 10, color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Slide Deck containing Trip metrics
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C2E).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Safety Score header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: scoreColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              "Safety Score: ${widget.trip.score.toStringAsFixed(0)}",
                              style: TextStyle(
                                color: scoreColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "${widget.trip.events.length} Safety Incidents",
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.trip.events.isNotEmpty
                              ? const Color(0xFFFF3B30)
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Key Performance Metrics
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetricColumn("DISTANCE", "${widget.trip.distanceKm.toStringAsFixed(1)} Km", Icons.straighten),
                      _buildMetricColumn("DURATION", "${widget.trip.durationMinutes.toStringAsFixed(0)} Min", Icons.timer_outlined),
                      _buildMetricColumn("AVG SPEED", "46 km/h", Icons.trending_up),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),
                  
                  // Summary count chips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.speed, color: Colors.orangeAccent, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            "${widget.trip.events.where((e) => e.type == 'speeding').length} Speeding alerts",
                            style: const TextStyle(fontSize: 11, color: Colors.white60),
                          ),
                        ],
                      ),
                      Container(width: 1, height: 12, color: Colors.white24),
                      Row(
                        children: [
                          const Icon(Icons.phone_android, color: Color(0xFFFF3B30), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            "${widget.trip.events.where((e) => e.type == 'distraction').length} Distractions",
                            style: const TextStyle(fontSize: 11, color: Colors.white60),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Colors.white30, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ],
    );
  }
}
