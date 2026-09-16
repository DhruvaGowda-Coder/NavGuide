# NavGuardian AI

Android-first Flutter foundation for live location, maps and sensor diagnostics. Advanced routing, recording, backend services and AI are intentionally reserved for later milestones.

## Included

- Branded onboarding, Explore/map, GPS metrics, sensor diagnostics, roadmap and privacy/settings screens.
- Real foreground location permission and continuous GPS updates; accuracy, speed, heading, coordinates and source timestamp.
- Denied/permanently denied permissions, location-off recovery, stream errors, initial-fix waiting and stale-fix labels.
- Accelerometer, gyroscope and magnetometer streams with units and source/receipt/monotonic timestamps; unavailable hardware states.
- Riverpod dependency injection, lifecycle cleanup, provider-independent entities/contracts, isolated Google map renderer.
- Destination search contract and honest unavailable screen; backend resource design and separate Python research packages.

## Run on this Windows machine

The toolchain is installed outside the repository at `%USERPROFILE%\.local\share\navguardian`. The wrapper sets Java and Android paths for its process; it does not replace your system Java.

```powershell
./scripts/flutter.ps1 pub get
./scripts/flutter.ps1 analyze
./scripts/flutter.ps1 test
./scripts/flutter.ps1 build apk --debug
./scripts/flutter.ps1 devices
./scripts/flutter.ps1 run -d YOUR_ANDROID_DEVICE_ID
```

On another machine install Flutter 3.47.2 (Dart 3.13.2), JDK 17 and Android SDK command-line tools, platform/build-tools 36, then use the equivalent `flutter` commands. Gradle may download the Flutter-pinned NDK and other required Android components. Use `flutter doctor` to inspect setup.

Enable Developer options and USB debugging on an Android phone, connect USB, select data mode if needed and accept the phone's debugging authorization. Google Play services are required for Google Maps. No physical Android device was connected during initial setup.

## Google Maps setup (Android)

1. Create/select your Google Cloud project, attach billing and enable **Maps SDK for Android**.
2. Create a client key restricted to that API and the Android package `com.navguardian.navguardian_ai` plus your signing certificate SHA-1. Obtain debug SHA-1 with `android/gradlew.bat signingReport` in the configured Java/SDK environment. Release signing needs its own certificate restriction.
3. Copy `config/development.example.json` to `config/development.json`. Set `GOOGLE_MAPS_API_KEY` to your key and `MAPS_ENABLED` to `true`.
4. Run or build with the same configuration:

```powershell
./scripts/flutter.ps1 run -d YOUR_ANDROID_DEVICE_ID --dart-define-from-file=config/development.json
./scripts/flutter.ps1 build apk --debug --dart-define-from-file=config/development.json
```

The Android build decodes the Dart defines into the manifest placeholder, so native and Dart map configuration share one source. Config JSON files are ignored by Git. Client Maps keys are extractable from apps: restrictions are mandatory, and server credentials must never go in this file. No Places/Routes API or backend account is needed for this milestone. Without a key the map area shows setup guidance and GPS/sensors remain usable. Invalid keys or billing/restriction errors must be diagnosed in Google Cloud/Android logs; the native map plugin cannot reliably expose every authorization error to Dart.

## Platform readiness

Android is the implemented map target. iOS, web and Windows runners are included for future work; map rendering on those platforms is gated until their native/browser key setup is implemented and tested. iOS location/motion purpose strings are included, but building requires macOS/Xcode and future Google Maps initialization. Browser GPS requires a secure origin; sensors vary by browser and web magnetometer is unavailable. Windows sensors/maps have no adapter here. No Windows dashboard is built.

Windows desktop was disabled in the local Flutter configuration to bypass this machine's missing symlink privilege. Before Windows development, enable Windows Developer Mode and run `flutter config --enable-windows-desktop`.

## Project guide

- `lib/app`: composition, providers, theme and lifecycle
- `lib/domain`: telemetry, destination, route, risk, recorder and engine contracts
- `lib/device`: location, sensor and connectivity plugin adapters
- `lib/maps`: Google map rendering/provider boundary
- `lib/features`: home, location state, sensors, search, roadmap and settings
- `backend`: future API/data resource responsibilities
- `ml/src/navguardian_ml`: ten isolated research areas with no fabricated model implementation
- `docs/architecture.md`: data flows and extension policy
- `docs/device-validation.md`: real-device acceptance checklist
- `docs/verification.md`: actual validation results and limits

The app does not persist journeys, upload telemetry, estimate positions during GPS outages, calculate safety scores or provide turn-by-turn directions. Foreground GPS stays enabled across app tabs until Stop or backgrounding; raw sensor subscriptions are active only on the diagnostics screen. Onboarding currently appears on each fresh launch.

## Release boundary

This is a maintainable first milestone, not a store-ready navigation product. Release signing is intentionally unconfigured (debug builds work). Before distribution: set the final application identity, supply release signing privately, replace generated launcher assets, review privacy disclosures, validate real devices and map billing/restrictions, and run CI plus the acceptance checklist. Commit `pubspec.lock` for reproducible dependency resolution.

Reference documentation: [Flutter](https://docs.flutter.dev/), [Google Maps Flutter](https://pub.dev/packages/google_maps_flutter), [Geolocator](https://pub.dev/packages/geolocator), [Sensors Plus](https://pub.dev/packages/sensors_plus).
