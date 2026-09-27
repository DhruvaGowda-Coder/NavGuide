import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../device/dead_reckoning/dead_reckoning_engine.dart';
import '../domain/telemetry.dart';

class GoogleMapSurface extends StatefulWidget {
  const GoogleMapSurface({
    super.key,
    required this.fix,
    this.destinationPoint,
    this.destinationName,
    this.routePolyline,
    this.onMapTap,
    this.onToggleFullscreen,
    this.isFullscreen = false,
  });

  final GeoFix? fix;
  final LatLng? destinationPoint;
  final String? destinationName;
  final List<LatLng>? routePolyline;
  final ValueChanged<LatLng>? onMapTap;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  @override
  State<GoogleMapSurface> createState() => _GoogleMapSurfaceState();
}

class _GoogleMapSurfaceState extends State<GoogleMapSurface> {
  GoogleMapController? _controller;
  bool _follow = true;
  bool _is3dPerspective = false;
  String? _cameraError;
  CameraPosition? _currentCameraPosition;
  DateTime _lastAutoCenterAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _hasReachedDestination {
    final dest = widget.destinationPoint;
    final fix = widget.fix;
    if (dest == null || fix == null) return false;
    final d = GeodesyUtils.haversineDistanceMeters(
      fix.latitude,
      fix.longitude,
      dest.latitude,
      dest.longitude,
    );
    return d <= 50.0;
  }

  @override
  void didUpdateWidget(covariant GoogleMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fix != oldWidget.fix && _follow) {
      final now = DateTime.now();
      if (now.difference(_lastAutoCenterAt) > const Duration(seconds: 2)) {
        _lastAutoCenterAt = now;
        _center();
      }
    }
    if (widget.destinationPoint != oldWidget.destinationPoint &&
        widget.destinationPoint != null) {
      _fitRouteOverview();
    }
  }

  Future<void> _fitRouteOverview() async {
    final fix = widget.fix;
    final dest = widget.destinationPoint;
    if (_controller == null || dest == null) return;
    try {
      if (fix != null) {
        final southWest = LatLng(
          math.min(fix.latitude, dest.latitude),
          math.min(fix.longitude, dest.longitude),
        );
        final northEast = LatLng(
          math.max(fix.latitude, dest.latitude),
          math.max(fix.longitude, dest.longitude),
        );
        if (_is3dPerspective) {
          final centerLat = (southWest.latitude + northEast.latitude) / 2;
          final centerLon = (southWest.longitude + northEast.longitude) / 2;
          await _controller!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(centerLat, centerLon),
                zoom: 16.2,
                tilt: 67.5,
                bearing: 30.0,
              ),
            ),
          );
        } else {
          await _controller!.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(southwest: southWest, northeast: northEast),
              70,
            ),
          );
        }
      } else {
        final double targetTilt = _is3dPerspective ? 67.5 : 0.0;
        final double targetBearing = _is3dPerspective ? 35.0 : 0.0;
        await _controller!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: dest,
              zoom: _is3dPerspective ? 17.6 : 15.0,
              tilt: targetTilt,
              bearing: targetBearing,
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _center() async {
    final fix = widget.fix;
    if (fix == null || _controller == null) return;
    try {
      final double targetTilt = _is3dPerspective ? 67.5 : 0.0;
      final double targetBearing = _is3dPerspective
          ? (fix.headingDegrees != null && fix.headingDegrees! > 0
                ? fix.headingDegrees!
                : 35.0)
          : 0.0;
      final double targetZoom = _is3dPerspective ? 17.8 : 16.0;

      await _controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(fix.latitude, fix.longitude),
            zoom: targetZoom,
            tilt: targetTilt,
            bearing: targetBearing,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _cameraError = 'Map camera unavailable. Try reopening the app.',
        );
      }
    }
  }

  Future<void> _applyPerspectiveToggle() async {
    if (_controller == null) return;
    try {
      final fix = widget.fix;
      final targetPos =
          _currentCameraPosition?.target ??
          (fix != null
              ? LatLng(fix.latitude, fix.longitude)
              : (widget.destinationPoint ?? const LatLng(12.9716, 77.5946)));

      final double currentZoom =
          _currentCameraPosition?.zoom ?? (fix != null ? 16.5 : 15.0);

      // In 3D: Deep 67.5° perspective pitch, dramatic 35° bearing angle, zoom >= 17.6 for 3D buildings!
      // In 2D: Flat 0° top-down perpendicular view, 0° North bearing, comfortable 15.2 zoom!
      final double targetTilt = _is3dPerspective ? 67.5 : 0.0;
      final double targetBearing = _is3dPerspective ? 35.0 : 0.0;
      final double targetZoom = _is3dPerspective
          ? math.max(currentZoom, 17.6)
          : math.min(currentZoom, 15.2);

      await _controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: targetPos,
            zoom: targetZoom,
            tilt: targetTilt,
            bearing: targetBearing,
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'Maps are not supported on this platform yet',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Use the Android application for this milestone.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final fix = widget.fix;
    final dest = widget.destinationPoint;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: fix == null
                ? const LatLng(12.9716, 77.5946)
                : LatLng(fix.latitude, fix.longitude),
            zoom: fix == null ? 12 : 16,
          ),
          onMapCreated: (controller) {
            _controller = controller;
            if (dest != null) {
              _fitRouteOverview();
            } else {
              _center();
            }
          },
          onTap: (point) {
            if (_follow) {
              setState(() => _follow = false);
            }
            widget.onMapTap?.call(point);
          },
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          onCameraMoveStarted: () {
            if (_follow) {
              setState(() => _follow = false);
            }
          },
          onCameraMove: (position) {
            _currentCameraPosition = position;
          },
          tiltGesturesEnabled: true,
          rotateGesturesEnabled: true,
          buildingsEnabled: true,
          myLocationEnabled: fix != null,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: true,
          polylines: {
            if (widget.routePolyline != null &&
                widget.routePolyline!.isNotEmpty)
              Polyline(
                polylineId: const PolylineId('explore_route'),
                points: widget.routePolyline!,
                color: const Color(0xff23695a),
                width: 6,
              )
            else if (fix != null && dest != null)
              Polyline(
                polylineId: const PolylineId('direct_reach_line'),
                points: [LatLng(fix.latitude, fix.longitude), dest],
                color: const Color(0xff23695a),
                width: 4,
                patterns: [PatternItem.dash(15), PatternItem.gap(10)],
              ),
          },
          markers: {
            // 1. Live GPS Location Marker
            if (fix != null)
              Marker(
                markerId: const MarkerId('position'),
                position: LatLng(fix.latitude, fix.longitude),
                infoWindow: InfoWindow(
                  title: fix.isStale(DateTime.now().toUtc())
                      ? 'Last GPS fix (stale)'
                      : 'Live Location',
                  snippet:
                      'Accuracy ±${fix.accuracyMeters.toStringAsFixed(1)} m',
                ),
              ),

            // 2. Destination Reach Point Marker
            if (dest != null)
              Marker(
                markerId: const MarkerId('destination_reach_point'),
                position: dest,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  _hasReachedDestination
                      ? BitmapDescriptor.hueGreen
                      : BitmapDescriptor.hueRed,
                ),
                infoWindow: InfoWindow(
                  title: _hasReachedDestination
                      ? '🎉 Destination Reached!'
                      : (widget.destinationName ?? 'Destination Reach Point'),
                  snippet: _hasReachedDestination
                      ? 'Safely reached target location'
                      : 'Target arrival point',
                ),
                zIndexInt: 900,
              ),
          },
          circles: {
            // GPS accuracy radius circle
            if (fix != null &&
                fix.accuracyMeters.isFinite &&
                fix.accuracyMeters >= 0)
              Circle(
                circleId: const CircleId('accuracy'),
                center: LatLng(fix.latitude, fix.longitude),
                radius: fix.accuracyMeters,
                strokeWidth: 1,
                fillColor: const Color(0x2223695a),
                strokeColor: const Color(0xff23695a),
              ),

            // Destination Reach Zone Circle
            if (dest != null)
              Circle(
                circleId: const CircleId('destination_reach_zone'),
                center: dest,
                radius: _hasReachedDestination ? 55.0 : 35.0,
                strokeWidth: 2,
                fillColor: _hasReachedDestination
                    ? const Color(0x3310b981)
                    : const Color(0x25ef4444),
                strokeColor: _hasReachedDestination
                    ? const Color(0xff10b981)
                    : const Color(0xffef4444),
              ),
          },
        ),

        Positioned(
          right: 12,
          top: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 3D / 2D Perspective Toggle Button (High-Visibility & Dynamic)
              Container(
                decoration: BoxDecoration(
                  color: _is3dPerspective
                      ? const Color(0xff23695a)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _is3dPerspective
                        ? const Color(0xff143d31)
                        : const Color(0xff23695a),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() => _is3dPerspective = !_is3dPerspective);
                      _applyPerspectiveToggle();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _is3dPerspective
                                ? Icons.view_in_ar_rounded
                                : Icons.view_in_ar_outlined,
                            size: 17,
                            color: _is3dPerspective
                                ? Colors.white
                                : const Color(0xff23695a),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _is3dPerspective ? '3D View' : '2D Map',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: _is3dPerspective
                                  ? Colors.white
                                  : const Color(0xff23695a),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () {
                  setState(() => _follow = !_follow);
                  if (_follow) _center();
                },
                icon: Icon(
                  _follow ? Icons.gps_fixed : Icons.gps_not_fixed,
                  size: 18,
                ),
                label: Text(_follow ? 'Following' : 'Explore'),
              ),
              if (widget.onToggleFullscreen != null) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: widget.onToggleFullscreen,
                  tooltip: widget.isFullscreen
                      ? 'Exit Fullscreen'
                      : 'Maximize Map',
                  icon: Icon(
                    widget.isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_cameraError != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_cameraError!),
              ),
            ),
          ),
      ],
    );
  }
}
