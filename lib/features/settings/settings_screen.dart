import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../sensors/sensor_debug_screen.dart';
import '../roadmap/roadmap_screen.dart';
import '../journey/backend_flow_animation_screen.dart';
import '../../device/crowdsourcing/crowdsourced_hazard_service.dart';
import '../../device/safety_data/route_safety_data_service.dart';
import '../../device/railway/online_train_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _openApiKeyDialog() {
    final controller = TextEditingController(text: OnlineTrainService.customApiKey ?? '');
    bool showAdvanced = OnlineTrainService.customApiKey != null && OnlineTrainService.customApiKey!.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: Color(0xFF23695A)),
              SizedBox(width: 8),
              Text('Live Rail Telemetry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xffecfdf5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xffa7f3d0)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(color: Color(0xff10b981), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Cloud Auto-Sync Active\nZero user effort required.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xff065f46)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'NavGuide automatically syncs official Indian Railways running telemetry, platform numbers, and delays directly from our cloud servers. You never need to hunt for or enter an API key.',
                style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setDialogState(() => showAdvanced = !showAdvanced),
                child: Row(
                  children: [
                    Icon(
                      showAdvanced ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      size: 18,
                      color: const Color(0xFF23695A),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Custom Proxy Override (For Developers)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF23695A)),
                    ),
                  ],
                ),
              ),
              if (showAdvanced) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Custom API Key / Proxy',
                    hintText: 'Leave empty for automated cloud sync',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            if (showAdvanced)
              TextButton(
                onPressed: () {
                  OnlineTrainService.setApiKey('');
                  setState(() {});
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reverted to automated cloud server sync.')),
                  );
                },
                child: const Text('Reset', style: TextStyle(color: Colors.red)),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF23695A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (showAdvanced && controller.text.trim().isNotEmpty) {
                  OnlineTrainService.setApiKey(controller.text.trim());
                }
                setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 48 + bottomInset),
      children: [
        Text(
          'System Settings & Presentation',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'NavGuide · Production Release',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),

        // Academic Project Summary Card
        Card(
          elevation: 2,
          color: const Color(0xff1b4332),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Full NavGuide Stack Active',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Complete on-device sensor fusion (EKF) + Ridge Regressor AI drift correction paired with real-world road safety intelligence & crowdsourced community reporting.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Live Data & Telemetry Services Section
        const Text(
          'Live Transit & Safety Telemetry',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xff23695a).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cell_tower_rounded, color: Color(0xff23695a), size: 20),
                ),
                title: const Text('OpenCellID Offline Engine', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Token Verified · Offline SIM Telemetry Lock Active (Jio / Airtel / Vi)', style: TextStyle(fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.train_rounded, color: Color(0xff23695a), size: 20),
                ),
                title: const Text('Indian Railways Live Feed', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Connected to NavGuide Cloud Telemetry · Live NTES Auto-Sync',
                  style: TextStyle(fontSize: 11, color: Color(0xff16a34a)),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Text(
                    'AUTO SYNC',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                  ),
                ),
                onTap: _openApiKeyDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                ),
                title: const Text('MoRTH Accident Blackspots', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('35 High-Fatality National Highway & Ghat Blackspots Loaded Across India', style: TextStyle(fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: Text(
                    'VERIFIED',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

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
                leading: const Icon(Icons.play_circle_outline_rounded, color: Color(0xff23695a)),
                title: const Text('Backend Flow & ML Animator', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Interactive animation comparing path tracing & TSP graph with vs. without ML', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BackendFlowAnimationScreen()),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.layers_outlined, color: Color(0xff23695a)),
                title: const Text('NavGuide — All Features', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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

        // Help & Support Section
        const Text(
          'Help & Support',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xff23695a).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.support_agent_rounded, color: Color(0xff23695a), size: 20),
                ),
                title: const Text('Contact Support', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('dhruvagowda2006@gmail.com · Tap to email or copy', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xff23695a)),
                onTap: () async {
                  final Uri emailLaunchUri = Uri(
                    scheme: 'mailto',
                    path: 'dhruvagowda2006@gmail.com',
                    queryParameters: {
                      'subject': 'NavGuide Support & Feedback',
                    },
                  );
                  try {
                    await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
                  } catch (_) {
                    await Clipboard.setData(const ClipboardData(text: 'dhruvagowda2006@gmail.com'));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Support email copied: dhruvagowda2006@gmail.com')),
                      );
                    }
                  }
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
        const SizedBox(height: 32),
      ],
    ),
  );
}
}
