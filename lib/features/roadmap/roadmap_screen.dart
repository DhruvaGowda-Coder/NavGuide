import 'package:flutter/material.dart';

import 'feature_catalog.dart';

class RoadmapScreen extends StatelessWidget {
  const RoadmapScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Built to grow', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('Planned modules · not implemented in this milestone'),
      const SizedBox(height: 16),
      for (final feature in plannedFeatures)
        Card(
          child: ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: Text(feature.title),
            subtitle: Text(feature.description),
            isThreeLine: false,
          ),
        ),
    ],
  );
}
