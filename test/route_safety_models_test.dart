import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/domain/route_safety_models.dart';

void main() {
  group('Route Safety Domain Models Tests', () {
    test('CongestionLevel categorizes delay ratio correctly', () {
      expect(CongestionLevel.fromDelayRatio(null), CongestionLevel.unknown);
      expect(CongestionLevel.fromDelayRatio(1.02), CongestionLevel.freeFlow);
      expect(CongestionLevel.fromDelayRatio(1.15), CongestionLevel.light);
      expect(CongestionLevel.fromDelayRatio(1.45), CongestionLevel.moderate);
      expect(CongestionLevel.fromDelayRatio(1.85), CongestionLevel.heavy);
      expect(CongestionLevel.fromDelayRatio(2.40), CongestionLevel.severe);
    });

    test('TrafficInfo calculates delay and delay ratio without fabrication', () {
      final traffic = TrafficInfo.calculate(
        staticSec: 600, // 10 minutes free flow
        trafficSec: 900, // 15 minutes in current traffic
        source: 'Google Routes (Live Traffic)',
      );

      expect(traffic.delaySeconds, 300);
      expect(traffic.delayRatio, 1.5);
      expect(traffic.congestionLevel, CongestionLevel.moderate);
      expect(traffic.isLive, true);
    });

    test('WeatherInfo interprets standard WMO weather codes and alerts', () {
      expect(WeatherInfo.describeWmoCode(0), 'Clear sky');
      expect(WeatherInfo.describeWmoCode(61), 'Rain (Slight to Heavy)');
      expect(WeatherInfo.describeWmoCode(95), 'Thunderstorm / Severe convective storm');
      expect(WeatherInfo.isSevereWmo(0), false);
      expect(WeatherInfo.isSevereWmo(95), true);
    });

    test('NormalizedRouteData aggregates segment flood and blackspot counts', () {
      final segment1 = RoadSegmentData(
        segmentId: 'seg_1',
        roadName: 'Hosur Road',
        startLat: 12.9176,
        startLon: 77.6238,
        endLat: 12.9080,
        endLon: 77.6250,
        polyline: const [(lat: 12.9176, lon: 77.6238)],
        distanceMeters: 1200,
        durationSeconds: 180,
        flood: const FloodRiskInfo(
          isHistoricalFloodProne: true,
          historicalSpotName: 'Central Silk Board',
          vulnerabilityRank: 'SEVERE',
        ),
        accident: const AccidentRiskInfo(
          isHistoricalBlackspot: true,
          blackspotName: 'Bommanahalli Junction',
          severity: AccidentSeverity.critical,
        ),
      );

      final segment2 = RoadSegmentData(
        segmentId: 'seg_2',
        roadName: 'Electronic City Flyover',
        startLat: 12.9080,
        startLon: 77.6250,
        endLat: 12.8450,
        endLon: 77.6600,
        polyline: const [(lat: 12.9080, lon: 77.6250)],
        distanceMeters: 9000,
        durationSeconds: 600,
      );

      final route = NormalizedRouteData(
        routeId: 'route_1',
        summary: 'via Hosur Rd',
        providerName: 'Google Routes (Live Traffic)',
        originName: 'Silk Board',
        destinationName: 'Electronic City',
        originLat: 12.9176,
        originLon: 77.6238,
        destinationLat: 12.8450,
        destinationLon: 77.6600,
        distanceMeters: 10200,
        staticDurationSeconds: 780,
        trafficDurationSeconds: 1100,
        fullPolyline: const [],
        segments: [segment1, segment2],
        sampleWeather: const WeatherInfo(
          temperatureC: 24.5,
          weatherDescription: 'Partly cloudy',
        ),
      );

      expect(route.detectedFloodSpotsCount, 1);
      expect(route.detectedAccidentBlackspotsCount, 1);
      expect(route.trafficDelaySeconds, 320);
      expect(route.overallCongestion, CongestionLevel.moderate);
    });
  });
}
