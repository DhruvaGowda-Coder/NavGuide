import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../device/crowdsourcing/crowdsourced_hazard_service.dart';
import '../../domain/crowdsourced_hazard_models.dart';
import '../location/location_controller.dart';
import 'hazard_report_screen.dart';

/// Full-featured Community Hazards Screen providing an interactive city hazard map,
/// filterable real-time hazard feed, and one-tap report creation.
class CommunityHazardsScreen extends ConsumerStatefulWidget {
  const CommunityHazardsScreen({super.key});

  @override
  ConsumerState<CommunityHazardsScreen> createState() => _CommunityHazardsScreenState();
}

class _CommunityHazardsScreenState extends ConsumerState<CommunityHazardsScreen> {
  final _hazardService = CrowdsourcedHazardService.instance;
  GoogleMapController? _mapController;

  HazardType? _filterType;
  bool _showMapView = true;
  bool _isLoading = true;

  static const LatLng _bangaloreCenter = LatLng(12.9352, 77.6245);

  @override
  void initState() {
    super.initState();
    _loadHazards();
  }

  Future<void> _loadHazards() async {
    await _hazardService.initialize();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  void _openReportModal() async {
    final fix = ref.read(locationControllerProvider).fix;
    final lat = fix?.latitude ?? _bangaloreCenter.latitude;
    final lon = fix?.longitude ?? _bangaloreCenter.longitude;

    final result = await showModalBottomSheet<CrowdsourcedHazardReport>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => HazardReportScreen(
        initialLatitude: lat,
        initialLongitude: lon,
        roadName: fix != null ? 'Current GPS Location' : 'Current Location Corridor',
      ),
    );

    if (result != null && mounted) {
      setState(() {});
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(result.latitude, result.longitude), 15),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final allHazards = _hazardService.getAllHazards();
    final filteredHazards = _filterType == null
        ? allHazards
        : allHazards.where((h) => h.hazardType == _filterType).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Hazards'),
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
        children: [
          // Filter Chips & View Toggle Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${filteredHazards.length} Live Community Hazards',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    IconButton.filledTonal(
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: Icon(_showMapView ? Icons.list_rounded : Icons.map_rounded, size: 18),
                      tooltip: _showMapView ? 'Switch to List' : 'Switch to Map',
                      onPressed: () => setState(() => _showMapView = !_showMapView),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All', style: TextStyle(fontSize: 11)),
                        selected: _filterType == null,
                        onSelected: (_) => setState(() => _filterType = null),
                      ),
                      const SizedBox(width: 6),
                      for (final type in HazardType.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(type.displayName, style: const TextStyle(fontSize: 11)),
                            selected: _filterType == type,
                            onSelected: (selected) {
                              setState(() => _filterType = selected ? type : null);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main View (Map or List)
          Expanded(
            child: _showMapView
                ? Stack(
                    children: [
                      Builder(
                        builder: (context) {
                          final fix = ref.watch(locationControllerProvider).fix;
                          return GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: fix != null
                                  ? LatLng(fix.latitude, fix.longitude)
                                  : _bangaloreCenter,
                              zoom: 13.5,
                            ),
                            myLocationEnabled: fix != null,
                            myLocationButtonEnabled: true,
                            zoomControlsEnabled: false,
                            onMapCreated: (ctrl) => _mapController = ctrl,
                            markers: {
                              for (final h in filteredHazards)
                                Marker(
                                  markerId: MarkerId('comm_${h.id}'),
                                  position: LatLng(h.latitude, h.longitude),
                                  icon: BitmapDescriptor.defaultMarkerWithHue(
                                    h.hazardType == HazardType.flood ||
                                            h.hazardType == HazardType.roadBlocked
                                        ? BitmapDescriptor.hueRed
                                        : (h.hazardType == HazardType.accident
                                            ? BitmapDescriptor.hueOrange
                                            : BitmapDescriptor.hueYellow),
                                  ),
                                  infoWindow: InfoWindow(
                                    title: '${h.hazardType.displayName} (${h.severity})',
                                    snippet:
                                        '${h.description} · ${(h.reliabilityScore * 100).toInt()}% verified',
                                  ),
                                  onTap: () => _showHazardDetailsModal(h),
                                ),
                            },
                          );
                        },
                      ),
                      if (filteredHazards.isEmpty)
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Card(
                            elevation: 3,
                            color: Colors.white.withValues(alpha: 0.94),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Color(0xff23695a), size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _filterType == null
                                          ? 'No hazards reported yet. The roads are clear!'
                                          : 'No active ${_filterType!.displayName} reports.',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : RefreshIndicator(
                    color: const Color(0xffb71c1c),
                    onRefresh: _loadHazards,
                    child: filteredHazards.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_outlined, size: 64, color: Colors.grey.shade400),
                                    const SizedBox(height: 16),
                                    Text(
                                      _filterType == null
                                          ? 'No Hazards Reported'
                                          : 'No ${_filterType!.displayName} Hazards',
                                      style: Theme.of(context).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'The community database is clear. Tap "Report Hazard" below to alert drivers if you spot road issues.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey, fontSize: 13),
                                    ),
                                    const SizedBox(height: 20),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(backgroundColor: const Color(0xffb71c1c)),
                                      onPressed: _openReportModal,
                                      icon: const Icon(Icons.add_alert_rounded),
                                      label: const Text('Report Hazard'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                            itemCount: filteredHazards.length,
                            itemBuilder: (ctx, idx) {
                              final h = filteredHazards[idx];
                              return _buildHazardCard(h);
                            },
                          ),
                  ),
          ),
        ],
      ),
      ),
      floatingActionButton: (!_showMapView && filteredHazards.isEmpty)
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom > 0 ? 10 : 16,
              ),
              child: FloatingActionButton.extended(
                heroTag: 'comm_report_btn',
                onPressed: _openReportModal,
                backgroundColor: const Color(0xffb71c1c),
                icon: const Icon(Icons.add_alert_rounded, color: Colors.white),
                label: const Text(
                  'Report Hazard',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
    );
  }

  Widget _buildHazardCard(CrowdsourcedHazardReport h) {
    final reliabilityPct = (h.reliabilityScore * 100).toInt();
    final alreadyVoted = _hazardService.hasUserVoted(h.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getHazardIcon(h.hazardType), color: Colors.orange.shade800, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    h.hazardType.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$reliabilityPct% verified',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(h.description, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              h.roadName,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const Divider(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${h.confirmationsCount} Confirmations · ${h.rejectionsCount} Absent',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.thumb_down_outlined,
                        size: 16,
                        color: alreadyVoted ? Colors.grey : Colors.red,
                      ),
                      tooltip: alreadyVoted ? 'Already voted' : 'Mark Absent / Fixed',
                      onPressed: alreadyVoted
                          ? null
                          : () async {
                              await _hazardService.rejectHazard(h.id);
                              if (!mounted) return;
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Feedback recorded: Marked absent.')),
                              );
                            },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.thumb_up_alt_rounded,
                        size: 16,
                        color: alreadyVoted ? Colors.grey : const Color(0xff23695a),
                      ),
                      tooltip: alreadyVoted ? 'Already voted' : 'Confirm Hazard',
                      onPressed: alreadyVoted
                          ? null
                          : () async {
                              await _hazardService.confirmHazard(h.id);
                              if (!mounted) return;
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Thank you! Hazard confirmed.')),
                              );
                            },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      tooltip: 'Delete Hazard',
                      onPressed: () => _confirmDeleteHazard(h),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteHazard(CrowdsourcedHazardReport h) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Delete Hazard?'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${h.hazardType.displayName}" on ${h.roadName}? It will be removed from the community map and will no longer affect route recommendations.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await _hazardService.deleteHazard(h.id);
              if (!mounted) return;
              if (ok) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.red.shade700,
                    content: Text('Hazard "${h.hazardType.displayName}" deleted successfully.'),
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showHazardDetailsModal(CrowdsourcedHazardReport h) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 24 + MediaQuery.of(ctx).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Icon(_getHazardIcon(h.hazardType), color: Colors.orange.shade800, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.hazardType.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        h.roadName,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${(h.reliabilityScore * 100).toInt()}% Verified',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(h.description, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Text(
              'Severity: ${h.severity} · ${h.confirmationsCount} Confirmations · ${h.rejectionsCount} Absent',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete Hazard'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmDeleteHazard(h);
                  },
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xff23695a)),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  IconData _getHazardIcon(HazardType type) {
    return switch (type) {
      HazardType.pothole => Icons.broken_image_rounded,
      HazardType.flood => Icons.water_drop_rounded,
      HazardType.accident => Icons.car_crash_rounded,
      HazardType.construction => Icons.construction_rounded,
      HazardType.roadBlocked => Icons.do_not_disturb_on_rounded,
      HazardType.poorRoad => Icons.waves_rounded,
      HazardType.other => Icons.warning_amber_rounded,
    };
  }
}
