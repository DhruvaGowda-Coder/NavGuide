import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../device/crowdsourcing/crowdsourced_hazard_service.dart';
import '../../domain/crowdsourced_hazard_models.dart';
import 'hazard_report_screen.dart';

/// Full-featured Community Hazards Screen providing an interactive city hazard map,
/// filterable real-time hazard feed, and one-tap report creation.
class CommunityHazardsScreen extends StatefulWidget {
  const CommunityHazardsScreen({super.key});

  @override
  State<CommunityHazardsScreen> createState() => _CommunityHazardsScreenState();
}

class _CommunityHazardsScreenState extends State<CommunityHazardsScreen> {
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
    final result = await showModalBottomSheet<CrowdsourcedHazardReport>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const HazardReportScreen(
        initialLatitude: 12.9352,
        initialLongitude: 77.6245,
        roadName: 'Current Location Corridor',
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
      body: Column(
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
                      GoogleMap(
                        initialCameraPosition: const CameraPosition(
                          target: _bangaloreCenter,
                          zoom: 12.8,
                        ),
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
                            ),
                        },
                        zoomControlsEnabled: false,
                        myLocationButtonEnabled: false,
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
                      // Floating Report CTA
                      Positioned(
                        right: 16,
                        bottom: 16,
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
                    ],
                  )
                : (filteredHazards.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
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
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
                        itemCount: filteredHazards.length,
                        itemBuilder: (ctx, idx) {
                          final h = filteredHazards[idx];
                          return _buildHazardCard(h);
                        },
                      )),
          ),
        ],
      ),
      floatingActionButton: !_showMapView && filteredHazards.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'comm_report_btn_list',
              onPressed: _openReportModal,
              backgroundColor: const Color(0xffb71c1c),
              icon: const Icon(Icons.add_alert_rounded, color: Colors.white),
              label: const Text(
                'Report Hazard',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            )
          : null,
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
                  ],
                ),
              ],
            ),
          ],
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
