import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import '../dead_reckoning/dead_reckoning_engine.dart';

/// Intermediate raw candidate route before safety data normalization.
class RawRouteCandidate {
  const RawRouteCandidate({
    required this.routeId,
    required this.summary,
    required this.providerName,
    required this.distanceMeters,
    required this.staticDurationSeconds,
    required this.trafficDurationSeconds,
    required this.fullPolyline,
    required this.steps,
    this.travelAdvisories = const [],
  });

  final String routeId;
  final String summary;
  final String providerName;
  final double distanceMeters;
  final double staticDurationSeconds;
  final double trafficDurationSeconds;
  final List<({double lat, double lon})> fullPolyline;
  final List<RawRouteStep> steps;
  final List<String> travelAdvisories;
}

class RawRouteStep {
  const RawRouteStep({
    required this.instruction,
    required this.roadName,
    required this.startLat,
    required this.startLon,
    required this.endLat,
    required this.endLon,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polyline,
  });

  final String instruction;
  final String roadName;
  final double startLat;
  final double startLon;
  final double endLat;
  final double endLon;
  final double distanceMeters;
  final double durationSeconds;
  final List<({double lat, double lon})> polyline;
}

/// Abstract interface for route calculation providers.
abstract class RouteProvider {
  Future<List<RawRouteCandidate>> computeRoutes({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required String originName,
    required String destName,
  });
}

/// Google Directions / Routes API implementation with traffic awareness.
class GoogleRouteProvider implements RouteProvider {
  GoogleRouteProvider({
    required this.apiKey,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String apiKey;
  final HttpClient _client;

  @override
  Future<List<RawRouteCandidate>> computeRoutes({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required String originName,
    required String destName,
  }) async {
    if (apiKey.isEmpty) {
      throw const SocketException('Google Maps API Key not provided.');
    }

    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$originLat,$originLon'
      '&destination=$destLat,$destLon'
      '&departure_time=now'
      '&traffic_model=best_guess'
      '&alternatives=true'
      '&key=$apiKey',
    );

    final request = await _client.getUrl(uri).timeout(const Duration(milliseconds: 4500));
    request.headers.set('X-Android-Package', 'com.navguardian.navguardian_ai');

    final response = await request.close().timeout(const Duration(milliseconds: 4500));
    if (response.statusCode != 200) {
      throw HttpException('Google Routes HTTP ${response.statusCode}');
    }

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final status = json['status'] as String?;
    if (status != 'OK') {
      final errorMsg = json['error_message'] as String? ?? status ?? 'Unknown Error';
      throw HttpException('Google Routes API Error: $errorMsg');
    }

    final routesList = json['routes'] as List<dynamic>? ?? [];
    final results = <RawRouteCandidate>[];

    for (var i = 0; i < routesList.length; i++) {
      final r = routesList[i] as Map<String, dynamic>;
      final summary = r['summary'] as String? ?? 'Route ${i + 1}';
      final legs = r['legs'] as List<dynamic>? ?? [];
      if (legs.isEmpty) continue;

      final leg = legs.first as Map<String, dynamic>;
      final distMeters = ((leg['distance'] as Map<String, dynamic>?)?['value'] as num?)?.toDouble() ?? 0.0;
      final staticSec = ((leg['duration'] as Map<String, dynamic>?)?['value'] as num?)?.toDouble() ?? 0.0;
      final trafficSec = ((leg['duration_in_traffic'] as Map<String, dynamic>?)?['value'] as num?)?.toDouble() ?? staticSec;

      final overviewPoly = (r['overview_polyline'] as Map<String, dynamic>?)?['points'] as String? ?? '';
      final decodedOverview = PolylineUtils.decodePolyline(overviewPoly);

      final stepsRaw = leg['steps'] as List<dynamic>? ?? [];
      final steps = <RawRouteStep>[];

      for (final s in stepsRaw) {
        final sm = s as Map<String, dynamic>;
        final startLoc = sm['start_location'] as Map<String, dynamic>? ?? {};
        final endLoc = sm['end_location'] as Map<String, dynamic>? ?? {};
        final sDist = ((sm['distance'] as Map<String, dynamic>?)?['value'] as num?)?.toDouble() ?? 0.0;
        final sDur = ((sm['duration'] as Map<String, dynamic>?)?['value'] as num?)?.toDouble() ?? 0.0;
        final instr = (sm['html_instructions'] as String? ?? '').replaceAll(RegExp(r'<[^>]*>'), '');
        final sPoly = (sm['polyline'] as Map<String, dynamic>?)?['points'] as String? ?? '';

        steps.add(
          RawRouteStep(
            instruction: instr,
            roadName: instr.split(' on ').length > 1 ? instr.split(' on ').last : instr,
            startLat: (startLoc['lat'] as num?)?.toDouble() ?? 0.0,
            startLon: (startLoc['lng'] as num?)?.toDouble() ?? 0.0,
            endLat: (endLoc['lat'] as num?)?.toDouble() ?? 0.0,
            endLon: (endLoc['lng'] as num?)?.toDouble() ?? 0.0,
            distanceMeters: sDist,
            durationSeconds: sDur,
            polyline: PolylineUtils.decodePolyline(sPoly),
          ),
        );
      }

      final warnings = (r['warnings'] as List<dynamic>?)?.map((w) => w.toString()).toList() ?? [];

      results.add(
        RawRouteCandidate(
          routeId: 'google_route_${i + 1}',
          summary: summary,
          providerName: 'Google Routes (Live Traffic)',
          distanceMeters: distMeters,
          staticDurationSeconds: staticSec,
          trafficDurationSeconds: trafficSec,
          fullPolyline: decodedOverview,
          steps: steps,
          travelAdvisories: warnings,
        ),
      );
    }

    return results;
  }
}

/// OpenStreetMap OSRM routing engine providing resilient candidate routes without API keys.
class OsrmRouteProvider implements RouteProvider {
  OsrmRouteProvider({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  RawRouteCandidate _parseOsrmRoute(
    Map<String, dynamic> r,
    int index,
    double originLat,
    double originLon,
    double destLat,
    double destLon,
  ) {
    final distMeters = (r['distance'] as num?)?.toDouble() ?? 0.0;
    final staticSec = (r['duration'] as num?)?.toDouble() ?? 0.0;

    final geom = r['geometry'] as Map<String, dynamic>? ?? {};
    final coordsList = geom['coordinates'] as List<dynamic>? ?? [];
    final fullPoly = coordsList.map((c) {
      final pair = c as List<dynamic>;
      return (lat: (pair[1] as num).toDouble(), lon: (pair[0] as num).toDouble());
    }).toList();

    final legs = r['legs'] as List<dynamic>? ?? [];
    final steps = <RawRouteStep>[];
    var primaryRoad = 'Major Urban Corridor';
    var longestRoad = '';
    var maxDist = 0.0;

    if (legs.isNotEmpty) {
      for (final leg in legs) {
        final lm = leg as Map<String, dynamic>;
        final rawSteps = lm['steps'] as List<dynamic>? ?? [];
        for (final s in rawSteps) {
          final sm = s as Map<String, dynamic>;
          final name = sm['name'] as String? ?? '';
          final sDist = (sm['distance'] as num?)?.toDouble() ?? 0.0;
          if (name.isNotEmpty) {
            if (primaryRoad == 'Major Urban Corridor') {
              primaryRoad = name;
            }
            if (sDist > maxDist) {
              maxDist = sDist;
              longestRoad = name;
            }
          }
          final sDur = (sm['duration'] as num?)?.toDouble() ?? 0.0;
          final sGeom = sm['geometry'] as Map<String, dynamic>? ?? {};
          final sCoords = (sGeom['coordinates'] as List<dynamic>? ?? []).map((c) {
            final pair = c as List<dynamic>;
            return (lat: (pair[1] as num).toDouble(), lon: (pair[0] as num).toDouble());
          }).toList();

          final start = sCoords.isNotEmpty ? sCoords.first : (lat: originLat, lon: originLon);
          final end = sCoords.isNotEmpty ? sCoords.last : (lat: destLat, lon: destLon);

          final maneuver = sm['maneuver'] as Map<String, dynamic>? ?? {};
          final type = maneuver['type'] as String? ?? 'proceed';
          final modifier = maneuver['modifier'] as String? ?? '';
          final instruction = name.isNotEmpty ? '$type $modifier onto $name' : '$type $modifier';

          steps.add(
            RawRouteStep(
              instruction: instruction,
              roadName: name.isNotEmpty ? name : 'Connecting Segment',
              startLat: start.lat,
              startLon: start.lon,
              endLat: end.lat,
              endLon: end.lon,
              distanceMeters: sDist,
              durationSeconds: sDur,
              polyline: sCoords,
            ),
          );
        }
      }
    }

    final summary = longestRoad.isNotEmpty ? longestRoad : primaryRoad;

    return RawRouteCandidate(
      routeId: 'osrm_route_$index',
      summary: summary,
      providerName: 'OpenStreetMap OSRM Engine',
      distanceMeters: distMeters,
      staticDurationSeconds: staticSec,
      trafficDurationSeconds: staticSec,
      fullPolyline: fullPoly,
      steps: steps,
      travelAdvisories: const [],
    );
  }

  @override
  Future<List<RawRouteCandidate>> computeRoutes({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required String originName,
    required String destName,
  }) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '$originLon,$originLat;$destLon,$destLat'
      '?overview=full&geometries=geojson&steps=true&alternatives=true',
    );

    final request = await _client.getUrl(uri).timeout(const Duration(milliseconds: 3500));
    final response = await request.close().timeout(const Duration(milliseconds: 3500));

    if (response.statusCode != 200) {
      throw HttpException('OSRM Route Engine HTTP ${response.statusCode}');
    }

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final code = json['code'] as String?;
    if (code != 'Ok') {
      throw HttpException('OSRM Route Engine Error: $code');
    }

    final routesList = json['routes'] as List<dynamic>? ?? [];
    final results = <RawRouteCandidate>[];

    for (var i = 0; i < routesList.length; i++) {
      results.add(
        _parseOsrmRoute(
          routesList[i] as Map<String, dynamic>,
          i + 1,
          originLat,
          originLon,
          destLat,
          destLon,
        ),
      );
    }

    // If OSRM returned fewer than 3 routes, calculate alternative corridors via offset midpoints
    if (results.length < 3) {
      final mLat = (originLat + destLat) / 2.0;
      final mLon = (originLon + destLon) / 2.0;
      final dx = destLon - originLon;
      final dy = destLat - originLat;
      final dist = math.sqrt(dx * dx + dy * dy);

      if (dist > 0.0005) {
        final offset = math.max(0.003, math.min(0.05, dist * 0.22));
        final waypoints = [
          (lat: mLat - (dy / dist) * offset, lon: mLon + (dx / dist) * offset),
          (lat: mLat + (dy / dist) * offset, lon: mLon - (dx / dist) * offset),
        ];

        final waypointsToQuery = waypoints.take(3 - results.length).toList();
        final altFutures = waypointsToQuery.map((wp) async {
          try {
            final altUri = Uri.parse(
              'https://router.project-osrm.org/route/v1/driving/'
              '$originLon,$originLat;${wp.lon},${wp.lat};$destLon,$destLat'
              '?overview=full&geometries=geojson&steps=true',
            );
            final altReq = await _client.getUrl(altUri).timeout(const Duration(milliseconds: 1800));
            final altResp = await altReq.close().timeout(const Duration(milliseconds: 1800));
            if (altResp.statusCode == 200) {
              final altBody = await altResp.transform(utf8.decoder).join();
              final altJson = jsonDecode(altBody) as Map<String, dynamic>;
              final altRoutes = altJson['routes'] as List<dynamic>? ?? [];
              if (altRoutes.isNotEmpty) {
                return _parseOsrmRoute(
                  altRoutes.first as Map<String, dynamic>,
                  0,
                  originLat,
                  originLon,
                  destLat,
                  destLon,
                );
              }
            }
          } catch (_) {}
          return null;
        });

        final altCandidates = await Future.wait(altFutures);
        for (final cand in altCandidates) {
          if (cand != null && results.length < 3) {
            final isDuplicate = results.any((existing) =>
                (existing.distanceMeters - cand.distanceMeters).abs() < 50 &&
                (existing.staticDurationSeconds - cand.staticDurationSeconds).abs() < 15);
            if (!isDuplicate) {
              results.add(
                RawRouteCandidate(
                  routeId: 'osrm_route_${results.length + 1}',
                  summary: cand.summary,
                  providerName: cand.providerName,
                  distanceMeters: cand.distanceMeters,
                  staticDurationSeconds: cand.staticDurationSeconds,
                  trafficDurationSeconds: cand.trafficDurationSeconds,
                  fullPolyline: cand.fullPolyline,
                  steps: cand.steps,
                  travelAdvisories: cand.travelAdvisories,
                ),
              );
            }
          }
        }
      }
    }

    return results;
  }
}


/// Utility to decode Google encoded polylines into Lat/Lon coordinates.
class PolylineUtils {
  static List<({double lat, double lon})> decodePolyline(String encoded) {
    final points = <({double lat, double lon})>[];
    if (encoded.isEmpty) return points;

    var index = 0;
    final len = encoded.length;
    var lat = 0;
    var lng = 0;

    while (index < len) {
      var b = 0;
      var shift = 0;
      var result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add((lat: lat / 1e5, lon: lng / 1e5));
    }
    return points;
  }
}

/// Resilient on-device routing fallback when network connections to Google & OSRM are unreachable.
class OfflineFallbackRouteProvider implements RouteProvider {
  @override
  Future<List<RawRouteCandidate>> computeRoutes({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required String originName,
    required String destName,
  }) async {
    final rawDistMeters = GeodesyUtils.haversineDistanceMeters(originLat, originLon, destLat, destLon);
    final distMeters = rawDistMeters * 1.25; // 1.25x for typical urban & highway road curvature
    final durationSec = (distMeters / 1000.0 / 42.0) * 3600.0; // average 42 km/h city/highway speed

    // Generate smooth, multi-point road spline along the corridor
    final points = <({double lat, double lon})>[];
    const segments = 16;
    for (int i = 0; i <= segments; i++) {
      final f = i / segments.toDouble();
      final arcOffset = math.sin(f * math.pi) * 0.002;
      points.add((
        lat: originLat + (destLat - originLat) * f + arcOffset,
        lon: originLon + (destLon - originLon) * f - arcOffset,
      ));
    }

    final step = RawRouteStep(
      instruction: 'Head towards $destName along direct connecting corridor',
      roadName: 'Main Connecting Road',
      startLat: originLat,
      startLon: originLon,
      endLat: destLat,
      endLon: destLon,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      polyline: points,
    );

    return [
      RawRouteCandidate(
        routeId: 'fallback_offline_corridor',
        summary: 'Direct Road Corridor to $destName',
        providerName: 'NavGuide Direct Route (Offline Resilient)',
        distanceMeters: distMeters,
        staticDurationSeconds: durationSec,
        trafficDurationSeconds: durationSec,
        fullPolyline: points,
        steps: [step],
        travelAdvisories: const ['Offline Direct Corridor · Reconnecting to Live Traffic'],
      ),
    ];
  }
}
