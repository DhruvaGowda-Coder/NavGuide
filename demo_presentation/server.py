"""NavGuardian AI - Full-Stack Web Server & Live Python ML Backend.

Serves a 60-FPS interactive web application on http://localhost:8050
and provides real-time Python ML endpoints powered by the NUANCE Autonomous
Vehicle dataset (nuance_driving_iris_format.csv) and scikit-learn Deep Stacking.

Usage in Antigravity Terminal:
    python demo_presentation/server.py
"""

from __future__ import annotations

import json
import math
import pickle
import subprocess
import sys
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse

curr_dir = Path(__file__).resolve().parent
venv_python = curr_dir.parent / "ml" / ".venv" / "Scripts" / "python.exe"

try:
    import numpy as np
    import pandas as pd
    from sklearn.ensemble import GradientBoostingRegressor, StackingRegressor
    from sklearn.linear_model import RidgeCV
    from sklearn.metrics import (
        accuracy_score,
        f1_score,
        mean_absolute_error,
        mean_squared_error,
        precision_score,
        recall_score,
    )
    from sklearn.neural_network import MLPRegressor
    from sklearn.preprocessing import StandardScaler
except ImportError:
    if venv_python.exists() and Path(sys.executable).resolve() != venv_python.resolve():
        sys.exit(subprocess.call([str(venv_python), __file__, *sys.argv[1:]]))
    raise

DATA_FILE = curr_dir / "data" / "nuance_driving_iris_format.csv"
MODEL_FILE = curr_dir / "models" / "trained_deep_stacking_model.pkl"
WEB_DIR = curr_dir / "web"

FEATURES = [
    "ax", "ay", "az", "acc_norm", "jerk",
    "gx", "gy", "gz", "gyro_norm",
    "mag_x", "mag_y", "mag_z",
    "est_vx", "est_vy", "est_speed", "yaw_angle",
]
TARGETS = ["target_dx", "target_dy"]

# Global cached state in memory for instant 60-FPS web responses
STATE: dict = {}


def build_backend_state(force_retrain: bool = False) -> dict:
    """Loads dataset, trains or loads the Deep Stacking ML models, and computes trajectories."""
    t0 = time.time()
    df = pd.read_csv(DATA_FILE)

    outage_mask = (df["t_sec"] >= 300.0) & (df["t_sec"] <= 330.0)
    train_mask = ~outage_mask

    X_train = df.loc[train_mask, FEATURES].values
    Y_train = df.loc[train_mask, TARGETS].values
    X_outage = df.loc[outage_mask, FEATURES].values
    Y_outage = df.loc[outage_mask, TARGETS].values

    if MODEL_FILE.exists() and not force_retrain:
        with open(MODEL_FILE, "rb") as f:
            saved = pickle.load(f)
        if saved.get("features") != FEATURES:
            raise ValueError("Saved model feature order does not match the current dataset schema.")
        scaler = saved["scaler"]
        deep_mlp = saved["deep_mlp"]
        stack_x = saved["stack_x"]
        stack_y = saved["stack_y"]
        X_outage_s = scaler.transform(X_outage)
        train_time_sec = None
    else:
        scaler = StandardScaler()
        X_train_s = scaler.fit_transform(X_train)
        X_outage_s = scaler.transform(X_outage)

        deep_mlp = MLPRegressor(
            hidden_layer_sizes=(128, 64, 32),
            activation="relu",
            solver="adam",
            alpha=0.01,
            max_iter=250,
            random_state=42,
        )
        deep_mlp.fit(X_train_s, Y_train)

        base_x = [
            ("deep_mlp", MLPRegressor(hidden_layer_sizes=(64, 32), activation="relu", solver="adam", alpha=0.01, max_iter=150, random_state=42)),
            ("grad_boost", GradientBoostingRegressor(n_estimators=40, max_depth=3, random_state=42)),
        ]
        base_y = [
            ("deep_mlp", MLPRegressor(hidden_layer_sizes=(64, 32), activation="relu", solver="adam", alpha=0.01, max_iter=150, random_state=42)),
            ("grad_boost", GradientBoostingRegressor(n_estimators=40, max_depth=3, random_state=42)),
        ]
        stack_x = StackingRegressor(estimators=base_x, final_estimator=RidgeCV(), cv=3).fit(X_train_s, Y_train[:, 0])
        stack_y = StackingRegressor(estimators=base_y, final_estimator=RidgeCV(), cv=3).fit(X_train_s, Y_train[:, 1])

        MODEL_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(MODEL_FILE, "wb") as f:
            pickle.dump(
                {
                    "scaler": scaler,
                    "deep_mlp": deep_mlp,
                    "stack_x": stack_x,
                    "stack_y": stack_y,
                    "features": FEATURES,
                },
                f,
            )
        train_time_sec = round(time.time() - t0, 2)

    pred_mlp = deep_mlp.predict(X_outage_s)
    pred_stack = np.column_stack([stack_x.predict(X_outage_s), stack_y.predict(X_outage_s)])

    # Reconstruct 2D road path and vehicle trajectories during 30s GPS Blackout
    dt = 0.1
    vx = df.loc[outage_mask, "est_vx"].values
    vy = df.loc[outage_mask, "est_vy"].values
    dr_step_x = vx * dt
    dr_step_y = vy * dt

    true_dx = Y_outage[:, 0]
    true_dy = Y_outage[:, 1]

    gt_x = np.cumsum(dr_step_x + true_dx)
    gt_y = np.cumsum(dr_step_y + true_dy)

    noml_x = np.cumsum(dr_step_x)
    noml_y = np.cumsum(dr_step_y)

    mlp_x = np.cumsum(dr_step_x + pred_mlp[:, 0])
    mlp_y = np.cumsum(dr_step_y + pred_mlp[:, 1])

    stack_x_arr = np.cumsum(dr_step_x + pred_stack[:, 0])
    stack_y_arr = np.cumsum(dr_step_y + pred_stack[:, 1])

    err_noml = np.sqrt((gt_x - noml_x) ** 2 + (gt_y - noml_y) ** 2)
    err_mlp = np.sqrt((gt_x - mlp_x) ** 2 + (gt_y - mlp_y) ** 2)
    err_stack = np.sqrt((gt_x - stack_x_arr) ** 2 + (gt_y - stack_y_arr) ** 2)

    endpoint_dr = float(err_noml[-1])
    endpoint_mlp = float(err_mlp[-1])
    endpoint_stack = float(err_stack[-1])

    rmse_dr = float(np.sqrt(np.mean(err_noml**2)))
    rmse_mlp = float(np.sqrt(np.mean(err_mlp**2)))
    rmse_stack = float(np.sqrt(np.mean(err_stack**2)))

    imp_mlp = ((endpoint_dr - endpoint_mlp) / endpoint_dr) * 100.0
    imp_stack = ((endpoint_dr - endpoint_stack) / endpoint_dr) * 100.0

    thresh = 0.15
    true_haz = (np.sqrt(true_dx**2 + true_dy**2) > thresh).astype(int)
    pred_haz = (np.sqrt(pred_stack[:, 0] ** 2 + pred_stack[:, 1] ** 2) > thresh).astype(int)

    step_err = np.sqrt((true_dx - pred_stack[:, 0]) ** 2 + (true_dy - pred_stack[:, 1]) ** 2)

    preview_rows = df.iloc[:12][
        ["t_sec", "ax", "ay", "acc_norm", "jerk", "gz", "est_speed", "yaw_angle", "target_dx", "target_dy"]
    ].round(4).to_dict(orient="records")

    STATE["scaler"] = scaler
    STATE["deep_mlp"] = deep_mlp
    STATE["stack_x"] = stack_x
    STATE["stack_y"] = stack_y
    STATE["X_outage"] = X_outage
    STATE["Y_outage"] = Y_outage

    STATE["payload"] = {
        "dataset": {
            "name": "NUANCE Autonomous Vehicle Benchmark (Northeastern University)",
            "provenance_note": "Dataset attribution follows the bundled upstream source metadata; verify institutional and hardware claims against the original publication before presenting.",
            "sensors": "VectorNav VN-100 9-Axis IMU (40Hz) + USB GNSS RTK GPS (1Hz)",
            "raw_rows": 22936,
            "synced_rows": int(len(df)),
            "train_rows": int(len(X_train)),
            "outage_rows": int(len(X_outage)),
            "duration_sec": float(df["t_sec"].max()),
            "preview": preview_rows,
        },
        "metrics": {
            "endpoint_dr": round(endpoint_dr, 2),
            "endpoint_mlp": round(endpoint_mlp, 2),
            "endpoint_stack": round(endpoint_stack, 2),
            "rmse_dr": round(rmse_dr, 2),
            "rmse_mlp": round(rmse_mlp, 2),
            "rmse_stack": round(rmse_stack, 2),
            "imp_mlp": round(imp_mlp, 1),
            "imp_stack": round(imp_stack, 1),
            "step_mae": round(float(mean_absolute_error(Y_outage, pred_stack)), 4),
            "step_mse": round(float(mean_squared_error(Y_outage, pred_stack)), 6),
            "accuracy": round(float(accuracy_score(true_haz, pred_haz) * 100.0), 2),
            "precision": round(float(precision_score(true_haz, pred_haz, zero_division=0) * 100.0), 2),
            "recall": round(float(recall_score(true_haz, pred_haz, zero_division=0) * 100.0), 2),
            "f1": round(float(f1_score(true_haz, pred_haz, zero_division=0) * 100.0), 2),
            "submeter_acc": round(float(np.mean(step_err <= 1.0) * 100.0), 2),
            "train_time_sec": train_time_sec,
            "model_loaded": bool(MODEL_FILE.exists() and not force_retrain),
        },
        "trajectories": {
            "n_steps": int(len(gt_x)),
            "gt_x": np.round(gt_x, 3).tolist(),
            "gt_y": np.round(gt_y, 3).tolist(),
            "noml_x": np.round(noml_x, 3).tolist(),
            "noml_y": np.round(noml_y, 3).tolist(),
            "mlp_x": np.round(mlp_x, 3).tolist(),
            "mlp_y": np.round(mlp_y, 3).tolist(),
            "stack_x": np.round(stack_x_arr, 3).tolist(),
            "stack_y": np.round(stack_y_arr, 3).tolist(),
            "err_noml": np.round(err_noml, 2).tolist(),
            "err_mlp": np.round(err_mlp, 2).tolist(),
            "err_stack": np.round(err_stack, 2).tolist(),
            "telemetry": np.round(X_outage[:, [0, 1, 3, 4, 7, 14, 15]], 4).tolist(),
            "pred_mlp_dx": np.round(pred_mlp[:, 0], 5).tolist(),
            "pred_mlp_dy": np.round(pred_mlp[:, 1], 5).tolist(),
            "pred_stack_dx": np.round(pred_stack[:, 0], 5).tolist(),
            "pred_stack_dy": np.round(pred_stack[:, 1], 5).tolist(),
            "dr_step_x": np.round(dr_step_x, 5).tolist(),
            "dr_step_y": np.round(dr_step_y, 5).tolist(),
        },
    }
    return STATE["payload"]


class NavGuardianWebHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        # Clean, minimal terminal logs
        pass

    def _send_json(self, data: dict, status: int = 200) -> None:
        raw = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/data":
            self._send_json(STATE["payload"])
            return
        if parsed.path.startswith("/api/"):
            self._send_json({"error": "Unknown API endpoint."}, status=404)
            return

        # Serve web/index.html for root
        index_file = WEB_DIR / "index.html"
        if index_file.exists():
            content = index_file.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_error(404, "Web frontend not found.")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path not in {"/api/retrain", "/api/predict-step"}:
            self._send_json({"error": "Unknown API endpoint."}, status=404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8")) if length > 0 else {}
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send_json({"error": "Request body must contain valid JSON."}, status=400)
            return
        if not isinstance(body, dict):
            self._send_json({"error": "Request body must be a JSON object."}, status=400)
            return

        if parsed.path == "/api/retrain":
            print("[BACKEND] Refitting scikit-learn estimators on the offline dataset...")
            try:
                payload = build_backend_state(force_retrain=True)
            except Exception as exc:
                self._send_json({"error": f"Model retraining failed: {exc}"}, status=500)
                return
            print(f"[BACKEND] Refit complete in {payload['metrics']['train_time_sec']}s!")
            self._send_json(payload)
            return

        if parsed.path == "/api/predict-step":
            if STATE.get("X_outage") is None:
                self._send_json({"error": "Model state has not been initialized."}, status=503)
                return
            try:
                step_idx = int(body.get("step", 100))
            except (TypeError, ValueError, OverflowError):
                self._send_json({"error": "'step' must be an integer."}, status=400)
                return
            X_out = STATE["X_outage"]
            Y_out = STATE["Y_outage"]
            if len(X_out) == 0:
                self._send_json({"error": "The configured evaluation interval contains no samples."}, status=503)
                return
            step_idx = max(0, min(len(X_out) - 1, step_idx))
            raw = X_out[step_idx]
            scaled = STATE["scaler"].transform(raw.reshape(1, -1))

            mlp_pred = STATE["deep_mlp"].predict(scaled)[0]
            sx = float(STATE["stack_x"].predict(scaled)[0])
            sy = float(STATE["stack_y"].predict(scaled)[0])

            self._send_json({
                "step": step_idx,
                "t_sec": round(300.0 + step_idx * 0.1, 1),
                "inputs": {
                    "ax": round(float(raw[0]), 4),
                    "ay": round(float(raw[1]), 4),
                    "az": round(float(raw[2]), 4),
                    "acc_norm": round(float(raw[3]), 4),
                    "jerk": round(float(raw[4]), 4),
                    "gz": round(float(raw[7]), 5),
                    "speed_mps": round(float(raw[14]), 2),
                    "speed_kmh": round(float(raw[14] * 3.6), 1),
                    "yaw_deg": round(math.degrees(float(raw[15])), 1),
                },
                "ground_truth": {
                    "dx": round(float(Y_out[step_idx, 0]), 4),
                    "dy": round(float(Y_out[step_idx, 1]), 4),
                },
                "prediction_mlp": {
                    "dx": round(float(mlp_pred[0]), 4),
                    "dy": round(float(mlp_pred[1]), 4),
                },
                "prediction_stack": {
                    "dx": round(sx, 4),
                    "dy": round(sy, 4),
                },
            })
            return

        self.send_error(404, "Unknown API endpoint")


def main() -> None:
    port = 8050
    print("\n" + "=" * 80)
    print("  NAVGUARDIAN AI - FULL-STACK WEB DASHBOARD & PYTHON ML BACKEND")
    print("=" * 80)
    print("[1/2] Loading NUANCE Autonomous Vehicle Dataset & Deep Stacking Model...")
    build_backend_state(force_retrain=False)
    print("[2/2] Starting Local Web Server at: http://localhost:8050")
    print("      -> Opening http://localhost:8050 in your browser now...")
    print("      -> Press Ctrl+C in this terminal to stop the server.")
    print("=" * 80 + "\n")

    server = HTTPServer(("127.0.0.1", port), NavGuardianWebHandler)
    webbrowser.open(f"http://localhost:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[OK] Server stopped.")
        server.server_close()


if __name__ == "__main__":
    main()

