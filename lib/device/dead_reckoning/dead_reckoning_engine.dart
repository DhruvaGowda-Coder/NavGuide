import 'dart:math' as math;
import '../../domain/telemetry.dart';

/// Geodesy and distance utility functions
class GeodesyUtils {
  const GeodesyUtils._();

  static const double earthRadiusMeters = 6378137.0;

  /// Haversine distance in meters between two lat/lon coordinates
  static double haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final rLat1 = lat1 * (math.pi / 180.0);
    final rLat2 = lat2 * (math.pi / 180.0);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) *
            math.cos(rLat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Convert North/East displacement in meters to delta latitude and delta longitude
  static ({double deltaLat, double deltaLon}) metersToDeltaLatLon(
    double northMeters,
    double eastMeters,
    double latitudeDeg,
  ) {
    final latRad = latitudeDeg * (math.pi / 180.0);
    final metersPerLat = earthRadiusMeters * (math.pi / 180.0);
    final metersPerLon =
        earthRadiusMeters * math.cos(latRad) * (math.pi / 180.0);

    final deltaLat = northMeters / metersPerLat;
    final deltaLon = metersPerLon.abs() > 1e-6 ? eastMeters / metersPerLon : 0.0;
    return (deltaLat: deltaLat, deltaLon: deltaLon);
  }

  /// Initial bearing (heading) in degrees from (lat1, lon1) to (lat2, lon2)
  static double bearingDegrees(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = lat1 * (math.pi / 180.0);
    final phi2 = lat2 * (math.pi / 180.0);
    final deltaLambda = (lon2 - lon1) * (math.pi / 180.0);

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final theta = math.atan2(y, x);
    return (theta * (180.0 / math.pi) + 360.0) % 360.0;
  }
}

/// Baseline Dead Reckoning Engine
///
/// Features:
/// 1. Attitude tracking via accelerometer gravity leveling + gyroscope angular rate integration
/// 2. World navigation frame gravity compensation (NED)
/// 3. Zero Velocity Update (ZUPT) detection to clamp stationary drift
/// 4. Damped velocity propagation with heading projection
/// 5. Geodetic coordinate integration
class DeadReckoningEngine implements NavigationEngine {
  DeadReckoningEngine({
    this.gravityMagnitude = 9.80665,
    this.zuptThresholdMps2 = 0.35,
    this.velocityDampingFactor = 0.98,
  });

  final double gravityMagnitude;
  final double zuptThresholdMps2;
  final double velocityDampingFactor;

  // Current State
  double _lat = 0.0;
  double _lon = 0.0;
  double _altitudeMeters = 0.0;
  double _velocityNorth = 0.0;
  double _velocityEast = 0.0;
  double _headingDegrees = 0.0; // 0 = North, 90 = East, 180 = South, 270 = West
  double _pitchRad = 0.0;
  double _rollRad = 0.0;

  DateTime? _lastTimestamp;
  int? _lastMonotonicMicros;
  bool _isInitialized = false;

  // Moving window for ZUPT (Zero Velocity Update) detection
  final List<double> _accelNormWindow = [];
  static const int _windowCapacity = 15;

  bool get isInitialized => _isInitialized;
  double get currentLatitude => _lat;
  double get currentLongitude => _lon;
  double get currentHeadingDegrees => _headingDegrees;
  double get currentSpeedMps =>
      math.sqrt(_velocityNorth * _velocityNorth + _velocityEast * _velocityEast);

  /// Seeds initial position from GPS
  void initializeWithGps(GeoFix fix, {int? monotonicMicros}) {
    _lat = fix.latitude;
    _lon = fix.longitude;
    _altitudeMeters = fix.altitudeMeters ?? 0.0;
    _headingDegrees = fix.headingDegrees ?? 0.0;

    final initialSpeed = fix.speedMetersPerSecond ?? 0.0;
    final headingRad = _headingDegrees * (math.pi / 180.0);
    _velocityNorth = initialSpeed * math.cos(headingRad);
    _velocityEast = initialSpeed * math.sin(headingRad);

    _lastTimestamp = fix.timestamp;
    _lastMonotonicMicros = monotonicMicros;
    _isInitialized = true;
    _accelNormWindow.clear();
  }

  /// Called when GPS is valid and visible
  @override
  void addFix(GeoFix fix) {
    _lat = fix.latitude;
    _lon = fix.longitude;
    if (fix.altitudeMeters != null) _altitudeMeters = fix.altitudeMeters!;
    if (fix.headingDegrees != null && fix.headingDegrees! > 0) {
      _headingDegrees = fix.headingDegrees!;
    }
    if (fix.speedMetersPerSecond != null) {
      final speed = fix.speedMetersPerSecond!;
      final rad = _headingDegrees * (math.pi / 180.0);
      _velocityNorth = speed * math.cos(rad);
      _velocityEast = speed * math.sin(rad);
    }
    _lastTimestamp = fix.timestamp;
    _isInitialized = true;
  }

  /// Updates navigation state solely from sensor streams (IMU)
  @override
  void addSensor(SensorSample sample) {
    if (!_isInitialized) return;

    final dt = _computeDeltaTimeSeconds(sample);
    if (dt <= 0.0 || dt > 1.0) {
      // Guard against abnormal time gaps or duplicate events
      return;
    }

    switch (sample.kind) {
      case SensorKind.gyroscope:
        _processGyroscope(sample.x, sample.y, sample.z, dt);
      case SensorKind.accelerometer:
        _processAccelerometer(sample.x, sample.y, sample.z, dt);
      case SensorKind.magnetometer:
        _processMagnetometer(sample.x, sample.y, sample.z);
    }
  }

  double _computeDeltaTimeSeconds(SensorSample sample) {
    if (_lastMonotonicMicros != null && sample.monotonicMicroseconds > 0) {
      final diffMicros =
          sample.monotonicMicroseconds - _lastMonotonicMicros!;
      _lastMonotonicMicros = sample.monotonicMicroseconds;
      _lastTimestamp = sample.receivedAt;
      return diffMicros / 1000000.0;
    }

    if (_lastTimestamp != null) {
      final diff = sample.receivedAt.difference(_lastTimestamp!).inMicroseconds;
      _lastTimestamp = sample.receivedAt;
      return diff / 1000000.0;
    }

    _lastTimestamp = sample.receivedAt;
    return 0.01;
  }

  void _processGyroscope(double gx, double gy, double gz, double dt) {
    // gz is yaw rate around device z axis
    // Transform body rotation rates to Euler yaw rate:
    // yawRate = (gy * sin(roll) + gz * cos(roll)) / cos(pitch)
    final cosPitch = math.cos(_pitchRad);
    final yawRateRadPerSec =
        cosPitch.abs() > 0.05
            ? (gy * math.sin(_rollRad) + gz * math.cos(_rollRad)) / cosPitch
            : gz;

    final deltaHeadingDeg = yawRateRadPerSec * (180.0 / math.pi) * dt;
    _headingDegrees = (_headingDegrees + deltaHeadingDeg + 360.0) % 360.0;
  }

  void _processAccelerometer(double ax, double ay, double az, double dt) {
    final norm = math.sqrt(ax * ax + ay * ay + az * az);

    // Maintain running window of acceleration norms for ZUPT
    _accelNormWindow.add(norm);
    if (_accelNormWindow.length > _windowCapacity) {
      _accelNormWindow.removeAt(0);
    }

    // 1. Estimate Pitch & Roll from gravity when not experiencing extreme accelerations
    if ((norm - gravityMagnitude).abs() < 2.0) {
      final instantPitch = math.atan2(ax, math.sqrt(ay * ay + az * az));
      final instantRoll = math.atan2(-ay, az);
      // Low-pass filter attitude
      _pitchRad = _pitchRad * 0.92 + instantPitch * 0.08;
      _rollRad = _rollRad * 0.92 + instantRoll * 0.08;
    }

    // 2. Rotate specific force to World / Navigation frame (North-East-Down)
    // Rotation matrix elements from Roll (phi), Pitch (theta), Heading (psi):
    final cp = math.cos(_pitchRad);
    final sp = math.sin(_pitchRad);
    final cr = math.cos(_rollRad);
    final sr = math.sin(_rollRad);
    final ch = math.cos(_headingDegrees * (math.pi / 180.0));
    final sh = math.sin(_headingDegrees * (math.pi / 180.0));

    // Direction Cosine Matrix rows for North & East
    final rNorthX = ch * cp;
    final rNorthY = ch * sp * sr - sh * cr;
    final rNorthZ = ch * sp * cr + sh * sr;

    final rEastX = sh * cp;
    final rEastY = sh * sp * sr + ch * cr;
    final rEastZ = sh * sp * cr - ch * sr;

    // Linear horizontal accelerations in World Frame
    final aNorth = rNorthX * ax + rNorthY * ay + rNorthZ * az;
    final aEast = rEastX * ax + rEastY * ay + rEastZ * az;

    // 3. Zero Velocity Update (ZUPT) Detection
    final isStationary = _checkStationaryZupt();
    if (isStationary) {
      _velocityNorth = 0.0;
      _velocityEast = 0.0;
      return;
    }

    // 4. Integrate velocity with damping to suppress quadratic integration explosion
    _velocityNorth = (_velocityNorth + aNorth * dt) * velocityDampingFactor;
    _velocityEast = (_velocityEast + aEast * dt) * velocityDampingFactor;

    // 5. Propagate geodetic position (latitude and longitude)
    final dNorth = _velocityNorth * dt;
    final dEast = _velocityEast * dt;

    final delta = GeodesyUtils.metersToDeltaLatLon(dNorth, dEast, _lat);
    _lat += delta.deltaLat;
    _lon += delta.deltaLon;
  }

  void _processMagnetometer(double mx, double my, double mz) {
    // Tilt-compensated compass heading
    final cp = math.cos(_pitchRad);
    final sp = math.sin(_pitchRad);
    final cr = math.cos(_rollRad);
    final sr = math.sin(_rollRad);

    final magXNav = mx * cp + my * sp * sr + mz * sp * cr;
    final magYNav = my * cr - mz * sr;

    final magHeadingDeg =
        (math.atan2(-magYNav, magXNav) * (180.0 / math.pi) + 360.0) % 360.0;

    // Softly fuse magnetometer heading with gyro heading to prevent long-term gyro drift
    final diff = ((magHeadingDeg - _headingDegrees + 540.0) % 360.0) - 180.0;
    if (diff.abs() < 45.0) {
      _headingDegrees = (_headingDegrees + diff * 0.02 + 360.0) % 360.0;
    }
  }

  bool _checkStationaryZupt() {
    if (_accelNormWindow.length < _windowCapacity) return false;

    // Calculate mean and variance of acceleration norm
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

    // If standard deviation is below threshold and mean is near 1G (~9.8 m/s^2), device is stationary
    return stdDev < zuptThresholdMps2 && (mean - gravityMagnitude).abs() < 1.0;
  }

  /// Produce current estimated position fix
  GeoFix get currentEstimate => GeoFix(
        latitude: _lat,
        longitude: _lon,
        altitudeMeters: _altitudeMeters,
        accuracyMeters: 15.0, // baseline estimate uncertainty
        speedMetersPerSecond: currentSpeedMps,
        headingDegrees: _headingDegrees,
        timestamp: _lastTimestamp ?? DateTime.now(),
        source: PositionSource.estimated,
      );

  @override
  Stream<GeoFix> get positions =>
      Stream.periodic(const Duration(milliseconds: 200), (_) => currentEstimate);
}
