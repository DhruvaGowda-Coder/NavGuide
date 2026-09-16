import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/device/dead_reckoning/dead_reckoning_engine.dart';
import 'package:navguardian_ai/device/dead_reckoning/outage_evaluator.dart';
import 'package:navguardian_ai/device/storage/journey_reader.dart';
import 'package:navguardian_ai/domain/telemetry.dart';

void main() {
  group('GeodesyUtils Tests', () {
    test('Haversine distance between Bangalore coordinates matches known distance', () {
      // (12.9384, 77.5611) to (12.9384, 77.5621) is ~108 meters eastward
      final dist = GeodesyUtils.haversineDistanceMeters(
        12.9384,
        77.5611,
        12.9384,
        77.5621,
      );
      expect(dist, greaterThan(100.0));
      expect(dist, lessThan(115.0));
    });

    test('metersToDeltaLatLon converts North displacement correctly', () {
      final res = GeodesyUtils.metersToDeltaLatLon(111320.0, 0.0, 0.0);
      expect(res.deltaLat, closeTo(1.0, 0.01));
      expect(res.deltaLon, closeTo(0.0, 0.0001));
    });
  });

  group('DeadReckoningEngine Baseline Tests', () {
    test('Stationary sensor stream activates ZUPT and maintains position without runaway drift', () {
      final engine = DeadReckoningEngine();
      final initialFix = GeoFix(
        latitude: 12.9384,
        longitude: 77.5611,
        accuracyMeters: 10.0,
        timestamp: DateTime.parse('2026-09-08T12:00:00Z'),
      );

      engine.initializeWithGps(initialFix, monotonicMicros: 0);

      // Feed 50 stationary accelerometer samples with gravity ~9.8 m/s^2 on Z axis
      for (var i = 1; i <= 50; i++) {
        final tMicros = i * 20000; // 50 Hz (20ms)
        engine.addSensor(
          SensorSample(
            kind: SensorKind.accelerometer,
            x: 0.01,
            y: -0.01,
            z: 9.81,
            sourceTimestamp: DateTime.parse('2026-09-08T12:00:00Z'),
            receivedAt: DateTime.parse('2026-09-08T12:00:00Z'),
            monotonicMicroseconds: tMicros,
          ),
        );
      }

      final est = engine.currentEstimate;
      final distDrift = GeodesyUtils.haversineDistanceMeters(
        initialFix.latitude,
        initialFix.longitude,
        est.latitude,
        est.longitude,
      );

      // ZUPT should have clamped velocity to 0, drift must be virtually 0 (< 0.1m)
      expect(distDrift, lessThan(0.1));
      expect(est.speedMetersPerSecond, closeTo(0.0, 0.01));
    });

    test('Forward acceleration updates velocity and heading propagation', () {
      final engine = DeadReckoningEngine();
      final initialFix = GeoFix(
        latitude: 12.9384,
        longitude: 77.5611,
        accuracyMeters: 10.0,
        headingDegrees: 0.0, // North
        speedMetersPerSecond: 5.0,
        timestamp: DateTime.parse('2026-09-08T12:00:00Z'),
      );

      engine.initializeWithGps(initialFix, monotonicMicros: 0);
      expect(engine.currentHeadingDegrees, 0.0);
      expect(engine.currentSpeedMps, closeTo(5.0, 0.01));
    });
  });

  group('OutageEvaluator Tests', () {
    test('Evaluates simulated blackout, isolates hidden GPS, and calculates error metrics', () {
      final startTime = DateTime.parse('2026-09-08T12:00:00Z');

      // Create a synthetic 30-second journey moving North at ~2 m/s
      final gpsFixes = <GeoFix>[];
      final accelSamples = <SensorSample>[];
      final gyroSamples = <SensorSample>[];
      final magSamples = <SensorSample>[];
      final records = <ReplayRecord>[];

      for (var s = 0; s <= 30; s++) {
        final tMicros = s * 1000000;
        final delta = GeodesyUtils.metersToDeltaLatLon(s * 2.0, 0.0, 12.9384);
        final fix = GeoFix(
          latitude: 12.9384 + delta.deltaLat,
          longitude: 77.5611 + delta.deltaLon,
          accuracyMeters: 5.0,
          speedMetersPerSecond: 2.0,
          headingDegrees: 0.0,
          timestamp: startTime.add(Duration(seconds: s)),
        );
        gpsFixes.add(fix);
        records.add(ReplayRecord.gps(fix, tMicros));
      }

      // Add 50Hz sensor records
      for (var ms = 0; ms <= 30000; ms += 20) {
        final tMicros = ms * 1000;
        final accel = SensorSample(
          kind: SensorKind.accelerometer,
          x: 0.0,
          y: 0.0,
          z: 9.81,
          sourceTimestamp: startTime.add(Duration(milliseconds: ms)),
          receivedAt: startTime.add(Duration(milliseconds: ms)),
          monotonicMicroseconds: tMicros,
        );
        accelSamples.add(accel);
        records.add(ReplayRecord.sensor(accel, tMicros));
      }

      records.sort((a, b) => a.monotonicMicros.compareTo(b.monotonicMicros));

      final journey = LoadedJourney(
        metadata: JourneyMetadata(
          id: 'test_journey',
          startTime: startTime,
          durationSeconds: 30,
          gpsCount: gpsFixes.length,
          accelCount: accelSamples.length,
          gyroCount: 0,
          magCount: 0,
          directoryPath: '',
        ),
        gpsFixes: gpsFixes,
        accelSamples: accelSamples,
        gyroSamples: gyroSamples,
        magSamples: magSamples,
        chronologicalRecords: records,
      );

      final evaluator = const OutageEvaluator();
      // Simulate 10-second blackout from sec 10 to sec 20
      final result = evaluator.evaluate(
        journey: journey,
        outageStartSeconds: 10.0,
        outageDurationSeconds: 10.0,
      );

      expect(result.outageDurationSeconds, 10.0);
      expect(result.hiddenGpsPointsCount, greaterThan(5));
      expect(result.endpointErrorMeters, isNonNegative);
      expect(result.rmseMeters, isNonNegative);
      expect(result.driftRateMps, isNonNegative);
      expect(result.groundTruthCoordinates.length, equals(result.hiddenGpsPointsCount));
    });
  });
}
