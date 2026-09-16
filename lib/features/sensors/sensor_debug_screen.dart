import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/telemetry.dart';

class SensorDebugScreen extends ConsumerWidget {
  const SensorDebugScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Device observatory',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Raw device measurements. These readings do not estimate your position yet.',
      ),
      const SizedBox(height: 16),
      for (final kind in SensorKind.values)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind.name, style: Theme.of(context).textTheme.titleLarge),
                Text(switch (kind) {
                  SensorKind.accelerometer => 'm/s² · includes gravity',
                  SensorKind.gyroscope => 'rad/s',
                  SensorKind.magnetometer => 'µT',
                }),
                const SizedBox(height: 12),
                ref
                    .watch(sensorProvider(kind))
                    .when(
                      data: (s) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'X ${s.x.toStringAsFixed(3)}    Y ${s.y.toStringAsFixed(3)}    Z ${s.z.toStringAsFixed(3)}',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Source: ${s.sourceTimestamp.toIso8601String()}',
                          ),
                          Text(
                            'Receipt UTC: ${s.receivedAt.toIso8601String()}',
                          ),
                          Text(
                            'Monotonic receipt: ${s.monotonicMicroseconds} µs',
                          ),
                        ],
                      ),
                      error: (_, _) => const Text(
                        'Unavailable: this sensor is missing, unsupported, or access failed.',
                      ),
                      loading: () => const Text(
                        'Waiting for sensor data. Hardware or browser support may be unavailable.',
                      ),
                    ),
              ],
            ),
          ),
        ),
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Rotate and tilt your phone to verify changing measurements. Sampling is requested at 5 Hz; actual timing is device-dependent. No samples are saved or uploaded.',
        ),
      ),
    ],
  );
}
