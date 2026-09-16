import 'package:flutter/material.dart';
import '../../device/crowdsourcing/crowdsourced_hazard_service.dart';
import '../../domain/crowdsourced_hazard_models.dart';
import '../../domain/route_safety_models.dart';

/// Comprehensive Journey Completion Report displaying route safety metrics,
/// technical GPS-blackout estimation stats, and crowdsourced route rating feedback.
class JourneyCompletionReportScreen extends StatefulWidget {
  const JourneyCompletionReportScreen({
    super.key,
    required this.selectedRoute,
    required this.destinationName,
    required this.totalDurationSeconds,
    required this.blackoutDurationSeconds,
    required this.totalDistanceKm,
    required this.averageSpeedKmh,
    required this.ekfDriftEstimateMeters,
    required this.aiDriftCorrectionMeters,
  });

  final RankedRoute selectedRoute;
  final String destinationName;
  final double totalDurationSeconds;
  final double blackoutDurationSeconds;
  final double totalDistanceKm;
  final double averageSpeedKmh;
  final double ekfDriftEstimateMeters;
  final double aiDriftCorrectionMeters;

  @override
  State<JourneyCompletionReportScreen> createState() =>
      _JourneyCompletionReportScreenState();
}

class _JourneyCompletionReportScreenState
    extends State<JourneyCompletionReportScreen> {
  int _selectedStars = 5;
  final Set<String> _selectedFeedbackTags = {};
  final _commentController = TextEditingController();
  bool _feedbackSubmitted = false;

  final List<String> _availableTags = [
    'Smooth Surface',
    'Low Traffic',
    'Severe Potholes',
    'Waterlogging / Flooding',
    'Construction Work',
    'Accident Blackspot Noticed',
    'Accurate Safety Score',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submitFeedback() {
    final feedback = RouteRatingFeedback(
      id: 'fb_${DateTime.now().millisecondsSinceEpoch}',
      routeId: widget.selectedRoute.routeId,
      starRating: _selectedStars,
      feedbackComment: _commentController.text.trim(),
      selectedTags: _selectedFeedbackTags.toList(),
      timestamp: DateTime.now(),
      distanceKm: widget.totalDistanceKm,
    );

    CrowdsourcedHazardService.instance.submitRouteRating(feedback);

    setState(() {
      _feedbackSubmitted = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xff23695a),
        content: Text('Thank you! Your rating helps the NavGuardian AI community.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final score = widget.selectedRoute.safetyScore.overallScore;
    final durationMin = (widget.totalDurationSeconds / 60.0).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey Complete'),
        backgroundColor: const Color(0xff1b4332),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Success Hero Banner
            Card(
              elevation: 4,
              color: const Color(0xffe8f5e9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xff2e7d32),
                      size: 54,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Arrived Safely at Destination',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff1b5e20),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.destinationName,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Journey Performance Metrics
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trip Summary & Safety Score',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMetricTile(
                          icon: Icons.timer_outlined,
                          value: '$durationMin min',
                          label: 'Total Time',
                        ),
                        _buildMetricTile(
                          icon: Icons.straighten_outlined,
                          value: '${widget.totalDistanceKm.toStringAsFixed(1)} km',
                          label: 'Distance',
                        ),
                        _buildMetricTile(
                          icon: Icons.shield_outlined,
                          value: '$score/100',
                          label: 'Safety Score',
                          valueColor: const Color(0xff23695a),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 3. Technical Dead Reckoning & AI Performance
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'NavGuardian AI Estimation Report',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: widget.blackoutDurationSeconds > 0
                                ? Colors.orange.shade100
                                : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.blackoutDurationSeconds > 0
                                ? '${widget.blackoutDurationSeconds.toInt()}s Blackout'
                                : 'Continuous GPS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: widget.blackoutDurationSeconds > 0
                                  ? Colors.orange.shade900
                                  : Colors.green.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    _buildTechRow(
                      'Simulated GPS Loss Duration',
                      '${widget.blackoutDurationSeconds.toStringAsFixed(1)} seconds',
                    ),
                    const SizedBox(height: 6),
                    _buildTechRow(
                      'EKF Pos Uncertainty (σ)',
                      '${widget.ekfDriftEstimateMeters.toStringAsFixed(2)} m',
                    ),
                    const SizedBox(height: 6),
                    _buildTechRow(
                      'AI Drift Correction Applied',
                      '${widget.aiDriftCorrectionMeters.toStringAsFixed(2)} m',
                    ),
                    const SizedBox(height: 6),
                    _buildTechRow(
                      'Sensors Utilized',
                      '9-Axis IMU (Accel, Gyro, Mag) @ 50Hz',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 4. Crowdsourced Route Rating & Feedback Form
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rate Route Safety & Conditions',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your community feedback updates safety scores for other drivers in real time.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    // Star Rating Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          IconButton(
                            icon: Icon(
                              i <= _selectedStars ? Icons.star_rounded : Icons.star_border_rounded,
                              color: Colors.amber.shade700,
                              size: 36,
                            ),
                            onPressed: _feedbackSubmitted
                                ? null
                                : () => setState(() => _selectedStars = i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Feedback tags chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final tag in _availableTags)
                          FilterChip(
                            label: Text(tag, style: const TextStyle(fontSize: 11)),
                            selected: _selectedFeedbackTags.contains(tag),
                            onSelected: _feedbackSubmitted
                                ? null
                                : (selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedFeedbackTags.add(tag);
                                      } else {
                                        _selectedFeedbackTags.remove(tag);
                                      }
                                    });
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _commentController,
                      enabled: !_feedbackSubmitted,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Any specific hazards, potholes, or flooded spots?',
                        hintStyle: const TextStyle(fontSize: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff23695a),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _feedbackSubmitted ? null : _submitFeedback,
                      child: Text(_feedbackSubmitted ? 'Feedback Submitted ✓' : 'Submit Route Rating'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 5. Back to Home Action
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text(
                'Done · Return to Home Map',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String value,
    required String label,
    Color? valueColor,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey.shade700, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.black87,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildTechRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
