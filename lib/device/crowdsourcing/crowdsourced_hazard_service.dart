import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../domain/crowdsourced_hazard_models.dart';
import '../dead_reckoning/dead_reckoning_engine.dart';

/// Service managing crowdsourced hazard reports, community confirmations, and route ratings.
/// Features dual persistent storage: local JSON cache + real Firebase Firestore cloud sync.
class CrowdsourcedHazardService {
  CrowdsourcedHazardService._();
  static final CrowdsourcedHazardService instance = CrowdsourcedHazardService._();

  // ── Firebase / Firestore config (diary-13644 project) ──
  static const String _fbProjectId = 'diary-13644';
  static const String _fbApiKey   = 'AIzaSyCFkg5ywh9TX0lGglxsVeR6K8JF-BFC7Zc';

  final List<CrowdsourcedHazardReport> _hazards = [];
  final List<RouteRatingFeedback> _ratings = [];
  final Set<String> _userVotedIds = {};
  bool _isInitialized = false;

  /// Initialize service strictly from persistent storage and trigger background cloud sync.
  Future<void> initialize({bool forceReset = false}) async {
    if (_isInitialized && !forceReset) return;

    if (forceReset) {
      await clearAllData();
      _isInitialized = true;
      return;
    }

    _hazards.clear();

    try {
      final file = await _getStorageFile('crowdsourced_hazards.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> list = jsonDecode(content);
          for (final item in list) {
            final report = CrowdsourcedHazardReport.fromJson(item as Map<String, dynamic>);
            _hazards.add(report);
          }
        }
      }

      final ratingsFile = await _getStorageFile('route_ratings.json');
      if (await ratingsFile.exists()) {
        final content = await ratingsFile.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> list = jsonDecode(content);
          _ratings.clear();
          for (final item in list) {
            _ratings.add(RouteRatingFeedback.fromJson(item as Map<String, dynamic>));
          }
        }
      }
    } catch (_) {
      // In tests or environments without native path_provider, starts with clean empty in-memory list
    }
    _isInitialized = true;

    // Trigger cloud sync in background (non-blocking)
    syncWithFirebase();
  }

  /// Get all active crowdsourced hazard reports (empty if none reported yet).
  List<CrowdsourcedHazardReport> getAllHazards() {
    return List.unmodifiable(_hazards);
  }

  /// Check whether user has already confirmed or rejected this report in the current session.
  bool hasUserVoted(String reportId) => _userVotedIds.contains(reportId);

  /// Find hazards within a given radius of a latitude/longitude point.
  List<CrowdsourcedHazardReport> getNearbyHazards({
    required double lat,
    required double lon,
    double radiusMeters = 3000,
  }) {
    final all = getAllHazards();
    return all.where((h) {
      final dist = GeodesyUtils.haversineDistanceMeters(lat, lon, h.latitude, h.longitude);
      return dist <= radiusMeters;
    }).toList();
  }

  /// Find hazards within buffer distance along a polyline.
  List<CrowdsourcedHazardReport> getHazardsAlongPolyline(
    List<({double lat, double lon})> polyline, {
    double bufferMeters = 100,
  }) {
    if (polyline.isEmpty) return [];
    final all = getAllHazards();
    final results = <CrowdsourcedHazardReport>[];

    for (final h in all) {
      var isNear = false;
      for (final pt in polyline) {
        final d = GeodesyUtils.haversineDistanceMeters(pt.lat, pt.lon, h.latitude, h.longitude);
        if (d <= bufferMeters) {
          isNear = true;
          break;
        }
      }
      if (isNear) {
        results.add(h);
      }
    }
    return results;
  }

  /// Submit a new user-reported hazard into the live database and broadcast to Firebase cloud.
  Future<CrowdsourcedHazardReport> submitHazardReport({
    required HazardType hazardType,
    required String description,
    required double latitude,
    required double longitude,
    required String roadName,
    String severity = 'HIGH',
  }) async {
    final report = CrowdsourcedHazardReport(
      id: 'cs_${DateTime.now().millisecondsSinceEpoch}',
      hazardType: hazardType,
      description: description,
      latitude: latitude,
      longitude: longitude,
      roadName: roadName,
      reportedAt: DateTime.now(),
      confirmationsCount: 1,
      rejectionsCount: 0,
      severity: severity,
      isUserReported: true,
    );

    _hazards.insert(0, report);
    _userVotedIds.add(report.id);
    await _saveHazards();

    // Broadcast to real Firebase Firestore backend
    _postHazardToFirebase(report);

    return report;
  }

  /// Confirm an existing hazard (upvote reliability).
  Future<CrowdsourcedHazardReport?> confirmHazard(String reportId) async {
    if (_userVotedIds.contains(reportId)) return null;

    final idx = _hazards.indexWhere((h) => h.id == reportId);
    if (idx < 0) return null;

    final existing = _hazards[idx];
    final updated = existing.copyWith(
      confirmationsCount: existing.confirmationsCount + 1,
    );
    _hazards[idx] = updated;
    _userVotedIds.add(reportId);
    await _saveHazards();

    _postHazardToFirebase(updated);

    return updated;
  }

  /// Reject an existing hazard (report resolved or not present).
  Future<CrowdsourcedHazardReport?> rejectHazard(String reportId) async {
    if (_userVotedIds.contains(reportId)) return null;

    final idx = _hazards.indexWhere((h) => h.id == reportId);
    if (idx < 0) return null;

    final existing = _hazards[idx];
    final updated = existing.copyWith(
      rejectionsCount: existing.rejectionsCount + 1,
    );
    _hazards[idx] = updated;
    _userVotedIds.add(reportId);
    await _saveHazards();

    _postHazardToFirebase(updated);

    return updated;
  }

  /// Delete/remove a hazard report completely from storage and cloud.
  Future<bool> deleteHazard(String reportId) async {
    final idx = _hazards.indexWhere((h) => h.id == reportId);
    if (idx < 0) return false;
    _hazards.removeAt(idx);
    _userVotedIds.remove(reportId);
    await _saveHazards();
    _deleteHazardFromFirebase(reportId);
    return true;
  }

  /// Syncs crowdsourced hazards with Firebase Firestore backend
  Future<void> syncWithFirebase() async {
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_fbProjectId/databases/(default)/documents/crowdsourced_hazards?key=$_fbApiKey',
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(url);
      req.headers.add('Accept', 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json.containsKey('documents') && json['documents'] is List) {
          final List<CrowdsourcedHazardReport> remoteHazards = [];
          for (final doc in (json['documents'] as List)) {
            try {
              final fields = doc['fields'] as Map<String, dynamic>;
              final rawJson = fields['hazardData']['stringValue'] as String;
              remoteHazards.add(CrowdsourcedHazardReport.fromJson(jsonDecode(rawJson)));
            } catch (_) {}
          }
          if (remoteHazards.isNotEmpty) {
            final remoteIds = remoteHazards.map((h) => h.id).toSet();
            final localOnly = _hazards.where((h) => !remoteIds.contains(h.id)).toList();

            _hazards.clear();
            _hazards.addAll([...remoteHazards, ...localOnly]);
            await _saveHazards();
          }
        }
      }
    } catch (_) {
      // Offline or network error, silently continue with local cache
    }
  }

  Future<void> _postHazardToFirebase(CrowdsourcedHazardReport hazard) async {
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_fbProjectId/databases/(default)/documents/crowdsourced_hazards/${hazard.id}?key=$_fbApiKey',
      );
      final client = HttpClient();
      final req = await client.patchUrl(url);
      req.headers.contentType = ContentType.json;
      req.headers.add('Accept', 'application/json');

      final body = jsonEncode({
        'fields': {
          'hazardData': {'stringValue': jsonEncode(hazard.toJson())},
          'updatedAt':  {'stringValue': DateTime.now().toIso8601String()},
          'hazardType': {'stringValue': hazard.hazardType.name},
          'roadName':   {'stringValue': hazard.roadName},
          'severity':   {'stringValue': hazard.severity},
          'latitude':   {'doubleValue': hazard.latitude},
          'longitude':  {'doubleValue': hazard.longitude},
        }
      });
      req.write(body);
      await req.close();
    } catch (_) {}
  }

  Future<void> _deleteHazardFromFirebase(String reportId) async {
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_fbProjectId/databases/(default)/documents/crowdsourced_hazards/$reportId?key=$_fbApiKey',
      );
      final client = HttpClient();
      final req = await client.deleteUrl(url);
      await req.close();
    } catch (_) {}
  }

  /// Record user rating feedback for a completed route.
  Future<void> submitRouteRating(RouteRatingFeedback feedback) async {
    _ratings.add(feedback);
    try {
      final file = await _getStorageFile('route_ratings.json');
      final list = _ratings.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (_) {}
  }

  List<RouteRatingFeedback> getAllRatings() => List.unmodifiable(_ratings);

  /// Completely purges all stored hazard reports and ratings for a 100% clean slate.
  Future<void> clearAllData() async {
    _hazards.clear();
    _ratings.clear();
    _userVotedIds.clear();
    try {
      final hFile = await _getStorageFile('crowdsourced_hazards.json');
      if (await hFile.exists()) await hFile.delete();

      final rFile = await _getStorageFile('route_ratings.json');
      if (await rFile.exists()) await rFile.delete();
    } catch (_) {}
  }

  Future<void> _saveHazards() async {
    try {
      final file = await _getStorageFile('crowdsourced_hazards.json');
      final list = _hazards.map((h) => h.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (_) {}
  }

  Future<File> _getStorageFile(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final parent = Directory('${dir.path}/crowdsourcing');
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    return File('${parent.path}/$fileName');
  }
}
