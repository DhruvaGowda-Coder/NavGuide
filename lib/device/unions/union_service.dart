import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/union_models.dart';

class UnionService extends ChangeNotifier {
  static final UnionService _instance = UnionService._internal();
  factory UnionService() => _instance;
  UnionService._internal();

  // ── Firebase / Firestore config (diary-13644 project) ──
  static const String _fbProjectId = 'diary-13644';
  static const String _fbApiKey   = 'AIzaSyCFkg5ywh9TX0lGglxsVeR6K8JF-BFC7Zc';

  List<TravelUnionGroup> _unions = [];
  bool _initialized = false;
  String? _firebaseProjectId;

  // Track unions created on this device / user profile
  Set<String> _myCreatedUnionIds = {};
  String? _myEmail;
  String? _myMobile;

  List<TravelUnionGroup> get unions => List.unmodifiable(_unions);

  bool isOwner(TravelUnionGroup union) {
    if (_myCreatedUnionIds.contains(union.id)) return true;
    if (_myEmail != null &&
        _myEmail!.trim().isNotEmpty &&
        union.hostEmail.trim().toLowerCase() == _myEmail!.trim().toLowerCase()) {
      return true;
    }
    if (_myMobile != null &&
        _myMobile!.trim().isNotEmpty &&
        union.hostMobile.trim() == _myMobile!.trim()) {
      return true;
    }
    return false;
  }

  UnionMemberStatus? myMembershipStatus(TravelUnionGroup union) {
    if (isOwner(union)) return UnionMemberStatus.accepted;
    for (final m in union.members) {
      if ((_myEmail != null && _myEmail!.isNotEmpty && m.email.trim().toLowerCase() == _myEmail!.toLowerCase()) ||
          (_myMobile != null && _myMobile!.isNotEmpty && m.mobile.trim() == _myMobile!.trim())) {
        return m.status;
      }
    }
    return null;
  }

  Future<void> initialize({String? firebaseProjectId}) async {
    if (_initialized) return;
    _firebaseProjectId = firebaseProjectId ?? _fbProjectId;

    // 1. Load user's ownership profile
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final myFile = File('${docDir.path}/my_unions_profile.json');
      if (await myFile.exists()) {
        final data = jsonDecode(await myFile.readAsString()) as Map<String, dynamic>;
        _myCreatedUnionIds = Set<String>.from((data['unionIds'] as List? ?? []));
        _myEmail = data['email'] as String?;
        _myMobile = data['mobile'] as String?;
      }
    } catch (_) {}

    // 2. Load local storage cache
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheFile = File('${docDir.path}/travel_unions_cache.json');
      if (await cacheFile.exists()) {
        final jsonStr = await cacheFile.readAsString();
        final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
        _unions = list
            .map((item) => TravelUnionGroup.fromJson(item as Map<String, dynamic>))
            .where((u) => !const {'u_101', 'u_102'}.contains(u.id))
            .toList();

        // Migrate previously locally-created unions if profile was empty
        if (_myCreatedUnionIds.isEmpty && _unions.isNotEmpty) {
          for (final u in _unions) {
            _myCreatedUnionIds.add(u.id);
            _myEmail ??= u.hostEmail;
            _myMobile ??= u.hostMobile;
          }
          await _saveMyProfile();
        }
      }
    } catch (_) {}

    _initialized = true;
    notifyListeners();

    // Sync with Firebase Firestore to fetch live unions
    syncWithFirebase();
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
    int maxMembers = 10,
  }) async {
    final id = 'u_${DateTime.now().millisecondsSinceEpoch}';
    final joinCode = _generateJoinCode();

    final hostMember = UnionMember(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      name: hostName,
      mobile: hostMobile,
      email: hostEmail,
      vehicle: hostVehicle,
      category: category,
      status: UnionMemberStatus.accepted,
      joinedAt: DateTime.now(),
    );

    final newUnion = TravelUnionGroup(
      id: id,
      title: title,
      fromLocation: fromLocation,
      toLocation: toLocation,
      departureDateStr: departureDateStr,
      category: category,
      hostName: hostName,
      hostMobile: hostMobile,
      hostEmail: hostEmail,
      joinCode: joinCode,
      members: [hostMember],
      maxMembers: maxMembers,
      createdAt: DateTime.now(),
    );

    _unions.insert(0, newUnion);
    _myCreatedUnionIds.add(id);
    _myEmail = hostEmail.trim().toLowerCase();
    _myMobile = hostMobile.trim();

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
    int maxMembers = 10,
  }) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;

    final old = _unions[idx];
    final updatedMembers = old.members.map((m) {
      if (m.email == old.hostEmail || m.name == old.hostName) {
        return UnionMember(
          id: m.id,
          name: hostName,
          mobile: hostMobile,
          email: hostEmail,
          vehicle: hostVehicle,
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
      fromLocation: fromLocation,
      toLocation: toLocation,
      departureDateStr: departureDateStr,
      category: category,
      hostName: hostName,
      hostMobile: hostMobile,
      hostEmail: hostEmail,
      joinCode: old.joinCode,
      members: updatedMembers,
      maxMembers: maxMembers,
      createdAt: old.createdAt,
    );

    _unions[idx] = updated;
    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(updated);
    }
  }

  Future<void> deleteUnion(String unionId) async {
    _unions.removeWhere((u) => u.id == unionId);
    _myCreatedUnionIds.remove(unionId);
    await _saveLocalCache();
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
      (u) => u.joinCode.toUpperCase() == codeClean || u.id.toUpperCase() == codeClean,
    );

    if (idx == -1) return false;

    final targetUnion = _unions[idx];
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

    final updatedMembers = List<UnionMember>.from(targetUnion.members)..add(newMember);

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
    // Remember rider contact to identify join status
    _myEmail ??= riderEmail.trim().toLowerCase();
    _myMobile ??= riderMobile.trim();
    await _saveMyProfile();
    await _saveLocalCache();
    notifyListeners();

    if (_firebaseProjectId != null) {
      _postUnionToFirebase(updatedUnion);
    }

    return true;
  }

  Future<void> respondToJoinRequest({
    required String unionId,
    required String memberId,
    required bool accept,
  }) async {
    final idx = _unions.indexWhere((u) => u.id == unionId);
    if (idx == -1) return;

    final targetUnion = _unions[idx];
    final updatedMembers = targetUnion.members.map((m) {
      if (m.id == memberId) {
        return UnionMember(
          id: m.id,
          name: m.name,
          mobile: m.mobile,
          email: m.email,
          vehicle: m.vehicle,
          category: m.category,
          status: accept ? UnionMemberStatus.accepted : UnionMemberStatus.rejected,
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
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
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
      await myFile.writeAsString(jsonEncode({
        'unionIds': _myCreatedUnionIds.toList(),
        'email': _myEmail,
        'mobile': _myMobile,
      }));
    } catch (_) {}
  }

  /// Syncs Travel Unions over Firebase Firestore REST API
  Future<void> syncWithFirebase() async {
    final projectId = _firebaseProjectId ?? _fbProjectId;
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/unions?key=$_fbApiKey',
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(url);
      req.headers.add('Accept', 'application/json');
      final res = await req.close();

      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json.containsKey('documents') && json['documents'] is List) {
          final List<TravelUnionGroup> remoteUnions = [];
          for (final doc in (json['documents'] as List)) {
            try {
              final fields = doc['fields'] as Map<String, dynamic>;
              final rawJson = fields['unionData']['stringValue'] as String;
              remoteUnions.add(TravelUnionGroup.fromJson(jsonDecode(rawJson)));
            } catch (_) {}
          }
          if (remoteUnions.isNotEmpty) {
            final remoteIds = remoteUnions.map((u) => u.id).toSet();
            final localOnly = _unions.where((u) => !remoteIds.contains(u.id)).toList();
            _unions = [...remoteUnions, ...localOnly];
            await _saveLocalCache();
            notifyListeners();
          } else {
            _unions = [];
            await _saveLocalCache();
            notifyListeners();
          }
        } else {
          _unions = [];
          await _saveLocalCache();
          notifyListeners();
        }
      }
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
          'joinCode':  {'stringValue': union.joinCode},
          'title':     {'stringValue': union.title},
          'from':      {'stringValue': union.fromLocation},
          'to':        {'stringValue': union.toLocation},
        }
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
}
