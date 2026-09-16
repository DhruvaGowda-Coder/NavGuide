import 'dart:math' as math;
import '../../domain/telemetry.dart';
import '../dead_reckoning/dead_reckoning_engine.dart';
import 'ekf_matrix.dart';

/// Diagnostics information from the EKF filter for debugging and telemetry analysis
class EkfDiagnostics {
  const EkfDiagnostics({
    required this.estimatedSpeedMps,
    required this.estimatedHeadingDegrees,
    required this.gyroBiasDegPerSec,
    required this.positionStdDevMeters,
    required this.gpsUpdatesCount,
    required this.magAnomaliesCount,
    required this.isStationary,
  });

  final double estimatedSpeedMps;
  final double estimatedHeadingDegrees;
  final double gyroBiasDegPerSec;
  final double positionStdDevMeters;
  final int gpsUpdatesCount;
  final int magAnomaliesCount;
  final bool isStationary;
}

/// Classical Extended Kalman Filter (EKF) Sensor Fusion Engine
///
/// State vector x in R^6:
///   x[0] = p_N  (North position displacement in meters from anchor)
///   x[1] = p_E  (East position displacement in meters from anchor)
///   x[2] = v_N  (North velocity in m/s)
///   x[3] = v_E  (East velocity in m/s)
///   x[4] = psi  (Heading/yaw in radians clockwise from True North)
///   x[5] = b_w  (Gyroscope yaw rate bias in rad/s)
class EkfSensorFusionEngine implements NavigationEngine {
  EkfSensorFusionEngine({
    this.gravityMagnitude = 9.80665,
    this.zuptThresholdMps2 = 0.35,
  }) {
    _state = List<double>.filled(6, 0.0);
    _cov = EkfMatrix.diagonal([
      4.0, // var(p_N) = (2m)^2
      4.0, // var(p_E) = (2m)^2
      1.0, // var(v_N) = (1m/s)^2
      1.0, // var(v_E) = (1m/s)^2
      0.08, // var(psi) = (~16 deg)^2
      0.001, // var(b_w) = (~1.8 deg/s)^2
    ]);
  }

  final double gravityMagnitude;
  final double zuptThresholdMps2;

  // Anchor Geodetic Coordinates (meters = 0 at anchor)
  double _anchorLat = 0.0;
  double _anchorLon = 0.0;
  double _anchorAltitude = 0.0;

  // Filter State: x = [p_N, p_E, v_N, v_E, psi, b_w]
  late List<double> _state;
  late EkfMatrix _cov;

  // Attitude (Pitch & Roll) tracked via gravity leveling
  double _pitchRad = 0.0;
  double _rollRad = 0.0;

  DateTime? _lastTimestamp;
  int? _lastMonotonicMicros;
  bool _isInitialized = false;

  // ZUPT Detection window
  final List<double> _accelNormWindow = [];
  static const int _windowCapacity = 15;
  bool _isStationary = false;

  // Diagnostics counters
  int _gpsUpdatesCount = 0;
  int _magAnomaliesCount = 0;

  // Process Noise Parameters (Spectral Densities)
  static const double _qAccel = 0.4; // m/s^2 accel noise
  static const double _qGyro = 0.02; // rad/s gyro noise
  static const double _qGyroBias = 0.00005; // rad/s^2 gyro bias random walk

  bool get isInitialized => _isInitialized;
  double get currentLatitude => _estimateCurrentLat();
  double get currentLongitude => _estimateCurrentLon();
  double get currentHeadingDegrees => (_state[4] * (180.0 / math.pi) + 360.0) % 360.0;
  double get currentSpeedMps => math.sqrt(_state[2] * _state[2] + _state[3] * _state[3]);
  double get velocityNorthMps => _state[2];
  double get velocityEastMps => _state[3];
  double get headingRad => _state[4];
  bool get isStationary => _isStationary;
  double get estimatedGyroBiasDegPerSec => _state[5] * (180.0 / math.pi);
  double get positionStdDevMeters => math.sqrt(math.max(0.0, _cov.get(0, 0) + _cov.get(1, 1)));

  EkfDiagnostics get diagnostics => EkfDiagnostics(
        estimatedSpeedMps: currentSpeedMps,
        estimatedHeadingDegrees: currentHeadingDegrees,
        gyroBiasDegPerSec: estimatedGyroBiasDegPerSec,
        positionStdDevMeters: positionStdDevMeters,
        gpsUpdatesCount: _gpsUpdatesCount,
        magAnomaliesCount: _magAnomaliesCount,
        isStationary: _isStationary,
      );

  double _estimateCurrentLat() {
    final delta = GeodesyUtils.metersToDeltaLatLon(_state[0], _state[1], _anchorLat);
    return _anchorLat + delta.deltaLat;
  }

  double _estimateCurrentLon() {
    final delta = GeodesyUtils.metersToDeltaLatLon(_state[0], _state[1], _anchorLat);
    return _anchorLon + delta.deltaLon;
  }

  /// Initialize filter state and anchor point with GPS fix
  void initializeWithGps(GeoFix fix, {int? monotonicMicros}) {
    _anchorLat = fix.latitude;
    _anchorLon = fix.longitude;
    _anchorAltitude = fix.altitudeMeters ?? 0.0;

    final initialHeadingRad = (fix.headingDegrees ?? 0.0) * (math.pi / 180.0);
    final initialSpeed = fix.speedMetersPerSecond ?? 0.0;

    _state = [
      0.0, // p_N
      0.0, // p_E
      initialSpeed * math.cos(initialHeadingRad), // v_N
      initialSpeed * math.sin(initialHeadingRad), // v_E
      _wrapAngle(initialHeadingRad), // psi
      0.0, // b_w
    ];

    final initialPosVar = math.max(4.0, math.pow(fix.accuracyMeters, 2).toDouble());
    _cov = EkfMatrix.diagonal([
      initialPosVar,
      initialPosVar,
      1.0,
      1.0,
      0.05,
      0.001,
    ]);

    _lastTimestamp = fix.timestamp;
    _lastMonotonicMicros = monotonicMicros;
    _isInitialized = true;
    _gpsUpdatesCount = 1;
    _accelNormWindow.clear();
  }

  /// Measurement Update: Called when a valid GPS fix arrives
  @override
  void addFix(GeoFix fix) {
    if (!_isInitialized) {
      initializeWithGps(fix);
      return;
    }

    _gpsUpdatesCount++;
    _lastTimestamp = fix.timestamp;

    // Convert GPS lat/lon to North/East meters relative to anchor
    final distNorth = GeodesyUtils.haversineDistanceMeters(
          _anchorLat,
          _anchorLon,
          fix.latitude,
          _anchorLon,
        ) *
        (fix.latitude >= _anchorLat ? 1.0 : -1.0);

    final distEast = GeodesyUtils.haversineDistanceMeters(
          _anchorLat,
          _anchorLon,
          _anchorLat,
          fix.longitude,
        ) *
        (fix.longitude >= _anchorLon ? 1.0 : -1.0);

    // Build Measurement vector z and matrix H
    // Base measurement: [p_N, p_E]
    final zList = <double>[distNorth, distEast];
    final hRows = <List<double>>[
      [1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0, 0.0, 0.0],
    ];

    // Adaptive position variance from GPS accuracy
    final rPos = math.max(4.0, math.pow(fix.accuracyMeters, 2).toDouble());
    final rDiag = <double>[rPos, rPos];

    // Velocity update if speed is available
    if (fix.speedMetersPerSecond != null && fix.headingDegrees != null) {
      final speed = fix.speedMetersPerSecond!;
      final headingRad = fix.headingDegrees! * (math.pi / 180.0);
      final vnGps = speed * math.cos(headingRad);
      final veGps = speed * math.sin(headingRad);

      zList.add(vnGps);
      hRows.add([0.0, 0.0, 1.0, 0.0, 0.0, 0.0]);
      rDiag.add(0.64); // (0.8 m/s)^2

      zList.add(veGps);
      hRows.add([0.0, 0.0, 0.0, 1.0, 0.0, 0.0]);
      rDiag.add(0.64);

      // Fused heading if device is moving fast enough for reliable course-over-ground
      if (speed > 1.2) {
        zList.add(_wrapAngle(headingRad));
        hRows.add([0.0, 0.0, 0.0, 0.0, 1.0, 0.0]);
        rDiag.add(0.04); // (~11 deg)^2
      }
    }

    _applyMeasurementUpdate(
      z: zList,
      H: EkfMatrix.fromRows(hRows),
      R: EkfMatrix.diagonal(rDiag),
      isAngleMeasurement: (idx) => idx == (zList.length - 1) && hRows[idx][4] == 1.0,
    );
  }

  /// Prediction & Sensor Step: Processes high-frequency IMU
  @override
  void addSensor(SensorSample sample) {
    if (!_isInitialized) return;

    final dt = _computeDeltaTimeSeconds(sample);
    if (dt <= 0.0 || dt > 1.0) return;

    switch (sample.kind) {
      case SensorKind.gyroscope:
        _predictGyro(sample.x, sample.y, sample.z, dt);
      case SensorKind.accelerometer:
        _predictAccelerometer(sample.x, sample.y, sample.z, dt);
      case SensorKind.magnetometer:
        _innovateMagnetometer(sample.x, sample.y, sample.z);
    }
  }

  double _computeDeltaTimeSeconds(SensorSample sample) {
    if (_lastMonotonicMicros != null && sample.monotonicMicroseconds > 0) {
      final diff = sample.monotonicMicroseconds - _lastMonotonicMicros!;
      _lastMonotonicMicros = sample.monotonicMicroseconds;
      _lastTimestamp = sample.receivedAt;
      return diff / 1000000.0;
    }

    if (_lastTimestamp != null) {
      final diff = sample.receivedAt.difference(_lastTimestamp!).inMicroseconds;
      _lastTimestamp = sample.receivedAt;
      return diff / 1000000.0;
    }

    _lastTimestamp = sample.receivedAt;
    return 0.01;
  }

  void _predictGyro(double gx, double gy, double gz, double dt) {
    // Transform body gyro to navigation yaw rate:
    final cosPitch = math.cos(_pitchRad);
    final yawRateRaw =
        cosPitch.abs() > 0.05 ? (gy * math.sin(_rollRad) + gz * math.cos(_rollRad)) / cosPitch : gz;

    // Unbiased yaw rate
    final unbiasedYawRate = yawRateRaw - _state[5];

    // Propagate heading state
    _state[4] = _wrapAngle(_state[4] + unbiasedYawRate * dt);

    // Propagate yaw and bias covariance
    final F = EkfMatrix.identity(6);
    F.set(4, 5, -dt);

    final Q = EkfMatrix.zeros(6, 6);
    Q.set(4, 4, _qGyro * dt);
    Q.set(5, 5, _qGyroBias * dt);

    _cov = F.multiply(_cov).multiply(F.transpose()).add(Q).makeSymmetric();
  }

  void _predictAccelerometer(double ax, double ay, double az, double dt) {
    final norm = math.sqrt(ax * ax + ay * ay + az * az);

    _accelNormWindow.add(norm);
    if (_accelNormWindow.length > _windowCapacity) {
      _accelNormWindow.removeAt(0);
    }

    // 1. Gravity Leveling for Pitch & Roll
    if ((norm - gravityMagnitude).abs() < 1.8) {
      final instPitch = math.atan2(ax, math.sqrt(ay * ay + az * az));
      final instRoll = math.atan2(-ay, az);
      _pitchRad = _pitchRad * 0.94 + instPitch * 0.06;
      _rollRad = _rollRad * 0.94 + instRoll * 0.06;
    }

    // 2. Check Zero Velocity Update (ZUPT)
    _isStationary = _checkStationaryZupt();
    if (_isStationary) {
      // Direct velocity damp/clamp
      _state[2] *= 0.1;
      _state[3] *= 0.1;

      // Pseudo-measurement update for zero velocity:
      _applyMeasurementUpdate(
        z: [0.0, 0.0],
        H: EkfMatrix.fromRows([
          [0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
          [0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        ]),
        R: EkfMatrix.diagonal([0.005, 0.005]),
      );
      return;
    }

    // 3. Direction Cosine Matrix: Body to Navigation (NED)
    final cp = math.cos(_pitchRad);
    final sp = math.sin(_pitchRad);
    final cr = math.cos(_rollRad);
    final sr = math.sin(_rollRad);
    final ch = math.cos(_state[4]);
    final sh = math.sin(_state[4]);

    final rNorthX = ch * cp;
    final rNorthY = ch * sp * sr - sh * cr;
    final rNorthZ = ch * sp * cr + sh * sr;

    final rEastX = sh * cp;
    final rEastY = sh * sp * sr + ch * cr;
    final rEastZ = sh * sp * cr - ch * sr;

    final aNorth = rNorthX * ax + rNorthY * ay + rNorthZ * az;
    final aEast = rEastX * ax + rEastY * ay + rEastZ * az;

    // 4. Kinematic State Propagation
    _state[0] += _state[2] * dt + 0.5 * aNorth * dt * dt; // p_N
    _state[1] += _state[3] * dt + 0.5 * aEast * dt * dt; // p_E
    _state[2] += aNorth * dt; // v_N
    _state[3] += aEast * dt; // v_E

    // 5. State Transition Jacobian F
    final F = EkfMatrix.identity(6);
    F.set(0, 2, dt);
    F.set(1, 3, dt);
    F.set(0, 4, -0.5 * aEast * dt * dt);
    F.set(1, 4, 0.5 * aNorth * dt * dt);
    F.set(2, 4, -aEast * dt);
    F.set(3, 4, aNorth * dt);

    // Process Noise Q
    final dt2 = dt * dt;
    final Q = EkfMatrix.zeros(6, 6);
    final posNoise = 0.25 * _qAccel * dt2 * dt2;
    final velNoise = _qAccel * dt2;

    Q.set(0, 0, posNoise);
    Q.set(1, 1, posNoise);
    Q.set(2, 2, velNoise);
    Q.set(3, 3, velNoise);

    _cov = F.multiply(_cov).multiply(F.transpose()).add(Q).makeSymmetric();
  }

  void _innovateMagnetometer(double mx, double my, double mz) {
    // 1. Validate Magnetic Field Strength (Reject indoor soft/hard iron distortion)
    final fieldMagnitude = math.sqrt(mx * mx + my * my + mz * mz);
    // Earth's natural magnetic field is ~25 to 65 microtesla
    if (fieldMagnitude < 22.0 || fieldMagnitude > 72.0) {
      _magAnomaliesCount++;
      return; // Reject distorted magnetometer sample
    }

    // 2. Tilt-compensated heading calculation
    final cp = math.cos(_pitchRad);
    final sp = math.sin(_pitchRad);
    final cr = math.cos(_rollRad);
    final sr = math.sin(_rollRad);

    final magXNav = mx * cp + my * sp * sr + mz * sp * cr;
    final magYNav = my * cr - mz * sr;

    final magHeadingRad = _wrapAngle(math.atan2(-magYNav, magXNav));

    // Check innovation residual against current yaw estimate
    final diff = _wrapAngle(magHeadingRad - _state[4]);
    if (diff.abs() > 0.8) {
      // > 45 degree discrepancy indicates local disturbance; reject
      _magAnomaliesCount++;
      return;
    }

    // Apply EKF Measurement Update for Yaw
    _applyMeasurementUpdate(
      z: [magHeadingRad],
      H: EkfMatrix.fromRows([
        [0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
      ]),
      R: EkfMatrix.diagonal([0.08]), // (~16 deg)^2
      isAngleMeasurement: (_) => true,
    );
  }

  /// General EKF Measurement Update using Joseph-form Covariance Update
  void _applyMeasurementUpdate({
    required List<double> z,
    required EkfMatrix H,
    required EkfMatrix R,
    bool Function(int index)? isAngleMeasurement,
  }) {
    final m = z.length;

    // Innovation residual: y = z - H*x
    final hx = H.multiplyVector(_state);
    final y = List<double>.filled(m, 0.0);
    for (var i = 0; i < m; i++) {
      var res = z[i] - hx[i];
      if (isAngleMeasurement != null && isAngleMeasurement(i)) {
        res = _wrapAngle(res);
      }
      y[i] = res;
    }

    // S = H * P * H^T + R
    final ht = H.transpose();
    final pht = _cov.multiply(ht);
    final S = H.multiply(pht).add(R);

    // K = P * H^T * inv(S)
    final invS = S.inverse();
    final K = pht.multiply(invS);

    // x = x + K * y
    final ky = K.multiplyVector(y);
    for (var i = 0; i < 6; i++) {
      _state[i] += ky[i];
    }
    _state[4] = _wrapAngle(_state[4]);

    // Joseph form: P = (I - K*H) * P * (I - K*H)^T + K * R * K^T
    final I = EkfMatrix.identity(6);
    final iKh = I.subtract(K.multiply(H));
    final term1 = iKh.multiply(_cov).multiply(iKh.transpose());
    final term2 = K.multiply(R).multiply(K.transpose());

    _cov = term1.add(term2).makeSymmetric();
  }

  bool _checkStationaryZupt() {
    if (_accelNormWindow.length < _windowCapacity) return false;

    var sum = 0.0;
    for (final val in _accelNormWindow) {
      sum += val;
    }
    final mean = sum / _accelNormWindow.length;

    var sumSqDiff = 0.0;
    for (final val in _accelNormWindow) {
      final diff = val - mean;
      sumSqDiff += diff * diff;
    }
    final variance = sumSqDiff / _accelNormWindow.length;
    final stdDev = math.sqrt(variance);

    return stdDev < zuptThresholdMps2 && (mean - gravityMagnitude).abs() < 1.0;
  }

  double _wrapAngle(double rad) {
    while (rad > math.pi) {
      rad -= 2 * math.pi;
    }
    while (rad < -math.pi) {
      rad += 2 * math.pi;
    }
    return rad;
  }

  GeoFix get currentEstimate => GeoFix(
        latitude: currentLatitude,
        longitude: currentLongitude,
        altitudeMeters: _anchorAltitude,
        accuracyMeters: positionStdDevMeters,
        speedMetersPerSecond: currentSpeedMps,
        headingDegrees: currentHeadingDegrees,
        timestamp: _lastTimestamp ?? DateTime.now(),
        source: PositionSource.estimated,
      );

  @override
  Stream<GeoFix> get positions =>
      Stream.periodic(const Duration(milliseconds: 200), (_) => currentEstimate);
}
