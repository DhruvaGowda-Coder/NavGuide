"""Model architectures for AI-based Dead Reckoning / EKF drift correction.

Implements:
1. Model A: Classical Regularized Multi-Output Ridge Baseline.
2. Model B: Temporal Sequence MLP Model (over a multi-step historical window).
"""

from __future__ import annotations

import pickle
from pathlib import Path
from typing import Tuple, Dict, Any

import numpy as np
from sklearn.linear_model import Ridge
from sklearn.multioutput import MultiOutputRegressor
from sklearn.neural_network import MLPRegressor
from sklearn.preprocessing import StandardScaler


class DriftCorrectionModelA:
    """Model A: Classical Regularized Ridge Regressor Baseline."""

    def __init__(self, alpha: float = 1.0):
        self.alpha = alpha
        self.scaler = StandardScaler()
        self.regressor = MultiOutputRegressor(Ridge(alpha=alpha))
        self.is_fitted = False

    def fit(self, X: np.ndarray, Y: np.ndarray) -> Dict[str, float]:
        """Fit model on feature matrix X and target residual displacements Y."""
        X_scaled = self.scaler.fit_transform(X)
        self.regressor.fit(X_scaled, Y)
        self.is_fitted = True

        pred = self.regressor.predict(X_scaled)
        mse = float(np.mean((pred - Y) ** 2))
        mae = float(np.mean(np.abs(pred - Y)))
        return {"train_mse": mse, "train_mae": mae}

    def predict(self, X: np.ndarray) -> np.ndarray:
        """Predict residual step correction [delta_x, delta_y]."""
        if not self.is_fitted:
            raise RuntimeError("Model A must be fitted before predict.")
        X_scaled = self.scaler.transform(X)
        return self.regressor.predict(X_scaled)

    def save(self, filepath: str | Path) -> None:
        path = Path(filepath)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "wb") as f:
            pickle.dump(
                {
                    "type": "ModelA_Ridge",
                    "alpha": self.alpha,
                    "scaler": self.scaler,
                    "regressor": self.regressor,
                },
                f,
            )

    @classmethod
    def load(cls, filepath: str | Path) -> DriftCorrectionModelA:
        with open(filepath, "rb") as f:
            data = pickle.load(f)
        model = cls(alpha=data["alpha"])
        model.scaler = data["scaler"]
        model.regressor = data["regressor"]
        model.is_fitted = True
        return model


class DriftCorrectionModelB:
    """Model B: Temporal Window Multi-Layer Perceptron (Sequence Baseline)."""

    def __init__(self, window_size: int = 5, hidden_layer_sizes: Tuple[int, ...] = (32, 16), alpha: float = 0.05):
        self.window_size = window_size
        self.hidden_layer_sizes = hidden_layer_sizes
        self.alpha = alpha
        self.scaler = StandardScaler()
        self.mlp = MLPRegressor(
            hidden_layer_sizes=hidden_layer_sizes,
            activation="relu",
            solver="adam",
            alpha=alpha,
            max_iter=500,
            random_state=42,
        )
        self.is_fitted = False

    def _create_temporal_windows(self, X: np.ndarray) -> np.ndarray:
        """Construct sliding historical window for each sample."""
        n, f = X.shape
        w = self.window_size
        X_win = np.zeros((n, w * f))
        for i in range(n):
            start = max(0, i - w + 1)
            chunk = X[start : i + 1]
            if len(chunk) < w:
                pad = np.repeat(chunk[0:1], w - len(chunk), axis=0)
                chunk = np.vstack([pad, chunk])
            X_win[i] = chunk.flatten()
        return X_win

    def fit(self, X: np.ndarray, Y: np.ndarray) -> Dict[str, float]:
        """Fit temporal sequence model."""
        X_win = self._create_temporal_windows(X)
        X_scaled = self.scaler.fit_transform(X_win)
        self.mlp.fit(X_scaled, Y)
        self.is_fitted = True

        pred = self.mlp.predict(X_scaled)
        mse = float(np.mean((pred - Y) ** 2))
        mae = float(np.mean(np.abs(pred - Y)))
        return {"train_mse": mse, "train_mae": mae}

    def predict(self, X: np.ndarray) -> np.ndarray:
        """Predict residual step correction using temporal window context."""
        if not self.is_fitted:
            raise RuntimeError("Model B must be fitted before predict.")
        X_win = self._create_temporal_windows(X)
        X_scaled = self.scaler.transform(X_win)
        return self.mlp.predict(X_scaled)

    def save(self, filepath: str | Path) -> None:
        path = Path(filepath)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "wb") as f:
            pickle.dump(
                {
                    "type": "ModelB_TemporalMLP",
                    "window_size": self.window_size,
                    "hidden_layer_sizes": self.hidden_layer_sizes,
                    "alpha": self.alpha,
                    "scaler": self.scaler,
                    "mlp": self.mlp,
                },
                f,
            )

    @classmethod
    def load(cls, filepath: str | Path) -> DriftCorrectionModelB:
        with open(filepath, "rb") as f:
            data = pickle.load(f)
        model = cls(
            window_size=data["window_size"],
            hidden_layer_sizes=data["hidden_layer_sizes"],
            alpha=data["alpha"],
        )
        model.scaler = data["scaler"]
        model.mlp = data["mlp"]
        model.is_fitted = True
        return model
