import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/device/safety_data/route_safety_data_service.dart';
import 'package:navguardian_ai/domain/route_safety_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RouteSafetyDataService enriches real Bangalore corridor with safety data layer', () async {
    final service = RouteSafetyDataService();

    // Silk Board to Electronic City corridor
    final routes = await service.fetchEnrichedRoutes(
      originLat: 12.9176,
      originLon: 77.6238,
      destLat: 12.8452,
      destLon: 77.6602,
      originName: 'Central Silk Board',
      destName: 'Electronic City',
    );

    expect(routes.isNotEmpty, true, reason: 'Must return at least 1 candidate route');

    final primaryRoute = routes.first;
    print('\n===== REAL ROUTE SAFETY DATA LAYER INSPECTION =====');
    print('Route ID: ${primaryRoute.routeId}');
    print('Provider: ${primaryRoute.providerName}');
    print('Summary: ${primaryRoute.summary}');
    print('Distance: ${(primaryRoute.distanceMeters / 1000).toStringAsFixed(1)} km');
    print('Static Duration: ${(primaryRoute.staticDurationSeconds / 60).toStringAsFixed(1)} min');
    print('Traffic Duration: ${(primaryRoute.trafficDurationSeconds / 60).toStringAsFixed(1)} min');
    print('Traffic Delay: +${(primaryRoute.trafficDelaySeconds / 60).toStringAsFixed(1)} min');
    print('Congestion Level: ${primaryRoute.overallCongestion.displayName}');
    print('Live Weather Description: ${primaryRoute.sampleWeather.weatherDescription}');
    print('Live Weather Temperature: ${primaryRoute.sampleWeather.temperatureC}°C');
    print('Live Weather Rain: ${primaryRoute.sampleWeather.rainfallMmPerHour} mm/hr');
    print('Live Weather Rain Prob: ${primaryRoute.sampleWeather.precipitationProbabilityPercent}%');
    print('Detected Flood Spots: ${primaryRoute.detectedFloodSpotsCount}');
    print('Detected Accident Blackspots: ${primaryRoute.detectedAccidentBlackspotsCount}');
    print('Total Segments: ${primaryRoute.segments.length}');
    print('Is Mock Data: ${primaryRoute.isMockData}');
    print('===================================================\n');

    expect(primaryRoute.distanceMeters > 5000, true);
    expect(primaryRoute.segments.isNotEmpty, true);
    expect(primaryRoute.isMockData, false);
    expect(primaryRoute.sampleWeather.isLive, true);
  });
}
