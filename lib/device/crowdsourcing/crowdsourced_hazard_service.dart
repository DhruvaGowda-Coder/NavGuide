import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../domain/crowdsourced_hazard_models.dart';
import '../dead_reckoning/dead_reckoning_engine.dart';

/// Service managing crowdsourced hazard reports, community confirmations, and route ratings.
/// Runs completely on real user-reported data with zero synthetic or mock data seeds.
class CrowdsourcedHazardService {
  CrowdsourcedHazardService._();
  static final CrowdsourcedHazardService instance = CrowdsourcedHazardService._();

  final List<CrowdsourcedHazardReport> _hazards = [];
  final List<RouteRatingFeedback> _ratings = [];
  final Set<String> _userVotedIds = {};
  bool _isInitialized = false;

  /// Initialize service strictly from persistent storage.
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

  /// Submit a new user-reported hazard into the live database.
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
    return updated;
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
