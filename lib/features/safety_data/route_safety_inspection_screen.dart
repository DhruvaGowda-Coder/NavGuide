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

  @override
  void initState() {
    super.initState();
    _selectedPreset = kBangaloreRoutePresets[widget.initialPresetIndex];
    _fetchRoutes();
  }

  Future<void> _fetchRoutes({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
                  children: [
                    _buildRouteTabs(),
                    const SizedBox(height: 12),
                    _buildMiniMap(),
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

    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(_selectedPreset.originLat, _selectedPreset.originLon),
          zoom: 12,
        ),
        polylines: {
          Polyline(
            polylineId: const PolylineId('selected_route'),
            points: polylineCoords,
            color: const Color(0xff1976d2),
            width: 5,
          ),
        },
        markers: {
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
        },
        onMapCreated: (ctrl) {
          _mapController = ctrl;
          _fitMapToRoute();
        },
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${r.summary} ($km km)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.traffic, size: 20, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(
                      'Traffic & Congestion',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.wb_cloudy_outlined,
                        size: 20, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'Weather & Precipitation',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Text(
                  w.source,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.water_damage_outlined,
                        size: 20, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text(
                      'Flood Vulnerability (BBMP & KSNDMC)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.car_crash_outlined, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      'Accident Risk (MoRTH & Police)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
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
      title: Text(
        'Inspect All ${r.segments.length} Discrete Road Segments',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: const Text(
        'View turn-by-turn road names, distance, and normalized fields',
        style: TextStyle(fontSize: 11),
      ),
      children: [
        for (var i = 0; i < r.segments.length; i++) ...[
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.grey.shade200,
              child: Text('${i + 1}', style: const TextStyle(fontSize: 10)),
            ),
            title: Text(
              r.segments[i].roadName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            subtitle: Text(
              '${r.segments[i].distanceMeters.toInt()}m · '
              'Traffic: ${r.segments[i].traffic.congestionLevel.displayName} · '
              'Flood: ${r.segments[i].flood.vulnerabilityRank} · '
              'Accident: ${r.segments[i].accident.severity.displayName}',
              style: const TextStyle(fontSize: 10),
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: highlight ? Colors.red : Colors.black87,
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
}
