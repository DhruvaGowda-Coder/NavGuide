"""3-Way Outage Evaluation and Benchmarking module.

Evaluates:
1. Phase 3 Basic Dead Reckoning
2. Phase 4 EKF Sensor Fusion
3. Phase 5 NavGuardian AI Correction
against strictly hidden Ground Truth GPS fixes. Generates comparison metrics
and publication-quality trajectory/error figures.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Any, List

import matplotlib
matplotlib.use("Agg")  # Non-interactive headless backend
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


def evaluate_3way(
    df_feat: pd.DataFrame,
    model,
    outage_start_sec: float = 2.0,
    outage_end_sec: float = 12.0,
    output_dir: str | Path = "ml/artifacts",
) -> Dict[str, Any]:
    """Execute 3-way evaluation during simulated GPS outage.

    Parameters
    ----------
    df_feat : pd.DataFrame
        Augmented dataframe containing 't_sec', 'gps_x', 'gps_y', 'ekf_x', 'ekf_y', etc.
    model : trained AI model
        Object with .predict(X) method.
    outage_start_sec : float
        Outage start in seconds.
    outage_end_sec : float
        Outage end in seconds.
    output_dir : str or Path
        Directory to save evaluation plots and json summary.
    """
    out_path = Path(output_dir)
    plots_path = out_path / "plots"
    plots_path.mkdir(parents=True, exist_ok=True)

    dt = 0.1
    mask_outage = (df_feat["t_sec"] >= outage_start_sec) & (df_feat["t_sec"] <= outage_end_sec)
    df_outage = df_feat[mask_outage].copy()
    actual_duration = float(df_outage["t_sec"].iloc[-1] - df_outage["t_sec"].iloc[0]) if len(df_outage) > 0 else (outage_end_sec - outage_start_sec)

    # 1. Ground Truth GPS during outage
    true_x = df_outage["gps_x"].values
    true_y = df_outage["gps_y"].values

    # 2. Method 1: Basic Dead Reckoning (ZUPT-clamped velocity integration)
    dr_x = np.zeros(len(df_outage))
    dr_y = np.zeros(len(df_outage))
    cur_dr_x = df_outage["gps_x"].iloc[0]
    cur_dr_y = df_outage["gps_y"].iloc[0]
    cur_dr_vx = 0.0
    cur_dr_vy = 0.0

    for i in range(len(df_outage)):
        is_stat = df_outage["is_stationary"].iloc[i] > 0.5
        if is_stat:
            cur_dr_vx = 0.0
            cur_dr_vy = 0.0
        else:
            # Kinematic acceleration step
            cur_dr_x += cur_dr_vx * dt
            cur_dr_y += cur_dr_vy * dt
            cur_dr_vx *= 0.98
            cur_dr_vy *= 0.98
        dr_x[i] = cur_dr_x
        dr_y[i] = cur_dr_y

    # 3. Method 2: EKF Sensor Fusion (Kinematic state without GPS)
    ekf_x = df_outage["ekf_x"].values
    ekf_y = df_outage["ekf_y"].values

    # 4. Method 3: NavGuardian AI Correction
    feature_cols = [
        "ax",
        "ay",
        "az",
        "acc_norm",
        "jerk",
        "gx",
        "gy",
        "gz",
        "gyro_norm",
        "ekf_vx",
        "ekf_vy",
        "ekf_speed",
        "ekf_psi",
        "is_stationary",
    ]
    X_outage = df_outage[feature_cols].values
    pred_corrections = model.predict(X_outage)  # [delta_x_corr, delta_y_corr]

    # Accumulate AI corrections on top of EKF
    ai_x = np.zeros(len(df_outage))
    ai_y = np.zeros(len(df_outage))
    cum_corr_x = 0.0
    cum_corr_y = 0.0

    for i in range(len(df_outage)):
        cum_corr_x += pred_corrections[i, 0]
        cum_corr_y += pred_corrections[i, 1]
        ai_x[i] = ekf_x[i] + cum_corr_x
        ai_y[i] = ekf_y[i] + cum_corr_y

    # Compute Euclidean distance errors over time
    err_dr = np.sqrt((dr_x - true_x) ** 2 + (dr_y - true_y) ** 2)
    err_ekf = np.sqrt((ekf_x - true_x) ** 2 + (ekf_y - true_y) ** 2)
    err_ai = np.sqrt((ai_x - true_x) ** 2 + (ai_y - true_y) ** 2)

    # Metrics computation helper
    def calc_metrics(err_arr: np.ndarray) -> Dict[str, float]:
        endpoint = float(err_arr[-1])
        rmse = float(np.sqrt(np.mean(err_arr**2)))
        mean_err = float(np.mean(err_arr))
        max_err = float(np.max(err_arr))
        drift_rate = float(endpoint / max(actual_duration, 0.1))
        return {
            "endpoint_error_m": endpoint,
            "rmse_m": rmse,
            "mean_error_m": mean_err,
            "max_error_m": max_err,
            "drift_rate_mps": drift_rate,
        }

    m_dr = calc_metrics(err_dr)
    m_ekf = calc_metrics(err_ekf)
    m_ai = calc_metrics(err_ai)

    # Improvement percentages
    improve_vs_dr = ((m_dr["rmse_m"] - m_ai["rmse_m"]) / max(m_dr["rmse_m"], 1e-4)) * 100.0
    improve_vs_ekf = ((m_ekf["rmse_m"] - m_ai["rmse_m"]) / max(m_ekf["rmse_m"], 1e-4)) * 100.0

    results = {
        "outage_duration_seconds": actual_duration,
        "outage_samples": len(df_outage),
        "basic_dr": m_dr,
        "ekf": m_ekf,
        "ai_corrected": m_ai,
        "ai_improvement_percent_vs_dr": float(improve_vs_dr),
        "ai_improvement_percent_vs_ekf": float(improve_vs_ekf),
    }

    # Save metrics json
    with open(out_path / "evaluation_results.json", "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    # Generate Publication Plots
    times = df_outage["t_sec"].values - df_outage["t_sec"].iloc[0]

    # Plot 1: Error Over Time
    fig, ax = plt.subplots(figsize=(8, 4.5), dpi=150)
    ax.plot(times, err_dr, label=f"Basic DR (RMSE: {m_dr['rmse_m']:.2f}m)", color="#ff8f00", linewidth=2.0)
    ax.plot(times, err_ekf, label=f"EKF Fusion (RMSE: {m_ekf['rmse_m']:.2f}m)", color="#8e24aa", linewidth=2.0)
    ax.plot(times, err_ai, label=f"NavGuardian AI (RMSE: {m_ai['rmse_m']:.2f}m)", color="#00897b", linewidth=2.5, linestyle="--")
    ax.set_title(f"Position Error vs Time During {actual_duration:.1f}s GPS Blackout", fontsize=12, fontweight="bold")
    ax.set_xlabel("Elapsed Blackout Time (seconds)", fontsize=10)
    ax.set_ylabel("Position Error (meters)", fontsize=10)
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend(loc="upper left")
    plt.tight_layout()
    fig.savefig(plots_path / "error_over_time.png")
    plt.close(fig)

    # Plot 2: 2D Trajectory Plot
    fig, ax = plt.subplots(figsize=(6, 6), dpi=150)
    ax.plot(true_x, true_y, label="Ground Truth GPS", color="#1976d2", linewidth=2.5, marker="o", markersize=4)
    ax.plot(dr_x, dr_y, label="Basic DR", color="#ff8f00", linewidth=2.0, linestyle="-.")
    ax.plot(ekf_x, ekf_y, label="EKF Fusion", color="#8e24aa", linewidth=2.0)
    ax.plot(ai_x, ai_y, label="NavGuardian AI", color="#00897b", linewidth=2.0, linestyle="--")

    # Mark endpoints
    ax.scatter([true_x[0]], [true_y[0]], color="green", s=80, zorder=5, label="Outage Start")
    ax.scatter([true_x[-1]], [true_y[-1]], color="#1976d2", s=80, zorder=5, label="GPS End")
    ax.scatter([dr_x[-1]], [dr_y[-1]], color="#ff8f00", s=80, marker="x", zorder=5, label="DR End")
    ax.scatter([ekf_x[-1]], [ekf_y[-1]], color="#8e24aa", s=80, marker="s", zorder=5, label="EKF End")
    ax.scatter([ai_x[-1]], [ai_y[-1]], color="#00897b", s=90, marker="^", zorder=5, label="AI End")

    ax.set_title(f"Trajectory Comparison ({actual_duration:.1f}s Outage)", fontsize=12, fontweight="bold")
    ax.set_xlabel("East Displacement (meters)", fontsize=10)
    ax.set_ylabel("North Displacement (meters)", fontsize=10)
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend(fontsize=8, loc="best")
    plt.tight_layout()
    fig.savefig(plots_path / "trajectory_comparison.png")
    plt.close(fig)

    # Plot 3: Metrics Comparison Bar Chart
    fig, ax = plt.subplots(figsize=(7, 4), dpi=150)
    methods = ["Basic DR", "EKF Fusion", "NavGuardian AI"]
    rmse_vals = [m_dr["rmse_m"], m_ekf["rmse_m"], m_ai["rmse_m"]]
    endpoint_vals = [m_dr["endpoint_error_m"], m_ekf["endpoint_error_m"], m_ai["endpoint_error_m"]]

    x = np.arange(len(methods))
    width = 0.35
    ax.bar(x - width / 2, rmse_vals, width, label="RMSE (m)", color=["#ffb74d", "#ba68c8", "#4db6ac"])
    ax.bar(x + width / 2, endpoint_vals, width, label="Endpoint Error (m)", color=["#f57c00", "#7b1fa2", "#00796b"])

    ax.set_ylabel("Error (meters)", fontsize=10)
    ax.set_title("Quantitative Comparison: Basic DR vs EKF vs NavGuardian AI", fontsize=11, fontweight="bold")
    ax.set_xticks(x)
    ax.set_xticklabels(methods, fontsize=10, fontweight="bold")
    ax.legend()
    ax.grid(True, axis="y", linestyle=":", alpha=0.6)
    plt.tight_layout()
    fig.savefig(plots_path / "metrics_bar_chart.png")
    plt.close(fig)

    return results
