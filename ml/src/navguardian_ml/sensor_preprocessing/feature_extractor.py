"""Feature extraction and supervised target generation module.

Computes EKF estimates, kinematic features, and residual positioning error targets
(delta_true - delta_ekf) for offline AI/ML training.
"""

from __future__ import annotations

import math
from typing import Tuple, List

import numpy as np
import pandas as pd


class FeatureExtractor:
    """Extracts kinematic features and residual correction targets."""

    def __init__(self, gravity: float = 9.80665, zupt_thresh: float = 0.05):
        self.gravity = gravity
        self.zupt_thresh = zupt_thresh

    def extract_features_and_targets(
        self,
        df: pd.DataFrame,
        outage_start_sec: float = 2.0,
        outage_end_sec: float = 12.0,
    ) -> Tuple[pd.DataFrame, np.ndarray, np.ndarray]:
        """Run EKF simulation, build feature matrix X, and ground-truth targets Y.

        Parameters
        ----------
        df : pd.DataFrame
            Synchronized 10Hz journey dataframe.
        outage_start_sec : float
            Simulated GPS outage start time in seconds.
        outage_end_sec : float
            Simulated GPS outage end time in seconds.

        Returns
        -------
        df_processed : pd.DataFrame
            Augmented dataframe with EKF, features, and targets.
        X : np.ndarray
            Feature matrix (N, num_features).
        Y : np.ndarray
            Target residual displacements [target_dx, target_dy] in meters.
        """
        n = len(df)
        dt = 0.1  # 10Hz uniform

        # Arrays to accumulate
        ekf_x = np.zeros(n)
        ekf_y = np.zeros(n)
        ekf_vx = np.zeros(n)
        ekf_vy = np.zeros(n)
        ekf_psi = np.zeros(n)
        ekf_bw = np.zeros(n)
        is_stat = np.zeros(n, dtype=bool)

        # Initialize with first GPS fix
        cur_x = df["gps_x"].iloc[0]
        cur_y = df["gps_y"].iloc[0]
        cur_vx = 0.0
        cur_vy = 0.0
        cur_psi = math.radians(df["gps_bearing"].iloc[0])
        cur_bw = 0.0
        cur_pitch = 0.0
        cur_roll = 0.0

        # Moving window for ZUPT
        norm_window: List[float] = []

        for i in range(n):
            t = df["t_sec"].iloc[i]
            in_outage = outage_start_sec <= t <= outage_end_sec

            ax = df["ax"].iloc[i]
            ay = df["ay"].iloc[i]
            az = df["az"].iloc[i]
            norm_a = math.sqrt(ax * ax + ay * ay + az * az)

            norm_window.append(norm_a)
            if len(norm_window) > 15:
                norm_window.pop(0)

            # Check stationary
            mean_a = float(np.mean(norm_window))
            std_a = float(np.std(norm_window))
            stationary = std_a < self.zupt_thresh and abs(mean_a - self.gravity) < 1.0
            is_stat[i] = stationary

            # Gravity leveling
            if abs(norm_a - self.gravity) < 1.8:
                inst_pitch = math.atan2(ax, math.sqrt(ay * ay + az * az))
                inst_roll = math.atan2(-ay, az)
                cur_pitch = 0.94 * cur_pitch + 0.06 * inst_pitch
                cur_roll = 0.94 * cur_roll + 0.06 * inst_roll

            # Gyro prediction
            gz = df["gz"].iloc[i]
            gy = df["gy"].iloc[i]
            cos_p = math.cos(cur_pitch)
            yaw_rate = (gy * math.sin(cur_roll) + gz * math.cos(cur_roll)) / cos_p if abs(cos_p) > 0.05 else gz
            unbiased_yaw = yaw_rate - cur_bw
            cur_psi = (cur_psi + unbiased_yaw * dt + math.pi) % (2 * math.pi) - math.pi

            # Accel rotation to North-East navigation frame
            # ay = forward acceleration, ax = lateral acceleration
            cp, sp = math.cos(cur_pitch), math.sin(cur_pitch)
            cr, sr = math.cos(cur_roll), math.sin(cur_roll)
            ch, sh = math.cos(cur_psi), math.sin(cur_psi)

            a_fwd = ay - self.gravity * sp
            a_lat = ax + self.gravity * sr
            r_north = a_fwd * ch - a_lat * sh
            r_east = a_fwd * sh + a_lat * ch

            if stationary:
                cur_vx *= 0.1
                cur_vy *= 0.1
            else:
                cur_x += cur_vx * dt + 0.5 * r_east * dt * dt
                cur_y += cur_vy * dt + 0.5 * r_north * dt * dt
                cur_vx += r_east * dt
                cur_vy += r_north * dt

            # GPS update (ONLY if not in blackout!)
            if not in_outage:
                gps_x = df["gps_x"].iloc[i]
                gps_y = df["gps_y"].iloc[i]
                # Filter correction pull
                cur_x = 0.8 * cur_x + 0.2 * gps_x
                cur_y = 0.8 * cur_y + 0.2 * gps_y

            ekf_x[i] = cur_x
            ekf_y[i] = cur_y
            ekf_vx[i] = cur_vx
            ekf_vy[i] = cur_vy
            ekf_psi[i] = cur_psi
            ekf_bw[i] = cur_bw

        # Compute step displacements
        true_dx = np.diff(df["gps_x"].values, prepend=df["gps_x"].iloc[0])
        true_dy = np.diff(df["gps_y"].values, prepend=df["gps_y"].iloc[0])

        ekf_dx = np.diff(ekf_x, prepend=ekf_x[0])
        ekf_dy = np.diff(ekf_y, prepend=ekf_y[0])

        # Target residual: true displacement minus EKF displacement
        target_dx = true_dx - ekf_dx
        target_dy = true_dy - ekf_dy

        # Extract features
        acc_norm = np.sqrt(df["ax"] ** 2 + df["ay"] ** 2 + df["az"] ** 2)
        jerk = np.abs(np.diff(acc_norm, prepend=acc_norm.iloc[0])) / dt
        gyro_norm = np.sqrt(df["gx"] ** 2 + df["gy"] ** 2 + df["gz"] ** 2)

        feat_df = pd.DataFrame(
            {
                "t_sec": df["t_sec"],
                "ax": df["ax"],
                "ay": df["ay"],
                "az": df["az"],
                "acc_norm": acc_norm,
                "jerk": jerk,
                "gx": df["gx"],
                "gy": df["gy"],
                "gz": df["gz"],
                "gyro_norm": gyro_norm,
                "ekf_vx": ekf_vx,
                "ekf_vy": ekf_vy,
                "ekf_speed": np.sqrt(ekf_vx**2 + ekf_vy**2),
                "ekf_psi": ekf_psi,
                "is_stationary": is_stat.astype(float),
                "ekf_x": ekf_x,
                "ekf_y": ekf_y,
                "gps_x": df["gps_x"],
                "gps_y": df["gps_y"],
                "target_dx": target_dx,
                "target_dy": target_dy,
            }
        )

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

        X = feat_df[feature_cols].values
        Y = feat_df[["target_dx", "target_dy"]].values

        return feat_df, X, Y
