import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/telemetry.dart';

class GoogleMapSurface extends StatefulWidget {
  const GoogleMapSurface({
    super.key,
    required this.fix,
    this.onToggleFullscreen,
    this.isFullscreen = false,
  });

  final GeoFix? fix;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  @override
  State<GoogleMapSurface> createState() => _GoogleMapSurfaceState();
}

class _GoogleMapSurfaceState extends State<GoogleMapSurface> {
  GoogleMapController? _controller;
  bool _follow = true;
  String? _cameraError;

  @override
  void didUpdateWidget(covariant GoogleMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fix != oldWidget.fix && _follow) _center();
  }

  Future<void> _center() async {
    final fix = widget.fix;
    if (fix == null || _controller == null) return;
    try {
      await _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(fix.latitude, fix.longitude), 16),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _cameraError = 'Map camera unavailable. Try reopening the app.',
        );
      }
    }
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
            _center();
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
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: true,
          markers: {
            if (fix != null)
              Marker(
                markerId: const MarkerId('position'),
                position: LatLng(fix.latitude, fix.longitude),
                infoWindow: InfoWindow(
                  title: fix.isStale(DateTime.now().toUtc())
                      ? 'Last GPS fix (stale)'
                      : 'GPS position',
                  snippet:
                      'Accuracy ±\ m',
                ),
              ),
          },
          circles: {
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
          },
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  tooltip:
                      widget.isFullscreen ? 'Exit Fullscreen' : 'Maximize Map',
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
