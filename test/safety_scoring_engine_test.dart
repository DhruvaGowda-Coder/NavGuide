import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/domain/route_safety_models.dart';
import 'package:navguardian_ai/domain/safety_scoring_models.dart';
import 'package:navguardian_ai/device/safety_scoring/safety_scoring_engine.dart';
import 'package:navguardian_ai/device/safety_scoring/bayesian_route_risk_evaluator.dart';

void main() {
  const engine = SafetyScoringEngine();
  const bayesian = BayesianRouteRiskEvaluator();

  group('Phase 7: Segment Risk Normalization Tests', () {
    test('Calculates normalized segment risk between 0.0 and 1.0', () {
      final safeSegment = RoadSegmentData(
        segmentId: 'seg_safe',
        roadName: 'Outer Ring Road Safe Section',
        startLat: 12.92,
        startLon: 77.63,
        endLat: 12.93,
        endLon: 77.64,
        polyline: [(lat: 12.92, lon: 77.63), (lat: 12.93, lon: 77.64)],
        distanceMeters: 1000,
        durationSeconds: 60,
        traffic: const TrafficInfo(
          congestionLevel: CongestionLevel.freeFlow,
          delayRatio: 1.0,
          delaySeconds: 0,
          isLive: true,
        ),
        weather: const WeatherInfo(
          rainfallMmPerHour: 0.0,
          precipitationProbabilityPercent: 10,
          isLive: true,
        ),
        flood: const FloodRiskInfo(
          isHistoricalFloodProne: false,
          vulnerabilityRank: 'NONE',
        ),
        accident: const AccidentRiskInfo(
          isHistoricalBlackspot: false,
          severity: AccidentSeverity.none,
        ),
        roadCondition: const RoadConditionInfo(
          condition: RoadCondition.good,
        ),
        construction: const ConstructionInfo(
          status: ConstructionStatus.noneReported,
        ),
      );

      final profile = engine.evaluateSegment(safeSegment);

      expect(profile.compositeRisk, greaterThanOrEqualTo(0.0));
      expect(profile.compositeRisk, lessThanOrEqualTo(1.0));
      expect(profile.compositeRisk, lessThan(0.20)); // High safety = low risk
      expect(profile.isCriticalHazard, isFalse);
      expect(profile.dataConfidence, equals(DataConfidence.high));
    });

    test('High hazard segment produces high normalized composite risk', () {
      final hazardSegment = RoadSegmentData(
        segmentId: 'seg_hazard',
        roadName: 'Silk Board Flooded Underpass',
        startLat: 12.91,
        startLon: 77.62,
        endLat: 12.92,
        endLon: 77.63,
        polyline: [(lat: 12.91, lon: 77.62), (lat: 12.92, lon: 77.63)],
        distanceMeters: 800,
        durationSeconds: 300,
        traffic: const TrafficInfo(
          congestionLevel: CongestionLevel.severe,
          delayRatio: 2.8,
          delaySeconds: 200,
          isLive: true,
        ),
        weather: const WeatherInfo(
          rainfallMmPerHour: 18.0, // Heavy rain
          precipitationProbabilityPercent: 95,
          isSevereWeatherAlert: true,
          isLive: true,
        ),
        flood: const FloodRiskInfo(
          isHistoricalFloodProne: true,
          historicalSpotName: 'Central Silk Board Junction',
          vulnerabilityRank: 'SEVERE',
        ),
        accident: const AccidentRiskInfo(
          isHistoricalBlackspot: true,
          severity: AccidentSeverity.high,
          fatalitiesPast3Yr: 4,
        ),
        roadCondition: const RoadConditionInfo(
          condition: RoadCondition.potholeProne,
        ),
      );

      final profile = engine.evaluateSegment(hazardSegment);

      expect(profile.compositeRisk, greaterThan(0.70));
      expect(profile.isCriticalHazard, isTrue); // Severe flood + torrential rain
      expect(profile.explanations, isNotEmpty);
    });
  });

  group('Phase 7: Route Safety Score & Peak Hazard Integration', () {
    test('Peak Hazard Penalty prevents benign highway miles from masking a localized death-trap', () {
      // 9 safe highway segments (9 km total)
      final safeSegments = List.generate(
        9,
        (i) => RoadSegmentData(
          segmentId: 'highway_$i',
          roadName: 'Safe Elevated Expressway $i',
          startLat: 12.80 + i * 0.01,
          startLon: 77.60 + i * 0.01,
          endLat: 12.81 + i * 0.01,
          endLon: 77.61 + i * 0.01,
          polyline: [(lat: 12.80 + i * 0.01, lon: 77.60 + i * 0.01), (lat: 12.81 + i * 0.01, lon: 77.61 + i * 0.01)],
          distanceMeters: 1000,
          durationSeconds: 60,
          traffic: const TrafficInfo(congestionLevel: CongestionLevel.freeFlow, delayRatio: 1.0, isLive: true),
          weather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
          flood: const FloodRiskInfo(isHistoricalFloodProne: false),
          accident: const AccidentRiskInfo(isHistoricalBlackspot: false),
          roadCondition: const RoadConditionInfo(condition: RoadCondition.good),
        ),
      );

      // 1 dangerous segment with critical accident blackspot (1 km)
      final lethalSegment = RoadSegmentData(
        segmentId: 'trap_segment',
        roadName: 'Lethal Blackspot Chokepoint',
        startLat: 12.90,
        startLon: 77.70,
        endLat: 12.91,
        endLon: 77.71,
        polyline: [(lat: 12.90, lon: 77.70), (lat: 12.91, lon: 77.71)],
        distanceMeters: 1000,
        durationSeconds: 120,
        traffic: const TrafficInfo(congestionLevel: CongestionLevel.moderate, delayRatio: 1.4, isLive: true),
        weather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
        flood: const FloodRiskInfo(isHistoricalFloodProne: false),
        accident: const AccidentRiskInfo(
          isHistoricalBlackspot: true,
          severity: AccidentSeverity.critical,
          fatalitiesPast3Yr: 8,
        ),
        roadCondition: const RoadConditionInfo(condition: RoadCondition.potholeProne),
      );

      final routeWithHazard = NormalizedRouteData(
        routeId: 'route_with_trap',
        summary: 'Elevated Expressway with Chokepoint',
        providerName: 'Google Routes',
        originName: 'A',
        destinationName: 'B',
        originLat: 12.80,
        originLon: 77.60,
        destinationLat: 12.91,
        destinationLon: 77.71,
        distanceMeters: 10000,
        staticDurationSeconds: 660,
        trafficDurationSeconds: 660,
        fullPolyline: [],
        segments: [...safeSegments, lethalSegment],
        sampleWeather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
      );

      final score = engine.evaluateRoute(routeWithHazard);

      // Because of the peak-hazard penalty (35% weight on max segment risk),
      // the route score is heavily degraded rather than averaging out to ~90/100!
      expect(score.overallScore, lessThan(78));
      expect(score.peakHazardRisk, greaterThan(0.40));
    });

    test('Critical Hazard Override marks road closure as AVOID and penalizes score', () {
      final closedSegment = RoadSegmentData(
        segmentId: 'closed_seg',
        roadName: 'Underpass Road Closed',
        startLat: 12.95,
        startLon: 77.60,
        endLat: 12.96,
        endLon: 77.61,
        polyline: [(lat: 12.95, lon: 77.60), (lat: 12.96, lon: 77.61)],
        distanceMeters: 500,
        durationSeconds: 60,
        construction: const ConstructionInfo(
          status: ConstructionStatus.closure,
          details: 'Submerged underpass road closure',
        ),
      );

      final route = NormalizedRouteData(
        routeId: 'route_closed',
        summary: 'Direct Underpass Route',
        providerName: 'OSRM Engine',
        originName: 'City Station',
        destinationName: 'North Gate',
        originLat: 12.95,
        originLon: 77.60,
        destinationLat: 12.96,
        destinationLon: 77.61,
        distanceMeters: 2000,
        staticDurationSeconds: 300,
        trafficDurationSeconds: 300,
        fullPolyline: [],
        segments: [closedSegment],
        sampleWeather: const WeatherInfo.unknown,
      );

      final score = engine.evaluateRoute(route);

      expect(score.criticalOverride, isTrue);
      expect(score.recommendationStatus, equals(RecommendationStatus.avoid));
      expect(score.overallScore, lessThanOrEqualTo(35));
      expect(score.criticalOverrideReason, contains('Confirmed road closure'));
    });
  });

  group('Phase 7: Multi-Objective Route Ranking & Mode Switching', () {
    final safeLongRoute = NormalizedRouteData(
      routeId: 'route_safe_long',
      summary: 'Outer Ring Road Perimeter',
      providerName: 'Google Routes',
      originName: 'Origin',
      destinationName: 'Destination',
      originLat: 12.90,
      originLon: 77.60,
      destinationLat: 12.98,
      destinationLon: 77.70,
      distanceMeters: 14000, // +3 km
      staticDurationSeconds: 1500, // 25 mins (+4 mins vs shortcut)
      trafficDurationSeconds: 1500,
      fullPolyline: [],
      segments: List.generate(
        5,
        (i) => RoadSegmentData(
          segmentId: 'safe_$i',
          roadName: 'Perimeter Safe Highway $i',
          startLat: 12.90 + i * 0.01,
          startLon: 77.60 + i * 0.01,
          endLat: 12.91 + i * 0.01,
          endLon: 77.61 + i * 0.01,
          polyline: [(lat: 12.90 + i * 0.01, lon: 77.60 + i * 0.01), (lat: 12.91 + i * 0.01, lon: 77.61 + i * 0.01)],
          distanceMeters: 2800,
          durationSeconds: 300,
          traffic: const TrafficInfo(congestionLevel: CongestionLevel.freeFlow, delayRatio: 1.0, isLive: true),
          weather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
          flood: const FloodRiskInfo(isHistoricalFloodProne: false),
          accident: const AccidentRiskInfo(isHistoricalBlackspot: false),
          roadCondition: const RoadConditionInfo(condition: RoadCondition.good),
        ),
      ),
      sampleWeather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
    );

    final riskyShortRoute = NormalizedRouteData(
      routeId: 'route_risky_short',
      summary: 'Direct Dense City Cut',
      providerName: 'OSRM Engine',
      originName: 'Origin',
      destinationName: 'Destination',
      originLat: 12.90,
      originLon: 77.60,
      destinationLat: 12.98,
      destinationLon: 77.70,
      distanceMeters: 11000, // 11 km (Shorter)
      staticDurationSeconds: 1260, // 21 mins (4 mins faster)
      trafficDurationSeconds: 1260,
      fullPolyline: [],
      segments: List.generate(
        4,
        (i) => RoadSegmentData(
          segmentId: 'risky_$i',
          roadName: 'Congested Chokepoint $i',
          startLat: 12.90 + i * 0.02,
          startLon: 77.60 + i * 0.02,
          endLat: 12.92 + i * 0.02,
          endLon: 77.62 + i * 0.02,
          polyline: [(lat: 12.90 + i * 0.02, lon: 77.60 + i * 0.02), (lat: 12.92 + i * 0.02, lon: 77.62 + i * 0.02)],
          distanceMeters: 2750,
          durationSeconds: 315,
          traffic: const TrafficInfo(congestionLevel: CongestionLevel.heavy, delayRatio: 1.8, isLive: true),
          weather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
          flood: const FloodRiskInfo(
            isHistoricalFloodProne: true,
            historicalSpotName: 'Waterlogged Junction',
            vulnerabilityRank: 'HIGH',
          ),
          accident: const AccidentRiskInfo(
            isHistoricalBlackspot: true,
            severity: AccidentSeverity.high,
            fatalitiesPast3Yr: 5,
          ),
          roadCondition: const RoadConditionInfo(condition: RoadCondition.potholeProne),
        ),
      ),
      sampleWeather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
    );

    test('Balanced Mode recommends the safer route when time penalty is minor (+4 mins for +40 safety score)', () {
      final ranked = engine.rankRoutes([riskyShortRoute, safeLongRoute], mode: ScoringMode.balanced);

      expect(ranked.first.route.routeId, equals('route_safe_long'));
      expect(ranked.first.isRecommended, isTrue);
      expect(ranked.first.safetyScore.overallScore, greaterThan(ranked[1].safetyScore.overallScore));
      expect(ranked.first.recommendationHeadline, contains('RECOMMENDS'));
    });

    test('Fastest Mode prioritizes the faster route unless critical hazard override triggers', () {
      final ranked = engine.rankRoutes([safeLongRoute, riskyShortRoute], mode: ScoringMode.fastest);

      // In Fastest Mode with no hard closure, the faster route is prioritized
      expect(ranked.first.route.routeId, equals('route_risky_short'));
      expect(ranked.first.timeDeltaSeconds, equals(0)); // fastest
    });

    test('Safest Mode strongly favors maximum safety and highlights safety margin', () {
      final ranked = engine.rankRoutes([riskyShortRoute, safeLongRoute], mode: ScoringMode.safest);

      expect(ranked.first.route.routeId, equals('route_safe_long'));
      expect(ranked.first.safetyScore.overallScore, greaterThan(80));
    });
  });

  group('Phase 7: Data Confidence & Missing Value Accountability', () {
    test('Untraversed routes with missing fields receive LOW or MEDIUM confidence, never assumed safe', () {
      final unknownSegment = RoadSegmentData(
        segmentId: 'seg_unknown',
        roadName: 'Unmapped Rural Connecting Link',
        startLat: 13.0,
        startLon: 77.5,
        endLat: 13.01,
        endLon: 77.51,
        polyline: [(lat: 13.0, lon: 77.5), (lat: 13.01, lon: 77.51)],
        distanceMeters: 1000,
        durationSeconds: 100,
        traffic: TrafficInfo.unknown,
        weather: WeatherInfo.unknown,
        flood: FloodRiskInfo.unknown,
        accident: AccidentRiskInfo.unknown,
        roadCondition: RoadConditionInfo.unknown,
        construction: ConstructionInfo.unknown,
      );

      final route = NormalizedRouteData(
        routeId: 'route_unknown',
        summary: 'Unknown Link',
        providerName: 'OSRM Engine',
        originName: 'Origin',
        destinationName: 'Dest',
        originLat: 13.0,
        originLon: 77.5,
        destinationLat: 13.01,
        destinationLon: 77.51,
        distanceMeters: 1000,
        staticDurationSeconds: 100,
        trafficDurationSeconds: 100,
        fullPolyline: [],
        segments: [unknownSegment],
        sampleWeather: WeatherInfo.unknown,
      );

      final score = engine.evaluateRoute(route);

      expect(score.dataConfidence, equals(DataConfidence.low));
      expect(score.confidenceScore, lessThan(0.55));
      // Unknown data is penalized with uncertainty and NOT assumed to be 100% safe!
      expect(score.overallScore, lessThan(75));
    });
  });

  group('Phase 7: AI Bayesian Route Risk Model Verification', () {
    test('Bayesian model outputs incident probability and aligns with baseline ranking', () {
      final safeRoute = NormalizedRouteData(
        routeId: 'bayesian_safe',
        summary: 'Safe Boulevard',
        providerName: 'Google',
        originName: 'A',
        destinationName: 'B',
        originLat: 12.9,
        originLon: 77.6,
        destinationLat: 12.91,
        destinationLon: 77.61,
        distanceMeters: 2000,
        staticDurationSeconds: 180,
        trafficDurationSeconds: 180,
        fullPolyline: [],
        segments: [
          RoadSegmentData(
            segmentId: 'b_seg1',
            roadName: 'Smooth Boulevard',
            startLat: 12.9,
            startLon: 77.6,
            endLat: 12.91,
            endLon: 77.61,
            polyline: [(lat: 12.9, lon: 77.6), (lat: 12.91, lon: 77.61)],
            distanceMeters: 2000,
            durationSeconds: 180,
            traffic: const TrafficInfo(congestionLevel: CongestionLevel.freeFlow, delayRatio: 1.0, isLive: true),
            weather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
            flood: const FloodRiskInfo(isHistoricalFloodProne: false),
            accident: const AccidentRiskInfo(isHistoricalBlackspot: false),
            roadCondition: const RoadConditionInfo(condition: RoadCondition.good),
          ),
        ],
        sampleWeather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
      );

      final bayesianResult = bayesian.evaluateRouteBayesian(safeRoute);
      final baselineScore = engine.evaluateRoute(safeRoute);
      final comparison = bayesian.compareWithBaseline(safeRoute, baselineScore);

      expect(bayesianResult.bayesianSafetyScore, greaterThan(80));
      expect(bayesianResult.routeIncidentProbability, lessThan(0.15));
      expect(comparison['agreement'], equals('HIGH_AGREEMENT'));
    });

    test('Phase 8 ML blueprint defines required crowdsourced training schema', () {
      expect(BayesianRouteRiskEvaluator.kPhase8MlBlueprint['targetVariable'], isNotEmpty);
      expect(BayesianRouteRiskEvaluator.kPhase8MlBlueprint['featureVectors'], isNotEmpty);
      expect((BayesianRouteRiskEvaluator.kPhase8MlBlueprint['featureVectors'] as List).length, greaterThanOrEqualTo(10));
    });
  });
}
