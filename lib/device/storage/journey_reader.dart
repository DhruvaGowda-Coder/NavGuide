import 'dart:convert';
import 'dart:io';

import '../../domain/telemetry.dart';

class ReplayRecord {
  const ReplayRecord.gps(this.fix, this.monotonicMicros)
      : sensor = null,
        isGps = true;

  const ReplayRecord.sensor(this.sensor, this.monotonicMicros)
      : fix = null,
        isGps = false;

  final GeoFix? fix;
  final SensorSample? sensor;
  final int monotonicMicros;
  final bool isGps;
}

class LoadedJourney {
  const LoadedJourney({
    required this.metadata,
    required this.gpsFixes,
    required this.accelSamples,
    required this.gyroSamples,
    required this.magSamples,
    required this.chronologicalRecords,
  });

  final JourneyMetadata metadata;
  final List<GeoFix> gpsFixes;
  final List<SensorSample> accelSamples;
  final List<SensorSample> gyroSamples;
  final List<SensorSample> magSamples;
  final List<ReplayRecord> chronologicalRecords;
}

class JourneyReader {
  const JourneyReader();

  Future<LoadedJourney> loadJourney(String journeyDirectoryPath) async {
    final dir = Directory(journeyDirectoryPath);
    if (!await dir.exists()) {
      throw FileSystemException('Journey directory does not exist', journeyDirectoryPath);
    }

    final metaFile = File('${dir.path}/metadata.json');
    if (!await metaFile.exists()) {
      throw FileSystemException('metadata.json not found in journey directory', metaFile.path);
    }
    final metaContent = await metaFile.readAsString();
    final metadata = JourneyMetadata.fromJson(jsonDecode(metaContent) as Map<String, dynamic>);

    final gpsList = <GeoFix>[];
    final accelList = <SensorSample>[];
    final gyroList = <SensorSample>[];
    final magList = <SensorSample>[];
    final records = <ReplayRecord>[];

    // 1. Read GPS
    final gpsFile = File('${dir.path}/gps.csv');
    if (await gpsFile.exists()) {
      final lines = await gpsFile.readAsLines();
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final parts = line.split(',');
        if (parts.length < 9) continue;

        final timestampIso = parts[0];
        final monotonicMicros = int.tryParse(parts[1]) ?? 0;
        final lat = double.tryParse(parts[2]) ?? 0.0;
        final lon = double.tryParse(parts[3]) ?? 0.0;
        final alt = double.tryParse(parts[4]);
        final acc = double.tryParse(parts[5]) ?? 10.0;
        final speed = double.tryParse(parts[6]);
        final heading = double.tryParse(parts[7]);
        final isMocked = parts[8].toLowerCase() == 'true';

        final fix = GeoFix(
          latitude: lat,
          longitude: lon,
          accuracyMeters: acc,
          timestamp: DateTime.tryParse(timestampIso) ?? DateTime.now(),
          altitudeMeters: alt,
          speedMetersPerSecond: speed,
          headingDegrees: heading,
          isMocked: isMocked,
        );
        gpsList.add(fix);
        records.add(ReplayRecord.gps(fix, monotonicMicros));
      }
    }

    // Helper for IMU CSVs
    Future<void> readImuFile(
      String filename,
      SensorKind kind,
      List<SensorSample> targetList,
    ) async {
      final file = File('${dir.path}/$filename');
      if (!await file.exists()) return;

      final lines = await file.readAsLines();
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final parts = line.split(',');
        if (parts.length < 6) continue;

        final receivedAt = DateTime.tryParse(parts[0]) ?? DateTime.now();
        final sourceTimestamp = DateTime.tryParse(parts[1]) ?? receivedAt;
        final monotonicMicros = int.tryParse(parts[2]) ?? 0;
        final x = double.tryParse(parts[3]) ?? 0.0;
        final y = double.tryParse(parts[4]) ?? 0.0;
        final z = double.tryParse(parts[5]) ?? 0.0;

        final sample = SensorSample(
          kind: kind,
          x: x,
          y: y,
          z: z,
          receivedAt: receivedAt,
          sourceTimestamp: sourceTimestamp,
          monotonicMicroseconds: monotonicMicros,
        );
        targetList.add(sample);
        records.add(ReplayRecord.sensor(sample, monotonicMicros));
      }
    }

    await Future.wait([
      readImuFile('accelerometer.csv', SensorKind.accelerometer, accelList),
      readImuFile('gyroscope.csv', SensorKind.gyroscope, gyroList),
      readImuFile('magnetometer.csv', SensorKind.magnetometer, magList),
    ]);

    // Sort unified records chronologically by monotonic timestamp
    records.sort((a, b) => a.monotonicMicros.compareTo(b.monotonicMicros));

    return LoadedJourney(
      metadata: metadata,
      gpsFixes: gpsList,
      accelSamples: accelList,
      gyroSamples: gyroList,
      magSamples: magList,
      chronologicalRecords: records,
    );
  }
}
