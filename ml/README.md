# Research workspace

Python training is isolated from the app. Packages under `src/navguardian_ml` are reserved research boundaries, not working models. No training data or model weights are supplied.

Pipeline: sensor preprocessing → dead reckoning → sensor fusion → drift analysis → AI drift correction. Separate prediction tracks cover route risk, flood risk and road condition, feeding a safety-score policy. Evaluation must split by user/journey/geography to avoid leakage and compare against GPS-only and classical fusion baselines.

Record units, coordinate frames, calibration, source clocks, ground-truth quality, consent and model/data versions. Evaluate position error, error growth during outages, recovery, uncertainty calibration and device generalization. Do not claim safety improvements without representative evaluation.
