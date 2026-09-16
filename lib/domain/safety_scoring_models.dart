import 'route_safety_models.dart';

/// Distinct components of environmental and road safety risk.
enum RiskComponent {
  traffic,
  weather,
  flood,
  roadCondition,
  construction,
  accident;

  String get displayName {
    switch (this) {
      case RiskComponent.traffic:
        return 'Traffic & Congestion';
      case RiskComponent.weather:
        return 'Weather & Rain';
      case RiskComponent.flood:
        return 'Flood Vulnerability';
      case RiskComponent.roadCondition:
        return 'Road Surface';
      case RiskComponent.construction:
        return 'Construction & Work Zones';
      case RiskComponent.accident:
        return 'Accident Blackspots';
    }
  }
}

/// Confidence level indicating completeness, freshness, and reliability of telemetry data.
enum DataConfidence {
  high,
  medium,
  low;

  String get displayName {
    switch (this) {
      case DataConfidence.high:
        return 'HIGH CONFIDENCE';
      case DataConfidence.medium:
        return 'MODERATE CONFIDENCE';
      case DataConfidence.low:
        return 'LOW CONFIDENCE (Missing Data)';
    }
  }
}

/// Recommendation tier for candidate routes.
enum RecommendationStatus {
  recommended,
  viable,
  caution,
  avoid;

  String get displayName {
    switch (this) {
      case RecommendationStatus.recommended:
        return 'RECOMMENDED';
      case RecommendationStatus.viable:
        return 'VIABLE ALTERNATIVE';
      case RecommendationStatus.caution:
        return 'EXERCISE CAUTION';
      case RecommendationStatus.avoid:
        return 'AVOID (CRITICAL HAZARD)';
    }
  }
}

/// User recommendation preference profiles.
enum ScoringMode {
  safest,
  balanced,
  fastest;

  String get displayName {
    switch (this) {
      case ScoringMode.safest:
        return 'Safest';
      case ScoringMode.balanced:
        return 'Balanced';
      case ScoringMode.fastest:
        return 'Fastest';
    }
  }

  String get description {
    switch (this) {
      case ScoringMode.safest:
        return 'Prioritizes maximum safety over travel time (allows reasonable detours).';
      case ScoringMode.balanced:
        return 'Optimal balance of safety and realistic travel duration.';
      case ScoringMode.fastest:
        return 'Optimizes for minimum ETA while strictly blocking confirmed critical hazards.';
    }
  }

  /// Relative weights for multi-objective optimization: [safetyWeight, etaWeight, distanceWeight].
  ({double safetyWeight, double etaWeight, double distanceWeight}) get weights {
    switch (this) {
      case ScoringMode.safest:
        return (safetyWeight: 0.70, etaWeight: 0.20, distanceWeight: 0.10);
      case ScoringMode.balanced:
        return (safetyWeight: 0.45, etaWeight: 0.40, distanceWeight: 0.15);
      case ScoringMode.fastest:
        return (safetyWeight: 0.20, etaWeight: 0.70, distanceWeight: 0.10);
    }
  }
}

/// Normalized risk evaluation for an individual road segment.
class SegmentRiskProfile {
  const SegmentRiskProfile({
    required this.segmentId,
    required this.roadName,
    required this.trafficRisk,
    required this.weatherRisk,
    required this.floodRisk,
    required this.roadConditionRisk,
    required this.constructionRisk,
    required this.accidentRisk,
    required this.compositeRisk,
    this.isCriticalHazard = false,
    this.criticalHazardReason,
    this.dataConfidence = DataConfidence.medium,
    this.explanations = const [],
  });

  final String segmentId;
  final String roadName;

  /// Normalized sub-risks on scale [0.0 (safest) - 1.0 (most hazardous)].
  final double trafficRisk;
  final double weatherRisk;
  final double floodRisk;
  final double roadConditionRisk;
  final double constructionRisk;
  final double accidentRisk;

  /// Weighted composite risk [0.0 - 1.0].
  final double compositeRisk;

  /// Critical hazard override flag (road closure, severe flood underpass, critical crash cluster).
  final bool isCriticalHazard;
  final String? criticalHazardReason;

  /// Data quality confidence level.
  final DataConfidence dataConfidence;

  /// Explainable factors contributing to this segment's risk profile.
  final List<String> explanations;

  /// Return risk value by component.
  double getRisk(RiskComponent component) {
    switch (component) {
      case RiskComponent.traffic:
        return trafficRisk;
      case RiskComponent.weather:
        return weatherRisk;
      case RiskComponent.flood:
        return floodRisk;
      case RiskComponent.roadCondition:
        return roadConditionRisk;
      case RiskComponent.construction:
        return constructionRisk;
      case RiskComponent.accident:
        return accidentRisk;
    }
  }
}

/// Route-level safety score (0–100) with explainable reasoning and critical hazard flags.
class RouteSafetyScore {
  const RouteSafetyScore({
    required this.overallScore,
    required this.componentScores,
    required this.distanceWeightedMeanRisk,
    required this.peakHazardRisk,
    required this.recommendationStatus,
    required this.dataConfidence,
    required this.confidenceScore,
    this.criticalOverride = false,
    this.criticalOverrideReason,
    this.positiveExplanations = const [],
    this.warningExplanations = const [],
    this.segmentProfiles = const [],
  });

  /// User-facing safety score: 0 (extremely risky) to 100 (safest possible).
  final int overallScore;

  /// Component sub-scores: 0 to 100 per safety dimension.
  final Map<RiskComponent, int> componentScores;

  /// Raw underlying distance-weighted mean risk [0.0 - 1.0].
  final double distanceWeightedMeanRisk;

  /// Peak hazard risk along the route [0.0 - 1.0] (prevents masking high-hazard spots).
  final double peakHazardRisk;

  /// Recommendation status tier.
  final RecommendationStatus recommendationStatus;

  /// Confidence tier reflecting missing data or untraversed segments.
  final DataConfidence dataConfidence;

  /// Numerical confidence index [0.0 - 1.0].
  final double confidenceScore;

  /// Confirmed critical hazard override flag.
  final bool criticalOverride;
  final String? criticalOverrideReason;

  /// Plain-English positive explanations ("Why recommended").
  final List<String> positiveExplanations;

  /// Plain-English warnings.
  final List<String> warningExplanations;

  /// Detailed segment-by-segment evaluations.
  final List<SegmentRiskProfile> segmentProfiles;

  /// Whether route is considered generally safe (score >= 70 and no critical hazard).
  bool get isGenerallySafe => overallScore >= 70 && !criticalOverride;
}

/// Candidate route ranked by NavGuardian AI's multi-objective evaluation engine.
class RankedRoute {
  const RankedRoute({
    required this.route,
    required this.safetyScore,
    required this.rank,
    required this.compositeUtility,
    required this.timeDeltaSeconds,
    required this.distanceDeltaMeters,
    required this.isRecommended,
    required this.recommendationHeadline,
    required this.mode,
  });

  final NormalizedRouteData route;
  final RouteSafetyScore safetyScore;
  final int rank;
  final double compositeUtility;
  final double timeDeltaSeconds;
  final double distanceDeltaMeters;
  final bool isRecommended;
  final String recommendationHeadline;
  final ScoringMode mode;

  String get timeDeltaFormatted {
    final mins = (timeDeltaSeconds / 60.0).round();
    if (mins <= 0) return 'Fastest';
    return '+$mins mins';
  }

  String get distanceDeltaFormatted {
    final km = distanceDeltaMeters / 1000.0;
    if (km <= 0.05) return 'Shortest';
    return '+${km.toStringAsFixed(1)} km';
  }
}
