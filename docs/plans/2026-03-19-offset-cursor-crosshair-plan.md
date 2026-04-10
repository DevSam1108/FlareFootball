# Offset Cursor + Crosshair Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate finger occlusion during calibration corner dragging by rendering the corner marker 60px above the finger with full-width crosshair alignment lines.

**Architecture:** Modify the existing `onPanUpdate` in `live_object_detection_screen.dart` to apply a vertical offset before storing the corner position. Add crosshair line rendering to `CalibrationOverlay` painter, gated by a new `activeCornerIndex` parameter. Zero new files, zero new dependencies.

**Tech Stack:** Flutter/Dart, existing `CalibrationOverlay` CustomPainter, existing `YoloCoordUtils`

**Design doc:** `docs/plans/2026-03-19-offset-cursor-crosshair-design.md`

---

### Task 1: Add `activeCornerIndex` parameter to CalibrationOverlay

**Files:**
- Modify: `lib/screens/live_object_detection/widgets/calibration_overlay.dart`

**Step 1: Add the new parameter to CalibrationOverlay**

In `calibration_overlay.dart`, add a new field to the class and constructor. This tells the painter which corner (if any) is currently being dragged, so it can draw crosshairs for that corner.

Add after line 29 (`final int? highlightZone;`):

```dart
/// Index of the corner currently being dragged. Null = no drag active.
/// When non-null, crosshair lines are drawn through this corner.
final int? activeCornerIndex;
```

Update the constructor (line 31-36) to include the new parameter:

```dart
const CalibrationOverlay({
  required this.cornerPoints,
  this.zoneMapper,
  this.cameraAspectRatio = 4.0 / 3.0,
  this.highlightZone,
  this.activeCornerIndex,
});
```

**Step 2: Run `flutter analyze` to confirm no errors**

Run: `flutter analyze`
Expected: Clean (the new parameter is optional/nullable, so existing call sites still compile)

---

### Task 2: Add crosshair painting to CalibrationOverlay

**Files:**
- Modify: `lib/screens/live_object_detection/widgets/calibration_overlay.dart`

**Step 1: Add the crosshair painting method**

Add this new method after `_paintZoneNumbers` (after line 181):

```dart
/// Draws full-width horizontal and full-height vertical crosshair lines
/// through the actively-dragged corner. Only called when a corner is
/// being dragged (activeCornerIndex != null).
void _paintCrosshair(Canvas canvas, Size size) {
  if (activeCornerIndex == null ||
      activeCornerIndex! < 0 ||
      activeCornerIndex! >= cornerPoints.length) {
    return;
  }

  final corner = cornerPoints[activeCornerIndex!];
  final pixel = YoloCoordUtils.toCanvasPixel(
    corner,
    size,
    cameraAspectRatio,
  );

  final crosshairPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.7)
    ..strokeWidth = 0.5;

  // Horizontal line (full canvas width).
  canvas.drawLine(
    Offset(0, pixel.dy),
    Offset(size.width, pixel.dy),
    crosshairPaint,
  );
  // Vertical line (full canvas height).
  canvas.drawLine(
    Offset(pixel.dx, 0),
    Offset(pixel.dx, size.height),
    crosshairPaint,
  );
}
```

**Step 2: Call `_paintCrosshair` from the `paint` method**

In the `paint` method (line 39-51), add the crosshair call at the end, after all other painting. This ensures crosshairs render on top of everything:

Replace the entire `paint` method:

```dart
@override
void paint(Canvas canvas, Size size) {
  if (size.isEmpty) return;

  _paintCornerMarkers(canvas, size);

  if (zoneMapper != null) {
    if (highlightZone != null) {
      _paintZoneHighlight(canvas, size);
    }
    _paintGrid(canvas, size);
    _paintZoneNumbers(canvas, size);
  }

  // Crosshair lines through the actively-dragged corner (topmost layer).
  _paintCrosshair(canvas, size);
}
```

**Step 3: Run `flutter analyze`**

Run: `flutter analyze`
Expected: Clean

---

### Task 3: Apply vertical offset in the screen's drag handler

**Files:**
- Modify: `lib/screens/live_object_detection/live_object_detection_screen.dart`

**Step 1: Add the offset constant**

Add after line 90 (`static const _dragHitRadius = 0.09;`):

```dart
/// Vertical offset in logical pixels for the "offset cursor" pattern.
/// During drag, the corner marker renders this many pixels ABOVE the
/// finger, solving finger occlusion. 60px is the standard iOS loupe offset.
static const _dragVerticalOffsetPx = 60.0;
```

**Step 2: Modify `onPanUpdate` to apply the offset**

Replace the current `onPanUpdate` handler (lines 653-662):

Current code:
```dart
onPanUpdate: (details) {
  if (_draggingCornerIndex == null) return;
  final normalized = YoloCoordUtils.fromCanvasPixel(
    details.localPosition,
    canvasSize,
    4.0 / 3.0,
  );
  setState(() {
    _cornerPoints[_draggingCornerIndex!] = normalized;
    _recomputeHomography();
  });
},
```

New code:
```dart
onPanUpdate: (details) {
  if (_draggingCornerIndex == null) return;
  final normalized = YoloCoordUtils.fromCanvasPixel(
    details.localPosition,
    canvasSize,
    4.0 / 3.0,
  );
  // Offset cursor: render corner 60px above finger to avoid
  // finger occlusion. Convert pixel offset to normalized space.
  final offsetNorm =
      _dragVerticalOffsetPx / canvasSize.height;
  final offsetPosition = Offset(
    normalized.dx,
    (normalized.dy - offsetNorm).clamp(0.0, 1.0),
  );
  setState(() {
    _cornerPoints[_draggingCornerIndex!] = offsetPosition;
    _recomputeHomography();
  });
},
```

**Step 3: Run `flutter analyze`**

Run: `flutter analyze`
Expected: Clean

---

### Task 4: Pass `activeCornerIndex` to CalibrationOverlay widget

**Files:**
- Modify: `lib/screens/live_object_detection/live_object_detection_screen.dart`

**Step 1: Add `activeCornerIndex` to the CalibrationOverlay constructor call**

Find the CalibrationOverlay instantiation (lines 435-443):

Current code:
```dart
painter: CalibrationOverlay(
  cornerPoints: _cornerPoints,
  zoneMapper: _zoneMapper,
  highlightZone:
      _impactDetector.phase == DetectionPhase.result &&
              _impactDetector.currentResult?.result ==
                  ImpactResult.hit
          ? _impactDetector.currentResult!.zone
          : null,
),
```

New code (add `activeCornerIndex` parameter):
```dart
painter: CalibrationOverlay(
  cornerPoints: _cornerPoints,
  zoneMapper: _zoneMapper,
  highlightZone:
      _impactDetector.phase == DetectionPhase.result &&
              _impactDetector.currentResult?.result ==
                  ImpactResult.hit
          ? _impactDetector.currentResult!.zone
          : null,
  activeCornerIndex: _draggingCornerIndex,
),
```

**Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: Clean

---

### Task 5: Run full test suite

**Files:** None (verification only)

**Step 1: Run all tests**

Run: `flutter test`
Expected: 81/81 passing. No test touches the drag offset or CalibrationOverlay painter directly, so all tests should pass unchanged.

**Step 2: Run analyzer**

Run: `flutter analyze`
Expected: 0 errors, 0 warnings

---

### Task 6: Device verification checklist

**Files:** None (manual testing)

This is manual testing on a physical device (iPhone 12 or Realme 9 Pro+).

**Step 1: Launch the app**

Run: `flutter run`

**Step 2: Navigate to Live Camera > Calibrate > Tap 4 corners**

Verify: Corner dots appear at tapped positions. Tap flow is unchanged.

**Step 3: Enter reference capture phase, drag a corner**

Verify:
- [ ] Corner marker jumps ~60px above the finger on first drag
- [ ] Thin white crosshair lines (horizontal + vertical) appear through the corner
- [ ] Crosshair lines extend full width and full height of screen
- [ ] You can see the goalpost corner/edge through the crosshair alignment
- [ ] Your finger does NOT cover the corner marker

**Step 4: Release the finger**

Verify:
- [ ] Crosshair lines disappear immediately
- [ ] Corner stays at its offset position
- [ ] Grid recomputes correctly from new corner positions

**Step 5: Drag a corner near the top edge of screen**

Verify:
- [ ] Corner marker does NOT go above the top of the screen (clamped to 0.0)

**Step 6: Tap Confirm button**

Verify:
- [ ] Confirm button still works (not blocked by GestureDetector)
- [ ] Reference capture completes normally

**Step 7: Tap Back button**

Verify:
- [ ] Back button still works during reference capture phase
