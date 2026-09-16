import 'package:flutter/material.dart';
import '../sensors/sensor_debug_screen.dart';
import '../roadmap/roadmap_screen.dart';
import '../../device/crowdsourcing/crowdsourced_hazard_service.dart';
import '../../device/safety_data/route_safety_data_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text(
        'System Settings & Presentation',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
      const SizedBox(height: 4),
      Text(
        'NavGuardian AI · Production Final Release (Phases 1–9)',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      const SizedBox(height: 16),

      // Academic Project Summary Card
      Card(
        elevation: 2,
        color: const Color(0xff1b4332),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Full NavGuardian AI Stack Active',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Complete on-device sensor fusion (EKF) + Ridge Regressor AI drift correction paired with real-world road safety intelligence & crowdsourced community reporting.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),

      // Diagnostics Section
      const Text(
        'Hardware & Engineering Diagnostics',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      const SizedBox(height: 8),
      Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.sensors, color: Color(0xff23695a)),
              title: const Text('Live IMU Sensor Diagnostics', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Inspect high-frequency 9-axis Accelerometer, Gyroscope & Magnetometer streams', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SensorDebugScreen()),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.layers_outlined, color: Color(0xff23695a)),
              title: const Text('NavGuardian AI — All Features', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('View all live features active on your device', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RoadmapScreen()),
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // Privacy & Data Clean Slate
      const Text(
        'Privacy & Data Management',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      const SizedBox(height: 8),
      Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.security, color: Colors.green),
              title: Text('100% On-Device Sensor Processing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('IMU readings, Dead Reckoning calculations, and EKF matrices are processed strictly in phone RAM with zero external server dependencies.', style: TextStyle(fontSize: 11)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              title: const Text('Clear All Hazard & Route Feedback', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Delete all stored crowdsourced reports and ratings for a completely fresh start', style: TextStyle(fontSize: 11)),
              onTap: () async {
                await CrowdsourcedHazardService.instance.clearAllData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All hazard reports and community ratings cleared. Database is completely fresh.')),
                  );
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.refresh_rounded, color: Color(0xff23695a)),
              title: const Text('Clear Cached Corridors & Fresh Live Sync', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Purge in-memory route cache to force fresh live queries from OSRM/Google and weather stations', style: TextStyle(fontSize: 11)),
              onTap: () {
                RouteSafetyDataService().clearCache();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Route cache cleared. Corridors and live weather will be fetched fresh.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    ],
  );
}
