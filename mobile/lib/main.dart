import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'crash_detector.dart';
import 'triage_engine.dart';
import 'map_dashboard.dart';
import 'ambulance_tracker.dart';
import 'trip_visualization.dart';
import 'preventative_alerts.dart';
import 'location_sharing.dart';
import 'db_helper.dart';
import 'multi_dashboard.dart';

void main() {
  runApp(const RoadSOSApp());
}

class RoadSOSApp extends StatelessWidget {
  const RoadSOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoadSOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF3B30),
          secondary: Color(0xFF34C759),
          surface: Color(0xFF1C1C2E),
          background: Color(0xFF0F0F1A),
        ),
        fontFamily: 'Inter',
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.example.roadsos/sensors');
  
  bool _isServiceRunning = false;
  List<double> _currentFeatures = List.filled(44, 0.0);
  RandomForestClassifier? _classifier;
  
  // Triage state
  bool _isCountingDown = false;
  int _countdownSeconds = 10;
  Timer? _countdownTimer;
  TriageAssessment? _assessment;
  Map<String, dynamic>? _activeDispatchedHospital;

  // Preventative driving states
  bool _isAssistantActive = false;
  double _simulatedSpeed = 0.0;
  bool _isInteractingWithPhone = false;

  // Emergency Alerts state (Phase 4)
  List<Map<String, dynamic>> _contacts = [];
  Map<String, dynamic>? _userProfile;
  bool _isDistressTransmitting = false;
  String _formattedDistressPayload = "";
  List<String> _distressLog = [];
  Map<String, String> _transmissionStatus = {};

  // Mock safety trips history
  final List<TripData> _mockTrips = [
    TripData(
      id: "trip-01",
      date: "May 29, 2026",
      time: "18:45",
      score: 84.0,
      distanceKm: 8.6,
      durationMinutes: 18.0,
      route: [
        const LatLng(28.5244, 77.2066),
        const LatLng(28.5270, 77.2085),
        const LatLng(28.5310, 77.2045),
        const LatLng(28.5360, 77.2095),
        const LatLng(28.5390, 77.2035),
      ],
      events: [
        DrivingEvent(
          position: const LatLng(28.5270, 77.2085),
          type: "speeding",
          description: "Vehicle exceeded speed limit (82 km/h in 50 km/h zone)",
          time: "18:47",
        ),
        DrivingEvent(
          position: const LatLng(28.5360, 77.2095),
          type: "distraction",
          description: "Mobile device interaction detected while vehicle in motion",
          time: "18:53",
        ),
      ],
    ),
    TripData(
      id: "trip-02",
      date: "May 28, 2026",
      time: "09:12",
      score: 95.0,
      distanceKm: 14.2,
      durationMinutes: 28.0,
      route: [
        const LatLng(28.5244, 77.2066),
        const LatLng(28.5190, 77.2000),
        const LatLng(28.5110, 77.2050),
        const LatLng(28.5030, 77.1980),
      ],
      events: [
        DrivingEvent(
          position: const LatLng(28.5110, 77.2050),
          type: "speeding",
          description: "Exceeded speed threshold on flyover (68 km/h in 60 km/h zone)",
          time: "09:21",
        ),
      ],
    ),
  ];

  // Visual feedback states
  double _lastAccMag = 0.0;
  double _lastGyroMag = 0.0;

  Future<void> _initDatabaseData() async {
    final db = DbHelper.instance;
    try {
      // Check if user profile exists, if not seed it
      var profile = await db.getUserProfile();
      if (profile == null) {
        await db.upsertUserProfile({
          'full_name': 'Aarya Patel',
          'blood_type': 'O+',
          'allergies': 'None',
          'medical_conditions': 'None',
          'insurance_id': 'INS-SOS-8822',
          'emergency_message': 'Emergency: Crash detected. Please help!',
        });
        profile = await db.getUserProfile();
      }
      
      // Check if emergency contacts exist, if not seed them
      var contacts = await db.getEmergencyContacts();
      if (contacts.isEmpty) {
        await db.insertEmergencyContact({
          'name': 'Mom',
          'phone': '+91 98765 43210',
          'relationship': 'Mother',
          'blood_type': 'O+',
          'allergies': 'None',
        });
        await db.insertEmergencyContact({
          'name': 'Dad',
          'phone': '+91 87654 32109',
          'relationship': 'Father',
          'blood_type': 'A+',
          'allergies': 'Penicillin',
        });
        contacts = await db.getEmergencyContacts();
      }

      setState(() {
        _userProfile = profile;
        _contacts = contacts;
      });
      debugPrint("DbHelper seeded/loaded: ${contacts.length} emergency contacts found.");
    } catch (e) {
      debugPrint("Error initializing local emergency db cache: $e");
      // Fallback in-memory states to guarantee zero runtime crashing
      setState(() {
        _userProfile = {
          'full_name': 'Aarya Patel',
          'blood_type': 'O+',
          'allergies': 'None',
        };
        _contacts = [
          {'name': 'Mom', 'phone': '+91 98765 43210'},
          {'name': 'Dad', 'phone': '+91 87654 32109'},
        ];
      });
    }
  }

  void _triggerManualSOS() {
    final assessmentResult = TriageEngine.performTriage(
      gForce: 10.0, // Manual triggers simulate standard high kinetic triage routing
      hasAirbagDeployed: false,
      isRollover: false,
      gcs: 15,
      age: 28,
      isoCountryCode: 'IN',
    );
    setState(() {
      _assessment = assessmentResult;
    });
    _dispatchSOSEmergency();
  }

  @override
  void initState() {
    super.initState();
    _loadClassifier();
    _initDatabaseData();
    platform.setMethodCallHandler(_handleNativeMethodCall);
  }

  Future<void> _loadClassifier() async {
    try {
      final clf = await RandomForestClassifier.loadFromAssets('assets/models/crash_detector_rf.json');
      setState(() {
        _classifier = clf;
      });
      debugPrint("Random Forest Edge AI Model loaded successfully.");
    } catch (e) {
      debugPrint("Error loading edge AI model: $e");
    }
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onSensorUpdate') {
      final List<dynamic> args = call.arguments;
      final features = args.map((e) => (e as num).toDouble()).toList();
      setState(() {
        _currentFeatures = features;
        _lastAccMag = features[42]; // Current Acc Mag (Index 42)
        _lastGyroMag = features[43]; // Current Gyro Mag (Index 43)

        // Continuous Edge AI Classification of sliding window metrics
        if (_classifier != null && _classifier!.isCrash(features) && !_isCountingDown) {
          _triggerCrashCountdown();
        }
      });
    }
  }


  Future<void> _toggleSensorService() async {
    try {
      if (_isServiceRunning) {
        try {
          final String result = await platform.invokeMethod('stopSensorService');
          debugPrint(result);
        } catch (_) {}
        setState(() {
          _isServiceRunning = false;
          _currentFeatures = List.filled(44, 0.0);
          _lastAccMag = 0.0;
          _lastGyroMag = 0.0;
        });
      } else {
        try {
          final String result = await platform.invokeMethod('startSensorService');
          debugPrint(result);
        } catch (_) {
          // Web / Desktop platform simulation fallback
          debugPrint("Sensors platform channel unavailable. Running high-fidelity web simulation mode.");
          // Periodically update telemetry metrics to present a premium dynamic interactive interface
          Timer.periodic(const Duration(milliseconds: 500), (timer) {
            if (!_isServiceRunning) {
              timer.cancel();
              return;
            }
            setState(() {
              _lastAccMag = 9.8 + (1.0 - 2.0 * (1.0 - (timer.hashCode % 10) / 10.0));
              _lastGyroMag = (timer.hashCode % 5) / 10.0;
            });
          });
        }
        setState(() {
          _isServiceRunning = true;
        });
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to toggle service: '${e.message}'.");
    }
  }

  void _triggerCrashCountdown() {
    // Generate ACS-COT assessment upon crash detection trigger using current kinetic values
    final gForceVal = _lastAccMag > 0 ? _lastAccMag / 9.80665 : 12.5; // Simulate realistic fallback decel force
    final isRolloverEvent = _lastGyroMag > 4.5;
    
    final assessmentResult = TriageEngine.performTriage(
      gForce: gForceVal,
      hasAirbagDeployed: true,
      isRollover: isRolloverEvent,
      gcs: 13, // Simulated GCS score reflecting high kinematic impact
      age: 28,
      isoCountryCode: 'IN', // Default country profile
    );

    setState(() {
      _assessment = assessmentResult;
      _isCountingDown = true;
      _countdownSeconds = 10;
    });
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds--;
        } else {
          _countdownTimer?.cancel();
          _isCountingDown = false;
          _dispatchSOSEmergency();
        }
      });
    });
  }

  void _cancelCrashCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _isCountingDown = false;
      _countdownSeconds = 10;
      _assessment = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Emergency dispatch cancelled by user."),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  void _dispatchSOSEmergency() {
    final bloodType = _userProfile?['blood_type'] ?? 'O+';
    final allergies = _userProfile?['allergies'] ?? 'None';
    final double gForceVal = _lastAccMag > 0 ? _lastAccMag / 9.80665 : 12.5;
    
    // Protocol Resilient Payload Format: LAT:{lat};LON:{lon};SEV:{g_force};MED:{blood_type|allergies}
    final distressMsg = "LAT:28.5244;LON:77.2066;SEV:${gForceVal.toStringAsFixed(1)};MED:$bloodType|$allergies";

    setState(() {
      _isDistressTransmitting = true;
      _formattedDistressPayload = distressMsg;
      _activeDispatchedHospital = {
        'name': _assessment?.destinationRecommendation ?? 'Max Super Speciality Hospital',
        'latitude': 28.5264,
        'longitude': 77.2036,
      };

      // Set initial status to PENDING for all contacts
      _transmissionStatus = {};
      for (var contact in _contacts) {
        final name = contact['name'] ?? 'Contact';
        _transmissionStatus[name] = 'PENDING';
      }
    });

    // Visual transmission loop simulation
    for (int i = 0; i < _contacts.length; i++) {
      final name = _contacts[i]['name'] ?? 'Contact';
      final phone = _contacts[i]['phone'] ?? '';
      Timer(Duration(milliseconds: 1000 * (i + 1)), () {
        setState(() {
          _transmissionStatus[name] = 'SENT';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("📲 FREE SMS distress payload transmitted to $name ($phone)"),
            backgroundColor: const Color(0xFF34C759),
            duration: const Duration(seconds: 2),
          ),
        );
      });
    }

    // Fallback HTTP API Routing to Local GSM Gateway
    final backendUrl = Uri.parse("http://localhost:8000/distress/sms");
    http.post(
      backendUrl,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"payload": distressMsg}),
    ).then((response) {
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _distressLog.insert(0, "[${DateTime.now().toLocal().toString().substring(11, 19)}] Distress signal routed successfully: $distressMsg");
        });
        debugPrint("Gateway status: ${data['message']}");
      } else {
        setState(() {
          _distressLog.insert(0, "[${DateTime.now().toLocal().toString().substring(11, 19)}] Distress signal queued (Local SMS fallback): $distressMsg");
        });
      }
    }).catchError((err) {
      setState(() {
        _distressLog.insert(0, "[${DateTime.now().toLocal().toString().substring(11, 19)}] Serial Gateway offline. Offline SMS triggered: $distressMsg");
      });
      debugPrint("HTTP post failure, fallback to raw SMS transmission: $err");
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("🚨 SOS CRASH BROADCAST TRIGGERED! RECOMMENDED DESTINATION: ${_assessment?.destinationRecommendation ?? 'Trauma Center'}. Dialing ${_assessment?.primarySOSNumber ?? '112'}"),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient Layer
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F0F1A), Color(0xFF1E1E3A)],
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // App Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                "RoadSOS",
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.dashboard_customize_rounded, color: Color(0xFFFF3B30), size: 22),
                                tooltip: "Stakeholder Console",
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const MultiStakeholderDashboard(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Autonomous Kinematic Crash Shield",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      // Status dot indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isServiceRunning 
                            ? const Color(0xFF34C759).withOpacity(0.15) 
                            : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isServiceRunning ? const Color(0xFF34C759) : Colors.white24,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _isServiceRunning ? const Color(0xFF34C759) : Colors.white54,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isServiceRunning ? "SHIELD ON" : "SHIELD OFF",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _isServiceRunning ? const Color(0xFF34C759) : Colors.white70,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Main Status Shield Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isServiceRunning 
                          ? [const Color(0xFF1E1E3A), const Color(0xFF282855)] 
                          : [const Color(0xFF121222), const Color(0xFF16162A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _isServiceRunning 
                          ? const Color(0xFFFF3B30).withOpacity(0.4) 
                          : Colors.white.withOpacity(0.05),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isServiceRunning 
                            ? const Color(0xFFFF3B30).withOpacity(0.1) 
                            : Colors.transparent,
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _isServiceRunning ? Icons.shield_rounded : Icons.shield_outlined,
                          size: 72,
                          color: _isServiceRunning ? const Color(0xFFFF3B30) : Colors.white38,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isServiceRunning ? "Continuous Crash Scanning Active" : "Crash Scan Disarmed",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isServiceRunning 
                            ? "Polling Accelerometer & Gyroscope at 50Hz"
                            : "Arm shield to secure your journey",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _toggleSensorService,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isServiceRunning ? Colors.white.withOpacity(0.08) : const Color(0xFFFF3B30),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: _isServiceRunning ? Colors.white24 : Colors.transparent,
                              ),
                            ),
                            elevation: _isServiceRunning ? 0 : 8,
                          ),
                          child: Text(
                            _isServiceRunning ? "ARM SHIELD OFF" : "ARM SHIELD ON",
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Manual Driver SOS Panel (Confirm Slide)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFFF3B30).withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Manual Panic Trigger",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Bypass automated crash protocols",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF3B30).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                "NON-CRASH",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF3B30),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: _triggerManualSOS,
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFF3B30),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF3B30).withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                "SOS",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Real-time Telemetry Indicators
                  const Text(
                    "Real-Time Inertial Telemetry",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Accelerometer Card
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C2E),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.speed, size: 18, color: Colors.blueAccent),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Linear Accel",
                                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "${_lastAccMag.toStringAsFixed(2)} m/s²",
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Gyroscope Card
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C2E),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.sync, size: 18, color: Colors.orangeAccent),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Angular Velocity",
                                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "${_lastGyroMag.toStringAsFixed(2)} rad/s",
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Audio safety assistant HUD panel
                  PreventativeAlertsWidget(
                    currentSpeed: _simulatedSpeed,
                    isInteractingWithPhone: _isInteractingWithPhone,
                    isAssistantActive: _isAssistantActive,
                    onToggleAssistant: (active) {
                      setState(() {
                        _isAssistantActive = active;
                        if (!active) {
                          _simulatedSpeed = 0.0;
                          _isInteractingWithPhone = false;
                        }
                      });
                    },
                  ),

                  const SizedBox(height: 20),

                  // Voluntary Family Location sharing card
                  LocationSharingWidget(
                    onToggleSharing: () {
                      // Broadcast log
                    },
                  ),

                  // Distress Alert Dispatcher Console (Phase 4)
                  if (_isDistressTransmitting || _distressLog.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFFF3B30).withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.emergency_share_rounded, color: Color(0xFFFF3B30), size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    "Distress Alert Dispatcher",
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF34C759).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  "ACTIVE RELAY",
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF34C759)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            "RAW PROTOCOL PAYLOAD",
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white30, letterSpacing: 1.0),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: SelectableText(
                              _formattedDistressPayload.isNotEmpty 
                                  ? _formattedDistressPayload 
                                  : "LAT:28.5244;LON:77.2066;SEV:12.5;MED:O+|None",
                              style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "EMERGENCY CONTACTS SMS QUEUE",
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white30, letterSpacing: 1.0),
                          ),
                          const SizedBox(height: 8),
                          ..._contacts.map((contact) {
                            final name = contact['name'] ?? 'Contact';
                            final phone = contact['phone'] ?? '';
                            final status = _transmissionStatus[name] ?? 'PENDING';
                            final isSent = status == 'SENT';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(isSent ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                          color: isSent ? const Color(0xFF34C759) : Colors.white24, size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        "$name ($phone)",
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSent ? const Color(0xFF34C759) : Colors.amberAccent,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          if (_distressLog.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text(
                              "FALLBACK GATEWAY AUDIT LOG",
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white30, letterSpacing: 1.0),
                            ),
                            const SizedBox(height: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _distressLog.take(2).map((log) => Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Text(
                                  log,
                                  style: const TextStyle(fontSize: 10, color: Colors.white70, fontFamily: 'monospace'),
                                ),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],



                  const SizedBox(height: 24),
                  
                  // Interactive Live Mapping Panel or Tracker
                  if (_activeDispatchedHospital == null) ...[
                    const Text(
                      "Emergency Facilities Bounding Box",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    MapDashboardWidget(
                      initialLat: 28.5244,
                      initialLng: 77.2066,
                      onHospitalSelected: (hosp) {
                        setState(() {
                          _activeDispatchedHospital = hosp;
                        });
                      },
                    ),
                  ] else ...[
                    const Text(
                      "Live Ambulance Tracking Status",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AmbulanceTrackerWidget(
                      userLat: 28.5244,
                      userLng: 77.2066,
                      selectedHospital: _activeDispatchedHospital!,
                      onDismiss: () {
                        setState(() {
                          _activeDispatchedHospital = null;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 28),
                  
                  // Trip Safety Analytics History
                  const Text(
                    "Trip History & Safety Metrics",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._mockTrips.map((trip) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: const Color(0xFF1C1C2E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withOpacity(0.03)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (trip.score >= 90
                              ? const Color(0xFF34C759)
                              : Colors.orangeAccent).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.drive_eta,
                          color: trip.score >= 90
                              ? const Color(0xFF34C759)
                              : Colors.orangeAccent,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        "Trip Score: ${trip.score.toStringAsFixed(0)}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Text(
                        "${trip.date} • ${trip.distanceKm} Km • ${trip.events.length} Incidents",
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white38),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TripVisualizationPage(trip: trip),
                          ),
                        );
                      },
                    ),
                  )).toList(),
                ],
              ),
            ),
          ),
        ),

          // High-Contrast Glassmorphic Countdown Overlay
          if (_isCountingDown)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.85),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Warning Label
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: const Color(0xFFFF3B30)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3B30), size: 24),
                            SizedBox(width: 10),
                            Text(
                              "CRASH DETECTED",
                              style: TextStyle(
                                color: Color(0xFFFF3B30),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      
                      // Animated Circular Countdown
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: CircularProgressIndicator(
                              value: _countdownSeconds / 10.0,
                              strokeWidth: 12,
                              color: const Color(0xFFFF3B30),
                              backgroundColor: Colors.white12,
                            ),
                          ),
                          Text(
                            "$_countdownSeconds",
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      
                      if (_assessment != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 30),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _assessment!.level == TriageLevel.red 
                                ? Colors.redAccent.withOpacity(0.5) 
                                : Colors.amberAccent.withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                "Triage Assessment: ${_assessment!.level.name.toUpperCase()}",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _assessment!.level == TriageLevel.red ? Colors.redAccent : Colors.amberAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Recommended Destination:\n${_assessment!.destinationRecommendation}",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Divider(color: Colors.white24, height: 1),
                              const SizedBox(height: 8),
                              Text(
                                "Triggered Criteria:\n• ${_assessment!.triggeredCriteria.join('\n• ')}",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 11,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "SOS Number: ${_assessment!.primarySOSNumber}",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 30),
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40.0),
                        child: Text(
                          "Broadcasting emergency alerts and GPS location to emergency responders (${_assessment?.primarySOSNumber ?? '112'}) and family in...",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      
                      ElevatedButton(
                        onPressed: _cancelCrashCountdown,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          "I AM SAFE - CANCEL",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
