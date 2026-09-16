class PlannedFeature {
  const PlannedFeature(this.title, this.description);
  final String title, description;
}

const plannedFeatures = [
  PlannedFeature(
    'Destination search',
    'Places provider and search contract are reserved. No search API is connected.',
  ),
  PlannedFeature(
    'Route alternatives',
    'Routes API, traffic-aware geometry and route selection.',
  ),
  PlannedFeature(
    'Route safety score',
    'Evidence, freshness and uncertainty before route recommendations.',
  ),
  PlannedFeature(
    'Live journey',
    'Turn guidance and a consent-based journey recorder.',
  ),
  PlannedFeature(
    'GPS-loss / AI navigation',
    'Dead reckoning, calibrated fusion and evaluated drift correction. No estimated positions yet.',
  ),
  PlannedFeature(
    'Road hazard reporting',
    'Reports, moderation, expiry and confirmations.',
  ),
  PlannedFeature(
    'Journey history',
    'Local storage, retention, export and deletion.',
  ),
  PlannedFeature(
    'Journey analysis',
    'Position quality, route events and drift evaluation.',
  ),
];
