import 'package:flutter/material.dart';

class RoadmapScreen extends StatelessWidget {
  const RoadmapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NavGuardian AI — Features'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          Text(
            'What NavGuardian AI Does',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xff23695a),
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'All features below are live and active on your device.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          _FeatureCard(
            icon: Icons.shield_outlined,
            title: 'Safest-Route AI Engine',
            subtitle: 'Evaluates routes by balancing safety vs. travel time. '
                'Detects flood zones, accident blackspots, and hazardous road conditions.',
            tag: 'LIVE',
            tagColor: Colors.green,
          ),
          _FeatureCard(
            icon: Icons.search,
            title: 'All-India Destination Search',
            subtitle: 'Search any town, village, or city across India. '
                'Covers all districts and states including Hassan, Chikkamagaluru, Bengaluru, Mumbai, Delhi, and more.',
            tag: 'LIVE',
            tagColor: Colors.green,
          ),
          _FeatureCard(
            icon: Icons.navigation_outlined,
            title: 'Live Turn-by-Turn Navigation',
            subtitle: 'Real-time GPS navigation with a direction-aware vehicle puck '
                'that rotates smoothly as you move or change direction.',
            tag: 'LIVE',
            tagColor: Colors.green,
          ),
          _FeatureCard(
            icon: Icons.sensors,
            title: 'Automatic GPS Blackout Watchdog',
            subtitle: 'Silently monitors your GPS signal. If signal is lost in tunnels or basements, '
                'AI Dead Reckoning activates automatically and restores when signal returns.',
            tag: 'LIVE',
            tagColor: Colors.green,
          ),
          _FeatureCard(
            icon: Icons.route_outlined,
            title: 'Connected Route Polyline',
            subtitle: 'Route line always starts directly at your live vehicle position — '
                'no gaps or breaks between your location and the planned path.',
            tag: 'LIVE',
            tagColor: Colors.green,
          ),
          _FeatureCard(
            icon: Icons.record_voice_over_outlined,
            title: 'Journey Recording & AI Training',
            subtitle: 'Captures synchronized raw GPS and 9-axis IMU streams locally '
                'for dead reckoning and AI model training.',
            tag: 'LIVE',
            tagColor: Colors.green,
          ),
          _FeatureCard(
            icon: Icons.warning_amber_outlined,
            title: 'Road Hazard & Flood Map',
            subtitle: 'Live hazard map with accident hotspots, flood-prone roads, '
                'and weather-related risk areas marked visually.',
            tag: 'LIVE',
            tagColor: Colors.green,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xff23695a).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xff23695a).withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified, color: Color(0xff23695a), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'NavGuardian AI — all features are fully operational on your device.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff23695a),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.tagColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final Color tagColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xff23695a).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xff23695a), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tagColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: tagColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: tagColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
