import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/device/dead_reckoning/dead_reckoning_engine.dart';
import 'package:navguardian_ai/device/fusion/ekf_sensor_fusion_engine.dart';
import 'package:navguardian_ai/domain/telemetry.dart';

void main() {
  group('EkfSensorFusionEngine Tests', () {
    test('Initializes with GPS and establishes anchor', () {
      final ekf = EkfSensorFusionEngine();
      final fix = GeoFix(
        latitude: 12.9384,
        longitude: 77.5611,
        accuracyMeters: 5.0,
        speedMetersPerSecond: 1.5,
        headingDegrees: 90.0,
        timestamp: DateTime.parse('2026-09-08T12:00:00Z'),
      );

      ekf.initializeWithGps(fix, monotonicMicros: 0);

      expect(ekf.isInitialized, isTrue);
      expect(ekf.currentLatitude, closeTo(12.9384, 1e-6));
      expect(ekf.currentLongitude, closeTo(77.5611, 1e-6));
      expect(ekf.currentHeadingDegrees, closeTo(90.0, 0.1));
      expect(ekf.currentSpeedMps, closeTo(1.5, 0.1));
      expect(ekf.positionStdDevMeters, greaterThan(0.0));
    });

    test('Stationary ZUPT keeps EKF drift minimal during stationary intervals', () {
      final ekf = EkfSensorFusionEngine();
      final initialFix = GeoFix(
        latitude: 12.9384,
        longitude: 77.5611,
        accuracyMeters: 5.0,
        timestamp: DateTime.parse('2026-09-08T12:00:00Z'),
      );

      ekf.initializeWithGps(initialFix, monotonicMicros: 0);

      // Feed 50 stationary samples
      for (var i = 1; i <= 50; i++) {
        final tMicros = i * 20000; // 50 Hz
        ekf.addSensor(
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

      final drift = GeodesyUtils.haversineDistanceMeters(
        initialFix.latitude,
        initialFix.longitude,
        ekf.currentLatitude,
        ekf.currentLongitude,
      );

      expect(drift, lessThan(0.2));
      expect(ekf.diagnostics.isStationary, isTrue);
    });

    test('GPS measurement update reduces position covariance', () {
      final ekf = EkfSensorFusionEngine();
      final initialFix = GeoFix(
        latitude: 12.9384,
        longitude: 77.5611,
        accuracyMeters: 10.0,
        timestamp: DateTime.parse('2026-09-08T12:00:00Z'),
      );
      ekf.initializeWithGps(initialFix, monotonicMicros: 0);

      // After some IMU prediction steps, covariance grows
      for (var i = 1; i <= 10; i++) {
        ekf.addSensor(
          SensorSample(
            kind: SensorKind.accelerometer,
            x: 0.2,
            y: 0.0,
            z: 9.81,
            sourceTimestamp: DateTime.parse('2026-09-08T12:00:00Z'),
            receivedAt: DateTime.parse('2026-09-08T12:00:00Z'),
            monotonicMicroseconds: i * 20000,
          ),
        );
      }

      final covBeforeGps = ekf.positionStdDevMeters;

      // High-accuracy GPS arrives
      final updatedFix = GeoFix(
        latitude: 12.9385,
        longitude: 77.5612,
        accuracyMeters: 2.0,
        speedMetersPerSecond: 1.0,
        headingDegrees: 45.0,
        timestamp: DateTime.parse('2026-09-08T12:00:01Z'),
      );
      ekf.addFix(updatedFix);

      final covAfterGps = ekf.positionStdDevMeters;

      // Covariance must be reduced by measurement update
      expect(covAfterGps, lessThan(covBeforeGps));
    });

    test('Magnetometer outlier rejection drops magnetic anomaly samples', () {
      final ekf = EkfSensorFusionEngine();
      final fix = GeoFix(
        latitude: 12.9384,
        longitude: 77.5611,
        accuracyMeters: 5.0,
        timestamp: DateTime.parse('2026-09-08T12:00:00Z'),
      );
      ekf.initializeWithGps(fix, monotonicMicros: 0);

      // Distorted sample (norm = sqrt(150^2 + 150^2) = 212 microtesla >> 72)
      ekf.addSensor(
        SensorSample(
          kind: SensorKind.magnetometer,
          x: 150.0,
          y: 150.0,
          z: 0.0,
          sourceTimestamp: DateTime.parse('2026-09-08T12:00:00Z'),
          receivedAt: DateTime.parse('2026-09-08T12:00:00Z'),
          monotonicMicroseconds: 20000,
        ),
      );

      expect(ekf.diagnostics.magAnomaliesCount, equals(1));
    });
  });
}
