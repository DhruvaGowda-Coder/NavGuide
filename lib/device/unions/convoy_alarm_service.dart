import 'package:flutter/services.dart';

class ConvoyAlarmService {
  static final ConvoyAlarmService _instance = ConvoyAlarmService._internal();
  factory ConvoyAlarmService() => _instance;
  ConvoyAlarmService._internal();

  static const MethodChannel _alarmChannel = MethodChannel('com.navguardian.ai/alarm');
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  /// Plays loud emergency alarm sound and triggers heavy haptic vibration
  Future<void> startAlarm() async {
    if (_isPlaying) return;
    _isPlaying = true;
    try {
      await _alarmChannel.invokeMethod('playAlarmSound');
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Stops the emergency alarm sound
  Future<void> stopAlarm() async {
    _isPlaying = false;
    try {
      await _alarmChannel.invokeMethod('stopAlarmSound');
    } catch (_) {}
  }
}
