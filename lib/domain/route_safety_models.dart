import 'dart:math' as math;

/// Levels of traffic congestion derived strictly from calculated delay ratio.
enum CongestionLevel {
  freeFlow,
  light,
  moderate,
  heavy,
  severe,
  unknown;

  static CongestionLevel fromDelayRatio(double? ratio) {
    if (ratio == null || ratio.isNaN || ratio <= 0) return CongestionLevel.unknown;
    if (ratio < 1.05) return CongestionLevel.freeFlow;
    if (ratio < 1.25) return CongestionLevel.light;
    if (ratio < 1.60) return CongestionLevel.moderate;
    if (ratio < 2.00) return CongestionLevel.heavy;
    return CongestionLevel.severe;
  }

  String get displayName {
    switch (this) {
      case CongestionLevel.freeFlow:
        return 'Free Flow';
      case CongestionLevel.light:
        return 'Light Traffic';
      case CongestionLevel.moderate:
        return 'Moderate Delay';
      case CongestionLevel.heavy:
        return 'Heavy Congestion';
      case CongestionLevel.severe:
        return 'Severe Standstill';
      case CongestionLevel.unknown:
        return 'Traffic Unknown';
    }
  }
}

/// Normalized traffic observation for a route or segment.
class TrafficInfo {
  const TrafficInfo({
    this.staticDurationSeconds,
    this.trafficDurationSeconds,
    this.delaySeconds,
    this.delayRatio,
    this.congestionLevel = CongestionLevel.unknown,
    this.isLive = false,
    this.source = 'Unknown',
  });

  final double? staticDurationSeconds;
  final double? trafficDurationSeconds;
  final double? delaySeconds;
  final double? delayRatio;
  final CongestionLevel congestionLevel;
  final bool isLive;
  final String source;

  static TrafficInfo calculate({
    required double staticSec,
    required double trafficSec,
    required String source,
    bool isLive = true,
  }) {
    final delay = math.max(0.0, trafficSec - staticSec);
    final ratio = staticSec > 0 ? trafficSec / staticSec : 1.0;
    return TrafficInfo(
      staticDurationSeconds: staticSec,
      trafficDurationSeconds: trafficSec,
      delaySeconds: delay,
      delayRatio: ratio,
      congestionLevel: CongestionLevel.fromDelayRatio(ratio),
      isLive: isLive,
      source: source,
    );
  }

  static const TrafficInfo unknown = TrafficInfo(
    congestionLevel: CongestionLevel.unknown,
    isLive: false,
    source: 'No Traffic Data Available',
  );
}

/// Scientific weather observation along a route or at a road segment.
class WeatherInfo {
  const WeatherInfo({
    this.temperatureC,
    this.relativeHumidity,
    this.rainfallMmPerHour,
    this.precipitationProbabilityPercent,
    this.visibilityMeters,
    this.windSpeedKmh,
    this.wmoWeatherCode,
    this.weatherDescription = 'Unknown',
    this.isSevereWeatherAlert = false,
    this.isLive = false,
    this.source = 'Unknown',
  });

  final double? temperatureC;
  final double? relativeHumidity;
  final double? rainfallMmPerHour;
  final int? precipitationProbabilityPercent;
  final double? visibilityMeters;
  final double? windSpeedKmh;
  final int? wmoWeatherCode;
  final String weatherDescription;
  final bool isSevereWeatherAlert;
  final bool isLive;
  final String source;

  static const WeatherInfo unknown = WeatherInfo(
    weatherDescription: 'Weather Unknown',
    isLive: false,
    source: 'No Weather Station Data',
  );

  /// Helper to map WMO standard weather interpretation codes.
  static String describeWmoCode(int? code) {
    if (code == null) return 'Unknown';
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
      case 2:
      case 3:
        return 'Mainly clear / Partly cloudy';
      case 45:
      case 48:
        return 'Fog / Depositing rime fog';
      case 51:
      case 53:
      case 55:
        return 'Drizzle (Light to Dense)';
      case 61:
      case 63:
      case 65:
        return 'Rain (Slight to Heavy)';
      case 80:
      case 81:
      case 82:
        return 'Rain Showers (Moderate to Violent)';
      case 95:
      case 96:
      case 99:
        return 'Thunderstorm / Severe convective storm';
      default:
        return 'WMO Code $code';
    }
  }

  static bool isSevereWmo(int? code) {
    if (code == null) return false;
    return code == 65 || code == 82 || code >= 95;
  }
}

/// Distinct classification of flood risk evidence.
enum FloodRiskCategory {
  observed,
  historical,
  modelDerived,
  unknown,
}

/// Flood and waterlogging telemetry for a segment.
class FloodRiskInfo {
  const FloodRiskInfo({
    this.isHistoricalFloodProne = false,
    this.historicalSpotName,
    this.elevationMeters,
    this.activeRainfallMm,
    this.vulnerabilityRank = 'NONE',
    this.category = FloodRiskCategory.unknown,
    this.source = 'BBMP & Open-Meteo',
  });

  final bool isHistoricalFloodProne;
  final String? historicalSpotName;
  final double? elevationMeters;
  final double? activeRainfallMm;
  final String vulnerabilityRank;
  final FloodRiskCategory category;
  final String source;

  static const FloodRiskInfo unknown = FloodRiskInfo(
    isHistoricalFloodProne: false,
    vulnerabilityRank: 'UNKNOWN',
    category: FloodRiskCategory.unknown,
    source: 'No Flood Data',
  );
}

/// Road surface classification.
enum RoadCondition {
  good,
  moderate,
  poor,
  potholeProne,
  unknown;

  String get displayName {
    switch (this) {
      case RoadCondition.good:
        return 'Good Surface';
      case RoadCondition.moderate:
        return 'Moderate Quality';
      case RoadCondition.poor:
        return 'Rough / Degraded';
      case RoadCondition.potholeProne:
        return 'Pothole Prone';
      case RoadCondition.unknown:
        return 'Unknown Condition';
    }
  }
}

/// Road condition telemetry.
class RoadConditionInfo {
  const RoadConditionInfo({
    this.condition = RoadCondition.unknown,
    this.verticalJerkRms,
    this.roughnessScore,
    this.source = 'Unknown',
    this.confidence,
  });

  final RoadCondition condition;
  final double? verticalJerkRms;
  final double? roughnessScore;
  final String source;
  final double? confidence;

  static const RoadConditionInfo unknown = RoadConditionInfo(
    condition: RoadCondition.unknown,
    source: 'None (Untraversed)',
  );
}

/// Construction and road closure indicators.
enum ConstructionStatus {
  noneReported,
  closure,
  diversion,
  workZone,
  unknown;

  String get displayName {
    switch (this) {
      case ConstructionStatus.noneReported:
        return 'Clear / None Reported';
      case ConstructionStatus.closure:
        return 'Road Closed';
      case ConstructionStatus.diversion:
        return 'Traffic Diversion';
      case ConstructionStatus.workZone:
        return 'Active Work Zone';
      case ConstructionStatus.unknown:
        return 'Status Unknown';
    }
  }
}

class ConstructionInfo {
  const ConstructionInfo({
    this.status = ConstructionStatus.noneReported,
    this.details,
    this.source = 'Google Routes Advisories',
  });

  final ConstructionStatus status;
  final String? details;
  final String source;

  static const ConstructionInfo unknown = ConstructionInfo(
    status: ConstructionStatus.unknown,
    source: 'No Advisory Available',
  );
}

/// Historical accident classification.
enum AccidentSeverity {
  critical,
  high,
  moderate,
  none,
  unknown;

  String get displayName {
    switch (this) {
      case AccidentSeverity.critical:
        return 'Critical Accident Blackspot';
      case AccidentSeverity.high:
        return 'High Frequency Blackspot';
      case AccidentSeverity.moderate:
        return 'Moderate Risk Spot';
      case AccidentSeverity.none:
        return 'No Registered Blackspot';
      case AccidentSeverity.unknown:
        return 'Accident Risk Unknown';
    }
  }
}

class AccidentRiskInfo {
  const AccidentRiskInfo({
    this.isHistoricalBlackspot = false,
    this.blackspotName,
    this.severity = AccidentSeverity.none,
    this.fatalitiesPast3Yr,
    this.liveIncidentReported = false,
    this.liveIncidentDetails,
    this.source = 'MoRTH & Karnataka Traffic Police',
  });

  final bool isHistoricalBlackspot;
  final String? blackspotName;
  final AccidentSeverity severity;
  final int? fatalitiesPast3Yr;
  final bool liveIncidentReported;
  final String? liveIncidentDetails;
  final String source;

  static const AccidentRiskInfo unknown = AccidentRiskInfo(
    severity: AccidentSeverity.unknown,
    source: 'No Historical Blackspot Data',
  );
}

/// Normalized road segment linking discrete geometric edges with real-world safety telemetry.
class RoadSegmentData {
  RoadSegmentData({
    required this.segmentId,
    required this.roadName,
    required this.startLat,
    required this.startLon,
    required this.endLat,
    required this.endLon,
    required this.polyline,
    required this.distanceMeters,
    required this.durationSeconds,
    this.traffic = TrafficInfo.unknown,
    this.weather = WeatherInfo.unknown,
    this.flood = FloodRiskInfo.unknown,
    this.roadCondition = RoadConditionInfo.unknown,
    this.construction = ConstructionInfo.unknown,
    this.accident = AccidentRiskInfo.unknown,
    DateTime? fetchTimestamp,
    this.isMockData = false,
    List<String>? unknownFields,
  })  : fetchTimestamp = fetchTimestamp ?? DateTime.now(),
        unknownFields = unknownFields ?? [];

  final String segmentId;
  final String roadName;
  final double startLat;
  final double startLon;
  final double endLat;
  final double endLon;
  final List<({double lat, double lon})> polyline;
  final double distanceMeters;
  final double durationSeconds;

  final TrafficInfo traffic;
  final WeatherInfo weather;
  final FloodRiskInfo flood;
  final RoadConditionInfo roadCondition;
  final ConstructionInfo construction;
  final AccidentRiskInfo accident;

  final DateTime fetchTimestamp;
  final bool isMockData;
  final List<String> unknownFields;

  int get freshnessSeconds =>
      DateTime.now().difference(fetchTimestamp).inSeconds;
}

/// Full candidate route containing normalized metadata and segment-by-segment telemetry.
class NormalizedRouteData {
  NormalizedRouteData({
    required this.routeId,
    required this.summary,
    required this.providerName,
    required this.originName,
    required this.destinationName,
    required this.originLat,
    required this.originLon,
    required this.destinationLat,
    required this.destinationLon,
    required this.distanceMeters,
    required this.staticDurationSeconds,
    required this.trafficDurationSeconds,
    required this.fullPolyline,
    required this.segments,
    required this.sampleWeather,
    this.isMockData = false,
    DateTime? fetchTimestamp,
  })  : fetchTimestamp = fetchTimestamp ?? DateTime.now(),
        trafficDelaySeconds =
            math.max(0.0, trafficDurationSeconds - staticDurationSeconds),
        overallCongestion = CongestionLevel.fromDelayRatio(
          staticDurationSeconds > 0
              ? trafficDurationSeconds / staticDurationSeconds
              : 1.0,
        );

  final String routeId;
  final String summary;
  final String providerName;
  final String originName;
  final String destinationName;
  final double originLat;
  final double originLon;
  final double destinationLat;
  final double destinationLon;
  final double distanceMeters;
  final double staticDurationSeconds;
  final double trafficDurationSeconds;
  final double trafficDelaySeconds;
  final CongestionLevel overallCongestion;
  final List<({double lat, double lon})> fullPolyline;
  final List<RoadSegmentData> segments;
  final WeatherInfo sampleWeather;
  final bool isMockData;
  final DateTime fetchTimestamp;

  int get freshnessSeconds =>
      DateTime.now().difference(fetchTimestamp).inSeconds;

  int get detectedFloodSpotsCount =>
      segments.where((s) => s.flood.isHistoricalFloodProne).length;

  int get detectedAccidentBlackspotsCount =>
      segments.where((s) => s.accident.isHistoricalBlackspot).length;

  int get detectedWorkZonesCount => segments
      .where((s) => s.construction.status != ConstructionStatus.noneReported &&
          s.construction.status != ConstructionStatus.unknown)
      .length;
}
