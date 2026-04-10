# Roadmap: Flare Football Object Detection POC

## Milestones

- ✅ **v1.0 Detection Feasibility** - Phases 1-5 (shipped 2026-02-23)
- 🚧 **v1.1 Ball Tracking** - Phases 6-8 (in progress)

## Phases

<details>
<summary>✅ v1.0 Detection Feasibility (Phases 1-5) - SHIPPED 2026-02-23</summary>

Phases 1–5 predate the GSD workflow and are archived here for continuity.
Delivered: YOLO11n real-time detection on Android and iOS, SSD MobileNet fallback,
build-time backend switching, landscape orientation lock, bounding box rendering,
three-screen navigation, and evaluation evidence capture.

</details>

---

### 🚧 v1.1 Ball Tracking (In Progress)

**Milestone Goal:** Prove that frame-to-frame ball tracking with a fading visual trail is technically
feasible on-device at acceptable performance on the YOLO pipeline (iOS and Android).

**Scope change:** SSD/TFLite path dropped from v1.1 — YOLO only on both platforms.

---

- [x] **Phase 6: Overlay Foundation** - Validate that a Flutter overlay renders correctly above YOLOView on both platforms and that ball center-point coordinates are accurate
- [x] **Phase 7: Trail Accumulation and Rendering** - Build BallTracker and TrailOverlay — bounded position queue, occlusion handling, fading dot trail on YOLO path
- [x] **Phase 8: Polish** - Add evaluator-facing status overlays that communicate tracking state (completed 2026-02-24)

## Phase Details

### Phase 6: Overlay Foundation
**Goal**: A custom Flutter overlay renders visibly and correctly above the camera view on both platforms, and a single debug dot reliably centers on the detected ball in real-time — proving coordinates are correct before any trail state is accumulated
**Depends on**: Phase 5 (v1.0 — detection pipelines working on both platforms)
**Requirements**: OVLY-01, OVLY-03, OVLY-04
**Success Criteria** (what must be TRUE):
  1. A dot appears centered on the ball in the live camera view on both iPhone 12 and Galaxy A32 — not offset, not in a corner
  2. The dot updates position every frame without lag on the YOLO path
  3. Native YOLO bounding boxes are no longer visible — the custom overlay is the only rendering layer
  4. Navigating away from the detection screen and back does not crash, freeze, or produce setState-after-dispose errors
**Plans:** 2 plans
Plans:
- [x] 06-01-PLAN.md — Implement debug dot overlay on YOLO path (coordinate extraction, native overlay suppression, mounted guards)
- [x] 06-02-PLAN.md — Device verification checkpoint (confirm dot accuracy on iPhone 12 and Galaxy A32)

### Phase 7: Trail Accumulation and Rendering
**Goal**: The ball leaves a fading dot-and-line trail as it moves across the screen — the trail pauses when the ball is lost and resumes with a visible gap on re-detection — on the YOLO path in landscape orientation
**Depends on**: Phase 6
**Requirements**: TRAK-01, TRAK-02, TRAK-03, TRAK-04, TRAK-05, RNDR-01, RNDR-02, RNDR-03, RNDR-04, RNDR-05
**Success Criteria** (what must be TRUE):
  1. Moving the ball across the camera produces a visible dot trail — recent dots are bright, older dots are faded
  2. Connecting lines are drawn between trail positions and skip the gap wherever the ball was lost
  3. When a tennis ball and a soccer ball are both visible, the trail follows the soccer ball
  4. After 30+ consecutive frames with no detection, the trail clears automatically
  5. Trail renders correctly in landscape on the YOLO path without visual artifacts
**Plans:** 3/3 complete
Plans:
- [x] 07-01-PLAN.md — Foundation: TrackedPosition value type, YoloCoordUtils shared utility, BallTracker service
- [x] 07-02-PLAN.md — TrailOverlay CustomPainter and YOLO screen integration (replace DebugDotPainter, upgrade ball selection)
- [x] 07-03-PLAN.md — Device verification checkpoint (confirm trail on iPhone 12) — 2 test rounds, AR fix (4:3), dedup fix

### Phase 8: Polish
**Goal**: The detection screen communicates tracking state to the evaluator with a visible badge when the ball is lost
**Depends on**: Phase 7
**Requirements**: PLSH-01
**Success Criteria** (what must be TRUE):
  1. A "Ball lost" badge appears on screen within a few frames after the ball leaves view or becomes occluded
  2. The badge disappears when the ball is re-detected and tracking resumes
**Plans:** 1/1 plans complete
Plans:
- [ ] 08-01-PLAN.md — Add "Ball lost" badge (BallTracker getter + YOLO Stack badge widget + device verification)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 6. Overlay Foundation | v1.1 | 2/2 | Complete | 2026-02-23 |
| 7. Trail Accumulation and Rendering | v1.1 | 3/3 | Complete | 2026-02-23 |
| 8. Polish | 1/1 | Complete   | 2026-02-24 | - |
