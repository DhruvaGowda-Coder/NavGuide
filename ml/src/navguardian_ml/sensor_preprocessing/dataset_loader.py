"""Data loading and synchronization module for NavGuardian ML.

Loads raw multi-frequency CSVs (GPS at 1Hz, IMU at 50-100Hz) and resamples
them onto a synchronized 10 Hz metric time-series grid.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Dict, Any, Tuple

import numpy as np
import pandas as pd

EARTH_RADIUS_METERS = 6378137.0


def latlon_to_metric(lat: np.ndarray, lon: np.ndarray, lat0: float, lon0: float) -> Tuple[np.ndarray, np.ndarray]:
    """Convert geodetic lat/lon to local Cartesian North/East displacement in meters."""
    lat_rad = np.radians(lat)
    lon_rad = np.radians(lon)
    lat0_rad = math.radians(lat0)
    lon0_rad = math.radians(lon0)

    dlat = lat_rad - lat0_rad
    dlon = lon_rad - lon0_rad

    y_north = EARTH_RADIUS_METERS * dlat
    x_east = EARTH_RADIUS_METERS * math.cos(lat0_rad) * dlon
    return x_east, y_north


def metric_to_latlon(x_east: np.ndarray, y_north: np.ndarray, lat0: float, lon0: float) -> Tuple[np.ndarray, np.ndarray]:
    """Convert local Cartesian North/East meters back to geodetic lat/lon."""
    lat0_rad = math.radians(lat0)
    dlat = y_north / EARTH_RADIUS_METERS
    dlon = x_east / (EARTH_RADIUS_METERS * math.cos(lat0_rad))
    lat = np.degrees(lat0_rad + dlat)
    lon = np.degrees(math.radians(lon0) + dlon)
    return lat, lon


class JourneyDataset:
    """Represents a synchronized multi-stream journey."""

    def __init__(self, metadata: Dict[str, Any], df_sync: pd.DataFrame, lat0: float, lon0: float):
        self.metadata = metadata
        self.df = df_sync
        self.lat0 = lat0
        self.lon0 = lon0
        self.journey_id = metadata.get("id", "unknown")
        self.duration_seconds = metadata.get("durationSeconds", 0)

    def __len__(self) -> int:
        return len(self.df)


def load_journey_directory(journey_dir: str | Path, target_dt_sec: float = 0.1) -> JourneyDataset:
    """Load a journey directory, synchronize streams, and return a JourneyDataset.

    Parameters
    ----------
    journey_dir : str or Path
        Directory containing metadata.json, gps.csv, accelerometer.csv,
        gyroscope.csv, and magnetometer.csv.
    target_dt_sec : float
        Uniform grid interval in seconds (default: 0.1s for 10 Hz).
    """
    path = Path(journey_dir)
    meta_file = path / "metadata.json"
    if not meta_file.exists():
        raise FileNotFoundError(f"Missing metadata.json in {journey_dir}")

    with open(meta_file, "r", encoding="utf-8-sig") as f:
        metadata = json.load(f)

    # 1. Load CSVs
    df_gps = pd.read_csv(path / "gps.csv", encoding="utf-8-sig")
    df_acc = pd.read_csv(path / "accelerometer.csv", encoding="utf-8-sig")
    df_gyr = pd.read_csv(path / "gyroscope.csv", encoding="utf-8-sig")
    df_mag = pd.read_csv(path / "magnetometer.csv", encoding="utf-8-sig")

    # Clean empty strings / whitespace
    for df in [df_gps, df_acc, df_gyr, df_mag]:
        df.columns = [c.strip() for c in df.columns]

    # Reference time origin (start monotonic micros)
    min_micros = min(
        df_gps["monotonic_micros"].min(),
        df_acc["monotonic_micros"].min(),
        df_gyr["monotonic_micros"].min(),
        df_mag["monotonic_micros"].min(),
    )
    max_micros = max(
        df_gps["monotonic_micros"].max(),
        df_acc["monotonic_micros"].max(),
        df_gyr["monotonic_micros"].max(),
        df_mag["monotonic_micros"].max(),
    )

    # Reference anchor coordinate
    lat0 = float(df_gps["latitude"].iloc[0])
    lon0 = float(df_gps["longitude"].iloc[0])

    # Convert GPS to local metric
    gps_time_sec = (df_gps["monotonic_micros"] - min_micros) / 1e6
    x_east, y_north = latlon_to_metric(df_gps["latitude"].values, df_gps["longitude"].values, lat0, lon0)
    df_gps["x_east"] = x_east
    df_gps["y_north"] = y_north
    df_gps["t_sec"] = gps_time_sec

    # IMU times in seconds
    acc_time_sec = (df_acc["monotonic_micros"] - min_micros) / 1e6
    gyr_time_sec = (df_gyr["monotonic_micros"] - min_micros) / 1e6
    mag_time_sec = (df_mag["monotonic_micros"] - min_micros) / 1e6

    # 2. Resample onto uniform target grid
    total_time = (max_micros - min_micros) / 1e6
    grid_times = np.arange(0.0, total_time + target_dt_sec / 2, target_dt_sec)

    # Interpolate accelerometer
    ax = np.interp(grid_times, acc_time_sec, df_acc["x_mps2"])
    ay = np.interp(grid_times, acc_time_sec, df_acc["y_mps2"])
    az = np.interp(grid_times, acc_time_sec, df_acc["z_mps2"])

    # Interpolate gyroscope
    gx = np.interp(grid_times, gyr_time_sec, df_gyr["x_radps"])
    gy = np.interp(grid_times, gyr_time_sec, df_gyr["y_radps"])
    gz = np.interp(grid_times, gyr_time_sec, df_gyr["z_radps"])

    # Interpolate magnetometer
    mx = np.interp(grid_times, mag_time_sec, df_mag["x_uT"])
    my = np.interp(grid_times, mag_time_sec, df_mag["y_uT"])
    mz = np.interp(grid_times, mag_time_sec, df_mag["z_uT"])

    # Interpolate ground truth GPS metric positions & metrics
    gps_x = np.interp(grid_times, df_gps["t_sec"], df_gps["x_east"])
    gps_y = np.interp(grid_times, df_gps["t_sec"], df_gps["y_north"])
    gps_speed = np.interp(grid_times, df_gps["t_sec"], df_gps["speed_mps"])
    gps_bearing = np.interp(grid_times, df_gps["t_sec"], df_gps["heading_deg"])
    gps_acc = np.interp(grid_times, df_gps["t_sec"], df_gps["accuracy_m"])

    sync_df = pd.DataFrame(
        {
            "t_sec": grid_times,
            "ax": ax,
            "ay": ay,
            "az": az,
            "gx": gx,
            "gy": gy,
            "gz": gz,
            "mx": mx,
            "my": my,
            "mz": mz,
            "gps_x": gps_x,
            "gps_y": gps_y,
            "gps_speed": gps_speed,
            "gps_bearing": gps_bearing,
            "gps_accuracy": gps_acc,
        }
    )

    return JourneyDataset(metadata=metadata, df_sync=sync_df, lat0=lat0, lon0=lon0)
