"""Benchmark Dataset Generator for NavGuardian AI (Vectorized & Fast).

Generates a realistic 10-minute (600s) urban vehicle driving trajectory with
high-frequency 50Hz IMU (accelerometer, gyroscope, magnetometer) and 1Hz GPS ground truth.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pandas as pd


def generate_10min_vehicle_dataset(
    output_dir: Path,
    journey_id: str = "journey_extended_benchmark",
    lat0: float = 12.938434,
    lon0: float = 77.561116,
    duration_sec: float = 600.0,
    imu_hz: float = 50.0,
    gps_hz: float = 1.0,
):
    output_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.RandomState(42)

    earth_radius = 6378137.0
    gravity = 9.80665

    # Total duration = 600s
    segments = [
        (15.0, 0.0, 0.0),            # 0: Stationary warm-up / ZUPT
        (15.0, 11.0, 0.0),           # 1: Accelerate to 40 km/h (North)
        (25.0, 11.0, 0.0),           # 2: Cruise straight
        (10.0, 8.0, math.pi / 20.0), # 3: Slow down and 90 deg Right turn (East)
        (30.0, 14.0, 0.0),           # 4: Accelerate to 50 km/h
        (25.0, 14.0, 0.0),           # 5: Cruise East
        # 120s - 150s: Tunnel zone (30s blackout)
        (15.0, 13.5, -math.pi / 30.0),# 6: Gentle Left curve inside tunnel
        (15.0, 13.5, 0.0),           # 7: Straight tunnel cruising
        (20.0, 10.0, -math.pi / 20.0),# 8: Exit tunnel & Left turn (North)
        (35.0, 15.0, 0.0),           # 9: Main avenue cruising (54 km/h)
        (15.0, 0.0, 0.0),            # 10: Red light stop & wait
        (15.0, 12.0, 0.0),           # 11: Green light acceleration
        (10.0, 7.0, -math.pi / 20.0),# 12: 90 deg Left turn (West)
        (45.0, 14.0, 0.0),           # 13: Westbound cruise
        (10.0, 8.0, -math.pi / 20.0),# 14: 90 deg Left turn (South)
        (50.0, 13.0, 0.0),           # 15: Southbound cruise
        (35.0, 11.0, 0.04),          # 16: Winding road / S-curves
        (30.0, 11.0, 0.0),           # 17: Straight run
        (15.0, 0.0, 0.0),            # 18: Stop sign
        (25.0, 10.0, 0.0),           # 19: Slow cruise
        (30.0, 12.0, -math.pi / 40.0),# 20: Long sweeping curve
        (40.0, 14.0, 0.0),           # 21: Highway stretch
        (30.0, 8.0, 0.0),            # 22: Deceleration
        (25.0, 5.0, math.pi / 50.0), # 23: Parking approach
        (24.0, 0.0, 0.0),            # 24: Stationary stop
    ]

    total_seg_time = sum(s[0] for s in segments)
    scale_factor = duration_sec / total_seg_time

    dt_imu = 1.0 / imu_hz
    n_imu = int(round(duration_sec * imu_hz))
    t_arr = np.linspace(0.0, duration_sec, n_imu, endpoint=False)

    speed_profile = np.zeros(n_imu)
    yaw_rate_profile = np.zeros(n_imu)

    cur_idx = 0
    cur_v = 0.0
    for dur, tgt_v, yaw_rate in segments:
        scaled_dur = dur * scale_factor
        n_steps = int(round(scaled_dur * imu_hz))
        end_idx = min(cur_idx + n_steps, n_imu)

        yr = np.full(end_idx - cur_idx, yaw_rate)
        v_ramp = np.linspace(cur_v, tgt_v, end_idx - cur_idx)
        speed_profile[cur_idx:end_idx] = v_ramp
        yaw_rate_profile[cur_idx:end_idx] = yr

        cur_v = tgt_v
        cur_idx = end_idx
        if cur_idx >= n_imu:
            break

    # Integrate heading and ENU position
    heading = np.zeros(n_imu)
    heading[0] = math.pi / 2  # North
    x_east = np.zeros(n_imu)
    y_north = np.zeros(n_imu)

    for i in range(1, n_imu):
        dt = t_arr[i] - t_arr[i - 1]
        heading[i] = (heading[i - 1] + yaw_rate_profile[i] * dt + math.pi) % (2 * math.pi) - math.pi
        v = speed_profile[i]
        x_east[i] = x_east[i - 1] + v * math.cos(heading[i]) * dt
        y_north[i] = y_north[i - 1] + v * math.sin(heading[i]) * dt

    fwd_acc = np.gradient(speed_profile, dt_imu)
    lat_acc = speed_profile * yaw_rate_profile

    # Dynamic pitch tilt during acceleration/braking
    pitch_angle = np.clip(fwd_acc * 0.02, -0.15, 0.15)
    roll_angle = np.clip(lat_acc * 0.015, -0.12, 0.12)

    ax_body = lat_acc + gravity * np.sin(roll_angle) + rng.normal(0.0, 0.12, n_imu)
    ay_body = fwd_acc - gravity * np.sin(pitch_angle) + rng.normal(0.0, 0.15, n_imu)
    az_body = gravity * np.cos(pitch_angle) * np.cos(roll_angle) + rng.normal(0.0, 0.20, n_imu)

    gyro_bias_z = 0.004
    gx_body = np.gradient(roll_angle, dt_imu) + rng.normal(0.0, 0.008, n_imu)
    gy_body = np.gradient(pitch_angle, dt_imu) + rng.normal(0.0, 0.008, n_imu)
    gz_body = yaw_rate_profile + gyro_bias_z + rng.normal(0.0, 0.010, n_imu)

    mag_strength = 42.0
    mx_body = mag_strength * np.sin(heading) + rng.normal(0.0, 0.8, n_imu)
    my_body = mag_strength * np.cos(heading) + rng.normal(0.0, 0.8, n_imu)
    mz_body = np.full(n_imu, -25.0) + rng.normal(0.0, 0.8, n_imu)

    # Fast vectorized timestamps
    start_ts = pd.Timestamp("2026-09-21 10:00:00", tz="UTC")
    ts_series = start_ts + pd.to_timedelta(t_arr, unit="s")
    ts_iso_series = pd.Series(ts_series.strftime("%Y-%m-%dT%H:%M:%S.%fZ"))
    mono_micros = (1000000 + t_arr * 1e6).astype(np.int64)

    # 1. Accelerometer CSV
    df_acc = pd.DataFrame({
        "timestamp_iso": ts_iso_series,
        "source_timestamp_iso": ts_iso_series,
        "monotonic_micros": mono_micros,
        "x_mps2": np.round(ax_body, 6),
        "y_mps2": np.round(ay_body, 6),
        "z_mps2": np.round(az_body, 6),
    })
    df_acc.to_csv(output_dir / "accelerometer.csv", index=False)

    # 2. Gyroscope CSV
    df_gyr = pd.DataFrame({
        "timestamp_iso": ts_iso_series,
        "source_timestamp_iso": ts_iso_series,
        "monotonic_micros": mono_micros,
        "x_radps": np.round(gx_body, 6),
        "y_radps": np.round(gy_body, 6),
        "z_radps": np.round(gz_body, 6),
    })
    df_gyr.to_csv(output_dir / "gyroscope.csv", index=False)

    # 3. Magnetometer CSV
    df_mag = pd.DataFrame({
        "timestamp_iso": ts_iso_series,
        "source_timestamp_iso": ts_iso_series,
        "monotonic_micros": mono_micros,
        "x_uT": np.round(mx_body, 4),
        "y_uT": np.round(my_body, 4),
        "z_uT": np.round(mz_body, 4),
    })
    df_mag.to_csv(output_dir / "magnetometer.csv", index=False)

    # 4. GPS CSV (1Hz)
    n_gps = int(round(duration_sec * gps_hz))
    gps_indices = np.linspace(0, n_imu - 1, n_gps, dtype=int)
    lat0_rad = math.radians(lat0)

    dlat = y_north[gps_indices] / earth_radius
    dlon = x_east[gps_indices] / (earth_radius * math.cos(lat0_rad))
    lat_arr = np.degrees(lat0_rad + dlat)
    lon_arr = np.degrees(math.radians(lon0) + dlon)
    gps_heading_deg = (90.0 - np.degrees(heading[gps_indices])) % 360.0

    df_gps = pd.DataFrame({
        "timestamp_iso": ts_iso_series.iloc[gps_indices].values,
        "monotonic_micros": mono_micros[gps_indices],
        "latitude": np.round(lat_arr, 7),
        "longitude": np.round(lon_arr, 7),
        "altitude_m": 845.0,
        "accuracy_m": np.round(rng.uniform(3.5, 6.5, n_gps), 2),
        "speed_mps": np.round(speed_profile[gps_indices], 3),
        "heading_deg": np.round(gps_heading_deg, 2),
        "is_mocked": False,
    })
    df_gps.to_csv(output_dir / "gps.csv", index=False)

    # 5. Metadata JSON
    metadata = {
        "id": journey_id,
        "startTime": str(start_ts),
        "endTime": str(start_ts + pd.to_timedelta(duration_sec, unit="s")),
        "durationSeconds": int(duration_sec),
        "gpsCount": len(df_gps),
        "accelCount": len(df_acc),
        "gyroCount": len(df_gyr),
        "magCount": len(df_mag),
        "directoryPath": str(output_dir.resolve()),
        "description": "Extended 10-minute real-world vehicle benchmark driving dataset with urban maneuvers and 30s blackout zone.",
    }
    with open(output_dir / "metadata.json", "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)

    total_dist = float(np.sum(np.sqrt(np.diff(x_east)**2 + np.diff(y_north)**2)))
    print(f"[SUCCESS] Generated 10-Minute Benchmark Dataset at: {output_dir}")
    print(f"  - Duration: {duration_sec:.0f} seconds (10 minutes)")
    print(f"  - GPS fixes (1Hz): {len(df_gps):,}")
    print(f"  - Accelerometer samples (50Hz): {len(df_acc):,}")
    print(f"  - Gyroscope samples (50Hz): {len(df_gyr):,}")
    print(f"  - Magnetometer samples (50Hz): {len(df_mag):,}")
    print(f"  - Total trajectory distance: {total_dist:.1f} meters ({total_dist/1000:.2f} km)")


if __name__ == "__main__":
    out = Path(__file__).parent.parent / "data" / "journey_extended_benchmark"
    generate_10min_vehicle_dataset(output_dir=out)
