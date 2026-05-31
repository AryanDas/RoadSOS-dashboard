import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'db_helper.dart';

class MapDashboardWidget extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final Function(Map<String, dynamic> hospital)? onHospitalSelected;

  const MapDashboardWidget({
    super.key,
    this.initialLat = 28.5244, // Delhi Saket center
    this.initialLng = 77.2066,
    this.onHospitalSelected,
  });

  @override
  State<MapDashboardWidget> createState() => _MapDashboardWidgetState();
}

class _MapDashboardWidgetState extends State<MapDashboardWidget> {
  final MapController _mapController = MapController();
  
  List<Map<String, dynamic>> _hospitals = [];
  List<Map<String, dynamic>> _policeStations = [];
  bool _isLoading = false;
  
  // Filter settings
  bool _showHospitals = true;
  bool _showPolice = true;
  bool _showTowing = true;
  
  // Selected amenity to display details
  Map<String, dynamic>? _selectedFacility;
  String? _selectedType; // 'hospital' or 'police'

  @override
  void initState() {
    super.initState();
    _fetchFacilities(widget.initialLat, widget.initialLng);
  }

  // Real-time query to backend for facilities in the bounding box
  Future<void> _fetchFacilities(double lat, double lng) async {
    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse(
      'http://localhost:8000/emergency-facilities?lat=$lat&lon=$lng&radius_km=5.0',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final List<dynamic> rawHospitals = data['hospitals'] ?? [];
        final List<dynamic> rawPolice = data['police_stations'] ?? [];

        // Parse and cache
        final parsedHospitals = rawHospitals.map((h) => {
          'osm_id': h['id']?.toString() ?? '',
          'name': h['name'] ?? 'Hospital',
          'latitude': h['lat'] ?? 0.0,
          'longitude': h['lon'] ?? 0.0,
          'phone': h['phone'] ?? '',
          'abdm_verified': (h['abdm_verified'] == true) ? 1 : 0,
          'abdm_facility_id': h['abdm_facility_id'] ?? '',
          'operational_status': h['operational_status'] ?? 'Active',
          'address': '${h['street'] ?? ''} ${h['city'] ?? ''}'.trim(),
        }).toList();

        final parsedPolice = rawPolice.map((p) => {
          'osm_id': p['id']?.toString() ?? '',
          'name': p['name'] ?? 'Police Station',
          'latitude': p['lat'] ?? 0.0,
          'longitude': p['lon'] ?? 0.0,
          'phone': p['phone'] ?? '',
          'address': '${p['street'] ?? ''} ${p['city'] ?? ''}'.trim(),
        }).toList();

        // Perform bulk cache inside SQLite DbHelper
        await DbHelper.instance.bulkCacheHospitals(parsedHospitals);
        await DbHelper.instance.bulkCachePoliceStations(parsedPolice);

        setState(() {
          _hospitals = parsedHospitals;
          _policeStations = parsedPolice;
        });
      } else {
        _loadCachedFallback(lat, lng);
      }
    } catch (e) {
      debugPrint("API Error, falling back to local SQLite cache: $e");
      _loadCachedFallback(lat, lng);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Offline/API-failed SQLite local cache fallback
  Future<void> _loadCachedFallback(double lat, double lng) async {
    final latDelta = 5.0 / 111.0;
    final lngDelta = 5.0 / (111.0 * 0.88); // Cos approximation

    final cachedHospitals = await DbHelper.instance.getNearbyHospitals(
      minLat: lat - latDelta,
      maxLat: lat + latDelta,
      minLon: lng - lngDelta,
      maxLon: lng + lngDelta,
    );

    final cachedPolice = await DbHelper.instance.getPoliceStations(); // Fetch all saved police stations

    setState(() {
      _hospitals = cachedHospitals;
      _policeStations = cachedPolice;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("⚠️ Offline Mode: Loaded emergency amenities from local database cache."),
        backgroundColor: Colors.amber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Generate markers
    final markers = <Marker>[];

    // User Location Marker (Pulse Animation)
    markers.add(
      Marker(
        point: LatLng(widget.initialLat, widget.initialLng),
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );

    // Hospitals
    if (_showHospitals) {
      for (final h in _hospitals) {
        final isVerified = h['abdm_verified'] == 1;
        markers.add(
          Marker(
            point: LatLng(h['latitude'], h['longitude']),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFacility = h;
                  _selectedType = 'hospital';
                });
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFF3B30),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.local_hospital_rounded,
                      color: Color(0xFFFF3B30),
                      size: 16,
                    ),
                  ),
                  if (isVerified)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFF34C759),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified,
                          color: Colors.white,
                          size: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }
    }

    // Police Stations
    if (_showPolice) {
      for (final p in _policeStations) {
        markers.add(
          Marker(
            point: LatLng(p['latitude'], p['longitude']),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFacility = p;
                  _selectedType = 'police';
                });
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.blue,
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.local_police,
                  color: Colors.blue,
                  size: 16,
                ),
              ),
            ),
          ),
        );
      }
    }

    return Container(
      height: 320,
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
          // Flutter Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(widget.initialLat, widget.initialLng),
              initialZoom: 14.0,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && position.center != null) {
                  // Real-time bounding box fetching
                  _fetchFacilities(
                    position.center!.latitude,
                    position.center!.longitude,
                  );
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.roadsos',
              ),
              MarkerLayer(markers: markers),
            ],
          ),

          // Filters / Control bar at top
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Real-time loader indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.only(right: 6.0),
                          child: SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      Text(
                        _isLoading ? "Updating bounds..." : "Live Map Active",
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Map toggle chips
                Row(
                  children: [
                    _buildFilterChip(
                      icon: Icons.local_hospital_rounded,
                      isActive: _showHospitals,
                      color: const Color(0xFFFF3B30),
                      onTap: () {
                        setState(() {
                          _showHospitals = !_showHospitals;
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChip(
                      icon: Icons.local_police,
                      isActive: _showPolice,
                      color: Colors.blue,
                      onTap: () {
                        setState(() {
                          _showPolice = !_showPolice;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Slide-Up Glassmorphic Facility Detail Sheet
          if (_selectedFacility != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111122).withOpacity(0.95),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                _selectedType == 'hospital'
                                    ? Icons.local_hospital_rounded
                                    : Icons.local_police,
                                color: _selectedType == 'hospital'
                                    ? const Color(0xFFFF3B30)
                                    : Colors.blue,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedFacility!['name'],
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedFacility = null;
                            });
                          },
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white54,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_selectedType == 'hospital' &&
                        _selectedFacility!['abdm_verified'] == 1) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.verified,
                            color: Color(0xFF34C759),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            "ABDM Verified Trauma Center",
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF34C759),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "ID: ${_selectedFacility!['abdm_facility_id']}",
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white30,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      _selectedFacility!['address'] != ''
                          ? _selectedFacility!['address']
                          : 'No location address listed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_selectedFacility!['phone'] != '')
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // Call phone
                              },
                              icon: const Icon(Icons.call, size: 14),
                              label: Text(
                                "Call (${_selectedFacility!['phone']})",
                                style: const TextStyle(fontSize: 11),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF3B30).withOpacity(0.15),
                                foregroundColor: const Color(0xFFFF3B30),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        if (_selectedFacility!['phone'] != '') const SizedBox(width: 10),
                        if (_selectedType == 'hospital' && widget.onHospitalSelected != null)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                widget.onHospitalSelected!(_selectedFacility!);
                                setState(() {
                                  _selectedFacility = null;
                                });
                              },
                              icon: const Icon(Icons.emergency_share, size: 14),
                              label: const Text(
                                "DISPATCH TO HERE",
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF34C759),
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
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

  Widget _buildFilterChip({
    required IconData icon,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.25) : Colors.black87.withOpacity(0.75),
          border: Border.all(
            color: isActive ? color : Colors.white12,
            width: 1,
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? color : Colors.white60,
          size: 16,
        ),
      ),
    );
  }
}
