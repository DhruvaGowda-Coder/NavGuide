import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/telemetry.dart';
import '../location/location_controller.dart';
import 'backend_flow_animation_screen.dart';
import 'journey_analysis_screen.dart';

class JourneyHistoryScreen extends ConsumerWidget {
  const JourneyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(journeyControllerProvider);
    final controller = ref.read(journeyControllerProvider.notifier);
    final locationState = ref.watch(locationControllerProvider);
    final locationController = ref.read(locationControllerProvider.notifier);
    final fix = locationState.fix;
    final isLive = locationState.status == TrackingStatus.live;
    final isRequesting = locationState.status == TrackingStatus.requesting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journeys & AI', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: controller.loadHistory,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          // 1. Dead Reckoning AI Explanation Banner (Requested First in Text)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xff23695a).withValues(alpha: 0.08),
                  const Color(0xff23695a).withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xff23695a).withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xff23695a),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Dead Reckoning Optimization',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xff1e293b),
                            ),
                          ),
                          Text(
                            'Sensor-fusion training & offline calibration',
                            style: TextStyle(fontSize: 11, color: Color(0xff64748b)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Journey recording is done to improve and calibrate AI Dead Reckoning navigation on your device.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff23695a),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'When traveling through tunnels, flyovers, basements, or dense buildings where satellite GPS signal is lost, NavGuide utilizes these recorded 9-axis IMU motion streams (accelerometer, gyroscope, and magnetometer) to compute your continuous vehicle position, heading, and speed without any active GPS signal.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xff334155),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff23695a),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BackendFlowAnimationScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_circle_fill, size: 18),
                    label: const Text(
                      'Launch Backend Flow & ML Animation (Without vs. With ML)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Live GPS & Telemetry Diagnostics Card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isLive ? Icons.gps_fixed : Icons.gps_not_fixed,
                            color: isLive ? const Color(0xff23695a) : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isLive ? 'Live GPS Active' : 'GPS Signal Inactive',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isLive ? const Color(0xff23695a) : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      if (!isLive)
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: isRequesting ? null : () => locationController.start(),
                          child: Text(isRequesting ? 'Connecting…' : 'Enable GPS', style: const TextStyle(fontSize: 12)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('ONLINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (fix != null && isLive) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TelemetryMetric(
                            label: 'Speed',
                            value: '${((fix.speedMetersPerSecond ?? 0.0) * 3.6).toStringAsFixed(1)} km/h',
                            icon: Icons.speed,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TelemetryMetric(
                            label: 'Accuracy',
                            value: '±${fix.accuracyMeters.toStringAsFixed(0)} m',
                            icon: Icons.my_location,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TelemetryMetric(
                            label: 'Heading',
                            value: '${(fix.headingDegrees ?? 0.0).toStringAsFixed(0)}°',
                            icon: Icons.navigation_outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 3. Journey Recording Controls Card
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            state.isRecording ? Icons.fiber_manual_record : Icons.radio_button_checked,
                            color: state.isRecording ? Colors.red : const Color(0xff23695a),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            state.isRecording ? 'Active Recording Session' : 'Record Sensor Journey',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xff1e293b),
                            ),
                          ),
                        ],
                      ),
                      if (state.isRecording)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Text('RECORDING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (state.isRecording) ...[
                    Row(
                      children: [
                        Text(
                          state.formattedDuration,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: Color(0xffd32f2f),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${state.totalSamples} total telemetry points',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                'GPS: ${state.gpsCount} · Accel: ${state.accelCount} · Gyro: ${state.gyroCount} · Mag: ${state.magCount}',
                                style: const TextStyle(fontSize: 10.5, color: Color(0xff64748b)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xffd32f2f),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          final meta = await controller.stopJourney();
                          if (context.mounted && meta != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Saved "${meta.id}" (${meta.totalSamples} samples)'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.stop, size: 18),
                        label: const Text('Stop & Save Journey', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Record synchronized raw GPS coordinates and 9-axis phone motion streams (50 Hz) locally for dead reckoning algorithm training.',
                      style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff23695a),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          locationController.start();
                          await controller.startJourney();
                        },
                        icon: const Icon(Icons.fiber_manual_record, size: 16, color: Colors.redAccent),
                        label: const Text('Start Recording Journey', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 4. Recorded Sessions Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recorded Sessions (${state.history.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xff1e293b),
                ),
              ),
              if (state.isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // 5. History List or Empty State
          if (state.history.isEmpty)
            Card(
              elevation: 0,
              color: Colors.grey.shade100,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.history_outlined, size: 40, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'No recorded sessions yet',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tap "Start Recording Journey" above to capture high-frequency IMU and GPS telemetry locally.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
                    ),
                  ],
                ),
              ),
            )
          else
            ...state.history.map((journey) => _JourneyCard(
              journey: journey,
              onDelete: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Journey?'),
                    content: Text(
                      'Permanently delete "${journey.id}" and all its raw CSV data?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await controller.deleteJourney(journey.id);
                }
              },
              onInspect: () => _inspectJourney(context, journey),
              onAnalyze: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JourneyAnalysisScreen(journey: journey),
                  ),
                );
              },
            )),
        ],
      ),
    );
  }

  void _inspectJourney(BuildContext context, JourneyMetadata journey) async {
    final dir = Directory(journey.directoryPath);
    final files = <String, int>{};
    final previews = <String, String>{};

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          final stat = await entity.stat();
          files[name] = stat.size;

          if (name.endsWith('.csv') || name.endsWith('.json')) {
            try {
              final lines = await entity.readAsLines();
              previews[name] = lines.take(6).join('\n');
            } catch (_) {}
          }
        }
      }
    }

    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).padding.bottom;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (_, scrollController) => SafeArea(
            top: false,
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + bottomInset),
              children: [
            Row(
              children: [
                const Icon(Icons.folder_open, color: Color(0xff23695a)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    journey.id,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              'Location: ${journey.directoryPath}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 24),
            Text(
              'Recorded Files',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final entry in files.entries)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('${(entry.value / 1024).toStringAsFixed(1)} KB'),
                        ],
                      ),
                      if (previews.containsKey(entry.key)) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: SelectableText(
                            previews[entry.key]!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.journey,
    required this.onDelete,
    required this.onInspect,
    required this.onAnalyze,
  });

  final JourneyMetadata journey;
  final VoidCallback onDelete;
  final VoidCallback onInspect;
  final VoidCallback onAnalyze;

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                journey.id,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xffe8efeb),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatDuration(journey.durationSeconds),
                  style: const TextStyle(
                    color: Color(0xff23695a),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Started: ${journey.startTime.toLocal().toString().split('.').first}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _metricChip('GPS', journey.gpsCount),
              _metricChip('Accel', journey.accelCount),
              _metricChip('Gyro', journey.gyroCount),
              _metricChip('Mag', journey.magCount),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: onInspect,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Files'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onAnalyze,
                icon: const Icon(Icons.analytics_outlined, size: 16),
                label: const Text('Analyze (DR)'),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _metricChip(String label, int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Text(
      '$label: $count',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
  );
}

class _TelemetryMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _TelemetryMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xfff8fafc),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xff23695a)),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 10.5, color: Color(0xff64748b))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xff1e293b),
            ),
          ),
        ],
      ),
    );
  }
}
