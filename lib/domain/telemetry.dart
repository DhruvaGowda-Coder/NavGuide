enum PositionSource { gps, estimated }

class GeoFix {
  const GeoFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.speedMetersPerSecond,
    this.headingDegrees,
    this.altitudeMeters,
    this.source = PositionSource.gps,
    this.isMocked = false,
  });
  final double latitude, longitude, accuracyMeters;
  final double? speedMetersPerSecond, headingDegrees, altitudeMeters;
  final DateTime timestamp;
  final PositionSource source;
  final bool isMocked;
  bool isStale(DateTime now) =>
      now.difference(timestamp) > const Duration(seconds: 15);
}

enum SensorKind { accelerometer, gyroscope, magnetometer }

class SensorSample {
  const SensorSample({
    required this.kind,
    required this.x,
    required this.y,
    required this.z,
    required this.sourceTimestamp,
    required this.receivedAt,
    required this.monotonicMicroseconds,
  });
  final SensorKind kind;
  final double x, y, z;
  final DateTime sourceTimestamp, receivedAt;
  final int monotonicMicroseconds;
}

enum LocationAccess { granted, denied, deniedForever, serviceDisabled }

abstract interface class LocationService {
  Future<LocationAccess> access({required bool request});
  Stream<GeoFix> watch();
  Stream<bool> serviceChanges();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

abstract interface class SensorService {
  Stream<SensorSample> watch(SensorKind kind);
}

abstract interface class JourneyRecorder {
  Future<void> start();
  Future<void> addFix(GeoFix fix);
  Future<void> addSensor(SensorSample sample);
  Future<void> stop();
}

abstract interface class NavigationEngine {
  Stream<GeoFix> get positions;
  void addFix(GeoFix fix);
  void addSensor(SensorSample sample);
}

class JourneyMetadata {
  const JourneyMetadata({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.durationSeconds,
    required this.gpsCount,
    required this.accelCount,
    required this.gyroCount,
    required this.magCount,
    required this.directoryPath,
  });

  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds;
  final int gpsCount;
  final int accelCount;
  final int gyroCount;
  final int magCount;
  final String directoryPath;

  int get totalSamples => gpsCount + accelCount + gyroCount + magCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'durationSeconds': durationSeconds,
    'gpsCount': gpsCount,
    'accelCount': accelCount,
    'gyroCount': gyroCount,
    'magCount': magCount,
    'directoryPath': directoryPath,
  };

  factory JourneyMetadata.fromJson(Map<String, dynamic> json) =>
      JourneyMetadata(
        id: json['id'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'] as String)
            : null,
        durationSeconds: json['durationSeconds'] as int? ?? 0,
        gpsCount: json['gpsCount'] as int? ?? 0,
        accelCount: json['accelCount'] as int? ?? 0,
        gyroCount: json['gyroCount'] as int? ?? 0,
        magCount: json['magCount'] as int? ?? 0,
        directoryPath: json['directoryPath'] as String? ?? '',
      );
}
