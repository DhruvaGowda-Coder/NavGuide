import 'dart:math' as math;
import '../../domain/route_safety_models.dart';
import 'accident_data_provider.dart';
import 'flood_data_provider.dart';
import 'road_condition_provider.dart';
import 'route_provider.dart';
import 'weather_provider.dart';

/// Master orchestration service for Phase 6 Real-World Safety Data Integration.
///
/// Fetches multi-candidate routes and enriches every discrete road segment with
/// normalized traffic, weather, flood, road condition, construction, and accident risk telemetry.
class RouteSafetyDataService {
  RouteSafetyDataService({
    RouteProvider? primaryRouteProvider,
    RouteProvider? fallbackRouteProvider,
    WeatherProvider? weatherProvider,
    FloodDataProvider? floodProvider,
    AccidentDataProvider? accidentProvider,
    RoadConditionProvider? roadConditionProvider,
    String? googleMapsApiKey,
  })  : _primaryRouteProvider = primaryRouteProvider ??
            GoogleRouteProvider(
              apiKey: googleMapsApiKey ??
                  const String.fromEnvironment('GOOGLE_MAPS_API_KEY'),
            ),
        _fallbackRouteProvider = fallbackRouteProvider ?? OsrmRouteProvider(),
        _weatherProvider = weatherProvider ?? WeatherProvider(),
        _floodProvider = floodProvider ?? FloodDataProvider(),
        _accidentProvider = accidentProvider ?? AccidentDataProvider(),
        _roadConditionProvider =
            roadConditionProvider ?? RoadConditionProvider();

  final RouteProvider _primaryRouteProvider;
  final RouteProvider _fallbackRouteProvider;
  final WeatherProvider _weatherProvider;
  final FloodDataProvider _floodProvider;
  final AccidentDataProvider _accidentProvider;
  final RoadConditionProvider _roadConditionProvider;

  // Simple in-memory cache to respect API rate limits and conserve battery
  final Map<String, ({DateTime timestamp, List<NormalizedRouteData> routes})>
      _routeCache = {};

  static const Duration cacheTtl = Duration(minutes: 5);

  /// Computes and enriches multi-candidate routes for origin and destination.
  Future<List<NormalizedRouteData>> fetchEnrichedRoutes({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required String originName,
    required String destName,
    bool forceRefresh = false,
  }) async {
    final cacheKey =
        '${originLat.toStringAsFixed(4)},${originLon.toStringAsFixed(4)}->'
        '${destLat.toStringAsFixed(4)},${destLon.toStringAsFixed(4)}';

    if (!forceRefresh && _routeCache.containsKey(cacheKey)) {
      final cached = _routeCache[cacheKey]!;
      if (DateTime.now().difference(cached.timestamp) < cacheTtl) {
        return cached.routes;
      }
    }

    // Step 1: Initialize local datasets (Flood spots and Accident blackspots)
    await Future.wait([
      _floodProvider.initialize(),
      _accidentProvider.initialize(),
    ]);

    // Step 2: Fetch raw routes from primary provider (Google) or fallback (OSRM)
    List<RawRouteCandidate> rawRoutes = [];
    try {
      rawRoutes = await _primaryRouteProvider.computeRoutes(
        originLat: originLat,
        originLon: originLon,
        destLat: destLat,
        destLon: destLon,
        originName: originName,
        destName: destName,
      );
    } catch (_) {
      // Fallback to OSRM if Google is restricted or quota exceeded
      rawRoutes = await _fallbackRouteProvider.computeRoutes(
        originLat: originLat,
        originLon: originLon,
        destLat: destLat,
        destLon: destLon,
        originName: originName,
        destName: destName,
      );
    }

    if (rawRoutes.isEmpty) {
      return [];
    }

    // Step 3: Fetch real-time weather telemetry at origin and destination
    final originWeather = await _weatherProvider.fetchWeather(
      latitude: originLat,
      longitude: originLon,
    );

    final destWeather = (originLat - destLat).abs() > 0.05 ||
            (originLon - destLon).abs() > 0.05
        ? await _weatherProvider.fetchWeather(
            latitude: destLat,
            longitude: destLon,
          )
        : originWeather;

    // Step 4: Enrich every candidate route and its discrete road segments
    final enrichedRoutes = <NormalizedRouteData>[];

    for (final raw in rawRoutes) {
      final segments = <RoadSegmentData>[];
      final totalSteps = raw.steps.length;

      for (var sIdx = 0; sIdx < totalSteps; sIdx++) {
        final step = raw.steps[sIdx];
        final fraction = totalSteps > 1 ? sIdx / (totalSteps - 1) : 0.0;

        // Interpolate or assign weather
        final segWeather = fraction < 0.5 ? originWeather : destWeather;

        // Evaluate flood risk
        final floodInfo = await _floodProvider.evaluateLocation(
          latitude: step.startLat,
          longitude: step.startLon,
          activeRainfallMm: segWeather.rainfallMmPerHour,
        );

        // Evaluate accident blackspot risk
        final accidentInfo = await _accidentProvider.evaluateLocation(
          latitude: step.startLat,
          longitude: step.startLon,
        );

        // Evaluate road condition
        final roadCond = await _roadConditionProvider.evaluateLocation(
          latitude: step.startLat,
          longitude: step.startLon,
        );

        // Evaluate construction / advisories
        ConstructionInfo constrInfo = const ConstructionInfo(
          status: ConstructionStatus.noneReported,
          details: null,
          source: 'Routing Provider Advisories',
        );
        if (raw.travelAdvisories.isNotEmpty) {
          final matchedAdv = raw.travelAdvisories.firstWhere(
            (adv) =>
                adv.toLowerCase().contains(step.roadName.toLowerCase()) ||
                adv.toLowerCase().contains('closure') ||
                adv.toLowerCase().contains('work'),
            orElse: () => '',
          );
          if (matchedAdv.isNotEmpty) {
            constrInfo = ConstructionInfo(
              status: matchedAdv.toLowerCase().contains('closure')
                  ? ConstructionStatus.closure
                  : ConstructionStatus.workZone,
              details: matchedAdv,
              source: raw.providerName,
            );
          }
        }

        // Calculate segment traffic info
        final segStaticSec = step.durationSeconds;
        // If route has traffic ratio, scale segment duration proportionately
        final routeDelayRatio = raw.staticDurationSeconds > 0
            ? raw.trafficDurationSeconds / raw.staticDurationSeconds
            : 1.0;
        final segTrafficSec = segStaticSec * routeDelayRatio;

        final trafficInfo = TrafficInfo.calculate(
          staticSec: segStaticSec,
          trafficSec: segTrafficSec,
          source: raw.providerName,
          isLive: raw.providerName.contains('Live Traffic'),
        );

        final unknownFields = <String>[];
        if (trafficInfo.congestionLevel == CongestionLevel.unknown) {
          unknownFields.add('Traffic Congestion');
        }
        if (segWeather.weatherDescription == 'Unknown') {
          unknownFields.add('Weather');
        }
        if (roadCond.condition == RoadCondition.unknown) {
          unknownFields.add('Road Surface Condition');
        }

        segments.add(
          RoadSegmentData(
            segmentId: '${raw.routeId}_seg_$sIdx',
            roadName: step.roadName,
            startLat: step.startLat,
            startLon: step.startLon,
            endLat: step.endLat,
            endLon: step.endLon,
            polyline: step.polyline,
            distanceMeters: step.distanceMeters,
            durationSeconds: step.durationSeconds,
            traffic: trafficInfo,
            weather: segWeather,
            flood: floodInfo,
            roadCondition: roadCond,
            construction: constrInfo,
            accident: accidentInfo,
            isMockData: false,
            unknownFields: unknownFields,
          ),
        );
      }

      enrichedRoutes.add(
        NormalizedRouteData(
          routeId: raw.routeId,
          summary: raw.summary,
          providerName: raw.providerName,
          originName: originName,
          destinationName: destName,
          originLat: originLat,
          originLon: originLon,
          destinationLat: destLat,
          destinationLon: destLon,
          distanceMeters: raw.distanceMeters,
          staticDurationSeconds: raw.staticDurationSeconds,
          trafficDurationSeconds: raw.trafficDurationSeconds,
          fullPolyline: raw.fullPolyline,
          segments: segments,
          sampleWeather: originWeather,
          isMockData: false,
        ),
      );
    }

    _routeCache[cacheKey] = (
      timestamp: DateTime.now(),
      routes: enrichedRoutes,
    );

    return enrichedRoutes;
  }

  void clearCache() {
    _routeCache.clear();
  }
}
