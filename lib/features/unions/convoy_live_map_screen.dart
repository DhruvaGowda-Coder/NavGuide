import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/union_models.dart';
import '../../device/unions/union_service.dart';
import '../../device/unions/convoy_alarm_service.dart';

class ConvoyLiveMapScreen extends StatefulWidget {
  final String unionId;

  const ConvoyLiveMapScreen({super.key, required this.unionId});

  @override
  State<ConvoyLiveMapScreen> createState() => _ConvoyLiveMapScreenState();
}

class _ConvoyLiveMapScreenState extends State<ConvoyLiveMapScreen> {
  final UnionService _service = UnionService();
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _posStream;
  Timer? _remoteSyncTimer;
  bool _isSharingLocation = false;
  bool _bottomSheetExpanded = false;
  LatLng? _myCurrentPosition;
  double _myCurrentSpeed = 0.0;
  double _myCurrentHeading = 0.0;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);

    // If there is an active emergency in my convoy, ensure alarm is playing (if not silenced)
    final union = _union;
    final alert = union?.latestEmergency;
    if (union != null &&
        union.hasActiveEmergency &&
        _service.isMyConvoy(union) &&
        (alert == null || !_service.isAlertSilenced(alert.id))) {
      ConvoyAlarmService().startAlarm();
    }

    // Auto-start live GPS tracking immediately so real-time location is shown
    _autoStartLiveTracking();

    // Auto-sync real-time convoy status from Firebase every 4 seconds
    _remoteSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _service.syncWithFirebase();
    });
  }

  Future<void> _autoStartLiveTracking() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        return;
      }

      // Fetch initial position immediately so marker appears without waiting for movement
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 4));
        _handleNewPosition(pos);
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) _handleNewPosition(last);
      }

      // Start continuous high-frequency stream for live moving riders
      _posStream?.cancel();
      _posStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 3,
            ),
          ).listen((pos) {
            _handleNewPosition(pos);
          });

      if (mounted) {
        setState(() => _isSharingLocation = true);
      }
    } catch (_) {}
  }

  void _handleNewPosition(Position pos) {
    _myCurrentPosition = LatLng(pos.latitude, pos.longitude);
    _myCurrentSpeed = (pos.speed * 3.6).clamp(0, 150);
    _myCurrentHeading = pos.heading;

    final union = _union;
    if (union != null) {
      final myName = _service.isOwner(union) ? union.hostName : 'My Rider';
      final myMobile = _service.myRiderMobile ?? _service.myHostMobile ?? '';
      final rider = ConvoyLiveRider(
        id: myMobile.isNotEmpty ? myMobile : 'me_${union.id}',
        name: myName,
        mobile: myMobile,
        vehicle: _service.isOwner(union) ? 'Convoy Lead 👑' : 'Rider Bike',
        category: union.category,
        latitude: pos.latitude,
        longitude: pos.longitude,
        speedKmph: _myCurrentSpeed,
        heading: pos.heading,
        isHost: _service.isOwner(union),
        lastUpdated: DateTime.now(),
      );
      _service.updateRiderLocation(union.id, rider);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _remoteSyncTimer?.cancel();
    _service.removeListener(_onServiceUpdate);
    _posStream?.cancel();
    ConvoyAlarmService().stopAlarm();
    super.dispose();
  }

  void _onServiceUpdate() {
    final union = _union;
    if (union != null) {
      final alert = union.latestEmergency;
      final shouldAlarm = union.hasActiveEmergency &&
          _service.isMyConvoy(union) &&
          (alert == null || !_service.isAlertSilenced(alert.id));
      if (shouldAlarm && !ConvoyAlarmService().isPlaying) {
        ConvoyAlarmService().startAlarm();
      } else if (!shouldAlarm && ConvoyAlarmService().isPlaying) {
        ConvoyAlarmService().stopAlarm();
      }
    }
    if (mounted) setState(() {});
  }

  TravelUnionGroup? get _union {
    return _service.unions.where((u) => u.id == widget.unionId).firstOrNull;
  }

  String _liveSpreadLabel(TravelUnionGroup union) {
    if (union.liveRiders.length < 2) return 'Spread: --';

    double maxMeters = 0;
    for (var i = 0; i < union.liveRiders.length; i++) {
      for (var j = i + 1; j < union.liveRiders.length; j++) {
        final a = union.liveRiders[i];
        final b = union.liveRiders[j];
        final meters = Geolocator.distanceBetween(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        );
        maxMeters = math.max(maxMeters, meters);
      }
    }

    return 'Spread: ~${(maxMeters / 1000).toStringAsFixed(1)} km';
  }

  void _toggleLiveGpsSharing() async {
    final union = _union;
    if (union == null) return;

    if (_isSharingLocation) {
      await _posStream?.cancel();
      _posStream = null;
      setState(() => _isSharingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📍 Location sharing paused.')),
      );
      return;
    }

    _autoStartLiveTracking();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '🟢 Live GPS tracking active! Your current location is shared with the convoy.',
        ),
        backgroundColor: Color(0xFF23695A),
      ),
    );
  }

  Future<void> _makeCall(String phone) async {
    try {
      final clean = phone.replaceAll(RegExp(r'\s+'), '');
      if (clean.isNotEmpty) {
        await launchUrl(
          Uri.parse('tel:$clean'),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {}
  }

  void _openEmergencyDialog(TravelUnionGroup union) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.emergency_rounded,
                        color: Colors.redAccent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Convoy Emergency SOS',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          Text(
                            'Instantly sound the alarm to all convoy riders',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                const Text(
                  'Select Emergency Reason:',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 10),
                _buildSosOption(
                  icon: Icons.personal_injury_rounded,
                  title: 'Accident / Crash',
                  subtitle: 'Urgent medical or physical assistance needed',
                  color: Colors.red,
                  onTap: () => _triggerSos(union, 'Accident / Crash'),
                ),
                const SizedBox(height: 8),
                _buildSosOption(
                  icon: Icons.car_crash_rounded,
                  title: 'Engine / Bike Breakdown',
                  subtitle: 'Vehicle stalled or mechanical failure on route',
                  color: Colors.orange.shade800,
                  onTap: () => _triggerSos(union, 'Engine / Bike Breakdown'),
                ),
                const SizedBox(height: 8),
                _buildSosOption(
                  icon: Icons.tire_repair_rounded,
                  title: 'Flat Tyre / Puncture',
                  subtitle: 'Puncture kit or air pump needed',
                  color: Colors.amber.shade900,
                  onTap: () => _triggerSos(union, 'Flat Tyre / Puncture'),
                ),
                const SizedBox(height: 8),
                _buildSosOption(
                  icon: Icons.local_gas_station_rounded,
                  title: 'Out of Fuel',
                  subtitle: 'Ran dry, need petrol or tow to fuel pump',
                  color: Colors.blueGrey,
                  onTap: () => _triggerSos(union, 'Out of Fuel'),
                ),
                const SizedBox(height: 8),
                _buildSosOption(
                  icon: Icons.notification_important_rounded,
                  title: 'General Distress / Stranded',
                  subtitle: 'Lost, bad weather, or unsafe conditions',
                  color: Colors.purple,
                  onTap: () =>
                      _triggerSos(union, 'General Distress / Stranded'),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSosOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerSos(TravelUnionGroup union, String reason) async {
    Navigator.of(context).pop();

    double lat = 13.0072;
    double lng = 76.0965;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 4),
        ),
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      final (sLat, sLng) = UnionService.resolveCityCoords(union.fromLocation);
      lat = sLat;
      lng = sLng;
    }

    final myName = _service.isOwner(union) ? union.hostName : 'Convoy Rider';
    final myMobile =
        _service.myRiderMobile ?? _service.myHostMobile ?? '+91 99000 12345';

    await _service.broadcastEmergencyAlert(
      unionId: union.id,
      emergencyType: reason,
      riderName: myName,
      riderMobile: myMobile,
      latitude: lat,
      longitude: lng,
      note:
          'Urgent support needed along ${union.fromLocation} -> ${union.toLocation}',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(
            '🚨 SOS Alert Broadcasted to all ${union.title} riders!',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _centerOnRider(ConvoyLiveRider rider) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(rider.latitude, rider.longitude),
          zoom: 14.5,
        ),
      ),
    );
  }

  void _fitAllRiders(TravelUnionGroup union) {
    if (_mapController == null) return;
    final waypoints = UnionService.getHighwayRouteWaypoints(
      union.fromLocation,
      union.toLocation,
    );

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;

    for (final pt in waypoints) {
      minLat = math.min(minLat, pt.latitude);
      maxLat = math.max(maxLat, pt.latitude);
      minLng = math.min(minLng, pt.longitude);
      maxLng = math.max(maxLng, pt.longitude);
    }

    for (final r in union.liveRiders) {
      minLat = math.min(minLat, r.latitude);
      maxLat = math.max(maxLat, r.latitude);
      minLng = math.min(minLng, r.longitude);
      maxLng = math.max(maxLng, r.longitude);
    }

    if (_myCurrentPosition != null) {
      minLat = math.min(minLat, _myCurrentPosition!.latitude);
      maxLat = math.max(maxLat, _myCurrentPosition!.latitude);
      minLng = math.min(minLng, _myCurrentPosition!.longitude);
      maxLng = math.max(maxLng, _myCurrentPosition!.longitude);
    }

    if (minLat > maxLat || minLng > maxLng) return;

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.05, minLng - 0.05),
          northeast: LatLng(maxLat + 0.05, maxLng + 0.05),
        ),
        65,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final union = _union;
    if (union == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Convoy Live Radar')),
        body: const Center(child: Text('Convoy not found')),
      );
    }

    final waypoints = UnionService.getHighwayRouteWaypoints(
      union.fromLocation,
      union.toLocation,
    );
    final startPt = waypoints.first;
    final endPt = waypoints.last;

    // Build markers
    final Set<Marker> markers = {};

    // 1. Origin Marker
    markers.add(
      Marker(
        markerId: const MarkerId('origin'),
        position: startPt,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Start: ${union.fromLocation}',
          snippet: 'Convoy Route Start',
        ),
      ),
    );

    // 2. Destination Marker (Fixed as decided during convoy creation)
    markers.add(
      Marker(
        markerId: const MarkerId('dest'),
        position: endPt,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Finish: ${union.toLocation}',
          snippet: 'Fixed Convoy Destination',
        ),
      ),
    );

    // 3. Current User Live Marker (Real-time GPS position)
    if (_myCurrentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('my_live_gps'),
          position: _myCurrentPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title:
                '${_service.isOwner(union) ? union.hostName : "You"} (Live GPS)',
            snippet:
                '${_myCurrentSpeed.toStringAsFixed(0)} km/h • Current Location',
          ),
          rotation: _myCurrentHeading,
          zIndexInt: 10,
        ),
      );
    }

    // 4. Live Riders Markers
    for (final rider in union.liveRiders) {
      final isDistressed = rider.isEmergency;
      final hue = isDistressed
          ? BitmapDescriptor.hueRose
          : (rider.isHost
                ? BitmapDescriptor.hueYellow
                : BitmapDescriptor.hueCyan);

      markers.add(
        Marker(
          markerId: MarkerId(rider.id),
          position: LatLng(rider.latitude, rider.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title:
                '${rider.name} ${rider.isHost ? '👑 Lead' : ''} ${isDistressed ? '🚨 SOS' : ''}',
            snippet:
                '${rider.vehicle} • ${rider.speedKmph.toStringAsFixed(0)} km/h',
          ),
          onTap: () {
            setState(() => _bottomSheetExpanded = true);
          },
        ),
      );
    }

    // High-visibility Highway Polylines (outer glow + inner vibrant lane)
    final Set<Polyline> polylines = {};
    if (waypoints.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('convoy_route_glow'),
          color: const Color(0xFF0F382E),
          width: 8,
          points: waypoints,
        ),
      );
      polylines.add(
        Polyline(
          polylineId: const PolylineId('convoy_route_main'),
          color: const Color(0xFF23695A),
          width: 5,
          points: waypoints,
        ),
      );
    }

    // If rider has moved away from start, connect their live position to the route
    if (_myCurrentPosition != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('my_live_corridor'),
          color: const Color(0xFF0284C7),
          width: 4,
          patterns: [PatternItem.dash(12), PatternItem.gap(6)],
          points: [_myCurrentPosition!, endPt],
        ),
      );
    }

    final latestAlert = union.latestEmergency;

    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(
                (startPt.latitude + endPt.latitude) / 2,
                (startPt.longitude + endPt.longitude) / 2,
              ),
              zoom: 8.5,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              Future.delayed(
                const Duration(milliseconds: 350),
                () => _fitAllRiders(union),
              );
            },
          ),

          // Top Header & Controls Overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Color(0xFF1E293B),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                union.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${union.fromLocation} ➔ ${union.toLocation}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Fit bounds button
                        IconButton(
                          icon: const Icon(
                            Icons.crop_free_rounded,
                            color: Color(0xFF23695A),
                            size: 20,
                          ),
                          tooltip: 'Fit All Riders',
                          onPressed: () => _fitAllRiders(union),
                        ),
                        // Live Radar Status Pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF23695A)
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.radar_rounded,
                                size: 14,
                                color: Color(0xFF23695A),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Live Radar',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF23695A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Emergency Alert Banner (when active)
                  if (latestAlert != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🚨 SOS: ${latestAlert.riderName}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${union.title} • ${latestAlert.emergencyType}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _makeCall(latestAlert.riderMobile),
                            child: const Text(
                              'Call',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Navigate within OUR app — fly map camera to SOS rider position
                          IconButton(
                            icon: const Icon(
                              Icons.my_location_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Locate on Map',
                            onPressed: () {
                              _mapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  LatLng(
                                    latestAlert.latitude,
                                    latestAlert.longitude,
                                  ),
                                  16.5,
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '📍 Map locked to ${latestAlert.riderName}\'s SOS location',
                                  ),
                                  backgroundColor: Colors.red.shade700,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          // Silence Audio Siren
                          IconButton(
                            icon: Icon(
                              (ConvoyAlarmService().isPlaying &&
                                      !_service.isAlertSilenced(latestAlert.id))
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: (ConvoyAlarmService().isPlaying &&
                                    !_service.isAlertSilenced(latestAlert.id))
                                ? 'Silence Siren'
                                : 'Siren Silenced',
                            onPressed: () {
                              if (ConvoyAlarmService().isPlaying ||
                                  !_service.isAlertSilenced(latestAlert.id)) {
                                _service.silenceAlert(latestAlert.id);
                              } else {
                                _service.unsilenceAlert(latestAlert.id);
                                ConvoyAlarmService().startAlarm();
                              }
                              setState(() {});
                            },
                          ),
                          const SizedBox(width: 5),
                          // Accept SOS Button (formerly tick mark)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF1B5E20),
                              size: 14,
                            ),
                            label: const Text(
                              'Accept',
                              style: TextStyle(
                                color: Color(0xFF1B5E20),
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              await _service.resolveEmergencyAlert(
                                union.id,
                                latestAlert.id,
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF23695A),
                                    content: Text(
                                      '✅ SOS in ${union.title} Accepted & Resolved!',
                                    ),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Floating Action Buttons (Fit All, GPS Share, Emergency SOS)
          Positioned(
            right: 16,
            bottom: _bottomSheetExpanded ? 315 : 135,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Re-center / Fit All Riders on Map
                FloatingActionButton.small(
                  heroTag: 'fit_all_bounds',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E293B),
                  elevation: 3,
                  tooltip: 'Fit All Riders',
                  onPressed: () => _fitAllRiders(union),
                  child: const Icon(Icons.crop_free_rounded, size: 18),
                ),
                const SizedBox(height: 10),

                // Live GPS Broadcast Toggle
                FloatingActionButton.small(
                  heroTag: 'gps_share',
                  backgroundColor: _isSharingLocation
                      ? const Color(0xFF10B981)
                      : Colors.white,
                  foregroundColor: _isSharingLocation
                      ? Colors.white
                      : const Color(0xFF23695A),
                  elevation: 3,
                  tooltip: _isSharingLocation
                      ? 'GPS Sharing Active'
                      : 'Start Sharing GPS',
                  onPressed: _toggleLiveGpsSharing,
                  child: Icon(
                    _isSharingLocation
                        ? Icons.my_location_rounded
                        : Icons.location_searching_rounded,
                  ),
                ),
                const SizedBox(height: 12),

                // High-visibility Emergency SOS Button
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: FloatingActionButton.extended(
                    heroTag: 'convoy_sos',
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    icon: const Icon(Icons.emergency_rounded, size: 22),
                    label: const Text(
                      'EMERGENCY SOS',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () => _openEmergencyDialog(union),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Convoy Radar Sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 12,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle & Summary Row
                    InkWell(
                      onTap: () => setState(
                        () => _bottomSheetExpanded = !_bottomSheetExpanded,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8F5E9),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.radar_rounded,
                                            size: 14,
                                            color: Color(0xFF23695A),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${union.liveRiders.length} Active Riders',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF23695A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _liveSpreadLabel(union),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  _bottomSheetExpanded
                                      ? Icons.keyboard_arrow_down_rounded
                                      : Icons.keyboard_arrow_up_rounded,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Expandable Riders Roster
                    if (_bottomSheetExpanded) ...[
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: union.liveRiders.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.two_wheeler_rounded,
                                      size: 36,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'No riders active on the route yet.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'GPS live tracking is active. Real-time locations of moving riders will appear here.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount: union.liveRiders.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 8),
                                itemBuilder: (ctx, i) {
                                  final r = union.liveRiders[i];
                                  return InkWell(
                                    onTap: () => _centerOnRider(r),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: r.isEmergency
                                                ? Colors.red.shade100
                                                : (r.isHost
                                                      ? Colors.amber.shade100
                                                      : const Color(
                                                          0xFFEFF6F3,
                                                        )),
                                            child: Text(
                                              r.isEmergency
                                                  ? '🚨'
                                                  : (r.name.isNotEmpty
                                                        ? r.name[0]
                                                              .toUpperCase()
                                                        : 'R'),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: r.isEmergency
                                                    ? Colors.red
                                                    : const Color(0xFF23695A),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      r.name,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 13,
                                                        color: r.isEmergency
                                                            ? Colors
                                                                  .red
                                                                  .shade800
                                                            : const Color(
                                                                0xFF1E293B,
                                                              ),
                                                      ),
                                                    ),
                                                    if (r.isHost) ...[
                                                      const SizedBox(width: 4),
                                                      const Text(
                                                        '👑',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                Text(
                                                  '${r.vehicle} • ${r.speedKmph.toStringAsFixed(0)} km/h',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.phone_rounded,
                                              size: 18,
                                              color: Color(0xFF23695A),
                                            ),
                                            onPressed: () =>
                                                _makeCall(r.mobile),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
