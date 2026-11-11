# NavGuardian AI - Offline Benchmark and ML Demo

This folder contains a public vehicle telemetry dataset and a presentation demo that can load a saved scikit-learn model or refit it locally. The dashboard is a simulation and offline benchmark replay, not a live navigation backend. Dataset provenance and sensor specifications should be attributed to the upstream repository unless independently verified against its original paper.

---

## Run the Offline Benchmark Demo

Open your terminal in Antigravity and run:

```bash
python demo_presentation/server.py
```
*(Or run `python demo_presentation/animate_backend_flow.py` or double-click **`run_demo.bat`**!)*

This starts the local Python API and opens the animated dashboard in your browser at:
👉 **`http://localhost:8050`**

### What's Inside the Web Application (`http://localhost:8050`):
1. **Tab 1 — GPS blackout benchmark replay**: Animates the 301 recorded rows in the 300–330 second holdout interval; it does not read live vehicle sensors.
2. **Tab 2 — Illustrative route graph**: Hand-authored graph values and local sliders demonstrate distance/risk weighting. Paths are selected by a threshold; there is no live map/hazard service, Bayesian inference, TSP solver, or Dijkstra solver.
3. **Tab 3 — Demo flow diagram**: Shows the offline replay and model path. Animation is decorative; it is not live sensor or hazard packet traffic.
4. **Tab 4 — Dataset and Python ML**: Displays dataset rows, predicts held-out samples through `/api/predict-step`, and can refit the models through `/api/retrain`.

### What the backend actually trains

`server.py` uses 16 precomputed feature columns. The 300–330 second interval (301 rows) is held out, and the other 5,258 rows are used for training. It trains one `(128, 64, 32)` MLP for both residual targets and two separate `StackingRegressor` models, one per target. Each stacking model contains a `(64, 32)` MLP and a 40-tree gradient boosting regressor, with `RidgeCV` as final estimator. The presentation's deep stacking wording is shorthand; these are conventional scikit-learn estimators, and no EKF, ZUPT, Bayesian hazard estimator, map matcher, or live routing is implemented by this demo.

The reported endpoint reduction percentages compare endpoint position errors in this one fixed holdout interval. The step MAE is a different metric, measured in meters of per-step residual prediction error. Do not describe it as endpoint accuracy or generalize these results to other trips without additional evaluation.

---

## Dataset Source (Verify Before Attributing)

> **Careful attribution:**
> *"This demo uses the public CSV linked by the upstream project repository. We use its bundled metadata for attribution and have not independently verified all platform or sensor claims."*
> 
> * **Public Download URL**:  
>   `https://raw.githubusercontent.com/Aryaman22102002/Sensor_Fusion_of_GPS_and_IMU_Data_for_Automotive_Dead_Reckoning/main/analysis/data_driving.csv`
> * **Platform and hardware**:
>   The upstream notes report a NUANCE vehicle, VectorNav IMU and USB GNSS receiver. Confirm these details in the cited paper or dataset documentation before presenting them as verified specifications.
> * **Raw Data in this Folder**:  
>   `demo_presentation/data/nuance_autonomous_driving_raw.csv` (Contains **22,936 records**).
> * **Clean Iris-Style Format**:  
>   `demo_presentation/data/nuance_driving_iris_format.csv` (prepared at 10Hz with 5,559 rows across about 10 minutes; row count and interval are locally verified, while source claims remain upstream metadata)."*

---

## 📊 2. Dataset Attributes (Iris Dataset Comparison)

This prepared vehicle telemetry dataset has **16 precomputed kinematic/sensor feature columns** and **2 target residual columns**:

| # | Attribute Name | Type | Units | Description |
| :-: | :--- | :-: | :-: | :--- |
| **1** | `ax` | Float | $\text{m/s}^2$ | VectorNav lateral acceleration (body frame X) |
| **2** | `ay` | Float | $\text{m/s}^2$ | VectorNav forward acceleration (body frame Y) |
| **3** | `az` | Float | $\text{m/s}^2$ | VectorNav vertical acceleration (body frame Z) |
| **4** | `acc_norm` | Float | $\text{m/s}^2$ | Euclidean acceleration vector magnitude ($\|a\|_2$) |
| **5** | `jerk` | Float | $\text{m/s}^3$ | Time derivative of acceleration ($da/dt$) |
| **6** | `gx` | Float | $\text{rad/s}$ | Roll angular velocity |
| **7** | `gy` | Float | $\text{rad/s}$ | Pitch angular velocity |
| **8** | `gz` | Float | $\text{rad/s}$ | Yaw rate (turning angular velocity) |
| **9** | `gyro_norm` | Float | $\text{rad/s}$ | Total angular rate magnitude ($\|\omega\|_2$) |
| **10** | `mag_x` | Float | $\mu\text{T}$ | Magnetic field intensity X |
| **11** | `mag_y` | Float | $\mu\text{T}$ | Magnetic field intensity Y |
| **12** | `mag_z` | Float | $\mu\text{T}$ | Magnetic field intensity Z |
| **13** | `est_vx` | Float | $\text{m/s}$ | Integrated inertial velocity East |
| **14** | `est_vy` | Float | $\text{m/s}$ | Integrated inertial velocity North |
| **15** | `est_speed` | Float | $\text{m/s}$ | Forward vehicle speed |
| **16** | `yaw_angle` | Float | $\text{rad}$ | Heading yaw orientation angle |
| **17** | `target_dx` *(Target)* | Float | meters | Ground truth step drift East ($\text{GPS\_dx} - \text{DR\_dx}$) |
| **18** | `target_dy` *(Target)* | Float | meters | Ground truth step drift North ($\text{GPS\_dy} - \text{DR\_dy}$) |

---

## 🧠 3. Models Actually Used by This Demo

> **Careful attribution:**
> *"We evaluate a standalone MLP and two target-specific scikit-learn stacking regressors on a fixed held-out dataset interval."*
> 
> * **Standalone MLP (separate model)**:
>   * Architecture: $\text{Input}(16) \rightarrow \text{Dense}(128, \text{ReLU}) \rightarrow \text{Dense}(64, \text{ReLU}) \rightarrow \text{Dense}(32, \text{ReLU}) \rightarrow \text{Output}(1)$.
>   * Optimizer: Adam solver with adaptive learning rate and L2 regularization ($\alpha = 0.01$).
> * **Two target-specific stacking models**: each uses a `(64, 32)` MLP and a 40-tree gradient boosting regressor (max depth 3), with `RidgeCV` as the final estimator. One stack predicts East residual and the other predicts North residual.
>
> These are not the displayed `(128,64,32)` MLP plus GBDT inside one shared stack; the larger MLP is trained independently.

---

## 📈 4. Fixed Holdout Metrics (One Dataset Interval)

On the fixed **300–330 second held-out interval** from this prepared dataset (301 samples at 10Hz; not a live tunnel test). Endpoint and RMSE numbers are reproducible from the checked-in pre-trained estimators; clicking retrain fits new estimators, so results can vary by sklearn version or convergence:

| Evaluation method | Endpoint position error | RMSE drift | Endpoint error reduction |
| :--- | :---: | :---: | :---: |
| **1. Dataset dead-reckoning proxy (uncorrected)** | $146.30\,\text{m}$ | $87.97\,\text{m}$ | *Baseline* |
| **2. Standalone MLP (128-64-32)** | $56.54\,\text{m}$ | $33.93\,\text{m}$ | **$+61.4\%$ endpoint error reduction** |
| **3. Two target-specific stacking regressors** | $81.76\,\text{m}$ | $48.67\,\text{m}$ | **$+44.1\%$ endpoint error reduction** |

* **Step MAE**: The stacked residual prediction has an average absolute error of **$0.1912\,\text{m}$ per target value**, as calculated by this backend. It is not average 2D Euclidean step error.
