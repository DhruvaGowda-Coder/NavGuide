import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../domain/route_safety_models.dart';
import '../dead_reckoning/dead_reckoning_engine.dart';

class FloodSpotRecord {
  const FloodSpotRecord({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.bufferRadiusMeters,
    required this.vulnerabilityLevel,
    required this.historicalDepthCm,
    required this.corridor,
    required this.terrain,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double bufferRadiusMeters;
  final String vulnerabilityLevel;
  final int historicalDepthCm;
  final String corridor;
  final String terrain;

  factory FloodSpotRecord.fromJson(Map<String, dynamic> json) {
    return FloodSpotRecord(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      bufferRadiusMeters: (json['buffer_radius_meters'] as num?)?.toDouble() ?? 250.0,
      vulnerabilityLevel: json['vulnerability_level'] as String? ?? 'MODERATE',
      historicalDepthCm: json['historical_waterlog_depth_cm'] as int? ?? 30,
      corridor: json['corridor'] as String? ?? '',
      terrain: json['terrain'] as String? ?? '',
    );
  }
}

/// Provider for Karnataka / BBMP flood vulnerability data and topographic elevation.
class FloodDataProvider {
  FloodDataProvider({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  List<FloodSpotRecord> _floodSpots = [];
  bool _isLoaded = false;

  /// Loads official BBMP & KSNDMC flood blackspots asset.
  Future<void> initialize({String? jsonString}) async {
    if (_isLoaded) return;
    try {
      final content = jsonString ??
          await rootBundle.loadString('assets/data/bangalore_flood_spots.json');
      final data = jsonDecode(content) as Map<String, dynamic>;
      final list = data['flood_spots'] as List<dynamic>? ?? [];
      _floodSpots = list
          .map((e) => FloodSpotRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      _isLoaded = true;
    } catch (_) {
      _floodSpots = [];
    }
  }

  final Map<String, double?> _elevationCache = {};

  /// Evaluates flood risk for given coordinates.
  Future<FloodRiskInfo> evaluateLocation({
    required double latitude,
    required double longitude,
    double? activeRainfallMm,
    double? elevation,
  }) async {
    if (!_isLoaded) {
      await initialize();
    }

    FloodSpotRecord? matchedSpot;
    var minDistance = double.infinity;

    for (final spot in _floodSpots) {
      final dist = GeodesyUtils.haversineDistanceMeters(
        latitude,
        longitude,
        spot.latitude,
        spot.longitude,
      );
      if (dist <= spot.bufferRadiusMeters && dist < minDistance) {
        minDistance = dist;
        matchedSpot = spot;
      }
    }

    // Fast in-memory resolution from cache or precomputed corridor elevation
    final key = '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}';
    final resolvedElevation = elevation ?? _elevationCache[key];

    if (matchedSpot != null) {
      final isIntenseRain = (activeRainfallMm ?? 0.0) >= 5.0;
      return FloodRiskInfo(
        isHistoricalFloodProne: true,
        historicalSpotName: matchedSpot.name,
        elevationMeters: resolvedElevation,
        activeRainfallMm: activeRainfallMm,
        vulnerabilityRank: matchedSpot.vulnerabilityLevel,
        category: isIntenseRain
            ? FloodRiskCategory.observed
            : FloodRiskCategory.historical,
        source: 'BBMP/KSNDMC Registered Flood Spot (${minDistance.toInt()}m from core)',
      );
    }

    // If not a registered spot, but in high rain and low elevation
    return FloodRiskInfo(
      isHistoricalFloodProne: false,
      historicalSpotName: null,
      elevationMeters: resolvedElevation,
      activeRainfallMm: activeRainfallMm,
      vulnerabilityRank: 'NONE',
      category: FloodRiskCategory.modelDerived,
      source: 'Open-Meteo Terrain & BBMP Inundation Catalog',
    );
  }

  /// Fetches and caches topographic elevation for given coordinates.
  Future<double?> fetchElevation(double lat, double lon) async {
    final key = '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
    if (_elevationCache.containsKey(key)) {
      return _elevationCache[key];
    }
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/elevation?latitude=${lat.toStringAsFixed(4)}&longitude=${lon.toStringAsFixed(4)}',
      );
      final request =
          await _client.getUrl(uri).timeout(const Duration(milliseconds: 2000));
      final response =
          await request.close().timeout(const Duration(milliseconds: 2000));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final elevList = json['elevation'] as List<dynamic>?;
        if (elevList != null && elevList.isNotEmpty) {
          final val = (elevList.first as num?)?.toDouble();
          _elevationCache[key] = val;
          return val;
        }
      }
    } catch (_) {}
    _elevationCache[key] = null;
    return null;
  }

  void dispose() {
    _client.close(force: true);
  }
}
