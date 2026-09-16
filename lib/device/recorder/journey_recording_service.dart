import 'dart:async';

import '../../domain/telemetry.dart';
import '../storage/journey_storage.dart';

class LiveRecordingStats {
  const LiveRecordingStats({
    required this.gpsCount,
    required this.accelCount,
    required this.gyroCount,
    required this.magCount,
  });

  final int gpsCount;
  final int accelCount;
  final int gyroCount;
  final int magCount;

  int get totalSamples => gpsCount + accelCount + gyroCount + magCount;
}

class JourneyRecordingService {
  JourneyRecordingService({
    required this.locationService,
    required this.sensorService,
    required this.storage,
  });

  final LocationService locationService;
  final SensorService sensorService;
  final JourneyStorage storage;

  JourneySessionWriter? _activeWriter;
  StreamSubscription<GeoFix>? _gpsSub;
  StreamSubscription<SensorSample>? _accelSub;
  StreamSubscription<SensorSample>? _gyroSub;
  StreamSubscription<SensorSample>? _magSub;

  final Stopwatch _monotonicClock = Stopwatch();
  void Function(LiveRecordingStats)? onStatsUpdate;

  bool get isRecording => _activeWriter != null;
  String? get activeJourneyId => _activeWriter?.journeyId;

  LiveRecordingStats get currentStats => LiveRecordingStats(
    gpsCount: _activeWriter?.gpsCount ?? 0,
    accelCount: _activeWriter?.accelCount ?? 0,
    gyroCount: _activeWriter?.gyroCount ?? 0,
    magCount: _activeWriter?.magCount ?? 0,
  );

  Future<String> startJourney({String? customId}) async {
    if (isRecording) {
      throw StateError('A journey is already recording.');
    }

    final now = DateTime.now().toUtc();
    final journeyId =
        customId ??
        'journey_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    _monotonicClock.reset();
    _monotonicClock.start();

    final writer = await storage.createSession(journeyId, now);
    _activeWriter = writer;

    // Connect GPS stream
    _gpsSub = locationService.watch().listen(
      (fix) {
        writer.writeGps(fix, _monotonicClock.elapsedMicroseconds);
        onStatsUpdate?.call(currentStats);
      },
      onError: (_) {
        // Continue recording other modalities even if GPS fix drops
      },
    );

    // Connect Accelerometer
    _accelSub = sensorService.watch(SensorKind.accelerometer).listen(
      (sample) {
        writer.writeSensor(sample);
        onStatsUpdate?.call(currentStats);
      },
      onError: (_) {},
    );

    // Connect Gyroscope
    _gyroSub = sensorService.watch(SensorKind.gyroscope).listen(
      (sample) {
        writer.writeSensor(sample);
        onStatsUpdate?.call(currentStats);
      },
      onError: (_) {},
    );

    // Connect Magnetometer
    _magSub = sensorService.watch(SensorKind.magnetometer).listen(
      (sample) {
        writer.writeSensor(sample);
        onStatsUpdate?.call(currentStats);
      },
      onError: (_) {},
    );

    return journeyId;
  }

  Future<JourneyMetadata> stopJourney() async {
    final writer = _activeWriter;
    if (writer == null) {
      throw StateError('No active journey recording to stop.');
    }

    // Cancel subscriptions cleanly
    await Future.wait([
      if (_gpsSub != null) _gpsSub!.cancel(),
      if (_accelSub != null) _accelSub!.cancel(),
      if (_gyroSub != null) _gyroSub!.cancel(),
      if (_magSub != null) _magSub!.cancel(),
    ]);

    _gpsSub = null;
    _accelSub = null;
    _gyroSub = null;
    _magSub = null;
    _monotonicClock.stop();

    final now = DateTime.now().toUtc();
    final meta = await writer.close(endTime: now);
    _activeWriter = null;

    return meta;
  }

  Future<void> cancelAndDiscard() async {
    if (!isRecording) return;
    final writer = _activeWriter;
    _activeWriter = null;

    await Future.wait([
      if (_gpsSub != null) _gpsSub!.cancel(),
      if (_accelSub != null) _accelSub!.cancel(),
      if (_gyroSub != null) _gyroSub!.cancel(),
      if (_magSub != null) _magSub!.cancel(),
    ]);

    _gpsSub = null;
    _accelSub = null;
    _gyroSub = null;
    _magSub = null;
    _monotonicClock.stop();

    if (writer != null) {
      await writer.close(endTime: DateTime.now().toUtc());
      await storage.deleteJourney(writer.journeyId);
    }
  }
}
