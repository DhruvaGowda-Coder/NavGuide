# Walkthrough: Phase 3 — Basic Dead Reckoning Baseline

Phase 3 introduces NavGuardian AI's **unassisted baseline dead-reckoning engine**, simulating GPS outages, estimating trajectories from IMU motion sensors, and benchmarking drift and error metrics against hidden ground-truth GPS coordinates.

---

## 1. Architecture & Implementation

### A. Journey Replay & Deserialization
* **[`JourneyReader`](file:///c:/Users/dhruv/OneDrive/Documents/ChatGPT/Final_Project/lib/device/storage/journey_reader.dart)**:
  * Reads `metadata.json`, `gps.csv`, `accelerometer.csv`, `gyroscope.csv`, and `magnetometer.csv` from any saved journey folder.
  * Combines all data into a unified, chronologically sorted stream using high-resolution monotonic timestamps (`monotonic_micros`).

### B. Baseline Dead Reckoning Engine
* **[`DeadReckoningEngine`](file:///c:/Users/dhruv/OneDrive/Documents/ChatGPT/Final_Project/lib/device/dead_reckoning/dead_reckoning_engine.dart)**:
  * **Attitude & Orientation**: Low-pass filtered pitch and roll leveling using the gravity vector ($[0, 0, g]^T$); dynamic heading updates from gyroscope angular rate integration transformed from body rates to navigation Euler yaw rates; soft magnetometer heading fusion.
  * **World-Frame Gravity Removal**: Direction Cosine Matrix ($R_{dev \to nav}$) rotates raw accelerations to North-East-Down (NED), subtracting standard Earth gravity ($9.80665\,\text{m/s}^2$).
  * **Zero Velocity Update (ZUPT)**: Sliding-window standard deviation detector clamps velocity to zero during stationary periods, eliminating unbounded integration drift.
  * **Damped Velocity & Position Propagation**: Projects horizontal velocities and maps displacements to latitude/longitude using WGS-84 / spherical geodesy ($R = 6,378,137\,\text{m}$).

### C. Simulated GPS Blackout Evaluator
* **[`OutageEvaluator`](file:///c:/Users/dhruv/OneDrive/Documents/ChatGPT/Final_Project/lib/device/dead_reckoning/outage_evaluator.dart)**:
  * **Strict Isolation**: During the configured blackout window $[t_{\text{start}}, t_{\text{start}} + \text{duration}]$, GPS fixes are **100% hidden** from the dead reckoning engine and preserved exclusively as ground truth.
  * **Scientific Metrics**: Computes **Endpoint Position Error** (m), **RMSE** (m), **Mean Position Error** (m), **Max Position Error** (m), and **Drift Rate** (m/s).

### D. Interactive Map & Replay UI
* **[`JourneyAnalysisScreen`](file:///c:/Users/dhruv/OneDrive/Documents/ChatGPT/Final_Project/lib/features/journey/journey_analysis_screen.dart)**:
  * **Google Map Visualization**:
    * **Blue Polyline**: Full actual GPS ground-truth route.
    * **Amber/Orange Polyline**: Dead Reckoning estimated trajectory during blackout.
    * **Green Marker**: Outage start (last known GPS fix).
    * **Azure Marker**: Actual ground-truth GPS endpoint.
    * **Orange Marker**: Dead Reckoning predicted endpoint with live error snippet.
  * **Blackout Selector**: Duration chips (`10s`, `30s`, `60s`, or `Max available`).
  * **Metrics Card**: Floating HUD showing Final Error, RMSE, Drift Rate, Mean, and Max error.
  * **Point-by-Point Drawer**: Modal sheet displaying timestamped ground-truth vs. DR coordinates.
* **[`JourneyHistoryScreen`](file:///c:/Users/dhruv/OneDrive/Documents/ChatGPT/Final_Project/lib/features/journey/journey_history_screen.dart)**:
  * Added **"Analyze (DR)"** action directly on each journey card.

---

## 2. Benchmark Results on Real Physical Journey (`journey_20260908_125527`)

Evaluated against the physical recording captured on your **iQOO Neo9 Pro** (19 seconds, 3 GPS fixes, 1,962 accelerometer samples, 972 magnetometer samples):

| Simulated Outage | Evaluated Duration | Hidden GPS Fixes | Final Endpoint Error | RMSE | Mean Error | Max Error | Drift Rate |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **10-Second Blackout** | **10.6 s** | 1 fix | **2.62 m** | **1.32 m** | **1.32 m** | **2.62 m** | **0.247 m/s** |
| **Full Outage (~18s)** | **16.4 s** | 3 fixes | **2.68 m** | **1.76 m** | **1.58 m** | **2.68 m** | **0.163 m/s** |

### Why This Baseline Matters:
* **Honest Unassisted Metrics**: No Kalman filtering, road snapping, or future GPS coordinate leaking were used.
* **Stationary Stability**: Thanks to our Zero Velocity Update (ZUPT) detector, the phone did not experience the classic naive-integration explosion (which typically rockets off to kilometers in seconds).
* **Moving Journey Recommendation**: Because `journey_20260908_125527` was recorded while resting stationary on a desk, the displacement was minimal. To benchmark 30s and 60s dynamic blackouts with vehicle speed, turns, and lateral acceleration, you can record an outdoor walking or driving journey with NavGuardian and immediately tap **"Analyze (DR)"** to see the curve drift!

---

## 3. Automated Test Suite & Code Quality

* **Static Analysis**: `flutter analyze` $\to$ **0 issues found**.
* **Automated Unit & Integration Tests**: `flutter test` $\to$ **15/15 passed** across all suites:
  * `GeodesyUtils Tests`: Haversine distance, delta lat/lon conversions, bearing calculations: **PASS**.
  * `DeadReckoningEngine Baseline Tests`: Attitude tracking, gravity compensation, stationary ZUPT clamp, forward velocity propagation: **PASS**.
  * `OutageEvaluator Tests`: Blackout simulation, strict GPS isolation, RMSE/drift calculations: **PASS**.
  * `Real Physical Journey Evaluation`: Automated real-device trajectory evaluation: **PASS**.
  * `Journey Recording & Telemetry Tests`: Multi-frequency CSV writers, lifecycle, permissions: **PASS**.

---

## 4. Installed on Physical Phone
* The updated debug APK has been compiled and installed onto your connected **iQOO Neo9 Pro** (`10BE1Z1RDQ0003N`).
* The app is running and ready to analyze past journeys or record new moving trips.
