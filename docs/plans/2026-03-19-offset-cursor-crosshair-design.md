# Design: Offset Cursor + Crosshair for Calibration Corner Dragging

**Date:** 2026-03-19
**Status:** Approved
**Problem:** Finger occlusion makes precise corner placement impossible during calibration drag

## Problem Statement

When dragging calibration corners on the live camera view to align with goalpost corners, the user's fingertip physically covers the exact spot they're trying to place the corner on, making precise alignment impossible.

## Research Summary

Exhaustive research conducted:
- 8 research agents investigated Flutter built-in widgets, native iOS/Android patterns, and document scanner UX
- 22 pub.dev keyword searches covering every possible angle
- 4 magnifier packages source-code inspected (`flutter_quad_annotator`, `flutter_magnifier_lens`, `flutter_magnifier`, `flutter_image_perspective_crop`)
- Flutter's built-in `RawMagnifier` / `CupertinoMagnifier` evaluated

**Key finding:** ALL magnifier-based solutions fail because they use `BackdropFilter` or `canvas.drawImageRect(ui.Image)`, which cannot access platform view content (the `YOLOView` camera feed renders outside Flutter's compositing layer). This is a fundamental architectural limitation of Flutter's platform view system.

## Chosen Solution: Offset Cursor + Crosshair

Industry-standard pattern used by Adobe Scan, CamScanner, and iOS text cursor placement.

### User Experience

1. During drag, corner marker renders **60px above** the finger touch point
2. Two thin **crosshair lines** (horizontal + vertical) extend from the marker across the entire screen
3. Crosshairs provide alignment cues against goalpost edges
4. Lines disappear when finger lifts

### Code Changes

**Files changed:** 2
- `lib/screens/live_object_detection/live_object_detection_screen.dart` (~15 lines)
- `lib/screens/live_object_detection/widgets/calibration_overlay.dart` (~15 lines)

**New dependencies:** 0
**New files:** 0

### Implementation Details

**Screen file:** Apply vertical offset in `onPanUpdate`:
- Convert 60px to normalized space: `offsetNorm = 60.0 / canvasSize.height`
- Offset position: `Offset(normalized.dx, normalized.dy - offsetNorm)`
- Clamp to prevent going above screen: `max(0.0, ...)`
- Pass `activeCornerIndex` to CalibrationOverlay

**Overlay painter:** Draw crosshair when corner is being dragged:
- Horizontal line (full width) through corner Y position
- Vertical line (full height) through corner X position
- White, 70% opacity, 0.5px stroke width
- Only drawn when `activeCornerIndex != null`

### Edge Cases

| Case | Handling |
|------|----------|
| Corner near top of screen | Clamp offset to prevent marker going off-screen |
| Initial touch "jump" | Intentional -- small adjustments mean small jump |
| Visual clutter | Lines are thin, semi-transparent, only during drag |
| Existing tap flow | Unaffected -- offset only in drag phase |
| Back/Confirm buttons | Still tappable -- HitTestBehavior.translucent preserved |

### What We Deliberately Excluded (YAGNI)

- No magnifier (can't work over platform view)
- No fine-adjustment sensitivity mode
- No virtual D-pad
- No animated offset transition
- No new dependencies or files

## Alternatives Evaluated and Rejected

| Alternative | Reason Rejected |
|-------------|-----------------|
| Flutter `RawMagnifier` | BackdropFilter can't see platform view camera content |
| `flutter_quad_annotator` | Self-contained widget requiring static `ui.Image`, not a camera overlay |
| `flutter_magnifier_lens` | Requires Flutter 3.41+ (incompatible); Fragment Shader approach |
| `flutter_magnifier` | BackdropFilter-based; v0.0.2, 62 downloads |
| `flutter_image_perspective_crop` | Static `Uint8List` images only |
| `LongPressDraggable` | Drag-and-drop paradigm, not point repositioning |
| `InteractiveViewer` | Conflicts with platform view; two-step zoom-then-drag UX |
| Custom screenshot magnifier | `toImage()` can't capture platform views; 30fps screenshot capture would cause jank |
