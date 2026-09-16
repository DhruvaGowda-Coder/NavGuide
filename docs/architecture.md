# NavGuardian AI architecture

Milestone 1 is foreground device telemetry and a Google map. It is not a route planner or a safety-critical navigation system yet. No simulated positions, safety scores, or AI estimates are displayed.

## Boundaries

- `app`: bootstrap, theme, lifecycle and navigation shell; Riverpod owns dependencies.
- `domain`: provider-independent location, sensor and navigation contracts.
- `device`: geolocator, sensors_plus and connectivity adapters; permission handling lives here.
- `maps`: Google-specific rendering and future Places/Routes adapters. UI never calls Google HTTP APIs.
- `features`: feature presentation and application state; planned modules explicitly identify their unavailable status.
- `backend`: contracts and storage design only; no server or authentication is deployed.
- `ml`: separate Python research packages; never imported by the Flutter app.

## Data flow

GPS and timestamped sensors → device adapters → future journey recorder → navigation engine → map presentation.

Traffic, weather, flood, road data and reports → backend repositories → future risk inference → safety assessment → route alternatives.

Future GPS loss: last trusted fix + calibrated inertial samples → dead reckoning/fusion → optional model correction → estimated fix with uncertainty and provenance. The initial implementation never extrapolates a position. Old GPS fixes are labeled stale; no AI-active indicator is fabricated.

## Lifecycle and privacy

Streams run only while the application is resumed. Subscription disposal stops plugin listeners. Permission is requested only after user action; denial, permanent denial, disabled services, timeouts and missing sensors have visible states. Returning from settings retries location only if the user already enabled it. No background permission, uploads or persistent location recording are enabled.

Sensor samples retain source timestamp, UTC receipt timestamp and process-monotonic receipt time. These clocks must be calibrated before fusion; wall-clock timestamps alone are insufficient. Acceleration includes gravity, gyroscope uses rad/s, magnetometer uses microtesla, speed uses m/s internally.

## Extension policy

Implement repositories behind contracts before adding screens that consume them. Add a persisted, consent-based recorder with retention/export/deletion controls before collecting ML data. Location estimates require explicit source and uncertainty. Risk assessments require evidence freshness and confidence; unknown risk must never become a zero-risk score. Keep server credentials and Places/Routes web-service credentials on a backend. Native Maps keys are shipped to clients and must be restricted by application identity and API.

Android is the validation target. iOS needs macOS/Xcode and native key configuration. Web requires browser-specific Maps loading and secure-origin location permissions. Windows has no Google Maps Flutter adapter and displays an unsupported state; no dashboard is included.
