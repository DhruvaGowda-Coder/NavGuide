import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../domain/route_safety_models.dart';
import '../../device/safety_data/route_safety_data_service.dart';

class RoutePreset {
  const RoutePreset({
    required this.title,
    required this.subtitle,
    required this.originName,
    required this.originLat,
    required this.originLon,
    required this.destName,
    required this.destLat,
    required this.destLon,
  });

  final String title;
  final String subtitle;
  final String originName;
  final double originLat;
  final double originLon;
  final String destName;
  final double destLat;
  final double destLon;
}

const List<RoutePreset> kBangaloreRoutePresets = [
  RoutePreset(
    title: 'Silk Board → Electronic City',
    subtitle: 'Hosur Road Corridor (Flood spot + MoRTH Blackspots)',
    originName: 'Central Silk Board',
    originLat: 12.9176,
    originLon: 77.6238,
    destName: 'Electronic City Phase 1',
    destLat: 12.8452,
    destLon: 77.6602,
  ),
  RoutePreset(
    title: 'Koramangala → Whitefield',
    subtitle: 'Outer Ring Road (Sony World + Bellandur + Varthur)',
    originName: 'Sony World Koramangala',
    originLat: 12.9345,
    originLon: 77.6285,
    destName: 'ITPL Whitefield',
    destLat: 12.9850,
    destLon: 77.7310,
  ),
  RoutePreset(
    title: 'Majestic → Hebbal Flyover',
    subtitle: 'Underpass Corridor (Okalipuram & Windsor Manor)',
    originName: 'Majestic City Railway Station',
    originLat: 12.9780,
    originLon: 77.5695,
    destName: 'Hebbal Flyover',
    destLat: 13.0358,
    destLon: 77.5970,
  ),
];

class RouteSafetyInspectionScreen extends StatefulWidget {
  const RouteSafetyInspectionScreen({
    super.key,
    this.initialPresetIndex = 0,
  });

  final int initialPresetIndex;

  @override
  State<RouteSafetyInspectionScreen> createState() =>
      _RouteSafetyInspectionScreenState();
}

class _RouteSafetyInspectionScreenState
    extends State<RouteSafetyInspectionScreen> {
  final RouteSafetyDataService _dataService = RouteSafetyDataService();

  late RoutePreset _selectedPreset;
  bool _isLoading = false;
  String? _errorMessage;
  List<NormalizedRouteData> _routes = [];
  int _selectedRouteIndex = 0;

  GoogleMapController? _mapController;
  int? _inspectedSegmentIndex;
  bool _isMapFullscreen = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedPreset = kBangaloreRoutePresets[widget.initialPresetIndex];
    _fetchRoutes();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchRoutes({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _inspectedSegmentIndex = null;
    });

    try {
      final routes = await _dataService.fetchEnrichedRoutes(
        originLat: _selectedPreset.originLat,
        originLon: _selectedPreset.originLon,
        destLat: _selectedPreset.destLat,
        destLon: _selectedPreset.destLon,
        originName: _selectedPreset.originName,
        destName: _selectedPreset.destName,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _routes = routes;
        _selectedRouteIndex = 0;
        _inspectedSegmentIndex = null;
        _isLoading = false;
      });

      _fitMapToRoute();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _fitMapToRoute() {
    if (_routes.isEmpty || _mapController == null) return;
    final r = _routes[_selectedRouteIndex];
    if (r.fullPolyline.isEmpty) return;

    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final p in r.fullPolyline) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        48.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isMapFullscreen &&
        _routes.isNotEmpty &&
        _selectedRouteIndex < _routes.length) {
      return _buildFullscreenMapView();
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Safety Inspection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Route Data',
            onPressed: () => _fetchRoutes(forceRefresh: true),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildPresetSelector(),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Querying Route, Traffic & Open-Meteo Weather...'),
                    ],
                  ),
                ),
              )
            else if (_errorMessage != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _fetchRoutes(forceRefresh: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_routes.isEmpty)
              const Expanded(
                child: Center(child: Text('No routes found for this corridor.')),
              )
            else
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
                  children: [
                    _buildRouteTabs(),
                    const SizedBox(height: 12),
                    _buildMiniMap(),
                    if (_inspectedSegmentIndex != null &&
                        _inspectedSegmentIndex! <
                            _routes[_selectedRouteIndex].segments.length) ...[
                      const SizedBox(height: 8),
                      _buildActiveSegmentBanner(
                        _routes[_selectedRouteIndex]
                            .segments[_inspectedSegmentIndex!],
                        _inspectedSegmentIndex!,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildOverviewCard(),
                    const SizedBox(height: 12),
                    _buildTrafficCard(),
                    const SizedBox(height: 12),
                    _buildWeatherCard(),
                    const SizedBox(height: 12),
                    _buildFloodCard(),
                    const SizedBox(height: 12),
                    _buildAccidentCard(),
                    const SizedBox(height: 12),
                    _buildRoadConditionCard(),
                    const SizedBox(height: 12),
                    _buildSegmentInspectionTile(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSegmentBanner(RoadSegmentData seg, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.shade300, width: 1.2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.teal.shade700,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'FOCUSED SEGMENT ${index + 1}: ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        seg.roadName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${seg.distanceMeters.toInt()}m · Traffic: ${seg.traffic.congestionLevel.displayName} · Amber highlighted on map',
                  style: TextStyle(fontSize: 10, color: Colors.teal.shade900),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              setState(() {
                _inspectedSegmentIndex = null;
              });
              _fitMapToRoute();
            },
            child: const Text('Reset', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade100,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RoutePreset>(
          value: _selectedPreset,
          isExpanded: true,
          icon: const Icon(Icons.alt_route),
          items: kBangaloreRoutePresets.map((preset) {
            return DropdownMenuItem<RoutePreset>(
              value: preset,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    preset.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    preset.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (newPreset) {
            if (newPreset != null && newPreset != _selectedPreset) {
              setState(() {
                _selectedPreset = newPreset;
              });
              _fetchRoutes();
            }
          },
        ),
      ),
    );
  }

  Widget _buildRouteTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _routes.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  'Route ${i + 1}: ${_routes[i].summary}',
                  style: const TextStyle(fontSize: 12),
                ),
                selected: _selectedRouteIndex == i,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedRouteIndex = i;
                      _inspectedSegmentIndex = null;
                    });
                    _fitMapToRoute();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniMap() {
    final route = _routes[_selectedRouteIndex];
    final polylineCoords =
        route.fullPolyline.map((p) => LatLng(p.lat, p.lon)).toList();

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('origin'),
        position:
            LatLng(_selectedPreset.originLat, _selectedPreset.originLon),
        infoWindow: InfoWindow(title: _selectedPreset.originName),
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position:
            LatLng(_selectedPreset.destLat, _selectedPreset.destLon),
        infoWindow: InfoWindow(title: _selectedPreset.destName),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('selected_route'),
        points: polylineCoords,
        color: const Color(0xff1976d2),
        width: 5,
      ),
    };

    if (_inspectedSegmentIndex != null &&
        _inspectedSegmentIndex! >= 0 &&
        _inspectedSegmentIndex! < route.segments.length) {
      final seg = route.segments[_inspectedSegmentIndex!];
      final segCoords =
          seg.polyline.map((p) => LatLng(p.lat, p.lon)).toList();
      if (segCoords.isNotEmpty) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('highlighted_segment'),
            points: segCoords,
            color: Colors.amber.shade900,
            width: 8,
            zIndex: 10,
          ),
        );
      }
      markers.add(
        Marker(
          markerId: const MarkerId('inspected_marker'),
          position: LatLng(seg.startLat, seg.startLon),
          infoWindow: InfoWindow(
            title: 'Segment ${_inspectedSegmentIndex! + 1}: ${seg.roadName}',
            snippet:
                '${seg.distanceMeters.toInt()}m · ${seg.traffic.congestionLevel.displayName}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange),
        ),
      );
    }

    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(_selectedPreset.originLat, _selectedPreset.originLon),
              zoom: 12,
            ),
            polylines: polylines,
            markers: markers,
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              if (_inspectedSegmentIndex != null &&
                  _inspectedSegmentIndex! < route.segments.length) {
                final s = route.segments[_inspectedSegmentIndex!];
                ctrl.animateCamera(CameraUpdate.newLatLngZoom(
                    LatLng(s.startLat, s.startLon), 16.0));
              } else {
                _fitMapToRoute();
              }
            },
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_inspectedSegmentIndex != null) ...[
                  Material(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      icon: const Icon(Icons.refresh,
                          size: 18, color: Colors.blueGrey),
                      tooltip: 'Reset map view to whole route',
                      onPressed: () {
                        setState(() {
                          _inspectedSegmentIndex = null;
                        });
                        _fitMapToRoute();
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Material(
                  color: Colors.white.withValues(alpha: 0.95),
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen,
                        size: 22, color: Colors.black87),
                    tooltip: 'Maximize Map (Fullscreen)',
                    onPressed: () {
                      setState(() => _isMapFullscreen = true);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    final r = _routes[_selectedRouteIndex];
    final km = (r.distanceMeters / 1000.0).toStringAsFixed(1);
    final durMin = (r.trafficDurationSeconds / 60.0).toStringAsFixed(0);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r.summary} ($km km)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '~ $durMin mins',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Provider: ${r.providerName}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metricPill(
                  label: 'Segments',
                  value: '${r.segments.length}',
                  color: Colors.grey.shade800,
                ),
                _metricPill(
                  label: 'Flood Spots',
                  value: '${r.detectedFloodSpotsCount}',
                  color: r.detectedFloodSpotsCount > 0
                      ? Colors.blue.shade800
                      : Colors.green.shade700,
                ),
                _metricPill(
                  label: 'Blackspots',
                  value: '${r.detectedAccidentBlackspotsCount}',
                  color: r.detectedAccidentBlackspotsCount > 0
                      ? Colors.red.shade800
                      : Colors.green.shade700,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficCard() {
    final r = _routes[_selectedRouteIndex];
    final delayMin = (r.trafficDelaySeconds / 60.0).toStringAsFixed(1);

    Color badgeColor = Colors.green.shade100;
    Color textColor = Colors.green.shade900;
    if (r.overallCongestion == CongestionLevel.heavy ||
        r.overallCongestion == CongestionLevel.severe) {
      badgeColor = Colors.red.shade100;
      textColor = Colors.red.shade900;
    } else if (r.overallCongestion == CongestionLevel.moderate) {
      badgeColor = Colors.amber.shade100;
      textColor = Colors.amber.shade900;
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.traffic, size: 20, color: Colors.orange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Traffic & Congestion',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.overallCongestion.displayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _infoRow(
              'Normal Travel Time (Free flow)',
              '${(r.staticDurationSeconds / 60.0).toStringAsFixed(0)} mins',
            ),
            _infoRow(
              'Traffic-Aware Travel Time',
              '${(r.trafficDurationSeconds / 60.0).toStringAsFixed(0)} mins',
            ),
            _infoRow('Calculated Traffic Delay', '+$delayMin mins'),
            _infoRow('Data Freshness', '${r.freshnessSeconds}s ago'),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    final r = _routes[_selectedRouteIndex];
    final w = r.sampleWeather;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_cloudy_outlined,
                    size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Weather & Precipitation',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    w.source,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _infoRow(
              'Conditions',
              w.weatherDescription,
              highlight: w.isSevereWeatherAlert,
            ),
            _infoRow(
              'Temperature',
              w.temperatureC != null ? '${w.temperatureC}°C' : 'Unknown',
            ),
            _infoRow(
              'Precipitation Rate',
              w.rainfallMmPerHour != null
                  ? '${w.rainfallMmPerHour} mm/hr'
                  : '0.0 mm/hr',
            ),
            _infoRow(
              'Rain Probability',
              w.precipitationProbabilityPercent != null
                  ? '${w.precipitationProbabilityPercent}%'
                  : 'Unknown',
            ),
            _infoRow(
              'Wind Speed',
              w.windSpeedKmh != null ? '${w.windSpeedKmh} km/h' : 'Unknown',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloodCard() {
    final r = _routes[_selectedRouteIndex];
    final floodSegments =
        r.segments.where((s) => s.flood.isHistoricalFloodProne).toList();

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water_damage_outlined,
                    size: 20, color: Colors.blueAccent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Flood Vulnerability (BBMP & KSNDMC)',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: floodSegments.isNotEmpty
                        ? Colors.blue.shade100
                        : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    floodSegments.isNotEmpty
                        ? '${floodSegments.length} Flood Spots'
                        : 'No Blackspots',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: floodSegments.isNotEmpty
                          ? Colors.blue.shade900
                          : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (floodSegments.isEmpty)
              const Text(
                'No officially cataloged BBMP/KSNDMC waterlogging blackspots intersect this route.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              )
            else
              Column(
                children: [
                  for (final fs in floodSegments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber,
                              size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${fs.flood.historicalSpotName} (${fs.flood.vulnerabilityRank})',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (fs.flood.elevationMeters != null)
                            Text(
                              '${fs.flood.elevationMeters!.toInt()}m alt',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccidentCard() {
    final r = _routes[_selectedRouteIndex];
    final accSegments =
        r.segments.where((s) => s.accident.isHistoricalBlackspot).toList();

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.car_crash_outlined, size: 20, color: Colors.red),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Accident Risk (MoRTH & Police)',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accSegments.isNotEmpty
                        ? Colors.red.shade100
                        : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    accSegments.isNotEmpty
                        ? '${accSegments.length} Blackspots'
                        : 'Clear',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accSegments.isNotEmpty
                          ? Colors.red.shade900
                          : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (accSegments.isEmpty)
              const Text(
                'No official MoRTH high-fatality accident blackspots registered on this route.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              )
            else
              Column(
                children: [
                  for (final as in accSegments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.report_problem_outlined,
                              size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${as.accident.blackspotName} (${as.accident.severity.displayName})',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (as.accident.fatalitiesPast3Yr != null)
                            Text(
                              '${as.accident.fatalitiesPast3Yr} fatalities (3yr)',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoadConditionCard() {
    final r = _routes[_selectedRouteIndex];
    final knownSegments = r.segments
        .where((s) => s.roadCondition.condition != RoadCondition.unknown)
        .length;
    final unknownSegments = r.segments.length - knownSegments;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.straighten, size: 20, color: Colors.teal),
                SizedBox(width: 8),
                Text(
                  'Road Surface & Roughness',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _infoRow(
              'Traversed Sensor History',
              knownSegments > 0
                  ? '$knownSegments segments calibrated'
                  : '0 segments traversed',
            ),
            _infoRow(
              'Untraversed Segments',
              '$unknownSegments (Marked explicitly as UNKNOWN)',
            ),
            _infoRow(
              'Data Policy',
              'Zero fake pothole generation',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentInspectionTile() {
    final r = _routes[_selectedRouteIndex];

    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(
        'Inspect All ${r.segments.length} Discrete Road Segments',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: const Text(
        'Tap any segment to inspect coordinates, weather, flood & blackspots',
        style: TextStyle(fontSize: 11),
      ),
      children: [
        for (var i = 0; i < r.segments.length; i++) ...[
          _buildSegmentTile(r.segments[i], i),
          const Divider(height: 1),
        ],
      ],
    );
  }

  Widget _buildSegmentTile(RoadSegmentData seg, int index) {
    final isInspected = _inspectedSegmentIndex == index;

    return ListTile(
      dense: true,
      selected: isInspected,
      selectedTileColor: Colors.teal.shade50.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: CircleAvatar(
        radius: 13,
        backgroundColor:
            isInspected ? Colors.teal.shade700 : Colors.grey.shade200,
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isInspected ? Colors.white : Colors.black87,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              seg.roadName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isInspected ? Colors.teal.shade900 : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (seg.flood.isHistoricalFloodProne) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'FLOOD',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          ],
          if (seg.accident.isHistoricalBlackspot) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'BLACKSPOT',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${seg.distanceMeters.toInt()}m · '
        'Traffic: ${seg.traffic.congestionLevel.displayName} · '
        'Flood: ${seg.flood.vulnerabilityRank} · '
        'Accident: ${seg.accident.severity.displayName}',
        style: const TextStyle(fontSize: 10),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.teal),
      onTap: () {
        setState(() {
          _inspectedSegmentIndex = index;
        });
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(seg.startLat, seg.startLon),
            16.0,
          ),
        );
        _showSegmentDetailModal(context, seg, index + 1);
      },
    );
  }

  void _showSegmentDetailModal(
      BuildContext context, RoadSegmentData seg, int index) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          expand: false,
          builder: (sheetContext, scrollController) {
            return Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.teal.shade700,
                        child: Text(
                          '$index',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              seg.roadName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Segment $index of ${_routes[_selectedRouteIndex].segments.length} · ${seg.distanceMeters.toInt()} meters',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding:
                        EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomPadding),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.my_location, size: 16),
                              label: const Text('Focus on Map',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _mapController?.animateCamera(
                                  CameraUpdate.newLatLngZoom(
                                    LatLng(seg.startLat, seg.startLon),
                                    16.5,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.zoom_out_map, size: 16),
                              label: const Text('Whole Route',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _fitMapToRoute();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildModalSection(
                        icon: Icons.place_outlined,
                        iconColor: Colors.blue,
                        title: 'GPS Coordinates & Geometry',
                        children: [
                          _infoRow(
                            'Start Coordinate',
                            '${seg.startLat.toStringAsFixed(5)}, ${seg.startLon.toStringAsFixed(5)}',
                          ),
                          _infoRow(
                            'End Coordinate',
                            '${seg.endLat.toStringAsFixed(5)}, ${seg.endLon.toStringAsFixed(5)}',
                          ),
                          _infoRow(
                            'Segment Distance',
                            '${seg.distanceMeters.toStringAsFixed(0)} meters',
                          ),
                          _infoRow(
                            'Est. Travel Time',
                            '${(seg.durationSeconds / 60.0).toStringAsFixed(1)} min',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildModalSection(
                        icon: Icons.traffic,
                        iconColor: Colors.orange,
                        title: 'Real-World Traffic & Delay',
                        children: [
                          _infoRow(
                            'Congestion Level',
                            seg.traffic.congestionLevel.displayName,
                          ),
                          _infoRow(
                            'Traffic Delay',
                            '+${(seg.traffic.delaySeconds ?? 0).toStringAsFixed(0)}s',
                          ),
                          _infoRow(
                            'Delay Ratio',
                            '${(seg.traffic.delayRatio ?? 1.0).toStringAsFixed(2)}x',
                          ),
                          _infoRow(
                            'Telemetry Source',
                            seg.traffic.source,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildModalSection(
                        icon: Icons.wb_cloudy_outlined,
                        iconColor: Colors.lightBlue,
                        title: 'Open-Meteo Segment Weather',
                        children: [
                          _infoRow(
                            'Conditions',
                            seg.weather.weatherDescription,
                            highlight: seg.weather.isSevereWeatherAlert,
                          ),
                          _infoRow(
                            'Temperature',
                            seg.weather.temperatureC != null
                                ? '${seg.weather.temperatureC}°C'
                                : 'Unknown',
                          ),
                          _infoRow(
                            'Rain Rate',
                            seg.weather.rainfallMmPerHour != null
                                ? '${seg.weather.rainfallMmPerHour} mm/hr'
                                : '0.0 mm/hr',
                          ),
                          _infoRow(
                            'Rain Probability',
                            seg.weather.precipitationProbabilityPercent != null
                                ? '${seg.weather.precipitationProbabilityPercent}%'
                                : 'Unknown',
                          ),
                          _infoRow(
                            'Wind Speed',
                            seg.weather.windSpeedKmh != null
                                ? '${seg.weather.windSpeedKmh} km/h'
                                : 'Unknown',
                          ),
                          _infoRow('Source', seg.weather.source),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildModalSection(
                        icon: Icons.water_damage_outlined,
                        iconColor: Colors.blueAccent,
                        title: 'BBMP & KSNDMC Flood Vulnerability',
                        children: [
                          _infoRow(
                            'Flood Spot Status',
                            seg.flood.isHistoricalFloodProne
                                ? 'YES (Recorded Flood Spot)'
                                : 'Clear (No BBMP Blackspot)',
                            highlight: seg.flood.isHistoricalFloodProne,
                          ),
                          if (seg.flood.isHistoricalFloodProne) ...[
                            _infoRow('Cataloged Name',
                                seg.flood.historicalSpotName ?? 'N/A'),
                            _infoRow('Vulnerability Rank',
                                seg.flood.vulnerabilityRank),
                            if (seg.flood.elevationMeters != null)
                              _infoRow('Elevation',
                                  '${seg.flood.elevationMeters!.toInt()}m altitude'),
                          ],
                          _infoRow('Data Source', seg.flood.source),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildModalSection(
                        icon: Icons.car_crash_outlined,
                        iconColor: Colors.red,
                        title: 'MoRTH & Police Accident Risk',
                        children: [
                          _infoRow(
                            'Accident Blackspot',
                            seg.accident.isHistoricalBlackspot
                                ? 'YES (${seg.accident.severity.displayName})'
                                : 'Clear (No Registered Blackspot)',
                            highlight: seg.accident.isHistoricalBlackspot,
                          ),
                          if (seg.accident.isHistoricalBlackspot) ...[
                            _infoRow('Location Name',
                                seg.accident.blackspotName ?? 'N/A'),
                            _infoRow('Severity Level',
                                seg.accident.severity.displayName),
                            if (seg.accident.fatalitiesPast3Yr != null)
                              _infoRow('3-Yr Fatalities',
                                  '${seg.accident.fatalitiesPast3Yr} fatalities reported'),
                          ],
                          _infoRow('Data Source', seg.accident.source),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildModalSection(
                        icon: Icons.straighten,
                        iconColor: Colors.teal,
                        title: 'Road Surface & Sensor History',
                        children: [
                          _infoRow('Road Condition',
                              seg.roadCondition.condition.displayName),
                          _infoRow('Calibration Source',
                              seg.roadCondition.source),
                          _infoRow(
                            'Data Policy',
                            'Zero fake pothole generation (Explicitly UNKNOWN until traversed)',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildModalSection(
                        icon: Icons.construction_outlined,
                        iconColor: Colors.deepOrange,
                        title: 'Construction & Road Advisories',
                        children: [
                          _infoRow(
                              'Status', seg.construction.status.displayName),
                          if (seg.construction.details != null)
                            _infoRow(
                                'Advisory Details', seg.construction.details!),
                          _infoRow('Source', seg.construction.source),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildModalSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: highlight ? Colors.red : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildFullscreenMapView() {
    final r = _routes[_selectedRouteIndex];
    final polylineCoords =
        r.fullPolyline.map((p) => LatLng(p.lat, p.lon)).toList();

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('origin'),
        position:
            LatLng(_selectedPreset.originLat, _selectedPreset.originLon),
        infoWindow: InfoWindow(title: 'Start: ${_selectedPreset.originName}'),
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position:
            LatLng(_selectedPreset.destLat, _selectedPreset.destLon),
        infoWindow:
            InfoWindow(title: 'Destination: ${_selectedPreset.destName}'),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    for (var i = 0; i < r.segments.length; i++) {
      final s = r.segments[i];
      if (s.flood.isHistoricalFloodProne) {
        markers.add(
          Marker(
            markerId: MarkerId('flood_$i'),
            position: LatLng(s.startLat, s.startLon),
            infoWindow: InfoWindow(
              title: 'Flood Spot: ${s.flood.historicalSpotName ?? s.roadName}',
              snippet:
                  'Severity: ${s.flood.vulnerabilityRank} (${s.flood.elevationMeters?.toInt() ?? 0}m alt)',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueCyan),
          ),
        );
      }
      if (s.accident.isHistoricalBlackspot) {
        markers.add(
          Marker(
            markerId: MarkerId('accident_$i'),
            position: LatLng(s.startLat, s.startLon),
            infoWindow: InfoWindow(
              title:
                  'Accident Blackspot: ${s.accident.blackspotName ?? s.roadName}',
              snippet:
                  'Severity: ${s.accident.severity.displayName} · ${s.accident.fatalitiesPast3Yr ?? 0} deaths (3yr)',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRose),
          ),
        );
      }
    }

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('fullscreen_route'),
        points: polylineCoords,
        color: const Color(0xff1976d2),
        width: 6,
      ),
    };

    if (_inspectedSegmentIndex != null &&
        _inspectedSegmentIndex! >= 0 &&
        _inspectedSegmentIndex! < r.segments.length) {
      final seg = r.segments[_inspectedSegmentIndex!];
      final segCoords =
          seg.polyline.map((p) => LatLng(p.lat, p.lon)).toList();
      if (segCoords.isNotEmpty) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('highlighted_segment_full'),
            points: segCoords,
            color: Colors.amber.shade900,
            width: 9,
            zIndex: 10,
          ),
        );
      }
      markers.add(
        Marker(
          markerId: const MarkerId('active_segment_marker'),
          position: LatLng(seg.startLat, seg.startLon),
          infoWindow: InfoWindow(
            title: 'Segment ${_inspectedSegmentIndex! + 1}: ${seg.roadName}',
            snippet:
                '${seg.distanceMeters.toInt()}m · ${seg.traffic.congestionLevel.displayName}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange),
        ),
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target:
                  LatLng(_selectedPreset.originLat, _selectedPreset.originLon),
              zoom: 12,
            ),
            polylines: polylines,
            markers: markers,
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              if (_inspectedSegmentIndex != null &&
                  _inspectedSegmentIndex! < r.segments.length) {
                final s = r.segments[_inspectedSegmentIndex!];
                ctrl.animateCamera(CameraUpdate.newLatLngZoom(
                    LatLng(s.startLat, s.startLon), 16.0));
              } else {
                _fitMapToRoute();
              }
            },
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Exit Fullscreen',
                      onPressed: () {
                        setState(() => _isMapFullscreen = false);
                      },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedPreset.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Route ${_selectedRouteIndex + 1}: ${r.summary}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen_exit),
                      tooltip: 'Exit Fullscreen',
                      onPressed: () {
                        setState(() => _isMapFullscreen = false);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.crop_free),
                      tooltip: 'Fit entire route to screen',
                      onPressed: () {
                        setState(() => _inspectedSegmentIndex = null);
                        _fitMapToRoute();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 16 + bottomInset,
            left: 16,
            right: 16,
            child: _buildFullscreenBottomCard(r),
          ),
        ],
      ),
    );
  }

  Widget _buildFullscreenBottomCard(NormalizedRouteData r) {
    final currentIndex = _inspectedSegmentIndex ?? 0;
    final seg = r.segments.isNotEmpty && currentIndex < r.segments.length
        ? r.segments[currentIndex]
        : null;

    if (seg == null) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('No segments recorded for this route.'),
        ),
      );
    }

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.chevron_left, size: 16),
                  label: const Text('Prev', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: currentIndex > 0
                      ? () {
                          final prevIdx = currentIndex - 1;
                          setState(() => _inspectedSegmentIndex = prevIdx);
                          _mapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(
                                  LatLng(r.segments[prevIdx].startLat,
                                      r.segments[prevIdx].startLon),
                                  16.0));
                        }
                      : null,
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Text(
                    'Segment ${currentIndex + 1} of ${r.segments.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900,
                    ),
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: currentIndex < r.segments.length - 1
                      ? () {
                          final nextIdx = currentIndex + 1;
                          setState(() => _inspectedSegmentIndex = nextIdx);
                          _mapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(
                                  LatLng(r.segments[nextIdx].startLat,
                                      r.segments[nextIdx].startLon),
                                  16.0));
                        }
                      : null,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Next', style: TextStyle(fontSize: 11)),
                      Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    seg.roadName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (seg.flood.isHistoricalFloodProne) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('FLOOD',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue)),
                  ),
                ],
                if (seg.accident.isHistoricalBlackspot) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('BLACKSPOT',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.red)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${seg.distanceMeters.toInt()}m · Traffic: ${seg.traffic.congestionLevel.displayName} · Flood: ${seg.flood.vulnerabilityRank}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.info_outline, size: 16),
                label: const Text('View Full Segment Telemetry',
                    style: TextStyle(fontSize: 12)),
                onPressed: () =>
                    _showSegmentDetailModal(context, seg, currentIndex + 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
