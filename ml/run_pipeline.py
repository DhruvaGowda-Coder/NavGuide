"""Master CLI script to execute Phase 5 AI/ML pipeline end-to-end.

Usage:
  python ml/run_pipeline.py
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

# Ensure src/navguardian_ml is in path
ml_root = Path(__file__).parent
sys.path.insert(0, str(ml_root / "src"))

from navguardian_ml.sensor_preprocessing.dataset_loader import load_journey_directory
from navguardian_ml.sensor_preprocessing.feature_extractor import FeatureExtractor
from navguardian_ml.ai_drift_correction.trainer import train_models
from navguardian_ml.evaluation.evaluator import evaluate_3way


def main():
    print("\n" + "=" * 65)
    print("      NAVGUARDIAN AI: PHASE 5 MACHINE LEARNING PIPELINE")
    print("=" * 65)

    # 1. Dataset location
    benchmark_path = ml_root / "data" / "journey_extended_benchmark"
    poc_path = ml_root / "data" / "journey_20260908_125527"
    journey_path = benchmark_path if benchmark_path.exists() else poc_path

    if not journey_path.exists():
        print(f"[ERROR] Journey directory not found: {journey_path}")
        sys.exit(1)

    print(f"\n[1] Loading journey dataset from: {journey_path.name}")
    dataset = load_journey_directory(journey_path, target_dt_sec=0.1)
    print(f"    - Duration: {dataset.duration_seconds}s ({len(dataset.df):,} synchronized 10Hz steps)")
    print(f"    - Anchor Origin: ({dataset.lat0:.6f}, {dataset.lon0:.6f})")

    # 2. Feature Extraction & EKF Simulation
    print("\n[2] Running feature engineering & EKF simulation...")
    extractor = FeatureExtractor()
    if "extended" in journey_path.name:
        outage_start = 120.0
        outage_end = 150.0  # 30-second tunnel blackout at 50 km/h
    else:
        outage_start = 2.0
        outage_end = 12.0
    df_feat, X, Y = extractor.extract_features_and_targets(
        dataset.df,
        outage_start_sec=outage_start,
        outage_end_sec=outage_end,
    )
    print(f"    - Feature Matrix X shape: {X.shape}")
    print(f"    - Target Residual Y shape: {Y.shape}")

    # 3. Model Training
    artifacts_dir = (ml_root / "artifacts").resolve()
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    (artifacts_dir / "plots").mkdir(parents=True, exist_ok=True)
    print(f"\n[3] Training AI Drift Correction Models (Output: {artifacts_dir})...")
    model_a, model_b, train_metrics = train_models(X, Y, output_dir=artifacts_dir, val_split_ratio=0.2)

    print("\n    Model A (Ridge Baseline):")
    print(f"      Train MSE: {train_metrics['model_a']['train_mse']:.6f}")
    print(f"      Val MSE:   {train_metrics['model_a']['val_mse']:.6f}")
    print(f"      Val MAE:   {train_metrics['model_a']['val_mae']:.6f} m")

    print("\n    Model B (Temporal Sequence MLP):")
    print(f"      Train MSE: {train_metrics['model_b']['train_mse']:.6f}")
    print(f"      Val MSE:   {train_metrics['model_b']['val_mse']:.6f}")
    print(f"      Val MAE:   {train_metrics['model_b']['val_mae']:.6f} m")

    # Select Model B (Temporal Sequence MLP) as primary deep temporal model
    selected_model = model_b
    selected_name = "Model B (Temporal Sequence MLP Neural Network)"
    print(f"\n    -> Selected for Outage Evaluation: {selected_name}")

    # 4. 3-Way Outage Evaluation
    print(f"\n[4] Executing 3-Way Blackout Evaluation ({outage_end - outage_start:.1f}s window)...")
    eval_results = evaluate_3way(
        df_feat=df_feat,
        model=selected_model,
        outage_start_sec=outage_start,
        outage_end_sec=outage_end,
        output_dir=artifacts_dir,
    )

    m_dr = eval_results["basic_dr"]
    m_ekf = eval_results["ekf"]
    m_ai = eval_results["ai_corrected"]

    print("\n" + "-" * 65)
    print("             3-WAY SIMULATED OUTAGE BENCHMARK RESULTS")
    print("-" * 65)
    print(f"Outage Duration: {eval_results['outage_duration_seconds']:.1f}s")
    print(f"{'Metric':<22} | {'Basic DR (P3)':<13} | {'EKF Fusion (P4)':<15} | {'NavGuardian AI (P5)':<15}")
    print("-" * 65)
    print(f"{'Endpoint Error':<22} | {m_dr['endpoint_error_m']:>11.2f}m | {m_ekf['endpoint_error_m']:>13.2f}m | {m_ai['endpoint_error_m']:>17.2f}m")
    print(f"{'RMSE':<22} | {m_dr['rmse_m']:>11.2f}m | {m_ekf['rmse_m']:>13.2f}m | {m_ai['rmse_m']:>17.2f}m")
    print(f"{'Mean Position Error':<22} | {m_dr['mean_error_m']:>11.2f}m | {m_ekf['mean_error_m']:>13.2f}m | {m_ai['mean_error_m']:>17.2f}m")
    print(f"{'Max Position Error':<22} | {m_dr['max_error_m']:>11.2f}m | {m_ekf['max_error_m']:>13.2f}m | {m_ai['max_error_m']:>17.2f}m")
    print(f"{'Drift Rate':<22} | {m_dr['drift_rate_mps']:>9.3f} m/s | {m_ekf['drift_rate_mps']:>11.3f} m/s | {m_ai['drift_rate_mps']:>15.3f} m/s")
    print("-" * 65)
    print(f"AI vs Basic DR RMSE Improvement: {eval_results['ai_improvement_percent_vs_dr']:+.1f}%")
    print(f"AI vs EKF RMSE Improvement:      {eval_results['ai_improvement_percent_vs_ekf']:+.1f}%")
    print("=" * 65)

    # 5. Copy plots to conversation artifact directories for UI display
    brain_dir = Path(os.environ.get("USERPROFILE", "")) / ".gemini" / "antigravity-ide" / "brain"
    target_convs = ["d3cf5866-a3bc-4d7a-ad55-a8d9bd01df58", "8926725c-4a18-4a65-8586-2ddf08f935fb"]
    for cid in target_convs:
        dest_dir = brain_dir / cid
        if dest_dir.exists():
            for plot_name in ["trajectory_comparison.png", "error_over_time.png", "metrics_bar_chart.png"]:
                src_file = artifacts_dir / "plots" / plot_name
                if src_file.exists():
                    shutil.copy2(src_file, dest_dir / plot_name)
            print(f"[5] Publication plots copied to artifact folder: {dest_dir.name}")


if __name__ == "__main__":
    main()
