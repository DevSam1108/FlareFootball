# Phase 7: Trail Accumulation and Rendering — Research

**Researched:** 2026-02-23
**Domain:** Flutter CustomPainter trail rendering + bounded position queue + YOLO-only ball tracking
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TRAK-01 | Ball positions stored in a bounded queue (max ~45 entries, ~1.5s at 30fps) that automatically evicts oldest entries | `dart:collection ListQueue` provides O(1) add/remove; time-based pruning more correct than count-based; use `Duration(seconds: 1, milliseconds: 500)` window |
| TRAK-02 | Occlusion handled via null sentinels — trail pauses when ball not detected, resumes with visible gap | `TrackedPosition.isOccluded = true` sentinel; `markOccluded()` adds sentinel only if previous position was not already a sentinel; `TrailOverlay` skips `drawLine` across occluded points |
| TRAK-03 | Class priority filter selects "Soccer ball" over "ball" and rejects "tennis-ball" detections | Replace current `_pickBestBallYolo` which includes tennis-ball; new filter: accept `{'Soccer ball', 'ball'}` only, prefer `Soccer ball` over `ball` by checking class name priority before falling back to confidence |
| TRAK-04 | When multiple valid detections exist in same frame, nearest-to-last-known-position used as tiebreaker | Compute Euclidean distance from `_tracker.lastKnownPosition` to each candidate's `normalizedBox.center`; pick minimum; fall back to highest confidence when no history exists |
| TRAK-05 | Trail auto-clears after 30+ consecutive frames with no ball detected | `BallTracker` maintains `int _consecutiveMissedFrames`; increments on `markOccluded()`, resets on `update()`; calls `reset()` when count exceeds 30 |
| RNDR-01 | Fading dot trail with age-based opacity gradient (recent dots opaque, older dots fade out) | Age computed as `DateTime.now().difference(pos.timestamp).inMilliseconds / windowMs`; opacity = `(1.0 - age).clamp(0.0, 1.0)`; radius also tapers with age: `5.0 * opacity + 2.0` |
| RNDR-02 | Connecting line segments drawn between consecutive trail positions | `canvas.drawLine(prev, curr, linePaint)` in a loop over trail pairs; line opacity matches segment age |
| RNDR-03 | Line segments skip occlusion gaps — no line drawn across null sentinels | `if (prev.isOccluded || curr.isOccluded) continue;` inside the line-drawing loop |
| RNDR-04 | Trail CustomPainter wrapped in RepaintBoundary for rendering isolation | `RepaintBoundary(child: CustomPaint(painter: TrailOverlay(...)))` — same pattern already used for `DebugDotPainter` in this codebase |
| RNDR-05 | Trail overlay renders correctly on YOLO path in landscape orientation | FILL_CENTER crop offset math already solved in `DebugDotPainter`; `TrailOverlay` must apply the same crop correction when mapping `normalizedCenter` to canvas pixels |
</phase_requirements>

---

## Summary

Phase 7 builds on the proven foundation from Phase 6. The coordinate extraction is correct (FILL_CENTER crop offset solved in `DebugDotPainter`), `showOverlays: false` works, and `mounted` guards are in place. Everything needed for this phase — `dart:collection ListQueue`, `CustomPainter`, `RepaintBoundary`, `Canvas.drawCircle`, `Canvas.drawLine` — is already available in the Flutter SDK with no new packages required.

The primary work is three new pure-Dart components wired into the existing screen: a `TrackedPosition` value type, a `BallTracker` service class, and a `TrailOverlay` CustomPainter. The existing `DebugDotPainter` and `_debugDotPosition` field become dead code once the trail is working — they should be removed or replaced by the trail. The existing `_pickBestBallYolo` helper must be upgraded to implement class priority (accept `Soccer ball` and `ball` only; prefer `Soccer ball`; add nearest-neighbor tiebreaker for TRAK-04).

One critical technical detail not previously documented: the `TrailOverlay` painter must apply the same FILL_CENTER crop offset math that `DebugDotPainter` uses, because `normalizedBox` coordinates from YOLO are relative to the full uncropped camera frame. This is confirmed working on iPhone 12 and is the single most important implementation constraint for RNDR-05. The crop math is already in the codebase and must be extracted into a shared utility so both painters use the same formula consistently.

**Primary recommendation:** Build bottom-up — `TrackedPosition` → `BallTracker` → `TrailOverlay` → wire into screen — and replace `DebugDotPainter` with `TrailOverlay` in a single clean changeover rather than running both painters simultaneously.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `dart:collection ListQueue` | SDK built-in | Bounded position history buffer | O(1) amortized `addLast`/`removeFirst`; no allocation overhead; supports capacity hint |
| `CustomPainter` + `CustomPaint` | SDK built-in | Trail rendering on transparent canvas | Zero widget allocation per frame; direct Canvas API access; correct tool for 2D overlay |
| `RepaintBoundary` | SDK built-in | Scope repaints to trail layer only | Camera frame and trail are independent render objects; prevents full-tree repaint on each detection callback |
| `dart:ui Canvas`, `Paint`, `Offset` | SDK built-in | Drawing primitives | `drawCircle`, `drawLine` are the exact APIs needed; no abstraction layer needed |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `IgnorePointer` | SDK built-in | Prevent trail consuming touch events | Wrap `CustomPaint` to pass through taps to underlying camera view |
| `dart:math` | SDK built-in | Euclidean distance for TRAK-04 tiebreaker | `sqrt(dx*dx + dy*dy)` — trivial; no external package needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ListQueue` with time-based pruning | Fixed-count `List` + `removeAt(0)` | Count-based simpler but wrong: frame rate varies (30fps iPhone 12 vs ~15fps A32 varies); time-window gives consistent 1.5s visual regardless of device speed |
| `DateTime.now()` for age calculation in `paint()` | `AnimationController` tick counter | Ticker adds a vsync dependency and a separate `TickerProviderStateMixin`; timestamp arithmetic in `paint()` is simpler and already works — `paint()` is called per-setState, which is per-detection-frame |
| Normalized coords in `TrackedPosition` | Screen-pixel coords | Normalized coords are stable across orientation changes and device sizes; pixel coords would be wrong if canvas size changes between frames |

**Installation:** No new packages. All technologies are Flutter SDK built-ins.

---

## Architecture Patterns

### Recommended Project Structure

```
lib/
├── models/
│   └── tracked_position.dart          # NEW: TrackedPosition value type
│
├── services/
│   └── ball_tracker.dart              # NEW: BallTracker tracking state machine
│
└── screens/
    └── live_object_detection/
        ├── live_object_detection_screen.dart   # MODIFIED: wire tracker + overlay
        └── widgets/
            ├── debug_dot_overlay.dart           # REPLACED by trail_overlay.dart
            ├── rounded_button.dart              # Existing — unchanged
            └── trail_overlay.dart              # NEW: TrailOverlay CustomPainter
```

### Pattern 1: TrackedPosition Value Type

**What:** A plain Dart class (no Flutter dependencies) with three fields: `normalizedCenter: Offset`, `timestamp: DateTime`, `isOccluded: bool`. Immutable. Used by both `BallTracker` and `TrailOverlay`.

**Why separate:** No Flutter imports means it can be unit-tested without a test harness. All trail logic (`BallTracker`) and all rendering logic (`TrailOverlay`) depend on this type, not on each other.

```dart
// lib/models/tracked_position.dart
// Source: architecture pattern from .planning/research/ARCHITECTURE.md
class TrackedPosition {
  final Offset normalizedCenter; // 0.0–1.0 on both axes
  final DateTime timestamp;
  final bool isOccluded; // true = break the trail line here (gap sentinel)

  const TrackedPosition({
    required this.normalizedCenter,
    required this.timestamp,
    this.isOccluded = false,
  });
}
```

### Pattern 2: BallTracker Service with Bounded ListQueue

**What:** A plain Dart service class (no Flutter dependencies) that accepts a normalized `Offset?` per frame, maintains a time-windowed position history, handles occlusion via gap sentinels, counts consecutive missed frames for auto-clear, and exposes an unmodifiable `trail` list.

**Critical details:**
- `ListQueue` not `List` — `removeFirst()` is O(1); `List.removeAt(0)` is O(n)
- Time-based window (1.5s), not count-based — frame rate varies between devices
- `markOccluded()` inserts a sentinel only if the last entry was not already a sentinel — prevents sentinel stacking during long occlusions
- `_consecutiveMissedFrames` counter resets on every `update()` and triggers `reset()` at 30 — this implements TRAK-05
- `lastKnownPosition` getter exposes the last non-occluded position for the TRAK-04 nearest-neighbor tiebreaker

```dart
// lib/services/ball_tracker.dart
import 'dart:collection';
import 'package:flutter/painting.dart';
import 'package:tensorflow_demo/models/tracked_position.dart';

class BallTracker {
  final Duration trailWindow;
  static const int autoResetThreshold = 30;

  final _history = ListQueue<TrackedPosition>();
  int _consecutiveMissedFrames = 0;

  BallTracker({this.trailWindow = const Duration(seconds: 1, milliseconds: 500)});

  List<TrackedPosition> get trail => List.unmodifiable(_history);

  Offset? get lastKnownPosition {
    for (final pos in _history.toList().reversed) {
      if (!pos.isOccluded) return pos.normalizedCenter;
    }
    return null;
  }

  void update(Offset normalizedCenter) {
    _consecutiveMissedFrames = 0;
    _history.addLast(TrackedPosition(
      normalizedCenter: normalizedCenter,
      timestamp: DateTime.now(),
    ));
    _prune();
  }

  void markOccluded() {
    _consecutiveMissedFrames++;
    if (_consecutiveMissedFrames >= autoResetThreshold) {
      reset();
      return;
    }
    // Only insert sentinel if previous entry was not already a sentinel.
    if (_history.isNotEmpty && !_history.last.isOccluded) {
      _history.addLast(TrackedPosition(
        normalizedCenter: _history.last.normalizedCenter,
        timestamp: DateTime.now(),
        isOccluded: true,
      ));
    }
    _prune();
  }

  void reset() {
    _history.clear();
    _consecutiveMissedFrames = 0;
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(trailWindow);
    while (_history.isNotEmpty && _history.first.timestamp.isBefore(cutoff)) {
      _history.removeFirst();
    }
  }
}
```

### Pattern 3: TrailOverlay CustomPainter with FILL_CENTER Crop Correction

**What:** A `CustomPainter` that renders the fading dot trail. Takes `trail: List<TrackedPosition>` and `cameraAspectRatio: double`. Maps normalized coordinates to canvas pixels using the same FILL_CENTER crop correction math already proven in `DebugDotPainter`.

**Critical detail — RNDR-05:** The FILL_CENTER crop math must be applied here, not just in `DebugDotPainter`. The `_toPixel()` method must mirror `DebugDotPainter.paint()` exactly. Recommend extracting this math into a shared utility method (see "Don't Hand-Roll" section).

```dart
// lib/screens/live_object_detection/widgets/trail_overlay.dart
// Source: architecture pattern from .planning/research/ARCHITECTURE.md
// + FILL_CENTER crop offset from DebugDotPainter (Phase 6)
class TrailOverlay extends CustomPainter {
  final List<TrackedPosition> trail;
  final Duration trailWindow;
  final double cameraAspectRatio;

  TrailOverlay({
    required this.trail,
    required this.trailWindow,
    this.cameraAspectRatio = 16.0 / 9.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty) return;

    final now = DateTime.now();
    final windowMs = trailWindow.inMilliseconds.toDouble();

    // Draw connecting line segments (skip across occluded sentinels).
    final linePaint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 1; i < trail.length; i++) {
      final prev = trail[i - 1];
      final curr = trail[i];
      if (prev.isOccluded || curr.isOccluded) continue; // RNDR-03: gap

      final age = now.difference(curr.timestamp).inMilliseconds / windowMs;
      final opacity = (1.0 - age).clamp(0.0, 1.0);
      linePaint.color = Colors.orange.withValues(alpha: opacity * 0.7);
      canvas.drawLine(
        _toPixel(prev.normalizedCenter, size),
        _toPixel(curr.normalizedCenter, size),
        linePaint,
      );
    }

    // Draw dot at each non-occluded position (RNDR-01).
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final pos in trail) {
      if (pos.isOccluded) continue;
      final age = now.difference(pos.timestamp).inMilliseconds / windowMs;
      final opacity = (1.0 - age).clamp(0.0, 1.0);
      final radius = 5.0 * opacity + 2.0; // taper radius with age
      dotPaint.color = Colors.orange.withValues(alpha: opacity);
      canvas.drawCircle(_toPixel(pos.normalizedCenter, size), radius, dotPaint);
    }
  }

  /// Maps a normalized [0.0–1.0] offset to canvas pixel coordinates,
  /// accounting for FILL_CENTER (BoxFit.cover) crop offset.
  /// Must match the crop math in DebugDotPainter exactly.
  Offset _toPixel(Offset normalized, Size size) {
    final widgetAR = size.width / size.height;
    double pixelX, pixelY;

    if (widgetAR > cameraAspectRatio) {
      // Widget wider than camera → scaled by width, height cropped.
      final scaledHeight = size.width / cameraAspectRatio;
      final cropY = (scaledHeight - size.height) / 2.0;
      pixelX = normalized.dx * size.width;
      pixelY = normalized.dy * scaledHeight - cropY;
    } else {
      // Widget taller than camera → scaled by height, width cropped.
      final scaledWidth = size.height * cameraAspectRatio;
      final cropX = (scaledWidth - size.width) / 2.0;
      pixelX = normalized.dx * scaledWidth - cropX;
      pixelY = normalized.dy * size.height;
    }
    return Offset(pixelX, pixelY);
  }

  @override
  bool shouldRepaint(TrailOverlay old) =>
      trail != old.trail ||
      trailWindow != old.trailWindow ||
      cameraAspectRatio != old.cameraAspectRatio;
}
```

### Pattern 4: Upgraded _pickBestBallYolo with Class Priority + Nearest-Neighbor Tiebreaker

**What:** Replaces the existing `_pickBestBallYolo` in the screen. Current implementation includes `tennis-ball` and uses only confidence to pick the best ball — violates TRAK-03 and TRAK-04.

**Changes needed:**
1. Reject `tennis-ball` (TRAK-03)
2. Prefer `Soccer ball` over `ball` regardless of confidence (TRAK-03)
3. Among equal-priority candidates, pick nearest to last known position (TRAK-04)

```dart
// Replacement for _pickBestBallYolo in live_object_detection_screen.dart
YOLOResult? _pickBestBallYolo(List<YOLOResult> results) {
  // TRAK-03: Reject tennis-ball; accept Soccer ball and ball only.
  const priority = {'Soccer ball': 0, 'ball': 1};
  final candidates = results
      .where((r) => priority.containsKey(r.className))
      .toList();
  if (candidates.isEmpty) return null;

  // Sort by class priority first, then confidence within same class.
  candidates.sort((a, b) {
    final pa = priority[a.className]!;
    final pb = priority[b.className]!;
    if (pa != pb) return pa.compareTo(pb);
    return b.confidence.compareTo(a.confidence);
  });

  // TRAK-04: If there are multiple candidates with the same top priority,
  // use nearest-to-last-known-position as tiebreaker.
  final topPriority = priority[candidates.first.className]!;
  final topCandidates = candidates
      .where((r) => priority[r.className] == topPriority)
      .toList();

  if (topCandidates.length == 1) return topCandidates.first;

  final lastKnown = _tracker.lastKnownPosition;
  if (lastKnown == null) return topCandidates.first; // no history, take first

  // Pick candidate whose normalizedBox center is closest to last known position.
  topCandidates.sort((a, b) {
    final ca = a.normalizedBox.center;
    final cb = b.normalizedBox.center;
    final da = _dist(ca, lastKnown);
    final db = _dist(cb, lastKnown);
    return da.compareTo(db);
  });
  return topCandidates.first;
}

double _dist(Offset a, Offset b) {
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  return dx * dx + dy * dy; // squared distance is fine for comparison
}
```

### Pattern 5: Widget Tree Integration (YOLO Path)

**What:** Replace `DebugDotPainter` with `TrailOverlay` in the YOLO Stack. The `_debugDotPosition` field and diagnostic coordinate text overlay become dead code and should be removed.

```dart
// In live_object_detection_screen.dart — YOLO build() Stack
Stack(
  fit: StackFit.expand,
  children: [
    YOLOView(
      modelPath: Platform.isIOS ? 'yolo11n' : 'yolo11n.tflite',
      task: YOLOTask.detect,
      showOverlays: false,
      onResult: (results) {
        if (!mounted) return;
        final ball = _pickBestBallYolo(results);
        setState(() {
          if (ball != null) {
            _tracker.update(Offset(
              ball.normalizedBox.center.dx,
              ball.normalizedBox.center.dy,
            ));
          } else {
            _tracker.markOccluded();
          }
        });
      },
    ),
    // RNDR-04: RepaintBoundary wraps CustomPaint.
    RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: TrailOverlay(
            trail: _tracker.trail,
            trailWindow: const Duration(seconds: 1, milliseconds: 500),
          ),
        ),
      ),
    ),
    // Backend label badge (existing — unchanged).
    Positioned(top: 12, left: 12, child: ...),
  ],
)
```

### Anti-Patterns to Avoid

- **Storing pixel coordinates in `TrackedPosition`:** If `ScreenParams` or canvas size changes, all stored positions become misaligned. Always store normalized [0.0, 1.0] and denormalize in `paint()`.
- **Running trail pruning in `paint()`:** `paint()` must be side-effect free. All mutation happens in `BallTracker.update()` / `markOccluded()` inside `setState`. Age-based opacity calculation in `paint()` is read-only and acceptable.
- **`List` with `removeAt(0)` instead of `ListQueue.removeFirst()`:** `removeAt(0)` on a `List` is O(n) — grows linearly with trail length. Use `ListQueue` for O(1) operations.
- **Duplicating FILL_CENTER math in TrailOverlay:** Copy-pasting the crop math from `DebugDotPainter` risks drift if one is updated and the other is not. Extract to a shared utility function.
- **Introducing MobX for trail state:** Violates the project rule (MobX only on Home Screen). `setState` in the screen state is sufficient.
- **Sentinel stacking:** Adding multiple consecutive occluded sentinels during a long ball-lost period wastes queue slots and makes line-drawing logic iterate over useless entries. `markOccluded()` must check `_history.last.isOccluded` before inserting.
- **Running both `DebugDotPainter` and `TrailOverlay` simultaneously:** Don't keep `DebugDotPainter` around as a fallback. Replace it cleanly — two painters on top of the same view cause visual confusion and unnecessary repaint overhead.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| FILL_CENTER pixel mapping | New crop-correction formula | Extract `_toPixel()` from `DebugDotPainter` into shared util | Formula already verified on iPhone 12; hand-rolling a new one risks re-introducing the Y-offset bug fixed in Phase 6 |
| Bounded queue with O(1) eviction | `List<TrackedPosition>` with `removeAt(0)` | `dart:collection ListQueue` | `removeAt(0)` on List is O(n); `removeFirst()` on ListQueue is O(1) |
| Age-based opacity | `AnimationController` + `Tween` | `DateTime.now().difference(pos.timestamp)` in `paint()` | Tween requires vsync setup; timestamp arithmetic is simpler, correct, and already available |
| Distance comparison for TRAK-04 | Trigonometric functions | Squared Euclidean distance `dx*dx + dy*dy` | Square root not needed for relative comparison; `dart:math` sqrt is unnecessary overhead |

**Key insight:** All the hard problems in this phase (bounded queues, coordinate math, opacity animation) have one-liner solutions in the Flutter SDK. The value is in wiring them correctly, not in algorithm design.

---

## Common Pitfalls

### Pitfall 1: FILL_CENTER Crop Not Applied in TrailOverlay

**What goes wrong:** Trail dots render above/below the ball position — same Y-axis offset bug as Phase 6 before the fix.
**Why it happens:** Normalizing coordinates via `normalizedCenter.dx * size.width` and `normalizedCenter.dy * size.height` is only correct when the widget aspect ratio exactly matches the camera aspect ratio. In landscape, the widget AR differs from camera AR, so FILL_CENTER crops one dimension.
**How to avoid:** `TrailOverlay._toPixel()` must implement the same FILL_CENTER crop correction as `DebugDotPainter.paint()`. Extract into a shared `YoloCoordUtils.toCanvasPixel(normalized, size, cameraAR)` function so both painters cannot diverge.
**Warning signs:** Trail dots appear shifted from where the ball actually is, especially when holding the device at different landscape angles.

### Pitfall 2: Sentinel Stacking Fills the Queue

**What goes wrong:** During a 1.5-second ball occlusion at 30fps, `markOccluded()` adds 45 sentinel entries, consuming the entire queue capacity with no actual positions.
**Why it happens:** Calling `_history.addLast(sentinel)` unconditionally every frame during occlusion.
**How to avoid:** `markOccluded()` checks `_history.last.isOccluded` before inserting. Only one sentinel is ever present at the end of the queue at a time.
**Warning signs:** Trail appears completely empty even after ball reappears; queue is full of sentinels.

### Pitfall 3: Auto-Reset Never Fires (TRAK-05)

**What goes wrong:** `_consecutiveMissedFrames` never reaches 30 because the counter is reset by `markOccluded()` adding a sentinel and then the sentinel getting pruned in `_prune()`.
**Why it happens:** If `_prune()` removes the sentinel (it becomes older than the trail window), the queue no longer ends with a sentinel, so the next `markOccluded()` adds another one — and the counter keeps incrementing correctly. This is actually fine. The pitfall is if someone resets `_consecutiveMissedFrames` inside `_prune()`.
**How to avoid:** `_consecutiveMissedFrames` is only reset in `update()` (real detection). Never reset it in `_prune()`.
**Warning signs:** Trail ghost persists on screen after moving ball completely out of frame for multiple seconds.

### Pitfall 4: `shouldRepaint` Returns Wrong Value

**What goes wrong:** Either (a) trail never updates visually because `shouldRepaint` always returns `false`, or (b) unnecessary repaints fire because it always returns `true` even when trail hasn't changed.
**Why it happens:** (a) Comparing `List` identity when `_tracker.trail` returns `List.unmodifiable(_history)` — every call creates a new list wrapper, so reference equality fails. (b) Always returning `true` is technically correct but wastes GPU cycles.
**How to avoid:** Compare meaningful properties. The cleanest approach: `trail != old.trail` works if `BallTracker.trail` returns the same unmodifiable view (which `List.unmodifiable` does NOT — it creates a new wrapper each time). Solution: return `true` in `shouldRepaint` always during live detection (this is correct since we only call `setState` when detection data changes, so `build()` + `paint()` only fires when needed). The real performance guard is `RepaintBoundary`, not `shouldRepaint`.
**Warning signs:** Trail freezes on screen (never updates), or frame rate drops noticeably below detection frame rate.

### Pitfall 5: _pickBestBallYolo Returns tennis-ball (TRAK-03 Violation)

**What goes wrong:** A stationary tennis ball in the frame gets tracked instead of the moving soccer ball.
**Why it happens:** Current implementation includes `'tennis-ball'` in `ballClasses` and uses only confidence to sort. If the tennis ball has higher confidence than the soccer ball, it wins.
**How to avoid:** Class priority map `{'Soccer ball': 0, 'ball': 1}` — tennis-ball is simply not in the map and is filtered out by `priority.containsKey(r.className)`.
**Warning signs:** Trail locks onto a stationary object instead of the moving ball; `r.className == 'tennis-ball'` appears in YOLO result logs when trail misbehaves.

---

## Code Examples

### FILL_CENTER Crop Utility (extract from DebugDotPainter)

```dart
// Recommended extraction into:
// lib/utils/yolo_coord_utils.dart
// Source: DebugDotPainter.paint() — Phase 6, verified on iPhone 12
static Offset toCanvasPixel(Offset normalized, Size canvasSize, double cameraAR) {
  final widgetAR = canvasSize.width / canvasSize.height;
  double pixelX, pixelY;

  if (widgetAR > cameraAR) {
    // Widget wider than camera → scaled by width, height cropped.
    final scaledHeight = canvasSize.width / cameraAR;
    final cropY = (scaledHeight - canvasSize.height) / 2.0;
    pixelX = normalized.dx * canvasSize.width;
    pixelY = normalized.dy * scaledHeight - cropY;
  } else {
    // Widget taller than camera → scaled by height, width cropped.
    final scaledWidth = canvasSize.height * cameraAR;
    final cropX = (scaledWidth - canvasSize.width) / 2.0;
    pixelX = normalized.dx * scaledWidth - cropX;
    pixelY = normalized.dy * canvasSize.height;
  }
  return Offset(pixelX, pixelY);
}
```

### BallTracker Field Declaration in Screen State

```dart
// In _LiveObjectDetectionScreenState:
final _tracker = BallTracker(
  trailWindow: const Duration(seconds: 1, milliseconds: 500),
);
```

### onResult Callback — Complete Replacement

```dart
onResult: (results) {
  if (!mounted) return; // OVLY-04: guard setState-after-dispose
  final ball = _pickBestBallYolo(results); // TRAK-03 + TRAK-04
  setState(() {
    if (ball != null) {
      _tracker.update(Offset(
        ball.normalizedBox.center.dx,
        ball.normalizedBox.center.dy,
      ));
    } else {
      _tracker.markOccluded(); // TRAK-02 + TRAK-05
    }
  });
},
```

### dispose() Addition

```dart
@override
void dispose() {
  _tracker.reset(); // clean up trail history
  SystemChrome.setPreferredOrientations([...]); // existing
  // ... existing dispose body ...
  super.dispose();
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `DebugDotPainter` shows single dot | `TrailOverlay` shows full fading trail | Phase 7 | Replaces debug visualization with the actual tracking product |
| `_pickBestBallYolo` includes tennis-ball, confidence-only tiebreaker | Priority map + nearest-neighbor tiebreaker | Phase 7 | Correctly handles TRAK-03, TRAK-04 |
| `_debugDotPosition: Offset?` field | `_tracker: BallTracker` + `_tracker.trail` | Phase 7 | Single position → history queue |

**Removed in Phase 7:**
- `DebugDotPainter` import and usage in YOLO path build
- `_debugDotPosition` state field
- Diagnostic coordinate text overlay (or demote to dev-only build flag)
- `import 'package:tensorflow_demo/screens/live_object_detection/widgets/debug_dot_overlay.dart'` (replaced by trail_overlay)

---

## Open Questions

1. **Should `DebugDotPainter` be deleted or kept?**
   - What we know: Phase 6 purpose (coordinate validation) is complete. `TrailOverlay` subsumes it.
   - What's unclear: Whether there's future value in a quick "show single dot" painter for debugging new coordinate systems (e.g., when Android is tested).
   - Recommendation: Keep the file during Phase 7 but remove all references from the screen. Delete in cleanup before Phase 8. If Galaxy A32 Android testing uncovers coordinate issues, it can be temporarily re-wired.

2. **Should the coordinate text overlay (`dot: (x, y)`) be removed?**
   - What we know: It was for coordinate validation during Phase 6. Trail overlay makes the ball position visually obvious.
   - What's unclear: Whether it's useful for ongoing evaluation recordings.
   - Recommendation: Remove from production build path. If diagnostic overlays are needed in the future, gate behind a `kDebugMode` check.

3. **What happens to the SSD path's `_debugDotPosition` / `_pickBestBallSsd`?**
   - What we know: SSD path is frozen (no new features). The `_debugDotPosition` field is shared between YOLO and SSD builds currently.
   - What's unclear: Whether to add `BallTracker` to the SSD build path or leave the SSD overlay broken.
   - Recommendation: Since SSD is frozen, leave the SSD side of the screen as-is (with the existing `_debugDotPosition` showing the single dot). Phase 7 only wires `BallTracker` + `TrailOverlay` on the YOLO path. `_debugDotPosition` can remain as a field used only by the SSD path's `DebugDotPainter`. This avoids any risk of touching the SSD path.

4. **Trail window: 1.5s (REQUIREMENTS.md) vs 3s (ARCHITECTURE.md examples)?**
   - What we know: TRAK-01 specifies "max ~45 entries, ~1.5s at 30fps". ARCHITECTURE.md code examples used 3 seconds.
   - What's unclear: Which is the right default for evaluation.
   - Recommendation: Use `Duration(seconds: 1, milliseconds: 500)` to match TRAK-01 specification exactly. If the trail looks too short during evaluation, it's trivial to increase the constant.

---

## Sources

### Primary (HIGH confidence)

- Existing codebase — `lib/screens/live_object_detection/live_object_detection_screen.dart` (read directly): current `_pickBestBallYolo`, `_debugDotPosition`, YOLO Stack widget tree
- Existing codebase — `lib/screens/live_object_detection/widgets/debug_dot_overlay.dart` (read directly): FILL_CENTER crop math, `shouldRepaint` pattern, `RepaintBoundary` usage
- `.planning/research/ARCHITECTURE.md` (read directly): complete code stubs for `TrackedPosition`, `BallTracker`, `TrailOverlay`, data flow diagrams, coordinate system table
- `.planning/research/SUMMARY.md` (read directly): standard stack rationale, pitfall catalog, build order
- `.planning/phases/06-overlay-foundation/06-02-SUMMARY.md` (read directly): Phase 6 outcomes — FILL_CENTER fix verified on iPhone 12
- Flutter SDK `dart:collection` ListQueue: O(1) add/remove confirmed by SDK documentation

### Secondary (MEDIUM confidence)

- [Flutter CustomPainter API](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html) — `paint()`, `shouldRepaint()`, lifecycle
- [Flutter RepaintBoundary API](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html) — repaint isolation semantics
- [dart:collection ListQueue](https://api.flutter.dev/flutter/dart-collection/ListQueue-class.html) — O(1) addLast/removeFirst
- [PyImageSearch OpenCV Object Tracking](https://pyimagesearch.com/2015/09/21/opencv-track-object-movement/) — canonical deque + null-sentinel pattern this architecture is modeled after

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all Flutter SDK built-ins; versions not a concern; no new packages
- Architecture: HIGH — codebase read directly; patterns confirmed from working Phase 6 code; complete stubs available from prior research
- Pitfalls: HIGH — FILL_CENTER pitfall verified empirically on iPhone 12 in Phase 6; sentinel stacking and shouldRepaint patterns sourced from official Flutter docs + prior architecture research

**Research date:** 2026-02-23
**Valid until:** 2026-03-30 (stable Flutter SDK patterns; no fast-moving dependencies)
