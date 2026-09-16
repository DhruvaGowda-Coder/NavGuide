import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/device/recorder/journey_recording_service.dart';
import 'package:navguardian_ai/device/storage/journey_storage.dart';
import 'package:navguardian_ai/domain/telemetry.dart';

class MockLocationService implements LocationService {
  final controller = StreamController<GeoFix>.broadcast();
  int subCount = 0;

  @override
  Stream<GeoFix> watch() {
    subCount++;
    return controller.stream;
  }

  @override
  Future<LocationAccess> access({required bool request}) async =>
      LocationAccess.granted;

  @override
  Stream<bool> serviceChanges() => const Stream.empty();

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class MockSensorService implements SensorService {
  final controllers = {
    SensorKind.accelerometer: StreamController<SensorSample>.broadcast(),
    SensorKind.gyroscope: StreamController<SensorSample>.broadcast(),
    SensorKind.magnetometer: StreamController<SensorSample>.broadcast(),
  };
  final subCounts = {
    SensorKind.accelerometer: 0,
    SensorKind.gyroscope: 0,
    SensorKind.magnetometer: 0,
  };

  @override
  Stream<SensorSample> watch(SensorKind kind) {
    subCounts[kind] = (subCounts[kind] ?? 0) + 1;
    return controllers[kind]!.stream;
  }
}

class TestJourneyStorage extends JourneyStorage {
  TestJourneyStorage(this.tempDir);
  final Directory tempDir;

  @override
  Future<Directory> getJourneysDirectory() async => tempDir;
}

void main() {
  late Directory tempDir;
  late TestJourneyStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('journey_test_');
    storage = TestJourneyStorage(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('JourneySessionWriter streams multi-frequency CSVs and metadata', () async {
    final start = DateTime.utc(2026, 9, 8, 12, 0, 0);
    final writer = await storage.createSession('test_journey_1', start);

    // Write 2 GPS fixes
    writer.writeGps(
      GeoFix(
        latitude: 12.93845,
        longitude: 77.56112,
        accuracyMeters: 5.2,
        altitudeMeters: 920.5,
        speedMetersPerSecond: 1.2,
        headingDegrees: 45.0,
        timestamp: start,
      ),
      1000000,
    );
    writer.writeGps(
      GeoFix(
        latitude: 12.93850,
        longitude: 77.56120,
        accuracyMeters: 4.8,
        altitudeMeters: 921.0,
        speedMetersPerSecond: 1.4,
        headingDegrees: 46.0,
        timestamp: start.add(const Duration(seconds: 1)),
      ),
      2000000,
    );

    // Write 5 Accelerometer samples
    for (var i = 0; i < 5; i++) {
      writer.writeSensor(
        SensorSample(
          kind: SensorKind.accelerometer,
          x: 0.1 * i,
          y: 9.8,
          z: 0.2,
          sourceTimestamp: start.add(Duration(milliseconds: 200 * i)),
          receivedAt: start.add(Duration(milliseconds: 200 * i)),
          monotonicMicroseconds: 200000 * i,
        ),
      );
    }

    // Write 3 Gyroscope samples
    for (var i = 0; i < 3; i++) {
      writer.writeSensor(
        SensorSample(
          kind: SensorKind.gyroscope,
          x: 0.01 * i,
          y: -0.02,
          z: 0.05,
          sourceTimestamp: start.add(Duration(milliseconds: 200 * i)),
          receivedAt: start.add(Duration(milliseconds: 200 * i)),
          monotonicMicroseconds: 200000 * i,
        ),
      );
    }

    // Write 4 Magnetometer samples
    for (var i = 0; i < 4; i++) {
      writer.writeSensor(
        SensorSample(
          kind: SensorKind.magnetometer,
          x: 25.0 + i,
          y: -10.0,
          z: 42.0,
          sourceTimestamp: start.add(Duration(milliseconds: 200 * i)),
          receivedAt: start.add(Duration(milliseconds: 200 * i)),
          monotonicMicroseconds: 200000 * i,
        ),
      );
    }

    final end = start.add(const Duration(seconds: 10));
    final meta = await writer.close(endTime: end);

    expect(meta.id, 'test_journey_1');
    expect(meta.gpsCount, 2);
    expect(meta.accelCount, 5);
    expect(meta.gyroCount, 3);
    expect(meta.magCount, 4);
    expect(meta.durationSeconds, 10);
    expect(meta.totalSamples, 14);

    // Verify files exist
    final sessionDir = Directory('${tempDir.path}/test_journey_1');
    expect(await sessionDir.exists(), isTrue);

    final gpsFile = File('${sessionDir.path}/gps.csv');
    expect(await gpsFile.exists(), isTrue);
    final gpsLines = await gpsFile.readAsLines();
    expect(gpsLines.length, 3); // header + 2 rows
    expect(gpsLines.first, contains('altitude_m'));
    expect(gpsLines[1], contains('12.93845,77.56112,920.5'));

    final accelFile = File('${sessionDir.path}/accelerometer.csv');
    final accelLines = await accelFile.readAsLines();
    expect(accelLines.length, 6); // header + 5 rows
    expect(accelLines.first, contains('monotonic_micros'));

    // Verify listing journeys
    final list = await storage.listJourneys();
    expect(list.length, 1);
    expect(list.first.id, 'test_journey_1');
    expect(list.first.gpsCount, 2);

    // Verify deleting journey
    final deleted = await storage.deleteJourney('test_journey_1');
    expect(deleted, isTrue);
    expect(await sessionDir.exists(), isFalse);
    expect((await storage.listJourneys()).isEmpty, isTrue);
  });

  test('JourneyRecordingService orchestrates streams and cancels cleanly', () async {
    final mockLocation = MockLocationService();
    final mockSensors = MockSensorService();

    final service = JourneyRecordingService(
      locationService: mockLocation,
      sensorService: mockSensors,
      storage: storage,
    );

    LiveRecordingStats? lastStats;
    service.onStatsUpdate = (s) => lastStats = s;

    final journeyId = await service.startJourney(customId: 'test_service_journey');
    expect(service.isRecording, isTrue);
    expect(service.activeJourneyId, journeyId);

    final now = DateTime.now().toUtc();

    // Emit 1 GPS fix
    mockLocation.controller.add(
      GeoFix(
        latitude: 12.0,
        longitude: 77.0,
        accuracyMeters: 10.0,
        altitudeMeters: 800.0,
        timestamp: now,
      ),
    );

    // Emit 3 accel, 2 gyro, 1 mag
    for (var i = 0; i < 3; i++) {
      mockSensors.controllers[SensorKind.accelerometer]!.add(
        SensorSample(
          kind: SensorKind.accelerometer,
          x: 0,
          y: 9.8,
          z: 0,
          sourceTimestamp: now,
          receivedAt: now,
          monotonicMicroseconds: i * 1000,
        ),
      );
    }
    for (var i = 0; i < 2; i++) {
      mockSensors.controllers[SensorKind.gyroscope]!.add(
        SensorSample(
          kind: SensorKind.gyroscope,
          x: 0,
          y: 0,
          z: 0,
          sourceTimestamp: now,
          receivedAt: now,
          monotonicMicroseconds: i * 1000,
        ),
      );
    }
    mockSensors.controllers[SensorKind.magnetometer]!.add(
      SensorSample(
        kind: SensorKind.magnetometer,
        x: 10,
        y: 20,
        z: 30,
        sourceTimestamp: now,
        receivedAt: now,
        monotonicMicroseconds: 0,
      ),
    );

    // Allow microtasks/event loop to process stream writes
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(lastStats?.gpsCount, 1);
    expect(lastStats?.accelCount, 3);
    expect(lastStats?.gyroCount, 2);
    expect(lastStats?.magCount, 1);

    final meta = await service.stopJourney();
    expect(service.isRecording, isFalse);
    expect(meta.id, 'test_service_journey');
    expect(meta.gpsCount, 1);
    expect(meta.accelCount, 3);
    expect(meta.gyroCount, 2);
    expect(meta.magCount, 1);

    await mockLocation.controller.close();
    for (final c in mockSensors.controllers.values) {
      await c.close();
    }
  });
}
