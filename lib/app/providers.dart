import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/location/geolocator_service.dart';
import '../device/sensors/phone_sensor_service.dart';
import '../device/connectivity/connectivity_service.dart';
import '../device/storage/journey_storage.dart';
import '../device/recorder/journey_recording_service.dart';
import '../features/journey/journey_controller.dart';
import '../domain/telemetry.dart';

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorService(),
);
final sensorServiceProvider = Provider<SensorService>(
  (ref) => PhoneSensorService(),
);
final foregroundProvider = NotifierProvider<Foreground, bool>(Foreground.new);

class Foreground extends Notifier<bool> {
  @override
  bool build() => true;
  void setActive(bool value) => state = value;
}

final sensorProvider = StreamProvider.autoDispose
    .family<SensorSample, SensorKind>((ref, kind) {
      if (!ref.watch(foregroundProvider)) return const Stream.empty();
      return ref.watch(sensorServiceProvider).watch(kind);
    });
final connectivityProvider = StreamProvider.autoDispose<bool>((ref) {
  if (!ref.watch(foregroundProvider)) return const Stream.empty();
  return ConnectivityService().watch();
});
final clockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now().toUtc(),
  ),
);

final journeyStorageProvider = Provider<JourneyStorage>(
  (ref) => const JourneyStorage(),
);

final journeyRecordingServiceProvider = Provider<JourneyRecordingService>(
  (ref) => JourneyRecordingService(
    locationService: ref.watch(locationServiceProvider),
    sensorService: ref.watch(sensorServiceProvider),
    storage: ref.watch(journeyStorageProvider),
  ),
);

final journeyControllerProvider =
    NotifierProvider<JourneyController, JourneyState>(
      JourneyController.new,
    );

