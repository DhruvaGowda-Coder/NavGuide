import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/telemetry.dart';
import 'journey_analysis_screen.dart';

class JourneyHistoryScreen extends ConsumerWidget {
  const JourneyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(journeyControllerProvider);
    final controller = ref.read(journeyControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorded Journeys'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: controller.loadHistory,
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.history.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.history_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No journeys recorded yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Start a journey on the Explore tab to record multi-frequency GPS and IMU sensor data locally.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: state.history.length,
              itemBuilder: (context, index) {
                final journey = state.history[index];
                return _JourneyCard(
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
                );
              },
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
