import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/providers.dart';
import '../../device/dead_reckoning/dead_reckoning_engine.dart';
import '../../maps/google_map_surface.dart';
import '../location/location_controller.dart';
import '../search/destination_search_screen.dart';
import '../journey/journey_history_screen.dart';
import '../safety_scoring/route_safety_recommendation_screen.dart';
import '../../domain/telemetry.dart';
import '../common/location_share_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isMapFullscreen = false;
  bool _showMapSurface = false;
  Timer? _mapWarmupTimer;
  LatLng? _selectedDestination;
  String? _destinationName;

  void _onMapTap(LatLng point) {
    setState(() {
      _selectedDestination = point;
      _destinationName =
          'Destination Point (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
    });
  }

  void _clearDestination() {
    setState(() {
      _selectedDestination = null;
      _destinationName = null;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(locationControllerProvider.notifier).start();
      }
    });
    _mapWarmupTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() => _showMapSurface = true);
      }
    });
  }

  @override
  void dispose() {
    _mapWarmupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(locationControllerProvider);
    final journeyState = ref.watch(journeyControllerProvider);
    final fix = state.fix;

    if (_isMapFullscreen) {
      final bottomInset = MediaQuery.of(context).padding.bottom;
      return Stack(
        children: [
          Positioned.fill(child: _buildMapSurface(fix, isFullscreen: true)),
          Positioned(
            bottom: 16 + bottomInset,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          journeyState.isRecording
                              ? Icons.fiber_manual_record
                              : Icons.navigation,
                          color: journeyState.isRecording
                              ? Colors.red
                              : const Color(0xff23695a),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          journeyState.isRecording
                              ? 'Recording (${journeyState.formattedDuration})'
                              : (fix != null
                                    ? '${((fix.speedMetersPerSecond ?? 0.0) * 3.6).toStringAsFixed(1)} km/h · ±${fix.accuracyMeters.toStringAsFixed(0)}m'
                                    : 'Waiting for GPS'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    FilledButton.tonal(
                      onPressed: () => setState(() => _isMapFullscreen = false),
                      child: const Text('Exit Fullscreen'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return SafeArea(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Search Bar (Google Maps Clean Style) with Direct Share Location Action
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DestinationSearchScreen(),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(6.0),
                          child: Icon(
                            Icons.search,
                            color: Color(0xff23695a),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const DestinationSearchScreen(),
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Where to? Search destination...',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Share Location button directly invoking native system share dialog
                      Tooltip(
                        message: 'Share Live Location',
                        child: InkWell(
                          onTap: () {
                            final lat = fix?.latitude ?? 12.9716;
                            final lon = fix?.longitude ?? 77.5946;
                            LocationShareSheet.shareDirectly(
                              latitude: lat,
                              longitude: lon,
                              accuracyMeters: fix?.accuracyMeters,
                              placeName: fix != null
                                  ? 'My Live Location'
                                  : 'Bengaluru Central',
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff23695a)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.share_location_rounded,
                                  size: 15,
                                  color: Color(0xff23695a),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Share',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xff23695a),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DestinationSearchScreen(),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xff23695a)
                                .withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.directions,
                            size: 17,
                            color: Color(0xff23695a),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Maximum Exposure Map View (Full Screen under Search)
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: _buildMapSurface(fix, isFullscreen: false),
                ),
              ),
            ],
          ),

          // If user tapped map to pick a destination, display Destination Reach Card at bottom
          if (_selectedDestination != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: _buildDestinationReachCard(fix),
            ),

          // If a journey recording is active in the background, show a floating indicator
          if (journeyState.isRecording)
            Positioned(
              top: 72,
              left: 20,
              right: 20,
              child: Center(
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const JourneyHistoryScreen(),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff1e293b).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Recording: ${journeyState.formattedDuration} · ${journeyState.totalSamples} pts',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 10,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapSurface(GeoFix? fix, {required bool isFullscreen}) {
    if (!_showMapSurface) {
      return _buildMapPlaceholder(fix);
    }

    return GoogleMapSurface(
      fix: fix,
      destinationPoint: _selectedDestination,
      destinationName: _destinationName,
      onMapTap: _onMapTap,
      isFullscreen: isFullscreen,
      onToggleFullscreen: () => setState(() {
        _isMapFullscreen = !isFullscreen;
      }),
    );
  }

  Widget _buildMapPlaceholder(GeoFix? fix) {
    return Container(
      color: const Color(0xFFEFF6F3),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/navguide_icon.png',
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Opening NavGuide',
              style: TextStyle(
                color: Color(0xFF134E42),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              fix == null ? 'Preparing map and GPS...' : 'Preparing map...',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestinationReachCard(GeoFix? fix) {
    if (_selectedDestination == null) return const SizedBox.shrink();

    double? distKm;
    if (fix != null) {
      final meters = GeodesyUtils.haversineDistanceMeters(
        fix.latitude,
        fix.longitude,
        _selectedDestination!.latitude,
        _selectedDestination!.longitude,
      );
      distKm = meters / 1000.0;
    }

    final isArrived = distKm != null && distKm <= 0.05;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isArrived
              ? const Color(0xff10b981)
              : const Color(0xff23695a).withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      (isArrived
                              ? const Color(0xff10b981)
                              : const Color(0xffef4444))
                          .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isArrived ? Icons.check_circle_rounded : Icons.place_rounded,
                  color: isArrived
                      ? const Color(0xff10b981)
                      : const Color(0xffef4444),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isArrived
                          ? '🎉 Reached Destination!'
                          : (_destinationName ?? 'Destination Point'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xff1e293b),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      distKm != null
                          ? (isArrived
                                ? 'You have arrived at this location'
                                : '${distKm.toStringAsFixed(2)} km from current location')
                          : 'Destination reach point selected',
                      style: TextStyle(
                        fontSize: 12,
                        color: isArrived
                            ? const Color(0xff10b981)
                            : Colors.black54,
                        fontWeight: isArrived
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.black45),
                onPressed: _clearDestination,
                tooltip: 'Clear destination',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff23695a),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    final oLat = fix?.latitude ?? 12.9716;
                    final oLon = fix?.longitude ?? 77.5946;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RouteSafetyRecommendationScreen(
                          customOriginLat: oLat,
                          customOriginLon: oLon,
                          customOriginName: 'Current Location',
                          customDestLat: _selectedDestination!.latitude,
                          customDestLon: _selectedDestination!.longitude,
                          customDestName:
                              _destinationName ?? 'Destination Reach Point',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.alt_route_rounded, size: 18),
                  label: const Text(
                    'Evaluate Safe Routes ➔',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: const Color(0xff23695a).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    LocationShareSheet.shareDirectly(
                      latitude: _selectedDestination!.latitude,
                      longitude: _selectedDestination!.longitude,
                      placeName: _destinationName ?? 'Destination Point',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: const Icon(
                      Icons.share_location_rounded,
                      color: Color(0xff23695a),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
