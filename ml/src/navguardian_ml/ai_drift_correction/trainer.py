"""Training pipeline orchestrator for AI drift correction models."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Any, Tuple

import numpy as np

from navguardian_ml.ai_drift_correction.models import DriftCorrectionModelA, DriftCorrectionModelB


def train_models(
    X: np.ndarray,
    Y: np.ndarray,
    output_dir: str | Path,
    val_split_ratio: float = 0.2,
) -> Tuple[DriftCorrectionModelA, DriftCorrectionModelB, Dict[str, Any]]:
    """Train Model A and Model B using chronological leak-free splitting.

    Parameters
    ----------
    X : np.ndarray
        Feature matrix (N, F).
    Y : np.ndarray
        Target residual step displacements (N, 2).
    output_dir : str or Path
        Directory to store trained artifacts.
    val_split_ratio : float
        Proportion of chronological end samples reserved for validation.
    """
    out_path = Path(output_dir)
    out_path.mkdir(parents=True, exist_ok=True)

    n_samples = len(X)
    split_idx = int(n_samples * (1.0 - val_split_ratio))

    # Strict chronological split (NO random row shuffling to prevent temporal leakage!)
    X_train, X_val = X[:split_idx], X[split_idx:]
    Y_train, Y_val = Y[:split_idx], Y[split_idx:]

    print(f"Dataset Size: {n_samples} samples (10Hz)")
    print(f"Train samples: {len(X_train)} ({len(X_train)*0.1:.1f}s)")
    print(f"Val samples:   {len(X_val)} ({len(X_val)*0.1:.1f}s)")

    # 1. Train Model A (Ridge Baseline)
    model_a = DriftCorrectionModelA(alpha=1.0)
    train_metrics_a = model_a.fit(X_train, Y_train)

    pred_val_a = model_a.predict(X_val)
    val_mse_a = float(np.mean((pred_val_a - Y_val) ** 2))
    val_mae_a = float(np.mean(np.abs(pred_val_a - Y_val)))

    # 2. Train Model B (Temporal Sequence MLP)
    model_b = DriftCorrectionModelB(window_size=5, hidden_layer_sizes=(32, 16), alpha=0.05)
    train_metrics_b = model_b.fit(X_train, Y_train)

    pred_val_b = model_b.predict(X_val)
    val_mse_b = float(np.mean((pred_val_b - Y_val) ** 2))
    val_mae_b = float(np.mean(np.abs(pred_val_b - Y_val)))

    # Save artifacts
    model_a.save(out_path / "model_a_ridge.pkl")
    model_b.save(out_path / "model_b_mlp.pkl")

    metrics_summary = {
        "dataset_samples": n_samples,
        "train_samples": len(X_train),
        "val_samples": len(X_val),
        "features_count": X.shape[1],
        "model_a": {
            "type": "RidgeRegressor",
            "train_mse": train_metrics_a["train_mse"],
            "train_mae": train_metrics_a["train_mae"],
            "val_mse": val_mse_a,
            "val_mae": val_mae_a,
        },
        "model_b": {
            "type": "TemporalMLPRegressor",
            "train_mse": train_metrics_b["train_mse"],
            "train_mae": train_metrics_b["train_mae"],
            "val_mse": val_mse_b,
            "val_mae": val_mae_b,
        },
    }

    with open(out_path / "training_metrics.json", "w", encoding="utf-8") as f:
        json.dump(metrics_summary, f, indent=2)

    return model_a, model_b, metrics_summary
