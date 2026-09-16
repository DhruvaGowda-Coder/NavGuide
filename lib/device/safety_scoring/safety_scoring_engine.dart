import 'dart:math' as math;
import '../../domain/route_safety_models.dart';
import '../../domain/safety_scoring_models.dart';
import '../../domain/crowdsourced_hazard_models.dart';

/// Scientific, multi-criteria safety evaluation and route ranking engine.
class SafetyScoringEngine {
  const SafetyScoringEngine();

  /// Default component weights summing to 1.0.
  static const Map<RiskComponent, double> kDefaultWeights = {
    RiskComponent.accident: 0.25,
    RiskComponent.flood: 0.22,
    RiskComponent.traffic: 0.18,
    RiskComponent.weather: 0.15,
    RiskComponent.roadCondition: 0.10,
    RiskComponent.construction: 0.10,
  };

  /// Evaluate risk for an individual road segment.
  SegmentRiskProfile evaluateSegment(
    RoadSegmentData segment, {
    DateTime? estimatedArrival,
    WeatherInfo? corridorWeather,
  }) {
    final explanations = <String>[];
    var isCritical = false;
    String? criticalReason;
    var unknownCount = 0;

    // 1. Traffic Risk [0.0 - 1.0]
    double trafficRisk;
    if (segment.traffic.congestionLevel == CongestionLevel.unknown &&
        segment.traffic.delayRatio == null) {
      trafficRisk = 0.30;
      unknownCount++;
    } else {
      final ratio = segment.traffic.delayRatio ?? 1.0;
      if (ratio <= 1.05) {
        trafficRisk = 0.05;
      } else {
        trafficRisk = math.min(1.0, math.max(0.0, (ratio - 1.0) / 1.5));
      }
      if (segment.traffic.congestionLevel == CongestionLevel.severe) {
        trafficRisk = math.max(trafficRisk, 0.85);
        explanations.add('Severe standstill traffic delay');
      } else if (segment.traffic.congestionLevel == CongestionLevel.heavy) {
        trafficRisk = math.max(trafficRisk, 0.65);
        explanations.add('Heavy traffic congestion');
      }
    }

    // 2. Weather Risk [0.0 - 1.0]
    final w = segment.weather.isLive ? segment.weather : (corridorWeather ?? segment.weather);
    double weatherRisk = 0.05;
    if (!w.isLive && w.weatherDescription == 'Weather Unknown') {
      weatherRisk = 0.20;
      unknownCount++;
    } else {
      final rainMm = w.rainfallMmPerHour ?? 0.0;
      final pop = w.precipitationProbabilityPercent ?? 0;
      final rainRisk = math.min(1.0, rainMm / 15.0);
      final popRisk = pop / 100.0;
      final severeBonus = (w.isSevereWeatherAlert || WeatherInfo.isSevereWmo(w.wmoWeatherCode)) ? 0.40 : 0.0;

      weatherRisk = math.min(1.0, 0.45 * rainRisk + 0.25 * popRisk + severeBonus + 0.05);

      if (rainMm >= 5.0) {
        explanations.add('Heavy rainfall (${rainMm.toStringAsFixed(1)} mm/hr)');
      }
      if (w.isSevereWeatherAlert) {
        explanations.add('Active severe convective weather alert');
      }
    }

    // 3. Flood Risk [0.0 - 1.0]
    double floodRisk = 0.0;
    final isFloodUnknown = segment.flood.vulnerabilityRank == 'UNKNOWN' &&
        segment.flood.category == FloodRiskCategory.unknown &&
        !segment.flood.isHistoricalFloodProne;

    if (isFloodUnknown) {
      floodRisk = 0.25; // Unknown territory carries cautious baseline
      unknownCount++;
    } else if (segment.flood.isHistoricalFloodProne) {
      switch (segment.flood.vulnerabilityRank.toUpperCase()) {
        case 'SEVERE':
          floodRisk = 0.90;
          break;
        case 'HIGH':
          floodRisk = 0.70;
          break;
        case 'MODERATE':
          floodRisk = 0.45;
          break;
        case 'LOW':
          floodRisk = 0.25;
          break;
        default:
          floodRisk = 0.35;
      }
      final spot = segment.flood.historicalSpotName ?? 'Recorded Flood Spot';
      explanations.add('BBMP/KSNDMC flood blackspot: $spot (${segment.flood.vulnerabilityRank})');

      // Check dynamic rainfall interaction
      final activeRain = w.rainfallMmPerHour ?? 0.0;
      if (activeRain > 0) {
        floodRisk = math.min(1.0, floodRisk * (1.0 + 0.5 * math.min(2.0, activeRain / 10.0)));
      }

      // Critical Hazard Override: Severe flood spot under active rain
      if (segment.flood.vulnerabilityRank.toUpperCase() == 'SEVERE' && activeRain >= 4.0) {
        isCritical = true;
        criticalReason = 'Severe flood blackspot active under heavy rain ($spot)';
      }
    } else {
      // Known to not be historically flood prone
      floodRisk = 0.0;
      final activeRain = w.rainfallMmPerHour ?? 0.0;
      if (activeRain >= 20.0) {
        floodRisk = 0.25; // Surface water accumulation from torrential rain
      }
    }

    // 4. Road Condition Risk [0.0 - 1.0]
    double surfaceRisk;
    switch (segment.roadCondition.condition) {
      case RoadCondition.good:
        surfaceRisk = 0.05;
        break;
      case RoadCondition.moderate:
        surfaceRisk = 0.30;
        break;
      case RoadCondition.poor:
        surfaceRisk = 0.65;
        explanations.add('Degraded road surface detected');
        break;
      case RoadCondition.potholeProne:
        surfaceRisk = 0.85;
        explanations.add('Pothole-prone road section');
        break;
      case RoadCondition.unknown:
        surfaceRisk = 0.40;
        unknownCount++;
        break;
    }

    // 5. Construction & Closure Risk [0.0 - 1.0]
    double constRisk = 0.0;
    switch (segment.construction.status) {
      case ConstructionStatus.noneReported:
        constRisk = 0.0;
        break;
      case ConstructionStatus.workZone:
        constRisk = 0.35;
        explanations.add('Active construction work zone');
        break;
      case ConstructionStatus.diversion:
        constRisk = 0.65;
        explanations.add('Traffic diversion in effect');
        break;
      case ConstructionStatus.closure:
        constRisk = 1.0;
        isCritical = true;
        criticalReason = 'Confirmed road closure on ${segment.roadName}';
        explanations.add('ROAD CLOSED: Confirmed closure');
        break;
      case ConstructionStatus.unknown:
        constRisk = 0.15;
        unknownCount++;
        break;
    }

    // 6. Accident Blackspot Risk [0.0 - 1.0]
    double accidentRisk = 0.0;
    if (segment.accident.severity == AccidentSeverity.unknown) {
      accidentRisk = 0.25; // Unknown accident history carries cautious baseline
      unknownCount++;
    } else if (segment.accident.isHistoricalBlackspot) {
      switch (segment.accident.severity) {
        case AccidentSeverity.critical:
          accidentRisk = 0.95;
          break;
        case AccidentSeverity.high:
          accidentRisk = 0.75;
          break;
        case AccidentSeverity.moderate:
          accidentRisk = 0.45;
          break;
        case AccidentSeverity.none:
          accidentRisk = 0.0;
          break;
        case AccidentSeverity.unknown:
          accidentRisk = 0.25;
          break;
      }
      final fatalCount = segment.accident.fatalitiesPast3Yr ?? 0;
      accidentRisk = math.min(1.0, accidentRisk + 0.05 * math.min(5, fatalCount));
      final spot = segment.accident.blackspotName ?? 'MoRTH Accident Blackspot';
      explanations.add('$spot (${segment.accident.severity.displayName})');

      if (segment.accident.liveIncidentReported) {
        accidentRisk = math.min(1.0, accidentRisk + 0.25);
        explanations.add('Live accident incident reported on this road');
        if (segment.accident.severity == AccidentSeverity.critical) {
          isCritical = true;
          criticalReason = 'Critical accident blackspot with active incident on ${segment.roadName}';
        }
      }
    }

    // 7. Community Crowdsourced Hazards Integration
    if (segment.crowdsourcedHazards.isNotEmpty) {
      for (final h in segment.crowdsourcedHazards) {
        if (!h.isCommunityConfirmed && h.confirmationsCount < 1) continue;

        final weight = h.hazardType.defaultRiskWeight * h.reliabilityScore;
        switch (h.hazardType) {
          case HazardType.roadBlocked:
            isCritical = true;
            criticalReason = 'Community confirmed road blockage on ${segment.roadName}';
            explanations.add('ROAD BLOCKED: ${h.description} (${h.confirmationsCount} confirmations)');
            constRisk = 1.0;
            break;
          case HazardType.flood:
            floodRisk = math.max(floodRisk, math.min(1.0, floodRisk + weight));
            explanations.add('Crowdsourced waterlogging: ${h.description} (${h.confirmationsCount} votes)');
            if (h.severity == 'CRITICAL' && h.confirmationsCount >= 5) {
              isCritical = true;
              criticalReason = 'Critical flood hazard reported by community on ${segment.roadName}';
            }
            break;
          case HazardType.pothole:
          case HazardType.poorRoad:
            surfaceRisk = math.max(surfaceRisk, math.min(1.0, surfaceRisk + weight * 0.7));
            explanations.add('Crowdsourced hazard: ${h.description}');
            break;
          case HazardType.accident:
            accidentRisk = math.max(accidentRisk, math.min(1.0, accidentRisk + weight * 0.8));
            explanations.add('Crowdsourced incident: ${h.description}');
            break;
          case HazardType.construction:
            constRisk = math.max(constRisk, math.min(1.0, constRisk + weight * 0.6));
            explanations.add('Crowdsourced work zone: ${h.description}');
            break;
          case HazardType.other:
            explanations.add('Community notice: ${h.description}');
            break;
        }
      }
    }

    // Weighted composite risk
    final composite = kDefaultWeights[RiskComponent.accident]! * accidentRisk +
        kDefaultWeights[RiskComponent.flood]! * floodRisk +
        kDefaultWeights[RiskComponent.traffic]! * trafficRisk +
        kDefaultWeights[RiskComponent.weather]! * weatherRisk +
        kDefaultWeights[RiskComponent.roadCondition]! * surfaceRisk +
        kDefaultWeights[RiskComponent.construction]! * constRisk;

    // Confidence
    DataConfidence confidence = DataConfidence.high;
    if (unknownCount >= 3) {
      confidence = DataConfidence.low;
    } else if (unknownCount >= 1) {
      confidence = DataConfidence.medium;
    }

    return SegmentRiskProfile(
      segmentId: segment.segmentId,
      roadName: segment.roadName,
      trafficRisk: trafficRisk,
      weatherRisk: weatherRisk,
      floodRisk: floodRisk,
      roadConditionRisk: surfaceRisk,
      constructionRisk: constRisk,
      accidentRisk: accidentRisk,
      compositeRisk: math.min(1.0, math.max(0.0, composite)),
      isCriticalHazard: isCritical,
      criticalHazardReason: criticalReason,
      dataConfidence: confidence,
      explanations: explanations,
    );
  }

  /// Evaluate complete route safety score (0–100) and explainable recommendations.
  RouteSafetyScore evaluateRoute(
    NormalizedRouteData route, {
    ScoringMode mode = ScoringMode.balanced,
  }) {
    if (route.segments.isEmpty) {
      return const RouteSafetyScore(
        overallScore: 50,
        componentScores: {
          RiskComponent.traffic: 50,
          RiskComponent.weather: 50,
          RiskComponent.flood: 50,
          RiskComponent.roadCondition: 50,
          RiskComponent.construction: 50,
          RiskComponent.accident: 50,
        },
        distanceWeightedMeanRisk: 0.50,
        peakHazardRisk: 0.50,
        recommendationStatus: RecommendationStatus.caution,
        dataConfidence: DataConfidence.low,
        confidenceScore: 0.3,
        positiveExplanations: ['No segment details available.'],
        warningExplanations: ['Incomplete route geometry.'],
      );
    }

    final profiles = <SegmentRiskProfile>[];
    var totalDistance = 0.0;
    var weightedRiskSum = 0.0;
    var peakRisk = 0.0;
    var hasCritical = false;
    String? criticalReason;

    final componentWeightedSums = <RiskComponent, double>{
      for (final c in RiskComponent.values) c: 0.0,
    };

    var highConfCount = 0;
    var lowConfCount = 0;

    for (final seg in route.segments) {
      final profile = evaluateSegment(seg, corridorWeather: route.sampleWeather);
      profiles.add(profile);

      final d = math.max(1.0, seg.distanceMeters);
      totalDistance += d;
      weightedRiskSum += d * profile.compositeRisk;

      if (profile.compositeRisk > peakRisk) {
        peakRisk = profile.compositeRisk;
      }

      for (final c in RiskComponent.values) {
        componentWeightedSums[c] = componentWeightedSums[c]! + d * profile.getRisk(c);
      }

      if (profile.isCriticalHazard) {
        hasCritical = true;
        criticalReason ??= profile.criticalHazardReason;
      }

      if (profile.dataConfidence == DataConfidence.high) highConfCount++;
      if (profile.dataConfidence == DataConfidence.low) lowConfCount++;
    }

    final distanceWeightedMean = totalDistance > 0 ? (weightedRiskSum / totalDistance) : 0.5;

    // Component sub-scores (0-100, where 100 = safest)
    final componentScores = <RiskComponent, int>{};
    for (final c in RiskComponent.values) {
      final meanCompRisk = totalDistance > 0 ? (componentWeightedSums[c]! / totalDistance) : 0.5;
      componentScores[c] = (math.max(0.0, 1.0 - meanCompRisk) * 100.0).round();
    }

    // Peak-Hazard Integrated Risk formula:
    // Ensures a 10% death-trap cannot be hidden by 90% benign highway.
    final integratedRisk = 0.55 * distanceWeightedMean + 0.45 * peakRisk;

    // Base score (0-100)
    var overallScore = (math.max(0.0, 1.0 - integratedRisk) * 100.0).round();


    // Data confidence calculation
    final confidenceScore = math.max(
      0.1,
      math.min(
        1.0,
        (highConfCount * 1.0 + (route.segments.length - highConfCount - lowConfCount) * 0.7 + lowConfCount * 0.3) /
            route.segments.length,
      ),
    );

    DataConfidence routeConfidence = DataConfidence.high;
    if (confidenceScore < 0.55 || lowConfCount > route.segments.length * 0.4) {
      routeConfidence = DataConfidence.low;
    } else if (confidenceScore < 0.80) {
      routeConfidence = DataConfidence.medium;
    }

    // Uncertainty adjustment: route with low confidence cannot be declared completely safe
    if (routeConfidence == DataConfidence.low) {
      overallScore = math.min(overallScore, 68);
    } else if (routeConfidence == DataConfidence.medium) {
      overallScore = math.min(overallScore, 84);
    }

    // Critical Hazard Override penalty
    if (hasCritical) {
      overallScore = math.min(overallScore, 35);
    }
    overallScore = math.min(100, math.max(0, overallScore));


    // Recommendation Status
    RecommendationStatus status;
    if (hasCritical) {
      status = RecommendationStatus.avoid;
    } else if (overallScore >= 80) {
      status = RecommendationStatus.recommended;
    } else if (overallScore >= 65) {
      status = RecommendationStatus.viable;
    } else {
      status = RecommendationStatus.caution;
    }

    // Generate plain-English explanations
    final (positive, warnings) = _generateExplanations(
      route,
      componentScores,
      hasCritical,
      criticalReason,
      profiles,
    );

    return RouteSafetyScore(
      overallScore: overallScore,
      componentScores: componentScores,
      distanceWeightedMeanRisk: distanceWeightedMean,
      peakHazardRisk: peakRisk,
      recommendationStatus: status,
      dataConfidence: routeConfidence,
      confidenceScore: confidenceScore,
      criticalOverride: hasCritical,
      criticalOverrideReason: criticalReason,
      positiveExplanations: positive,
      warningExplanations: warnings,
      segmentProfiles: profiles,
    );
  }

  /// Multi-objective candidate route ranking algorithm.
  List<RankedRoute> rankRoutes(
    List<NormalizedRouteData> routes, {
    ScoringMode mode = ScoringMode.balanced,
  }) {
    if (routes.isEmpty) return const [];

    final routeScores = <NormalizedRouteData, RouteSafetyScore>{};
    for (final r in routes) {
      routeScores[r] = evaluateRoute(r, mode: mode);
    }

    // Find baseline minimums for normalization
    final minDuration = routes.map((r) => r.trafficDurationSeconds).reduce(math.min);
    final minDistance = routes.map((r) => r.distanceMeters).reduce(math.min);

    final weights = mode.weights;
    final scoredList = <({NormalizedRouteData route, RouteSafetyScore score, double utility})>[];

    for (final r in routes) {
      final score = routeScores[r]!;

      // If critical hazard override, penalize utility severely
      if (score.criticalOverride) {
        scoredList.add((route: r, score: score, utility: -100.0 + score.overallScore));
        continue;
      }

      // Multi-Objective Utility Function:
      // Safety (normalized [0, 1]) - Travel Time Penalty - Distance Penalty
      final safetyNorm = score.overallScore / 100.0;
      final timePenalty = minDuration > 0 ? (r.trafficDurationSeconds - minDuration) / minDuration : 0.0;
      final distPenalty = minDistance > 0 ? (r.distanceMeters - minDistance) / minDistance : 0.0;

      final utility = weights.safetyWeight * safetyNorm -
          weights.etaWeight * timePenalty -
          weights.distanceWeight * distPenalty;

      scoredList.add((route: r, score: score, utility: utility));
    }

    // Sort descending by utility
    scoredList.sort((a, b) => b.utility.compareTo(a.utility));

    final results = <RankedRoute>[];
    for (var i = 0; i < scoredList.length; i++) {
      final item = scoredList[i];
      final isRec = i == 0 && !item.score.criticalOverride;
      final timeDelta = item.route.trafficDurationSeconds - minDuration;
      final distDelta = item.route.distanceMeters - minDistance;

      final headline = _createRecommendationHeadline(
        rank: i + 1,
        isRecommended: isRec,
        route: item.route,
        score: item.score,
        timeDeltaSec: timeDelta,
        mode: mode,
      );

      results.add(
        RankedRoute(
          route: item.route,
          safetyScore: item.score,
          rank: i + 1,
          compositeUtility: item.utility,
          timeDeltaSeconds: timeDelta,
          distanceDeltaMeters: distDelta,
          isRecommended: isRec,
          recommendationHeadline: headline,
          mode: mode,
        ),
      );
    }

    return results;
  }

  /// Grounded plain-English bullet points.
  (List<String> positive, List<String> warnings) _generateExplanations(
    NormalizedRouteData route,
    Map<RiskComponent, int> componentScores,
    bool hasCritical,
    String? criticalReason,
    List<SegmentRiskProfile> profiles,
  ) {
    final positive = <String>[];
    final warnings = <String>[];

    // Flood analysis
    final floodCount = route.detectedFloodSpotsCount;
    if (floodCount == 0) {
      positive.add('Zero BBMP/KSNDMC waterlogging spots registered');
    } else {
      warnings.add('$floodCount recorded flood vulnerability blackspot${floodCount > 1 ? 's' : ''}');
    }

    // Accident blackspots
    final accidentCount = route.detectedAccidentBlackspotsCount;
    if (accidentCount == 0) {
      positive.add('Zero official MoRTH high-fatality accident blackspots');
    } else {
      warnings.add('$accidentCount MoRTH high-fatality accident blackspot${accidentCount > 1 ? 's' : ''}');
    }

    // Traffic condition
    if (componentScores[RiskComponent.traffic]! >= 85) {
      positive.add('Free-flowing traffic with minimal delay (+${(route.trafficDelaySeconds / 60).round()}m)');
    } else if (componentScores[RiskComponent.traffic]! <= 50) {
      warnings.add('Heavy traffic congestion (+${(route.trafficDelaySeconds / 60).round()}m delay)');
    }

    // Weather condition
    if (route.sampleWeather.isLive && (route.sampleWeather.rainfallMmPerHour ?? 0.0) >= 2.0) {
      warnings.add('Active rainfall ${route.sampleWeather.rainfallMmPerHour} mm/hr along corridor');
    } else if (route.sampleWeather.isLive) {
      positive.add('Favorable weather (${route.sampleWeather.weatherDescription})');
    }

    // Construction / Work zones
    final workZones = route.detectedWorkZonesCount;
    if (workZones == 0) {
      positive.add('No active construction work zones reported');
    } else {
      warnings.add('$workZones active road construction work zone${workZones > 1 ? 's' : ''}');
    }

    // Road condition / Surface
    if (componentScores[RiskComponent.roadCondition]! >= 80) {
      positive.add('Calibrated sensor history indicates smooth road surface');
    } else if (componentScores[RiskComponent.roadCondition]! <= 50) {
      warnings.add('Degraded road surface / roughness detected on corridor');
    }

    // Critical hazard override
    if (hasCritical && criticalReason != null) {
      warnings.insert(0, 'CRITICAL HAZARD: $criticalReason');
    }

    return (positive, warnings);
  }

  String _createRecommendationHeadline({
    required int rank,
    required bool isRecommended,
    required NormalizedRouteData route,
    required RouteSafetyScore score,
    required double timeDeltaSec,
    required ScoringMode mode,
  }) {
    if (score.criticalOverride) {
      return 'AVOID ROUTE: ${score.criticalOverrideReason ?? "Critical hazard detected"}';
    }

    if (isRecommended) {
      final timeMins = (timeDeltaSec / 60.0).round();
      if (timeMins <= 0) {
        return 'NAVGUARDIAN RECOMMENDS ROUTE (Fastest & Safest, Safety: ${score.overallScore}/100)';
      }
      return 'NAVGUARDIAN RECOMMENDS ROUTE (+$timeMins mins, Higher Safety: ${score.overallScore}/100)';
    }

    return 'Alternative Candidate (Rank #$rank · Safety: ${score.overallScore}/100)';
  }
}
