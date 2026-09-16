import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../domain/telemetry.dart';

class PhoneSensorService implements SensorService {
  final Stopwatch _clock = Stopwatch()..start();

  SensorSample _sample(
    SensorKind kind,
    double x,
    double y,
    double z,
    DateTime time,
  ) => SensorSample(
    kind: kind,
    x: x,
    y: y,
    z: z,
    sourceTimestamp: time,
    receivedAt: DateTime.now().toUtc(),
    monotonicMicroseconds: _clock.elapsedMicroseconds,
  );

  @override
  Stream<SensorSample> watch(SensorKind kind) {
    if ((!kIsWeb &&
            defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS) ||
        (kIsWeb && kind == SensorKind.magnetometer)) {
      return Stream.error(
        UnsupportedError('Sensor unavailable on this platform.'),
      );
    }
    const interval = Duration(milliseconds: 200);
    return switch (kind) {
      SensorKind.accelerometer => accelerometerEventStream(
        samplingPeriod: interval,
      ).map((e) => _sample(kind, e.x, e.y, e.z, e.timestamp)),
      SensorKind.gyroscope => gyroscopeEventStream(
        samplingPeriod: interval,
      ).map((e) => _sample(kind, e.x, e.y, e.z, e.timestamp)),
      SensorKind.magnetometer => magnetometerEventStream(
        samplingPeriod: interval,
      ).map((e) => _sample(kind, e.x, e.y, e.z, e.timestamp)),
    };
  }
}
