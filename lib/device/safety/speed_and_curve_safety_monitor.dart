import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../dead_reckoning/dead_reckoning_engine.dart';
import '../voice/voice_guidance_service.dart';

class SpeedAndCurveSafetyMonitor {
  DateTime? _lastSpeedWarningTime;
  DateTime? _lastCurveWarningTime;
  int _lastWarnedCurveIndex = -1;

  double citySpeedLimitKmh = 50.0;
  double highwaySpeedLimitKmh = 80.0;

  void evaluateSafety({
    required double currentSpeedKmh,
    required LatLng currentPosition,
    required List<LatLng> polylinePoints,
    required int targetPolylineIndex,
    required VoiceGuidanceService voiceGuidance,
    bool isHighway = false,
  }) {
    final speedLimit = isHighway ? highwaySpeedLimitKmh : citySpeedLimitKmh;
    final now = DateTime.now();

    // 1. Overspeeding check (Speed limit + 5 km/h tolerance)
    if (currentSpeedKmh >= speedLimit + 5.0) {
      if (_lastSpeedWarningTime == null ||
          now.difference(_lastSpeedWarningTime!).inSeconds > 18) {
        _lastSpeedWarningTime = now;
        voiceGuidance.speak(
          'Caution. You are exceeding the safe speed limit of ${speedLimit.round()} kilometers per hour.',
          force: true,
        );
        return; // Don't speak multiple alerts in the same instant
      }
    }

    // 2. Sharp curve / hairpin bend lookahead check
    if (polylinePoints.isEmpty || targetPolylineIndex >= polylinePoints.length - 1) return;

    double distAhead = 0.0;
    LatLng prev = currentPosition;

    for (int i = targetPolylineIndex; i < polylinePoints.length - 1; i++) {
      final p1 = polylinePoints[i];
      final p2 = polylinePoints[i + 1];

      distAhead += GeodesyUtils.haversineDistanceMeters(
        prev.latitude,
        prev.longitude,
        p1.latitude,
        p1.longitude,
      );

      // We inspect curves up to 140 meters ahead
      if (distAhead > 140.0) break;

      final b1 = _calculateBearing(prev, p1);
      final b2 = _calculateBearing(p1, p2);
      var delta = (b2 - b1 + 360) % 360;
      if (delta > 180) delta -= 360;

      // Sharp curve detected (bend angle >= 42 degrees)
      if (delta.abs() >= 42.0) {
        // If speed is above safe turning speed (32 km/h)
        if (currentSpeedKmh > 32.0 &&
            (_lastWarnedCurveIndex != i ||
                _lastCurveWarningTime == null ||
                now.difference(_lastCurveWarningTime!).inSeconds > 15)) {
          _lastWarnedCurveIndex = i;
          _lastCurveWarningTime = now;

          final curveDist = distAhead.round();
          voiceGuidance.speak(
            'Caution. Sharp curve in $curveDist meters. Reduce speed.',
            force: true,
          );
        }
        break; // Evaluated nearest curve
      }

      prev = p1;
    }
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180.0;
    final lon1 = from.longitude * math.pi / 180.0;
    final lat2 = to.latitude * math.pi / 180.0;
    final lon2 = to.longitude * math.pi / 180.0;

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    return (radians * 180.0 / math.pi + 360.0) % 360.0;
  }

  void reset() {
    _lastSpeedWarningTime = null;
    _lastCurveWarningTime = null;
    _lastWarnedCurveIndex = -1;
  }
}
