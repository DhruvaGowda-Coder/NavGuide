import 'package:geolocator/geolocator.dart';

import '../../domain/telemetry.dart';

class GeolocatorService implements LocationService {
  @override
  Future<LocationAccess> access({required bool request}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (request && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  @override
  Stream<GeoFix> watch() =>
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).map(
        (p) => GeoFix(
          latitude: p.latitude,
          longitude: p.longitude,
          accuracyMeters: p.accuracy,
          timestamp: p.timestamp.toUtc(),
          speedMetersPerSecond: p.speed.isFinite && p.speed >= 0
              ? p.speed
              : null,
          headingDegrees: p.heading.isFinite && p.heading >= 0
              ? p.heading
              : null,
          isMocked: p.isMocked,
        ),
      );

  @override
  Stream<bool> serviceChanges() => Geolocator.getServiceStatusStream().map(
    (s) => s == ServiceStatus.enabled,
  );
  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
