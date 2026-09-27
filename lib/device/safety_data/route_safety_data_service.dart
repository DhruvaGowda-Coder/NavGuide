import '../../domain/route_safety_models.dart';
import 'accident_data_provider.dart';
import 'flood_data_provider.dart';
import 'road_condition_provider.dart';
import 'route_provider.dart';
import 'weather_provider.dart';
import '../crowdsourcing/crowdsourced_hazard_service.dart';

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
                  const String.fromEnvironment(
                    'GOOGLE_MAPS_API_KEY',
                    defaultValue: 'AIzaSyCFkg5ywh9TX0lGglxsVeR6K8JF-BFC7Zc',
                  ),
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

  Future<List<RawRouteCandidate>> _fetchRawRoutes({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required String originName,
    required String destName,
  }) async {
    try {
      final routes = await _primaryRouteProvider.computeRoutes(
        originLat: originLat,
        originLon: originLon,
        destLat: destLat,
        destLon: destLon,
        originName: originName,
        destName: destName,
      );
      if (routes.isNotEmpty) return routes;
    } catch (_) {}

    try {
      final routes = await _fallbackRouteProvider.computeRoutes(
        originLat: originLat,
        originLon: originLon,
        destLat: destLat,
        destLon: destLon,
        originName: originName,
        destName: destName,
      );
      if (routes.isNotEmpty) return routes;
    } catch (_) {}

    // Resilient on-device fallback: Ensures users never get an empty route error or blank screen
    try {
      return await OfflineFallbackRouteProvider().computeRoutes(
        originLat: originLat,
        originLon: originLon,
        destLat: destLat,
        destLon: destLon,
        originName: originName,
        destName: destName,
      );
    } catch (_) {
      return [];
    }
  }

  Future<({WeatherInfo origin, WeatherInfo dest})> _fetchWeatherPair({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
  }) async {
    final originFuture = _weatherProvider.fetchWeather(
      latitude: originLat,
      longitude: originLon,
    );

    final bool isDistant = (originLat - destLat).abs() > 0.05 ||
        (originLon - destLon).abs() > 0.05;

    final destFuture = isDistant
        ? _weatherProvider.fetchWeather(
            latitude: destLat,
            longitude: destLon,
          )
        : originFuture;

    final results = await Future.wait([originFuture, destFuture]);
    return (origin: results[0], dest: results[1]);
  }

  Future<({double? origin, double? dest})> _fetchCorridorElevation({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
  }) async {
    final oElevFuture = _floodProvider.fetchElevation(originLat, originLon);
    final dElevFuture = _floodProvider.fetchElevation(destLat, destLon);
    final res = await Future.wait([oElevFuture, dElevFuture]);
    return (origin: res[0], dest: res[1]);
  }

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

    // Step 1: Execute route calculation, weather telemetry, corridor elevations,
    // and local datasets initialization strictly IN PARALLEL.
    final initFuture = Future.wait([
      _floodProvider.initialize(),
      _accidentProvider.initialize(),
      _roadConditionProvider.initialize(),
    ]);

    final rawRoutesFuture = _fetchRawRoutes(
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
      originName: originName,
      destName: destName,
    );

    final weatherFuture = _fetchWeatherPair(
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
    ).timeout(
      const Duration(milliseconds: 1800),
      onTimeout: () => (
        origin: WeatherInfo.unknown,
        dest: WeatherInfo.unknown,
      ),
    );

    final elevFuture = _fetchCorridorElevation(
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
    ).timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () => (origin: null, dest: null),
    );

    final results = await Future.wait([
      rawRoutesFuture,
      weatherFuture,
      elevFuture,
      initFuture,
    ]);

    final rawRoutes = results[0] as List<RawRouteCandidate>;
    final weatherPair = results[1] as ({WeatherInfo origin, WeatherInfo dest});
    final corridorElev = results[2] as ({double? origin, double? dest});

    if (rawRoutes.isEmpty) {
      return [];
    }

    final originWeather = weatherPair.origin;
    final destWeather = weatherPair.dest;

    // Step 2: Enrich every candidate route and its discrete road segments (100% in-memory)
    final enrichedRoutes = <NormalizedRouteData>[];

    for (final raw in rawRoutes) {
      final segments = <RoadSegmentData>[];
      final totalSteps = raw.steps.length;

      for (var sIdx = 0; sIdx < totalSteps; sIdx++) {
        final step = raw.steps[sIdx];
        final fraction = totalSteps > 1 ? sIdx / (totalSteps - 1) : 0.0;

        // Interpolate or assign weather
        final segWeather = fraction < 0.5 ? originWeather : destWeather;
        final segElevation = fraction < 0.5 ? corridorElev.origin : corridorElev.dest;

        // Evaluate flood risk (in-memory lookup with cached elevation)
        final floodInfo = await _floodProvider.evaluateLocation(
          latitude: step.startLat,
          longitude: step.startLon,
          activeRainfallMm: segWeather.rainfallMmPerHour,
          elevation: segElevation,
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

        final crowdsourcedHazards = CrowdsourcedHazardService.instance
            .getHazardsAlongPolyline(step.polyline);

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
            crowdsourcedHazards: crowdsourcedHazards,
            isMockData: false,
            unknownFields: unknownFields,
          ),
        );
      }

      final allRouteHazards = CrowdsourcedHazardService.instance
          .getHazardsAlongPolyline(raw.fullPolyline);

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
          crowdsourcedHazards: allRouteHazards,
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
