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