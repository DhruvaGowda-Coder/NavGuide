import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../../domain/telemetry.dart';

class JourneyStorage {
  const JourneyStorage();

  Future<Directory> getJourneysDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final journeysDir = Directory('${docsDir.path}/journeys');
    if (!await journeysDir.exists()) {
      await journeysDir.create(recursive: true);
    }
    return journeysDir;
  }

  Future<JourneySessionWriter> createSession(
    String journeyId,
    DateTime startTime,
  ) async {
    final baseDir = await getJourneysDirectory();
    final sessionDir = Directory('${baseDir.path}/$journeyId');
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }

    final gpsFile = File('${sessionDir.path}/gps.csv');
    final accelFile = File('${sessionDir.path}/accelerometer.csv');
    final gyroFile = File('${sessionDir.path}/gyroscope.csv');
    final magFile = File('${sessionDir.path}/magnetometer.csv');

    final gpsSink = gpsFile.openWrite();
    final accelSink = accelFile.openWrite();
    final gyroSink = gyroFile.openWrite();
    final magSink = magFile.openWrite();

    // Write CSV Headers
    gpsSink.writeln(
      'timestamp_iso,monotonic_micros,latitude,longitude,altitude_m,accuracy_m,speed_mps,heading_deg,is_mocked',
    );
    accelSink.writeln(
      'timestamp_iso,source_timestamp_iso,monotonic_micros,x_mps2,y_mps2,z_mps2',
    );
    gyroSink.writeln(
      'timestamp_iso,source_timestamp_iso,monotonic_micros,x_radps,y_radps,z_radps',
    );
    magSink.writeln(
      'timestamp_iso,source_timestamp_iso,monotonic_micros,x_uT,y_uT,z_uT',
    );

    return JourneySessionWriter(
      journeyId: journeyId,
      sessionDir: sessionDir,
      startTime: startTime,
      gpsSink: gpsSink,
      accelSink: accelSink,
      gyroSink: gyroSink,
      magSink: magSink,
    );
  }

  Future<List<JourneyMetadata>> listJourneys() async {
    final baseDir = await getJourneysDirectory();
    if (!await baseDir.exists()) return [];

    final list = <JourneyMetadata>[];
    await for (final entity in baseDir.list()) {
      if (entity is Directory) {
        final metaFile = File('${entity.path}/metadata.json');
        if (await metaFile.exists()) {
          try {
            final content = await metaFile.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            list.add(JourneyMetadata.fromJson(json));
          } catch (_) {
            // Ignore corrupted metadata files during listing
          }
        }
      }
    }
    list.sort((a, b) => b.startTime.compareTo(a.startTime));
    return list;
  }

  Future<bool> deleteJourney(String journeyId) async {
    final baseDir = await getJourneysDirectory();
    final sessionDir = Directory('${baseDir.path}/$journeyId');
    if (await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
      return true;
    }
    return false;
  }
}

class JourneySessionWriter {
  JourneySessionWriter({
    required this.journeyId,
    required this.sessionDir,
    required this.startTime,
    required this.gpsSink,
    required this.accelSink,
    required this.gyroSink,
    required this.magSink,
  });

  final String journeyId;
  final Directory sessionDir;
  final DateTime startTime;

  final IOSink gpsSink;
  final IOSink accelSink;
  final IOSink gyroSink;
  final IOSink magSink;

  int gpsCount = 0;
  int accelCount = 0;
  int gyroCount = 0;
  int magCount = 0;
  bool _isClosed = false;

  void writeGps(GeoFix fix, int monotonicMicros) {
    if (_isClosed) return;
    gpsCount++;
    gpsSink.writeln(
      '${fix.timestamp.toIso8601String()},$monotonicMicros,${fix.latitude},${fix.longitude},'
      '${fix.altitudeMeters ?? ""},${fix.accuracyMeters},${fix.speedMetersPerSecond ?? ""},'
      '${fix.headingDegrees ?? ""},${fix.isMocked}',
    );
  }

  void writeSensor(SensorSample sample) {
    if (_isClosed) return;
    final row =
        '${sample.receivedAt.toIso8601String()},${sample.sourceTimestamp.toIso8601String()},'
        '${sample.monotonicMicroseconds},${sample.x},${sample.y},${sample.z}';

    switch (sample.kind) {
      case SensorKind.accelerometer:
        accelCount++;
        accelSink.writeln(row);
      case SensorKind.gyroscope:
        gyroCount++;
        gyroSink.writeln(row);
      case SensorKind.magnetometer:
        magCount++;
        magSink.writeln(row);
    }
  }

  Future<JourneyMetadata> close({required DateTime endTime}) async {
    if (_isClosed) {
      final metaFile = File('${sessionDir.path}/metadata.json');
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        return JourneyMetadata.fromJson(
          jsonDecode(content) as Map<String, dynamic>,
        );
      }
    }
    _isClosed = true;

    await Future.wait([
      gpsSink.flush().then((_) => gpsSink.close()),
      accelSink.flush().then((_) => accelSink.close()),
      gyroSink.flush().then((_) => gyroSink.close()),
      magSink.flush().then((_) => magSink.close()),
    ]);

    final durationSec = endTime.difference(startTime).inSeconds;
    final meta = JourneyMetadata(
      id: journeyId,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: durationSec >= 0 ? durationSec : 0,
      gpsCount: gpsCount,
      accelCount: accelCount,
      gyroCount: gyroCount,
      magCount: magCount,
      directoryPath: sessionDir.path,
    );

    final metaFile = File('${sessionDir.path}/metadata.json');
    await metaFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
    );

    return meta;
  }
}
