import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Local SQLite database helper for caching emergency contacts,
/// hospitals, police stations, and towing services for offline access.
class DbHelper {
  static final DbHelper instance = DbHelper._internal();
  static Database? _database;

  DbHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'roadsos_emergency.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Emergency contacts table
    await db.execute('''
      CREATE TABLE emergency_contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        relationship TEXT,
        blood_type TEXT,
        allergies TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Cached hospitals from Overpass/ABDM queries
    await db.execute('''
      CREATE TABLE hospitals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        osm_id TEXT UNIQUE,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        phone TEXT,
        emergency_phone TEXT,
        trauma_level INTEGER,
        abdm_verified INTEGER DEFAULT 0,
        abdm_facility_id TEXT,
        operational_status TEXT,
        address TEXT,
        last_updated TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Cached police stations
    await db.execute('''
      CREATE TABLE police_stations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        osm_id TEXT UNIQUE,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        phone TEXT,
        address TEXT,
        last_updated TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Towing services
    await db.execute('''
      CREATE TABLE towing_services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        coverage_radius_km REAL,
        is_24x7 INTEGER DEFAULT 0,
        last_updated TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // User medical profile for SOS payloads
    await db.execute('''
      CREATE TABLE user_profile (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        full_name TEXT,
        blood_type TEXT,
        allergies TEXT,
        medical_conditions TEXT,
        insurance_id TEXT,
        emergency_message TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  // ---------------------------------------------------------------
  // Emergency Contacts CRUD
  // ---------------------------------------------------------------

  Future<int> insertEmergencyContact(Map<String, dynamic> contact) async {
    final db = await database;
    return await db.insert('emergency_contacts', contact);
  }

  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    final db = await database;
    return await db.query('emergency_contacts', orderBy: 'name ASC');
  }

  Future<int> deleteEmergencyContact(int id) async {
    final db = await database;
    return await db.delete('emergency_contacts', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------
  // Hospitals CRUD
  // ---------------------------------------------------------------

  Future<int> upsertHospital(Map<String, dynamic> hospital) async {
    final db = await database;
    return await db.insert(
      'hospitals',
      hospital,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getHospitals() async {
    final db = await database;
    return await db.query('hospitals', orderBy: 'name ASC');
  }

  /// Finds nearby hospitals within a bounding box.
  Future<List<Map<String, dynamic>>> getNearbyHospitals({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
  }) async {
    final db = await database;
    return await db.query(
      'hospitals',
      where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
      whereArgs: [minLat, maxLat, minLon, maxLon],
    );
  }

  /// Retrieves only ABDM-verified trauma centers.
  Future<List<Map<String, dynamic>>> getVerifiedTraumaCenters() async {
    final db = await database;
    return await db.query(
      'hospitals',
      where: 'abdm_verified = 1 AND trauma_level IS NOT NULL',
      orderBy: 'trauma_level ASC',
    );
  }

  // ---------------------------------------------------------------
  // Police Stations CRUD
  // ---------------------------------------------------------------

  Future<int> upsertPoliceStation(Map<String, dynamic> station) async {
    final db = await database;
    return await db.insert(
      'police_stations',
      station,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPoliceStations() async {
    final db = await database;
    return await db.query('police_stations', orderBy: 'name ASC');
  }

  // ---------------------------------------------------------------
  // Towing Services CRUD
  // ---------------------------------------------------------------

  Future<int> insertTowingService(Map<String, dynamic> service) async {
    final db = await database;
    return await db.insert('towing_services', service);
  }

  Future<List<Map<String, dynamic>>> getTowingServices() async {
    final db = await database;
    return await db.query('towing_services', orderBy: 'name ASC');
  }

  // ---------------------------------------------------------------
  // User Medical Profile
  // ---------------------------------------------------------------

  Future<int> upsertUserProfile(Map<String, dynamic> profile) async {
    final db = await database;
    // Always maintain a single profile row
    final existing = await db.query('user_profile');
    if (existing.isNotEmpty) {
      return await db.update('user_profile', profile, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
    return await db.insert('user_profile', profile);
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    final db = await database;
    final results = await db.query('user_profile', limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  // ---------------------------------------------------------------
  // Bulk cache sync (called after API fetch)
  // ---------------------------------------------------------------

  /// Bulk insert hospitals from an Overpass/ABDM API response.
  Future<void> bulkCacheHospitals(List<Map<String, dynamic>> hospitals) async {
    final db = await database;
    final batch = db.batch();
    for (final h in hospitals) {
      batch.insert('hospitals', h, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Bulk insert police stations from an Overpass API response.
  Future<void> bulkCachePoliceStations(List<Map<String, dynamic>> stations) async {
    final db = await database;
    final batch = db.batch();
    for (final s in stations) {
      batch.insert('police_stations', s, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Close the database connection.
  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }
}
