# Implementation Plan - RoadSOS Emergency Response System

RoadSOS is a highly resilient, AI-powered emergency response ecosystem designed for the National Road Safety Hackathon 2026. The solution consists of a Flutter mobile frontend with a native Android 14 background Foreground Service for high-frequency sensor polling, an edge-based machine learning model for crash detection, an offline-first architecture (Mapbox vector tiles, local SQLite, SMS fallback gateway), a FastAPI backend querying the OpenStreetMap Overpass API and validating facilities via the Ayushman Bharat Digital Mission (ABDM), and a global routing/triage resolution engine.

---

## User Review Required

Please review the following architecture points:
1. **Background Service Type**: Under Android 14 background rules, we are implementing a native `ForegroundService` with `foregroundServiceType="specialUse"` and the `FOREGROUND_SERVICE_SPECIAL_USE` permission.
2. **Offline Vector Map Tile Packs Limit**: Custom logic in Flutter to track downloaded Mapbox regions and enforce a limit of **750 map tile packs** to comply with API restrictions.
3. **SMS Distress Format**: Highly compressed string structure `LAT:{lat};LON:{lon};SEV:{g_force};MED:{blood_type_allergies}` sent via fallback SMS if API calls fail.

---

## Open Questions

> [!NOTE]
> There are no immediate blockages. The requirements defined in the strategic blueprint are precise and complete. Any specific adjustments to the classifier architecture or SMS formats can be refined during their respective phases.

---

## Proposed Changes

We will organize the project in a modular folder structure:
- `/mobile`: The Flutter application
- `/backend`: FastAPI backend and Overpass/ABDM validation engines
- `/gateway`: SMS gateway and GSM modem listener

---

### Component 1: Hybrid Mobile Frontend (Flutter + Native Kotlin) [Phase 1]

We will build the primary UI and native service channels.

#### [NEW] [pubspec.yaml](file:///d:/Coding/RoadSOS/mobile/pubspec.yaml)
- Define Flutter app and project metadata.
- Dependencies: `sqflite`, `path`, `path_provider`, `mapbox_maps_flutter`, `http`, `permission_handler`, `tflite_flutter` (or a helper placeholder for Phase 2), `shared_preferences`.

#### [NEW] [AndroidManifest.xml](file:///d:/Coding/RoadSOS/mobile/android/app/src/main/AndroidManifest.xml)
- Set up permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `RECEIVE_BOOT_COMPLETED`, `SEND_SMS`.
- Declare `SensorService` as a foreground service with `android:foregroundServiceType="specialUse"`.

#### [NEW] [build.gradle](file:///d:/Coding/RoadSOS/mobile/android/app/build.gradle)
- Set SDK versions (compileSdkVersion 34, targetSdkVersion 34, minSdkVersion 21).

#### [NEW] [MainActivity.kt](file:///d:/Coding/RoadSOS/mobile/android/app/src/main/kotlin/com/example/roadsos/MainActivity.kt)
- Register `MethodChannel` to communicate with Flutter.
- Handle service start/stop commands and receive sliding window sensor data.

#### [NEW] [SensorService.kt](file:///d:/Coding/RoadSOS/mobile/android/app/src/main/kotlin/com/example/roadsos/SensorService.kt)
- Kotlin Foreground Service running sensor listener.
- Continuously poll Accelerometer and Gyroscope at 50Hz (20ms interval).
- Maintain an in-memory rolling/overlapping sliding window of 3 seconds of data (150 samples).
- Compute $A_{mag} = \sqrt{A_x^2 + A_y^2 + A_z^2}$ and $\omega_{mag} = \sqrt{\omega_x^2 + \omega_y^2 + \omega_z^2}$.
- Extract statistical features to assemble a 1x44 feature vector.

#### [NEW] [main.dart](file:///d:/Coding/RoadSOS/mobile/lib/main.dart)
- Flutter primary entry point.
- Modern high-contrast premium user interface (dark theme, glassmorphic cards, clear high-contrast call-to-actions).
- Trigger auditory alarm and 10-second countdown on crash detection, allowing the user to cancel or proceed to dispatch.

---

### Component 2: Edge AI Crash Detection Module [Phase 2]

#### [NEW] [train_model.py](file:///d:/Coding/RoadSOS/ml/train_model.py)
- Python script using `scikit-learn` to train a Random Forest classifier.
- Generates mock crash (sudden deceleration, tumbling) and non-crash (running, normal driving, sudden braking) datasets.
- Feature vectors of 1x44 metrics.
- Export trained model to TensorFlow Lite (`crash_detector.tflite`).

---

### Component 3: Resilient Offline-First Architecture [Phase 3]

#### [NEW] [db_helper.dart](file:///d:/Coding/RoadSOS/mobile/lib/db_helper.dart)
- SQLite helper to cache offline emergency contact data.

#### [NEW] [offline_maps_manager.dart](file:///d:/Coding/RoadSOS/mobile/lib/offline_maps_manager.dart)
- Mapbox tile region downloader. Enforce maximum limit of 750 tile packs.

#### [NEW] [sms_receiver.py](file:///d:/Coding/RoadSOS/gateway/sms_receiver.py)
- Python script interfacing with a physical GSM modem via serial.
- Sends AT commands to initialize (`AT&F`, `AT+CMGF=1`) and read SMS signals.

---

### Component 4: Backend API & Geospatial Data Engine [Phase 4]

#### [NEW] [requirements.txt](file:///d:/Coding/RoadSOS/backend/requirements.txt)
- Python dependencies: `fastapi`, `uvicorn`, `requests`, `pandas`, `pydantic`.

#### [NEW] [main.py](file:///d:/Coding/RoadSOS/backend/main.py)
- FastAPI application.
- Endpoint `/emergency-facilities` that executes Overpass QL bounding box queries, processes via `pandas.io.json.json_normalize`, cross-checks operational status using the ABDM Sandbox Health Facility Registry (HFR) API, and returns enriched JSON response.

---

### Component 5: Global Routing & Triage Logic [Phase 5]

#### [NEW] [triage_engine.dart](file:///d:/Coding/RoadSOS/mobile/lib/triage_engine.dart)
- Implementation of the ACS-COT Field Triage decision tree.
- Dynamic ISO 3166-1 country lookup to adjust dial/SOS emergency numbers.

---

## Verification Plan

### Automated & Unit Tests
- Execute Flutter test suite and dry-run code compiling.
- Run Python unit tests for ML training, FastAPI endpoints, and Overpass parser.

### Manual Verification
- Verify Foreground Service activation on Android device simulation/manifest check.
- Validate that the model is loaded in Flutter and registers features properly.
- Run mock API calls and SMS payload decoders to ensure robustness.
