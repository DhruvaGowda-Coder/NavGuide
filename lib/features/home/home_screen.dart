import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../maps/google_map_surface.dart';
import '../location/location_controller.dart';
import '../search/destination_search_screen.dart';
import '../journey/journey_history_screen.dart';
import '../journey/journey_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isMapFullscreen = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(locationControllerProvider);
    final controller = ref.read(locationControllerProvider.notifier);
    final journeyState = ref.watch(journeyControllerProvider);
    final journeyController = ref.read(journeyControllerProvider.notifier);
    final fix = state.fix;
    final stale = fix?.isStale(DateTime.now().toUtc()) ?? false;
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

    if (_isMapFullscreen) {
      final bottomInset = MediaQuery.of(context).padding.bottom;
      return Stack(
        children: [
          Positioned.fill(
            child: GoogleMapSurface(
              fix: fix,
              isFullscreen: true,
              onToggleFullscreen: () =>
                  setState(() => _isMapFullscreen = false),
            ),
          ),
          Positioned(
            bottom: 16 + bottomInset,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          journeyState.isRecording
                              ? Icons.fiber_manual_record
                              : Icons.navigation,
                          color: journeyState.isRecording
                              ? Colors.red
                              : const Color(0xff23695a),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          journeyState.isRecording
                              ? 'Recording (${journeyState.formattedDuration})'
                              : (fix != null
                                  ? '${((fix.speedMetersPerSecond ?? 0.0) * 3.6).toStringAsFixed(1)} km/h · ±${fix.accuracyMeters.toStringAsFixed(0)}m'
                                  : 'Waiting for GPS'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    FilledButton.tonal(
                      onPressed: () =>
                          setState(() => _isMapFullscreen = false),
                      child: const Text('Exit Fullscreen'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

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
                    label: const Text('Destination Search & Route Safety'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: (constraints.maxHeight * .45).clamp(220.0, 480.0),
              child: GoogleMapSurface(
                fix: fix,
                isFullscreen: false,
                onToggleFullscreen: () =>
                    setState(() => _isMapFullscreen = true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _journeyRecordingCard(
                    context,
                    journeyState,
                    journeyController,
                    controller,
                  ),
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
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: (state.status == TrackingStatus.requesting ||
                                state.status == TrackingStatus.live)
                            ? null
                            : () => controller.start(),
                        style: state.status == TrackingStatus.live
                            ? FilledButton.styleFrom(
                                backgroundColor: const Color(0xff23695a),
                                disabledBackgroundColor:
                                    const Color(0xff23695a),
                                disabledForegroundColor: Colors.white,
                              )
                            : null,
                        icon: state.status == TrackingStatus.requesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                state.status == TrackingStatus.live
                                    ? Icons.check_circle_outline
                                    : Icons.my_location,
                              ),
                        label: Text(
                          switch (state.status) {
                            TrackingStatus.idle => 'Enable live location',
                            TrackingStatus.requesting => 'Connecting GPS…',
                            TrackingStatus.waiting => 'Searching for fix…',
                            TrackingStatus.live => 'Live GPS Active',
                            _ => 'Retry location',
                          },
                        ),
                      ),
                      if (state.status == TrackingStatus.live ||
                          state.status == TrackingStatus.waiting)
                        OutlinedButton.icon(
                          onPressed: controller.stop,
                          icon: const Icon(Icons.stop, size: 16),
                          label: const Text('Stop tracking'),
                        ),
                      if (state.status == TrackingStatus.blocked ||
                          state.status == TrackingStatus.disabled)
                        OutlinedButton(
                          onPressed: () => controller.openSettings(
                            location: state.status == TrackingStatus.disabled,
                          ),
                          child: const Text('Open settings'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  Widget _journeyRecordingCard(
    BuildContext context,
    JourneyState journeyState,
    JourneyController journeyController,
    LocationController locationController,
  ) {
    final isRecording = journeyState.isRecording;
    final m = (journeyState.elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (journeyState.elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final elapsedStr = '$m:$s';

    return Card(
      elevation: isRecording ? 2 : 0,
      color: isRecording ? const Color(0xfffbf0ef) : const Color(0xfff0f5f2),
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isRecording
              ? const Color(0xffd32f2f)
              : const Color(0xff23695a).withValues(alpha: 0.2),
          width: isRecording ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isRecording
                          ? Icons.fiber_manual_record
                          : Icons.play_circle_outline,
                      color: isRecording
                          ? const Color(0xffd32f2f)
                          : const Color(0xff23695a),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isRecording ? 'RECORDING JOURNEY' : 'Journey Recording',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: isRecording ? 0.5 : 0,
                        color: isRecording
                            ? const Color(0xffd32f2f)
                            : const Color(0xff23695a),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const JourneyHistoryScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.folder_outlined, size: 18),
                  label: Text('History (${journeyState.history.length})'),
                ),
              ],
            ),
            if (isRecording) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Elapsed time',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        elapsedStr,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xffd32f2f),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final meta = await journeyController.stopJourney();
                      if (context.mounted && meta != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Saved "${meta.id}" (${meta.totalSamples} samples)',
                            ),
                            action: SnackBarAction(
                              label: 'View',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const JourneyHistoryScreen(),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Journey'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _counterChip('GPS', journeyState.gpsCount),
                  _counterChip('Accel', journeyState.accelCount),
                  _counterChip('Gyro', journeyState.gyroCount),
                  _counterChip('Mag', journeyState.magCount),
                ],
              ),
            ] else ...[
              const SizedBox(height: 6),
              const Text(
                'Capture synchronized raw GPS and 9-axis IMU streams locally for dead reckoning and AI models.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  locationController.start();
                  await journeyController.startJourney();
                },
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('Start Journey'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _counterChip(String label, int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Text(
      '$label: $count',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

