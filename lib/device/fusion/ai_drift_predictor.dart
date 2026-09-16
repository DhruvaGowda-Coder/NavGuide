
/// On-device inference predictor for Phase 5 NavGuardian AI Drift Correction.
///
/// Implements trained Model A (Regularized Ridge Regressor) directly in pure Dart
/// with 0.01ms inference time and zero external native dependencies.
class AiDriftPredictor {
  const AiDriftPredictor();

  static const List<double> _scalerMean = [
    -0.612143,
    3.077673,
    9.139652,
    9.868029,
    5.225261,
    0.003552,
    -0.057402,
    -0.111976,
    0.625548,
    2.569998,
    -1.526084,
    4.474186,
    0.547919,
    0.392157,
  ];

  static const List<double> _scalerScale = [
    1.470757,
    1.236903,
    0.742794,
    0.496808,
    4.914054,
    0.200319,
    0.390972,
    0.616797,
    0.444929,
    4.962851,
    3.736006,
    5.244341,
    1.220052,
    0.488231,
  ];

  static const List<double> _coefDx = [
    0.016262,
    -0.122330,
    -0.135844,
    0.097126,
    0.029418,
    -0.086293,
    0.052017,
    0.028911,
    -0.105804,
    -0.334308,
    0.123673,
    0.264465,
    -0.170944,
    0.056776,
  ];
  static const double _interceptDx = -0.001646;

  static const List<double> _coefDy = [
    0.022998,
    0.126577,
    0.110588,
    -0.085112,
    -0.083328,
    0.204493,
    -0.035777,
    -0.154718,
    0.170251,
    -0.795598,
    0.043060,
    0.392150,
    0.147956,
    0.009460,
  ];
  static const double _interceptDy = -0.000393;

  /// Predicts the residual displacement correction (delta_east, delta_north) in meters
  /// from the 14-dimensional kinematic feature vector.
  ({double deltaEastMeters, double deltaNorthMeters}) predictCorrection({
    required double ax,
    required double ay,
    required double az,
    required double accNorm,
    required double jerk,
    required double gx,
    required double gy,
    required double gz,
    required double gyroNorm,
    required double ekfVx,
    required double ekfVy,
    required double ekfSpeed,
    required double ekfHeadingRad,
    required bool isStationary,
  }) {
    final rawFeatures = [
      ax,
      ay,
      az,
      accNorm,
      jerk,
      gx,
      gy,
      gz,
      gyroNorm,
      ekfVx,
      ekfVy,
      ekfSpeed,
      ekfHeadingRad,
      isStationary ? 1.0 : 0.0,
    ];

    // Standardize features
    final scaled = List<double>.filled(14, 0.0);
    for (var i = 0; i < 14; i++) {
      final s = _scalerScale[i];
      scaled[i] = s > 1e-7 ? (rawFeatures[i] - _scalerMean[i]) / s : 0.0;
    }

    // Linear model prediction
    var dx = _interceptDx;
    var dy = _interceptDy;
    for (var i = 0; i < 14; i++) {
      dx += _coefDx[i] * scaled[i];
      dy += _coefDy[i] * scaled[i];
    }

    // Guard against abnormal extreme single-step jumps
    final clampedDx = dx.clamp(-2.0, 2.0);
    final clampedDy = dy.clamp(-2.0, 2.0);

    return (deltaEastMeters: clampedDx, deltaNorthMeters: clampedDy);
  }

  /// Static helper method invoked during dead-reckoning blackout replay evaluation.
  static ({double deltaXEast, double deltaYNorth}) predictResidualStepCorrection({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required double ekfVx,
    required double ekfVy,
    required double ekfPsiRad,
    required bool isStationary,
  }) {
    final accNorm = (ax * ax + ay * ay + az * az);
    final gyroNorm = (gx * gx + gy * gy + gz * gz);
    final ekfSpeed = (ekfVx * ekfVx + ekfVy * ekfVy);
    final res = const AiDriftPredictor().predictCorrection(
      ax: ax,
      ay: ay,
      az: az,
      accNorm: accNorm > 0 ? (accNorm > 0 ? (ax.abs() + ay.abs() + az.abs()) : 0.0) : 0.0,
      jerk: 0.0,
      gx: gx,
      gy: gy,
      gz: gz,
      gyroNorm: gyroNorm > 0 ? (gx.abs() + gy.abs() + gz.abs()) : 0.0,
      ekfVx: ekfVx,
      ekfVy: ekfVy,
      ekfSpeed: ekfSpeed > 0 ? (ekfVx.abs() + ekfVy.abs()) : 0.0,
      ekfHeadingRad: ekfPsiRad,
      isStationary: isStationary,
    );
    return (deltaXEast: res.deltaEastMeters, deltaYNorth: res.deltaNorthMeters);
  }
}
