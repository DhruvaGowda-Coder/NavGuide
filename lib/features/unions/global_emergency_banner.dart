import 'package:flutter/material.dart';
import '../../device/unions/convoy_alarm_service.dart';
import '../../device/unions/union_service.dart';
import 'convoy_details_screen.dart';

/// Global floating on-screen emergency notification banner.
/// Automatically appears across the app whenever a convoy the user
/// belongs to has an active, unresolved SOS alert.
class GlobalConvoyEmergencyBanner extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;

  const GlobalConvoyEmergencyBanner({
    super.key,
    this.navigatorKey,
  });

  @override
  State<GlobalConvoyEmergencyBanner> createState() =>
      _GlobalConvoyEmergencyBannerState();
}

class _GlobalConvoyEmergencyBannerState
    extends State<GlobalConvoyEmergencyBanner> {
  final UnionService _service = UnionService();
  final Set<String> _locallyDismissedAlertIds = {};

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final union = _service.myActiveEmergencyUnion;
    if (union == null) return const SizedBox.shrink();

    final alert = union.latestEmergency;
    if (alert == null || _locallyDismissedAlertIds.contains(alert.id)) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          elevation: 12,
          shadowColor: Colors.red.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24, width: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Warning header + Dismiss 'X'
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🚨 SOS ALERT: ${union.title}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${alert.riderName} reported ${alert.emergencyType} (${union.fromLocation} → ${union.toLocation})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Dismiss from Screen',
                      onPressed: () {
                        _service.silenceAlert(alert.id);
                        ConvoyAlarmService().stopAlarm();
                        setState(() {
                          _locallyDismissedAlertIds.add(alert.id);
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Action buttons row: Turn Off Alarm, Accept, View Convoy
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Turn off alarm and close notification banner from screen
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(
                        Icons.volume_off_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      label: const Text(
                        'Turn Off Alarm',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      onPressed: () {
                        _service.silenceAlert(alert.id);
                        ConvoyAlarmService().stopAlarm();
                        setState(() {
                          _locallyDismissedAlertIds.add(alert.id);
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Color(0xFF1E293B),
                            duration: Duration(seconds: 2),
                            content: Text('🔕 Alarm Turned Off & SOS Banner Closed'),
                          ),
                        );
                      },
                    ),

                    // Accept Button
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF1B5E20),
                        size: 14,
                      ),
                      label: const Text(
                        'Accept',
                        style: TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                      onPressed: () async {
                        _service.silenceAlert(alert.id);
                        ConvoyAlarmService().stopAlarm();
                        setState(() {
                          _locallyDismissedAlertIds.add(alert.id);
                        });
                        await _service.resolveEmergencyAlert(
                          union.id,
                          alert.id,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF23695A),
                              content: Text(
                                '✅ SOS for ${alert.riderName} in ${union.title} Accepted & Resolved!',
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // View Convoy Button
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(
                        Icons.map_rounded,
                        color: Color(0xFF23695A),
                        size: 14,
                      ),
                      label: const Text(
                        'View Convoy',
                        style: TextStyle(
                          color: Color(0xFF23695A),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                      onPressed: () {
                        final nav = widget.navigatorKey?.currentState ??
                            Navigator.maybeOf(context);
                        if (nav != null) {
                          nav.push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ConvoyDetailsScreen(unionId: union.id),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
