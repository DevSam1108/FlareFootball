# System Patterns

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## High-Level Architecture

The app has a single YOLO detection pipeline. The `DETECTOR_BACKEND` environment variable infrastructure is preserved for future extensibility but currently only `yolo` is implemented. The codebase has been aggressively slimmed -- all non-detection code (Unsplash API, MobX, Retrofit, Dio, data models) was removed on 2026-03-09.

```
+-----------------------------------------------------+
|                     main.dart                        |
|  reads DETECTOR_BACKEND env var at startup           |
|  default = 'yolo' (only backend implemented)         |
+---------------------------+--------------------------+
                            | yolo
                            v
                   +----------------------+
                   |   ultralytics_yolo    |
                   |   (YOLO11n)           |
                   |   Platform-native     |
                   |   ACTIVE              |
                   +-----------+----------+
                               |
                               v
                   +----------------------+
                   |  YOLOView widget      |
                   |  (self-contained)     |
                   +-----------+----------+
                               | onResult(List<YOLOResult>)
                               v
                   +----------------------+
                   |  _pickBestBallYolo()  |
                   |  (priority filter +   |
                   |   nearest-neighbor)   |
                   +-----------+----------+
                               | Offset (normalized)
                               v
                   +----------------------+
                   |  BallTracker         |
                   |  (service -- no       |
                   |   Flutter deps)       |
                   |  - bounded ListQueue  |
                   |  - occlusion sentinel |
                   |  - 30-frame auto-reset|
                   |  - min-dist dedup     |
                   +-----------+----------+
                               | trail: List<TrackedPosition>
                               v
                   +----------------------+
                   |  TrailOverlay         |
                   |  (CustomPainter)      |
                   |  - fading orange dots |
                   |  - connecting lines   |
                   |  - occlusion gaps     |
                   |  - YoloCoordUtils     |
                   |    (FILL_CENTER crop) |
                   +----------------------+

              Pipeline feeds (when _pipelineLive):
              +----------------------+        +---------------------+
              |  KickDetector        |        |  ImpactDetector      |
              |  (4-state gate)      | -----> |  (state machine)     | ---> AudioService
              |  idle/confirm/active/|        |  Ready->Track->Result|      zone_1-9.m4a
              |  refractory          |        |  Decision signal:    |       miss.m4a
              +----------------------+        |  last directZone     |
              Result gate accepts              |  (ball's actual pos  |
              confirming OR active             |   via pointToZone)   |
              (tickResultTimeout() called      +---------------------+
               every frame outside kick gate)

              Decision priority (2026-04-09, ADR-063):
              1. Edge exit → MISS
              2. Last observed directZone → HIT zone N
              3. No directZone → noResult
              (WallPlanePredictor/extrapolation removed from decisions)
```

---

## Design Patterns Used

### 1. Singleton -- Services
`NavigationService` and `SnackBarService` are implemented as Dart singletons using a private named constructor pattern. New services should follow the same pattern.

### 2. Enum-Driven Backend Config -- DetectorConfig
The active backend is expressed as an enum:
```dart
enum DetectorBackend { yolo }
```
`DetectorConfig.backend` reads the compile-time environment variable and returns the appropriate enum value. Default is `yolo`. New backends can be added by extending the enum and adding a case to the switch.

### 3. Platform-Aware Model Loading -- YOLO Path
The YOLO model path is resolved differently per platform at the widget level:
```dart
modelPath: Platform.isIOS ? 'yolo11n' : 'yolo11n.tflite'
```
- iOS: `'yolo11n'` -- `ultralytics_yolo` loads this as a Core ML mlpackage from the Xcode bundle
- Android: `'yolo11n.tflite'` -- package loads from `android/app/src/main/assets/`

### 4. Custom Painter Overlay -- YOLO Trail
The ball trail renders as a `CustomPainter` layered above `YOLOView` using a `Stack`:
```dart
Stack(
  fit: StackFit.expand,
  children: [
    YOLOView(..., showOverlays: false, onResult: ...),
    RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: TrailOverlay(trail: _tracker.trail, ...),
        ),
      ),
    ),
    // Back button badge (circular, top-left)
    // "Ball lost" badge (top-right)
    // Other badge overlays (Positioned widgets)
  ],
)
```
Key constraints:
- `showOverlays: false` suppresses native YOLO bounding boxes
- `RepaintBoundary` isolates repaint to the overlay layer only
- `IgnorePointer` prevents the overlay from consuming touch events
- `TrailOverlay.shouldRepaint` always returns `true` (list identity is unreliable)

### 5. Normalized Coordinate + FILL_CENTER Crop Correction
YOLO detection coordinates are normalized to [0.0, 1.0] relative to the **full camera frame**. `YOLOView` renders using FILL_CENTER (BoxFit.cover): the camera preview is scaled to fill the widget, cropping one dimension. `YoloCoordUtils.toCanvasPixel()` corrects for this crop:
```dart
if (widgetAR > cameraAspectRatio) {
  // Widget wider -> scaled by width, height cropped
  final scaledHeight = size.width / cameraAspectRatio;
  final cropY = (scaledHeight - size.height) / 2.0;
  pixelX = normalized.dx * size.width;
  pixelY = normalized.dy * scaledHeight - cropY;
} else {
  // Widget taller -> scaled by height, width cropped
  final scaledWidth = size.height * cameraAspectRatio;
  final cropX = (scaledWidth - size.width) / 2.0;
  pixelX = normalized.dx * scaledWidth - cropX;
  pixelY = normalized.dy * size.height;
}
```
**Camera AR = 4:3** (not 16:9). `ultralytics_yolo` uses `.photo` session preset on iOS (4032x3024).

---

## Data Flow: YOLO Live Detection

```
Physical camera hardware
        |
        v
  YOLOView widget (ultralytics_yolo)
  |-- manages camera session internally (.photo preset -> 4032x3024 on iOS)
  |-- feeds frames to YOLO11n model
  |     |-- Android: TFLite runtime
  |     +-- iOS: Core ML runtime
  |-- runs inference per frame
  +-- fires onResult(List<YOLOResult>)
            |
            v
      onResult callback in LiveObjectDetectionScreen
      |-- if (!mounted) return   (setState-after-dispose guard)
      |-- _pickBestBallYolo(results)
      |     |-- filter: keep 'Soccer ball' (priority 0), 'ball' (priority 1), 'tennis-ball' (priority 2)
      |     |-- sort by priority, then confidence within same class
      |     +-- tiebreak multiple same-priority candidates by nearest-to-lastKnownPosition
      +-- setState(() {
            if (_awaitingReferenceCapture) -> store bbox area for reference
            if (_pipelineLive):
              ball != null -> _tracker.update(normalizedCenter)
              ball == null -> _tracker.markOccluded()
            else: YOLO output ignored (silent)
          })
                    |
                    v
              BallTracker
              |-- update(): dedup, append TrackedPosition, prune expired
              |-- markOccluded(): increment miss count, insert sentinel, auto-reset at 30 frames
              +-- trail getter -> List<TrackedPosition> (unmodifiable snapshot)
                          |
                          v
                    TrailOverlay (CustomPainter)
                    |-- connecting lines between non-occluded consecutive positions
                    |     (opacity fades with age, orange)
                    +-- dots at each non-occluded position
                          (radius 2-7px, opacity fades with age, orange)
                          via YoloCoordUtils.toCanvasPixel() (FILL_CENTER crop correction)

              (When _pipelineLive == true -- after calibration + reference confirm):
              BallTracker.velocity + TrajectoryExtrapolator
                          |
                          v
                    ImpactDetector.processFrame()
                    |-- State machine: Ready -> Tracking -> Result -> Ready
                    |-- Tracking: ball moving with velocity, 3+ frames (ADR-047)
                    |-- Decision (ball lost 5+ frames):
                    |     1. Edge exit (8% of frame edge) -> MISS
                    |     2. Depth-verified direct zone (ADR-051) -> HIT (preferred)
                    |     3. Trajectory intersects target -> HIT (fallback)
                    |     4. Neither -> noResult
                    +-- Phase transition to Result triggers:
                          |-- Visual: large zone number / MISS overlay (3s)
                          +-- Audio: AudioService.playImpactResult() (once)
```

---

## Screen / Navigation Structure

```
Routes (lib/values/app_routes.dart):
  '/'         -> HomeScreen (minimal launcher with "Start Detection" button)
  '/camera/'  -> LiveObjectDetectionScreen

NavigationService (singleton) wraps Navigator for programmatic routing.
```

Note: The PhotoAnalyzeScreen (`/detail/`) was removed on 2026-03-05. The Unsplash grid home screen was replaced with a minimal launcher on 2026-03-09.

## Orientation Strategy
| Screen | Orientation |
|---|---|
| HomeScreen | Portrait only |
| LiveObjectDetectionScreen | Landscape only (forced in initState, restored in dispose) |

`_tracker.reset()` is called in `dispose` before orientation restore.

---

## Android-Specific Patterns

### 6. MethodChannel for Display Rotation Polling
The `ultralytics_yolo` Android plugin does not distinguish landscape-left from landscape-right -- it uses `Configuration.ORIENTATION_LANDSCAPE` uniformly. iOS handles this in the plugin via `AVCaptureVideoOrientation`. On Android, normalizedBox coordinates are relative to the camera sensor's native orientation, so when the device is in the "non-native" landscape direction, coordinates need a 180-degree rotation.

**Platform code:** `MainActivity.kt` exposes a `"com.flare/display"` MethodChannel:
```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.flare/display")
    .setMethodCallHandler { call, result ->
        if (call.method == "getRotation") {
            val rotation = (getSystemService(WINDOW_SERVICE) as WindowManager)
                .defaultDisplay.rotation
            result.success(rotation)  // Surface.ROTATION_0=0, _90=1, _180=2, _270=3
        }
    }
```

**Dart side:** `_pollDisplayRotation()` polls every 500ms via a `Timer.periodic`. When `_androidDisplayRotation == 3` (landscape-right), coordinates are flipped:
```dart
if (Platform.isAndroid && _androidDisplayRotation == 3) {
  dx = 1.0 - dx;
  dy = 1.0 - dy;
}
```

**Status:** Device-verified on Galaxy A32 as of 2026-02-25.

### 8. AudioService Singleton with Lazy Player (Phase 4)
`AudioService` follows the singleton pattern but creates the `AudioPlayer` lazily on first playback. This avoids triggering `audioplayers` platform channels at app startup and simplifies unit testing (tests that don't call playback never touch platform channels).

```dart
class AudioService {
  AudioService._();
  static final instance = AudioService._();
  AudioPlayer? _player;

  Future<void> playImpactResult(ImpactEvent event) async {
    switch (event.result) {
      case ImpactResult.hit:
        if (event.zone != null) {
          _player ??= AudioPlayer();
          await _player!.play(AssetSource('audio/zone_${event.zone}.m4a'));
        }
      case ImpactResult.miss:
        _player ??= AudioPlayer();
        await _player!.play(AssetSource('audio/miss.m4a'));
      case ImpactResult.noResult:
        break;
    }
  }
}
```

Audio is triggered once per impact using **phase-transition detection**: capture `prevPhase` before `processFrame()`, then check if phase changed to `result` afterward. This prevents duplicate plays during the 3-second result display. `stop()` is called before `play()` to ensure clean player state when switching between different audio sources (e.g., zone callout → miss).

### 10. Extrapolation Retention in ImpactDetector (Updated ADR-047, 2026-03-17)
**History:** Originally `_bestExtrapolation` was only updated when non-null (ISSUE-007 caused stale false HITs). Changed to always-latest (including null) to fix. ADR-047 refines this:
- **When ball IS detected:** Always use latest value (including null) — if trajectory no longer intersects target, that's real information. Prevents ISSUE-007 false HITs.
- **When ball is NOT detected (occlusion):** Retain the last valid extrapolation. Absence of detection is not new trajectory information.
- **During occlusion:** Recompute extrapolation using Kalman-predicted state (position + velocity remain valid during predict-only phase). This aligns the impact detector with what the trail overlay shows visually.

### 11. Explicit Camera Permission Request (permission_handler)
`ultralytics_yolo` v0.2.0 on iOS only **checks** camera authorization status but never **requests** it. When status is `.notDetermined` (fresh install), the plugin silently fails. The app uses `permission_handler` to explicitly call `Permission.camera.request()` in `initState`, gating `YOLOView` rendering behind a `_cameraReady` flag. iOS requires `PERMISSION_CAMERA=1` in Podfile `GCC_PREPROCESSOR_DEFINITIONS`. Android side of `ultralytics_yolo` does request permissions internally, but `permission_handler` handles it uniformly on both platforms.

### 13. Pipeline Gating (`_pipelineLive` Boolean)
The detection pipeline (BallTracker, TrailOverlay, ImpactDetector, AudioService) is gated behind a single `_pipelineLive` boolean. YOLO runs from camera open, but its output is only fed into the pipeline after calibration + reference ball confirm. This enforces 4 clear stages:
1. **Preview** — camera open, YOLO silent, no dots/badges/impact
2. **Calibration** — tapping + dragging corners, YOLO silent
3. **Reference Capture** — YOLO used only for bbox area detection (for reference ball), no tracker/impact
4. **Live** — `_pipelineLive = true`, full pipeline active

`_pipelineLive` is set `true` in `_confirmReferenceCapture()` and `false` in `_startCalibration()` (re-calibrate resets pipeline).

### 14. KickDetector Result Gate
`KickDetector` (`lib/services/kick_detector.dart`) gates **result acceptance only** — not pipeline input. `ImpactDetector.processFrame()` runs unconditionally every frame. KickDetector's `isKickActive` flag controls whether a result is announced (audio + overlay). Four signal layers:

1. **Jerk gate** — `jerk = |accel[t] - accel[t-1]|` where `accel = |speed[t] - speed[t-1]|`. Kicks go 0→max speed in 1-2 frames; dribbling ramps slowly. `jerkThreshold = 0.01`.
2. **Energy sustain** — Speed must stay ≥ `sustainThreshold = 0.005` for `sustainFrames = 3` consecutive frames after the jerk spike.
3. **Direction filter** — `velocity · (goalCenter - ballPosition) > 0` (dot product). Rejects ball moving away from calibrated target.
4. **Refractory period** — 20-frame cooldown after `onKickComplete()`. Prevents double-firing.

**IMPORTANT:** An earlier attempt (2026-04-08) to gate `ImpactDetector.processFrame()` behind KickDetector state broke grounded kick detection — KickDetector's jerk threshold doesn't fire for low-velocity shots. This was reverted (ADR-061, ISSUE-025). KickDetector must only gate output, not input.

`tickResultTimeout()` is called **outside** the kick gate every frame to ensure the 3-second result display always expires, even when no kick is in progress. This prevents the stuck overlay bug.

```dart
// In live screen onResult callback (simplified):
_kickDetector.processFrame(ballDetected: ..., velocity: ..., ballPosition: ..., goalCenter: _goalCenter);
_impactDetector.tickResultTimeout(); // Always called
_impactDetector.processFrame(...);   // Always called — unconditional
if (/* phase changed to result */ && _kickDetector.isKickActive) {
  // Only ANNOUNCE when kick is confirmed
  _audioService.playImpactResult(...);
  _kickDetector.onKickComplete();
}
```

### 15. Dynamic sharePositionOrigin via GlobalKey
iOS 13+ requires `sharePositionOrigin: Rect` to be non-zero when calling `Share.shareXFiles` from iPad, and iOS 26.3.1 now enforces it on iPhone landscape too. The correct Flutter pattern is:

```dart
final _shareButtonKey = GlobalKey();

// In _shareLog():
final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : Rect.zero;
await Share.shareXFiles([XFile(path)], sharePositionOrigin: origin);
```

Attach `key: _shareButtonKey` to the widget the share action originates from. The `&` operator on `Offset` and `Size` creates a `Rect`. Falls back to `Rect.zero` if the render object is unavailable. This pattern works on any screen size, device type, or orientation.

### 12. Full-Screen Detection View (No AppBar)
The detection screen Scaffold has no `appBar`. Navigation back to home is via a circular back arrow icon button (`GestureDetector` + `Navigator.of(context).pop()`) at `Positioned(top: 12, left: 12)`. This reclaims ~56px vertical height in landscape mode. The button style matches other badge overlays: `Colors.black54`, rounded.

### 9. aaptOptions for TFLite Model Integrity
Android's `build.gradle` must include `aaptOptions { noCompress 'tflite' }` inside the `android {}` closure. Without this, Gradle compresses the `.tflite` file during APK packaging, which corrupts TFLite's memory-mapped loading. This was the root cause for `onResult` not firing on Android (fixed in Phase 9).

---

## Key File Map

| Concern | File(s) |
|---|---|
| Entry point + backend init | `lib/main.dart` |
| Backend enum + config | `lib/config/detector_config.dart` |
| Route definitions | `lib/values/app_routes.dart`, `lib/routes.dart` |
| App root | `lib/app.dart` |
| YOLO live screen | `lib/screens/live_object_detection/live_object_detection_screen.dart` |
| YOLO trail painter | `lib/screens/live_object_detection/widgets/trail_overlay.dart` |
| Ball tracker service | `lib/services/ball_tracker.dart` |
| Trail position model | `lib/models/tracked_position.dart` |
| YOLO coordinate utilities | `lib/utils/yolo_coord_utils.dart` |
| Homography transform (DLT) | `lib/services/homography_transform.dart` |
| Target zone mapper (1-9) | `lib/services/target_zone_mapper.dart` |
| Calibration overlay painter | `lib/screens/live_object_detection/widgets/calibration_overlay.dart` |
| Impact event model | `lib/models/impact_event.dart` |
| Impact detector (state machine) | `lib/services/impact_detector.dart` |
| Kalman filter (4-state) | `lib/services/kalman_filter.dart` |
| Trajectory extrapolator | `lib/services/trajectory_extrapolator.dart` |
| Home screen (launcher) | `lib/screens/home/home_screen.dart` |
| Navigation | `lib/services/navigation_service.dart` |
| Snackbar service | `lib/services/snackbar_service.dart` |
| Audio feedback service | `lib/services/audio_service.dart` |
| Audio assets (TTS clips) | `assets/audio/zone_1-9.m4a`, `assets/audio/miss.m4a` |
| Rotate-to-landscape overlay | `lib/screens/live_object_detection/widgets/rotate_device_overlay.dart` |
| Android rotation channel | `android/app/.../MainActivity.kt` |
