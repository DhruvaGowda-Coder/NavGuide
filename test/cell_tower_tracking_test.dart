import 'package:flutter_test/flutter_test.dart';
import 'package:navguide/device/railway/train_tracking_engine.dart';
import 'package:navguide/device/telephony/cell_tower_service.dart';

void main() {
  test('CellTowerService matches train location along track corridor', () {
    const route = TrainRoute(
      trainNumber: '12657',
      trainName: 'Bengaluru - Chennai Central Mail',
      trainType: 'Superfast Mail',
      departureTime: '22:45',
      arrivalTime: '04:15',
      duration: '5h 30m',
      runningDays: 'Daily',
      halts: [
        StationHalt(
          station: RailwayStation(code: 'SBC', name: 'KSR Bengaluru', city: 'Bengaluru', state: 'Karnataka', zone: 'SWR', latitude: 12.9781, longitude: 77.5696),
          arrivalTime: 'Source',
          departureTime: '22:45',
          haltMinutes: 0,
          platform: 'PF 1',
          distanceKm: 0.0,
        ),
        StationHalt(
          station: RailwayStation(code: 'BNC', name: 'Bengaluru Cant', city: 'Bengaluru', state: 'Karnataka', zone: 'SWR', latitude: 12.9934, longitude: 77.5983),
          arrivalTime: '22:54',
          departureTime: '22:56',
          haltMinutes: 2,
          platform: 'PF 2',
          distanceKm: 4.4,
        ),
        StationHalt(
          station: RailwayStation(code: 'KJM', name: 'Krishnarajapuram', city: 'Bengaluru', state: 'Karnataka', zone: 'SWR', latitude: 13.0012, longitude: 77.6766),
          arrivalTime: '23:08',
          departureTime: '23:10',
          haltMinutes: 2,
          platform: 'PF 2',
          distanceKm: 14.1,
        ),
        StationHalt(
          station: RailwayStation(code: 'BWT', name: 'Bangarapet', city: 'Bangarapet', state: 'Karnataka', zone: 'SWR', latitude: 12.9935, longitude: 78.1966),
          arrivalTime: '23:58',
          departureTime: '00:01',
          haltMinutes: 2,
          platform: 'PF 3',
          distanceKm: 70.0,
        ),
        StationHalt(
          station: RailwayStation(code: 'MAS', name: 'Chennai Central', city: 'Chennai', state: 'Tamil Nadu', zone: 'SR', latitude: 13.0827, longitude: 80.2707),
          arrivalTime: '04:15',
          departureTime: 'Dest',
          haltMinutes: 0,
          platform: 'PF 4',
          distanceKm: 357.0,
        ),
      ],
    );

    // 1. Test when phone connects to tower near Bangarapet (within 1km)
    final matchAtBwt = CellTowerService.calculatePositionOnRoute(
      route: route,
      towerLat: 12.9950,
      towerLon: 78.1950,
    );
    expect(matchAtBwt, isNotNull);
    expect(matchAtBwt!.stationCode, 'BWT');
    expect(matchAtBwt.isAtStation, isTrue);
    expect(matchAtBwt.stationIndex, 3);

    // 2. Test when phone connects to tower between KJM (km 14.1) and BWT (km 70.0) near Malur
    final matchMidway = CellTowerService.calculatePositionOnRoute(
      route: route,
      towerLat: 13.0030,
      towerLon: 77.9380,
    );
    expect(matchMidway, isNotNull);
    expect(matchMidway!.stationIndex, 2); // Departed KJM
    expect(matchMidway.isAtStation, isFalse);
    expect(matchMidway.stationCode, 'BWT'); // Next station is BWT
    expect(matchMidway.distanceToNextKm, greaterThan(15.0));
    expect(matchMidway.distanceToNextKm, lessThan(45.0));
  });
}
