import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/device/safety_data/flood_data_provider.dart';
import 'package:navguardian_ai/device/safety_data/accident_data_provider.dart';
import 'package:navguardian_ai/device/safety_data/road_condition_provider.dart';
import 'package:navguardian_ai/device/safety_data/route_provider.dart';
import 'package:navguardian_ai/domain/route_safety_models.dart';

const String kMockFloodSpotsJson = '''
{
  "flood_spots": [
    {
      "id": "blr_flood_01",
      "name": "Central Silk Board Junction",
      "latitude": 12.9176,
      "longitude": 77.6238,
      "buffer_radius_meters": 250,
      "vulnerability_level": "SEVERE",
      "historical_waterlog_depth_cm": 60,
      "corridor": "Hosur Road",
      "terrain": "Depression"
    }
  ]
}
''';

const String kMockAccidentBlackspotsJson = '''
{
  "accident_blackspots": [
    {
      "id": "blr_acc_01",
      "name": "Hosur Road - Kudlu Gate Junction",
      "latitude": 12.8905,
      "longitude": 77.6435,
      "buffer_radius_meters": 250,
      "historical_severity": "CRITICAL",
      "fatalities_past_3yr": 18,
      "road_name": "NH-44",
      "junction_type": "Signalized Highway Intersection",
      "risk_factors": "Speeding"
    }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Safety Data Providers Integration Tests', () {
    test('FloodDataProvider matches registered BBMP flood spot within buffer', () async {
      final provider = FloodDataProvider();
      await provider.initialize(jsonString: kMockFloodSpotsJson);

      // Coordinates directly at Silk Board
      final match = await provider.evaluateLocation(
        latitude: 12.9178,
        longitude: 77.6240,
        activeRainfallMm: 6.0,
      );

      expect(match.isHistoricalFloodProne, true);
      expect(match.historicalSpotName, 'Central Silk Board Junction');
      expect(match.vulnerabilityRank, 'SEVERE');
      expect(match.category, FloodRiskCategory.observed); // High rain triggers observed

      // Coordinates 5km away (no flood spot)
      final noMatch = await provider.evaluateLocation(
        latitude: 12.9716,
        longitude: 77.5946,
      );

      expect(noMatch.isHistoricalFloodProne, false);
      expect(noMatch.vulnerabilityRank, 'NONE');
    });

    test('AccidentDataProvider flags official MoRTH blackspot corridor', () async {
      final provider = AccidentDataProvider();
      await provider.initialize(jsonString: kMockAccidentBlackspotsJson);

      // Coordinates at Kudlu Gate
      final match = await provider.evaluateLocation(
        latitude: 12.8908,
        longitude: 77.6432,
      );

      expect(match.isHistoricalBlackspot, true);
      expect(match.blackspotName, 'Hosur Road - Kudlu Gate Junction');
      expect(match.severity, AccidentSeverity.critical);
      expect(match.fatalitiesPast3Yr, 18);

      // Coordinates distant from Kudlu Gate
      final noMatch = await provider.evaluateLocation(
        latitude: 13.0358,
        longitude: 77.5970,
      );

      expect(noMatch.isHistoricalBlackspot, false);
      expect(noMatch.severity, AccidentSeverity.none);
    });

    test('RoadConditionProvider returns unknown for untraversed segments without inventing potholes', () async {
      final provider = RoadConditionProvider();

      final cond = await provider.evaluateLocation(
        latitude: 13.0500,
        longitude: 77.6000,
      );

      expect(cond.condition, RoadCondition.unknown);
      expect(cond.source, 'None (Untraversed)');
    });

    test('PolylineUtils decodes standard Google encoded polyline correctly', () {
      // Encoded polyline for a short straight line
      const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
      final decoded = PolylineUtils.decodePolyline(encoded);

      expect(decoded.isNotEmpty, true);
      expect(decoded.length, 3);
      expect(decoded.first.lat, closeTo(38.5, 0.1));
      expect(decoded.first.lon, closeTo(-120.2, 0.1));
    });
  });
}
