# Tech Context

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Framework
- **Flutter** (Dart) -- cross-platform mobile framework
- **Dart SDK:** >=3.2.3 <4.0.0
- **Flutter SDK:** stable channel (3.38.9 / Dart 3.10.8)
- **Target platforms:** iOS (primary), Android (primary), macOS/Windows/Linux/Web (scaffolded, not evaluated)

## ML / Inference Stack

### YOLO11n via ultralytics_yolo (Only Backend)
| Detail | Value |
|---|---|
| Package | `ultralytics_yolo: ^0.2.0` |
| Android model | `yolo11n.tflite` in `android/app/src/main/assets/` |
| iOS model | `yolo11n.mlpackage` bundled via Xcode Resources (in `ios/` dir) |
| Model format -- Android | TensorFlow Lite |
| Model format -- iOS | Apple Core ML (mlpackage) |
| Inference location | On-device, fully offline |
| Label source | Embedded in model -- no external label file |
| Classes | `Soccer ball`, `ball`, `tennis-ball` (3 classes) |
| Task | `YOLOTask.detect` (bounding box detection) |
| Camera management | Handled internally by `YOLOView` widget |
| Orientation | Landscape only (left + right) |

Note: The SSD MobileNet v1 / tflite_flutter fallback path was fully removed on 2026-03-05. The Unsplash/API layer was fully removed on 2026-03-09.

## Key Dependencies

### Runtime
```yaml
ultralytics_yolo: ^0.2.0        # YOLO11n integration (wraps TFLite/CoreML per platform)
cupertino_icons: ^1.0.2          # iOS-style icons
audioplayers: ^6.1.0             # Audio feedback for impact results (zone callouts + miss)
sensors_plus: ^6.1.0             # Accelerometer for rotate-to-landscape overlay
permission_handler: ^11.3.1      # Explicit camera permission request (iOS needs PERMISSION_CAMERA=1 Podfile macro)
path_provider: ^2.1.3            # App Documents directory path for DiagnosticLogger CSV output
share_plus: ^10.0.0              # Share log CSV file via system share sheet (Share.shareXFiles)
```

### Dev
```yaml
flutter_test (SDK)               # Widget/unit testing
flutter_lints: ^2.0.0            # Lint rules
```

### Removed Dependencies (as of 2026-03-09)
The following were removed during the Unsplash/API cleanup:
- `dio: ^5.4.3+1` -- HTTP client
- `retrofit: ^4.1.0` -- Declarative API client generation
- `mobx: ^2.3.3+2` -- Reactive state management
- `flutter_mobx: ^2.2.1+1` -- MobX Flutter bindings
- `provider: ^6.1.2` -- Dependency injection
- `json_annotation: ^4.8.1` -- JSON model annotations
- `flutter_svg: ^2.0.17` -- SVG icon rendering
- `build_runner: ^2.11.1` -- Code generation runner
- `json_serializable: ^6.7.1` -- fromJson/toJson generation
- `retrofit_generator: ^10.2.1` -- Retrofit HTTP client generation
- `mobx_codegen: ^2.6.1` -- MobX observable/action generation

Previously removed during SSD cleanup (2026-03-05):
- `tflite_flutter: 0.11.0` -- SSD MobileNet inference engine
- `image: ^4.5.2` -- Image encoding/decoding/resizing for SSD
- `camera: ^0.11.3+1` -- Live camera feed for SSD path
- `image_picker: ^1.1.2` -- Gallery/camera photo selection for SSD photo analysis
- `path_provider: ^2.1.0` -- Device directory access

## Backend Selection: Environment Variable
The active ML backend is selected **at build time** via the `DETECTOR_BACKEND` Dart environment variable:

```bash
# Run with YOLO (the only backend -- also the default)
flutter run --dart-define=DETECTOR_BACKEND=yolo
# or simply:
flutter run
```

This is read in both `main.dart` and `lib/config/detector_config.dart` via:
```dart
const backend = String.fromEnvironment('DETECTOR_BACKEND', defaultValue: 'yolo');
```

The infrastructure supports adding future backends by extending the `DetectorBackend` enum and adding cases to the switch statements in `detector_config.dart` and `main.dart`.

## Code Generation
No code generation is needed. The `build_runner` pipeline was removed along with MobX, Retrofit, and json_serializable dependencies on 2026-03-09.

## Platform-Specific Configurations

### Android
- `AndroidManifest.xml`: `android:hardwareAccelerated="true"`, `launchMode="singleTop"`
- Model location: `android/app/src/main/assets/yolo11n.tflite` (must be placed manually)
- `build.gradle`: `aaptOptions { noCompress 'tflite' }` -- critical for TFLite model integrity
- `MainActivity.kt`: MethodChannel `"com.flare/display"` for rotation polling
- `gradle.properties`: `org.gradle.jvmargs=-Xmx4G`, JDK 17 path
- Supported orientations: portrait + landscape

### iOS
- `Info.plist`: Camera usage description set (placeholder text -- must update before external demo), Photo Library usage description set
- Model location: `ios/yolo11n.mlpackage` (must be placed manually), added to Xcode target -> Build Phases -> Copy Bundle Resources
- Supported orientations: portrait + landscape (left + right)
- Xcode build reference: `9883D8872F43899800AEC4E1 /* yolo11n.mlpackage in Resources */`
- **Camera session preset:** `ultralytics_yolo` plugin uses `.photo` preset -> camera captures at 4032x3024 (4:3 aspect ratio). This is critical for FILL_CENTER coordinate mapping -- using 16:9 causes ~10% Y-axis offset.
- **Podfile:** `PERMISSION_CAMERA=1` in `GCC_PREPROCESSOR_DEFINITIONS` (required by `permission_handler` to compile camera permission code on iOS)
- **Camera permission:** `ultralytics_yolo` v0.2.0 does NOT request camera permission on iOS (checks status but returns false on `.notDetermined`). App explicitly requests via `permission_handler` in `_requestCameraPermission()`. Free dev certificates expire every 7 days; deleting app wipes permission state.

## Asset Structure
- `assets/audio/` -- 10 M4A audio assets for impact feedback (`zone_1-9.m4a` + `miss.m4a`). Zone files contain "You hit N!" + crowd cheer (~4.7s each). Generated via macOS TTS (Samantha, rate 170) + Pixabay crowd cheer SFX, composited with ffmpeg.
- `assets/audio/originals/` -- Backup of original plain number callout audio files (pre-2026-03-19)
- YOLO model files placed in platform-specific locations (see above)

## Files That Must Be Placed Manually
| File | Platform | Where to place |
|---|---|---|
| `yolo11n.tflite` | Android | `android/app/src/main/assets/` (create dir if needed) |
| `yolo11n.mlpackage` | iOS | `ios/` directory, then add to Xcode target resources |

## Linting
- `analysis_options.yaml` extends `package:flutter_lints/flutter.yaml`
- Standard Flutter recommended lint rules
- Current lint status: **0 errors, 0 warnings, 28 infos** (26 `avoid_print` from intentional diagnostic prints + 2 `unnecessary_import` in test files)

## Version Control
- No git repository -- `.git` directory removed by developer decision (2026-03-05)
- Project is local-only, not pushed to GitHub or any remote
