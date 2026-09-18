import 'dart:async';
import 'package:flutter/services.dart';
import 'train_tracking_engine.dart';

enum AlarmTriggerMode {
  distance,
  time,
}

class StationAlarm {
  final String targetStationCode;
  final String targetStationName;
  final AlarmTriggerMode mode;
  final double triggerValue; // in km or in minutes
  final bool enableVibration;
  final bool enableSound;
  bool isTriggered;
  bool isSnoozed;
  DateTime? snoozedUntil;

  StationAlarm({
    required this.targetStationCode,
    required this.targetStationName,
    required this.mode,
    required this.triggerValue,
    this.enableVibration = true,
    this.enableSound = true,
    this.isTriggered = false,
    this.isSnoozed = false,
    this.snoozedUntil,
  });

  String get summaryText {
    if (mode == AlarmTriggerMode.distance) {
      return '${triggerValue.toInt()} km before $targetStationName';
    } else {
      return '${triggerValue.toInt()} mins before $targetStationName';
    }
  }
}

class TrainAlarmEngine {
  static final TrainAlarmEngine _instance = TrainAlarmEngine._internal();
  factory TrainAlarmEngine() => _instance;
  TrainAlarmEngine._internal();

  static const MethodChannel _alarmChannel = MethodChannel('com.navguardian.ai/alarm');

  StationAlarm? _activeAlarm;
  StationAlarm? get activeAlarm => _activeAlarm;

  final StreamController<StationAlarm> _alarmTriggeredController =
      StreamController<StationAlarm>.broadcast();
  Stream<StationAlarm> get onAlarmTriggered => _alarmTriggeredController.stream;

  Timer? _vibrationTimer;
  Timer? _soundFallbackTimer;
  bool _isPlayingSound = false;
  bool get isPlayingSound => _isPlayingSound;

  void setAlarm(StationAlarm alarm) {
    _activeAlarm = alarm;
  }

  void cancelAlarm() {
    _stopVibration();
    stopAlarmSound();
    _activeAlarm = null;
  }

  void snoozeAlarm({int minutes = 5}) {
    _stopVibration();
    stopAlarmSound();
    if (_activeAlarm != null) {
      _activeAlarm!.isSnoozed = true;
      _activeAlarm!.snoozedUntil = DateTime.now().add(Duration(minutes: minutes));
    }
  }

  void dismissAlarm() {
    _stopVibration();
    stopAlarmSound();
    _activeAlarm = null;
  }

  Future<void> playAlarmSound() async {
    _isPlayingSound = true;
    try {
      await _alarmChannel.invokeMethod('playAlarmSound');
    } catch (_) {
      // Fallback: SystemSound alert pulse
      SystemSound.play(SystemSoundType.alert);
      _soundFallbackTimer?.cancel();
      _soundFallbackTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (_isPlayingSound) {
          SystemSound.play(SystemSoundType.alert);
        }
      });
    }
  }

  Future<void> stopAlarmSound() async {
    _isPlayingSound = false;
    _soundFallbackTimer?.cancel();
    _soundFallbackTimer = null;
    try {
      await _alarmChannel.invokeMethod('stopAlarmSound');
    } catch (_) {}
  }

  void evaluateProximity({
    required String nextStationCode,
    required double distanceToNextKm,
    required double estimatedMinsToNext,
    List<StationHalt>? routeHalts,
    int? currentStationIndex,
  }) {
    final alarm = _activeAlarm;
    if (alarm == null || alarm.isTriggered) return;

    if (alarm.isSnoozed && alarm.snoozedUntil != null) {
      if (DateTime.now().isBefore(alarm.snoozedUntil!)) {
        return; // still snoozing
      } else {
        alarm.isSnoozed = false;
      }
    }

    // Calculate distance and time to the target station
    double totalDistanceToTarget = -1;
    double totalMinutesToTarget = -1;

    if (alarm.targetStationCode == nextStationCode) {
      totalDistanceToTarget = distanceToNextKm;
      totalMinutesToTarget = estimatedMinsToNext;
    } else if (routeHalts != null && currentStationIndex != null) {
      // Find target station index
      final targetIdx = routeHalts.indexWhere(
        (h) => h.station.code == alarm.targetStationCode,
      );
      if (targetIdx > currentStationIndex) {
        // Approximate distance
        final currentHaltDist = routeHalts[currentStationIndex].distanceKm;
        final targetHaltDist = routeHalts[targetIdx].distanceKm;
        final routeDelta = targetHaltDist - currentHaltDist;
        totalDistanceToTarget = distanceToNextKm + (routeDelta > 0 ? routeDelta : 0);
        // Estimate time roughly based on 60 km/h avg
        totalMinutesToTarget = estimatedMinsToNext + (routeDelta / 60.0) * 60;
      }
    }

    if (totalDistanceToTarget < 0) return;

    bool shouldTrigger = false;
    if (alarm.mode == AlarmTriggerMode.distance) {
      if (totalDistanceToTarget <= alarm.triggerValue) {
        shouldTrigger = true;
      }
    } else {
      if (totalMinutesToTarget <= alarm.triggerValue) {
        shouldTrigger = true;
      }
    }

    if (shouldTrigger) {
      alarm.isTriggered = true;
      _alarmTriggeredController.add(alarm);
      if (alarm.enableVibration) {
        _startVibrationLoop();
      }
      if (alarm.enableSound) {
        playAlarmSound();
      }
    }
  }

  void _startVibrationLoop() {
    _stopVibration();
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      HapticFeedback.heavyImpact();
    });
  }

  void _stopVibration() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }
}
