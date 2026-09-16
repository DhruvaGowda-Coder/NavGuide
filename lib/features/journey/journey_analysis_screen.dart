import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../device/dead_reckoning/outage_evaluator.dart';
import '../../device/storage/journey_reader.dart';
import '../../domain/telemetry.dart';

class JourneyAnalysisScreen extends StatefulWidget {
  const JourneyAnalysisScreen({super.key, required this.journey});

  final JourneyMetadata journey;

  @override
  State<JourneyAnalysisScreen> createState() => _JourneyAnalysisScreenState();
}

class _JourneyAnalysisScreenState extends State<JourneyAnalysisScreen> {
  final _reader = const JourneyReader();
  final _evaluator = const OutageEvaluator();

  bool _isLoading = true;
  String? _errorMessage;
  LoadedJourney? _loadedJourney;
  OutageEvaluationResult? _result;

  double _selectedDuration = 10.0;
  double _outageStartSeconds = 3.0;

  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _loadAndRun();
  }

  Future<void> _loadAndRun() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loaded = await _reader.loadJourney(widget.journey.directoryPath);
      _loadedJourney = loaded;

      if (loaded.gpsFixes.isEmpty) {
        throw StateError('This journey contains no GPS data to analyze.');
      }

      // Automatically adjust outage start and duration to fit journey length
      final maxAvailableSec = widget.journey.durationSeconds > 0
          ? widget.journey.durationSeconds.toDouble()
          : (loaded.gpsFixes.last.timestamp
                  .difference(loaded.gpsFixes.first.timestamp)
                  .inMilliseconds /
              1000.0);

      if (_outageStartSeconds >= maxAvailableSec) {
        _outageStartSeconds = 0.0;
      }

      if (_outageStartSeconds + _selectedDuration > maxAvailableSec) {
        _selectedDuration = (maxAvailableSec - _outageStartSeconds).clamp(1.0, 60.0);
      }

      _runEvaluation();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _runEvaluation() {
    if (_loadedJourney == null) return;
    try {
      final result = _evaluator.evaluate(
        journey: _loadedJourney!,
        outageStartSeconds: _outageStartSeconds,
        outageDurationSeconds: _selectedDuration,
      );

      setState(() {
        _result = result;
        _isLoading = false;
      });

      _zoomToFit(result);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _zoomToFit(OutageEvaluationResult result) {
    if (_mapController == null) return;
    final allPoints = <LatLng>[
      for (final p in result.allGpsCoordinates) LatLng(p.lat, p.lon),
      for (final p in result.deadReckoningCoordinates) LatLng(p.lat, p.lon),
      for (final p in result.ekfCoordinates) LatLng(p.lat, p.lon),
    ];

    if (allPoints.isEmpty) return;

    var minLat = allPoints.first.latitude;
    var maxLat = allPoints.first.latitude;
    var minLon = allPoints.first.longitude;
    var maxLon = allPoints.first.longitude;

    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    // Add padding if all points are nearly identical (e.g. stationary)
    if ((maxLat - minLat).abs() < 0.0001) {
      minLat -= 0.0005;
      maxLat += 0.0005;
    }
    if ((maxLon - minLon).abs() < 0.0001) {
      minLon -= 0.0005;
      maxLon += 0.0005;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        60.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Evaluation: ${widget.journey.id}'),
        actions: [
          if (_loadedJourney != null) ...[
            IconButton(
              icon: const Icon(Icons.tune_outlined),
              tooltip: 'EKF Diagnostics',
              onPressed: _showEkfDiagnostics,
            ),
            IconButton(
              icon: const Icon(Icons.table_chart_outlined),
              tooltip: 'Comparison Table',
              onPressed: _showDetailedComparisons,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loadAndRun,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                _buildMap(),
                _buildTopControls(),
                _buildBottomMetricsCard(),
              ],
            ),
    );
  }

  Widget _buildTopControls() {
    final journeyDuration = widget.journey.durationSeconds;
    final options = [10.0, 30.0, 60.0];

    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Simulated GPS Blackout',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    'Total Journey: ${journeyDuration}s',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final sec in options)
                    ChoiceChip(
                      label: Text('${sec.toInt()}s Outage'),
                      selected: (_selectedDuration - sec).abs() < 0.5,
                      onSelected: (sec <= journeyDuration || journeyDuration == 0)
                          ? (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedDuration = sec;
                                  _runEvaluation();
                                });
                              }
                            }
                          : null,
                    ),
                  if (journeyDuration > 0 && journeyDuration < 60)
                    ChoiceChip(
                      label: Text('Max (${journeyDuration}s)'),
                      selected: (_selectedDuration - journeyDuration).abs() < 0.5,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _outageStartSeconds = 0.0;
                            _selectedDuration = journeyDuration.toDouble();
                            _runEvaluation();
                          });
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_result == null) return const SizedBox.shrink();

    final result = _result!;
    final polylines = <Polyline>{};
    final markers = <Marker>{};

    // 1. Full Ground-Truth GPS Trajectory (Blue)
    if (result.allGpsCoordinates.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('all_gps'),
          color: const Color(0xff1976d2),
          width: 4,
          points: [
            for (final p in result.allGpsCoordinates) LatLng(p.lat, p.lon),
          ],
        ),
      );
    }

    // 2. Phase 3 Baseline Dead Reckoning Trajectory (Amber / Orange)
    if (result.deadReckoningCoordinates.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('dr_estimate'),
          color: const Color(0xffff8f00),
          width: 4,
          points: [
            LatLng(result.outageStartFix.latitude, result.outageStartFix.longitude),
            for (final p in result.deadReckoningCoordinates) LatLng(p.lat, p.lon),
          ],
        ),
      );
    }

    // 3. Phase 4 EKF Sensor Fusion Trajectory (Purple)
    if (result.ekfCoordinates.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('ekf_estimate'),
          color: const Color(0xff8e24aa),
          width: 5,
          points: [
            LatLng(result.outageStartFix.latitude, result.outageStartFix.longitude),
            for (final p in result.ekfCoordinates) LatLng(p.lat, p.lon),
          ],
        ),
      );
    }

    // 4. Markers
    // Start of Outage (Green)
    markers.add(
      Marker(
        markerId: const MarkerId('outage_start'),
        position: LatLng(result.outageStartFix.latitude, result.outageStartFix.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(
          title: 'Outage Start',
          snippet: 'GPS hidden from here onwards',
        ),
      ),
    );

    // Actual Ground Truth GPS End (Azure)
    if (result.outageEndFix != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('gps_actual_end'),
          position: LatLng(result.outageEndFix!.latitude, result.outageEndFix!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(
            title: 'Ground Truth GPS End',
            snippet: 'Actual position',
          ),
        ),
      );
    }

    // Phase 3 Basic DR End (Orange)
    markers.add(
      Marker(
        markerId: const MarkerId('dr_estimated_end'),
        position: LatLng(result.estimatedEndFix.latitude, result.estimatedEndFix.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: 'Basic DR End',
          snippet: 'Error: ${result.endpointErrorMeters.toStringAsFixed(1)} m',
        ),
      ),
    );

    // Phase 4 EKF Sensor Fusion End (Violet)
    markers.add(
      Marker(
        markerId: const MarkerId('ekf_estimated_end'),
        position: LatLng(result.ekfEstimatedEndFix.latitude, result.ekfEstimatedEndFix.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: InfoWindow(
          title: 'EKF Fusion End',
          snippet: 'Error: ${result.ekfEndpointErrorMeters.toStringAsFixed(1)} m',
        ),
      ),
    );

    final initialCenter = LatLng(
      result.outageStartFix.latitude,
      result.outageStartFix.longitude,
    );

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initialCenter, zoom: 17),
      padding: EdgeInsets.only(top: 110, bottom: 220 + bottomInset),
      polylines: polylines,
      markers: markers,
      onMapCreated: (ctrl) {
        _mapController = ctrl;
        _zoomToFit(result);
      },
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
    );
  }

  Widget _buildBottomMetricsCard() {
    if (_result == null) return const SizedBox.shrink();
    final res = _result!;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final pctImprove = res.rmseImprovementPercent;
    final isBetter = pctImprove > 0.5;
    final isWorse = pctImprove < -0.5;

    return Positioned(
      bottom: 16 + bottomInset,
      left: 12,
      right: 12,
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Phase 3 DR vs Phase 4 EKF',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${res.outageDurationSeconds.toInt()}s Outage · Hidden GPS: ${res.hiddenGpsPointsCount}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isBetter
                          ? Colors.green.shade100
                          : isWorse
                              ? Colors.red.shade100
                              : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isBetter
                          ? '+${pctImprove.toStringAsFixed(1)}% EKF Gain'
                          : isWorse
                              ? '${pctImprove.toStringAsFixed(1)}% EKF Drift'
                              : 'Similar RMSE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isBetter
                            ? Colors.green.shade900
                            : isWorse
                                ? Colors.red.shade900
                                : Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              // Comparison Table Rows
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2.2),
                  1: FlexColumnWidth(2.0),
                  2: FlexColumnWidth(2.0),
                },
                children: [
                  TableRow(
                    children: [
                      const Text(
                        'Metric',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Basic DR (P3)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                      Text(
                        'EKF Fusion (P4)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                  const TableRow(children: [SizedBox(height: 6), SizedBox(), SizedBox()]),
                  TableRow(
                    children: [
                      const Text('Final Error', style: TextStyle(fontSize: 11)),
                      Text(
                        '${res.endpointErrorMeters.toStringAsFixed(2)} m',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${res.ekfEndpointErrorMeters.toStringAsFixed(2)} m',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: res.ekfEndpointErrorMeters <= res.endpointErrorMeters
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                  const TableRow(children: [SizedBox(height: 4), SizedBox(), SizedBox()]),
                  TableRow(
                    children: [
                      const Text('RMSE', style: TextStyle(fontSize: 11)),
                      Text(
                        '${res.rmseMeters.toStringAsFixed(2)} m',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${res.ekfRmseMeters.toStringAsFixed(2)} m',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: res.ekfRmseMeters <= res.rmseMeters
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                  const TableRow(children: [SizedBox(height: 4), SizedBox(), SizedBox()]),
                  TableRow(
                    children: [
                      const Text('Drift Rate', style: TextStyle(fontSize: 11)),
                      Text(
                        '${res.driftRateMps.toStringAsFixed(3)} m/s',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${res.ekfDriftRateMps.toStringAsFixed(3)} m/s',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: res.ekfDriftRateMps <= res.driftRateMps
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'P3 Amber · P4 Purple · GPS Blue',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  InkWell(
                    onTap: _showEkfDiagnostics,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      child: Text(
                        'View EKF Diagnostics >',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEkfDiagnostics() {
    if (_result == null) return;
    final diag = _result!.ekfDiagnostics;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EKF Filter Diagnostics',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Real-time filter states and covariance metrics',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Divider(height: 20),
            _diagRow('Estimated Gyro Bias (b_w)', '${diag.gyroBiasDegPerSec.toStringAsFixed(3)} °/s'),
            _diagRow('Filter Position Uncertainty (σ)', '${diag.positionStdDevMeters.toStringAsFixed(2)} m'),
            _diagRow('Estimated Velocity', '${diag.estimatedSpeedMps.toStringAsFixed(2)} m/s'),
            _diagRow('Estimated Heading', '${diag.estimatedHeadingDegrees.toStringAsFixed(1)}°'),
            _diagRow('GPS Corrections Applied', '${diag.gpsUpdatesCount}'),
            _diagRow('Magnetometer Anomalies Dropped', '${diag.magAnomaliesCount}'),
            _diagRow('Stationary (ZUPT Active)', diag.isStationary ? 'Yes' : 'No'),
          ],
        ),
      ),
    );
  }

  Widget _diagRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  void _showDetailedComparisons() {
    if (_result == null) return;
    final points = _result!.comparisonPoints;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Point-by-Point Ground Truth vs DR vs EKF',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Evaluating isolated GPS fixes against both estimation filters',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Divider(),
              Expanded(
                child: points.isEmpty
                    ? const Center(child: Text('No GPS points landed in this window.'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: points.length,
                        itemBuilder: (ctx, i) {
                          final p = points[i];
                          final ekfErr = p.ekfErrorMeters ?? 0.0;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '+${p.elapsedSeconds.toStringAsFixed(1)}s into Outage',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            'DR: ${p.errorMeters.toStringAsFixed(2)}m',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.orange.shade900,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'EKF: ${ekfErr.toStringAsFixed(2)}m',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.purple.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'GPS: (${p.gpsLat.toStringAsFixed(5)}, ${p.gpsLon.toStringAsFixed(5)})\n'
                                    'DR:  (${p.estimatedLat.toStringAsFixed(5)}, ${p.estimatedLon.toStringAsFixed(5)})\n'
                                    'EKF: (${p.ekfLat?.toStringAsFixed(5) ?? "-"}, ${p.ekfLon?.toStringAsFixed(5) ?? "-"})',
                                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
