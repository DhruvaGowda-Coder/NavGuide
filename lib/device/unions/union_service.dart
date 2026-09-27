import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/union_models.dart';
import '../auth/google_auth_service.dart';
import 'convoy_alarm_service.dart';

class UnionService extends ChangeNotifier {
  static final UnionService _instance = UnionService._internal();
  factory UnionService() => _instance;
  UnionService._internal();

  // ── Firebase / Firestore config (diary-13644 project) ──
  static const String _fbProjectId = 'diary-13644';
  static const String _fbApiKey = 'AIzaSyCFkg5ywh9TX0lGglxsVeR6K8JF-BFC7Zc';

  static const List<String> defaultScenicBanners = [
    'assets/banners/banner_mountain_convoy_ride.jpg',
    'assets/banners/banner_coastal_convoy_ride.jpg',
    'assets/banners/banner_canyon_convoy_ride.jpg',
    'assets/banners/banner_himalayan_pangong.jpg',
    'assets/banners/banner_coastal_paradise.jpg',
    'assets/banners/banner_tea_hills_sunrise.jpg',
    'assets/banners/banner_jungle_mangrove_river.jpg',
    'assets/banners/banner_desert_oasis.jpg',
    'assets/banners/banner_western_ghats.jpg',
    'assets/banners/banner_coastal_highway.jpg',
    'assets/banners/banner_himalayan_highway.jpg',
    'assets/banners/banner_forest_waterfall.jpg',
    'assets/banners/banner_desert_sunset.jpg',
    'assets/banners/banner_autumn_valleys.jpg',
    'assets/banners/banner_river_canyon.jpg',
  ];

  static String getRandomScenicBanner([int? seed]) {
    final s = seed ?? DateTime.now().millisecondsSinceEpoch;
    final idx = s.abs() % defaultScenicBanners.length;
    return defaultScenicBanners[idx];
  }

  List<TravelUnionGroup> _unions = [];
  bool _initialized = false;
  String? _firebaseProjectId = _fbProjectId;

  // STRICT OWNERSHIP: Only IDs of unions created on this device
  Set<String> _myCreatedUnionIds = {};
  Set<String> _myJoinedUnionIds = {};
  Set<String> _myRequestedUnionIds = {};
  Set<String> _myRequestedGroupIds = {};
  Set<String> _savedUnionIds = {};
  String? _myHostEmail;
  String? _myHostMobile;
  String? _myRiderEmail;
  String? _myRiderMobile;
  String? _myDeviceId;

  static String normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  String get myDeviceId {
    if (_myDeviceId == null || _myDeviceId!.isEmpty) {
      _myDeviceId =
          'dev_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
      _saveMyProfile();
    }
    return _myDeviceId!;
  }

  // Convoy simulation state
  Timer? _simTimer;
  Timer? _bgSyncTimer;
  bool _isSimulating = false;
  bool get isSimulating => _isSimulating;

  int get totalNotificationCount {
    int count = 0;
    // 1. Pending join requests on my convoys
    for (final u in _unions) {
      if (isOwner(u)) {
        count += u.pendingRequests.length;
      }
    }
    // 2. Pending join requests on my groups
    for (final g in _groups) {
      if (isGroupAdmin(g)) {
        count += g.members.where((m) => m.isPending).length;
      }
    }
    // 3. Active emergencies in my convoys
    for (final u in _unions) {
      if (isMyConvoy(u) && u.hasActiveEmergency) {
        count += u.activeAlerts.length;
      }
    }
    return count;
  }

  bool isMemberOfGroup(TravelGroup g) => isGroupMember(g);

  List<TravelUnionGroup> get unions => List.unmodifiable(_unions);

  String? get myHostMobile => _myHostMobile;
  String? get myHostEmail => _myHostEmail;
  String? get myRiderMobile => _myRiderMobile;
  String? get myRiderEmail => _myRiderEmail;

  Future<void> updateHostMobile(String mobile) async {
    _myHostMobile = mobile.trim();
    _myRiderMobile = mobile.trim();
    await _saveMyProfile();
    notifyListeners();
  }

  bool isSaved(String unionId) => _savedUnionIds.contains(unionId);
  int get savedCount => _savedUnionIds.length;

  Future<void> toggleSaveUnion(String unionId) async {
    if (_savedUnionIds.contains(unionId)) {
      _savedUnionIds.remove(unionId);
    } else {
      _savedUnionIds.add(unionId);
    }
    await _saveMyProfile();
    notifyListeners();
    final gUser = GoogleAuthService().currentUser;
    if (gUser != null) {
      await _writeGoogleAccountIndex(gUser);
    }
  }

  // ── Group Star Rating ──────────────────────────────────────────────────────
  // Stores this device's rating for each group: unionId -> 1..5
  final Map<String, int> _myRatings = {};

  /// Returns this device's previously submitted rating for [unionId], or null.
  int? myRatingFor(String unionId) => _myRatings[unionId];

  /// Submits a star rating (1-5) for a union group.
  /// Recalculates the group's average and notifies listeners.
  Future<void> rateUnion(String unionId, int stars) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;
    stars = stars.clamp(1, 5);
    final previous = _myRatings[unionId];
    _myRatings[unionId] = stars;

    final current = _unions[idx];
    int count = current.memberRatingsCount;
    double totalSum = current.groupRating * count;

    if (previous != null) {
      // Replace old vote
      totalSum = totalSum - previous + stars;
    } else {
      // New vote
      totalSum += stars;
      count += 1;
    }

    final newAvg = count > 0 ? totalSum / count : 0.0;
    _unions[idx] = current.copyWith(
      groupRating: double.parse(newAvg.toStringAsFixed(1)),
      memberRatingsCount: count,
    );

    await _saveLocalCache();
    await _saveMyProfile();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(_unions[idx]);
    }
  }

  Future<void> clearAllData() async {
    _unions.clear();
    _groups.clear();
    _myCreatedUnionIds.clear();
    _myJoinedUnionIds.clear();
    _myCreatedGroupIds.clear();
    _myJoinedGroupIds.clear();
    _savedUnionIds.clear();
    _myHostEmail = null;
    _myHostMobile = null;
    _myRiderEmail = null;
    _myRiderMobile = null;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheFile = File('${docDir.path}/travel_unions_cache.json');
      if (await cacheFile.exists()) await cacheFile.delete();
      final myFile = File('${docDir.path}/my_unions_profile.json');
      if (await myFile.exists()) await myFile.delete();
      final groupFile = File('${docDir.path}/travel_groups_cache.json');
      if (await groupFile.exists()) await groupFile.delete();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> sendChatMessage(
    String unionId, {
    required String text,
    required String senderName,
    required String senderMobile,
    bool isHost = false,
  }) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;
    final msg = UnionChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderName: senderName,
      senderMobile: senderMobile,
      text: text,
      timestamp: DateTime.now(),
      isHost: isHost,
    );
    final current = _unions[idx];
    final updatedChat = List<UnionChatMessage>.from(current.chatMessages)
      ..add(msg);
    _unions[idx] = current.copyWith(chatMessages: updatedChat);
    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(_unions[idx]);
    }
  }

  Future<void> deleteChatMessage(String unionId, String messageId) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;
    final current = _unions[idx];
    final updatedChat = current.chatMessages
        .where((m) => m.id != messageId)
        .toList();
    _unions[idx] = current.copyWith(chatMessages: updatedChat);
    await _saveLocalCache();
    notifyListeners();
    if (_firebaseProjectId != null) {
      _postUnionToFirebase(_unions[idx]);
    }
  }

  static (double, double) resolveCityCoords(String cityName) {
    final lower = cityName.toLowerCase().trim().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (lower.contains('hassan') || lower.contains('hasan'))
      return (13.0072, 76.0965);
    if (lower.contains('bangal') ||
        lower.contains('bengal') ||
        lower.contains('banglor') ||
        lower == 'blr')
      return (12.9716, 77.5946);
    if (lower.contains('myso') || lower.contains('mysu'))
      return (12.2958, 76.6394);
    if (lower.contains('mangal') || lower.contains('mlore'))
      return (12.9141, 74.8560);
    if (lower.contains('saklesh') || lower.contains('sakles'))
      return (12.9439, 75.7877);
    if (lower.contains('chikmag') ||
        lower.contains('chikkamag') ||
        lower.contains('ckm'))
      return (13.3161, 75.7720);
    if (lower.contains('coorg') || lower.contains('madikeri'))
      return (12.4244, 75.7382);
    if (lower.contains('shimog') || lower.contains('shivamog'))
      return (13.9299, 75.5681);
    if (lower.contains('goa') || lower.contains('panaji'))
      return (15.4909, 73.8278);
    if (lower.contains('chennai') || lower.contains('madras'))
      return (13.0827, 80.2707);
    if (lower.contains('hyderabad') || lower.contains('hyd'))
      return (17.3850, 78.4867);
    if (lower.contains('mumbai') || lower.contains('bombay'))
      return (19.0760, 72.8777);
    if (lower.contains('delhi')) return (28.6139, 77.2090);
    if (lower.contains('pune')) return (18.5204, 73.8567);
    if (lower.contains('kochi') || lower.contains('cochin'))
      return (9.9312, 76.2673);
    if (lower.contains('belgaum') || lower.contains('belagavi'))
      return (15.8497, 74.4977);
    if (lower.contains('hubli') || lower.contains('dharwad'))
      return (15.3647, 75.1240);
    if (lower.contains('tumkur') || lower.contains('tumakuru'))
      return (13.3409, 77.1010);
    return (12.9716, 77.5946);
  }

  static List<LatLng> getHighwayRouteWaypoints(String from, String to) {
    final lowerFrom = from.toLowerCase().trim().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final lowerTo = to.toLowerCase().trim().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );

    final isFromHassan =
        lowerFrom.contains('hassan') || lowerFrom.contains('hasan');
    final isToHassan = lowerTo.contains('hassan') || lowerTo.contains('hasan');
    final isFromBlr =
        lowerFrom.contains('bangal') ||
        lowerFrom.contains('bengal') ||
        lowerFrom.contains('banglor') ||
        lowerFrom == 'blr';
    final isToBlr =
        lowerTo.contains('bangal') ||
        lowerTo.contains('bengal') ||
        lowerTo.contains('banglor') ||
        lowerTo == 'blr';

    if (isFromHassan && isToBlr) {
      return const [
        LatLng(13.0072, 76.0965), // Hassan Central
        LatLng(12.9860, 76.1550), // Hassan Bypass NH75
        LatLng(12.9754, 76.2230), // Shantigrama
        LatLng(12.9420, 76.3150), // Nuggehalli turn
        LatLng(12.9066, 76.3926), // Channarayapatna
        LatLng(12.9080, 76.5350), // Hirisave
        LatLng(12.9350, 76.7150), // Bellur Cross (Adichunchanagiri)
        LatLng(12.9720, 76.8850), // Yediyur
        LatLng(13.0238, 77.0345), // Kunigal
        LatLng(13.0450, 77.1200), // Kudur Cross
        LatLng(13.0640, 77.1950), // Solur
        LatLng(13.0820, 77.2950), // Motaganahalli
        LatLng(13.0970, 77.3910), // Nelamangala Toll
        LatLng(13.0550, 77.4850), // Madavara / BIEC
        LatLng(13.0290, 77.5400), // Yeshwanthpur
        LatLng(12.9716, 77.5946), // Bengaluru (City Center)
      ];
    } else if (isFromBlr && isToHassan) {
      return getHighwayRouteWaypoints('hassan', 'bangalore').reversed.toList();
    }

    final (startLat, startLng) = resolveCityCoords(from);
    final (endLat, endLng) = resolveCityCoords(to);
    final bool isSamePoint =
        (startLat - endLat).abs() < 0.001 && (startLng - endLng).abs() < 0.001;
    if (isSamePoint) {
      // Don't draw arbitrary zig-zag loops when cities resolve to the same point
      return [LatLng(startLat, startLng)];
    }
    return [
      LatLng(startLat, startLng),
      LatLng(
        startLat + (endLat - startLat) * 0.33,
        startLng + (endLng - startLng) * 0.33,
      ),
      LatLng(
        startLat + (endLat - startLat) * 0.66,
        startLng + (endLng - startLng) * 0.66,
      ),
      LatLng(endLat, endLng),
    ];
  }

  void stopSimulation() {
    _simTimer?.cancel();
    _simTimer = null;
    _isSimulating = false;
    notifyListeners();
  }

  void startSimulation(String unionId, {int riderCount = 12}) {
    stopSimulation();
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;

    final cleaned = _stripDemoLiveRiders(_unions[idx]);
    if (!identical(cleaned, _unions[idx])) {
      _unions[idx] = cleaned;
      _saveLocalCache();
      notifyListeners();
    }
  }

  bool _isDemoLiveRider(ConvoyLiveRider rider) {
    return rider.id.startsWith('sim_') || rider.mobile.startsWith('+91 98860 ');
  }

  TravelUnionGroup _stripDemoLiveRiders(TravelUnionGroup union) {
    final realRiders = union.liveRiders
        .where((rider) => !_isDemoLiveRider(rider))
        .toList(growable: false);
    if (realRiders.length == union.liveRiders.length) return union;
    return union.copyWith(liveRiders: realRiders);
  }

  Future<void> updateRiderLocation(
    String unionId,
    ConvoyLiveRider rider,
  ) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;
    final current = _unions[idx];

    final list = current.liveRiders
        .where((r) => !_isDemoLiveRider(r))
        .toList(growable: true);
    final rIdx = list.indexWhere(
      (r) =>
          r.id == rider.id ||
          (r.name == rider.name && r.mobile == rider.mobile),
    );
    if (rIdx != -1) {
      list[rIdx] = rider;
    } else {
      list.add(rider);
    }

    _unions[idx] = current.copyWith(liveRiders: list);
    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(_unions[idx]);
    }
  }

  Future<void> broadcastEmergencyAlert({
    required String unionId,
    required String emergencyType,
    required String riderName,
    required String riderMobile,
    required double latitude,
    required double longitude,
    String note = '',
  }) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;
    final current = _unions[idx];

    final alert = ConvoyEmergencyAlert(
      id: 'sos_${DateTime.now().millisecondsSinceEpoch}',
      unionId: unionId,
      riderId: riderMobile.isNotEmpty
          ? riderMobile
          : 'rider_${DateTime.now().millisecondsSinceEpoch}',
      riderName: riderName,
      riderMobile: riderMobile,
      emergencyType: emergencyType,
      note: note,
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      isResolved: false,
    );

    final updatedRiders = current.liveRiders
        .where((r) => !_isDemoLiveRider(r))
        .map((r) {
          if (r.name.toLowerCase() == riderName.toLowerCase() ||
              (riderMobile.isNotEmpty && r.mobile == riderMobile)) {
            return r.copyWith(
              isEmergency: true,
              emergencyReason: emergencyType,
              latitude: latitude,
              longitude: longitude,
              lastUpdated: DateTime.now(),
            );
          }
          return r;
        })
        .toList();

    if (!updatedRiders.any(
      (r) =>
          r.name.toLowerCase() == riderName.toLowerCase() ||
          (riderMobile.isNotEmpty && r.mobile == riderMobile),
    )) {
      updatedRiders.add(
        ConvoyLiveRider(
          id: riderMobile.isNotEmpty
              ? riderMobile
              : 'sos_rider_${DateTime.now().millisecondsSinceEpoch}',
          name: riderName,
          mobile: riderMobile,
          vehicle: current.category == VehicleCategory.car
              ? 'Convoy Vehicle'
              : 'Rider Bike',
          category: current.category,
          latitude: latitude,
          longitude: longitude,
          speedKmph: 0,
          heading: 0,
          isHost:
              riderName.trim().toLowerCase() ==
              current.hostName.trim().toLowerCase(),
          isEmergency: true,
          emergencyReason: emergencyType,
          lastUpdated: DateTime.now(),
        ),
      );
    }

    final updatedAlerts = List<ConvoyEmergencyAlert>.from(current.activeAlerts)
      ..add(alert);

    _unions[idx] = current.copyWith(
      liveRiders: updatedRiders,
      activeAlerts: updatedAlerts,
    );

    // Start siren audio loop
    ConvoyAlarmService().startAlarm();

    // Broadcast chat message
    await sendChatMessage(
      unionId,
      text:
          '🚨 EMERGENCY ALERT: $riderName reported $emergencyType! Urgent assistance needed at [${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}]',
      senderName: '🚨 SOS System',
      senderMobile: riderMobile,
      isHost: false,
    );

    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(_unions[idx]);
    }
  }

  Future<void> resolveEmergencyAlert(String unionId, String alertId) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;
    final current = _unions[idx];

    final updatedAlerts = current.activeAlerts.map((a) {
      if (a.id == alertId) {
        return ConvoyEmergencyAlert(
          id: a.id,
          unionId: a.unionId,
          riderId: a.riderId,
          riderName: a.riderName,
          riderMobile: a.riderMobile,
          emergencyType: a.emergencyType,
          note: a.note,
          latitude: a.latitude,
          longitude: a.longitude,
          timestamp: a.timestamp,
          isResolved: true,
        );
      }
      return a;
    }).toList();

    _silencedAlertIds.remove(alertId);

    final stillActive = updatedAlerts.any((a) => !a.isResolved);
    if (!stillActive) {
      ConvoyAlarmService().stopAlarm();
    }

    final updatedRiders = current.liveRiders.map((r) {
      return r.copyWith(isEmergency: false, emergencyReason: '');
    }).toList();

    _unions[idx] = current.copyWith(
      activeAlerts: updatedAlerts,
      liveRiders: updatedRiders,
    );

    await sendChatMessage(
      unionId,
      text: '✅ Emergency alert resolved. All riders safe.',
      senderName: 'Convoy System',
      senderMobile: '',
      isHost: false,
    );

    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(_unions[idx]);
    }
  }

  /// Returns true if the current user is genuinely the owner/host of this convoy
  bool isOwner(TravelUnionGroup union) {
    // 0. If user is signed in with Google and email matches convoy hostEmail, they are 100% the owner!
    final googleUser = GoogleAuthService().currentUser;
    if (googleUser != null &&
        googleUser.email.isNotEmpty &&
        union.hostEmail.trim().isNotEmpty) {
      if (union.hostEmail.trim().toLowerCase() ==
          googleUser.email.trim().toLowerCase()) {
        return true;
      }
    }

    // 1. Must be in explicitly created unions on this device
    if (!_myCreatedUnionIds.contains(union.id)) {
      return false;
    }

    // 2. If host name indicates someone else (e.g. friend "gandu"), user is NOT owner
    if (union.hostName.trim().toLowerCase() == 'gandu') {
      return false;
    }

    // 3. If mobile is specified on both, it must strictly match
    if (_myHostMobile != null &&
        _myHostMobile!.isNotEmpty &&
        union.hostMobile.isNotEmpty) {
      if (union.hostMobile.replaceAll(RegExp(r'\D'), '') !=
          _myHostMobile!.replaceAll(RegExp(r'\D'), '')) {
        return false;
      }
    }

    return true;
  }

  /// Returns true if the current user can manage/edit this convoy
  bool canEditConvoy(TravelUnionGroup union) {
    if (isOwner(union)) return true;
    if (_myCreatedUnionIds.contains(union.id)) return true;
    for (final g in _groups) {
      if (g.convoyIds.contains(union.id) && isGroupAdmin(g)) {
        return true;
      }
    }
    return false;
  }

  /// Removes ownership claim for a convoy (e.g. created by a friend)
  void disclaimOwnership(String unionId) {
    _myCreatedUnionIds.remove(unionId);
    _saveMyProfile();
    notifyListeners();
  }

  /// Transfers the Host role of a convoy to another approved member.
  Future<bool> transferConvoyHost({
    required String unionId,
    required String newHostMemberId,
  }) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return false;
    final current = _unions[idx];
    if (!isOwner(current)) return false;

    final newHost = current.members
        .where((m) => m.id == newHostMemberId)
        .firstOrNull;
    if (newHost == null) return false;

    // Update live riders host flag
    final updatedRiders = current.liveRiders.map((r) {
      if (r.id == newHost.id ||
          (newHost.mobile.isNotEmpty && r.mobile == newHost.mobile)) {
        return r.copyWith(isHost: true);
      }
      return r.copyWith(isHost: false);
    }).toList();

    final updatedUnion = current.copyWith(
      hostName: newHost.name,
      hostMobile: newHost.mobile,
      hostEmail: newHost.email,
      liveRiders: updatedRiders,
    );

    _unions[idx] = updatedUnion;
    _myCreatedUnionIds.remove(unionId);

    await _saveLocalCache();
    await _saveMyProfile();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(updatedUnion);
    }
    return true;
  }

  UnionMemberStatus? myMembershipStatus(TravelUnionGroup union) {
    if (isOwner(union)) return UnionMemberStatus.accepted;

    final rEmail = _myRiderEmail ?? _myHostEmail;
    final rMobile = _myRiderMobile ?? _myHostMobile;
    final gEmail = GoogleAuthService().currentUser?.email.trim().toLowerCase();

    for (final m in union.members) {
      // Don't mistake the host's member record for a joined rider
      if (m.email.trim().toLowerCase() ==
              union.hostEmail.trim().toLowerCase() &&
          m.mobile.trim() == union.hostMobile.trim()) {
        continue;
      }

      final emailMatch = (rEmail != null &&
              rEmail.isNotEmpty &&
              m.email.trim().toLowerCase() == rEmail.toLowerCase()) ||
          (gEmail != null &&
              gEmail.isNotEmpty &&
              m.email.trim().toLowerCase() == gEmail);

      final mNorm = normalizePhone(m.mobile);
      final rNorm = rMobile != null ? normalizePhone(rMobile) : '';
      final mobMatch = mNorm.isNotEmpty && rNorm.isNotEmpty && mNorm == rNorm;

      if (emailMatch || mobMatch) {
        return m.status;
      }
    }

    if (_myJoinedUnionIds.contains(union.id)) return UnionMemberStatus.accepted;
    if (_myRequestedUnionIds.contains(union.id)) return UnionMemberStatus.pending;

    return null;
  }

  final Set<String> _silencedAlertIds = {};

  bool isAlertSilenced(String alertId) => _silencedAlertIds.contains(alertId);

  /// Silences/turns off the audible siren for a specific alert
  void silenceAlert(String alertId) {
    _silencedAlertIds.add(alertId);
    ConvoyAlarmService().stopAlarm();
    notifyListeners();
  }

  /// Unsilences an alert
  void unsilenceAlert(String alertId) {
    _silencedAlertIds.remove(alertId);
    notifyListeners();
  }

  /// Returns true if the current user belongs to this convoy (Host/Owner or Accepted Member)
  bool isMyConvoy(TravelUnionGroup union) {
    if (isOwner(union)) return true;
    if (_myJoinedUnionIds.contains(union.id)) return true;
    final status = myMembershipStatus(union);
    return status == UnionMemberStatus.accepted;
  }

  /// Returns the active emergency convoy that belongs to the current user (if any)
  TravelUnionGroup? get myActiveEmergencyUnion {
    return _unions.where((u) {
      if (!isMyConvoy(u) || !u.hasActiveEmergency) return false;
      final latest = u.latestEmergency;
      if (latest != null && _silencedAlertIds.contains(latest.id)) return false;
      return true;
    }).firstOrNull;
  }

  /// Restores admin rights for all convoys matching the given contact or join code
  int restoreAdminByContactOrCode(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return 0;
    int restored = 0;

    for (final u in _unions) {
      final codeMatches = u.joinCode.toUpperCase() == clean.toUpperCase();
      final emailMatches =
          u.hostEmail.trim().toLowerCase() == clean.toLowerCase();
      final mobileMatches = u.hostMobile.trim() == clean;

      if (codeMatches || emailMatches || mobileMatches) {
        _myCreatedUnionIds.add(u.id);
        if (emailMatches || codeMatches)
          _myHostEmail = u.hostEmail.trim().toLowerCase();
        if (mobileMatches || codeMatches) _myHostMobile = u.hostMobile.trim();
        restored++;
      }
    }

    if (restored > 0) {
      _saveMyProfile();
      notifyListeners();
    }
    return restored;
  }

  /// Claims host access for a specific convoy
  bool claimSpecificUnionAdmin(String unionId, String codeOrContact) {
    final clean = codeOrContact.trim();
    if (clean.isEmpty) return false;
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return false;
    final u = _unions[idx];

    final codeMatches = u.joinCode.toUpperCase() == clean.toUpperCase();
    final emailMatches =
        u.hostEmail.trim().toLowerCase() == clean.toLowerCase();
    final mobileMatches = u.hostMobile.trim() == clean;

    if (codeMatches || emailMatches || mobileMatches) {
      _myCreatedUnionIds.add(u.id);
      _myHostEmail = u.hostEmail.trim().toLowerCase();
      _myHostMobile = u.hostMobile.trim();
      _saveMyProfile();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Syncs user convoys with their Google Account
  Future<void> syncWithGoogleUser(GoogleUserProfile user) async {
    final emailClean = user.email.trim().toLowerCase();
    if (emailClean.isEmpty) return;

    _myHostEmail = emailClean;
    _myRiderEmail = emailClean;

    for (final u in _unions) {
      if (u.hostEmail.trim().toLowerCase() == emailClean) {
        _myCreatedUnionIds.add(u.id);
      }
    }

    await _saveLocalCache();
    await _saveMyProfile();

    // Pull cloud convoys and groups, then persist the account's ownership and
    // membership index so the same account can restore them on another device.
    await syncWithFirebase();
    for (final u in _unions) {
      final ownsUnion = u.hostEmail.trim().toLowerCase() == emailClean;
      final isMember = u.members.any(
        (m) => m.email.trim().toLowerCase() == emailClean,
      );
      if (ownsUnion) {
        _myCreatedUnionIds.add(u.id);
      } else if (isMember) {
        _myJoinedUnionIds.add(u.id);
      }
    }
    await _syncGroupsWithFirebase(user);
    await _writeGoogleAccountIndex(user);
    await _saveMyProfile();
    notifyListeners();
  }

  Future<void> initialize({String? firebaseProjectId}) async {
    if (_initialized) return;
    _firebaseProjectId = firebaseProjectId ?? _fbProjectId;

    // Initialize Google Auth silently
    try {
      await GoogleAuthService().initialize();
      final gUser = GoogleAuthService().currentUser;
      if (gUser != null) {
        final emailClean = gUser.email.trim().toLowerCase();
        if (emailClean.isNotEmpty) {
          _myHostEmail = emailClean;
          _myRiderEmail = emailClean;
        }
      }
    } catch (_) {}

    // 1. Load user's ownership & rider profile
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final myFile = File('${docDir.path}/my_unions_profile.json');
      if (await myFile.exists()) {
        final data =
            jsonDecode(await myFile.readAsString()) as Map<String, dynamic>;
        _myCreatedUnionIds = Set<String>.from(
          (data['createdUnionIds'] ?? data['unionIds'] as List? ?? []),
        );
        _myJoinedUnionIds = Set<String>.from(
          data['joinedUnionIds'] as List? ?? [],
        );
        _myRequestedUnionIds = Set<String>.from(
          data['requestedUnionIds'] as List? ?? [],
        );
        _myRequestedGroupIds = Set<String>.from(
          data['requestedGroupIds'] as List? ?? [],
        );
        _savedUnionIds = Set<String>.from(data['savedUnionIds'] as List? ?? []);
        _myHostEmail = data['hostEmail'] as String? ?? data['email'] as String?;
        _myHostMobile =
            data['hostMobile'] as String? ?? data['mobile'] as String?;
        _myRiderEmail = data['riderEmail'] as String?;
        _myRiderMobile = data['riderMobile'] as String?;
        _myDeviceId = data['deviceId'] as String?;
      }
    } catch (_) {}

    // 2. Cache schema version migration check
    const int currentCacheVersion = 2;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final verFile = File('${docDir.path}/navguide_cache_version.txt');
      int existingVersion = 0;
      if (await verFile.exists()) {
        existingVersion =
            int.tryParse((await verFile.readAsString()).trim()) ?? 0;
      }
      if (existingVersion < currentCacheVersion) {
        // Upgrade from older app build: clear stale pre-existing test files so only clean remote data is loaded
        final oldUnionsCache = File('${docDir.path}/travel_unions_cache.json');
        if (await oldUnionsCache.exists()) await oldUnionsCache.delete();
        final oldGroupsCache = File('${docDir.path}/travel_groups_cache.json');
        if (await oldGroupsCache.exists()) await oldGroupsCache.delete();
        await verFile.writeAsString('$currentCacheVersion');
      }
    } catch (_) {}

    // 3. Load local storage cache
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheFile = File('${docDir.path}/travel_unions_cache.json');
      if (await cacheFile.exists()) {
        final jsonStr = await cacheFile.readAsString();
        final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
        _unions = list
            .map(
              (item) => TravelUnionGroup.fromJson(item as Map<String, dynamic>),
            )
            .where((u) => !const {'u_101', 'u_102'}.contains(u.id))
            .toList();

        // Clean any foreign unions that were mistakenly included in _myCreatedUnionIds
        _myCreatedUnionIds.removeWhere((id) {
          final match = _unions.where((u) => u.id == id).firstOrNull;
          if (match == null) return false;
          if (match.hostName.trim().toLowerCase() == 'gandu') return true;
          if (_myHostMobile != null &&
              _myHostMobile!.isNotEmpty &&
              match.hostMobile.trim() != _myHostMobile!.trim()) {
            return true;
          }
          return false;
        });
        await _saveMyProfile();
      }
    } catch (_) {}

    _initialized = true;
    // Also load groups
    await _loadGroupsCache();
    notifyListeners();

    // Start active real-time polling so notifications, chats, and requests arrive without delay
    _bgSyncTimer?.cancel();
    _bgSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      syncWithFirebase();
    });

    // Sync with the restored Google account automatically after local caches
    // are ready. This is intentionally fire-and-forget so cold start remains
    // responsive while cloud data arrives in the background.
    final gUser = GoogleAuthService().currentUser;
    if (gUser != null) {
      syncWithGoogleUser(gUser);
    } else {
      syncWithFirebase();
    }
  }

  Future<TravelUnionGroup> createUnion({
    required String title,
    required String fromLocation,
    required String toLocation,
    required String departureDateStr,
    required VehicleCategory category,
    required String hostName,
    required String hostMobile,
    required String hostEmail,
    required String hostVehicle,
    String description = '',
    String viaHighway = '',
    String slogan = '',
    int maxMembers = 10,
    bool isPublicFeed = true,
    String? imageUrl,
  }) async {
    final id = 'u_${DateTime.now().millisecondsSinceEpoch}';
    final joinCode = _generateJoinCode();

    final gUser = GoogleAuthService().currentUser;
    final effectiveHostEmail = hostEmail.trim().isNotEmpty
        ? hostEmail.trim()
        : (gUser?.email ?? '');
    final effectiveHostName = hostName.trim().isNotEmpty
        ? hostName.trim()
        : (gUser?.displayName ?? 'Convoy Host');

    final hostMember = UnionMember(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      name: effectiveHostName,
      mobile: hostMobile,
      email: effectiveHostEmail,
      vehicle: hostVehicle,
      category: category,
      status: UnionMemberStatus.accepted,
      joinedAt: DateTime.now(),
    );

    final newUnion = TravelUnionGroup(
      id: id,
      title: title,
      slogan: slogan.isNotEmpty ? slogan : 'Ride Safe, Ride Together',
      fromLocation: fromLocation,
      toLocation: toLocation,
      viaHighway: viaHighway,
      description: description.isNotEmpty
          ? description
          : 'Join our convoy for a safe, coordinated journey.',
      departureDateStr: departureDateStr,
      category: category,
      hostName: effectiveHostName,
      hostMobile: hostMobile,
      hostEmail: effectiveHostEmail,
      joinCode: joinCode,
      members: [hostMember],
      maxMembers: maxMembers,
      isPublicFeed: isPublicFeed,
      imageUrl: (imageUrl != null && imageUrl.isNotEmpty)
          ? imageUrl
          : getRandomScenicBanner(DateTime.now().millisecondsSinceEpoch),
      createdAt: DateTime.now(),
    );

    _unions.insert(0, newUnion);
    _myCreatedUnionIds.add(id);
    if (hostEmail.trim().isNotEmpty) {
      _myHostEmail = hostEmail.trim().toLowerCase();
    }
    if (hostMobile.trim().isNotEmpty) {
      _myHostMobile = hostMobile.trim();
    }

    await _saveLocalCache();
    await _saveMyProfile();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(newUnion);
    }

    return newUnion;
  }

  Future<void> updateUnion({
    required String unionId,
    required String title,
    required String fromLocation,
    required String toLocation,
    required String departureDateStr,
    required VehicleCategory category,
    required String hostName,
    required String hostMobile,
    required String hostEmail,
    required String hostVehicle,
    String? description,
    String? viaHighway,
    String? slogan,
    int maxMembers = 10,
    String? imageUrl,
  }) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;
    if (!canEditConvoy(_unions[idx])) return;

    final old = _unions[idx];
    final updatedMembers = old.members.map((m) {
      if (m.email == old.hostEmail || m.name == old.hostName) {
        return UnionMember(
          id: m.id,
          name: hostName.isNotEmpty ? hostName : m.name,
          mobile: hostMobile.isNotEmpty ? hostMobile : m.mobile,
          email: hostEmail.isNotEmpty ? hostEmail : m.email,
          vehicle: hostVehicle.isNotEmpty ? hostVehicle : m.vehicle,
          category: category,
          status: m.status,
          joinedAt: m.joinedAt,
        );
      }
      return m;
    }).toList();

    final updated = TravelUnionGroup(
      id: old.id,
      title: title,
      slogan: slogan ?? old.slogan,
      fromLocation: fromLocation,
      toLocation: toLocation,
      viaHighway: viaHighway ?? old.viaHighway,
      description: description ?? old.description,
      departureDateStr: departureDateStr,
      category: category,
      hostName: hostName.isNotEmpty ? hostName : old.hostName,
      hostMobile: hostMobile.isNotEmpty ? hostMobile : old.hostMobile,
      hostEmail: hostEmail.isNotEmpty ? hostEmail : old.hostEmail,
      joinCode: old.joinCode,
      members: updatedMembers,
      chatMessages: old.chatMessages,
      liveRiders: old.liveRiders,
      activeAlerts: old.activeAlerts,
      maxMembers: maxMembers,
      imageUrl: (imageUrl != null && imageUrl.isNotEmpty)
          ? imageUrl
          : old.imageUrl,
      createdAt: old.createdAt,
    );

    _unions[idx] = updated;
    if (hostMobile.trim().isNotEmpty) {
      _myHostMobile = hostMobile.trim();
    }
    if (hostEmail.trim().isNotEmpty) {
      _myHostEmail = hostEmail.trim().toLowerCase();
    }
    await _saveLocalCache();
    await _saveMyProfile();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(updated);
    }
  }

  Future<void> deleteUnion(String unionId) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx != -1 && !isOwner(_unions[idx])) {
      // Security guard: Only the creator/host can delete this union!
      return;
    }
    _unions.removeWhere((u) => u.id == unionId);
    _myCreatedUnionIds.remove(unionId);
    for (int i = 0; i < _groups.length; i++) {
      if (_groups[i].convoyIds.contains(unionId)) {
        _groups[i] = _groups[i].copyWith(
          convoyIds: _groups[i].convoyIds.where((id) => id != unionId).toList(),
        );
      }
    }
    await _saveLocalCache();
    await _saveGroupsCache();
    await _saveMyProfile();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _deleteUnionFromFirebase(unionId);
    }
  }

  Future<bool> requestToJoin({
    required String joinCodeOrId,
    required String riderName,
    required String riderMobile,
    required String riderEmail,
    required String riderVehicle,
    required VehicleCategory category,
  }) async {
    final codeClean = joinCodeOrId.trim().toUpperCase();
    final idx = _unions.indexWhere(
      (u) =>
          u.joinCode.toUpperCase() == codeClean ||
          u.id.toUpperCase() == codeClean,
    );

    if (idx == -1) return false;

    final targetUnion = _unions[idx];

    // Enforce team size limit: cannot request to join if convoy is already full!
    if (targetUnion.isFull) {
      return false;
    }

    // Prevent duplicate join requests from the same user
    final emailClean = riderEmail.trim().toLowerCase();
    final mobileClean = riderMobile.trim();
    final alreadyMember = targetUnion.members.any((m) {
      if (emailClean.isNotEmpty && m.email.trim().toLowerCase() == emailClean)
        return true;
      if (mobileClean.isNotEmpty && m.mobile.trim() == mobileClean) return true;
      return false;
    });
    if (alreadyMember) return false;

    final memberId = 'm_${DateTime.now().millisecondsSinceEpoch}';

    final newMember = UnionMember(
      id: memberId,
      name: riderName,
      mobile: riderMobile,
      email: riderEmail,
      vehicle: riderVehicle,
      category: category,
      status: UnionMemberStatus.pending, // Pending host approval!
      joinedAt: DateTime.now(),
    );

    final updatedMembers = List<UnionMember>.from(targetUnion.members)
      ..add(newMember);

    final updatedUnion = TravelUnionGroup(
      id: targetUnion.id,
      title: targetUnion.title,
      fromLocation: targetUnion.fromLocation,
      toLocation: targetUnion.toLocation,
      departureDateStr: targetUnion.departureDateStr,
      category: targetUnion.category,
      hostName: targetUnion.hostName,
      hostMobile: targetUnion.hostMobile,
      hostEmail: targetUnion.hostEmail,
      joinCode: targetUnion.joinCode,
      members: updatedMembers,
      maxMembers: targetUnion.maxMembers,
      createdAt: targetUnion.createdAt,
    );

    _unions[idx] = updatedUnion;

    // Record rider credentials and pending request so membership badge updates — NEVER add to _myCreatedUnionIds!
    _myRequestedUnionIds.add(targetUnion.id);
    _myRiderEmail = riderEmail.trim().toLowerCase();
    _myRiderMobile = riderMobile.trim();

    await _saveMyProfile();
    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(updatedUnion);
    }

    return true;
  }

  Future<bool> respondToJoinRequest({
    required String unionId,
    required String memberId,
    required bool accept,
  }) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return false;

    final targetUnion = _unions[idx];

    // Enforce team size limit: if accepting and convoy has reached capacity, reject acceptance!
    if (accept && targetUnion.isFull) {
      return false;
    }

    final updatedMembers = targetUnion.members.map((m) {
      if (m.id == memberId) {
        return UnionMember(
          id: m.id,
          name: m.name,
          mobile: m.mobile,
          email: m.email,
          vehicle: m.vehicle,
          category: m.category,
          status: accept
              ? UnionMemberStatus.accepted
              : UnionMemberStatus.rejected,
          joinedAt: m.joinedAt,
        );
      }
      return m;
    }).toList();

    _unions[idx] = TravelUnionGroup(
      id: targetUnion.id,
      title: targetUnion.title,
      fromLocation: targetUnion.fromLocation,
      toLocation: targetUnion.toLocation,
      departureDateStr: targetUnion.departureDateStr,
      category: targetUnion.category,
      hostName: targetUnion.hostName,
      hostMobile: targetUnion.hostMobile,
      hostEmail: targetUnion.hostEmail,
      joinCode: targetUnion.joinCode,
      members: updatedMembers,
      maxMembers: targetUnion.maxMembers,
      createdAt: targetUnion.createdAt,
    );

    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(_unions[idx]);
    }

    return true;
  }

  /// Allows a joined/pending member to exit/leave a convoy
  Future<void> leaveUnion(String unionId) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;

    final targetUnion = _unions[idx];
    final rEmail = (_myRiderEmail ?? _myHostEmail)?.trim().toLowerCase();
    final rMobile = (_myRiderMobile ?? _myHostMobile)?.trim();

    // Remove rider matching user credentials (host cannot leave this way)
    final updatedMembers = targetUnion.members.where((m) {
      if (m.email.trim().toLowerCase() ==
          targetUnion.hostEmail.trim().toLowerCase())
        return true;
      if (rEmail != null &&
          rEmail.isNotEmpty &&
          m.email.trim().toLowerCase() == rEmail)
        return false;
      if (rMobile != null && rMobile.isNotEmpty && m.mobile.trim() == rMobile)
        return false;
      return true;
    }).toList();

    _unions[idx] = TravelUnionGroup(
      id: targetUnion.id,
      title: targetUnion.title,
      fromLocation: targetUnion.fromLocation,
      toLocation: targetUnion.toLocation,
      departureDateStr: targetUnion.departureDateStr,
      category: targetUnion.category,
      hostName: targetUnion.hostName,
      hostMobile: targetUnion.hostMobile,
      hostEmail: targetUnion.hostEmail,
      joinCode: targetUnion.joinCode,
      members: updatedMembers,
      maxMembers: targetUnion.maxMembers,
      createdAt: targetUnion.createdAt,
    );

    _myJoinedUnionIds.remove(unionId);
    _myRequestedUnionIds.remove(unionId);
    await _saveMyProfile();
    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(_unions[idx]);
    }
  }

  Future<void> cancelJoinRequest(String unionId) async {
    await leaveUnion(unionId);
  }

  /// Allows the convoy Host to kick/remove a member
  Future<void> kickMember({
    required String unionId,
    required String memberId,
  }) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;
    if (!isOwner(_unions[idx])) return; // Strict security: Only Host can kick!

    final targetUnion = _unions[idx];
    final updatedMembers = targetUnion.members.where((m) {
      // Cannot kick the host
      if (m.id == memberId &&
          m.email.trim().toLowerCase() !=
              targetUnion.hostEmail.trim().toLowerCase()) {
        return false;
      }
      return true;
    }).toList();

    _unions[idx] = TravelUnionGroup(
      id: targetUnion.id,
      title: targetUnion.title,
      fromLocation: targetUnion.fromLocation,
      toLocation: targetUnion.toLocation,
      departureDateStr: targetUnion.departureDateStr,
      category: targetUnion.category,
      hostName: targetUnion.hostName,
      hostMobile: targetUnion.hostMobile,
      hostEmail: targetUnion.hostEmail,
      joinCode: targetUnion.joinCode,
      members: updatedMembers,
      maxMembers: targetUnion.maxMembers,
      createdAt: targetUnion.createdAt,
    );

    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(_unions[idx]);
    }
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  Future<void> _saveLocalCache() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheFile = File('${docDir.path}/travel_unions_cache.json');
      final jsonList = _unions.map((u) => u.toJson()).toList();
      await cacheFile.writeAsString(jsonEncode(jsonList));
    } catch (_) {}
  }

  Future<void> _saveMyProfile() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final myFile = File('${docDir.path}/my_unions_profile.json');
      await myFile.writeAsString(
        jsonEncode({
          'createdUnionIds': _myCreatedUnionIds.toList(),
          'joinedUnionIds': _myJoinedUnionIds.toList(),
          'requestedUnionIds': _myRequestedUnionIds.toList(),
          'requestedGroupIds': _myRequestedGroupIds.toList(),
          'savedUnionIds': _savedUnionIds.toList(),
          'hostEmail': _myHostEmail,
          'hostMobile': _myHostMobile,
          'riderEmail': _myRiderEmail,
          'riderMobile': _myRiderMobile,
          'deviceId': _myDeviceId,
          'myRatings': _myRatings.map((k, v) => MapEntry(k, v)),
        }),
      );
    } catch (_) {}
  }

  // Lightweight fingerprint of the current state to skip no-op notifies
  String _lastUnionFingerprint = '';
  String _lastGroupFingerprint = '';

  String _computeFingerprint(List<TravelUnionGroup> unions) {
    // Include member statuses so pending→accepted triggers a rebuild
    final buf = StringBuffer();
    for (final u in unions) {
      buf
        ..write(u.id)
        ..write(':')
        ..write(u.liveRiders.length)
        ..write(':')
        ..write(u.activeAlerts.length)
        ..write(':');
      for (final m in u.members) {
        buf
          ..write(m.id)
          ..write('=')
          ..write(m.status.name)
          ..write(';');
      }
      buf
        ..write(':')
        ..write(u.chatMessages.length)
        ..write('|');
    }
    return buf.toString();
  }

  String _computeGroupFingerprint(List<TravelGroup> groups) {
    final buf = StringBuffer();
    for (final g in groups) {
      buf
        ..write(g.id)
        ..write(':')
        ..write(g.chatMessages.length)
        ..write(':');
      if (g.chatMessages.isNotEmpty) {
        buf.write(g.chatMessages.last.id);
      }
      buf.write(':');
      for (final m in g.members) {
        buf
          ..write(m.id)
          ..write('=')
          ..write(m.isPending ? 'p' : 'a')
          ..write(';');
      }
      buf.write('|');
    }
    return buf.toString();
  }

  /// Syncs Travel Unions over Firebase Firestore REST API
  Future<void> syncWithFirebase() async {
    final projectId = _firebaseProjectId ?? _fbProjectId;
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/unions?key=$_fbApiKey',
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(url);
      req.headers.add('Accept', 'application/json');
      final res = await req.close();

      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json.containsKey('documents') && json['documents'] is List) {
          final List<TravelUnionGroup> remoteUnions = [];
          final List<TravelGroup> remoteGroups = [];
          for (final doc in (json['documents'] as List)) {
            try {
              final fields = doc['fields'] as Map<String, dynamic>;
              if (fields.containsKey('groupData')) {
                final rawJson = fields['groupData']['stringValue'] as String;
                remoteGroups.add(TravelGroup.fromJson(jsonDecode(rawJson)));
              } else if (fields.containsKey('unionData')) {
                final rawJson = fields['unionData']['stringValue'] as String;
                remoteUnions.add(TravelUnionGroup.fromJson(jsonDecode(rawJson)));
              }
            } catch (_) {}
          }
          if (remoteGroups.isNotEmpty) {
            final remoteGroupIds = remoteGroups.map((g) => g.id).toSet();
            final localOnlyGroups = _groups
                .where((g) =>
                    !remoteGroupIds.contains(g.id) &&
                    _myCreatedGroupIds.contains(g.id))
                .toList();
            _groups = [...remoteGroups, ...localOnlyGroups];
            await _saveGroupsCache();
            // Notify on group changes (new chats, approved members)
            final gfp = _computeGroupFingerprint(_groups);
            if (gfp != _lastGroupFingerprint) {
              _lastGroupFingerprint = gfp;
              notifyListeners();
            }
          }
          if (remoteUnions.isNotEmpty) {
            final remoteIds = remoteUnions.map((u) => u.id).toSet();
            final localOnly = _unions
                .where((u) =>
                    !remoteIds.contains(u.id) &&
                    _myCreatedUnionIds.contains(u.id))
                .toList();

            // Merge real-time rider GPS from this device when the remote copy has
            // not received a newer rider list yet.
            final merged = remoteUnions.map((ru) {
              final local = _unions.where((u) => u.id == ru.id).firstOrNull;
              if (local != null &&
                  local.liveRiders.isNotEmpty &&
                  ru.liveRiders.isEmpty) {
                return _stripDemoLiveRiders(
                  ru.copyWith(liveRiders: local.liveRiders),
                );
              }
              return _stripDemoLiveRiders(ru);
            }).toList();

            _unions = [...merged, ...localOnly.map(_stripDemoLiveRiders)];
            await _saveLocalCache();

            // Clean any foreign unions that were mistakenly included in _myCreatedUnionIds
            _myCreatedUnionIds.removeWhere((id) {
              final match = _unions.where((u) => u.id == id).firstOrNull;
              if (match == null) return false;
              if (match.hostName.trim().toLowerCase() == 'gandu') return true;
              if (_myHostMobile != null &&
                  _myHostMobile!.isNotEmpty &&
                  match.hostMobile.trim() != _myHostMobile!.trim()) {
                return true;
              }
              return false;
            });
            await _saveMyProfile();

            // Auto-trigger native siren alarm ONLY if a convoy the user belongs to has an active un-silenced emergency
            final myEmergencyUnion = _unions.where((u) {
              if (!isMyConvoy(u) || !u.hasActiveEmergency) return false;
              final latest = u.latestEmergency;
              if (latest != null && _silencedAlertIds.contains(latest.id))
                return false;
              return true;
            }).firstOrNull;

            final hasMyEmergency = myEmergencyUnion != null;
            if (hasMyEmergency && !ConvoyAlarmService().isPlaying) {
              ConvoyAlarmService().startAlarm();
            } else if (!hasMyEmergency && ConvoyAlarmService().isPlaying) {
              ConvoyAlarmService().stopAlarm();
            }

            // Skip notify if nothing meaningful changed (avoids unnecessary rebuilds)
            final newFingerprint = _computeFingerprint(_unions);
            if (newFingerprint != _lastUnionFingerprint) {
              _lastUnionFingerprint = newFingerprint;
              notifyListeners();
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<Map<String, Set<String>>> _readGoogleAccountIndex(String email) async {
    final projectId = _firebaseProjectId ?? _fbProjectId;
    final result = <String, Set<String>>{
      'unionIds': <String>{},
      'savedUnionIds': <String>{},
      'createdGroupIds': <String>{},
      'joinedGroupIds': <String>{},
    };
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/accounts/${Uri.encodeComponent(email)}?key=$_fbApiKey',
      );
      final client = HttpClient();
      final req = await client.getUrl(url);
      req.headers.add('Accept', 'application/json');
      final res = await req.close();
      if (res.statusCode != 200) return result;
      final raw = jsonDecode(
        await res.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      final fields = raw['fields'] as Map<String, dynamic>? ?? {};
      for (final key in result.keys) {
        final values =
            (fields[key] as Map<String, dynamic>?)?['arrayValue']
                as Map<String, dynamic>?;
        final rawValues = values?['values'] as List<dynamic>? ?? [];
        result[key] = rawValues
            .map((v) => (v as Map<String, dynamic>)['stringValue'] as String?)
            .whereType<String>()
            .toSet();
      }
    } catch (_) {}
    return result;
  }

  Future<List<TravelGroup>> _fetchGroupsFromFirebase() async {
    final projectId = _firebaseProjectId ?? _fbProjectId;
    final groups = <TravelGroup>[];
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/unions?key=$_fbApiKey',
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(url);
      req.headers.add('Accept', 'application/json');
      final res = await req.close();
      if (res.statusCode != 200) return groups;
      final body = jsonDecode(
        await res.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      for (final doc in body['documents'] as List<dynamic>? ?? []) {
        try {
          final fields = doc['fields'] as Map<String, dynamic>;
          if (fields.containsKey('groupData')) {
            final raw = fields['groupData']['stringValue'] as String;
            groups.add(TravelGroup.fromJson(jsonDecode(raw)));
          }
        } catch (_) {}
      }
    } catch (_) {}
    return groups;
  }

  Future<void> _syncGroupsWithFirebase(GoogleUserProfile user) async {
    final account = await _readGoogleAccountIndex(user.email);
    final remoteGroups = await _fetchGroupsFromFirebase();
    final remoteIds = remoteGroups.map((g) => g.id).toSet();
    final localOnly = _groups
        .where((g) =>
            !remoteIds.contains(g.id) && _myCreatedGroupIds.contains(g.id))
        .toList();
    _groups = [...remoteGroups, ...localOnly];

    _savedUnionIds.addAll(account['savedUnionIds'] ?? {});
    _myCreatedGroupIds.addAll(account['createdGroupIds'] ?? {});
    _myJoinedGroupIds.addAll(account['joinedGroupIds'] ?? {});
    await _saveMyProfile();
    await _saveGroupsCache();

    // Upload only groups this account created or joined, never the bundled
    // sample groups shown to guests.
    final accountGroupIds = {..._myCreatedGroupIds, ..._myJoinedGroupIds};
    for (final group in _groups.where((g) => accountGroupIds.contains(g.id))) {
      await _postGroupToFirebase(group, ownerEmail: user.email);
    }
  }

  Future<void> _writeGoogleAccountIndex(GoogleUserProfile user) async {
    final projectId = _firebaseProjectId ?? _fbProjectId;
    try {
      final unionIds = {..._myCreatedUnionIds, ..._myJoinedUnionIds};
      final createdGroupIds = {..._myCreatedGroupIds};
      final joinedGroupIds = {..._myJoinedGroupIds};
      final values = (Set<String> ids) => {
        'arrayValue': {
          'values': ids.map((id) => {'stringValue': id}).toList(),
        },
      };
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/accounts/${Uri.encodeComponent(user.email)}?key=$_fbApiKey',
      );
      final client = HttpClient();
      final req = await client.patchUrl(url);
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'fields': {
            'email': {'stringValue': user.email.trim().toLowerCase()},
            'displayName': {'stringValue': user.displayName},
            'unionIds': values(unionIds),
            'savedUnionIds': values(_savedUnionIds),
            'createdGroupIds': values(createdGroupIds),
            'joinedGroupIds': values(joinedGroupIds),
            'updatedAt': {'stringValue': DateTime.now().toIso8601String()},
          },
        }),
      );
      await req.close();
    } catch (_) {}
  }

  Future<void> _postGroupToFirebase(
    TravelGroup group, {
    String? ownerEmail,
  }) async {
    final projectId = _firebaseProjectId ?? _fbProjectId;
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/unions/${Uri.encodeComponent(group.id)}?key=$_fbApiKey',
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.patchUrl(url);
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'fields': {
            'groupData': {'stringValue': jsonEncode(group.toJson())},
            'docType': {'stringValue': 'group'},
            'name': {'stringValue': group.name},
            'category': {'stringValue': group.category},
            'ownerEmail': {'stringValue': (ownerEmail ?? '').trim().toLowerCase()},
            'updatedAt': {'stringValue': DateTime.now().toIso8601String()},
          },
        }),
      );
      await req.close();
    } catch (_) {}
  }

  Future<void> _postUnionToFirebase(TravelUnionGroup union) async {
    final projectId = _firebaseProjectId ?? _fbProjectId;
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/unions/${union.id}?key=$_fbApiKey',
      );
      final client = HttpClient();
      final req = await client.patchUrl(url);
      req.headers.contentType = ContentType.json;
      req.headers.add('Accept', 'application/json');

      final body = jsonEncode({
        'fields': {
          'unionData': {'stringValue': jsonEncode(union.toJson())},
          'updatedAt': {'stringValue': DateTime.now().toIso8601String()},
          'joinCode': {'stringValue': union.joinCode},
          'title': {'stringValue': union.title},
          'from': {'stringValue': union.fromLocation},
          'to': {'stringValue': union.toLocation},
        },
      });
      req.write(body);
      await req.close();
    } catch (_) {}
  }

  Future<void> _deleteUnionFromFirebase(String unionId) async {
    final projectId = _firebaseProjectId ?? _fbProjectId;
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/unions/$unionId?key=$_fbApiKey',
      );
      final client = HttpClient();
      final req = await client.deleteUrl(url);
      await req.close();
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────
  //  GROUPS SERVICE (community layer)
  // ─────────────────────────────────────────────────────────

  List<TravelGroup> _groups = [];
  Set<String> _myCreatedGroupIds = {};
  Set<String> _myJoinedGroupIds = {};

  List<TravelGroup> get groups => List.unmodifiable(_groups);

  bool isGroupAdmin(TravelGroup g) {
    if (_myCreatedGroupIds.contains(g.id)) return true;
    final myMobs = {
      if (myRiderMobile != null && myRiderMobile!.isNotEmpty)
        normalizePhone(myRiderMobile!),
      if (myHostMobile != null && myHostMobile!.isNotEmpty)
        normalizePhone(myHostMobile!),
    };
    for (final m in g.members) {
      if (m.role == GroupMemberRole.admin && !m.isPending) {
        if (myMobs.isNotEmpty && myMobs.contains(normalizePhone(m.mobile))) {
          return true;
        }
      }
    }
    return false;
  }

  GroupMembershipStatus myGroupMembershipStatus(TravelGroup g) {
    if (isGroupAdmin(g)) return GroupMembershipStatus.admin;

    final myMobs = {
      if (myRiderMobile != null && myRiderMobile!.isNotEmpty)
        normalizePhone(myRiderMobile!),
      if (myHostMobile != null && myHostMobile!.isNotEmpty)
        normalizePhone(myHostMobile!),
    };

    for (final m in g.members) {
      final mNorm = normalizePhone(m.mobile);
      final mobMatch = mNorm.isNotEmpty && myMobs.contains(mNorm);
      if (mobMatch) {
        if (m.role == GroupMemberRole.admin && !m.isPending) {
          return GroupMembershipStatus.admin;
        }
        return m.isPending
            ? GroupMembershipStatus.pending
            : GroupMembershipStatus.accepted;
      }
    }

    if (_myJoinedGroupIds.contains(g.id)) {
      final isPending = g.members.any((m) {
        final mNorm = normalizePhone(m.mobile);
        return m.isPending && (mNorm.isEmpty || myMobs.contains(mNorm));
      });
      if (!g.isPublic && isPending) return GroupMembershipStatus.pending;
      return GroupMembershipStatus.accepted;
    }

    if (_myRequestedGroupIds.contains(g.id)) {
      return GroupMembershipStatus.pending;
    }

    return GroupMembershipStatus.none;
  }

  bool isGroupMember(TravelGroup g) {
    final status = myGroupMembershipStatus(g);
    return status == GroupMembershipStatus.admin ||
        status == GroupMembershipStatus.accepted;
  }

  bool isGroupPending(TravelGroup g) {
    return myGroupMembershipStatus(g) == GroupMembershipStatus.pending;
  }

  Future<void> setConvoyPublicity(String convoyId, bool isPublic) async {
    final idx = _unions.indexWhere((u) => u.id == convoyId);
    if (idx != -1) {
      _unions[idx] = _unions[idx].copyWith(isPublicFeed: isPublic);
      await _saveLocalCache();
      notifyListeners();
    }
  }

  Future<void> _loadGroupsCache() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final f = File('${docDir.path}/travel_groups_cache.json');
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _groups = (raw['groups'] as List<dynamic>? ?? [])
            .map((e) => TravelGroup.fromJson(e as Map<String, dynamic>))
            .toList();
        _myCreatedGroupIds = Set<String>.from(
          raw['myCreatedGroupIds'] as List<dynamic>? ?? [],
        );
        _myJoinedGroupIds = Set<String>.from(
          raw['myJoinedGroupIds'] as List<dynamic>? ?? [],
        );
      } else {
        _seedDemoGroups();
        _myCreatedGroupIds = {};
        _myJoinedGroupIds = {};
      }
    } catch (_) {
      _seedDemoGroups();
      _myCreatedGroupIds = {};
      _myJoinedGroupIds = {};
    }
  }

  void _seedDemoGroups() {
    _groups = [];
  }

  Future<void> _saveGroupsCache() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final f = File('${docDir.path}/travel_groups_cache.json');
      await f.writeAsString(
        jsonEncode({
          'groups': _groups.map((g) => g.toJson()).toList(),
          'myCreatedGroupIds': _myCreatedGroupIds.toList(),
          'myJoinedGroupIds': _myJoinedGroupIds.toList(),
        }),
      );
    } catch (_) {}
  }

  Future<TravelGroup> createGroup({
    required String name,
    required String description,
    required String category,
    required bool isPublic,
    required String emoji,
    required String adminName,
    required String adminMobile,
    String? imageUrl,
  }) async {
    final id = 'grp_${DateTime.now().millisecondsSinceEpoch}';
    final admin = GroupMember(
      id: 'gm_${DateTime.now().millisecondsSinceEpoch}',
      name: adminName,
      mobile: adminMobile,
      role: GroupMemberRole.admin,
      joinedAt: DateTime.now(),
    );
    final group = TravelGroup(
      id: id,
      name: name,
      description: description,
      category: category,
      isPublic: isPublic,
      emoji: emoji,
      imageUrl: imageUrl?.isNotEmpty == true
          ? imageUrl!
          : getRandomScenicBanner(DateTime.now().millisecondsSinceEpoch),
      members: [admin],
      createdAt: DateTime.now(),
    );
    _groups.insert(0, group);
    _myCreatedGroupIds.add(id);
    await _saveGroupsCache();
    await _saveMyProfile();
    notifyListeners();
    final gUser = GoogleAuthService().currentUser;
    await _postGroupToFirebase(group, ownerEmail: gUser?.email);
    if (gUser != null) {
      await _writeGoogleAccountIndex(gUser);
    }
    return group;
  }

  Future<void> joinGroup(
    String groupId, {
    required String name,
    required String mobile,
  }) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    final normMob = normalizePhone(mobile);
    // Already a member?
    if (g.members.any((m) =>
        normalizePhone(m.mobile) == normMob && normMob.isNotEmpty)) return;

    final member = GroupMember(
      id: 'gm_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      mobile: mobile,
      joinedAt: DateTime.now(),
      isPending: !g.isPublic, // pending if private group
    );
    _groups[idx] = g.copyWith(members: [...g.members, member]);
    if (!g.isPublic) {
      _myRequestedGroupIds.add(groupId);
    } else {
      _myJoinedGroupIds.add(groupId);
    }
    if (mobile.trim().isNotEmpty &&
        (_myRiderMobile == null || _myRiderMobile!.isEmpty)) {
      _myRiderMobile = mobile.trim();
    }
    await _saveGroupsCache();
    await _saveMyProfile();
    notifyListeners();
    final gUser = GoogleAuthService().currentUser;
    await _postGroupToFirebase(_groups[idx], ownerEmail: gUser?.email);
    if (gUser != null) {
      await _writeGoogleAccountIndex(gUser);
    }
  }

  Future<void> approveGroupMember(String groupId, String memberId) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    final updatedMembers = g.members.map((m) {
      if (m.id == memberId) return m.copyWith(isPending: false);
      return m;
    }).toList();
    _groups[idx] = g.copyWith(members: updatedMembers);
    await _saveGroupsCache();
    await _saveMyProfile();
    notifyListeners();
    final gUser = GoogleAuthService().currentUser;
    await _postGroupToFirebase(_groups[idx], ownerEmail: gUser?.email);
    if (gUser != null) {
      await _writeGoogleAccountIndex(gUser);
    }
  }

  Future<void> rejectGroupMember(String groupId, String memberId) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    _groups[idx] = g.copyWith(
      members: g.members.where((m) => m.id != memberId).toList(),
    );
    await _saveGroupsCache();
    await _saveMyProfile();
    notifyListeners();
    final gUser = GoogleAuthService().currentUser;
    await _postGroupToFirebase(_groups[idx], ownerEmail: gUser?.email);
    if (gUser != null) {
      await _writeGoogleAccountIndex(gUser);
    }
  }

  Future<void> leaveGroup(String groupId, {String? mobile}) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    final targetMobiles = {
      if (mobile != null && mobile.isNotEmpty) normalizePhone(mobile),
      if (myRiderMobile != null && myRiderMobile!.isNotEmpty)
        normalizePhone(myRiderMobile!),
      if (myHostMobile != null && myHostMobile!.isNotEmpty)
        normalizePhone(myHostMobile!),
    };
    final updatedMembers = g.members.where((m) {
      final mNorm = normalizePhone(m.mobile);
      if (targetMobiles.isNotEmpty && targetMobiles.contains(mNorm)) {
        return false;
      }
      return true;
    }).toList();
    _groups[idx] = g.copyWith(members: updatedMembers);
    _myJoinedGroupIds.remove(groupId);
    _myRequestedGroupIds.remove(groupId);
    _myCreatedGroupIds.remove(groupId);
    await _saveGroupsCache();
    await _saveMyProfile();
    notifyListeners();
    final gUser = GoogleAuthService().currentUser;
    await _postGroupToFirebase(_groups[idx], ownerEmail: gUser?.email);
    if (gUser != null) {
      await _writeGoogleAccountIndex(gUser);
    }
  }

  Future<void> removeGroupMember(String groupId, String memberId) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    _groups[idx] = g.copyWith(
      members: g.members.where((m) => m.id != memberId).toList(),
    );
    await _saveGroupsCache();
    notifyListeners();
    final gUser = GoogleAuthService().currentUser;
    await _postGroupToFirebase(_groups[idx], ownerEmail: gUser?.email);
    if (gUser != null) {
      await _writeGoogleAccountIndex(gUser);
    }
  }

  /// Grants Admin role to a member or transfers group ownership
  Future<bool> transferGroupAdmin({
    required String groupId,
    required String targetMemberId,
    bool relinquishAdmin = false,
  }) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return false;
    final g = _groups[idx];
    if (!isGroupAdmin(g)) return false;

    final updatedMembers = g.members.map((m) {
      if (m.id == targetMemberId) {
        return m.copyWith(role: GroupMemberRole.admin);
      }
      return m;
    }).toList();

    _groups[idx] = g.copyWith(members: updatedMembers);
    if (relinquishAdmin) {
      _myCreatedGroupIds.remove(groupId);
    }
    await _saveGroupsCache();
    notifyListeners();
    _postGroupToFirebase(_groups[idx]);
    return true;
  }

  Future<void> updateGroup(
    String groupId, {
    String? name,
    String? description,
    String? category,
    bool? isPublic,
    String? emoji,
    String? imageUrl,
  }) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    _groups[idx] = g.copyWith(
      name: name ?? g.name,
      description: description ?? g.description,
      category: category ?? g.category,
      isPublic: isPublic ?? g.isPublic,
      emoji: emoji ?? g.emoji,
      imageUrl: imageUrl ?? g.imageUrl,
    );
    await _saveGroupsCache();
    notifyListeners();
    _postGroupToFirebase(_groups[idx]);
  }

  Future<void> sendGroupChatMessage(
    String groupId, {
    required String text,
    required String senderName,
    required String senderId,
    bool isAdmin = false,
  }) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    final msg = GroupChatMessage(
      id: 'gcm_${DateTime.now().millisecondsSinceEpoch}',
      senderName: senderName,
      senderId: senderId,
      text: text,
      timestamp: DateTime.now(),
      isAdmin: isAdmin,
    );
    _groups[idx] = g.copyWith(chatMessages: [...g.chatMessages, msg]);
    await _saveGroupsCache();
    notifyListeners();
    _postGroupToFirebase(_groups[idx]);
  }

  Future<void> deleteGroupChatMessage(String groupId, String messageId) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    _groups[idx] = g.copyWith(
      chatMessages: g.chatMessages.where((m) => m.id != messageId).toList(),
    );
    await _saveGroupsCache();
    notifyListeners();
    _postGroupToFirebase(_groups[idx]);
  }

  Future<void> linkConvoyToGroup(String groupId, String convoyId) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    if (!g.convoyIds.contains(convoyId)) {
      _groups[idx] = g.copyWith(convoyIds: [...g.convoyIds, convoyId]);
      await _saveGroupsCache();
      notifyListeners();
    }
  }

  Future<void> _deleteGroupFromFirebase(String groupId) async {
    final projectId = _firebaseProjectId ?? _fbProjectId;
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/unions/${Uri.encodeComponent(groupId)}?key=$_fbApiKey',
      );
      final client = HttpClient();
      final req = await client.deleteUrl(url);
      await req.close();
    } catch (_) {}
  }

  Future<void> clearLocalCacheAndRefresh() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final oldUnionsCache = File('${docDir.path}/travel_unions_cache.json');
      if (await oldUnionsCache.exists()) await oldUnionsCache.delete();
      final oldGroupsCache = File('${docDir.path}/travel_groups_cache.json');
      if (await oldGroupsCache.exists()) await oldGroupsCache.delete();
    } catch (_) {}
    _unions.clear();
    _groups.clear();
    notifyListeners();
    await syncWithFirebase();
    final gUser = GoogleAuthService().currentUser;
    if (gUser != null) {
      await syncWithGoogleUser(gUser);
    }
  }

  Future<void> deleteGroup(String groupId) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    final g = _groups[idx];
    if (!isGroupAdmin(g)) return;

    // Delete any convoys created under this group
    for (final cid in g.convoyIds) {
      _unions.removeWhere((u) => u.id == cid);
      _myCreatedUnionIds.remove(cid);
      _deleteUnionFromFirebase(cid);
    }
    _groups.removeAt(idx);
    _myCreatedGroupIds.remove(groupId);
    _myJoinedGroupIds.remove(groupId);
    await _saveLocalCache();
    await _saveGroupsCache();
    await _deleteGroupFromFirebase(groupId);
    notifyListeners();
  }

  Future<void> removeConvoyFromGroup(String groupId, String convoyId) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx != -1) {
      final g = _groups[idx];
      _groups[idx] = g.copyWith(
        convoyIds: g.convoyIds.where((id) => id != convoyId).toList(),
      );
      await _saveGroupsCache();
    }
    _unions.removeWhere((u) => u.id == convoyId);
    _myCreatedUnionIds.remove(convoyId);
    await _saveLocalCache();
    notifyListeners();
  }
}
