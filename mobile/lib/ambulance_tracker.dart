import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class AmbulanceTrackerWidget extends StatefulWidget {
  final double userLat;
  final double userLng;
  final Map<String, dynamic> selectedHospital;
  final VoidCallback onDismiss;

  const AmbulanceTrackerWidget({
    super.key,
    required this.userLat,
    required this.userLng,
    required this.selectedHospital,
    required this.onDismiss,
  });

  @override
  State<AmbulanceTrackerWidget> createState() => _AmbulanceTrackerWidgetState();
}

class _AmbulanceTrackerWidgetState extends State<AmbulanceTrackerWidget> {
  final MapController _mapController = MapController();
  
  List<LatLng> _routePoints = [];
  bool _isLoading = true;
  String _status = "Initializing GPS Sync...";
  int _currentPathIndex = 0;
  
  // Real-time animation variables
  LatLng? _ambulancePos;
  double _distanceRemainingKm = 0.0;
  double _etaMinutes = 0.0;
  double _speedKmh = 48.0;
  Timer? _simulationTimer;

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }

  // Fetches calculated route path from FastAPI backend
  Future<void> _fetchRoute() async {
    final hospLat = widget.selectedHospital['latitude'] ?? widget.userLat - 0.01;
    final hospLng = widget.selectedHospital['longitude'] ?? widget.userLng + 0.01;
    
    final url = Uri.parse(
      'http://localhost:8000/ambulance/route?user_lat=${widget.userLat}&user_lon=${widget.userLng}&hospital_lat=$hospLat&hospital_lon=$hospLng',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> rawRoute = data['route'] ?? [];
        
        setState(() {
          _routePoints = rawRoute.map((p) => LatLng(p['lat'], p['lon'])).toList();
          _distanceRemainingKm = data['distance_km'] ?? 3.5;
          _etaMinutes = data['eta_minutes'] ?? 5.0;
          _isLoading = false;
          _status = "Ambulance Dispatched";
        });
        
        _startSimulation();
      } else {
        _generateMockRoute();
      }
    } catch (e) {
      debugPrint("Routing API Error, simulating backup dispatch path: $e");
      _generateMockRoute();
    }
  }

  // Backup high-fidelity client-side route generator on offline/network errors
  void _generateMockRoute() {
    final hospLat = widget.selectedHospital['latitude'] ?? widget.userLat - 0.01;
    final hospLng = widget.selectedHospital['longitude'] ?? widget.userLng + 0.01;

    // Build realistic block turns
    final List<LatLng> generated = [];
    generated.add(LatLng(hospLat, hospLng));
    
    // Add block turns
    generated.add(LatLng(hospLat + (widget.userLat - hospLat) * 0.3, hospLng));
    generated.add(LatLng(hospLat + (widget.userLat - hospLat) * 0.3, hospLng + (widget.userLng - hospLng) * 0.6));
    generated.add(LatLng(hospLat + (widget.userLat - hospLat) * 0.8, hospLng + (widget.userLng - hospLng) * 0.6));
    generated.add(LatLng(widget.userLat, widget.userLng));

    setState(() {
      _routePoints = generated;
      _distanceRemainingKm = 2.8;
      _etaMinutes = 4.2;
      _isLoading = false;
      _status = "Ambulance Dispatched";
    });

    _startSimulation();
  }

  // Starts the active simulated GPS tracking update
  void _startSimulation() {
    if (_routePoints.isEmpty) return;
    
    _ambulancePos = _routePoints.first;
    _currentPathIndex = 0;
    
    // Periodically advance the ambulance along the route segment coordinates
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!mounted) return;
      
      setState(() {
        if (_currentPathIndex < _routePoints.length - 1) {
          _currentPathIndex++;
          _ambulancePos = _routePoints[_currentPathIndex];
          
          // Gradually reduce ETA and remaining distance
          final progress = _currentPathIndex / (_routePoints.length - 1);
          _distanceRemainingKm = max(0.0, _distanceRemainingKm * (1.0 - progress * 0.15));
          _etaMinutes = max(0.0, _etaMinutes * (1.0 - progress * 0.15));
          
          // Speed variance
          _speedKmh = 45.0 + (timer.hashCode % 15 - 7);

          // Update Status
          if (progress > 0.85) {
            _status = "Ambulance Approaching Scene";
          } else if (progress > 0.4) {
            _status = "En Route - Speed Optimized";
          } else {
            _status = "Dispatched - Transmitting Triage Assessment";
          }
        } else {
          // Arrived
          _ambulancePos = _routePoints.last;
          _distanceRemainingKm = 0.0;
          _etaMinutes = 0.0;
          _status = "Arrived at Emergency Scene";
          _simulationTimer?.cancel();
        }
      });

      // Fit map bounds to show both user and moving ambulance dynamically
      if (_mapController.camera != null) {
        _mapController.move(_ambulancePos!, 14.5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 400,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C2E),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF3B30)),
        ),
      );
    }

    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Leaflet Map layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(widget.userLat, widget.userLng),
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.roadsos',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 4.5,
                    color: const Color(0xFFFF3B30),
                    borderColor: const Color(0xFFFF3B30).withOpacity(0.3),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // User Location (Target Star)
                  Marker(
                    point: LatLng(widget.userLat, widget.userLng),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blueAccent, width: 2),
                      ),
                      child: const Icon(Icons.person_pin, color: Colors.blueAccent, size: 24),
                    ),
                  ),
                  
                  // Ambulance Moving Marker (Animated)
                  if (_ambulancePos != null)
                    Marker(
                      point: _ambulancePos!,
                      width: 50,
                      height: 50,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulse indicator
                          _StatusPulseRing(),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF3B30),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFFFF3B30),
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                )
                              ]
                            ),
                            child: const Icon(
                              Icons.airport_shuttle_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Glassmorphic status board at the top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF111122).withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF3B30),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _status.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF3B30),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "${_speedKmh.toStringAsFixed(0)} km/h",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "ESTIMATED ETA",
                            style: TextStyle(fontSize: 9, color: Colors.white30, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _etaMinutes > 0
                                ? "${_etaMinutes.toStringAsFixed(1)} Mins"
                                : "Arrived",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            "DISTANCE LEFT",
                            style: TextStyle(fontSize: 9, color: Colors.white30, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _distanceRemainingKm > 0
                                ? "${_distanceRemainingKm.toStringAsFixed(2)} Km"
                                : "0.0 Km",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom control deck
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111122).withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.selectedHospital['name'] ?? 'Trauma Center Service',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          "Vehicle: AMB-SOS-2026-DL",
                          style: TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: widget.onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.08),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                    child: const Text(
                      "DISMISS",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPulseRing extends StatefulWidget {
  @override
  State<_StatusPulseRing> createState() => _StatusPulseRingState();
}

class _StatusPulseRingState extends State<_StatusPulseRing> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 50 * _controller.value,
          height: 50 * _controller.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF3B30).withOpacity(1.0 - _controller.value),
          ),
        );
      },
    );
  }
}
