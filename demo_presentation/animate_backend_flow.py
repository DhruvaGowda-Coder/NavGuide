"""NavGuardian AI - 60-FPS Web Dashboard & Live Python ML Backend Launcher.

Starts the local Python ML server (powered by nuance_driving_iris_format.csv
and scikit-learn Deep Stacking Ensemble) and opens the butter-smooth 60-FPS
Web Application at http://localhost:8050 in your browser.

How to run in Antigravity Terminal:
    python demo_presentation/animate_backend_flow.py
    (or: python demo_presentation/server.py)
"""

from server import main

if __name__ == "__main__":
    main()
