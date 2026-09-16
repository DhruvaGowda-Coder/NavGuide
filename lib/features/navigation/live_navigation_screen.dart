import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/providers.dart';
import '../../device/crowdsourcing/crowdsourced_hazard_service.dart';
import '../../device/dead_reckoning/dead_reckoning_engine.dart';
import '../../device/fusion/ai_drift_predictor.dart';
import '../../device/fusion/ekf_sensor_fusion_engine.dart';
import '../../domain/crowdsourced_hazard_models.dart';
import '../../domain/safety_scoring_models.dart';
import '../../domain/telemetry.dart';
import '../crowdsourcing/hazard_report_screen.dart';
import '../journey/journey_completion_report_screen.dart';
import '../location/location_controller.dart';

/// Live Turn-by-Turn Navigation Screen with Real-Time NavGuardian AI Dead Reckoning,
/// simulated blackout presentation mode, and live crowdsourced hazard alerts.
class LiveNavigationScreen extends ConsumerStatefulWidget {
  const LiveNavigationScreen({
    super.key,
    required this.selectedRoute,
    required this.destinationName,
  });

  final RankedRoute selectedRoute;
  final String destinationName;

  @override
  ConsumerState<LiveNavigationScreen> createState() => _LiveNavigationScreenState();
}

class _LiveNavigationScreenState extends ConsumerState<LiveNavigationScreen> {
  GoogleMapController? _mapController;
  final _hazardService = CrowdsourcedHazardService.instance;

  // Real-time navigation state
  late LatLng _currentPosition;
  double _currentHeading = 0.0;
  double _currentSpeedKmh = 0.0;
  late DateTime _journeyStartTime;
  bool _hasArrived = false;

  // Navigation mode: true for desk simulation demo, false for real physical device tracking
  bool _isDemoSimulationMode = false;

  // Blackout simulation state for presentations
  bool _isBlackoutSimulated = false;
  bool _isAutoBlackoutActive = false;
  DateTime? _blackoutStartTime;
  DateTime _lastGpsFixTime = DateTime.now();
  double _accumulatedBlackoutSeconds = 0.0;
  Timer? _gpsWatchdogTimer;

  bool get _isBlackoutEngaged => _isBlackoutSimulated || _isAutoBlackoutActive;

  // On-device Dead Reckoning & AI Engines
  final _ekfEngine = EkfSensorFusionEngine();
  final _drEngine = DeadReckoningEngine();
  final _aiPredictor = const AiDriftPredictor();
  double _aiCumEast = 0.0;
  double _aiCumNorth = 0.0;
  double _lastAx = 0.0, _lastAy = 0.0, _lastAz = 9.80665;
  double _lastGx = 0.0, _lastGy = 0.0, _lastGz = 0.0;
  double _prevAccNorm = 9.80665;
  int _prevAiStepMicros = 0;

  // Active hazard proximity alert
  CrowdsourcedHazardReport? _upcomingHazard;
  double _distanceToUpcomingHazardMeters = 0.0;
  final Set<String> _dismissedHazardIds = {};

  // Sensors subscription
  StreamSubscription<SensorSample>? _accelSub;
  StreamSubscription<SensorSample>? _gyroSub;
  StreamSubscription<GeoFix?>? _gpsSub;
  Timer? _simulatedProgressTimer;

  // Route points
  late List<LatLng> _routePolylinePoints;
  int _targetPolylineIndex = 0;
  List<LatLng> get _activeDisplayPolyline {
    if (_routePolylinePoints.isEmpty) return [_currentPosition];
    final startIdx = _targetPolylineIndex.clamp(0, _routePolylinePoints.length - 1);
    final remaining = _routePolylinePoints.sublist(startIdx);
    return [_currentPosition, ...remaining];
  }


  @override
  void initState() {
    super.initState();
    _journeyStartTime = DateTime.now();

    // Extract polyline points directly from the selected route
    final rawPoints = widget.selectedRoute.route.fullPolyline;
    if (rawPoints.isNotEmpty) {
      _routePolylinePoints = rawPoints.map((p) => LatLng(p.lat, p.lon)).toList();
      _currentPosition = _routePolylinePoints.first;
    } else {
      _routePolylinePoints = [
        LatLng(widget.selectedRoute.route.originLat, widget.selectedRoute.route.originLon),
        LatLng(widget.selectedRoute.route.destinationLat, widget.selectedRoute.route.destinationLon),
      ];
      _currentPosition = _routePolylinePoints.first;
    }

    _hazardService.initialize();
    _initEngines();
    _subscribeSensors();
    _subscribeRealGps();
    _startGpsWatchdog();
  }

  void _startGpsWatchdog() {
    _gpsWatchdogTimer?.cancel();
    _gpsWatchdogTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!mounted || _isDemoSimulationMode) return;
      final elapsed = DateTime.now().difference(_lastGpsFixTime).inMilliseconds / 1000.0;
      if (elapsed >= 3.5 && !_isAutoBlackoutActive) {
        // Automatic GPS Loss detected!
        setState(() {
          _isAutoBlackoutActive = true;
          _blackoutStartTime ??= DateTime.now();
        });
      }
    });
  }

  void _initEngines() {
    final initialFix = GeoFix(
      latitude: _currentPosition.latitude,
      longitude: _currentPosition.longitude,
      accuracyMeters: 4.0,
      timestamp: DateTime.now(),
      speedMetersPerSecond: 0.0,
      headingDegrees: _currentHeading,
      source: PositionSource.gps,
    );
    _ekfEngine.initializeWithGps(initialFix, monotonicMicros: 0);
    _drEngine.initializeWithGps(initialFix, monotonicMicros: 0);
  }

  void _subscribeRealGps() {
    final locationController = ref.read(locationControllerProvider.notifier);
    locationController.start();

    final locationService = ref.read(locationServiceProvider);
    _gpsSub = locationService.watch().listen((fix) {
      if (!mounted) return;
      if (_isDemoSimulationMode) return; // Simulation mode drives progress instead

      _lastGpsFixTime = DateTime.now();
      if (_isAutoBlackoutActive) {
        setState(() {
          _isAutoBlackoutActive = false;
        });
      }

      if (!_isBlackoutEngaged) {
        setState(() {
          _currentPosition = LatLng(fix.latitude, fix.longitude);
          if (fix.headingDegrees != null && fix.headingDegrees! >= 0) {
            _currentHeading = _smoothHeading(_currentHeading, fix.headingDegrees!);
          }
          _currentSpeedKmh = (fix.speedMetersPerSecond ?? 0.0) * 3.6;
        });

        _ekfEngine.addFix(fix);
        _drEngine.addFix(fix);

        // Advance route progress along polyline as user moves
        if (_routePolylinePoints.isNotEmpty && _targetPolylineIndex < _routePolylinePoints.length - 1) {
          final nextPt = _routePolylinePoints[_targetPolylineIndex];
          final distToNext = GeodesyUtils.haversineDistanceMeters(
            fix.latitude,
            fix.longitude,
            nextPt.latitude,
            nextPt.longitude,
          );
          if (distToNext < 25.0) {
            _targetPolylineIndex++;
          }
        }
      } else {
        // Dead Reckoning fallback when blackout simulated
        _stepDeadReckoningPosition();
      }

      _checkUpcomingHazards();
      _checkArrival();
      _centerMapOnVehicle();
    });
  }

  void _subscribeSensors() {
    final sensorService = ref.read(sensorServiceProvider);
    _accelSub = sensorService.watch(SensorKind.accelerometer).listen((sample) {
      _drEngine.addSensor(sample);
      _ekfEngine.addSensor(sample);
      _lastAx = sample.x;
      _lastAy = sample.y;
      _lastAz = sample.z;

      if (_isBlackoutEngaged) {
        final dtSinceAi = _prevAiStepMicros > 0
            ? (sample.monotonicMicroseconds - _prevAiStepMicros) / 1000000.0
            : 0.1;
        if (_prevAiStepMicros == 0 || dtSinceAi >= 0.09) {
          _prevAiStepMicros = sample.monotonicMicroseconds;
          final accNorm = math.sqrt(_lastAx * _lastAx + _lastAy * _lastAy + _lastAz * _lastAz);
          final jerk = dtSinceAi > 0.0001 ? ((accNorm - _prevAccNorm).abs() / dtSinceAi) : 0.0;
          _prevAccNorm = accNorm;
          final gyroNorm = math.sqrt(_lastGx * _lastGx + _lastGy * _lastGy + _lastGz * _lastGz);

          final corr = _aiPredictor.predictCorrection(
            ax: _lastAx,
            ay: _lastAy,
            az: _lastAz,
            accNorm: accNorm,
            jerk: jerk,
            gx: _lastGx,
            gy: _lastGy,
            gz: _lastGz,
            gyroNorm: gyroNorm,
            ekfVx: _ekfEngine.velocityEastMps,
            ekfVy: _ekfEngine.velocityNorthMps,
            ekfSpeed: _ekfEngine.currentSpeedMps,
            ekfHeadingRad: _ekfEngine.headingRad,
            isStationary: _ekfEngine.isStationary,
          );

          if (!_ekfEngine.isStationary) {
            _aiCumEast += corr.deltaEastMeters;
            _aiCumNorth += corr.deltaNorthMeters;
          }
        }
      }
    });

    _gyroSub = sensorService.watch(SensorKind.gyroscope).listen((sample) {
      _drEngine.addSensor(sample);
      _ekfEngine.addSensor(sample);
      _lastGx = sample.x;
      _lastGy = sample.y;
      _lastGz = sample.z;
    });
  }

  void _stepDeadReckoningPosition() {
    final ekfLat = _ekfEngine.currentLatitude;
    final ekfLon = _ekfEngine.currentLongitude;
    final aiDelta = GeodesyUtils.metersToDeltaLatLon(_aiCumNorth, _aiCumEast, ekfLat);

    if (!ekfLat.isNaN && !ekfLon.isNaN && ekfLat.abs() > 1.0) {
      setState(() {
        _currentPosition = LatLng(ekfLat + aiDelta.deltaLat, ekfLon + aiDelta.deltaLon);
        _currentHeading = _ekfEngine.currentHeadingDegrees;
        _currentSpeedKmh = _ekfEngine.currentSpeedMps * 3.6;
      });
    }
  }

  void _toggleSimulationMode(bool enableSim) {
    setState(() {
      _isDemoSimulationMode = enableSim;
    });

    _simulatedProgressTimer?.cancel();
    _gpsWatchdogTimer?.cancel();
    if (enableSim) {
      _simulatedProgressTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
        if (!mounted) return;

        if (_targetPolylineIndex < _routePolylinePoints.length - 1) {
          _targetPolylineIndex++;
          final nextTarget = _routePolylinePoints[_targetPolylineIndex];

          if (!_isBlackoutEngaged) {
            final bearing = _calculateBearing(_currentPosition, nextTarget);
            setState(() {
              _currentPosition = nextTarget;
              _currentHeading = bearing;
              _currentSpeedKmh = 35.0;
            });

            _ekfEngine.addFix(GeoFix(
              latitude: nextTarget.latitude,
              longitude: nextTarget.longitude,
              accuracyMeters: 3.5,
              timestamp: DateTime.now(),
              speedMetersPerSecond: 35.0 / 3.6,
              headingDegrees: bearing,
              source: PositionSource.gps,
            ));
          } else {
            _stepDeadReckoningPosition();
          }

          _checkUpcomingHazards();
          _checkArrival();
          _centerMapOnVehicle();
        } else {
          _checkArrival();
        }
      });
    }
  }

  void _checkArrival() {
    if (_routePolylinePoints.isEmpty || _hasArrived) return;
    final dest = _routePolylinePoints.last;
    final distM = GeodesyUtils.haversineDistanceMeters(
      _currentPosition.latitude,
      _currentPosition.longitude,
      dest.latitude,
      dest.longitude,
    );

    if (distM <= 50.0 || _targetPolylineIndex >= _routePolylinePoints.length - 1) {
      setState(() {
        _hasArrived = true;
      });
    }
  }

  void _checkUpcomingHazards() {
    final nearby = _hazardService.getNearbyHazards(
      lat: _currentPosition.latitude,
      lon: _currentPosition.longitude,
      radiusMeters: 450,
    );

    CrowdsourcedHazardReport? closest;
    var minDistance = double.infinity;

    for (final h in nearby) {
      if (_dismissedHazardIds.contains(h.id)) continue;
      final dist = GeodesyUtils.haversineDistanceMeters(
        _currentPosition.latitude,
        _currentPosition.longitude,
        h.latitude,
        h.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        closest = h;
      }
    }

    if (!mounted) return;
    setState(() {
      _upcomingHazard = closest;
      _distanceToUpcomingHazardMeters = minDistance;
    });
  }

  void _centerMapOnVehicle() {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition,
          zoom: 17.5,
          tilt: 45.0,
          bearing: _currentHeading,
        ),
      ),
    );
  }

  double _smoothHeading(double current, double target) {
    var diff = (target - current) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;
    return (current + diff * 0.35) % 360.0;
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final startLat = start.latitude * (math.pi / 180.0);
    final startLon = start.longitude * (math.pi / 180.0);
    final endLat = end.latitude * (math.pi / 180.0);
    final endLon = end.longitude * (math.pi / 180.0);

    final dLon = endLon - startLon;
    final y = math.sin(dLon) * math.cos(endLat);
    final x = math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLon);

    final rad = math.atan2(y, x);
    return (rad * (180.0 / math.pi) + 360.0) % 360.0;
  }

  void _toggleBlackoutSimulation(bool value) {
    setState(() {
      _isBlackoutSimulated = value;
      if (value) {
        _blackoutStartTime = DateTime.now();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xffd32f2f),
            duration: Duration(seconds: 3),
            content: Text(
              '⚠️ SIMULATED GPS BLACKOUT ACTIVE!\nNavGuardian AI (Dead Reckoning + EKF + AI Drift) is steering vehicle position.',
            ),
          ),
        );
      } else {
        if (_blackoutStartTime != null) {
          _accumulatedBlackoutSeconds +=
              DateTime.now().difference(_blackoutStartTime!).inMilliseconds / 1000.0;
          _blackoutStartTime = null;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xff2e7d32),
            duration: Duration(seconds: 2),
            content: Text('🟢 GPS SIGNAL RESTORED · Returning to Live GPS Tracking'),
          ),
        );
      }
    });
  }

  void _endJourney() {
    _simulatedProgressTimer?.cancel();
    _gpsWatchdogTimer?.cancel();
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();

    final totalDurationSeconds = DateTime.now().difference(_journeyStartTime).inSeconds.toDouble();
    var blackoutSecs = _accumulatedBlackoutSeconds;
    if (_blackoutStartTime != null) {
      blackoutSecs += DateTime.now().difference(_blackoutStartTime!).inSeconds.toDouble();
    }

    final totalDistanceKm = widget.selectedRoute.route.distanceMeters / 1000.0;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => JourneyCompletionReportScreen(
          selectedRoute: widget.selectedRoute,
          destinationName: widget.destinationName,
          totalDurationSeconds: totalDurationSeconds,
          blackoutDurationSeconds: blackoutSecs,
          totalDistanceKm: totalDistanceKm,
          averageSpeedKmh: _currentSpeedKmh > 0 ? _currentSpeedKmh : 30.0,
          ekfDriftEstimateMeters: _ekfEngine.positionStdDevMeters,
          aiDriftCorrectionMeters: math.sqrt(_aiCumEast * _aiCumEast + _aiCumNorth * _aiCumNorth),
        ),
      ),
    );
  }

  void _openQuickReportModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => HazardReportScreen(
        initialLatitude: _currentPosition.latitude,
        initialLongitude: _currentPosition.longitude,
        roadName: widget.selectedRoute.route.summary.isNotEmpty
            ? widget.selectedRoute.route.summary
            : 'Active Route',
      ),
    );
  }

  @override
  void dispose() {
    _simulatedProgressTimer?.cancel();
    _gpsWatchdogTimer?.cancel();
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Interactive 3D Live Navigation Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 17.5,
              tilt: 45.0,
              bearing: _currentHeading,
            ),
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              _centerMapOnVehicle();
            },
            polylines: {
              Polyline(
                polylineId: const PolylineId('nav_route'),
                points: _activeDisplayPolyline,
                color: const Color(0xff23695a),
                width: 7,
              ),
            },
            markers: {
              // Current vehicle marker
              Marker(
                markerId: const MarkerId('vehicle_marker'),
                position: _currentPosition,
                rotation: _currentHeading,
                anchor: const Offset(0.5, 0.5),
                flat: true,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  _isBlackoutEngaged ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure,
                ),
              ),
              // Upcoming hazard markers along corridor
              for (final h in _hazardService.getNearbyHazards(
                lat: _currentPosition.latitude,
                lon: _currentPosition.longitude,
                radiusMeters: 1500,
              ))
                Marker(
                  markerId: MarkerId('nav_h_${h.id}'),
                  position: LatLng(h.latitude, h.longitude),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    h.hazardType == HazardType.flood || h.hazardType == HazardType.roadBlocked
                        ? BitmapDescriptor.hueRed
                        : BitmapDescriptor.hueYellow,
                  ),
                  infoWindow: InfoWindow(
                    title: '${h.hazardType.displayName} (${h.severity})',
                    snippet: h.description,
                  ),
                ),
            },
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
          ),

          // 2. Top Turn-by-Turn Instruction Banner
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopManeuverBanner(),
          ),

          // 3. Dynamic Live Status Badge (GPS / Dead Reckoning Mode)
          Positioned(
            top: 145,
            left: 16,
            right: 16,
            child: GestureDetector(onTap: () => _toggleBlackoutSimulation(!_isBlackoutSimulated), child: _buildDynamicStatusBadge()),
          ),

          // 4. Upcoming Hazard Alert Card (Proximity Pop-up)
          if (_upcomingHazard != null)
            Positioned(
              bottom: 155 + bottomInset,
              left: 16,
              right: 16,
              child: _buildUpcomingHazardCard(),
            ),

          // 5. Arrival Banner (When user reaches destination)
          if (_hasArrived)
            Positioned(
              bottom: 145 + bottomInset,
              left: 16,
              right: 16,
              child: Card(
                elevation: 6,
                color: const Color(0xffe8f5e9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xff2e7d32), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xff2e7d32), size: 36),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Destination Reached!',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff1b5e20)),
                            ),
                            Text(
                              'Tap "End Journey" below to view complete safety summary.',
                              style: TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xff2e7d32)),
                        onPressed: _endJourney,
                        child: const Text('Report'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 6. Floating Recenter Button
          Positioned(
            right: 16,
            bottom: 130 + bottomInset,
            child: FloatingActionButton.small(
              heroTag: 'recenter_btn',
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xff23695a),
              onPressed: _centerMapOnVehicle,
              tooltip: 'Center on Vehicle',
              elevation: 4,
              child: const Icon(Icons.my_location),
            ),
          ),

          // 7. Bottom Navigation Bar & Mode Controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomNavigationBar(bottomInset),
          ),
        ],
      ),
    );
  }

  Widget _buildTopManeuverBanner() {
    final topPadding = MediaQuery.of(context).padding.top;
    final remainingDistKm = widget.selectedRoute.route.distanceMeters / 1000.0;
    final remainingMin = (widget.selectedRoute.route.trafficDurationSeconds / 60.0).toStringAsFixed(0);

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0xff1b4332),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasArrived
                          ? 'Arrived at Destination'
                          : (_isDemoSimulationMode ? 'Demo Simulation Active' : 'Live Turn-by-Turn Navigation'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xffa7f3d0),
                      ),
                    ),
                    Text(
                      widget.selectedRoute.route.summary.isNotEmpty
                          ? widget.selectedRoute.route.summary
                          : widget.destinationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.warning_amber_rounded, color: Colors.white70),
                tooltip: 'Report Road Hazard',
                onPressed: _openQuickReportModal,
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Exit Navigation',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Exit Navigation?'),
                      content: const Text('Do you want to stop active navigation and return to search?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Resume')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.pop(context);
                          },
                          child: const Text('Exit'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ETA: $remainingMin min (${remainingDistKm.toStringAsFixed(1)} km)',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'Safety Score: ${widget.selectedRoute.safetyScore.overallScore}/100',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicStatusBadge() {
    if (!_isBlackoutEngaged) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xff1b5e20).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isDemoSimulationMode ? 'DEMO SIMULATION ACTIVE' : 'LIVE GPS TRACKING',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '${_currentSpeedKmh.toStringAsFixed(0)} km/h',
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xffb71c1c).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amberAccent, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.amberAccent, size: 18),
            const SizedBox(width: 6),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'GPS SIGNAL LOST · NAVGUARDIAN AI ACTIVE',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '9-Axis IMU Fusion + EKF + AI Ridge Regressor Steering',
                    style: TextStyle(color: Colors.white70, fontSize: 9.5),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_currentSpeedKmh.toStringAsFixed(0)} km/h',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildUpcomingHazardCard() {
    final hazard = _upcomingHazard!;
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.orange, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_rounded, color: Colors.orange, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${hazard.hazardType.displayName} in ${_distanceToUpcomingHazardMeters.toInt()}m',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${(hazard.reliabilityScore * 100).toInt()}% Verified',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hazard.description,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.thumb_down_outlined, size: 14, color: Colors.red),
                  label: const Text('Not There', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _hazardService.rejectHazard(hazard.id);
                    setState(() {
                      _dismissedHazardIds.add(hazard.id);
                      _upcomingHazard = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Feedback recorded: Hazard marked absent.')),
                    );
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff23695a),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.thumb_up_alt_rounded, size: 14),
                  label: const Text('Confirm (+1)', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _hazardService.confirmHazard(hazard.id);
                    setState(() {
                      _dismissedHazardIds.add(hazard.id);
                      _upcomingHazard = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Thank you! Hazard confirmed for community.')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar(double bottomInset) {
    return Container(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 14 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Destination Info & End Journey Button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.destinationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${(widget.selectedRoute.route.distanceMeters / 1000.0).toStringAsFixed(1)} km · ${_isDemoSimulationMode ? "Demo Walkthrough" : "Live Device GPS"}',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: Icon(
                  _isDemoSimulationMode ? Icons.play_circle_fill : Icons.play_circle_outline,
                  color: _isDemoSimulationMode ? const Color(0xff23695a) : Colors.grey.shade600,
                  size: 26,
                ),
                tooltip: _isDemoSimulationMode ? 'Pause Desk Demo' : 'Start Desk Demo Simulation',
                onPressed: () => _toggleSimulationMode(!_isDemoSimulationMode),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _hasArrived ? const Color(0xff2e7d32) : const Color(0xffb71c1c),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(_hasArrived ? Icons.check_circle : Icons.flag_rounded, color: Colors.white, size: 16),
                label: Text(
                  _hasArrived ? 'Finish' : 'End Journey',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                ),
                onPressed: _endJourney,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
