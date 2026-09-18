import 'package:flutter/material.dart';
import '../../device/crowdsourcing/crowdsourced_hazard_service.dart';
import '../../domain/crowdsourced_hazard_models.dart';

/// One-tap community hazard reporting screen and nearby community feed.
class HazardReportScreen extends StatefulWidget {
  const HazardReportScreen({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    this.roadName = 'Hosur Road corridor',
  });

  final double initialLatitude;
  final double initialLongitude;
  final String roadName;

  @override
  State<HazardReportScreen> createState() => _HazardReportScreenState();
}

class _HazardReportScreenState extends State<HazardReportScreen> {
  final _hazardService = CrowdsourcedHazardService.instance;
  final _descController = TextEditingController();

  final Set<HazardType> _selectedTypes = {HazardType.pothole};
  String _selectedSeverity = 'HIGH';
  bool _isSubmitting = false;

  final List<String> _severities = ['LOW', 'MODERATE', 'HIGH', 'CRITICAL'];

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  void _submitReport() async {
    if (_selectedTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one hazard type.')),
      );
      return;
    }

    final text = _descController.text.trim();
    setState(() => _isSubmitting = true);

    final submittedReports = <CrowdsourcedHazardReport>[];
    for (final type in _selectedTypes) {
      final description = text.isNotEmpty
          ? text
          : '${type.displayName} reported on ${widget.roadName}';

      final report = await _hazardService.submitHazardReport(
        hazardType: type,
        description: description,
        latitude: widget.initialLatitude,
        longitude: widget.initialLongitude,
        roadName: widget.roadName,
        severity: _selectedSeverity,
      );
      submittedReports.add(report);
    }

    if (!mounted) return;

    final count = submittedReports.length;
    final typesStr = submittedReports.map((r) => r.hazardType.displayName).join(', ');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xff23695a),
        content: Text(
          count == 1
              ? 'Report submitted! $typesStr broadcasted to all drivers.'
              : '$count hazards reported! ($typesStr) broadcasted to all drivers.',
        ),
      ),
    );

    Navigator.pop(context, submittedReports.isNotEmpty ? submittedReports.first : null);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    final nearbyHazards = _hazardService.getNearbyHazards(
      lat: widget.initialLatitude,
      lon: widget.initialLongitude,
      radiusMeters: 2500,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_alert_rounded, color: Colors.red, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Report Road Hazards',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      widget.roadName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 18),

          Expanded(
            child: ListView(
              children: [
                // 1. Hazard Type Selector (Multi-Select)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Hazard Types',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xff23695a).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_selectedTypes.length} selected',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff23695a),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select one or multiple hazards present at this location:',
                  style: TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in HazardType.values)
                      FilterChip(
                        avatar: Icon(
                          _getHazardIcon(type),
                          size: 16,
                          color: _selectedTypes.contains(type)
                              ? const Color(0xff23695a)
                              : Colors.grey.shade700,
                        ),
                        label: Text(
                          type.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _selectedTypes.contains(type)
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        selected: _selectedTypes.contains(type),
                        selectedColor: const Color(0xff23695a).withValues(alpha: 0.18),
                        checkmarkColor: const Color(0xff23695a),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedTypes.add(type);
                            } else {
                              if (_selectedTypes.length > 1) {
                                _selectedTypes.remove(type);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    duration: Duration(seconds: 1),
                                    content: Text('At least one hazard type must remain selected.'),
                                  ),
                                );
                              }
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Severity Level
                const Text(
                  'Severity Level',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final sev in _severities)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: Text(
                              sev,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: _selectedSeverity == sev ? Colors.white : Colors.black87,
                              ),
                            ),
                            selected: _selectedSeverity == sev,
                            selectedColor: _getSeverityColor(sev),
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedSeverity = sev);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. Description Field
                TextField(
                  controller: _descController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Details (e.g. Deep crater waterlogged after heavy rain)',
                    hintStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Submit Button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffb71c1c),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.broadcast_on_personal_rounded, size: 20),
                  label: Text(
                    _isSubmitting
                        ? 'Broadcasting...'
                        : 'Broadcast ${_selectedTypes.length} Hazard${_selectedTypes.length > 1 ? "s" : ""} to Drivers',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: _isSubmitting ? null : _submitReport,
                ),
                const SizedBox(height: 22),

                // 5. Nearby Community Reports Feed
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Active Community Reports Nearby',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${nearbyHazards.length} hazards',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (nearbyHazards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'No hazards reported along this section yet.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  )
                else
                  for (final h in nearbyHazards)
                    _buildCommunityHazardTile(h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityHazardTile(CrowdsourcedHazardReport h) {
    final reliabilityPct = (h.reliabilityScore * 100).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_getHazardIcon(h.hazardType), color: Colors.orange.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      h.hazardType.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$reliabilityPct% verified (${h.confirmationsCount}👍)',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Delete hazard',
                      onPressed: () => _confirmDeleteHazard(h),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  h.description,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 2),
                Text(
                  h.roadName,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
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
          'Are you sure you want to remove "${h.hazardType.displayName}" on ${h.roadName}? It will be permanently removed from the community map.',
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

  Color _getSeverityColor(String sev) {
    return switch (sev) {
      'LOW' => Colors.blue.shade700,
      'MODERATE' => Colors.amber.shade800,
      'HIGH' => Colors.orange.shade800,
      'CRITICAL' => Colors.red.shade800,
      _ => Colors.grey.shade700,
    };
  }
}
