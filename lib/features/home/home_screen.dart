import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../maps/google_map_surface.dart';
import '../location/location_controller.dart';
import '../search/destination_search_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationControllerProvider);
    final controller = ref.read(locationControllerProvider.notifier);
    final now =
        ref.watch(clockProvider).asData?.value ?? DateTime.now().toUtc();
    final fix = state.fix;
    final stale = fix?.isStale(now) ?? false;
    final label = switch (state.status) {
      TrackingStatus.idle => 'Ready when you are',
      TrackingStatus.requesting => 'Checking location access…',
      TrackingStatus.waiting => 'Waiting for a GPS fix…',
      TrackingStatus.live =>
        stale ? 'GPS fix is stale · no position estimation' : 'Live GPS',
      TrackingStatus.denied => 'Location permission denied',
      TrackingStatus.blocked => 'Location blocked · open app settings',
      TrackingStatus.disabled => 'Device location is switched off',
      TrackingStatus.paused => 'Tracking paused',
      TrackingStatus.error => 'Location unavailable',
    };
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Know where you are.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'A clearer view of your journey starts with a reliable fix.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DestinationSearchScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.search),
                    label: const Text('Destination search · coming next'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: (constraints.maxHeight * .45).clamp(220.0, 480.0),
              child: GoogleMapSurface(fix: fix),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleLarge),
                  if (state.message != null) Text(state.message!),
                  if (fix?.isMocked ?? false)
                    const Text('Device reports a mocked location.'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _metric(
                        'Accuracy',
                        fix == null
                            ? '—'
                            : '±${fix.accuracyMeters.toStringAsFixed(1)} m',
                      ),
                      _metric(
                        'Speed',
                        fix?.speedMetersPerSecond == null
                            ? '—'
                            : '${(fix!.speedMetersPerSecond! * 3.6).toStringAsFixed(1)} km/h',
                      ),
                      _metric(
                        'Heading',
                        fix?.headingDegrees == null
                            ? '—'
                            : '${fix!.headingDegrees!.toStringAsFixed(0)}°',
                      ),
                    ],
                  ),
                  if (fix != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${fix.latitude.toStringAsFixed(6)}, ${fix.longitude.toStringAsFixed(6)}\nGPS timestamp: ${fix.timestamp.toIso8601String()}',
                      ),
                    ),
                  const SizedBox(height: 8),
                  ref
                      .watch(connectivityProvider)
                      .when(
                        data: (online) => Text(
                          online
                              ? 'Network link available'
                              : 'Offline · map tiles may be unavailable',
                        ),
                        error: (_, _) =>
                            const Text('Network status unavailable'),
                        loading: () => const Text('Checking network…'),
                      ),
                  const SizedBox(height: 12),