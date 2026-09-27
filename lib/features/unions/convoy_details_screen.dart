import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';

import '../../device/auth/google_auth_service.dart';
import '../../device/unions/union_service.dart';
import '../../device/unions/convoy_alarm_service.dart';
import '../../domain/union_models.dart';
import 'convoy_live_map_screen.dart';
import 'edit_convoy_sheet.dart';
import '../safety_scoring/route_safety_recommendation_screen.dart';

class ConvoyDetailsScreen extends StatefulWidget {
  final String unionId;

  const ConvoyDetailsScreen({super.key, required this.unionId});

  @override
  State<ConvoyDetailsScreen> createState() => _ConvoyDetailsScreenState();
}

class _ConvoyDetailsScreenState extends State<ConvoyDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UnionService _service = UnionService();
  final TextEditingController _chatInputCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();
  Timer? _remoteSyncTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _service.addListener(_onServiceUpdate);
    final u = _union;
    final alert = u?.latestEmergency;
    final shouldAlarm =
        u != null &&
        u.hasActiveEmergency &&
        _service.isMyConvoy(u) &&
        (alert == null || !_service.isAlertSilenced(alert.id));
    if (shouldAlarm && !ConvoyAlarmService().isPlaying) {
      ConvoyAlarmService().startAlarm();
    }

    // Auto-sync real-time updates from Firebase every 3 seconds for fast live sync
    _remoteSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _service.syncWithFirebase();
    });
  }

  @override
  void dispose() {
    _remoteSyncTimer?.cancel();
    _tabController.dispose();
    _service.removeListener(_onServiceUpdate);
    _chatInputCtrl.dispose();
    _chatScrollCtrl.dispose();
    ConvoyAlarmService().stopAlarm();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      final u = _union;
      final alert = u?.latestEmergency;
      final shouldAlarm =
          u != null &&
          u.hasActiveEmergency &&
          _service.isMyConvoy(u) &&
          (alert == null || !_service.isAlertSilenced(alert.id));
      if (shouldAlarm && !ConvoyAlarmService().isPlaying) {
        ConvoyAlarmService().startAlarm();
      } else if (!shouldAlarm && ConvoyAlarmService().isPlaying) {
        ConvoyAlarmService().stopAlarm();
      }
      setState(() {});
    }
  }

  TravelUnionGroup? get _union {
    return _service.unions.where((u) => u.id == widget.unionId).firstOrNull;
  }

  Future<GoogleUserProfile?> _ensureSignedInForSync() async {
    final auth = GoogleAuthService();
    try {
      await auth.initialize();
      var user = auth.currentUser;
      if (user == null || user.email.trim().isEmpty) {
        user = await auth.signIn();
      }
      if (user == null || user.email.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in with Google to sync this action.'),
            ),
          );
        }
        return null;
      }
      await _service.syncWithGoogleUser(user);
      return user;
    } catch (_) {
      return null;
    }
  }

  String _averageLiveSpeedLabel(TravelUnionGroup union) {
    if (union.liveRiders.isEmpty) return 'Avg: --';
    final avg =
        union.liveRiders
            .map((r) => r.speedKmph)
            .fold<double>(0, (sum, speed) => sum + speed) /
        union.liveRiders.length;
    return 'Avg: ${avg.toStringAsFixed(0)} km/h';
  }

  double? _liveSpreadKm(TravelUnionGroup union) {
    if (union.liveRiders.length < 2) return null;

    double maxMeters = 0;
    for (var i = 0; i < union.liveRiders.length; i++) {
      for (var j = i + 1; j < union.liveRiders.length; j++) {
        final a = union.liveRiders[i];
        final b = union.liveRiders[j];
        final meters = Geolocator.distanceBetween(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        );
        maxMeters = math.max(maxMeters, meters);
      }
    }
    return maxMeters / 1000;
  }

  String _liveSpreadLabel(TravelUnionGroup union) {
    final spreadKm = _liveSpreadKm(union);
    if (spreadKm == null) return 'Spread: --';
    return 'Spread: ~${spreadKm.toStringAsFixed(1)} km';
  }

  String _liveRadarLabel(TravelUnionGroup union) {
    if (union.liveRiders.isEmpty) return 'No Live GPS';
    return 'Live Radar';
  }

  Future<void> _makeCall(String phone) async {
    try {
      final clean = phone.replaceAll(RegExp(r'\s+'), '');
      await launchUrl(
        Uri.parse('tel:$clean'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  Future<void> _sendEmail(String email) async {
    try {
      await launchUrl(
        Uri.parse('mailto:$email'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  void _sendChat(TravelUnionGroup union) {
    final text = _chatInputCtrl.text.trim();
    if (text.isEmpty) return;

    final isHost = _service.isOwner(union);
    final gUser = GoogleAuthService().currentUser;
    final myMobs = {
      if (_service.myRiderMobile != null && _service.myRiderMobile!.isNotEmpty)
        _service.myRiderMobile!,
      if (_service.myHostMobile != null && _service.myHostMobile!.isNotEmpty)
        _service.myHostMobile!,
    };
    final myMember = union.members
        .where((m) => myMobs.contains(m.mobile))
        .firstOrNull;
    final String myName = isHost
        ? union.hostName
        : (myMember?.name ?? gUser?.displayName ?? 'Rider');

    _service.sendChatMessage(
      union.id,
      text: text,
      senderName: myName,
      senderMobile: _service.myDeviceId,
      isHost: isHost,
    );
    _chatInputCtrl.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openRequestJoin(TravelUnionGroup union) {
    final nameCtrl = TextEditingController(text: 'Rider');
    final savedMob = _service.myRiderMobile ?? _service.myHostMobile ?? '';
    final mobileCtrl = TextEditingController(text: savedMob);
    final vehicleCtrl = TextEditingController(text: 'Royal Enfield / KTM');
    VehicleCategory selectedCat = VehicleCategory.bike;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final media = MediaQuery.of(ctx);
          final navPad = math.max(media.padding.bottom, 32.0);
          final bottomPad = navPad + media.viewInsets.bottom + 16.0;

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              bottom: true,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: media.size.height * 0.88,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.group_add_rounded,
                              color: Color(0xFF23695A),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Request to Join ${union.title}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Host ${union.hostName} will review and approve your request.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Your Full Name',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: mobileCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Mobile Number',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: vehicleCtrl,
                        decoration: InputDecoration(
                          labelText: 'Your Bike / Vehicle Model',
                          prefixIcon: const Icon(Icons.two_wheeler_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF23695A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            if (nameCtrl.text.trim().isEmpty ||
                                mobileCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please fill in your name and mobile number.',
                                  ),
                                ),
                              );
                              return;
                            }
                            final googleUser = await _ensureSignedInForSync();
                            if (googleUser == null || !mounted) return;
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                            final rawMob = mobileCtrl.text.trim();
                            final digits = rawMob.replaceAll(RegExp(r'\D'), '');
                            final formattedMob = digits.length == 10
                                ? '+91 $digits'
                                : rawMob;

                            final ok = await _service.requestToJoin(
                              joinCodeOrId: union.id,
                              riderName: nameCtrl.text.trim(),
                              riderMobile: formattedMob,
                              riderEmail: googleUser.email,
                              riderVehicle: vehicleCtrl.text.trim(),
                              category: selectedCat,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: ok
                                      ? const Color(0xFF23695A)
                                      : Colors.red.shade700,
                                  content: Text(
                                    ok
                                        ? 'Request submitted! Awaiting ${union.hostName}\'s approval.'
                                        : 'Unable to request join. You may already be in this convoy or it is full.',
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            'Send Join Request',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openRouteOnMap(TravelUnionGroup union) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ConvoyLiveMapScreen(unionId: union.id)),
    );
  }

  Future<void> _openSingleRideNavigation(TravelUnionGroup union) async {
    double originLat = 12.9716;
    double originLng = 77.5946;
    String originName = 'My Location';

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      originLat = pos.latitude;
      originLng = pos.longitude;
    } catch (_) {
      final (sLat, sLng) = UnionService.resolveCityCoords(union.fromLocation);
      originLat = sLat;
      originLng = sLng;
      originName = union.fromLocation;
    }

    final (destLat, destLng) = UnionService.resolveCityCoords(union.toLocation);

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteSafetyRecommendationScreen(
          customOriginLat: originLat,
          customOriginLon: originLng,
          customOriginName: originName,
          customDestLat: destLat,
          customDestLon: destLng,
          customDestName: union.toLocation,
        ),
      ),
    );
  }

  void _openEmergencyDialog(TravelUnionGroup union) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        String? selectedReason;
        bool isSending = false;

        return StatefulBuilder(
          builder: (context, setSheetState) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.emergency_rounded,
                            color: Colors.redAccent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Convoy Emergency SOS',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              Text(
                                'Pick one issue, then broadcast to members',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    const Text(
                      'Select Distress Type:',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildSosOption(
                      icon: Icons.personal_injury_rounded,
                      title: 'Accident / Crash',
                      subtitle: 'Urgent medical or physical assistance needed',
                      color: Colors.red,
                      isSelected: selectedReason == 'Accident / Crash',
                      onTap: () => setSheetState(
                        () => selectedReason = 'Accident / Crash',
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSosOption(
                      icon: Icons.car_crash_rounded,
                      title: 'Engine / Bike Breakdown',
                      subtitle:
                          'Vehicle stalled or mechanical failure on route',
                      color: Colors.orange.shade800,
                      isSelected: selectedReason == 'Engine / Bike Breakdown',
                      onTap: () => setSheetState(
                        () => selectedReason = 'Engine / Bike Breakdown',
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSosOption(
                      icon: Icons.tire_repair_rounded,
                      title: 'Flat Tyre / Puncture',
                      subtitle: 'Puncture kit or air pump needed',
                      color: Colors.amber.shade900,
                      isSelected: selectedReason == 'Flat Tyre / Puncture',
                      onTap: () => setSheetState(
                        () => selectedReason = 'Flat Tyre / Puncture',
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSosOption(
                      icon: Icons.local_gas_station_rounded,
                      title: 'Out of Fuel',
                      subtitle: 'Ran dry, need petrol or towing',
                      color: Colors.blueGrey,
                      isSelected: selectedReason == 'Out of Fuel',
                      onTap: () =>
                          setSheetState(() => selectedReason = 'Out of Fuel'),
                    ),
                    const SizedBox(height: 8),
                    _buildSosOption(
                      icon: Icons.notification_important_rounded,
                      title: 'General Distress / Stranded',
                      subtitle: 'Lost, bad weather, or unsafe conditions',
                      color: Colors.purple,
                      isSelected:
                          selectedReason == 'General Distress / Stranded',
                      onTap: () => setSheetState(
                        () => selectedReason = 'General Distress / Stranded',
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          disabledBackgroundColor: Colors.red.shade100,
                          disabledForegroundColor: Colors.red.shade300,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: selectedReason == null || isSending
                            ? null
                            : () async {
                                setSheetState(() => isSending = true);
                                await _triggerSos(union, selectedReason!);
                              },
                        icon: isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.campaign_rounded),
                        label: Text(
                          isSending ? 'Broadcasting SOS...' : 'Broadcast SOS',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSosOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.14)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.25),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: isSelected
                  ? Icon(
                      Icons.check_circle_rounded,
                      key: const ValueKey('selected'),
                      size: 24,
                      color: color,
                    )
                  : Icon(
                      Icons.radio_button_unchecked_rounded,
                      key: const ValueKey('not-selected'),
                      size: 22,
                      color: color.withValues(alpha: 0.5),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerSos(TravelUnionGroup union, String reason) async {
    Navigator.of(context).pop();

    double lat = 13.0072;
    double lng = 76.0965;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 4),
        ),
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      final (sLat, sLng) = UnionService.resolveCityCoords(union.fromLocation);
      lat = sLat;
      lng = sLng;
    }

    final myName = _service.isOwner(union) ? union.hostName : 'Convoy Rider';
    final myMobile =
        _service.myRiderMobile ?? _service.myHostMobile ?? '+91 99000 12345';

    await _service.broadcastEmergencyAlert(
      unionId: union.id,
      emergencyType: reason,
      riderName: myName,
      riderMobile: myMobile,
      latitude: lat,
      longitude: lng,
      note:
          'Urgent support requested along ${union.fromLocation} -> ${union.toLocation}',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(
            '🚨 SOS Alert Broadcasted to all ${union.title} riders!',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _shareConvoyLink(TravelUnionGroup union) {
    final cleanLink = 'https://navguardian.app/convoy/${union.id}';
    SharePlus.instance.share(ShareParams(text: cleanLink));
  }

  Future<void> _openEditConvoySheet(TravelUnionGroup union) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditConvoySheet(convoy: union, service: _service),
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _confirmTransferHost(
    TravelUnionGroup union,
    UnionMember m,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Text('👑 ', style: TextStyle(fontSize: 20)),
            Text('Transfer Host?'),
          ],
        ),
        content: Text(
          'Make "${m.name}" the primary Host of "${union.title}"?\n\nThey will gain full Host privileges to manage riders, route, and broadcast alerts. You will remain an approved rider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF23695A),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Transfer Host'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await _service.transferConvoyHost(
        unionId: union.id,
        newHostMemberId: m.id,
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '👑 Host rights transferred to ${m.name}!'
                  : 'Failed to transfer Host role.',
            ),
            backgroundColor: const Color(0xFF23695A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatMsgTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Widget _buildConvoyBanner(TravelUnionGroup union) {
    final bannerPath = union.imageUrl.isNotEmpty
        ? union.imageUrl
        : UnionService.getRandomScenicBanner(union.id.hashCode);

    if (bannerPath.startsWith('assets/')) {
      return Image.asset(bannerPath, fit: BoxFit.cover, cacheWidth: 900);
    }
    return Image.network(
      bannerPath,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        UnionService.getRandomScenicBanner(union.id.hashCode),
        fit: BoxFit.cover,
        cacheWidth: 900,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final union = _union;
    if (union == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Convoy Details')),
        body: const Center(child: Text('Convoy not found or removed.')),
      );
    }

    final isHost = _service.isOwner(union);
    final canEdit = _service.canEditConvoy(union);
    final myStatus = _service.myMembershipStatus(union);
    final isSaved = _service.isSaved(union.id);
    final acceptedCount = union.acceptedMembers.length;
    final canContactHost = isHost || myStatus == UnionMemberStatus.accepted;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F6),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              elevation: 0,
              backgroundColor: const Color(0xff0e382d),
              foregroundColor: Colors.white,
              title: AnimatedOpacity(
                opacity: innerBoxIsScrolled ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  union.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              leading: IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.28),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                if (canEdit)
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.28),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.edit_rounded, color: Colors.white),
                    tooltip: 'Edit Convoy',
                    onPressed: () => _openEditConvoySheet(union),
                  ),
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.28),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  tooltip: 'Refresh Convoy',
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await _service.syncWithFirebase();
                    if (mounted) setState(() {});
                  },
                ),
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.28),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.share_rounded, color: Colors.white),
                  tooltip: 'Share Convoy Link',
                  onPressed: () => _shareConvoyLink(union),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Scenic Route Hero Graphic
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xff0a261f),
                            Color(0xff0e382d),
                            Color(0xff164e3f),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: _buildConvoyBanner(union),
                    ),
                    // Atmospheric Scenery Overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.35),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.88),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    // Non-overlapping Header Content Pinned to Bottom
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: AnimatedOpacity(
                        opacity: innerBoxIsScrolled ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Status, Capacity, Category Chips Row
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                // Status Tag (Upcoming / Active)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF23695A),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.flash_on_rounded,
                                        color: Colors.amberAccent,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        union.statusTag.isNotEmpty
                                            ? union.statusTag
                                            : 'Upcoming',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Riders count badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        union.isFull
                                            ? Icons.lock_rounded
                                            : Icons.group_rounded,
                                        color: union.isFull
                                            ? Colors.redAccent
                                            : Colors.greenAccent,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        union.isFull
                                            ? 'Team Full (${union.maxMembers}/${union.maxMembers})'
                                            : '$acceptedCount/${union.maxMembers} Riders',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Vehicle Category
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    union.category.displayName,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Convoy Title
                            Text(
                              union.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.2,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Route corridor
                            Row(
                              children: [
                                const Icon(
                                  Icons.alt_route_rounded,
                                  size: 14,
                                  color: Colors.greenAccent,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    '${union.fromLocation} ➔ ${union.toLocation}${union.viaHighway.isNotEmpty ? ' (${union.viaHighway})' : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (union.slogan.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                '"${union.slogan}"',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white60,
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
            ),
          ];
        },
        body: Column(
          children: [
            // Facts Summary Header Bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildFactItem(
                    Icons.schedule_rounded,
                    union.departureDateStr,
                    'Start Time',
                  ),
                  _buildFactItem(
                    Icons.my_location_rounded,
                    union.fromLocation,
                    'Start Point',
                  ),
                  _buildFactItem(
                    Icons.flag_rounded,
                    union.toLocation,
                    'Destination',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

            // Host Trust Card
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFFE8F5E9),
                    child: Text(
                      union.hostName.isNotEmpty
                          ? union.hostName[0].toUpperCase()
                          : 'H',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF23695A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              union.hostName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: Color(0xFF23695A),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (union.hostRating > 0) ...[
                              const Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${union.hostRating} (${union.hostRidesCount} ride${union.hostRidesCount == 1 ? '' : 's'})',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ] else
                              Text(
                                union.hostRidesCount > 0
                                    ? '${union.hostRidesCount} ride${union.hostRidesCount == 1 ? '' : 's'} · Not yet rated'
                                    : 'Not yet rated',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                        Text(
                          union.hostBio,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (canContactHost)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _makeCall(union.hostMobile),
                          icon: const Icon(
                            Icons.phone_rounded,
                            color: Color(0xFF23695A),
                            size: 20,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFE8F5E9),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: () => _sendEmail(union.hostEmail),
                          icon: const Icon(
                            Icons.mail_rounded,
                            color: Color(0xFF23695A),
                            size: 20,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFE8F5E9),
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.privacy_tip_outlined,
                        color: Color(0xFF64748B),
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),

            // Active Emergency Alert Banner
            if (union.hasActiveEmergency && union.latestEmergency != null) ...[
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🚨 SOS: ${union.latestEmergency!.riderName}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${union.title} • ${union.latestEmergency!.emergencyType}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          _makeCall(union.latestEmergency!.riderMobile),
                      child: const Text(
                        'Call',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _openRouteOnMap(union),
                      child: const Text(
                        'Radar',
                        style: TextStyle(
                          color: Color(0xFF23695A),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Navigate within OUR app — opens convoy live map to see the rider's exact position
                    IconButton(
                      icon: const Icon(
                        Icons.my_location_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'View on Live Map',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ConvoyLiveMapScreen(unionId: union.id),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    // Silence / Unsilence audio siren
                    IconButton(
                      icon: Icon(
                        (ConvoyAlarmService().isPlaying &&
                                !_service.isAlertSilenced(
                                  union.latestEmergency!.id,
                                ))
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip:
                          (ConvoyAlarmService().isPlaying &&
                              !_service.isAlertSilenced(
                                union.latestEmergency!.id,
                              ))
                          ? 'Silence Siren'
                          : 'Siren Silenced',
                      onPressed: () {
                        if (ConvoyAlarmService().isPlaying ||
                            !_service.isAlertSilenced(
                              union.latestEmergency!.id,
                            )) {
                          _service.silenceAlert(union.latestEmergency!.id);
                        } else {
                          _service.unsilenceAlert(union.latestEmergency!.id);
                          ConvoyAlarmService().startAlarm();
                        }
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 5),
                    // Accept SOS Button (formerly tick mark)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                      onPressed: () async {
                        await _service.resolveEmergencyAlert(
                          union.id,
                          union.latestEmergency!.id,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF23695A),
                              content: Text(
                                '✅ SOS in ${union.title} Accepted & Resolved!',
                              ),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],

            // Tab Bar
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF23695A),
                unselectedLabelColor: const Color(0xFF64748B),
                indicatorColor: const Color(0xFF23695A),
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
                tabs: [
                  const Tab(text: 'About'),
                  Tab(text: 'Members ($acceptedCount)'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Chat'),
                        if (canContactHost &&
                            union.chatMessages.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF23695A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${union.chatMessages.length}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

            // Tab Bar Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: About
                  _buildAboutTab(union),
                  // Tab 2: Members
                  _buildMembersTab(union, isHost),
                  // Tab 3: Chat
                  _buildChatTab(union),
                ],
              ),
            ),

            // Sticky Bottom Action Bar
            _buildBottomActionBar(union, isHost, myStatus, isSaved),
          ],
        ),
      ),
    );
  }

  Widget _buildFactItem(IconData icon, String value, String label) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF23695A)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab(TravelUnionGroup union) {
    final canUseConvoyTools =
        _service.isOwner(union) ||
        _service.myMembershipStatus(union) == UnionMemberStatus.accepted;

    return RefreshIndicator(
      color: const Color(0xFF23695A),
      onRefresh: () async {
        await _service.syncWithFirebase();
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Route Corridor Card with Highway Radar HUD
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Corridor Title + Status + Full Map
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF23695A)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.alt_route_rounded,
                            size: 16,
                            color: Color(0xFF23695A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Route Corridor',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (union.liveRiders.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF23695A)
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${union.liveRiders.length} Live',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF23695A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    InkWell(
                      onTap: canUseConvoyTools
                          ? () => _openRouteOnMap(union)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6F3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF23695A)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.map_rounded,
                              size: 14,
                              color: Color(0xFF23695A),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Full Map',
                              style: TextStyle(
                                color: Color(0xFF23695A),
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Interactive Highway Radar Card (App Green & Clean Theme — No Black Screen)
                GestureDetector(
                  onTap: canUseConvoyTools
                      ? () => _openRouteOnMap(union)
                      : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFF1F8F5,
                      ), // Light clean mint / sage background matching app
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF23695A).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Top Row: Origin City (Flexible) | Highway Badge | Destination City (Flexible)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Origin
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          union.fromLocation,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0F172A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 13,
                                      top: 2,
                                    ),
                                    child: Text(
                                      union.departureDateStr,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Highway Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF23695A)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF23695A)
                                      .withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.navigation_rounded,
                                    size: 10,
                                    color: Color(0xFF23695A),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    union.viaHighway.isNotEmpty
                                        ? union.viaHighway
                                        : 'Direct Route',
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF23695A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Destination
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          union.toLocation,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0F172A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.location_on_rounded,
                                        size: 14,
                                        color: Colors.redAccent,
                                      ),
                                    ],
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(right: 18, top: 2),
                                    child: Text(
                                      'Destination',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Highway Track & Live Rider Corridor
                        SizedBox(
                          height: 44,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final trackWidth = constraints.maxWidth;
                              final usableWidth = trackWidth - 48;

                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // Asphalt Emerald Track Ribbon
                                  Center(
                                    child: Container(
                                      height: 10,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF23695A),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                  ),

                                  // Center Road Dashes
                                  Center(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 22,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: List.generate(
                                          9,
                                          (i) => Container(
                                            width: 8,
                                            height: 2,
                                            decoration: BoxDecoration(
                                              color: Colors.white70,
                                              borderRadius:
                                                  BorderRadius.circular(1),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Origin Green Ring
                                  Positioned(
                                    left: 6,
                                    top: 13,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF10B981)
                                                .withValues(alpha: 0.6),
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Destination Red Ring
                                  Positioned(
                                    right: 6,
                                    top: 13,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.redAccent.withValues(
                                              alpha: 0.6,
                                            ),
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Live Riders Along Highway Track
                                  if (union.liveRiders.isNotEmpty) ...[
                                    ...union.liveRiders.take(8).map((r) {
                                      final idx = union.liveRiders.indexOf(r);
                                      final totalCount = math.min(
                                        union.liveRiders.length,
                                        8,
                                      );
                                      final progress = totalCount > 1
                                          ? (0.10 +
                                                (idx / (totalCount - 1)) * 0.78)
                                          : 0.5;
                                      final posX =
                                          24 + (progress * usableWidth) - 13;
                                      final isDistressed = r.isEmergency;

                                      return Positioned(
                                        left: posX.clamp(
                                          20.0,
                                          trackWidth - 36.0,
                                        ),
                                        top: isDistressed ? 1 : 9,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: EdgeInsets.all(
                                                isDistressed ? 5 : 3.5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isDistressed
                                                    ? Colors.red
                                                    : (r.isHost
                                                          ? const Color(
                                                              0xFFF59E0B,
                                                            )
                                                          : const Color(
                                                              0xFF23695A,
                                                            )),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 1.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: isDistressed
                                                        ? Colors.redAccent
                                                              .withValues(
                                                                alpha: 0.9,
                                                              )
                                                        : Colors.black26,
                                                    blurRadius: isDistressed
                                                        ? 8
                                                        : 3,
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                isDistressed
                                                    ? Icons
                                                          .warning_amber_rounded
                                                    : (r.isHost
                                                          ? Icons.star_rounded
                                                          : Icons
                                                                .two_wheeler_rounded),
                                                size: isDistressed ? 13 : 10,
                                                color: Colors.white,
                                              ),
                                            ),
                                            if (isDistressed)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'SOS',
                                                  style: TextStyle(
                                                    fontSize: 8,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Bottom Stats Capsule
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF23695A)
                                  .withValues(alpha: 0.15),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.speed_rounded,
                                      size: 13,
                                      color: Color(0xFF23695A),
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        _averageLiveSpeedLabel(union),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF1E293B),
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.social_distance_rounded,
                                      size: 13,
                                      color: Color(0xFF23695A),
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        _liveSpreadLabel(union),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF1E293B),
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.radar_rounded,
                                    size: 13,
                                    color: Color(0xFF23695A),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _liveRadarLabel(union),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF23695A),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Navigation and Convoy Actions
                Column(
                  children: [
                    // Row 1: Ride Now (Solo Navigation) + Live Radar (Group Tracking)
                    Row(
                      children: [
                        // Ride Now Button (Single Rider Turn-by-Turn Navigation)
                        Expanded(
                          flex: 5,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            onPressed: () => _openSingleRideNavigation(union),
                            icon: const Icon(
                              Icons.navigation_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              '🧭 Ride Now (Solo)',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        if (canUseConvoyTools) ...[
                          const SizedBox(width: 8),
                          // Live Radar (Group Convoy Tracking)
                          Expanded(
                            flex: 5,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1E40AF),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              onPressed: () => _openRouteOnMap(union),
                              icon: const Icon(Icons.radar_rounded, size: 18),
                              label: Text(
                                union.liveRiders.isNotEmpty
                                    ? 'Live Radar (${union.liveRiders.length})'
                                    : 'Live Radar (Group)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    if (canUseConvoyTools) ...[
                      const SizedBox(height: 8),
                      // SOS Alert Broadcast Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(
                              color: Color(0xFFDC2626),
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => _openEmergencyDialog(union),
                          icon: const Icon(Icons.emergency_rounded, size: 18),
                          label: const Text(
                            '🚨 Broadcast SOS to Convoy',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tap "Ride Now" to navigate solo, or Join Convoy to unlock Group Radar & SOS.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // Stats Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatTile(
                      Icons.alt_route_rounded,
                      '~${union.estimatedDistanceKm} km',
                      'Distance',
                    ),
                    _buildStatTile(
                      Icons.timelapse_rounded,
                      union.estimatedDuration,
                      'Est. Duration',
                    ),
                    _buildStatTile(
                      Icons.add_road_rounded,
                      union.routeType,
                      'Route Type',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Ride Description Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ride Description',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  union.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: union.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Members Preview Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Members (${union.acceptedMembers.length})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _tabController.animateTo(1),
                      child: const Text(
                        'View All >',
                        style: TextStyle(
                          color: Color(0xFF23695A),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: union.acceptedMembers.take(8).map((m) {
                      final isLeader =
                          m.name.toLowerCase() == union.hostName.toLowerCase();
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: isLeader
                                      ? const Color(0xFF23695A)
                                      : Colors.grey.shade200,
                                  child: Text(
                                    m.name.isNotEmpty
                                        ? m.name[0].toUpperCase()
                                        : 'R',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: isLeader
                                          ? Colors.white
                                          : const Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                if (isLeader)
                                  const Positioned(
                                    top: -6,
                                    right: -2,
                                    child: Text(
                                      '👑',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.name.split(' ').first,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isLeader
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isLeader
                                    ? const Color(0xFF23695A)
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF23695A)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildMembersTab(TravelUnionGroup union, bool isHost) {
    final accepted = union.acceptedMembers;
    final pending = union.pendingRequests;

    return RefreshIndicator(
      color: const Color(0xFF23695A),
      onRefresh: () async {
        await _service.syncWithFirebase();
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Pending Requests (only for host to approve/reject)
          if (isHost && pending.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.pending_actions_rounded,
                        size: 18,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pending Join Requests (${pending.length})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...pending.map((m) {
                    return Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.amber.shade100,
                            child: Text(
                              m.name[0].toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  m.vehicle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                            ),
                            onPressed: () => _service.respondToJoinRequest(
                              unionId: union.id,
                              memberId: m.id,
                              accept: true,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.cancel_rounded,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => _service.respondToJoinRequest(
                              unionId: union.id,
                              memberId: m.id,
                              accept: false,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          // Accepted Members Roster
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Approved Convoy Riders (${accepted.length}/${union.maxMembers})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),
                ...accepted.map((m) {
                  final isLead =
                      m.name.toLowerCase() == union.hostName.toLowerCase();
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: isLead
                              ? const Color(0xFF23695A)
                              : const Color(0xFFE2E8F0),
                          child: Text(
                            m.name.isNotEmpty ? m.name[0].toUpperCase() : 'R',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isLead
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    m.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  if (isLead) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '👑 Host',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.brown,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                m.vehicle.isNotEmpty ? m.vehicle : 'Rider',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLead && isHost) ...[
                          IconButton(
                            icon: const Icon(
                              Icons.workspace_premium_rounded,
                              size: 20,
                              color: Color(0xFF23695A),
                            ),
                            tooltip: 'Transfer Host 👑',
                            onPressed: () => _confirmTransferHost(union, m),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.person_remove_rounded,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                            tooltip: 'Remove Rider',
                            onPressed: () => _service.kickMember(
                              unionId: union.id,
                              memberId: m.id,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab(TravelUnionGroup union) {
    final messages = union.chatMessages;
    final isHost = _service.isOwner(union);
    final myStatus = _service.myMembershipStatus(union);
    // Only host or accepted members can chat
    final canChat = isHost || myStatus == UnionMemberStatus.accepted;

    if (!canChat) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 40,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Group Chat Locked',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                myStatus == UnionMemberStatus.pending
                    ? 'Your join request is awaiting ${union.hostName}\'s approval. Once approved, the chat and live HUD will unlock.'
                    : 'Join this convoy to access the group chat and coordinate with fellow riders.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              if (myStatus == UnionMemberStatus.pending) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.hourglass_top_rounded,
                        size: 16,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '⏳ Request Pending Approval',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text(
                    'Cancel Request',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _service.cancelJoinRequest(union.id),
                ),
              ] else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF23695A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: const Text(
                    'Request to Join',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _openRequestJoin(union),
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No messages yet.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        'Say hi to ${union.hostName} and fellow riders!',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, idx) {
                    final msg = messages[idx];
                    final isMyMsg = (msg.senderMobile == _service.myDeviceId) ||
                        (msg.senderName == 'You') ||
                        (isHost && msg.isHost && msg.senderName == union.hostName);
                    final canDelete = isMyMsg || isHost;

                    return Align(
                      alignment: isMyMsg
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: canDelete
                            ? () => _showDeleteMessageDialog(union, msg)
                            : null,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isMyMsg
                                ? const Color(0xFF23695A)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: isMyMsg
                                ? null
                                : Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: isMyMsg
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    msg.senderName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: isMyMsg
                                          ? Colors.amberAccent
                                          : const Color(0xFF23695A),
                                    ),
                                  ),
                                  if (msg.isHost) ...[
                                    const SizedBox(width: 4),
                                    const Text(
                                      '👑',
                                      style: TextStyle(fontSize: 9),
                                    ),
                                  ],
                                  if (isMyMsg) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.touch_app_rounded,
                                      size: 9,
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                msg.text,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isMyMsg
                                      ? Colors.white
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatMsgTime(msg.timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMyMsg
                                          ? Colors.white.withValues(alpha: 0.7)
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                  if (canDelete) ...[
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () =>
                                          _showDeleteMessageDialog(union, msg),
                                      child: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 13,
                                        color: isMyMsg
                                            ? Colors.amberAccent
                                            : Colors.redAccent.shade200,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatInputCtrl,
                  decoration: InputDecoration(
                    hintText: 'Message convoy group...',
                    hintStyle: const TextStyle(fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _sendChat(union),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: Color(0xFF23695A)),
                onPressed: () => _sendChat(union),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDeleteMessageDialog(TravelUnionGroup union, UnionChatMessage msg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  msg.text,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text(
                    'Delete Message',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _service.deleteChatMessage(union.id, msg.id);
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(
    TravelUnionGroup union,
    bool isHost,
    UnionMemberStatus? myStatus,
    bool isSaved,
  ) {
    final canUseMemberTools = isHost || myStatus == UnionMemberStatus.accepted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Message shortcut button
            if (canUseMemberTools) ...[
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: () => _tabController.animateTo(2),
                  icon: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: Color(0xFF23695A),
                  ),
                  label: const Text(
                    'Message',
                    style: TextStyle(
                      color: Color(0xFF23695A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF23695A)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],

            // Join / Manage Action Button
            Expanded(
              flex: canUseMemberTools ? 5 : 8,
              child: isHost
                  ? FilledButton.icon(
                      onPressed: () => _tabController.animateTo(1),
                      icon: const Icon(
                        Icons.admin_panel_settings_rounded,
                        size: 16,
                      ),
                      label: const Text(
                        'Manage Convoy 👑',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF23695A),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : myStatus == UnionMemberStatus.accepted
                  ? OutlinedButton.icon(
                      onPressed: () => _service.leaveUnion(union.id),
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                        size: 16,
                      ),
                      label: const Text(
                        'Joined (Leave)',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : myStatus == UnionMemberStatus.pending
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: const Center(
                        child: Text(
                          '⏳ Pending Approval',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.brown,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () => _openRequestJoin(union),
                      icon: const Icon(Icons.group_add_rounded, size: 16),
                      label: const Text(
                        'Request to Join',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF23695A),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8), // Bookmark / Save
            IconButton(
              onPressed: () => _service.toggleSaveUnion(union.id),
              icon: Icon(
                isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: isSaved ? const Color(0xFF23695A) : Colors.grey.shade600,
              ),
              style: IconButton.styleFrom(
                backgroundColor: isSaved
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFF1F5F9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
