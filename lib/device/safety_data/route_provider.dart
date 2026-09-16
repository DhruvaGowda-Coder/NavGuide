import 'dart:convert';
import 'dart:io';

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

    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 8));
    request.headers.set('X-Android-Package', 'com.navguardian.navguardian_ai');

    final response = await request.close().timeout(const Duration(seconds: 8));
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

    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 8));
    final response = await request.close().timeout(const Duration(seconds: 8));

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
      final r = routesList[i] as Map<String, dynamic>;
      final distMeters = (r['distance'] as num?)?.toDouble() ?? 0.0;
      final staticSec = (r['duration'] as num?)?.toDouble() ?? 0.0;

      // Extract GeoJSON full geometry
      final geom = r['geometry'] as Map<String, dynamic>? ?? {};
      final coordsList = geom['coordinates'] as List<dynamic>? ?? [];
      final fullPoly = coordsList.map((c) {
        final pair = c as List<dynamic>;
        return (lat: (pair[1] as num).toDouble(), lon: (pair[0] as num).toDouble());
      }).toList();

      final legs = r['legs'] as List<dynamic>? ?? [];
      final steps = <RawRouteStep>[];
      var primaryRoad = 'Major Urban Corridor';

      if (legs.isNotEmpty) {
        final leg = legs.first as Map<String, dynamic>;
        final rawSteps = leg['steps'] as List<dynamic>? ?? [];
        for (final s in rawSteps) {
          final sm = s as Map<String, dynamic>;
          final name = sm['name'] as String? ?? '';
          if (name.isNotEmpty && primaryRoad == 'Major Urban Corridor') {
            primaryRoad = name;
          }
          final sDist = (sm['distance'] as num?)?.toDouble() ?? 0.0;
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

      results.add(
        RawRouteCandidate(
          routeId: 'osrm_route_${i + 1}',
          summary: primaryRoad,
          providerName: 'OpenStreetMap OSRM Engine',
          distanceMeters: distMeters,
          staticDurationSeconds: staticSec,
          trafficDurationSeconds: staticSec, // Free flow without live Google congestion
          fullPolyline: fullPoly,
          steps: steps,
          travelAdvisories: const [],
        ),
      );
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
