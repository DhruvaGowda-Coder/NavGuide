import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../railway/train_tracking_engine.dart';

/// Data class representing a connected mobile cell tower.
class CellTowerData {
  final String status;
  final String carrier;
  final String networkType;
  final int cellId;
  final int lac;
  final String mcc;
  final String mnc;
  final int dbm;
  final double? latitude;
  final double? longitude;
  final bool isPositionLocked;
  final DateTime timestamp;

  const CellTowerData({
    required this.status,
    required this.carrier,
    required this.networkType,
    required this.cellId,
    required this.lac,
    required this.mcc,
    required this.mnc,
    required this.dbm,
    this.latitude,
    this.longitude,
    this.isPositionLocked = false,
    required this.timestamp,
  });

  factory CellTowerData.initial() {
    return CellTowerData(
      status: 'INITIALIZING',
      carrier: 'Scanning SIM...',
      networkType: 'Cellular',
      cellId: 0,
      lac: 0,
      mcc: '',
      mnc: '',
      dbm: -999,
      timestamp: DateTime.now(),
    );
  }

  factory CellTowerData.fromMap(Map<dynamic, dynamic> map) {
    return CellTowerData(
      status: map['status'] as String? ?? 'UNKNOWN',
      carrier: map['carrier'] as String? ?? 'Mobile Network',
      networkType: map['networkType'] as String? ?? '4G LTE',
      cellId: (map['cellId'] as num?)?.toInt() ?? 0,
      lac: (map['lac'] as num?)?.toInt() ?? 0,
      mcc: map['mcc'] as String? ?? '',
      mnc: map['mnc'] as String? ?? '',
      dbm: (map['dbm'] as num?)?.toInt() ?? -999,
      timestamp: DateTime.now(),
    );
  }

  CellTowerData copyWith({
    String? status,
    String? carrier,
    String? networkType,
    int? cellId,
    int? lac,
    String? mcc,
    String? mnc,
    int? dbm,
    double? latitude,
    double? longitude,
    bool? isPositionLocked,
    DateTime? timestamp,
  }) {
    return CellTowerData(
      status: status ?? this.status,
      carrier: carrier ?? this.carrier,
      networkType: networkType ?? this.networkType,
      cellId: cellId ?? this.cellId,
      lac: lac ?? this.lac,
      mcc: mcc ?? this.mcc,
      mnc: mnc ?? this.mnc,
      dbm: dbm ?? this.dbm,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isPositionLocked: isPositionLocked ?? this.isPositionLocked,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  bool get hasTowerLock => cellId > 0;

  int get signalBars {
    if (dbm == -999) return 3;
    if (dbm >= -80) return 4;
    if (dbm >= -95) return 3;
    if (dbm >= -110) return 2;
    if (dbm >= -120) return 1;
    return 1;
  }

  String get formattedTowerId {
    if (cellId > 0) {
      final locText = isPositionLocked && latitude != null && longitude != null
          ? ' • GPS LOCKED'
          : '';
      return 'CID: $cellId${lac > 0 ? ' • LAC: $lac' : ''}$locText';
    }
    return 'Scanning Cell Tower...';
  }
}

/// Represents the calculated train position along its route derived from a cell tower.
class CellTowerTrainMatch {
  final int stationIndex;
  final double distanceToNextKm;
  final bool isAtStation;
  final String stationName;
  final String stationCode;
  final double matchConfidence;

  const CellTowerTrainMatch({
    required this.stationIndex,
    required this.distanceToNextKm,
    required this.isAtStation,
    required this.stationName,
    required this.stationCode,
    required this.matchConfidence,
  });
}

class CellTowerService {
  static const MethodChannel _channel = MethodChannel('com.navguardian.ai/telephony');

  /// OpenCellID Official API Token
  static const String openCellIdKey = 'pk.87408a976ddce5ffc844e3a56269487b';

  static final Map<String, Map<String, double>> _towerGeoCache = {};
  static bool _cacheLoaded = false;

  static Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/opencellid_tower_cache.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        json.forEach((k, v) {
          if (v is Map) {
            _towerGeoCache[k] = {
              'lat': (v['lat'] as num).toDouble(),
              'lon': (v['lon'] as num).toDouble(),
            };
          }
        });
      }
    } catch (_) {}
    _cacheLoaded = true;
  }

  static Future<void> _saveCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/opencellid_tower_cache.json');
      await file.writeAsString(jsonEncode(_towerGeoCache));
    } catch (_) {}
  }

  static Future<CellTowerData> fetchCurrentTower() async {
    await _loadCache();
    CellTowerData baseData;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCellTowerInfo');
      if (result != null) {
        baseData = CellTowerData.fromMap(result);
      } else {
        baseData = CellTowerData.initial();
      }
    } catch (_) {
      baseData = CellTowerData.initial();
    }

    if (!baseData.hasTowerLock) {
      return baseData;
    }

    final cacheKey = '${baseData.mcc}_${baseData.mnc}_${baseData.lac}_${baseData.cellId}';

    // 1. Check local offline cache first (0ms instant lookup)
    if (_towerGeoCache.containsKey(cacheKey)) {
      final coords = _towerGeoCache[cacheKey]!;
      return baseData.copyWith(
        latitude: coords['lat'],
        longitude: coords['lon'],
        isPositionLocked: true,
      );
    }

    // 2. Query OpenCellID API if connected (rapid timeout to ensure zero UI lag when offline)
    if (baseData.cellId > 0 && baseData.mcc.isNotEmpty && baseData.mnc.isNotEmpty) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1800);
        final lacParam = baseData.lac > 0 ? '&lac=${baseData.lac}' : '';
        final uri = Uri.parse(
          'https://opencellid.org/cell/get?key=$openCellIdKey&mcc=${baseData.mcc}&mnc=${baseData.mnc}$lacParam&cellid=${baseData.cellId}&format=json',
        );
        final req = await client.getUrl(uri);
        final res = await req.close().timeout(const Duration(milliseconds: 1800));
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          if (json.containsKey('lat') && json.containsKey('lon')) {
            final lat = (json['lat'] as num).toDouble();
            final lon = (json['lon'] as num).toDouble();
            _towerGeoCache[cacheKey] = {'lat': lat, 'lon': lon};
            _saveCache(); // Persist for 100% offline usage!

            return baseData.copyWith(
              latitude: lat,
              longitude: lon,
              isPositionLocked: true,
            );
          }
        }
      } catch (_) {
        // Offline or connection timeout — zero blocking
      }
    }

    return baseData;
  }

  /// Pre-caches known corridor station locations for fast offline proximity matching
  static void precacheRouteStations(TrainRoute route) {
    for (final halt in route.halts) {
      final stn = halt.station;
      if (stn.latitude != 0.0 && stn.longitude != 0.0) {
        final corridorKey = 'station_${stn.code.toUpperCase()}';
        _towerGeoCache[corridorKey] = {'lat': stn.latitude, 'lon': stn.longitude};
      }
    }
  }

  /// Calculates actual train location on its route using the connected cellular tower
  static CellTowerTrainMatch? calculatePositionOnRoute({
    required TrainRoute route,
    required double towerLat,
    required double towerLon,
  }) {
    final halts = route.halts;
    if (halts.isEmpty) return null;

    int closestHaltIdx = 0;
    double minStationDist = double.infinity;

    for (int i = 0; i < halts.length; i++) {
      final stn = halts[i].station;
      if (stn.latitude == 0.0 && stn.longitude == 0.0) continue;
      final d = haversineDistanceKm(towerLat, towerLon, stn.latitude, stn.longitude);
      if (d < minStationDist) {
        minStationDist = d;
        closestHaltIdx = i;
      }
    }

    // If within 3.5 km of a station, train is physically at or arriving at this station!
    if (minStationDist <= 3.5) {
      final nextIdx = (closestHaltIdx < halts.length - 1) ? closestHaltIdx + 1 : closestHaltIdx;
      final distToNext = (nextIdx > closestHaltIdx)
          ? (halts[nextIdx].distanceKm - halts[closestHaltIdx].distanceKm).abs()
          : 0.0;

      return CellTowerTrainMatch(
        stationIndex: closestHaltIdx,
        distanceToNextKm: distToNext,
        isAtStation: true,
        stationName: halts[closestHaltIdx].station.name,
        stationCode: halts[closestHaltIdx].station.code,
        matchConfidence: 0.98,
      );
    }

    // Otherwise, find which track segment (between halt i and halt i+1) the tower coordinates lie on
    for (int i = 0; i < halts.length - 1; i++) {
      final h1 = halts[i];
      final h2 = halts[i + 1];
      if ((h1.station.latitude == 0 && h1.station.longitude == 0) ||
          (h2.station.latitude == 0 && h2.station.longitude == 0)) continue;

      final d1 = haversineDistanceKm(towerLat, towerLon, h1.station.latitude, h1.station.longitude);
      final d2 = haversineDistanceKm(towerLat, towerLon, h2.station.latitude, h2.station.longitude);
      final segDirect = haversineDistanceKm(h1.station.latitude, h1.station.longitude, h2.station.latitude, h2.station.longitude);

      if (d1 + d2 <= segDirect * 1.35 + 8.0) {
        final totalRailDist = (h2.distanceKm - h1.distanceKm).abs();
        final ratio = (d1 / (d1 + d2)).clamp(0.05, 0.95);
        final remainingKm = totalRailDist * (1.0 - ratio);

        return CellTowerTrainMatch(
          stationIndex: i,
          distanceToNextKm: remainingKm > 0.1 ? remainingKm : 0.5,
          isAtStation: false,
          stationName: h2.station.name,
          stationCode: h2.station.code,
          matchConfidence: 0.90,
        );
      }
    }

    return CellTowerTrainMatch(
      stationIndex: closestHaltIdx,
      distanceToNextKm: 1.0,
      isAtStation: false,
      stationName: halts[closestHaltIdx].station.name,
      stationCode: halts[closestHaltIdx].station.code,
      matchConfidence: 0.75,
    );
  }

  static double haversineDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371.0;
    final dLat = (lat2 - lat1) * (pi / 180.0);
    final dLon = (lon2 - lon1) * (pi / 180.0);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180.0)) * cos(lat2 * (pi / 180.0)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static Stream<CellTowerData> cellTowerStream({Duration interval = const Duration(seconds: 2)}) async* {
    while (true) {
      yield await fetchCurrentTower();
      await Future.delayed(interval);
    }
  }
}

final cellTowerProvider = StreamProvider.autoDispose<CellTowerData>((ref) {
  return CellTowerService.cellTowerStream();
});
