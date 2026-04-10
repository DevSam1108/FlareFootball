# Phase 6: Overlay Foundation - Research

**Researched:** 2026-02-23
**Domain:** Flutter CustomPainter overlay on platform view (YOLOView/CameraPreview), coordinate extraction, mounted-check guards
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

All implementation details are at Claude's discretion for this phase. The following constraints from prior research MUST be honored:
- Use `normalizedBox.center` on YOLO path (already 0-1 coordinates)
- Normalize `renderLocation` by `ScreenParams.screenPreviewSize` on SSD path
- Set `showOverlays: false` on YOLOView (verify availability first)
- Add `if (!mounted) return` guard to all detection callbacks
- Wrap overlay in `RepaintBoundary` for rendering isolation

### Claude's Discretion

- Debug dot appearance (color, size, opacity)
- Whether to show diagnostic text (coordinates, FPS, confidence) on screen
- Whether YOLO and SSD paths produce identical or slightly different visual output
- How to validate coordinate accuracy (visual inspection vs debug logging)
- Error handling approach when detection returns no results

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OVLY-01 | User can see ball center-point extracted from YOLO detection results using normalizedBox coordinates | Confirmed: `YOLOResult.normalizedBox` is a `Rect` in 0.0–1.0 space. Center is `normalizedBox.center` (a `dart:ui` `Offset`). Available in `ultralytics_yolo 0.2.0` — verified from pub cache source. `onResult` fires per frame with `List<YOLOResult>`. |
| OVLY-02 | User can see ball center-point extracted from SSD detection results with coordinate normalization via ScreenParams | Confirmed: `DetectedObjectDm.renderLocation` returns a `Rect` in screen-pixel space scaled by `ScreenParams.screenPreviewSize`. Center is `renderLocation.center`. Normalize by dividing `.dx / ScreenParams.screenPreviewSize.width` and `.dy / ScreenParams.screenPreviewSize.height`. |
| OVLY-03 | Native YOLOView bounding box overlay is disabled so custom trail overlay is the only rendering layer | Confirmed: `YOLOView` in `ultralytics_yolo 0.2.0` exposes `showOverlays: bool` (default `true`). Setting `showOverlays: false` disables BOTH native platform overlays (Android `OverlayView`, iOS `boundingBoxViews`/`overlayLayer`) AND the internal Flutter `YOLOOverlay` widget. Verified from source. No native code patching required. |
| OVLY-04 | All detection callbacks guard against setState after dispose with mounted check | The `onResult` callback in the current YOLO path has no `mounted` guard (only a `log()` call). The SSD path's `resultsStream.listen` already has `if (mounted) setState(...)`. OVLY-04 requires adding `if (!mounted) return;` as the first line of the `onResult` callback before any state mutation. |

</phase_requirements>

---

## Summary

Phase 6 is a correctness gate. Its sole deliverable is a debug dot that reliably centers on the detected ball in the live camera view on both pipelines and both target devices — proving coordinate extraction and overlay rendering are correct before any trail accumulation is built in Phase 7.

The codebase is in a known state: `YOLOView` is rendering with `showOverlays: true` (native boxes visible), and the `onResult` callback only calls `log()` with no state updates. The SSD path already renders bounding boxes via `BoxWidget` and uses `ScreenParams` for coordinate scaling. Neither path has a custom Flutter overlay yet.

All required APIs are confirmed in the installed package source (`ultralytics_yolo 0.2.0`, pub cache inspected directly). `showOverlays: false` is a constructor parameter that works at the Flutter layer — no native platform code changes are needed. `normalizedBox` is a `Rect` field in `YOLOResult` containing 0.0–1.0 values relative to `orig_shape`. The `onResult` callback is called on the main isolate. The SSD `resultsStream.listen` already has a `mounted` guard that must be preserved and extended.

**Primary recommendation:** Add a single `CustomPaint` widget to the existing `Stack` on each pipeline, extract `normalizedBox.center` on YOLO and compute normalized center from `renderLocation` on SSD, render a single fixed-radius dot at that position, and guard all state mutations with `if (!mounted) return`. Ship nothing more until the dot tracks accurately on both devices.

---

## Standard Stack

### Core

All technologies required for this phase are already in the project. No new dependencies are needed.

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Flutter `CustomPainter` + `CustomPaint` | SDK built-in | Draw a debug dot on a transparent canvas layer above the camera | The canonical Flutter approach for per-frame 2D drawing. Zero allocation overhead compared to widget-based approaches. |
| Flutter `Stack` + `StackFit.expand` | SDK built-in | Layer the `CustomPaint` above `YOLOView` or `CameraPreview` | Already used in both pipeline branches of `live_object_detection_screen.dart`. |
| `RepaintBoundary` | SDK built-in | Scope `CustomPaint` repaints to the overlay layer only | Required to prevent the debug dot's `setState`-triggered repaints from invalidating the camera or AppBar layers. |
| `ultralytics_yolo 0.2.0` | `^0.2.0` (pinned) | `YOLOResult.normalizedBox`, `YOLOView.showOverlays`, `onResult` callback | Already installed. Source inspected in pub cache. |
| `dart:ui` `Canvas`, `Paint`, `Offset` | SDK built-in | Draw the dot circle | Standard canvas primitives. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `flutter/services.dart` `SystemChrome` | SDK built-in | Preserve landscape orientation lock | Already imported. Not changing orientation behavior in this phase. |

### No New Dependencies

```bash
# No new packages. All APIs are in SDK or already installed.
flutter pub get
```

---

## Architecture Patterns

### Recommended Structure for This Phase

No new files are required for Phase 6. The debug dot lives entirely in `live_object_detection_screen.dart` as a private helper method and a `CustomPainter` subclass (defined at the bottom of the file or in a minimal new file).

If a new file is created, place it at:
```
lib/screens/live_object_detection/widgets/debug_dot_overlay.dart
```

This keeps overlay code co-located with the screen and avoids cluttering `lib/widgets/` which holds shared widgets.

### Pattern 1: YOLO Path Debug Dot

**What:** Replace the `log()` body of `onResult` with state extraction and a `setState` call. Add a `CustomPaint` to the YOLO `Stack`.

**Step-by-step:**

```dart
// 1. Add state field to _LiveObjectDetectionScreenState
Offset? _debugDotPosition; // null when no detection; 0.0–1.0 normalized

// 2. Replace the onResult body
onResult: (results) {
  if (!mounted) return; // OVLY-04: mounted guard required

  final ball = _pickBestBall(results); // filter by className
  final newDot = ball != null
      ? Offset(
          ball.normalizedBox.center.dx, // normalizedBox is Rect in 0.0–1.0
          ball.normalizedBox.center.dy,
        )
      : null;

  setState(() => _debugDotPosition = newDot);
},

// 3. Add _pickBestBall helper (YOLO path)
YOLOResult? _pickBestBall(List<YOLOResult> results) {
  const ballClasses = {'Soccer ball', 'ball', 'tennis-ball'};
  final candidates = results
      .where((r) => ballClasses.contains(r.className))
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
  return candidates.first;
}

// 4. Add CustomPaint to the YOLO Stack (above YOLOView, below label badge)
RepaintBoundary(
  child: CustomPaint(
    painter: _DebugDotPainter(dotPosition: _debugDotPosition),
  ),
),

// 5. Add showOverlays: false to YOLOView (OVLY-03)
YOLOView(
  modelPath: Platform.isIOS ? 'yolo11n' : 'yolo11n.tflite',
  task: YOLOTask.detect,
  showOverlays: false, // disables native boxes AND internal Flutter YOLOOverlay
  onResult: _handleYoloResult, // or inline
),
```

**Source:** `ultralytics_yolo-0.2.0/lib/yolo_view.dart` lines 35, 54, 273 — `showOverlays` is a constructor parameter with default `true`. Setting `false` prevents `YOLOOverlay` from rendering (condition `if (widget.showOverlays && _currentDetections.isNotEmpty)` at line 273 fails). The `showOverlays: false` is also passed to native via `creationParams` (line 322), disabling Android's `OverlayView` draws and iOS's `boundingBoxViews.show()`.

### Pattern 2: SSD Path Debug Dot

**What:** Extend the existing `resultsStream.listen` callback to also extract the ball center and set `_debugDotPosition`. Add the same `CustomPaint` to the SSD `Stack`.

```dart
// Extend the existing resultsStream listener
_objectDetectorStream = detector.resultsStream.listen((detectedObjects) {
  if (mounted) setState(() {
    detectedObjectList = detectedObjects; // existing
    _debugDotPosition = _pickBestBallSsd(detectedObjects); // new
  });
});

// SSD pick helper — returns normalized Offset
Offset? _pickBestBallSsd(List<DetectedObjectDm> objects) {
  // SSD MobileNet uses COCO labels — 'sports ball' is the target class
  // The custom YOLO model's classes are not used on the SSD path
  final candidates = objects
      .where((o) => o.label.toLowerCase().contains('ball'))
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final best = candidates.first;
  final previewSize = ScreenParams.screenPreviewSize;
  // renderLocation is in screen-pixel space; normalize to 0.0–1.0
  return Offset(
    best.renderLocation.center.dx / previewSize.width,
    best.renderLocation.center.dy / previewSize.height,
  );
}
```

**Coordinate system note:** `ScreenParams.screenPreviewSize` returns `Size(screenSize.width, screenSize.width * previewRatio)` where `previewRatio` is the max/min ratio of the preview's capture dimensions. The `CameraPreview` is wrapped in `AspectRatio(aspectRatio: 1 / controller.value.aspectRatio)` which constrains it to this size. The `CustomPaint` placed inside the same `Stack` (inside the same `AspectRatio`) receives the same size in its `paint(Canvas, Size)` call — so dividing by `screenPreviewSize` and then multiplying by `size` in `paint()` is consistent.

### Pattern 3: Debug Dot CustomPainter

**What:** A minimal `CustomPainter` that draws one circle when `dotPosition != null`.

```dart
class _DebugDotPainter extends CustomPainter {
  final Offset? dotPosition; // null = no detection this frame

  const _DebugDotPainter({required this.dotPosition});

  @override
  void paint(Canvas canvas, Size size) {
    final pos = dotPosition;
    if (pos == null) return;

    // Map normalized coords to canvas pixels
    final pixel = Offset(pos.dx * size.width, pos.dy * size.height);

    canvas.drawCircle(
      pixel,
      8.0,
      Paint()
        ..color = Colors.red.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );
    // Optional: outline for visibility on light backgrounds
    canvas.drawCircle(
      pixel,
      8.0,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_DebugDotPainter old) =>
      old.dotPosition != dotPosition;
}
```

**Why this approach:** `shouldRepaint` compares the previous `dotPosition` to the new one and repaints only when it changes. When the ball is not detected on a frame, `dotPosition` is `null` and `shouldRepaint` returns `false` only if it was already `null` — preventing unnecessary paint calls.

### Pattern 4: Diagnostic Overlay (Optional — Claude's Discretion)

To validate coordinate accuracy during testing, add a `Text` widget in the `Stack` showing the raw coordinates and confidence. Remove before Phase 7.

```dart
// Optional diagnostic badge (above the debug dot layer)
if (_debugDotPosition != null)
  Positioned(
    bottom: 12,
    left: 12,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.black54,
      child: Text(
        'dot: (${_debugDotPosition!.dx.toStringAsFixed(3)}, '
            '${_debugDotPosition!.dy.toStringAsFixed(3)})',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    ),
  ),
```

### Widget Tree After Changes

**YOLO path:**
```
Scaffold → body → Stack(StackFit.expand)
  ├── YOLOView(showOverlays: false, onResult: _handleYoloResult)
  │     └── [internal Stack: AndroidView/UiKitView only — no native boxes]
  ├── RepaintBoundary
  │     └── CustomPaint(painter: _DebugDotPainter(dotPosition: _debugDotPosition))
  └── Positioned(top:12, left:12) — backend label badge [unchanged]
```

**SSD path:**
```
Scaffold → body → Column
  └── AspectRatio(1/controller.aspectRatio)
        └── Stack(StackFit.expand)
              ├── CameraPreview(controller)
              ├── ...BoxWidget bounding boxes [unchanged]
              ├── RepaintBoundary
              │     └── CustomPaint(painter: _DebugDotPainter(dotPosition: _debugDotPosition))
              └── Positioned(top:12, left:12) — backend label badge [unchanged]
```

### Anti-Patterns to Avoid

- **Storing pixel coordinates in `_debugDotPosition`:** Both pipelines must store normalized (0.0–1.0) values. The painter multiplies by `size` at draw time. Storing raw pixels breaks on device rotation and makes the two pipelines incompatible.
- **Removing the `mounted` check from the existing SSD stream listener:** The SSD listener already has `if (mounted) setState(...)`. When extending it to update `_debugDotPosition`, keep it inside the same guarded `setState` block — do not add a second unguarded `setState`.
- **Setting `showOverlays: false` and skipping the `onResult` callback:** The debug dot requires `onResult` to fire. `showOverlays: false` affects box rendering only — results are still delivered to `onResult` regardless of this flag. Confirmed: `widget.onResult!(results)` at line 151 of `yolo_view.dart` is called unconditionally.
- **Placing `RepaintBoundary` inside the `CustomPaint` rather than outside:** `RepaintBoundary` must wrap `CustomPaint`, not be wrapped by it. `CustomPaint(child: RepaintBoundary(...))` does nothing for isolation.
- **Using `AnimationController` for the debug dot:** Phase 6 is a correctness gate, not a rendering quality gate. Drive repaints purely via `setState` in the detection callback. `AnimationController` is for Phase 7's trail fading, not needed here.

---

## Critical Discovery: `showOverlays` Behavior is NOT Obvious

**This finding corrects potential misreading of the `showOverlays` parameter.**

From direct source inspection of `ultralytics_yolo-0.2.0/lib/yolo_view.dart`:

```dart
// _handleDetectionResults (lines 133-155)
if (widget.showOverlays && widget.onResult != null) {
  if (_currentDetections.isNotEmpty) {
    setState(() { _currentDetections = []; }); // clears Flutter overlay list
  }
} else {
  setState(() { _currentDetections = results; }); // populates Flutter overlay list
}
widget.onResult!(results); // always called regardless of showOverlays

// build() (lines 268-285)
return Stack(children: [
  _buildCameraView(), // platform view (AndroidView / UiKitView)
  if (widget.showOverlays && _currentDetections.isNotEmpty)
    YOLOOverlay(detections: _currentDetections, ...), // Flutter overlay
]);
```

**What this means:**
- `showOverlays: true` (default) → native platform renders boxes (Android `OverlayView`, iOS `boundingBoxViews`) AND the internal Flutter `YOLOOverlay` condition fails because `_currentDetections` is always cleared → no Flutter boxes. **`onResult` is still called.**
- `showOverlays: false` → native platform does NOT render boxes AND `_currentDetections` is populated with results → internal Flutter `YOLOOverlay` renders Flutter-drawn boxes. **But:** `if (widget.showOverlays && ...)` in `build()` is `false`, so `YOLOOverlay` is NOT rendered either.

**Net result for OVLY-03:** `showOverlays: false` disables ALL rendering from `YOLOView` — both native boxes and the internal Flutter `YOLOOverlay`. The camera feed is visible with no overlays at all. Our custom `CustomPaint` in the parent `Stack` will be the only overlay rendered. `onResult` continues to fire with detection data regardless.

**The `YOLOOverlay` uses `boundingBox` (pixel coords), not `normalizedBox`.** The Flutter `YOLOOverlay` in the package draws using `detection.boundingBox.left/top/right/bottom` which are pixel coordinates relative to the platform view's dimensions. This is important context for Phase 7 — when the trail painter uses `normalizedBox` to compute positions, it must map to the `CustomPaint` canvas size, not the raw platform view pixel dimensions.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Normalized coordinate extraction (YOLO) | Custom coordinate transform | `result.normalizedBox.center` directly | `normalizedBox` is already 0.0–1.0 per axis relative to the rendered frame. No transform needed. |
| Disabling native bounding box overlay | Patch native Android/iOS plugin source | `YOLOView(showOverlays: false)` | Flutter constructor parameter passes to native via `creationParams`. Already implemented in v0.2.0. |
| Per-frame canvas drawing | `AnimationController` ticker | `setState` in `onResult` triggers `CustomPainter.shouldRepaint` | Detection callbacks are already per-frame. Driving repaints from the detection callback is simpler and correct. AnimationController is only needed for time-based fading (Phase 7). |

---

## Common Pitfalls

### Pitfall 1: `showOverlays: false` Does Not Stop `onResult` from Firing

**What goes wrong:** Developer assumes `showOverlays: false` will stop detection callbacks to reduce CPU load during debugging.

**Why it happens:** The name suggests "no overlays = no detection." But `onResult!(results)` at line 151 of `yolo_view.dart` is called unconditionally — `showOverlays` only controls rendering, never inference or callback delivery.

**How to avoid:** Always handle `onResult` being called even when `showOverlays: false`. The `mounted` guard prevents stale setState calls but doesn't stop the callback from firing.

### Pitfall 2: `normalizedBox` on iOS Normalized Against `orig_shape`, Not Screen Size

**What goes wrong:** Dot appears at wrong position on iOS — offset toward the center or a corner.

**Why it happens:** iOS `normalizedBox` is computed as `minX / orig_shape.width` where `orig_shape` is the CoreML model's input dimensions (not the screen dimensions). On Android, the same normalization applies against the image dimensions. If `orig_shape` is not 1:1 with the device's camera feed aspect ratio, the normalized values may not directly correspond to screen-space positions.

**How to avoid:** Start with `normalizedBox.center` and test with a physical ball on both devices. If the dot is consistently offset (e.g., always shifted 20% toward center), the coordinate transform from model space to screen space needs an additional correction step. Document the empirical result — do NOT attempt to fix without observing the behavior on device first.

**Source:** `YOLOView.swift` lines 1692-1698: `normalizedBox` is computed as `box.xywhn.minX/maxX/minY/maxY` — `xywhn` is the normalized bounding box from the CoreML model's native output, which should be 0-1 relative to the input image dimensions. This is the same space that `YOLOView` uses internally for its `YOLOOverlay`, which draws correctly with `boundingBox` (pixel). Whether the custom `CustomPaint` canvas matches this coordinate space needs empirical verification on both platforms.

### Pitfall 3: `ScreenParams.screenPreviewSize` is Zero at Stream Subscription Time (SSD Path)

**What goes wrong:** Division by zero or `Infinity` NaN values in `_debugDotPosition` when the SSD path first starts, because `ScreenParams.screenPreviewSize` is computed from `screenSize` which may be `Size.zero` until `MediaQuery` is available.

**Why it happens:** `ScreenParams.screenSize` is a static field set to `Size.zero` by default. It must be populated from `MediaQuery.of(context).size` before any detection callbacks fire. Looking at the codebase, `screenSize` is set during the widget build — but `_init()` and `resultsStream.listen` run asynchronously. The first detection results may arrive before `ScreenParams.screenSize` is set.

**How to avoid:** In `_pickBestBallSsd`, guard against zero-size before normalizing:
```dart
Offset? _pickBestBallSsd(List<DetectedObjectDm> objects) {
  final previewSize = ScreenParams.screenPreviewSize;
  if (previewSize.width == 0 || previewSize.height == 0) return null; // guard
  // ... rest of logic
}
```

### Pitfall 4: `RepaintBoundary` Placed at Wrong Level

**What goes wrong:** The `RepaintBoundary` does not prevent the camera layer from repainting when `_debugDotPosition` changes, causing visible jank on Galaxy A32.

**Why it happens:** `RepaintBoundary` creates an independent render layer. If the `CustomPaint` is not inside the `RepaintBoundary` (or if the `RepaintBoundary` is placed as a sibling rather than parent), the isolation fails.

**How to avoid:** The structure must be:
```dart
RepaintBoundary(            // <-- outer
  child: CustomPaint(       // <-- inner
    painter: _DebugDotPainter(...),
  ),
)
```
NOT:
```dart
CustomPaint(
  painter: _DebugDotPainter(...),
  child: RepaintBoundary(), // wrong — has no effect on the painter
)
```

### Pitfall 5: `setState` Called After `dispose()` on YOLO Path (OVLY-04)

**What goes wrong:** `setState() called after dispose()` exception when navigating away from the detection screen while a detection result is in-flight.

**Why it happens:** The current `onResult` implementation only calls `log()` — no `setState` — so this crash does not occur yet. Adding `setState(() => _debugDotPosition = ...)` to `onResult` introduces the risk. The YOLO path has no `StreamSubscription` to cancel on dispose; `onResult` is a callback held by the platform channel and may fire during the disposal window.

**How to avoid:** Add `if (!mounted) return;` as the FIRST LINE of the `onResult` callback body, before any state reads or mutations. This is OVLY-04's explicit requirement.

```dart
onResult: (results) {
  if (!mounted) return; // MUST be first — do not move or remove
  // ... rest of callback
},
```

### Pitfall 6: SSD `_appLifecycleListener` Dispose Error in YOLO Mode

**What goes wrong:** The `dispose()` method wraps `_appLifecycleListener.dispose()` in a `try/catch` because `_appLifecycleListener` is `late` and never initialized in YOLO mode. This is existing technical debt. Adding `_debugDotPosition` state does not require touching this — do not attempt to fix it in Phase 6.

**Why it happens:** `_appLifecycleListener` is declared as `late final AppLifecycleListener` but only assigned in the TFLite path's `initState`. This is a known issue documented in `activeContext.md`.

**How to avoid:** Leave the `try/catch` in `dispose()` unchanged. Phase 6 touches only `onResult`, `build()`, and state fields — not `dispose()` beyond adding `_debugDotPosition = null` if desired.

---

## Code Examples

### Extract Center from YOLO Result (Source: pub cache, verified)

```dart
// Source: ultralytics_yolo-0.2.0/lib/models/yolo_result.dart
// normalizedBox: Rect — all values 0.0–1.0 relative to orig_shape
// normalizedBox.center: Offset — standard dart:ui Rect property

final center = result.normalizedBox.center;
// center.dx is in [0.0, 1.0] — left=0.0, right=1.0
// center.dy is in [0.0, 1.0] — top=0.0, bottom=1.0
```

### Extract Center from SSD Result (Source: codebase, verified)

```dart
// Source: lib/models/detected_object/detected_object_dm.dart
// renderLocation: Rect in screen pixels
// ScreenParams.screenPreviewSize: Size in screen pixels

Offset? normCenter;
final previewSize = ScreenParams.screenPreviewSize;
if (previewSize.width > 0 && previewSize.height > 0) {
  normCenter = Offset(
    result.renderLocation.center.dx / previewSize.width,
    result.renderLocation.center.dy / previewSize.height,
  );
}
```

### Disable YOLOView Native Overlays (Source: pub cache, verified)

```dart
// Source: ultralytics_yolo-0.2.0/lib/yolo_view.dart line 35, 54
// showOverlays: bool — default true
// false → disables native Android OverlayView draws and iOS boundingBoxViews.show()
// false → also prevents internal Flutter YOLOOverlay from rendering
// onResult still fires regardless of showOverlays value

YOLOView(
  modelPath: Platform.isIOS ? 'yolo11n' : 'yolo11n.tflite',
  task: YOLOTask.detect,
  showOverlays: false, // OVLY-03: disables all box rendering from YOLOView
  onResult: (results) {
    if (!mounted) return; // OVLY-04: mounted guard
    // ... extract debug dot position
  },
),
```

### Minimal Debug Dot Painter

```dart
class _DebugDotPainter extends CustomPainter {
  final Offset? dotPosition; // normalized 0.0–1.0, null if no detection

  const _DebugDotPainter({required this.dotPosition});

  @override
  void paint(Canvas canvas, Size size) {
    final pos = dotPosition;
    if (pos == null) return;
    final pixel = Offset(pos.dx * size.width, pos.dy * size.height);
    canvas.drawCircle(pixel, 8.0,
        Paint()..color = Colors.red.withValues(alpha: 0.9));
    canvas.drawCircle(pixel, 8.0,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_DebugDotPainter old) =>
      old.dotPosition != dotPosition;
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| `YOLOView` renders native boxes only; no custom Flutter layer | `YOLOView` has `showOverlays: false` + Flutter `CustomPaint` on top | Clean separation: inference native, rendering Flutter |
| `onResult` fires `log()` only | `onResult` fires `setState(() => _debugDotPosition = ...)` with mounted guard | Detection results drive UI state for the first time |
| No coordinate extraction on YOLO path | `normalizedBox.center` used directly | Zero-transform coordinate pipeline from model output to screen |

---

## Open Questions

1. **`normalizedBox` coordinate accuracy on Galaxy A32 (GitHub Issue #105)**
   - What we know: There is a documented offset bug in `yolo-flutter-app` GitHub issue #105 where bounding box coordinates have a platform-specific offset on some Android devices.
   - What's unclear: Whether this affects `normalizedBox` or only `boundingBox`, and whether the Galaxy A32 (SM-A325F, Android 12, API 31) exhibits this offset.
   - Recommendation: Implement the debug dot using `normalizedBox.center` as specified. Test empirically on the Galaxy A32. If the dot is consistently offset relative to the ball's visual position, investigate `normalizedBox` vs `boundingBox` normalization. Document the empirical result as part of Phase 6 success criteria.

2. **SSD path `ScreenParams.screenSize` population timing — RESOLVED**
   - What we know: `ScreenParams.screenSize` is set in `HomeScreen.build()` via `ScreenParams.screenSize = MediaQuery.sizeOf(context)` (`lib/screens/home/home_screen.dart` line 17). Since `HomeScreen` always builds before navigation to `LiveObjectDetectionScreen`, `screenSize` is always populated when the detection screen is reached. Division by zero is not a risk for normal navigation flows.
   - Remaining concern: If `LiveObjectDetectionScreen` is navigated to programmatically before `HomeScreen.build()` runs (e.g., during widget tests), `screenSize` could be `Size.zero`. Add the zero-size guard in `_pickBestBallSsd()` as a defensive measure regardless.
   - Recommendation: Keep the guard `if (previewSize.width == 0 || previewSize.height == 0) return null;` in `_pickBestBallSsd()` as defensive programming. No fix to `ScreenParams` population needed.

3. **`YOLOOverlay` uses `boundingBox` not `normalizedBox` — coordinate space mismatch**
   - What we know: The internal `YOLODetectionPainter` in `yolo_overlay.dart` draws using `detection.boundingBox.left/top/right/bottom` (pixel coordinates). When `showOverlays: false` AND `onResult != null`, the code still populates `_currentDetections` but the `YOLOOverlay` widget is never shown (condition `if (widget.showOverlays && ...)` is false). So this is not a problem for our overlay rendering.
   - What's unclear: Whether the `boundingBox` pixel values are relative to the platform view's rendered dimensions or some other coordinate system. This matters if Phase 7 needs to use `boundingBox` as a fallback.
   - Recommendation: Use `normalizedBox.center` for Phase 6. Defer `boundingBox` investigation to Phase 7 if `normalizedBox` proves inaccurate.

---

## Sources

### Primary (HIGH confidence)

- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/lib/yolo_view.dart` — Direct source read: `showOverlays` parameter (line 35, 54, 273, 322), `onResult` always called (line 151), `_currentDetections` logic (lines 139-148)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/lib/models/yolo_result.dart` — Direct source read: `normalizedBox: Rect` field confirmed (line 56), `boundingBox: Rect` field confirmed (line 49)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/lib/widgets/yolo_overlay.dart` — Direct source read: `YOLODetectionPainter` uses `boundingBox` pixel coords (lines 91-98), NOT `normalizedBox`
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/ios/Classes/YOLOView.swift` — iOS native source: `showOverlays` controls `boundingBoxViews[i].show/hide()` (lines 649, 652, 732, 739), `normalizedBox` computed from `box.xywhn` (lines 1692-1699)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/example/android/ultralytics_yolo_plugin/src/main/kotlin/com/ultralytics/yolo/YOLOView.kt` — Android native: `showOverlays` controls `OverlayView` draws (line 780), `YOLOPlatformView.kt` reads `creationParams["showOverlays"]` (line that calls `yoloView.setShowOverlays(...)`)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/ios/Classes/SwiftYOLOPlatformView.swift` — iOS platform view: `showOverlays` passed from `creationParams` to `yoloView.showOverlays` (lines 82, 93, 112)
- `lib/screens/live_object_detection/live_object_detection_screen.dart` — Current codebase: `onResult` body is `log()` only (line 102), no `mounted` guard on YOLO path
- `lib/models/detected_object/detected_object_dm.dart` — `renderLocation` getter uses `ScreenParams.screenPreviewSize` (lines 30-41)
- `lib/models/screen_params.dart` — `screenPreviewSize` formula: `Size(screenSize.width, screenSize.width * previewRatio)` (line 20)

### Secondary (MEDIUM confidence)

- `.planning/research/PITFALLS.md` — Prior research on coordinate space pitfalls, `mounted` guard requirement, `showOverlays` context
- `.planning/research/ARCHITECTURE.md` — Prior research on `Stack` overlay patterns, `normalizedBox` usage
- `memory-bank/activeContext.md` — Confirmed YOLO path `onResult` currently only logs, SSD path has `mounted` guard

---

## Metadata

**Confidence breakdown:**
- `showOverlays: false` API: HIGH — read directly from pub cache source in 3 files (Dart, Swift, Kotlin)
- `normalizedBox.center` coordinate space: HIGH — confirmed from `yolo_result.dart` and iOS `YOLOView.swift`
- SSD coordinate normalization: HIGH — `renderLocation` and `ScreenParams` read directly from codebase
- `mounted` guard requirement: HIGH — current codebase read, gap on YOLO path confirmed
- Galaxy A32 coordinate accuracy: LOW — empirical device test required; GitHub issue documented but unresolved for this specific device

**Research date:** 2026-02-23
**Valid until:** 2026-03-23 (stable API — 30 day window appropriate for a pinned package version)
