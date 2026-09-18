import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../maps/google_map_surface.dart';
import '../location/location_controller.dart';
import '../search/destination_search_screen.dart';
import '../journey/journey_history_screen.dart';
import '../journey/journey_controller.dart';
import '../../domain/telemetry.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isMapFullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(locationControllerProvider.notifier).start();
      }
    });
  }

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

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Sleek Destination Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DestinationSearchScreen(),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Color(0xff23695a), size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Where to? Search destination...',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xff23695a).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.directions,
                        size: 18,
                        color: Color(0xff23695a),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Maximum Exposure Map View (Takes all available remaining space)
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: GoogleMapSurface(
                fix: fix,
                isFullscreen: false,
                onToggleFullscreen: () =>
                    setState(() => _isMapFullscreen = true),
              ),
            ),
          ),

          // Sleek, Compact Bottom Panel for Live GPS & Journey Recording
          _compactBottomPanel(
            context: context,
            state: state,
            controller: controller,
            journeyState: journeyState,
            journeyController: journeyController,
            fix: fix,
            label: label,
          ),
        ],
      ),
    );
  }

  Widget _compactBottomPanel({
    required BuildContext context,
    required TrackingState state,
    required LocationController controller,
    required JourneyState journeyState,
    required JourneyController journeyController,
    required GeoFix? fix,
    required String label,
  }) {
    final isLive = state.status == TrackingStatus.live;
    final isRequesting = state.status == TrackingStatus.requesting;
    final isRecording = journeyState.isRecording;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Live GPS status & speed
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isLive ? Icons.gps_fixed : Icons.gps_not_fixed,
                      color: isLive ? const Color(0xff23695a) : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: label,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isLive ? const Color(0xff23695a) : Colors.black87,
                              ),
                            ),
                            if (fix != null && isLive)
                              TextSpan(
                                text: ' · ${((fix.speedMetersPerSecond ?? 0.0) * 3.6).toStringAsFixed(1)} km/h · ±${fix.accuracyMeters.toStringAsFixed(0)}m',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLive)
                TextButton(
                  onPressed: isRequesting ? null : () => controller.start(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    isRequesting ? 'Connecting…' : 'Enable GPS',
                    style: const TextStyle(fontSize: 12, color: Color(0xff23695a)),
                  ),
                )
              else if (state.status == TrackingStatus.blocked ||
                  state.status == TrackingStatus.disabled)
                TextButton(
                  onPressed: () => controller.openSettings(
                    location: state.status == TrackingStatus.disabled,
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Settings', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 8),

          // Row 2: Simple Journey Recording & History
          Row(
            children: [
              if (isRecording) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xffd32f2f),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  journeyState.formattedDuration,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: Color(0xffd32f2f),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${journeyState.totalSamples} pts',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffd32f2f),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    final meta = await journeyController.stopJourney();
                    if (context.mounted && meta != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Saved "${meta.id}" (${meta.totalSamples} samples)'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('Stop', style: TextStyle(fontSize: 12)),
                ),
              ] else ...[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xff23695a),
                      side: const BorderSide(color: Color(0xff23695a)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () async {
                      controller.start();
                      await journeyController.startJourney();
                    },
                    icon: const Icon(Icons.fiber_manual_record, size: 14, color: Colors.red),
                    label: const Text(
                      'Record Journey',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Journey History',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const JourneyHistoryScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.folder_outlined, size: 18),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

