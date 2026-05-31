import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages offline Mapbox vector tile region downloads.
/// Enforces a hard limit of 750 unique tile packs to comply with
/// Mapbox Terms of Service API restrictions.
class OfflineMapsManager {
  static const int maxTilePacks = 750;
  static const String _prefsKey = 'offline_tile_regions';

  List<OfflineTileRegion> _downloadedRegions = [];

  /// Loads previously downloaded region metadata from local storage.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final regionStrings = prefs.getStringList(_prefsKey) ?? [];
    _downloadedRegions = regionStrings
        .map((s) => OfflineTileRegion.deserialize(s))
        .toList();
    debugPrint(
      "OfflineMapsManager initialized: ${_downloadedRegions.length}/$maxTilePacks regions cached.",
    );
  }

  /// Returns the current count of downloaded tile packs.
  int get downloadedCount => _downloadedRegions.length;

  /// Returns the remaining download budget.
  int get remainingBudget => maxTilePacks - _downloadedRegions.length;

  /// Returns true if a new tile pack can be downloaded.
  bool get canDownloadMore => _downloadedRegions.length < maxTilePacks;

  /// Returns all downloaded regions.
  List<OfflineTileRegion> get regions => List.unmodifiable(_downloadedRegions);

  /// Checks whether a region covering the given bounding box already exists.
  bool hasRegion(double minLat, double minLon, double maxLat, double maxLon) {
    return _downloadedRegions.any((r) =>
        r.minLat == minLat &&
        r.minLon == minLon &&
        r.maxLat == maxLat &&
        r.maxLon == maxLon);
  }

  /// Requests a new offline tile region download.
  ///
  /// Returns `true` if the download was accepted and queued.
  /// Returns `false` if the 750 pack limit has been reached or the region
  /// already exists.
  ///
  /// In a production build, this method would call the Mapbox
  /// `OfflineManager.createTileRegion()` API. Here, we enforce the
  /// compliance logic and persist the metadata.
  Future<bool> downloadRegion({
    required String regionName,
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    int minZoom = 10,
    int maxZoom = 16,
  }) async {
    // Guard: check limit compliance
    if (!canDownloadMore) {
      debugPrint(
        "⚠️ DOWNLOAD BLOCKED: Maximum of $maxTilePacks offline tile packs reached.",
      );
      return false;
    }

    // Guard: check for duplicate
    if (hasRegion(minLat, minLon, maxLat, maxLon)) {
      debugPrint("Region '$regionName' already cached — skipping download.");
      return false;
    }

    final region = OfflineTileRegion(
      name: regionName,
      minLat: minLat,
      minLon: minLon,
      maxLat: maxLat,
      maxLon: maxLon,
      minZoom: minZoom,
      maxZoom: maxZoom,
      downloadedAt: DateTime.now(),
    );

    // ------------------------------------------------------------------
    // PRODUCTION HOOK: Call Mapbox OfflineManager here.
    //
    // Example (pseudo-code):
    //   final tileRegionLoadOptions = TileRegionLoadOptions(
    //     geometry: Point(coordinates: Position(lon, lat)).toJson(),
    //     descriptorsOptions: [
    //       TilesetDescriptorOptions(
    //         styleURI: MapboxStyles.MAPBOX_STREETS,
    //         minZoom: minZoom,
    //         maxZoom: maxZoom,
    //       ),
    //     ],
    //   );
    //   await mapboxMap.offlineManager
    //       .loadTileRegion(regionName, tileRegionLoadOptions);
    // ------------------------------------------------------------------

    _downloadedRegions.add(region);
    await _persist();

    debugPrint(
      "✅ Region '$regionName' downloaded. "
      "${_downloadedRegions.length}/$maxTilePacks used.",
    );
    return true;
  }

  /// Removes a previously downloaded tile region.
  Future<bool> removeRegion(String regionName) async {
    final idx = _downloadedRegions.indexWhere((r) => r.name == regionName);
    if (idx == -1) return false;

    _downloadedRegions.removeAt(idx);
    await _persist();

    debugPrint(
      "Region '$regionName' removed. "
      "${_downloadedRegions.length}/$maxTilePacks used.",
    );
    return true;
  }

  /// Persists region metadata to SharedPreferences.
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = _downloadedRegions.map((r) => r.serialize()).toList();
    await prefs.setStringList(_prefsKey, serialized);
  }
}

/// Lightweight model representing a single offline tile region.
class OfflineTileRegion {
  final String name;
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;
  final int minZoom;
  final int maxZoom;
  final DateTime downloadedAt;

  OfflineTileRegion({
    required this.name,
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
    required this.minZoom,
    required this.maxZoom,
    required this.downloadedAt,
  });

  /// Serializes to a pipe-delimited string for SharedPreferences storage.
  String serialize() {
    return '$name|$minLat|$minLon|$maxLat|$maxLon|$minZoom|$maxZoom|${downloadedAt.toIso8601String()}';
  }

  /// Deserializes from a pipe-delimited string.
  factory OfflineTileRegion.deserialize(String data) {
    final parts = data.split('|');
    return OfflineTileRegion(
      name: parts[0],
      minLat: double.parse(parts[1]),
      minLon: double.parse(parts[2]),
      maxLat: double.parse(parts[3]),
      maxLon: double.parse(parts[4]),
      minZoom: int.parse(parts[5]),
      maxZoom: int.parse(parts[6]),
      downloadedAt: DateTime.parse(parts[7]),
    );
  }

  @override
  String toString() =>
      'OfflineTileRegion($name, [$minLat,$minLon]-[$maxLat,$maxLon], z$minZoom-$maxZoom)';
}
