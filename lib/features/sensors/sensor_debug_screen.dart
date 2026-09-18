import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/telemetry.dart';

class SensorDebugScreen extends ConsumerWidget {
  const SensorDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Device Sensors'),
    ),
    body: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Header info card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xff23695a).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xff23695a).withValues(alpha: 0.25)),
          ),
          child: const Row(
            children: [
              Icon(Icons.sensors, color: Color(0xff23695a), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Live sensor readings from your device hardware. Updates in real time.',
                  style: TextStyle(fontSize: 12, color: Color(0xff23695a), fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final kind in SensorKind.values)
          _SensorCard(kind: kind, ref: ref),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Rotate and tilt your phone to see changing values. Sampled at 5 Hz.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({required this.kind, required this.ref});
  final SensorKind kind;
  final WidgetRef ref;

  String get _unit => switch (kind) {
    SensorKind.accelerometer => 'm/s²',
    SensorKind.gyroscope => 'rad/s',
    SensorKind.magnetometer => 'µT',
  };

  IconData get _icon => switch (kind) {
    SensorKind.accelerometer => Icons.speed,
    SensorKind.gyroscope => Icons.rotate_right,
    SensorKind.magnetometer => Icons.compass_calibration_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xff23695a).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_icon, color: const Color(0xff23695a), size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.name[0].toUpperCase() + kind.name.substring(1),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(_unit, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            ref.watch(sensorProvider(kind)).when(
              data: (s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _AxisBadge(axis: 'X', value: s.x),
                      const SizedBox(width: 8),
                      _AxisBadge(axis: 'Y', value: s.y),
                      const SizedBox(width: 8),
                      _AxisBadge(axis: 'Z', value: s.z),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Updated ${_relativeTime(s.receivedAt)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              error: (_, _) => const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                  SizedBox(width: 6),
                  Text('Sensor unavailable on this device', style: TextStyle(fontSize: 12)),
                ],
              ),
              loading: () => const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Waiting for sensor...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt.toUtc()).abs();
    if (diff.inSeconds < 2) return 'just now';
    return '${diff.inSeconds}s ago';
  }
}

class _AxisBadge extends StatelessWidget {
  const _AxisBadge({required this.axis, required this.value});
  final String axis;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(axis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(
              value.toStringAsFixed(3),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
