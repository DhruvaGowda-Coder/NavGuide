// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/device/dead_reckoning/outage_evaluator.dart';
import 'package:navguardian_ai/device/storage/journey_reader.dart';

void main() {
  test('Evaluate Real Physical Phone Journey (journey_20260908_125527)', () async {
    const journeyPath =
        r'C:\Users\dhruv\.gemini\antigravity-ide\brain\8926725c-4a18-4a65-8586-2ddf08f935fb\scratch\journey_20260908_125527';
    final dir = Directory(journeyPath);
    if (!await dir.exists()) {
      return;
    }

    final reader = const JourneyReader();
    final journey = await reader.loadJourney(journeyPath);

    print('\n================ REAL JOURNEY EVALUATION: DR vs EKF ================');
    print('Journey ID: ${journey.metadata.id}');
    print('Total duration: ${journey.metadata.durationSeconds}s');
    print('GPS fixes: ${journey.gpsFixes.length}');
    print('Accelerometer samples: ${journey.accelSamples.length}');
    print('Gyroscope samples: ${journey.gyroSamples.length}');
    print('Magnetometer samples: ${journey.magSamples.length}');

    final evaluator = const OutageEvaluator();

    // 1. Test 10s Outage (from t=2s to 12s)
    final res10 = evaluator.evaluate(
      journey: journey,
      outageStartSeconds: 2.0,
      outageDurationSeconds: 10.0,
    );

    print('\n--- [10-Second Simulated Blackout] ---');
    print('Outage duration tested: ${res10.actualOutageDurationSeconds.toStringAsFixed(1)}s');
    print('Hidden GPS points: ${res10.hiddenGpsPointsCount}');
    print('Basic DR (P3) Endpoint Error: ${res10.endpointErrorMeters.toStringAsFixed(2)} m');
    print('EKF Fusion (P4) Endpoint Error: ${res10.ekfEndpointErrorMeters.toStringAsFixed(2)} m');
    print('AI Drift (P5) Endpoint Error: ${res10.aiEndpointErrorMeters.toStringAsFixed(2)} m');
    print('Basic DR RMSE: ${res10.rmseMeters.toStringAsFixed(2)} m');
    print('EKF Fusion RMSE: ${res10.ekfRmseMeters.toStringAsFixed(2)} m');
    print('AI Drift RMSE: ${res10.aiRmseMeters.toStringAsFixed(2)} m');
    print('EKF vs DR RMSE Improvement: ${res10.rmseImprovementPercent.toStringAsFixed(1)}%');
    print('AI vs DR RMSE Improvement: ${res10.aiRmseImprovementPercentVsDr.toStringAsFixed(1)}%');
    print('AI vs EKF RMSE Improvement: ${res10.aiRmseImprovementPercentVsEkf.toStringAsFixed(1)}%');
    print('EKF Gyro Bias Estimate: ${res10.ekfDiagnostics.gyroBiasDegPerSec.toStringAsFixed(3)} °/s');
    print('EKF Pos Uncertainty (σ): ${res10.ekfDiagnostics.positionStdDevMeters.toStringAsFixed(2)} m');
    print('Magnetometer Anomalies: ${res10.ekfDiagnostics.magAnomaliesCount}');

    // 2. Test Full Journey Outage (~18s)
    final resMax = evaluator.evaluate(
      journey: journey,
      outageStartSeconds: 0.0,
      outageDurationSeconds: 18.0,
    );

    print('\n--- [Full Journey Outage (~18s)] ---');
    print('Outage duration tested: ${resMax.actualOutageDurationSeconds.toStringAsFixed(1)}s');
    print('Hidden GPS points: ${resMax.hiddenGpsPointsCount}');
    print('Basic DR (P3) Endpoint Error: ${resMax.endpointErrorMeters.toStringAsFixed(2)} m');
    print('EKF Fusion (P4) Endpoint Error: ${resMax.ekfEndpointErrorMeters.toStringAsFixed(2)} m');
    print('AI Drift (P5) Endpoint Error: ${resMax.aiEndpointErrorMeters.toStringAsFixed(2)} m');
    print('Basic DR RMSE: ${resMax.rmseMeters.toStringAsFixed(2)} m');
    print('EKF Fusion RMSE: ${resMax.ekfRmseMeters.toStringAsFixed(2)} m');
    print('AI Drift RMSE: ${resMax.aiRmseMeters.toStringAsFixed(2)} m');
    print('EKF vs DR RMSE Improvement: ${resMax.rmseImprovementPercent.toStringAsFixed(1)}%');
    print('AI vs DR RMSE Improvement: ${resMax.aiRmseImprovementPercentVsDr.toStringAsFixed(1)}%');
    print('AI vs EKF RMSE Improvement: ${resMax.aiRmseImprovementPercentVsEkf.toStringAsFixed(1)}%');
    print('EKF Pos Uncertainty (σ): ${resMax.ekfDiagnostics.positionStdDevMeters.toStringAsFixed(2)} m');
    print('===================================================================\n');

    expect(res10.endpointErrorMeters, isNonNegative);
    expect(res10.ekfEndpointErrorMeters, isNonNegative);
    expect(res10.aiEndpointErrorMeters, isNonNegative);
    expect(resMax.endpointErrorMeters, isNonNegative);
    expect(resMax.ekfEndpointErrorMeters, isNonNegative);
    expect(resMax.aiEndpointErrorMeters, isNonNegative);
  });
}
