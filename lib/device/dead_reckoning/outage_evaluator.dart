import 'dart:math' as math;
import '../../domain/telemetry.dart';
import '../fusion/ai_drift_predictor.dart';
import '../fusion/ekf_sensor_fusion_engine.dart';
import '../storage/journey_reader.dart';
import 'dead_reckoning_engine.dart';

class ComparisonPoint {
  const ComparisonPoint({
    required this.timestamp,
    required this.elapsedSeconds,
    required this.gpsLat,
    required this.gpsLon,
    required this.estimatedLat,
    required this.estimatedLon,
    required this.errorMeters,
    this.ekfLat,
    this.ekfLon,
    this.ekfErrorMeters,
    this.aiLat,
    this.aiLon,
    this.aiErrorMeters,
  });

  final DateTime timestamp;
  final double elapsedSeconds;
  final double gpsLat;
  final double gpsLon;
  final double estimatedLat;
  final double estimatedLon;
  final double errorMeters;
  final double? ekfLat;
  final double? ekfLon;
  final double? ekfErrorMeters;
  final double? aiLat;
  final double? aiLon;
  final double? aiErrorMeters;
}

class OutageEvaluationResult {
  const OutageEvaluationResult({
    required this.outageDurationSeconds,
    required this.actualOutageDurationSeconds,
    // Phase 3 Baseline Dead Reckoning Metrics
    required this.endpointErrorMeters,
    required this.rmseMeters,
    required this.meanErrorMeters,
    required this.maxErrorMeters,
    required this.driftRateMps,
    required this.hiddenGpsPointsCount,
    required this.allGpsCoordinates,
    required this.groundTruthCoordinates,
    required this.deadReckoningCoordinates,
    required this.outageStartFix,
    required this.outageEndFix,
    required this.estimatedEndFix,
    required this.comparisonPoints,
    // Phase 4 EKF Sensor Fusion Metrics
    required this.ekfCoordinates,
    required this.ekfEstimatedEndFix,
    required this.ekfEndpointErrorMeters,
    required this.ekfRmseMeters,
    required this.ekfMeanErrorMeters,
    required this.ekfMaxErrorMeters,
    required this.ekfDriftRateMps,
    required this.ekfDiagnostics,
    // Phase 5 NavGuardian AI Metrics
    required this.aiCoordinates,
    required this.aiEstimatedEndFix,
    required this.aiEndpointErrorMeters,
    required this.aiRmseMeters,
    required this.aiMeanErrorMeters,
    required this.aiMaxErrorMeters,
    required this.aiDriftRateMps,
  });

  final double outageDurationSeconds;
  final double actualOutageDurationSeconds;
  final int hiddenGpsPointsCount;

  // Phase 3 Baseline Dead Reckoning
  final double endpointErrorMeters;
  final double rmseMeters;
  final double meanErrorMeters;
  final double maxErrorMeters;
  final double driftRateMps;
  final List<({double lat, double lon})> deadReckoningCoordinates;
  final GeoFix estimatedEndFix;

  // Phase 4 Extended Kalman Filter
  final double ekfEndpointErrorMeters;
  final double ekfRmseMeters;
  final double ekfMeanErrorMeters;
  final double ekfMaxErrorMeters;
  final double ekfDriftRateMps;
  final List<({double lat, double lon})> ekfCoordinates;
  final GeoFix ekfEstimatedEndFix;
  final EkfDiagnostics ekfDiagnostics;

  // Phase 5 NavGuardian AI
  final double aiEndpointErrorMeters;
  final double aiRmseMeters;
  final double aiMeanErrorMeters;
  final double aiMaxErrorMeters;
  final double aiDriftRateMps;
  final List<({double lat, double lon})> aiCoordinates;
  final GeoFix aiEstimatedEndFix;

  // Reference Trajectories & Anchors
  final List<({double lat, double lon})> allGpsCoordinates;
  final List<({double lat, double lon})> groundTruthCoordinates;
  final GeoFix outageStartFix;
  final GeoFix? outageEndFix;
  final List<ComparisonPoint> comparisonPoints;

  /// Percentage improvement of EKF over Basic DR RMSE
  double get rmseImprovementPercent =>
      rmseMeters > 0.0001 ? ((rmseMeters - ekfRmseMeters) / rmseMeters) * 100.0 : 0.0;

  /// Percentage improvement of AI over EKF RMSE
  double get aiImprovementPercentVsEkf =>
      ekfRmseMeters > 0.0001 ? ((ekfRmseMeters - aiRmseMeters) / ekfRmseMeters) * 100.0 : 0.0;

  /// Percentage improvement of AI over Basic DR RMSE
  double get aiImprovementPercentVsDr =>
      rmseMeters > 0.0001 ? ((rmseMeters - aiRmseMeters) / rmseMeters) * 100.0 : 0.0;
}

class OutageEvaluator {
  const OutageEvaluator();

  /// Runs deterministic replay and outage evaluation simultaneously across
  /// Phase 3 Basic DR, Phase 4 EKF Fusion, and Phase 5 NavGuardian AI.
  OutageEvaluationResult evaluate({
    required LoadedJourney journey,
    required double outageStartSeconds,
    required double outageDurationSeconds,
  }) {
    if (journey.gpsFixes.isEmpty) {
      throw StateError('Cannot evaluate journey without GPS fixes.');
    }

    final drEngine = DeadReckoningEngine();
    final ekfEngine = EkfSensorFusionEngine();

    final allGps = <({double lat, double lon})>[];
    final groundTruth = <({double lat, double lon})>[];
    final deadReckoningPath = <({double lat, double lon})>[];
    final ekfPath = <({double lat, double lon})>[];
    final aiPath = <({double lat, double lon})>[];
    final comparisons = <ComparisonPoint>[];

    final outageEndSeconds = outageStartSeconds + outageDurationSeconds;
    final outageStartMicros = (outageStartSeconds * 1000000).toInt();
    final outageEndMicros = (outageEndSeconds * 1000000).toInt();

    final initialGps = journey.gpsFixes.first;
    drEngine.initializeWithGps(initialGps, monotonicMicros: 0);
    ekfEngine.initializeWithGps(initialGps, monotonicMicros: 0);

    GeoFix lastKnownGpsBeforeOutage = initialGps;
    GeoFix? lastGroundTruthGps;
    var enteredOutage = false;

    // AI accumulated displacement corrections in meters
    var cumAiEastMeters = 0.0;
    var cumAiNorthMeters = 0.0;

    // Last known sensor readings for AI feature vector
    var lastAx = 0.0;
    var lastAy = 0.0;
    var lastAz = 9.81;
    var lastGx = 0.0;
    var lastGy = 0.0;
    var lastGz = 0.0;

    for (final record in journey.chronologicalRecords) {
      final tMicros = record.monotonicMicros;
      final inBlackout = tMicros >= outageStartMicros && tMicros <= outageEndMicros;

      if (record.isGps) {
        final fix = record.fix!;
        allGps.add((lat: fix.latitude, lon: fix.longitude));

        if (tMicros < outageStartMicros) {
          // Normal phase: Feed GPS fixes to both engines
          if (!drEngine.isInitialized) {
            drEngine.initializeWithGps(fix, monotonicMicros: tMicros);
          } else {
            drEngine.addFix(fix);
          }

          if (!ekfEngine.isInitialized) {
            ekfEngine.initializeWithGps(fix, monotonicMicros: tMicros);
          } else {
            ekfEngine.addFix(fix);
          }

          lastKnownGpsBeforeOutage = fix;
        } else if (inBlackout) {
          // CRITICAL: GPS is 100% HIDDEN from ALL engines during blackout!
          enteredOutage = true;
          groundTruth.add((lat: fix.latitude, lon: fix.longitude));
          lastGroundTruthGps = fix;

          final drEst = drEngine.currentEstimate;
          final ekfEst = ekfEngine.currentEstimate;

          // AI corrected geodetic coordinate
          final aiDelta = GeodesyUtils.metersToDeltaLatLon(
            cumAiNorthMeters,
            cumAiEastMeters,
            ekfEst.latitude,
          );
          final aiLat = ekfEst.latitude + aiDelta.deltaLat;
          final aiLon = ekfEst.longitude + aiDelta.deltaLon;

          final drErr = GeodesyUtils.haversineDistanceMeters(
            fix.latitude,
            fix.longitude,
            drEst.latitude,
            drEst.longitude,
          );

          final ekfErr = GeodesyUtils.haversineDistanceMeters(
            fix.latitude,
            fix.longitude,
            ekfEst.latitude,
            ekfEst.longitude,
          );

          final aiErr = GeodesyUtils.haversineDistanceMeters(
            fix.latitude,
            fix.longitude,
            aiLat,
            aiLon,
          );

          comparisons.add(
            ComparisonPoint(
              timestamp: fix.timestamp,
              elapsedSeconds: (tMicros - outageStartMicros) / 1000000.0,
              gpsLat: fix.latitude,
              gpsLon: fix.longitude,
              estimatedLat: drEst.latitude,
              estimatedLon: drEst.longitude,
              errorMeters: drErr,
              ekfLat: ekfEst.latitude,
              ekfLon: ekfEst.longitude,
              ekfErrorMeters: ekfErr,
              aiLat: aiLat,
              aiLon: aiLon,
              aiErrorMeters: aiErr,
            ),
          );
        }
      } else {
        // Sensor sample
        final sample = record.sensor!;
        drEngine.addSensor(sample);
        ekfEngine.addSensor(sample);

        if (sample.kind == SensorKind.accelerometer) {
          lastAx = sample.x;
          lastAy = sample.y;
          lastAz = sample.z;
        } else if (sample.kind == SensorKind.gyroscope) {
          lastGx = sample.x;
          lastGy = sample.y;
          lastGz = sample.z;
        }

        if (inBlackout) {
          // AI predict step correction
          final diag = ekfEngine.diagnostics;
          final aiCorr = AiDriftPredictor.predictResidualStepCorrection(
            ax: lastAx,
            ay: lastAy,
            az: lastAz,
            gx: lastGx,
            gy: lastGy,
            gz: lastGz,
            ekfVx: diag.estimatedSpeedMps * math.cos(diag.estimatedHeadingDegrees * (math.pi / 180.0)),
            ekfVy: diag.estimatedSpeedMps * math.sin(diag.estimatedHeadingDegrees * (math.pi / 180.0)),
            ekfPsiRad: diag.estimatedHeadingDegrees * (math.pi / 180.0),
            isStationary: diag.isStationary,
          );

          // Scaled to sample interval (~20ms = 0.2 of 10Hz step)
          cumAiEastMeters += aiCorr.deltaXEast * 0.2;
          cumAiNorthMeters += aiCorr.deltaYNorth * 0.2;

          final curEkfLat = ekfEngine.currentLatitude;
          final curEkfLon = ekfEngine.currentLongitude;

          final aiDelta = GeodesyUtils.metersToDeltaLatLon(
            cumAiNorthMeters,
            cumAiEastMeters,
            curEkfLat,
          );

          deadReckoningPath.add((
            lat: drEngine.currentLatitude,
            lon: drEngine.currentLongitude,
          ));
          ekfPath.add((
            lat: curEkfLat,
            lon: curEkfLon,
          ));
          aiPath.add((
            lat: curEkfLat + aiDelta.deltaLat,
            lon: curEkfLon + aiDelta.deltaLon,
          ));
        }
      }
    }

    lastGroundTruthGps ??= journey.gpsFixes.last;

    final actualDuration =
        enteredOutage
            ? (lastGroundTruthGps.timestamp
                .difference(lastKnownGpsBeforeOutage.timestamp)
                .inMilliseconds /
                1000.0)
            : outageDurationSeconds;
    final effectiveDuration = actualDuration > 0.1 ? actualDuration : outageDurationSeconds;

    final drFinalEst = drEngine.currentEstimate;
    final ekfFinalEst = ekfEngine.currentEstimate;

    // AI Final estimate
    final aiFinalDelta = GeodesyUtils.metersToDeltaLatLon(
      cumAiNorthMeters,
      cumAiEastMeters,
      ekfFinalEst.latitude,
    );
    final aiFinalEst = GeoFix(
      latitude: ekfFinalEst.latitude + aiFinalDelta.deltaLat,
      longitude: ekfFinalEst.longitude + aiFinalDelta.deltaLon,
      altitudeMeters: ekfFinalEst.altitudeMeters,
      accuracyMeters: ekfFinalEst.accuracyMeters,
      speedMetersPerSecond: ekfFinalEst.speedMetersPerSecond,
      headingDegrees: ekfFinalEst.headingDegrees,
      timestamp: ekfFinalEst.timestamp,
      source: PositionSource.estimated,
    );

    // Calculate Endpoint Errors
    final drEndpointError = GeodesyUtils.haversineDistanceMeters(
      lastGroundTruthGps.latitude,
      lastGroundTruthGps.longitude,
      drFinalEst.latitude,
      drFinalEst.longitude,
    );

    final ekfEndpointError = GeodesyUtils.haversineDistanceMeters(
      lastGroundTruthGps.latitude,
      lastGroundTruthGps.longitude,
      ekfFinalEst.latitude,
      ekfFinalEst.longitude,
    );

    final aiEndpointError = GeodesyUtils.haversineDistanceMeters(
      lastGroundTruthGps.latitude,
      lastGroundTruthGps.longitude,
      aiFinalEst.latitude,
      aiFinalEst.longitude,
    );

    // Calculate RMSE, Mean, and Max Errors for all 3 methods
    var drSumSq = 0.0, drSumErr = 0.0, drMaxErr = drEndpointError;
    var ekfSumSq = 0.0, ekfSumErr = 0.0, ekfMaxErr = ekfEndpointError;
    var aiSumSq = 0.0, aiSumErr = 0.0, aiMaxErr = aiEndpointError;

    if (comparisons.isNotEmpty) {
      for (final p in comparisons) {
        drSumSq += p.errorMeters * p.errorMeters;
        drSumErr += p.errorMeters;
        if (p.errorMeters > drMaxErr) drMaxErr = p.errorMeters;

        final ekfErr = p.ekfErrorMeters ?? 0.0;
        ekfSumSq += ekfErr * ekfErr;
        ekfSumErr += ekfErr;
        if (ekfErr > ekfMaxErr) ekfMaxErr = ekfErr;

        final aiErr = p.aiErrorMeters ?? 0.0;
        aiSumSq += aiErr * aiErr;
        aiSumErr += aiErr;
        if (aiErr > aiMaxErr) aiMaxErr = aiErr;
      }

      final count = comparisons.length;

      return OutageEvaluationResult(
        outageDurationSeconds: outageDurationSeconds,
        actualOutageDurationSeconds: effectiveDuration,
        hiddenGpsPointsCount: count,
        allGpsCoordinates: allGps,
        groundTruthCoordinates: groundTruth,
        outageStartFix: lastKnownGpsBeforeOutage,
        outageEndFix: lastGroundTruthGps,
        comparisonPoints: comparisons,
        // Phase 3 Basic DR
        endpointErrorMeters: drEndpointError,
        rmseMeters: math.sqrt(drSumSq / count),
        meanErrorMeters: drSumErr / count,
        maxErrorMeters: drMaxErr,
        driftRateMps: drEndpointError / effectiveDuration,
        deadReckoningCoordinates: deadReckoningPath,
        estimatedEndFix: drFinalEst,
        // Phase 4 EKF
        ekfCoordinates: ekfPath,
        ekfEstimatedEndFix: ekfFinalEst,
        ekfEndpointErrorMeters: ekfEndpointError,
        ekfRmseMeters: math.sqrt(ekfSumSq / count),
        ekfMeanErrorMeters: ekfSumErr / count,
        ekfMaxErrorMeters: ekfMaxErr,
        ekfDriftRateMps: ekfEndpointError / effectiveDuration,
        ekfDiagnostics: ekfEngine.diagnostics,
        // Phase 5 NavGuardian AI
        aiCoordinates: aiPath,
        aiEstimatedEndFix: aiFinalEst,
        aiEndpointErrorMeters: aiEndpointError,
        aiRmseMeters: math.sqrt(aiSumSq / count),
        aiMeanErrorMeters: aiSumErr / count,
        aiMaxErrorMeters: aiMaxErr,
        aiDriftRateMps: aiEndpointError / effectiveDuration,
      );
    } else {
      return OutageEvaluationResult(
        outageDurationSeconds: outageDurationSeconds,
        actualOutageDurationSeconds: effectiveDuration,
        hiddenGpsPointsCount: 0,
        allGpsCoordinates: allGps,
        groundTruthCoordinates: groundTruth,
        outageStartFix: lastKnownGpsBeforeOutage,
        outageEndFix: lastGroundTruthGps,
        comparisonPoints: [],
        // Phase 3 Basic DR
        endpointErrorMeters: drEndpointError,
        rmseMeters: drEndpointError,
        meanErrorMeters: drEndpointError,
        maxErrorMeters: drEndpointError,
        driftRateMps: drEndpointError / effectiveDuration,
        deadReckoningCoordinates: deadReckoningPath,
        estimatedEndFix: drFinalEst,
        // Phase 4 EKF
        ekfCoordinates: ekfPath,
        ekfEstimatedEndFix: ekfFinalEst,
        ekfEndpointErrorMeters: ekfEndpointError,
        ekfRmseMeters: ekfEndpointError,
        ekfMeanErrorMeters: ekfEndpointError,
        ekfMaxErrorMeters: ekfEndpointError,
        ekfDriftRateMps: ekfEndpointError / effectiveDuration,
        ekfDiagnostics: ekfEngine.diagnostics,
        // Phase 5 NavGuardian AI
        aiCoordinates: aiPath,
        aiEstimatedEndFix: aiFinalEst,
        aiEndpointErrorMeters: aiEndpointError,
        aiRmseMeters: aiEndpointError,
        aiMeanErrorMeters: aiEndpointError,
        aiMaxErrorMeters: aiEndpointError,
        aiDriftRateMps: aiEndpointError / effectiveDuration,
      );
    }
  }
}
