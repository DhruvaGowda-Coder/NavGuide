import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/domain/crowdsourced_hazard_models.dart';
import 'package:navguardian_ai/domain/route_safety_models.dart';
import 'package:navguardian_ai/device/crowdsourcing/crowdsourced_hazard_service.dart';
import 'package:navguardian_ai/device/safety_scoring/safety_scoring_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 8 & 9: Crowdsourced Hazard Model & Reliability Tests', () {
    test('Calculates Laplace smoothed reliability score correctly', () {
      final report = CrowdsourcedHazardReport(
        id: 'test_1',
        hazardType: HazardType.flood,
        description: 'Water accumulation',
        latitude: 12.918,
        longitude: 77.624,
        roadName: 'Hosur Road',
        reportedAt: DateTime.now(),
        confirmationsCount: 4,
        rejectionsCount: 1,
      );

      // Laplace formula: (4 + 1) / (4 + 1 + 2) = 5 / 7 ≈ 0.714
      expect(report.reliabilityScore, closeTo(5.0 / 7.0, 0.001));
      expect(report.isCommunityConfirmed, isTrue);
    });

    test('Confirming increases reliability and rejecting decreases it', () {
      final report = CrowdsourcedHazardReport(
        id: 'test_2',
        hazardType: HazardType.pothole,
        description: 'Deep pothole',
        latitude: 12.935,
        longitude: 77.629,
        roadName: '100ft Rd',
        reportedAt: DateTime.now(),
        confirmationsCount: 1,
        rejectionsCount: 0,
      );

      final confirmed = report.copyWith(confirmationsCount: report.confirmationsCount + 2);
      expect(confirmed.confirmationsCount, equals(3));
      expect(confirmed.reliabilityScore, greaterThan(report.reliabilityScore));

      final rejected = confirmed.copyWith(rejectionsCount: 3);
      expect(rejected.reliabilityScore, lessThan(confirmed.reliabilityScore));
    });
  });

  group('Phase 8 & 9: Crowdsourced Hazard Service & Real Data Operations', () {
    final service = CrowdsourcedHazardService.instance;

    setUp(() async {
      await service.clearAllData();
    });

    test('Starts fresh with empty hazard database', () {
      final all = service.getAllHazards();
      expect(all, isEmpty);
    });

    test('Submits real user hazard and queries by proximity and polyline', () async {
      final report = await service.submitHazardReport(
        hazardType: HazardType.flood,
        description: 'Waterlogging on service road',
        latitude: 12.9176,
        longitude: 77.6238,
        roadName: 'Hosur Main Road',
        severity: 'HIGH',
      );

      expect(report.id, startsWith('cs_'));
      expect(service.getAllHazards().length, equals(1));
      expect(service.hasUserVoted(report.id), isTrue);

      // Proximity query (Silk Board coordinates)
      final near = service.getNearbyHazards(
        lat: 12.9176,
        lon: 77.6238,
        radiusMeters: 500,
      );
      expect(near.length, equals(1));
      expect(near.first.roadName, equals('Hosur Main Road'));

      // Polyline query
      final polyline = [
        (lat: 12.9170, lon: 77.6230),
        (lat: 12.9176, lon: 77.6238),
        (lat: 12.9185, lon: 77.6250),
      ];
      final alongPoly = service.getHazardsAlongPolyline(polyline, bufferMeters: 100);
      expect(alongPoly.length, equals(1));

      // Rejects double voting from same user
      final doubleVote = await service.confirmHazard(report.id);
      expect(doubleVote, isNull);
    });
  });

  group('Phase 8 & 9: Safety Scoring Engine Integration', () {
    const engine = SafetyScoringEngine();

    test('Confirmed crowdsourced road blockage marks segment as Critical Hazard Override', () {
      final blockedReport = CrowdsourcedHazardReport(
        id: 'block_1',
        hazardType: HazardType.roadBlocked,
        description: 'Fallen tree blocking entire carriageway',
        latitude: 12.950,
        longitude: 77.610,
        roadName: 'Inner Ring Road',
        reportedAt: DateTime.now(),
        confirmationsCount: 6,
        rejectionsCount: 0,
      );

      final segment = RoadSegmentData(
        segmentId: 'seg_block',
        roadName: 'Inner Ring Road',
        startLat: 12.950,
        startLon: 77.610,
        endLat: 12.955,
        endLon: 77.615,
        polyline: [(lat: 12.950, lon: 77.610), (lat: 12.955, lon: 77.615)],
        distanceMeters: 800,
        durationSeconds: 90,
        traffic: const TrafficInfo(congestionLevel: CongestionLevel.freeFlow, isLive: true),
        weather: const WeatherInfo(rainfallMmPerHour: 0.0, isLive: true),
        flood: const FloodRiskInfo(isHistoricalFloodProne: false, vulnerabilityRank: 'NONE'),
        accident: const AccidentRiskInfo(isHistoricalBlackspot: false, severity: AccidentSeverity.none),
        roadCondition: const RoadConditionInfo(condition: RoadCondition.good),
        construction: const ConstructionInfo(status: ConstructionStatus.noneReported),
        crowdsourcedHazards: [blockedReport],
      );

      final profile = engine.evaluateSegment(segment);
      expect(profile.isCriticalHazard, isTrue);
      expect(profile.criticalHazardReason, contains('Community confirmed road blockage'));
      expect(profile.explanations.any((e) => e.contains('ROAD BLOCKED')), isTrue);
    });
  });
}
