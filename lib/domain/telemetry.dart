
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
