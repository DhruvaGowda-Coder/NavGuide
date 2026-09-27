import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../domain/route_safety_models.dart';
import '../../domain/safety_scoring_models.dart';
import '../../device/safety_data/route_safety_data_service.dart';
import '../../device/safety_scoring/safety_scoring_engine.dart';
import '../../device/safety_scoring/bayesian_route_risk_evaluator.dart';
import '../navigation/live_navigation_screen.dart';
import '../safety_data/route_safety_inspection_screen.dart';

class RouteSafetyRecommendationScreen extends StatefulWidget {
  const RouteSafetyRecommendationScreen({
    super.key,
    this.initialPresetIndex = 0,
    this.customOriginLat,
    this.customOriginLon,
    this.customOriginName,
    this.customDestLat,
    this.customDestLon,
    this.customDestName,
  });

  final int initialPresetIndex;
  final double? customOriginLat;
  final double? customOriginLon;
  final String? customOriginName;
  final double? customDestLat;
  final double? customDestLon;
  final String? customDestName;

  @override
  State<RouteSafetyRecommendationScreen> createState() =>
      _RouteSafetyRecommendationScreenState();
}

class _RouteSafetyRecommendationScreenState
    extends State<RouteSafetyRecommendationScreen> {
  final RouteSafetyDataService _dataService = RouteSafetyDataService();
  final SafetyScoringEngine _scoringEngine = SafetyScoringEngine();
  final BayesianRouteRiskEvaluator _bayesianEvaluator =
      const BayesianRouteRiskEvaluator();

  late RoutePreset _selectedPreset;
  ScoringMode _selectedMode = ScoringMode.balanced;

  bool _isLoading = true;
  String? _errorMessage;
  List<NormalizedRouteData> _candidateRoutes = [];
  List<RankedRoute> _rankedRoutes = [];
  int _selectedRouteIndex = 0;
  bool _isMapExpanded = false;
  bool _is3dPerspective = true;
  final Map<String, List<LatLng>> _latLngCache = {};

  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    final idx = widget.initialPresetIndex.clamp(0, kBangaloreRoutePresets.length - 1);
    _selectedPreset = kBangaloreRoutePresets[idx];
    _fetchAndScoreRoutes();
  }

  Future<void> _fetchAndScoreRoutes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    var oLat = widget.customOriginLat ?? _selectedPreset.originLat;
    var oLon = widget.customOriginLon ?? _selectedPreset.originLon;
    final dLat = widget.customDestLat ?? _selectedPreset.destLat;
    final dLon = widget.customDestLon ?? _selectedPreset.destLon;
    var oName = widget.customOriginName ?? _selectedPreset.originName;
    final dName = widget.customDestName ?? _selectedPreset.destName;

    // If destination was searched but origin is default Bengaluru center, acquire actual GPS if known
    if (widget.customDestLat != null &&
        (widget.customOriginLat == null ||
            (widget.customOriginLat! >= 12.9715 &&
             widget.customOriginLat! <= 12.9717 &&
             widget.customOriginLon! >= 77.5945 &&
             widget.customOriginLon! <= 77.5947))) {
      try {
        final pos = await Geolocator.getLastKnownPosition().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => null,
        );
        if (pos != null) {
          oLat = pos.latitude;
          oLon = pos.longitude;
          oName = 'Current Location';
        }
      } catch (_) {}
    }

    try {
      final routes = await _dataService.fetchEnrichedRoutes(
        originLat: oLat,
        originLon: oLon,
        destLat: dLat,
        destLon: dLon,
        originName: oName,
        destName: dName,
      );

      final ranked = _scoringEngine.rankRoutes(routes, mode: _selectedMode);

      _latLngCache.clear();
      for (final r in routes) {
        _latLngCache[r.routeId] = r.fullPolyline
            .map((p) => LatLng(p.lat, p.lon))
            .toList(growable: false);
      }

      if (!mounted) return;
      setState(() {
        _candidateRoutes = routes;
        _rankedRoutes = ranked;
        _selectedRouteIndex = 0;
        _isLoading = false;
      });

      _fitMapToRoutes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to score corridor routes: $e';
        _isLoading = false;
      });
    }
  }

  void _onModeChanged(ScoringMode newMode) {
    if (_selectedMode == newMode) return;
    final newlyRanked = _scoringEngine.rankRoutes(_candidateRoutes, mode: newMode);
    setState(() {
      _selectedMode = newMode;
      _rankedRoutes = newlyRanked;
      _selectedRouteIndex = 0;
    });
    if (newlyRanked.isNotEmpty) {
      _fitMapToRoute(newlyRanked.first.route);
    }
  }

  void _fitMapToRoute(NormalizedRouteData route) {
    if (!mounted || _mapController == null || route.fullPolyline.isEmpty) return;
    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final pt in route.fullPolyline) {
      if (pt.lat < minLat) minLat = pt.lat;
      if (pt.lat > maxLat) maxLat = pt.lat;
      if (pt.lon < minLon) minLon = pt.lon;
      if (pt.lon > maxLon) maxLon = pt.lon;
    }
    if (minLat < maxLat) {
      final double centerLat = (minLat + maxLat) / 2;
      final double centerLon = (minLon + maxLon) / 2;
      double bearing = 0.0;
      if (route.fullPolyline.length >= 2) {
        bearing = Geolocator.bearingBetween(
          route.fullPolyline.first.lat,
          route.fullPolyline.first.lon,
          route.fullPolyline.last.lat,
          route.fullPolyline.last.lon,
        );
      }

      final maxDiff = math.max((maxLat - minLat).abs(), (maxLon - minLon).abs());
      double zoom = 12.0;
      if (maxDiff < 0.02) {
        zoom = 14.8;
      } else if (maxDiff < 0.06) {
        zoom = 13.5;
      } else if (maxDiff < 0.12) {
        zoom = 12.2;
      } else if (maxDiff < 0.25) {
        zoom = 11.2;
      } else if (maxDiff < 0.5) {
        zoom = 10.2;
      } else {
        zoom = 9.0;
      }

      final double targetTilt = _is3dPerspective ? 65.0 : 0.0;
      final double targetZoom = _is3dPerspective ? (zoom + 1.2) : zoom;
      final double targetBearing = _is3dPerspective
          ? (bearing.abs() > 0.1 ? bearing : 28.0)
          : 0.0;

      try {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(centerLat, centerLon),
              zoom: targetZoom,
              tilt: targetTilt,
              bearing: targetBearing,
            ),
          ),
        );
      } catch (_) {
        try {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat - 0.005, minLon - 0.005),
                northeast: LatLng(maxLat + 0.005, maxLon + 0.005),
              ),
              50,
            ),
          );
        } catch (_) {}
      }
    }
  }

  void _fitMapToRoutes() {
    if (!mounted || _mapController == null || _candidateRoutes.isEmpty) return;
    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final r in _candidateRoutes) {
      for (final pt in r.fullPolyline) {
        if (pt.lat < minLat) minLat = pt.lat;
        if (pt.lat > maxLat) maxLat = pt.lat;
        if (pt.lon < minLon) minLon = pt.lon;
        if (pt.lon > maxLon) maxLon = pt.lon;
      }
    }
    if (minLat < maxLat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _mapController == null) return;
        final double centerLat = (minLat + maxLat) / 2;
        final double centerLon = (minLon + maxLon) / 2;
        final maxDiff = math.max((maxLat - minLat).abs(), (maxLon - minLon).abs());
        double zoom = 12.0;
        if (maxDiff < 0.02) {
          zoom = 14.8;
        } else if (maxDiff < 0.06) {
          zoom = 13.5;
        } else if (maxDiff < 0.12) {
          zoom = 12.0;
        } else if (maxDiff < 0.25) {
          zoom = 11.0;
        } else if (maxDiff < 0.5) {
          zoom = 10.0;
        } else {
          zoom = 8.8;
        }

        final double targetTilt = _is3dPerspective ? 65.0 : 0.0;
        final double targetZoom = _is3dPerspective ? (zoom + 1.2) : zoom;
        final double targetBearing = _is3dPerspective ? 25.0 : 0.0;

        try {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(centerLat, centerLon),
                zoom: targetZoom,
                tilt: targetTilt,
                bearing: targetBearing,
              ),
            ),
          );
        } catch (_) {
          try {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(minLat - 0.01, minLon - 0.01),
                  northeast: LatLng(maxLat + 0.01, maxLon + 0.01),
                ),
                50,
              ),
            );
          } catch (_) {}
        }
      });
    }
  }

  Set<Polyline> _buildPolylines() {
    final polylines = <Polyline>{};

    // Render unselected routes first (underneath, in muted slate grey)
    for (var i = 0; i < _rankedRoutes.length; i++) {
      if (i == _selectedRouteIndex) continue;
      final ranked = _rankedRoutes[i];
      final points = _latLngCache[ranked.route.routeId] ??
          ranked.route.fullPolyline
              .map((p) => LatLng(p.lat, p.lon))
              .toList(growable: false);

      polylines.add(
        Polyline(
          polylineId: PolylineId('route_${ranked.route.routeId}_$i'),
          points: points,
          width: 5,
          color: const Color(0xff94a3b8), // Slate grey
          zIndex: 1,
          onTap: () {
            setState(() {
              _selectedRouteIndex = i;
            });
            _fitMapToRoute(ranked.route);
          },
          consumeTapEvents: true,
        ),
      );
    }

    // Render selected route on top (standard green, width 7, zIndex 100)
    if (_rankedRoutes.isNotEmpty && _selectedRouteIndex < _rankedRoutes.length) {
      final selectedRanked = _rankedRoutes[_selectedRouteIndex];
      final points = _latLngCache[selectedRanked.route.routeId] ??
          selectedRanked.route.fullPolyline
              .map((p) => LatLng(p.lat, p.lon))
              .toList(growable: false);
      final isAvoid = selectedRanked.safetyScore.recommendationStatus ==
          RecommendationStatus.avoid;

      polylines.add(
        Polyline(
          polylineId: PolylineId('route_${selectedRanked.route.routeId}_sel'),
          points: points,
          width: 7,
          color: isAvoid ? Colors.red.shade700 : const Color(0xff1e8e3e), // Standard green
          zIndex: 100,
          onTap: () {
            _fitMapToRoute(selectedRanked.route);
          },
          consumeTapEvents: true,
        ),
      );
    }

    return polylines;
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    final oLat = widget.customOriginLat ?? _selectedPreset.originLat;
    final oLon = widget.customOriginLon ?? _selectedPreset.originLon;
    final dLat = widget.customDestLat ?? _selectedPreset.destLat;
    final dLon = widget.customDestLon ?? _selectedPreset.destLon;
    final oName = widget.customOriginName ?? _selectedPreset.originName;
    final dName = widget.customDestName ?? _selectedPreset.destName;

    markers.add(
      Marker(
        markerId: const MarkerId('origin'),
        position: LatLng(oLat, oLon),
        infoWindow: InfoWindow(title: 'Start: $oName', snippet: 'Your starting point'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    );
    markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(dLat, dLon),
        infoWindow: InfoWindow(title: 'Destination: $dName', snippet: 'Target reach point'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    if (_rankedRoutes.isNotEmpty && _selectedRouteIndex < _rankedRoutes.length) {
      final currentRoute = _rankedRoutes[_selectedRouteIndex].route;
      for (final seg in currentRoute.segments) {
        if (seg.flood.isHistoricalFloodProne) {
          markers.add(
            Marker(
              markerId: MarkerId('flood_${seg.segmentId}'),
              position: LatLng(seg.startLat, seg.startLon),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
              infoWindow: InfoWindow(
                title: 'Flood Spot: ${seg.flood.historicalSpotName ?? "Underpass"}',
                snippet: 'Rank: ${seg.flood.vulnerabilityRank}',
              ),
            ),
          );
        }
        if (seg.accident.isHistoricalBlackspot) {
          markers.add(
            Marker(
              markerId: MarkerId('accident_${seg.segmentId}'),
              position: LatLng(seg.startLat, seg.startLon),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
              infoWindow: InfoWindow(
                title: 'Accident Blackspot: ${seg.accident.blackspotName ?? "Road Blackspot"}',
                snippet: 'Severity: ${seg.accident.severity.displayName}',
              ),
            ),
          );
        }
      }
    }

    return markers;
  }

  Set<Circle> _buildCircles() {
    final circles = <Circle>{};
    final dLat = widget.customDestLat ?? _selectedPreset.destLat;
    final dLon = widget.customDestLon ?? _selectedPreset.destLon;
    circles.add(
      Circle(
        circleId: const CircleId('dest_reach_beacon'),
        center: LatLng(dLat, dLon),
        radius: 40.0,
        strokeWidth: 2,
        strokeColor: const Color(0xffef4444),
        fillColor: const Color(0x28ef4444),
      ),
    );
    return circles;
  }

  Color _getScoreColor(int score, RecommendationStatus status) {
    if (status == RecommendationStatus.avoid) return Colors.red.shade700;
    if (score >= 80) return const Color(0xff10b981);
    if (score >= 65) return Colors.amber.shade800;
    if (score >= 50) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final currentRanked = (_rankedRoutes.isNotEmpty &&
            _selectedRouteIndex < _rankedRoutes.length)
        ? _rankedRoutes[_selectedRouteIndex]
        : null;

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safest-Route AI Engine',

            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

        actions: [
          if (widget.customDestLat == null)
            IconButton(
              tooltip: 'Sample Corridors',
              icon: const Icon(Icons.tune),
              onPressed: _showPresetSelector,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: currentRanked != null
                                  ? _getScoreColor(
                                      currentRanked.safetyScore.overallScore,
                                      currentRanked.safetyScore.recommendationStatus,
                                    )
                                  : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            currentRanked != null
                                ? 'Route #${currentRanked.rank} • ${currentRanked.safetyScore.recommendationStatus.displayName}'
                                : 'Evaluating...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: currentRanked != null
                                  ? _getScoreColor(
                                      currentRanked.safetyScore.overallScore,
                                      currentRanked.safetyScore.recommendationStatus,
                                    )
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        currentRanked != null
                            ? '${currentRanked.safetyScore.overallScore}/100 Safety • ${(currentRanked.route.trafficDurationSeconds / 60).round()} min (${(currentRanked.route.distanceMeters / 1000).toStringAsFixed(1)} km)'
                            : '',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff23695a),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: currentRanked == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveNavigationScreen(
                              selectedRoute: currentRanked,
                              destinationName: widget.customDestName ?? _selectedPreset.destName,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.navigation, size: 16),
                label: const Text('Start Route', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xff23695a)),
                  SizedBox(height: 16),
                  Text('Calculating 6D segment risks & multi-objective ranking...',
                      style: TextStyle(fontSize: 13, color: Colors.black54)),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchAndScoreRoutes,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Mode Selector Bar
                    _buildModeSelector(),

                    // Map View (with expand/minimize toggle)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      height: _isMapExpanded ? 340.0 : 190.0,
                      child: Stack(
                        children: [
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng(_selectedPreset.originLat,
                                  _selectedPreset.originLon),
                              zoom: 12.5,
                            ),
                            polylines: _buildPolylines(),
                            markers: _buildMarkers(),
                            circles: _buildCircles(),
                            onMapCreated: (ctrl) {
                              _mapController = ctrl;
                              _fitMapToRoutes();
                            },
                            buildingsEnabled: true,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: Offset(0, 2)),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.alt_route,
                                      size: 14, color: Color(0xff23695a)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_candidateRoutes.length} Candidate Routes Evaluated',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 3D / 2D Perspective Toggle Button
                                Container(
                                  decoration: BoxDecoration(
                                    color: _is3dPerspective ? const Color(0xff23695a) : Colors.white.withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _is3dPerspective = !_is3dPerspective;
                                        });
                                        if (_rankedRoutes.isNotEmpty && _selectedRouteIndex < _rankedRoutes.length) {
                                          _fitMapToRoute(_rankedRoutes[_selectedRouteIndex].route);
                                        } else {
                                          _fitMapToRoutes();
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.view_in_ar_rounded,
                                              size: 15,
                                              color: _is3dPerspective ? Colors.white : const Color(0xff23695a),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _is3dPerspective ? '3D' : '2D',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                                color: _is3dPerspective ? Colors.white : const Color(0xff23695a),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Maximize / Minimize Map Button
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 4,
                                          offset: Offset(0, 2)),
                                    ],
                                  ),
                                  child: IconButton(
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      _isMapExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                                      size: 20,
                                      color: const Color(0xff23695a),
                                    ),
                                    tooltip: _isMapExpanded ? 'Minimize Map' : 'Expand Map',
                                    onPressed: () {
                                      setState(() {
                                        _isMapExpanded = !_isMapExpanded;
                                      });
                                      Future.delayed(const Duration(milliseconds: 260), _fitMapToRoutes);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Clean visual transition under map
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),

                    // Scrollable Route Comparison & Explainability Section
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(12, 12, 12, 28 + bottomInset),
                        children: [
                          // Candidate Route Selection Cards
                          Text('Ranked Candidate Routes',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          _buildCandidateRouteChips(),
                          const SizedBox(height: 12),

                          if (currentRanked != null) ...[
                            // Detailed Score & Headline Banner
                            _buildScoreOverviewCard(currentRanked),
                            const SizedBox(height: 12),

                            // Grounded Explanations (Why Recommended & Warnings)
                            _buildExplainabilityCard(currentRanked),
                            const SizedBox(height: 12),

                            // 6D Risk Component Radar/Breakdown
                            _buildComponentBreakdownCard(currentRanked),
                            const SizedBox(height: 12),

                            // Bayesian AI Incident Probability
                            _buildBayesianAiCard(currentRanked),
                            const SizedBox(height: 12),

                            // Segment-by-segment drilldown
                            _buildSegmentBreakdownCard(currentRanked),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 16, color: Color(0xff23695a)),
              const SizedBox(width: 6),
              Text(
                'Scoring Mode: ${_selectedMode.displayName}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'Safety ${_selectedMode.weights.safetyWeight.toStringAsFixed(2)} • Time ${_selectedMode.weights.etaWeight.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SegmentedButton<ScoringMode>(
            segments: const [
              ButtonSegment(
                value: ScoringMode.safest,
                label: Text('Safest', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.shield, size: 14),
              ),
              ButtonSegment(
                value: ScoringMode.balanced,
                label: Text('Balanced', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.balance, size: 14),
              ),
              ButtonSegment(
                value: ScoringMode.fastest,
                label: Text('Fastest', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.bolt, size: 14),
              ),
            ],
            selected: {_selectedMode},
            onSelectionChanged: (set) => _onModeChanged(set.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateRouteChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _rankedRoutes.length; i++) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _selectedRouteIndex = i;
                  });
                  _fitMapToRoute(_rankedRoutes[i].route);
                },
                child: _buildRouteSummaryCard(i, _rankedRoutes[i]),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteSummaryCard(int index, RankedRoute ranked) {
    final isSelected = index == _selectedRouteIndex;
    final score = ranked.safetyScore.overallScore;
    final status = ranked.safetyScore.recommendationStatus;
    final scoreColor = _getScoreColor(score, status);

    return SizedBox(
      width: 225,
      height: 112,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xff23695a).withValues(alpha: 0.08)
              : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xff23695a) : Colors.grey.shade300,
            width: isSelected ? 2.0 : 1.0,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xff23695a).withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: status == RecommendationStatus.avoid
                        ? Colors.red.shade100
                        : (ranked.rank == 1
                            ? Colors.green.shade100
                            : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status == RecommendationStatus.avoid
                        ? 'AVOID'
                        : '#${ranked.rank} ${status.displayName.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: status == RecommendationStatus.avoid
                          ? Colors.red.shade900
                          : (ranked.rank == 1 ? Colors.green.shade900 : Colors.black87),
                    ),
                  ),
                ),
                const Spacer(),
                CircleAvatar(
                  radius: 13,
                  backgroundColor: scoreColor.withValues(alpha: 0.15),
                  child: Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              ranked.route.summary.isNotEmpty
                  ? ranked.route.summary
                  : 'Corridor via ${ranked.route.segments.firstOrNull?.roadName ?? "Highway"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Row(
              children: [
                Text(
                  '${(ranked.route.distanceMeters / 1000).toStringAsFixed(1)} km',
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                ),
                const Text(' • ', style: TextStyle(color: Colors.black54)),
                Text(
                  '${(ranked.route.trafficDurationSeconds / 60).round()} min',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const Spacer(),
                if (ranked.timeDeltaSeconds > 0)
                  Text(
                    ranked.timeDeltaFormatted,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: ranked.timeDeltaSeconds > 300
                          ? Colors.orange.shade800
                          : Colors.black54,
                    ),
                  )
                else if (ranked.rank == 1)
                  Text(
                    'Optimal',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreOverviewCard(RankedRoute ranked) {
    final score = ranked.safetyScore.overallScore;
    final status = ranked.safetyScore.recommendationStatus;
    final scoreColor = _getScoreColor(score, status);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: CircularProgressIndicator(
                        value: score / 100.0,
                        strokeWidth: 7,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$score',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: scoreColor,
                          ),
                        ),
                        const Text('/100',
                            style:
                                TextStyle(fontSize: 9, color: Colors.black54)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              status.displayName.toUpperCase(),
                              style: TextStyle(
                                color: scoreColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _buildConfidenceBadge(ranked.safetyScore.dataConfidence),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ranked.recommendationHeadline,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Peak Hazard: ${(ranked.safetyScore.peakHazardRisk * 100).round()}% risk • Mean: ${(ranked.safetyScore.distanceWeightedMeanRisk * 100).round()}%',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.black54),
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

  Widget _buildConfidenceBadge(DataConfidence conf) {
    Color bg;
    Color fg;
    switch (conf) {
      case DataConfidence.high:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case DataConfidence.medium:
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade800;
        break;
      case DataConfidence.low:
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            '${conf.displayName} Conf.',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _buildExplainabilityCard(RankedRoute ranked) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_outline,
                    size: 16, color: Color(0xff23695a)),
                const SizedBox(width: 6),
                Text(
                  'Explainable Safety Insights',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (ranked.safetyScore.positiveExplanations.isNotEmpty) ...[
              const Text('Why Recommended:',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
              const SizedBox(height: 4),
              for (final p in ranked.safetyScore.positiveExplanations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(p, style: const TextStyle(fontSize: 11))),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
            if (ranked.safetyScore.warningExplanations.isNotEmpty) ...[
              const Text('Hazard Warnings:',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const SizedBox(height: 4),
              for (final w in ranked.safetyScore.warningExplanations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 14, color: Colors.red),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(w, style: const TextStyle(fontSize: 11))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComponentBreakdownCard(RankedRoute ranked) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, size: 16, color: Color(0xff23695a)),
                const SizedBox(width: 6),
                Text('6D Risk Component Sub-Scores (0–100)',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            for (final comp in RiskComponent.values) ...[
              _buildComponentBar(
                comp.displayName,
                ranked.safetyScore.componentScores[comp] ?? 50,
                _getComponentIcon(comp),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComponentBar(String label, int score, IconData icon) {
    final color = _getScoreColor(score, RecommendationStatus.viable);
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.black54),
        const SizedBox(width: 6),
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black87)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100.0,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 7,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 26,
          child: Text(
            '$score',
            textAlign: TextAlign.end,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
    );
  }

  IconData _getComponentIcon(RiskComponent c) {
    switch (c) {
      case RiskComponent.traffic:
        return Icons.traffic;
      case RiskComponent.weather:
        return Icons.cloud;
      case RiskComponent.flood:
        return Icons.water;
      case RiskComponent.roadCondition:
        return Icons.car_repair;
      case RiskComponent.construction:
        return Icons.construction;
      case RiskComponent.accident:
        return Icons.car_crash;
    }
  }

  Widget _buildBayesianAiCard(RankedRoute ranked) {
    final bayesComparison = _bayesianEvaluator.compareWithBaseline(
      ranked.route,
      ranked.safetyScore,
    );
    final bayesScore = bayesComparison['bayesianScore'] as int? ?? 50;
    final incidentP = (bayesComparison['bayesianIncidentProbability'] as double? ?? 0.05) * 100;
    final agreement = bayesComparison['agreement'] as String? ?? 'HIGH_AGREEMENT';
    final rationale = bayesComparison['rationale'] as String? ?? '';

    return Card(
      color: const Color(0xff23695a).withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: const Color(0xff23695a).withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 16, color: Color(0xff23695a)),
                const SizedBox(width: 6),
                const Text(
                  'Bayesian AI Risk Estimator',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff23695a)),
                ),
                const Spacer(),
                Text(
                  'Incident Prob: ${incidentP.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff23695a)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Bayesian Score: $bayesScore/100',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: agreement == 'HIGH_AGREEMENT'
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    agreement,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: agreement == 'HIGH_AGREEMENT'
                          ? Colors.green.shade900
                          : Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              rationale,
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentBreakdownCard(RankedRoute ranked) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          'Segment-by-Segment Risk Drilldown (${ranked.route.segments.length} links)',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Inspect individual road hazards along this corridor',
          style: TextStyle(fontSize: 10, color: Colors.black54),
        ),
        children: [
          for (final seg in ranked.route.segments) ...[
            _buildSegmentTile(seg),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  Widget _buildSegmentTile(RoadSegmentData seg) {
    final profile = _scoringEngine.evaluateSegment(seg);
    final riskPercent = (profile.compositeRisk * 100).round();
    Color badgeColor;
    if (profile.isCriticalHazard) {
      badgeColor = Colors.red.shade700;
    } else if (riskPercent >= 50) {
      badgeColor = Colors.orange.shade800;
    } else if (riskPercent >= 25) {
      badgeColor = Colors.amber.shade800;
    } else {
      badgeColor = Colors.green.shade700;
    }

    final distLabel = _formatDistance(seg.distanceMeters);
    final trafficLabel = seg.traffic.congestionLevel.displayName;
    final subtitleText = profile.isCriticalHazard
        ? 'CRITICAL: ${profile.criticalHazardReason}'
        : (profile.explanations.isNotEmpty
            ? '$trafficLabel • $distLabel • ${profile.explanations.first}'
            : '$trafficLabel • $distLabel');

    return ListTile(
      dense: true,
      onTap: () {
        final dist = distLabel;
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: badgeColor.withValues(alpha: 0.15),
                        child: Text('$riskPercent',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: badgeColor,
                                fontSize: 14)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(seg.roadName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(dist,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _detailRow(Icons.traffic, 'Traffic',
                      seg.traffic.congestionLevel.displayName),
                  const SizedBox(height: 10),
                  _detailRow(
                    Icons.water_drop_outlined,
                    'Flood',
                    seg.flood.isHistoricalFloodProne
                        ? 'Known flood-prone area'
                        : 'No recorded flooding',
                  ),
                  const SizedBox(height: 10),
                  _detailRow(
                    Icons.car_crash_outlined,
                    'Accident',
                    seg.accident.isHistoricalBlackspot
                        ? 'Blackspot: ${seg.accident.blackspotName ?? "Recorded"}'
                        : 'No accident blackspot',
                  ),
                  const SizedBox(height: 10),
                  _detailRow(Icons.speed, 'Risk Score', '$riskPercent / 100'),
                  if (profile.explanations.isNotEmpty) ...[
                    const Divider(height: 20),
                    for (final e in profile.explanations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                size: 13, color: Colors.black45),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(e,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54))),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
      leading: CircleAvatar(
        radius: 13,
        backgroundColor: badgeColor.withValues(alpha: 0.15),
        child: Text(
          '$riskPercent',
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.bold, color: badgeColor),
        ),
      ),
      title: Text(seg.roadName,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      subtitle: Text(
        subtitleText,
        style: TextStyle(
          fontSize: 10,
          color: profile.isCriticalHazard
              ? Colors.red.shade800
              : Colors.black54,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          const Icon(Icons.chevron_right, size: 16, color: Colors.black26),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xff23695a)),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  void _showPresetSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Select Bangalore Safety Corridor',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              for (final p in kBangaloreRoutePresets)
                ListTile(
                  leading: const Icon(Icons.route, color: Color(0xff23695a)),
                  title: Text(p.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(p.subtitle, style: const TextStyle(fontSize: 11)),
                  trailing: p.title == _selectedPreset.title
                      ? const Icon(Icons.check, color: Color(0xff23695a))
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedPreset = p;
                    });
                    _fetchAndScoreRoutes();
                  },
                ),
            ],
          ),
        );
      },
    );
  }


}
