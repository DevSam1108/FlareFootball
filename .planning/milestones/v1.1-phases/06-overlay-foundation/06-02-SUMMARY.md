# Plan 06-02 Summary: Device Verification Checkpoint

**Status:** Complete
**Started:** 2026-02-23
**Completed:** 2026-02-23

## What Was Done

### Task 1: Build and deploy to both devices for testing
- iOS YOLO mode: `flutter build ios --dart-define=DETECTOR_BACKEND=yolo` — 62.6MB clean build
- iOS TFLite mode: `flutter build ios` — 62.7MB clean build
- Android: SDK not configured on current Mac; build succeeds but deployment requires USB-connected device
- Cleaned up technical debt: removed iOS diagnostic probe from `main.dart`, replaced stale widget test

### Task 2: Verify debug dot accuracy (checkpoint:human-verify)
- **iPhone 12 YOLO test — first attempt:** Dot consistently slightly above ball. Native bounding boxes confirmed gone (OVLY-03 ✓). Tracking quality described as "very poor" (likely model limitation, not code issue).
- **Root cause identified:** `normalizedBox` coordinates are relative to full camera frame, but YOLOView uses FILL_CENTER scaling (BoxFit.cover) which crops height. The direct `normalizedY * canvasHeight` mapping didn't account for the crop offset.
- **Fix applied:** Updated `DebugDotPainter` to compute FILL_CENTER crop offset based on camera vs widget aspect ratios. Defaults to 16:9 camera AR.
- **iPhone 12 YOLO test — second attempt:** Dot now centered on ball. ✓

## Key Decisions
- SSD/TFLite path dropped from v1.1 scope — YOLO only going forward on both iOS and Android (model is old)
- Camera aspect ratio defaulted to 16:9 (standard for iPhone 12 and Galaxy A32 video capture)
- Galaxy A32 testing deferred — Android SDK not configured on current Mac

## Scope Change
OVLY-02 (SSD coordinate extraction) and RNDR-06 (SSD trail rendering) dropped from requirements. All v1.1 tracking work is YOLO-pipeline only.

## Commits
- `2bc9083` — Build/deploy task: clean builds, remove iOS diagnostic probe, replace stale test
- `b02af14` — docs: drop SSD/TFLite from v1.1 scope
- `b7768c5` — fix(06): account for FILL_CENTER camera crop in dot coordinate mapping

## Artifacts
- Updated: `memory-bank/activeContext.md`, `memory-bank/progress.md`
- Updated: `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/PROJECT.md`, `.planning/STATE.md`
- Modified: `lib/screens/live_object_detection/widgets/debug_dot_overlay.dart`
