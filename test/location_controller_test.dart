import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/app/providers.dart';
import 'package:navguardian_ai/domain/telemetry.dart';
import 'package:navguardian_ai/features/location/location_controller.dart';

class TestLocation implements LocationService {
  LocationAccess permission = LocationAccess.granted;
  final fixes = StreamController<GeoFix>.broadcast();
  final services = StreamController<bool>.broadcast();
  int subscriptions = 0;
  @override
  Future<LocationAccess> access({required bool request}) async => permission;
  @override
  Stream<GeoFix> watch() {
    subscriptions++;
    return fixes.stream;
  }

  @override
  Stream<bool> serviceChanges() => services.stream;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
}

void main() {
  late TestLocation service;
  late ProviderContainer container;
  setUp(() {
    service = TestLocation();
    container = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(service)],
    );
  });
  tearDown(() async {
    container.dispose();
    await service.fixes.close();
    await service.services.close();
  });

  test('denied permission never starts a location stream', () async {
    service.permission = LocationAccess.denied;
    await container.read(locationControllerProvider.notifier).start();
    expect(
      container.read(locationControllerProvider).status,
      TrackingStatus.denied,
    );
    expect(service.subscriptions, 0);
  });
  test(
    'permanent denial and disabled location remain distinguishable',
    () async {
      final controller = container.read(locationControllerProvider.notifier);
      service.permission = LocationAccess.deniedForever;
      await controller.start();
      expect(
        container.read(locationControllerProvider).status,
        TrackingStatus.blocked,
      );
      service.permission = LocationAccess.serviceDisabled;
      await controller.start();
      expect(
        container.read(locationControllerProvider).status,
        TrackingStatus.disabled,
      );
      expect(service.subscriptions, 0);
    },
  );
  test('real stream values pass through and Stop cancels listeners', () async {
    final controller = container.read(locationControllerProvider.notifier);
    await controller.start();
    final fix = GeoFix(
      latitude: 12,
      longitude: 77,
      accuracyMeters: 6,
      timestamp: DateTime.now().toUtc(),
    );
    service.fixes.add(fix);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(locationControllerProvider).fix, same(fix));
    controller.stop();
    expect(service.fixes.hasListener, isFalse);
    expect(container.read(locationControllerProvider).fix, isNull);
  });
  test('background cancels telemetry and resume reconnects', () async {
    await container.read(locationControllerProvider.notifier).start();
    container.read(foregroundProvider.notifier).setActive(false);
    expect(service.fixes.hasListener, isFalse);
    expect(
      container.read(locationControllerProvider).status,
      TrackingStatus.paused,
    );
    container.read(foregroundProvider.notifier).setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(service.subscriptions, 2);
  });
  test('stream errors clear live position and permit recovery', () async {
    final controller = container.read(locationControllerProvider.notifier);
    await controller.start();
    service.fixes.addError(StateError('lost permission'));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(locationControllerProvider).status,
      TrackingStatus.error,
    );
    expect(service.fixes.hasListener, isFalse);
    await controller.start();
    expect(service.fixes.hasListener, isTrue);
  });
  test('stale positions are recognized without extrapolation', () {
    final time = DateTime.utc(2026);
    final fix = GeoFix(
      latitude: 1,
      longitude: 2,
      accuracyMeters: 9,
      timestamp: time,