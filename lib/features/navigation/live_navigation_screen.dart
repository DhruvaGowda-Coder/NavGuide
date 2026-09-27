import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
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
import '../common/location_share_sheet.dart';
import '../../device/voice/voice_guidance_service.dart';
import '../../device/navigation/background_navigation_service.dart';
import '../../device/safety/speed_and_curve_safety_monitor.dart';

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
  // Voice Guidance Service (Indian English Text-To-Speech)
  final _voiceGuidance = VoiceGuidanceService();

  // Background Lock-Screen Notification & Curve/Speed Safety
  final _bgNavService = BackgroundNavigationService.instance;
  final _speedCurveMonitor = SpeedAndCurveSafetyMonitor();

  GoogleMapController? _mapController;
  final _hazardService = CrowdsourcedHazardService.instance;

  // Real-time navigation state
  late LatLng _currentPosition;
  double _currentHeading = 0.0;
  double _currentSpeedKmh = 0.0;
  late DateTime _journeyStartTime;
  bool _hasArrived = false;

  // Camera & Navigation Follow Controls
  bool _isFollowing = true;
  DateTime _lastCameraAnimTime = DateTime.fromMillisecondsSinceEpoch(0);
  double _currentMapZoom = 19.5;

  // Multi-tier intelligent dynamic icons matching authentic Google Maps navigation proportions
  BitmapDescriptor? _iconNormalStreet;    // 92dp for prominent street navigation (zoom >= 16.0)
  BitmapDescriptor? _iconNormalCity;      // 80dp for district/city corridors (12.5 <= zoom < 16.0)
  BitmapDescriptor? _iconNormalOverview;  // 70dp with beacon halo for bold regional/state overview (zoom < 12.5)

  BitmapDescriptor? _iconBlackoutStreet;
  BitmapDescriptor? _iconBlackoutCity;
  BitmapDescriptor? _iconBlackoutOverview;

  BitmapDescriptor? get _activeVehicleIcon {
    final isBlackout = _isBlackoutEngaged;
    if (_currentMapZoom >= 16.0) {
      return isBlackout ? (_iconBlackoutStreet ?? _iconBlackoutCity) : (_iconNormalStreet ?? _iconNormalCity);
    } else if (_currentMapZoom >= 12.5) {
      return isBlackout ? (_iconBlackoutCity ?? _iconBlackoutStreet) : (_iconNormalCity ?? _iconNormalStreet);
    } else {
      return isBlackout ? (_iconBlackoutOverview ?? _iconBlackoutCity) : (_iconNormalOverview ?? _iconNormalCity);
    }
  }

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

  // Voice maneuver milestone tracking
  int _lastAnnouncedManeuverIndex = -1;
  int _lastAnnouncedMilestoneMeters = -1;

  // Sensors subscription
  StreamSubscription<SensorSample>? _accelSub;
  StreamSubscription<SensorSample>? _gyroSub;
  StreamSubscription<SensorSample>? _magSub;
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

    // Align initial arrow and camera heading to the road direction!
    if (_routePolylinePoints.length >= 2) {
      _currentHeading = _calculateBearing(_routePolylinePoints[0], _routePolylinePoints[1]);
    }

    // Check if device already has a recent GPS fix
    final existingFix = ref.read(locationControllerProvider).fix;
    if (existingFix != null) {
      _currentPosition = LatLng(existingFix.latitude, existingFix.longitude);
      _lastGpsFixTime = DateTime.now();
      if (existingFix.headingDegrees != null && existingFix.headingDegrees! >= 0) {
        _currentHeading = existingFix.headingDegrees!;
      }
    }

    _hazardService.initialize();
    _loadNavigationIcons();
    _initEngines();
    _subscribeSensors();
    _subscribeRealGps();
    _startGpsWatchdog();

    _bgNavService.initialize().then((_) {
      if (mounted) _updateBackgroundNotification();
    });

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        _voiceGuidance.speakNavigationStart(widget.destinationName);
      }
    });
  }

  Future<void> _loadNavigationIcons() async {
    try {
      final normalStreet = await _buildNavigationArrowBitmap(
        isBlackout: false,
        logicalSize: 92.0,
        showHalo: true,
      );
      final normalCity = await _buildNavigationArrowBitmap(
        isBlackout: false,
        logicalSize: 80.0,
        showHalo: true,
      );
      final normalOverview = await _buildNavigationArrowBitmap(
        isBlackout: false,
        logicalSize: 70.0,
        showHalo: true,
      );

      final blackoutStreet = await _buildNavigationArrowBitmap(
        isBlackout: true,
        logicalSize: 92.0,
        showHalo: true,
      );
      final blackoutCity = await _buildNavigationArrowBitmap(
        isBlackout: true,
        logicalSize: 80.0,
        showHalo: true,
      );
      final blackoutOverview = await _buildNavigationArrowBitmap(
        isBlackout: true,
        logicalSize: 70.0,
        showHalo: true,
      );

      if (mounted) {
        setState(() {
          _iconNormalStreet = normalStreet;
          _iconNormalCity = normalCity;
          _iconNormalOverview = normalOverview;

          _iconBlackoutStreet = blackoutStreet;
          _iconBlackoutCity = blackoutCity;
          _iconBlackoutOverview = blackoutOverview;
        });
      }
    } catch (_) {}
  }

  Future<BitmapDescriptor> _buildNavigationArrowBitmap({
    required bool isBlackout,
    required double logicalSize,
    bool showHalo = false,
  }) async {
    const double pixelRatio = 3.0;
    final double physicalSize = logicalSize * pixelRatio;
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    canvas.scale(pixelRatio, pixelRatio);

    final size = logicalSize;

    // 0. Location Pulse Halo for Overview (matches Google Maps location beacon when zoomed out)
    if (showHalo) {
      final haloPaint = Paint()
        ..color = isBlackout
            ? const Color(0x33FF7043)
            : const Color(0x334285F4)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(size / 2, size / 2), size * 0.47, haloPaint);

      final haloBorder = Paint()
        ..color = isBlackout
            ? const Color(0x88FF7043)
            : const Color(0x884285F4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(size / 2, size / 2), size * 0.47, haloBorder);
    }

    // 1. Drop shadow (subtle elevation off road surface)
    final shadowPath = Path()
      ..moveTo(size / 2, size * 0.08)
      ..lineTo(size - 3.5, size - 3.5)
      ..lineTo(size / 2, size * 0.72)
      ..lineTo(3.5, size - 3.5)
      ..close();
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.38)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, (size * 0.06).clamp(2.0, 4.5));
    canvas.drawPath(shadowPath, shadowPaint);

    // 2. Razor-sharp pure white outer rim
    final chevronOutline = Path()
      ..moveTo(size / 2, size * 0.05)
      ..lineTo(size - 4.0, size - 4.5)
      ..lineTo(size / 2, size * 0.70)
      ..lineTo(4.0, size - 4.5)
      ..close();
    final whiteBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size * 0.085).clamp(2.5, 4.5)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(chevronOutline, whiteBorder);

    // 3. Left 3D Wing (Sunlit Face)
    final leftWing = Path()
      ..moveTo(size / 2, size * 0.05)
      ..lineTo(size / 2, size * 0.70)
      ..lineTo(4.0, size - 4.5)
      ..close();
    final leftShader = ui.Gradient.linear(
      Offset(size / 2, size * 0.05),
      Offset(4.0, size - 4.5),
      isBlackout
          ? [const Color(0xffff7043), const Color(0xffe64a19)]
          : [const Color(0xff4285f4), const Color(0xff1a73e8)],
    );
    canvas.drawPath(leftWing, Paint()..shader = leftShader);

    // 4. Right 3D Wing (Shaded 3D Chamfer)
    final rightWing = Path()
      ..moveTo(size / 2, size * 0.05)
      ..lineTo(size - 4.0, size - 4.5)
      ..lineTo(size / 2, size * 0.70)
      ..close();
    final rightShader = ui.Gradient.linear(
      Offset(size / 2, size * 0.05),
      Offset(size - 4.0, size - 4.5),
      isBlackout
          ? [const Color(0xffc62828), const Color(0xff8e0000)]
          : [const Color(0xff1967d2), const Color(0xff1557b0)],
    );
    canvas.drawPath(rightWing, Paint()..shader = rightShader);

    // 5. Center Ridge Specular Glint
    final ridge = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = (size * 0.035).clamp(1.2, 2.2)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size / 2, size * 0.08), Offset(size / 2, size * 0.68), ridge);

    final picture = pictureRecorder.endRecording();
    final img = await picture.toImage(physicalSize.toInt(), physicalSize.toInt());
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(
      pngBytes!.buffer.asUint8List(),
      imagePixelRatio: pixelRatio,
      width: logicalSize,
      height: logicalSize,
    );
  }

  void _startGpsWatchdog() {
    _gpsWatchdogTimer?.cancel();
    _gpsWatchdogTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!mounted || _isDemoSimulationMode) return;
      final elapsed = DateTime.now().difference(_lastGpsFixTime).inMilliseconds / 1000.0;
      if (elapsed >= 10.0 && !_isAutoBlackoutActive) {
        // Automatic GPS Loss detected only after 10 full seconds of signal starvation
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

      final speedKmh = (fix.speedMetersPerSecond ?? 0.0) * 3.6;

      if (!_isBlackoutEngaged) {
        // Determine target heading:
        // If moving at speed (>= 2.0 km/h) and GPS has valid heading, use course heading
        // If moving along polyline, calculate forward road bearing
        // Otherwise smoothly blend with compass
        var targetHeading = _currentHeading;
        if (fix.headingDegrees != null && fix.headingDegrees! >= 0 && speedKmh >= 2.0) {
          targetHeading = fix.headingDegrees!;
        } else if (_routePolylinePoints.isNotEmpty && _targetPolylineIndex < _routePolylinePoints.length) {
          final targetPt = _routePolylinePoints[_targetPolylineIndex];
          final dist = GeodesyUtils.haversineDistanceMeters(
            fix.latitude,
            fix.longitude,
            targetPt.latitude,
            targetPt.longitude,
          );
          if (dist > 4.0 && speedKmh >= 1.0) {
            targetHeading = _calculateBearing(LatLng(fix.latitude, fix.longitude), targetPt);
          }
        }

        setState(() {
          _currentPosition = LatLng(fix.latitude, fix.longitude);
          _currentHeading = _smoothHeading(_currentHeading, targetHeading, factor: 0.35);
          _currentSpeedKmh = speedKmh;
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

      _checkAndSpeakTurnManeuver();
      _speedCurveMonitor.evaluateSafety(
        currentSpeedKmh: _currentSpeedKmh,
        currentPosition: _currentPosition,
        polylinePoints: _routePolylinePoints,
        targetPolylineIndex: _targetPolylineIndex,
        voiceGuidance: _voiceGuidance,
      );
      _updateBackgroundNotification();
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

          // Step Dead Reckoning continuous positioning from inertial sensors even when GPS is dead!
          _stepDeadReckoningPosition();
          _centerMapOnVehicle();
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

    // Physical compass / magnetometer stream for smooth mobile turning
    _magSub = sensorService.watch(SensorKind.magnetometer).listen((sample) {
      if (!mounted) return;
      // Calculate compass orientation from Android magnetometer axes
      final compassAngle = (math.atan2(-sample.x, sample.y) * 180.0 / math.pi + 360.0) % 360.0;

      // When stopped or walking slowly (< 2.2 km/h), smoothly rotate map and arrow to match phone direction
      if (_currentSpeedKmh < 2.2) {
        final smoothed = _smoothHeading(_currentHeading, compassAngle, factor: 0.18);
        if ((smoothed - _currentHeading).abs() > 0.4) {
          setState(() {
            _currentHeading = smoothed;
          });
          _centerMapOnVehicle();
        }
      }
    });
  }

  void _stepDeadReckoningPosition() {
    final ekfLat = _ekfEngine.currentLatitude;
    final ekfLon = _ekfEngine.currentLongitude;
    final aiDelta = GeodesyUtils.metersToDeltaLatLon(_aiCumNorth, _aiCumEast, ekfLat);

    if (!ekfLat.isNaN && !ekfLon.isNaN && ekfLat.abs() > 1.0) {
      setState(() {
        _currentPosition = LatLng(ekfLat + aiDelta.deltaLat, ekfLon + aiDelta.deltaLon);
        _currentHeading = _smoothHeading(_currentHeading, _ekfEngine.currentHeadingDegrees, factor: 0.3);
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
              _currentHeading = _smoothHeading(_currentHeading, bearing, factor: 0.5);
              _currentSpeedKmh = 28.0; // Moving speed engages dynamic zoom in
            });

            _ekfEngine.addFix(GeoFix(
              latitude: nextTarget.latitude,
              longitude: nextTarget.longitude,
              accuracyMeters: 3.5,
              timestamp: DateTime.now(),
              speedMetersPerSecond: 28.0 / 3.6,
              headingDegrees: bearing,
              source: PositionSource.gps,
            ));
          } else {
            _stepDeadReckoningPosition();
          }

          _checkAndSpeakTurnManeuver();
          _speedCurveMonitor.evaluateSafety(
            currentSpeedKmh: _currentSpeedKmh,
            currentPosition: _currentPosition,
            polylinePoints: _routePolylinePoints,
            targetPolylineIndex: _targetPolylineIndex,
            voiceGuidance: _voiceGuidance,
          );
          _updateBackgroundNotification();
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
      _bgNavService.cancel();
      if (!_hasArrived) {
        _voiceGuidance.speakArrival(widget.destinationName);
      }
      setState(() {
        _hasArrived = true;
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(dest, 18.0),
      );
    }
  }

  void _updateBackgroundNotification() {
    if (_hasArrived) {
      _bgNavService.cancel();
      return;
    }

    final remainingDistKm = _calculateRemainingDistanceMeters() / 1000.0;
    final speed = _currentSpeedKmh > 5.0 ? _currentSpeedKmh : 25.0;
    final remainingMin = ((remainingDistKm / speed) * 60).round().clamp(1, 480);
    final etaTime = DateTime.now().add(Duration(minutes: remainingMin));
    final etaClockStr = '${etaTime.hour.toString().padLeft(2, '0')}:${etaTime.minute.toString().padLeft(2, '0')}';

    String maneuverText = 'Follow route';
    if (_targetPolylineIndex < _routePolylinePoints.length - 1) {
      final nextPt = _routePolylinePoints[_targetPolylineIndex];
      final distToTurn = GeodesyUtils.haversineDistanceMeters(
        _currentPosition.latitude,
        _currentPosition.longitude,
        nextPt.latitude,
        nextPt.longitude,
      );
      maneuverText = distToTurn <= 50.0 ? 'Turn approaching' : 'Continue straight';
    }

    _bgNavService.showOrUpdateNavigationNotification(
      maneuverText: maneuverText,
      destinationName: widget.destinationName,
      remainingDistance: '${remainingDistKm.toStringAsFixed(1)} km',
      eta: etaClockStr,
      speedKmh: _currentSpeedKmh.round(),
      isGpsLost: _isBlackoutEngaged,
    );
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

    if (closest != null && minDistance <= 250.0) {
      _voiceGuidance.speakHazard(
        hazardType: closest.hazardType.name,
        distanceMeters: minDistance,
      );
    }

    if (!mounted) return;
    setState(() {
      _upcomingHazard = closest;
      _distanceToUpcomingHazardMeters = minDistance;
    });
  }

  void _checkAndSpeakTurnManeuver() {
    if (_hasArrived || _routePolylinePoints.isEmpty) return;

    // Scan ahead along polyline from current position up to 1200m to find the next real corner/turn
    double accumulatedDistance = 0.0;
    LatLng prevPt = _currentPosition;

    for (int i = _targetPolylineIndex; i < _routePolylinePoints.length - 1; i++) {
      final curPt = _routePolylinePoints[i];
      final nextPt = _routePolylinePoints[i + 1];

      accumulatedDistance += GeodesyUtils.haversineDistanceMeters(
        prevPt.latitude,
        prevPt.longitude,
        curPt.latitude,
        curPt.longitude,
      );

      if (accumulatedDistance > 1200.0) break; // Beyond lookahead horizon

      // Check bearing difference between segment (prev -> cur) and (cur -> next)
      final b1 = _calculateBearing(prevPt, curPt);
      final b2 = _calculateBearing(curPt, nextPt);
      var delta = (b2 - b1 + 360) % 360;
      if (delta > 180) delta -= 360;

      if (delta.abs() >= 32.0) {
        // Found the next upcoming turn junction
        String turnInstruction = 'turn right';
        if (delta < -32.0 && delta >= -145.0) {
          turnInstruction = 'turn left';
        } else if (delta > 32.0 && delta <= 145.0) {
          turnInstruction = 'turn right';
        } else if (delta.abs() > 145.0) {
          turnInstruction = 'make a U-turn';
        }

        // Determine discrete milestone windows (500m, 200m, immediate <= 45m)
        int milestone = -1;
        if (accumulatedDistance <= 45.0) {
          milestone = 0; // Immediate execution
        } else if (accumulatedDistance >= 150.0 && accumulatedDistance <= 250.0) {
          milestone = 200;
        } else if (accumulatedDistance >= 450.0 && accumulatedDistance <= 550.0) {
          milestone = 500;
        }

        // Only speak if this specific turn milestone hasn't been triggered yet
        if (milestone != -1 &&
            (_lastAnnouncedManeuverIndex != i || _lastAnnouncedMilestoneMeters != milestone)) {
          _lastAnnouncedManeuverIndex = i;
          _lastAnnouncedMilestoneMeters = milestone;

          _voiceGuidance.speakManeuver(
            instruction: turnInstruction,
            distanceMeters: accumulatedDistance,
          );
        }
        return; // Only evaluate the first upcoming turn
      }

      prevPt = curPt;
    }
  }

  void _centerMapOnVehicle({bool force = false}) {
    if (_mapController == null || (!_isFollowing && !force)) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastCameraAnimTime).inMilliseconds < 250) {
      return;
    }
    _lastCameraAnimTime = now;

    // Speed-adaptive dynamic zoom like Google Maps:
    // At starting position, stationary, or walking (< 28 km/h):
    // Zoom in close to 19.5 with 52° 3D tilt so user immediately sees their exact real location, lane, and route start!
    // Medium driving speed (28 - 60 km/h): zoom 18.2, tilt 45.0°
    // High-speed highway (>= 60 km/h): zoom 16.8, tilt 36.0°
    final double targetZoom;
    final double targetTilt;
    if (_currentSpeedKmh >= 60.0) {
      targetZoom = 16.8;
      targetTilt = 36.0;
    } else if (_currentSpeedKmh >= 28.0) {
      targetZoom = 18.2;
      targetTilt = 45.0;
    } else {
      targetZoom = 19.5;
      targetTilt = 52.0;
    }

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition,
          zoom: targetZoom,
          tilt: targetTilt,
          bearing: _currentHeading,
        ),
      ),
    );
  }

  double _smoothHeading(double current, double target, {double factor = 0.25}) {
    var diff = (target - current) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;
    return (current + diff * factor) % 360.0;
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
              '⚠️ SIMULATED GPS BLACKOUT ACTIVE!\nNavGuide (Dead Reckoning + EKF + AI Drift) is steering vehicle position.',
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
    _bgNavService.cancel();
    _voiceGuidance.stop();
    _simulatedProgressTimer?.cancel();
    _gpsWatchdogTimer?.cancel();
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();

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

  @override
  void dispose() {
    _bgNavService.cancel();
    _simulatedProgressTimer?.cancel();
    _gpsWatchdogTimer?.cancel();
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    _voiceGuidance.dispose();
    super.dispose();
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
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Interactive 3D Live Navigation Map
          Listener(
            onPointerDown: (event) {
              // User physically touched the map screen to pan/explore
              if (_isFollowing) {
                setState(() {
                  _isFollowing = false;
                });
              }
            },
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentPosition,
                zoom: 19.5,
                tilt: 52.0,
                bearing: _currentHeading,
              ),
              onMapCreated: (ctrl) {
                _mapController = ctrl;
                _centerMapOnVehicle(force: true);
              },
              onCameraMove: (pos) {
                // Intelligently resize 3D navigation chevron matching Google Maps: Street (92dp), City (80dp), Overview (70dp + halo)
                int getTier(double z) {
                  if (z >= 16.0) return 2;
                  if (z >= 12.5) return 1;
                  return 0;
                }
                final oldTier = getTier(_currentMapZoom);
                final newTier = getTier(pos.zoom);
                _currentMapZoom = pos.zoom;
                if (oldTier != newTier && mounted) {
                  setState(() {});
                }
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
                // Current vehicle marker: Custom 3D directional chevron pointing along road
                Marker(
                  markerId: const MarkerId('vehicle_marker'),
                  position: _currentPosition,
                  rotation: _currentHeading,
                  anchor: const Offset(0.5, 0.5),
                  flat: true,
                  zIndexInt: 999,
                  icon: _activeVehicleIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        _isBlackoutEngaged ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure,
                      ),
                ),
                // Destination Reach Point Marker (changes to celebratory green flag/pin on reach)
                if (_routePolylinePoints.isNotEmpty)
                  Marker(
                    markerId: const MarkerId('destination_reach_marker'),
                    position: _routePolylinePoints.last,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      _hasArrived ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
                    ),
                    infoWindow: InfoWindow(
                      title: _hasArrived
                          ? '🏁 Destination Reached!'
                          : 'End: ${widget.destinationName}',
                      snippet: _hasArrived
                          ? 'Safely arrived at destination point'
                          : 'Target arrival point',
                    ),
                    zIndexInt: 998,
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
              circles: {
                if (_routePolylinePoints.isNotEmpty)
                  Circle(
                    circleId: const CircleId('destination_reach_zone'),
                    center: _routePolylinePoints.last,
                    radius: _hasArrived ? 55.0 : 35.0,
                    strokeWidth: 2,
                    strokeColor: _hasArrived
                        ? const Color(0xff10b981)
                        : const Color(0xffe11d48),
                    fillColor: _hasArrived
                        ? const Color(0x3310b981)
                        : const Color(0x22e11d48),
                  ),
              },
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: true,
            ),
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

          // 6. Floating Recenter Button (Appears only when user manually pans away)
          if (!_isFollowing)
            Positioned(
              right: 16,
              bottom: 130 + bottomInset,
              child: FloatingActionButton.extended(
                heroTag: 'recenter_btn',
                backgroundColor: const Color(0xff23695a),
                foregroundColor: Colors.white,
                onPressed: () {
                  setState(() {
                    _isFollowing = true;
                  });
                  _centerMapOnVehicle(force: true);
                },
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Re-center', style: TextStyle(fontWeight: FontWeight.bold)),
                elevation: 6,
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

  double _calculateRemainingDistanceMeters() {
    if (_routePolylinePoints.isEmpty || _hasArrived) return 0.0;
    if (_targetPolylineIndex >= _routePolylinePoints.length) return 0.0;

    double totalM = 0.0;
    final nextPt = _routePolylinePoints[_targetPolylineIndex.clamp(0, _routePolylinePoints.length - 1)];
    totalM += GeodesyUtils.haversineDistanceMeters(
      _currentPosition.latitude,
      _currentPosition.longitude,
      nextPt.latitude,
      nextPt.longitude,
    );

    for (int i = _targetPolylineIndex; i < _routePolylinePoints.length - 1; i++) {
      totalM += GeodesyUtils.haversineDistanceMeters(
        _routePolylinePoints[i].latitude,
        _routePolylinePoints[i].longitude,
        _routePolylinePoints[i + 1].latitude,
        _routePolylinePoints[i + 1].longitude,
      );
    }
    return totalM;
  }

  Widget _buildTopManeuverBanner() {
    final topPadding = MediaQuery.of(context).padding.top;
    final remainingDistM = _calculateRemainingDistanceMeters();
    final remainingDistKm = remainingDistM > 0
        ? remainingDistM / 1000.0
        : widget.selectedRoute.route.distanceMeters / 1000.0;

    final baselineSpeed = (widget.selectedRoute.route.distanceMeters > 0 &&
            widget.selectedRoute.route.trafficDurationSeconds > 0)
        ? (widget.selectedRoute.route.distanceMeters / 1000.0) /
            (widget.selectedRoute.route.trafficDurationSeconds / 3600.0)
        : 28.0;

    final effectiveSpeed = _currentSpeedKmh >= 15.0
        ? (_currentSpeedKmh * 0.7) + (baselineSpeed * 0.3)
        : baselineSpeed.clamp(15.0, 65.0);

    final remainingMin = _hasArrived
        ? 0
        : math.max(1, ((remainingDistKm / effectiveSpeed) * 60.0).round());

    final etaTime = DateTime.now().add(Duration(minutes: remainingMin));
    final hour = etaTime.hour % 12 == 0 ? 12 : etaTime.hour % 12;
    final minuteStr = etaTime.minute.toString().padLeft(2, '0');
    final amPm = etaTime.hour >= 12 ? 'PM' : 'AM';
    final etaClockStr = '$hour:$minuteStr $amPm';

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
                      widget.destinationName.trim().isNotEmpty && widget.destinationName != 'Destination Point'
                          ? widget.destinationName
                          : (widget.selectedRoute.route.summary.isNotEmpty
                              ? widget.selectedRoute.route.summary
                              : 'Destination'),
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
                icon: Icon(
                  _voiceGuidance.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: _voiceGuidance.isMuted ? Colors.white38 : const Color(0xffa7f3d0),
                ),
                tooltip: _voiceGuidance.isMuted ? 'Unmute Voice Guidance' : 'Mute Voice Guidance',
                onPressed: () {
                  setState(() {
                    _voiceGuidance.toggleMute();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _voiceGuidance.isMuted
                            ? '🔇 Voice Guidance Muted'
                            : '🔊 Voice Guidance Enabled (Indian English)',
                      ),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.share_location_rounded, color: Colors.white70),
                tooltip: 'Share Trip Progress',
                onPressed: () {
                  LocationShareSheet.shareDirectly(
                    latitude: _currentPosition.latitude,
                    longitude: _currentPosition.longitude,
                    destinationName: widget.destinationName,
                    tripEta: '$remainingMin min ($etaClockStr)',
                    remainingDistance: '${remainingDistKm.toStringAsFixed(1)} km',
                    speedKmh: _currentSpeedKmh.toInt(),
                  );
                },
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
                _hasArrived ? 'Arrived at destination' : 'ETA: $remainingMin min ($etaClockStr) · ${remainingDistKm.toStringAsFixed(1)} km',
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
    final remainingDistM = _calculateRemainingDistanceMeters();
    final remainingKm = remainingDistM > 0
        ? remainingDistM / 1000.0
        : widget.selectedRoute.route.distanceMeters / 1000.0;

    final baselineSpeed = (widget.selectedRoute.route.distanceMeters > 0 &&
            widget.selectedRoute.route.trafficDurationSeconds > 0)
        ? (widget.selectedRoute.route.distanceMeters / 1000.0) /
            (widget.selectedRoute.route.trafficDurationSeconds / 3600.0)
        : 28.0;

    final effectiveSpeed = _currentSpeedKmh >= 15.0
        ? (_currentSpeedKmh * 0.7) + (baselineSpeed * 0.3)
        : baselineSpeed.clamp(15.0, 65.0);

    final remainingMins = _hasArrived
        ? 0
        : math.max(1, ((remainingKm / effectiveSpeed) * 60.0).round());

    final etaTime = DateTime.now().add(Duration(minutes: remainingMins));
    final hour = etaTime.hour % 12 == 0 ? 12 : etaTime.hour % 12;
    final minuteStr = etaTime.minute.toString().padLeft(2, '0');
    final amPm = etaTime.hour >= 12 ? 'PM' : 'AM';
    final etaClockStr = '$hour:$minuteStr $amPm';

    final String timeRemainingStr;
    if (_hasArrived) {
      timeRemainingStr = 'Arrived';
    } else if (remainingMins >= 60) {
      final h = remainingMins ~/ 60;
      final m = remainingMins % 60;
      timeRemainingStr = '${h}h ${m}m';
    } else {
      timeRemainingStr = '$remainingMins min';
    }

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 16, 12 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minimal drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Google Maps Style ETA details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Big Green Remaining Duration
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Text(
                            timeRemainingStr,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Color(0xff1b873f), // Signature Google Maps Green
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (_currentSpeedKmh >= 15.0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.speed_rounded, size: 12, color: Colors.green.shade700),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${_currentSpeedKmh.toStringAsFixed(0)} km/h',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Distance + ETA Clock Time + Destination
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Text(
                            '${remainingKm.toStringAsFixed(1)} km',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                          ),
                          Icon(Icons.schedule_rounded, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 3),
                          Text(
                            etaClockStr,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Action Buttons: Share Trip + Simulation Play/Pause + Exit
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share_location_rounded, color: Color(0xff23695a), size: 24),
                    tooltip: 'Share Trip Progress',
                    onPressed: () {
                      LocationShareSheet.shareDirectly(
                        latitude: _currentPosition.latitude,
                        longitude: _currentPosition.longitude,
                        destinationName: widget.destinationName,
                        tripEta: '$remainingMins min ($etaClockStr)',
                        remainingDistance: '${remainingKm.toStringAsFixed(1)} km',
                        speedKmh: _currentSpeedKmh.toInt(),
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      _isDemoSimulationMode ? Icons.pause_circle_filled_rounded : Icons.play_circle_outline_rounded,
                      color: _isDemoSimulationMode ? const Color(0xff23695a) : Colors.grey.shade500,
                      size: 26,
                    ),
                    tooltip: _isDemoSimulationMode ? 'Pause Simulation' : 'Start Simulation',
                    onPressed: () => _toggleSimulationMode(!_isDemoSimulationMode),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _hasArrived ? const Color(0xff2e7d32) : const Color(0xffb71c1c),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _endJourney,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _hasArrived ? Icons.check_circle_outline_rounded : Icons.close_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _hasArrived ? 'Finish' : 'Exit',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
