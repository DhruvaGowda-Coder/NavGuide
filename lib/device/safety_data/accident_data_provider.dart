import 'dart:convert';
import 'package:flutter/services.dart';
import '../../domain/route_safety_models.dart';
import '../dead_reckoning/dead_reckoning_engine.dart';

class AccidentBlackspotRecord {
  const AccidentBlackspotRecord({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.bufferRadiusMeters,
    required this.severity,
    required this.fatalitiesPast3Yr,
    required this.roadName,
    required this.junctionType,
    required this.riskFactors,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double bufferRadiusMeters;
  final String severity;
  final int fatalitiesPast3Yr;
  final String roadName;
  final String junctionType;
  final String riskFactors;

  factory AccidentBlackspotRecord.fromJson(Map<String, dynamic> json) {
    return AccidentBlackspotRecord(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      bufferRadiusMeters: (json['buffer_radius_meters'] as num?)?.toDouble() ?? 250.0,
      severity: json['historical_severity'] as String? ?? 'HIGH',
      fatalitiesPast3Yr: json['fatalities_past_3yr'] as int? ?? 5,
      roadName: json['road_name'] as String? ?? '',
      junctionType: json['junction_type'] as String? ?? '',
      riskFactors: json['risk_factors'] as String? ?? '',
    );
  }
}

/// Provider for official Karnataka Traffic Police & MoRTH historical accident blackspots.
class AccidentDataProvider {
  List<AccidentBlackspotRecord> _blackspots = [];
  bool _isLoaded = false;

  /// Loads official accident blackspots dataset.
  Future<void> initialize({String? jsonString}) async {
    if (_isLoaded) return;
    try {
      String? content = jsonString;
      if (content == null) {
        try {
          content = await rootBundle.loadString('assets/data/all_india_accident_blackspots.json');
        } catch (_) {
          content = await rootBundle.loadString('assets/data/karnataka_accident_blackspots.json');
        }
      }
      final data = jsonDecode(content) as Map<String, dynamic>;
      final list = data['accident_blackspots'] as List<dynamic>? ?? [];
      _blackspots = list
          .map((e) => AccidentBlackspotRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      _isLoaded = true;
    } catch (_) {
      _blackspots = [];
    }
  }

  /// Evaluates historical accident risk for coordinates along a road segment.
  Future<AccidentRiskInfo> evaluateLocation({
    required double latitude,
    required double longitude,
  }) async {
    if (!_isLoaded) {
      await initialize();
    }

    AccidentBlackspotRecord? matchedSpot;
    var minDistance = double.infinity;

    for (final spot in _blackspots) {
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

    if (matchedSpot != null) {
      AccidentSeverity sev = AccidentSeverity.moderate;
      if (matchedSpot.severity.toUpperCase() == 'CRITICAL') {
        sev = AccidentSeverity.critical;
      } else if (matchedSpot.severity.toUpperCase() == 'HIGH') {
        sev = AccidentSeverity.high;
      }

      return AccidentRiskInfo(
        isHistoricalBlackspot: true,
        blackspotName: matchedSpot.name,
        severity: sev,
        fatalitiesPast3Yr: matchedSpot.fatalitiesPast3Yr,
        liveIncidentReported: false,
        source: 'MoRTH & Karnataka Traffic Police Audit (${minDistance.toInt()}m from core)',
      );
    }

    return const AccidentRiskInfo(
      isHistoricalBlackspot: false,
      blackspotName: null,
      severity: AccidentSeverity.none,
      liveIncidentReported: false,
      source: 'MoRTH & Karnataka Police Blackspot Audit',
    );
  }
}
