import 'dart:math' as math;
import '../../domain/route_safety_models.dart';
import '../../domain/safety_scoring_models.dart';

/// AI/Probabilistic Route Risk Evaluator implementing Naive Bayesian conditional hazard estimation.
///
/// Compares probabilistic route hazard expectations against the transparent multi-criteria
/// weighted baseline, and documents the Phase 8 crowdsourced feature blueprint.
class BayesianRouteRiskEvaluator {
  const BayesianRouteRiskEvaluator({
    this.baseHazardPrior = 0.05, // 5% prior incident probability on urban roads
  });

  /// Base prior probability of an incident / hazard occurring on any random road segment.
  final double baseHazardPrior;

  /// Estimate the posterior hazard probability P(Hazard | Evidence) for a road segment.
  double estimateSegmentHazardProbability(RoadSegmentData segment) {
    // Likelihood ratios L(E_i) = P(E_i | Hazard) / P(E_i | NoHazard)
    double likelihoodRatio = 1.0;

    // Evidence 1: Traffic Congestion
    final delayRatio = segment.traffic.delayRatio ?? 1.0;
    if (delayRatio > 2.0) {
      likelihoodRatio *= 2.4; // Standstill traffic has higher collision risk
    } else if (delayRatio > 1.3) {
      likelihoodRatio *= 1.4;
    } else {
      likelihoodRatio *= 0.85; // Free flow
    }

    // Evidence 2: Weather & Precipitation
    final rain = segment.weather.rainfallMmPerHour ?? 0.0;
    if (rain > 10.0 || segment.weather.isSevereWeatherAlert) {
      likelihoodRatio *= 3.2; // Severe storm / torrential rain
    } else if (rain > 2.0) {
      likelihoodRatio *= 1.8;
    } else {
      likelihoodRatio *= 0.9;
    }

    // Evidence 3: Historical Flood Blackspot
    if (segment.flood.isHistoricalFloodProne) {
      final rank = segment.flood.vulnerabilityRank.toUpperCase();
      if (rank == 'SEVERE') {
        likelihoodRatio *= 4.5;
      } else if (rank == 'HIGH') {
        likelihoodRatio *= 3.0;
      } else {
        likelihoodRatio *= 1.6;
      }
    } else {
      likelihoodRatio *= 0.8;
    }

    // Evidence 4: MoRTH Accident Blackspot
    if (segment.accident.isHistoricalBlackspot) {
      final sev = segment.accident.severity;
      if (sev == AccidentSeverity.critical) {
        likelihoodRatio *= 5.0;
      } else if (sev == AccidentSeverity.high) {
        likelihoodRatio *= 3.5;
      } else {
        likelihoodRatio *= 2.0;
      }
    } else {
      likelihoodRatio *= 0.75;
    }

    // Evidence 5: Road Surface Roughness
    if (segment.roadCondition.condition == RoadCondition.potholeProne ||
        segment.roadCondition.condition == RoadCondition.poor) {
      likelihoodRatio *= 2.2;
    } else if (segment.roadCondition.condition == RoadCondition.good) {
      likelihoodRatio *= 0.7;
    }

    // Evidence 6: Construction
    if (segment.construction.status == ConstructionStatus.closure) {
      return 0.99; // Near certainty of impassability
    } else if (segment.construction.status == ConstructionStatus.workZone ||
        segment.construction.status == ConstructionStatus.diversion) {
      likelihoodRatio *= 2.5;
    }

    // Odds update: Posterior Odds = Prior Odds * Likelihood Ratio
    final priorOdds = baseHazardPrior / (1.0 - baseHazardPrior);
    final posteriorOdds = priorOdds * likelihoodRatio;
    final posteriorProb = posteriorOdds / (1.0 + posteriorOdds);

    return math.min(0.99, math.max(0.01, posteriorProb));
  }

  /// Evaluates entire route hazard using Bayesian segment integration.
  ({double routeIncidentProbability, int bayesianSafetyScore}) evaluateRouteBayesian(NormalizedRouteData route) {
    if (route.segments.isEmpty) {
      return (routeIncidentProbability: baseHazardPrior, bayesianSafetyScore: 50);
    }

    // Probability that at least one hazardous incident occurs along the route:
    // P(Route Hazard) = 1 - product(1 - P(Segment_k Hazard))
    double safeProb = 1.0;
    for (final s in route.segments) {
      final segP = estimateSegmentHazardProbability(s);
      safeProb *= (1.0 - segP);
    }

    final routeHazardP = 1.0 - safeProb;
    final score = (math.max(0.0, 1.0 - routeHazardP) * 100.0).round();

    return (
      routeIncidentProbability: routeHazardP,
      bayesianSafetyScore: math.min(100, math.max(0, score)),
    );
  }

  /// Benchmark report comparing AI Bayesian route model with Transparent Weighted Baseline.
  Map<String, dynamic> compareWithBaseline(
    NormalizedRouteData route,
    RouteSafetyScore baselineScore,
  ) {
    final bayesian = evaluateRouteBayesian(route);
    final scoreDelta = (bayesian.bayesianSafetyScore - baselineScore.overallScore).abs();

    return {
      'routeId': route.routeId,
      'baselineScore': baselineScore.overallScore,
      'bayesianScore': bayesian.bayesianSafetyScore,
      'scoreDelta': scoreDelta,
      'bayesianIncidentProbability': bayesian.routeIncidentProbability,
      'baselinePeakHazard': baselineScore.peakHazardRisk,
      'agreement': scoreDelta <= 15 ? 'HIGH_AGREEMENT' : 'MODERATE_DIVERGENCE',
      'rationale': scoreDelta <= 15
          ? 'Analytical baseline and Bayesian model converge on route safety tier.'
          : 'Divergence caused by compound probability effect on multi-segment routes.',
    };
  }

  /// Machine Learning Dataset Blueprint for Phase 8 Crowdsourcing.
  ///
  /// Outlines the required supervised data attributes to train gradient-boosted
  /// models (XGBoost / LightGBM) in Phase 8 without premature synthetic overfitting.
  static const Map<String, dynamic> kPhase8MlBlueprint = {
    'targetVariable': 'hazard_incident_confirmed (bool, binary classification)',
    'featureVectors': [
      'traffic_delay_ratio (float, continuous)',
      'traffic_congestion_level (categorical, 5 levels)',
      'open_meteo_rainfall_mm_per_hr (float, continuous)',
      'precipitation_probability_percent (int, 0-100)',
      'bbmp_historical_flood_rank (categorical, 5 levels)',
      'morth_blackspot_3yr_fatalities (int, continuous)',
      'accelerometer_vertical_jerk_rms (float, continuous)',
      'road_roughness_score (float, 0-100)',
      'construction_status (categorical, 4 levels)',
      'time_of_day_hour (int, 0-23)',
      'is_weekend (bool)',
      'traversed_speed_vs_free_flow_ratio (float)',
    ],
    'requiredSampleSize': 'Minimum 500 ground-truth user confirmation events per corridor',
    'validationProtocol': 'Chronological temporal split with 5-fold cross-validation',
  };
}
