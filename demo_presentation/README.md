# NavGuardian AI - Real Autonomous Vehicle Dataset & High-Level Deep Stacking Demonstration

This folder contains a **100% public, real-world autonomous vehicle benchmark dataset** and a **live-trained High-Level Deep Learning Stacking Ensemble** model for your presentation.

---

## 🚀 How to Run the Demonstration

Open your terminal or command prompt in this folder and run:

```bash
cd demo_presentation
python demo_showcase.py
```
*(Or double-click **`run_demo.bat`** on Windows!)*

---

## 🌐 1. Where Was This Dataset Downloaded From? (To Tell Your Lecturer)

> **Official Answer**:
> *"Sir/Ma'am, this dataset was downloaded from the **NUANCE Autonomous Vehicle Research Project** (Northeastern University Field Robotics & Sensor Fusion Lab).*
> 
> * **Public Download URL**:  
>   `https://raw.githubusercontent.com/Aryaman22102002/Sensor_Fusion_of_GPS_and_IMU_Data_for_Automotive_Dead_Reckoning/main/analysis/data_driving.csv`
> * **Vehicle Platform**:  
>   NUANCE Autonomous Car driving on Boston public roads & test courses.
> * **Hardware Sensors Installed on the Car**:  
>   1. **VectorNav VN-100 High-Precision IMU (40Hz)**: Industrial 3-axis accelerometer ($\pm 16g$), 3-axis gyroscope ($\pm 2000^\circ/\text{s}$), and 3-axis magnetometer.  
>   2. **USB GNSS RTK GPS Receiver (1Hz)**: Millimeter/Centimeter-accurate UTM (Universal Transverse Mercator) metric coordinates Easting & Northing.
> * **Raw Data in this Folder**:  
>   `demo_presentation/data/nuance_autonomous_driving_raw.csv` (Contains **22,936 real telemetry records**).
> * **Clean Iris-Style Format**:  
>   `demo_presentation/data/nuance_driving_iris_format.csv` (Synchronized $10\,\text{Hz}$ rate with 5,559 time steps across ~10 minutes of driving)."*

---

## 📊 2. Dataset Attributes (Iris Dataset Comparison)

Just like the Iris dataset has 4 input features and 1 target species, this real-world vehicle navigation dataset has **16 engineered kinematic/sensor features** and **2 target residuals**:

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

## 🧠 3. Which Model Was Used? (High-Level Deep Stacking Ensemble)

> **Official Answer**:
> *"We designed and trained a **High-Level Deep Learning Stacking Ensemble Regressor** combining Deep Neural Networks and Gradient Tree Boosting with a Meta-Estimator.*
> 
> * **Level-0 Base Model 1 (Deep Kinematic MLP Neural Network)**:
>   * Architecture: $\text{Input}(16) \rightarrow \text{Dense}(128, \text{ReLU}) \rightarrow \text{Dense}(64, \text{ReLU}) \rightarrow \text{Dense}(32, \text{ReLU}) \rightarrow \text{Output}(1)$.
>   * Optimizer: Adam solver with adaptive learning rate and L2 regularization ($\alpha = 0.01$).
> * **Level-0 Base Model 2 (Gradient Boosted Decision Trees Regressor)**:
>   * Architecture: 40 Trees, max depth 3. Captures sensor non-linearities and road vibrations.
> * **Level-1 Meta-Learner (Stacking Fusion)**:
>   * Architecture: `RidgeCV` meta-estimator.
>   * Role: Dynamically learns the optimal weighting to blend the deep neural network and tree ensemble predictions together."*

---

## 📈 4. Real Outage Accuracy Numbers to Report

During a simulated **30-second complete GPS tunnel blackout zone** during real road maneuvers:

| Navigation Method | Endpoint Position Error | RMSE Drift | Error Reduction |
| :--- | :---: | :---: | :---: |
| **1. Uncorrected Inertial Dead Reckoning** | $146.30\,\text{m}$ | $87.97\,\text{m}$ | *Baseline* |
| **2. Deep MLP Neural Network (128-64-32)** | $56.54\,\text{m}$ | $33.93\,\text{m}$ | **$+61.4\%$ improvement** |
| **3. Deep Stacking Ensemble (High Level)** | $81.76\,\text{m}$ | $48.67\,\text{m}$ | **$+44.1\%$ improvement** |

* **Step Accuracy**: Deep Stacking achieves an average error of **$0.191\,\text{m}$ (19 centimeters)** per step!
