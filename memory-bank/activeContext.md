# Active Context

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Current Focus
**Pre-ByteTrack AR filter implemented and device-tested (2026-04-13).** A simple upper-bound aspect ratio filter (`ar > 1.8`) rejects elongated YOLO false positives (torso/limb bboxes, AR 2.4-3.6) before they enter ByteTrack. Device-tested on monitor — reduced false positive trail dots on player body. Clean visual output with debug overlay disabled. 176/176 tests passing.

### What Was Done This Session (2026-04-13)
1. **Attempted Mahalanobis rescue validation** — size ratio + velocity direction checks inside `_greedyMatch()` in `bytetrack_tracker.dart`. Reverted at developer request to maintain one-change-at-a-time discipline. The Mahalanobis rescue remains unguarded (ISSUE-026 still open).
2. **Added pre-ByteTrack AR filter** — 2 lines in `_toDetections()` in `live_object_detection_screen.dart`. Initially had both upper (>1.8) and lower (<0.55) bounds; lower bound removed after discussion since no false positives have tall-narrow bboxes and the lower bound may have been intermittently rejecting real ball detections.
3. **Debug bbox overlay disabled** — `_debugBboxOverlay = false` (set manually by developer). Overlay revealed that track ID churn and dual detections on same ball were always happening but don't affect functional behavior — BallIdentifier only follows the locked (green) track.

### Failed Approach (2026-04-13, earlier session) — DO NOT REPEAT
Implemented a 2-layer filter: (1) DetectionFilter pre-ByteTrack (AR + size hard reject), (2) TrackQualityGate post-ByteTrack (init delay + rolling median), (3) Mahalanobis rescue validation (size ratio + velocity direction). Device testing showed:
- **Init delay (4 frames) blocked BallIdentifier re-acquisition** — real ball stuck at [INIT] while BallIdentifier locked onto poster/head
- **Track ID churn** (id:1 → id:15 in one session) — filters intermittently rejected real ball, destabilizing ByteTrack
- **Player head (ar:0.9, c:0.98) passes ALL geometric filters** — fundamentally unfilterable with AR + size
- **Poster locked as ball** (ar:0.8, c:0.99) — passed all filters, static flag hadn't triggered yet (needs 30 frames)

**Key lesson:** Any filter between ByteTrack and BallIdentifier that delays or blocks tracks risks breaking re-acquisition. The re-acquisition path is the most fragile part of the pipeline. Filters must NOT starve BallIdentifier of candidates.

### What Remains
1. **Mahalanobis rescue hijacks ball identity (ISSUE-026)** — locked track jumps from real ball to false positives via Mahalanobis matching. Causes total tracking loss. Mahalanobis rescue validation (size ratio + velocity direction) was implemented and reverted this session — can be re-applied after AR filter is field-tested.
2. **Player head false positives (ar:0.9, c:0.98)** — passes AR filter (within ball range). Unfilterable with geometry alone. Needs second-stage classifier or motion channel.
3. **Track ID churn** — YOLO dual-class detections on same ball (Soccer ball + ball) create duplicate tracks. Cosmetic — doesn't affect BallIdentifier which follows locked track only. NMS dedup in `_toDetections()` would fix but is not a priority.

### Monitor Test Results — Session 2 (2026-04-09, with calibration diagnostics + debug overlay)

**Test 1 (tilt=green, aspectRatio=1.87, coverage=8.18%):**
| Kick | Actual | directZone | WallPredictor | Correct? | Announced? |
|------|--------|------------|---------------|----------|------------|
| 1 | Zone 1 | Zone 1 | Zone 1 | ✅ | ❌ (kickState=idle, isStatic bug) |
| 2 | Zone 1 | Zone 1 | Zone 1 | ✅ | ✅ |
| 3 | Zone 7 | Zone 6 | Zone 7 | ❌ (off by 1) | ✅ |
| 4 | Zone 6 | Zone 6 | Zone 6 | ✅ | ✅ |

**Test 2 (tilt=yellow, aspectRatio=2.08, coverage=8.23%, grid 0.04 lower):**
| Kick | Actual | directZone | WallPredictor | Correct? | Announced? |
|------|--------|------------|---------------|----------|------------|
| 1 | Zone 1 | Zone 1 | Zone 1 | ✅ | ✅ (premature) |
| 2 | Zone 1 | — | — | — | ❌ (total tracking loss — identity corrupted by video player) |
| 3 | Zone 1 | null | null | noResult | ❌ (directZone only on predicted frames) |
| 4 | Zone 7 | Zone 1 | Zone 6 | ❌ | ✅ (premature, wrong zone) |

### Monitor Test Results — Session 1 (2026-04-09, no diagnostics)

| Kick | Actual | directZone | WallPredictor | Extrapolation |
|------|--------|------------|---------------|---------------|
| 1 | Zone 1 | null | — | — |
| 2 | Zone 1 | null/1(pred) | 1 | 6 |
| 3 | Zone 7 | 1 | 1 | 1 |
| 4 | Zone 5 | 1 | 5 | 6 |
| 5 | Zone 6 | 1 | 1 | 6 |

### Video Test Results — Session 0 (2026-04-09, monitor playback on iPhone 12)

| Kick | Actual | directZone correct? | WallPredicted | Decision (pre-fix) | Announced? |
|------|--------|-------------------|---------------|----------|------------|
| 1 | Zone 1 | Yes (1 frame) | Zone 1 | HIT zone 1 | Yes |
| 2 | Zone 1 | Yes (3 frames) | null | reset (insufficient frames) | No |
| 3 | Zone 7 | Yes (1 frame) | null | reset (insufficient frames) | No |
| 4 | Zone 5 | Yes (1 frame) | Zone 5 | reset (insufficient frames) | No |
| 5 | Zone 6 | Yes (1 frame) | Zone 6 | HIT zone 6 | Yes |

**Key findings:**
1. **directZone was correct 5/5 (100%)** — the ball was tracked into the correct zone every single time via `pointToZone()` on the actual camera position.
2. **WallPlanePredictor also correct when it fired (2/2)** — but only fired on 2 of 5 kicks.
3. **3/5 kicks blocked by `trackingFrames` counter** — ImpactDetector counted only 1-2 frames despite ByteTrack tracking 5-9 frames. Root cause: ImpactDetector's frame counter increments only during `DetectionPhase.tracking`, but ByteTrack tracks frames before ImpactDetector enters tracking.
4. **3/5 kicks KickDetector stayed `confirming`** — never reached `active` (needs 3 sustained high-speed frames).
5. **No false announcements** — the one phantom decision between kicks had `directZone=null`, so the new logic naturally filters it out.

### Field Test Results (2026-04-06, iPhone 12) — Post-Reconnection

**Phase 1 (plain brick wall, no circles, ~11m):**
| Kick | Actual | Predicted | Result |
|------|--------|-----------|--------|
| 1 | Zone 1 | Zone 1 | ✅ Correct (announced before impact) |
| 2 | Zone 1 | — | ❌ Missed — KickDetector stayed `idle`, result rejected |
| 3 | Zone 7 | Zone 6 | ❌ One row down (announced before impact) |
| 4 | Zone 5 | Zone 2 | ❌ One row down (announced before impact) |

**Phase 2 (Flare Player banner with circles, ~11m):**
| Kick | Actual | Predicted | Result |
|------|--------|-----------|--------|
| 1 | Zone 7 | Zone 6 | ❌ One row down (announced before impact) |
| 2 | Zone 9 | Zone 6 | ❌ Wrong column + wrong row; circle dot on zone 9 |
| 3 | Zone 8 | Zone 6 | ❌ Wrong column + wrong row; false trail from zone 5 circle |

### Field Test Results (2026-04-04, iPhone 12)
- **Phase 1 (tripod waist height ~0.8m, 11m from target):** 7/18 correct (38.9%), zone 6 bias (11/18 reported zone 6, 0 were actually zone 6)
- **Phase 2 (tripod chest height ~1.25m, 11m from target):** 1/9 correct (11.1%), zone 1/2 bias
- **Both phases:** 23/27 kicks announced "too soon" — before ball reached the target

### Android Test Device Change
Android test device changed from **Galaxy A32 (SM-A325F)** to **Realme 9 Pro+ (Snapdragon 695)**.

## What Is Fully Working
- **YOLO live camera detection (iOS)** — `YOLOView` renders correctly on iPhone 12 with ball trail, "Ball lost" badge, and all overlays
- **YOLO live camera detection (Android)** — `YOLOView` renders on Realme 9 Pro+ with `onResult` confirmed firing. Trail dots, connecting lines, and "Ball lost" badge all visually confirmed working.
- **Ball tracking throughout flight** — YOLO + ByteTrack tracks the ball during flight. Track identity subject to corruption (ISSUE-026).
- **Pre-ByteTrack AR filter (2026-04-13)** — Rejects YOLO detections with aspect ratio > 1.8 in `_toDetections()` before they enter ByteTrack. Eliminates torso/limb false positives (AR 2.4-3.6). Device-tested on monitor — reduced false positive trail dots.
- **Debug bounding box overlay (2026-04-09)** — Visual debug overlay showing all ball-class detections with colored bboxes (green=locked, yellow=candidate, red=lost), trackId, bbox WxH, aspect ratio, confidence, isStatic. Toggle: `_debugBboxOverlay` const. **Currently disabled** (`false`).
- **Calibration geometry diagnostics (2026-04-09)** — Logs 15+ geometric parameters at every calibration and pipeline start for cross-session comparison.
- **Enhanced BallIdentifier logging (2026-04-09)** — Re-acquisition events log old→new trackId, bbox shape, reason. Lost events show all candidates with full info.
- **Backend switching infrastructure** — `DETECTOR_BACKEND` env var system preserved; currently only `yolo` is implemented
- **Landscape orientation** — YOLO mode forces landscape in `initState`, restores portrait+landscape on `dispose`
- **Home screen** — Minimal launch screen with soccer icon, title, subtitle, and "Start Detection" button
- **Navigation** — Two routes: homeScreen (`/`) and cameraScreen (`/camera/`)
- **Ball trail (Phase 7)** — `BallTracker` service with bounded 1.5s ListQueue, occlusion sentinels, 30-frame auto-reset, min-distance dedup. `TrailOverlay` CustomPainter with fading orange dots, connecting lines, occlusion gap skipping, FILL_CENTER crop correction via `YoloCoordUtils`.
- **Camera aspect ratio (4:3)** — Corrected from 16:9 to 4:3. Visually correct on both platforms.
- **"Ball lost" badge (Phase 8)** — Device-verified on iPhone 12 and visually confirmed on Realme 9 Pro+.
- **Android coordinate correction** — MethodChannel rotation polling + `(1-x, 1-y)` flip for rotation=3.
- **aaptOptions fix** — `aaptOptions { noCompress 'tflite' }` in `build.gradle` resolved Android `onResult` silence.
- **Widget test** — 3 `DetectorConfig` unit tests passing.
- **Camera permission handling** — `permission_handler: ^11.3.1` added. `_requestCameraPermission()` in `initState` explicitly requests camera permission before rendering `YOLOView`. iOS Podfile configured with `PERMISSION_CAMERA=1` macro.
- **AppBar removed** — Scaffold no longer has `appBar`. Camera preview fills full screen height in landscape (~56px reclaimed).
- **Back button badge** — Circular back arrow icon at top-left. Works during all calibration stages.
- **Draggable calibration corners with finger occlusion fix** — Hollow green ring markers, 30px vertical offset cursor during drag, full-width/height crosshair lines. Device-verified on iPhone 12 and Realme 9 Pro+.
- **Pipeline gating (`_pipelineLive`)** — Detection pipeline only activates after full calibration + reference ball confirm. Device-verified on iPhone 12 and Realme 9 Pro+.
- **Impact detection (Phase 3)** — `ImpactDetector` state machine (Ready -> Tracking -> Result -> Ready). Decision based on last observed `directZone` (ball's actual position in grid). Edge exit → MISS. No directZone → noResult. 150 unit tests (was 94, updated for new decision logic).
- **tickResultTimeout() fix (2026-03-23)** — `ImpactDetector.tickResultTimeout()` called every frame outside the kick gate, so the result display 3-second timeout always clears regardless of kick state. Fixes stuck overlay bug (Bug 1).
- **Audio feedback (Phase 4)** — `AudioService` singleton with lazy `AudioPlayer`. HIT audio: "You hit N!" + crowd cheer (~4.7s). MISS buzzer. Device-verified on iPhone 12, Galaxy A32, and Realme 9 Pro+.
- **Depth estimation (Phase 5)** — Reference Ball Capture + depth ratio trust qualifier. Depth-verified zone stored for diagnostics but no longer used for decisions (directZone is primary).
- **KickDetector service (2026-03-23)** — `lib/services/kick_detector.dart`. 4-state machine: idle → confirming → active → refractory. Integrated into live screen as **result gate**: accepts results when kick state is `confirming` OR `active` (was `active` only, loosened 2026-04-09). `onKickComplete()` also transitions from `confirming` to refractory.
- **DiagnosticLogger service (2026-03-23)** — `lib/services/diagnostic_logger.dart`. Per-frame and per-decision CSV logging. Writes to app documents directory. CSV includes `kick_confirmed` and `kick_state` columns. Share Log button exports CSV via `Share.shareXFiles`.
- **IMPACT DECISION diagnostic block (2026-04-09)** — Now includes `lastDirectZone`, `kickState`, and `ballConfidence` fields. No more blind spots in decision analysis.
- **`TrackedObject.confidence` field (2026-04-09)** — YOLO confidence surfaced from ByteTrack internal `_STrack` to public `TrackedObject` class.
- **Camera alignment aids (2026-04-08)** — Center crosshair, tilt indicator, shape validation in `CalibrationOverlay`. Device-verified on iPhone 12.
- **Large result overlay temporarily commented out (2026-04-08)** — Center-screen zone number / MISS overlay disabled for testing phase. Audio + bottom-right badge still announce results.
- **Code snapshots directory (2026-04-08)** — `memory-bank/snapshots/` for pre-change backups of source files before risky edits.
- **Two-way isStatic classification (2026-04-13, ISSUE-027 FIXED)** — ByteTrack `_STrack.evaluateStatic()` now uses sliding window displacement (last 30 frames) instead of lifetime cumulative accumulator. Flag transitions both ways: `false→true` when ball stops, `true→false` when ball moves. Inspired by Frigate NVR's production static object detection. Device-verified on iPhone 12.
- **Code quality** — `flutter analyze` 0 errors, 0 warnings, 81 infos. `flutter test` 176/176.
- **Evaluation documentation** — `docs/` and `result/android/` contain evidence from both platforms.

## What Is Partially Done / In Progress
- **Pre-ByteTrack AR filter — IMPLEMENTED, NEEDS FIELD TEST** — Rejects AR > 1.8 in `_toDetections()`. Monitor-tested, reduced false positive dots on player. Needs real field test to confirm.
- **directZone decision logic — PROVEN UNRELIABLE** — Reports first zone entered (always zone 1 for upward kicks), not impact zone. 0/5 to 3/4 correct depending on calibration. Needs fundamental rethink.
- **Mahalanobis rescue identity hijacking (ISSUE-026, CRITICAL)** — Locked track jumps to false positives. Causes total tracking loss. Fix code was written/tested/reverted this session — ready to re-apply after AR filter field test.
- **~~isStatic flag never clears (ISSUE-027)~~** — ✅ FIXED (2026-04-13). Sliding window displacement replaces lifetime accumulator. Device-verified.
- **`tennis-ball` accepted at priority 2** — Diagnostic concession from Phase 9; unnecessary but harmless.
- **Ball identifier re-acquisition** — Picks up player walking, target circles on bounce-back. Needs conservative re-acquisition during idle state.
- **False trail dots on non-ball objects — PARTIALLY MITIGATED** — AR filter reduces torso false positives. Player head (ar:0.9) still passes. Root cause is BallIdentifier track identity, not trail timing.
- **Phantom impact decisions during idle (log pollution)** — ImpactDetector fires decisions during kick=idle. NOT announced (KickDetector result gate blocks). Diagnostic log noise only.
- **Extrapolation overshoot in trail dots** — Video test showed trail dots extending past the grid (zone 8 and beyond) on kicks aimed at zone 5 or 7. The Kalman prediction keeps projecting linearly after the real ball stops. Trail dots are drawn from Kalman predictions, not just real detections.
- **Track ID churn (cosmetic)** — YOLO fires two detections per ball (Soccer ball + ball classes), each creating a separate ByteTrack track. Does NOT affect functionality — BallIdentifier follows locked track only. NMS dedup would fix if desired.

## Known Critical Issue: Target Circle False Positives (ISSUE-022)
**Status: CONFIRMED — physical fix required. Remove circles from target fabric.**

ByteTrack Round 3 (Mahalanobis restricted to locked ball) eliminates circle false positives during active ball tracking. However, circles still cause problems via:
- Ball identifier re-acquisition picks up circle detections after ball is lost
- Circle dot observations pollute trajectory data during kicks

**Decision: Remove circles from physical target.** The zones are defined by calibration corners + homography, not by physical circle markings.

## Known Gaps (Minor)
- **iOS camera description** — `Info.plist` placeholder (`"your usage description here"`) on lines 30 and 32. Must update before external demo.
- **No version control** — Git may be initialized as local safety net (developer considering). Project has no remote.
- **WallPlanePredictor/TrajectoryExtrapolator still in codebase** — No longer used for decisions but code remains. Can be cleaned up in future refactor. WallPlanePredictor still runs and logs `lastWallPredictedZone` for diagnostic comparison.

---

## NEXT FEATURE: Target Zone Impact Detection

### Feature Summary
A numbered target sheet (1760mm x 1120mm) with a 3x3 grid of zones (1-9) is attached to a goal post. After a ball is kicked, the app detects which zone was hit and calls out the number.

### Target Zone Layout (hardcoded in app)
```
Top row (L->R):    7, 8, 9
Middle row (L->R): 6, 5, 4
Bottom row (L->R): 1, 2, 3
```
Each zone is approximately 587mm x 373mm.

### Physical Target Sheet
- Dimensions: 1760mm wide x 1120mm tall
- Black background with red LED-ringed circles and gold numbers — **THE CIRCLES CAUSE YOLO FALSE POSITIVES**
- Mounted on solid green metal fence (ball cannot pass through)
- Banner material, not rigid — shows wrinkles and folds

### Implementation Phases
| Phase | What it delivers | Status |
|---|---|---|
| Phase 1 | Calibration mode -- tap 4 corners, green grid overlay | ✅ COMPLETE |
| Phase 2 | Kalman filter + trajectory tracking | ✅ COMPLETE |
| Phase 3 | Impact detection + zone mapping + result display | ✅ COMPLETE |
| Phase 4 | Audio feedback -- number callouts + miss buzzer | ✅ COMPLETE |
| Phase 5 | Depth estimation (ball size tracking) to filter false impacts | ✅ COMPLETE (trust qualifier) |
| KickDetector | Kick gate to prevent false triggers from non-kick movement | ✅ COMPLETE |
| DiagnosticLogger | Per-frame/per-decision CSV logging for field analysis | ✅ COMPLETE |
| **directZone decision** | **Use ball's actual grid position instead of prediction** | **✅ IMPLEMENTED — PENDING FIELD TEST** |
| **FALSE POSITIVE FIX** | **Remove circles from physical target fabric** | **🟡 PHYSICAL CHANGE NEEDED** |
| **Guided Setup Flow** | **Voice-guided camera positioning with auto-lock (7-step flow)** | **🔴 NEXT — #1 FEATURE** |

### User Experience Flow (LOCKED 2026-04-06)

**Step 1: Static instruction screen (before camera)**
Illustration showing tripod behind kicker, centered on target. Voice: *"Place your phone on the tripod, behind the kicking spot, facing the target."* → Tap Next.

**Step 2: Tap 4 corners (existing behavior)**
Camera preview loads in landscape. Voice: *"Tap the 4 draggable corners of the target."* User taps TL, TR, BR, BL.

**Step 3: Guided position adjustment (NEW — one issue at a time)**
Green grid appears. Voice-guided position checks from the 4 corner positions:
- Distance check → *"Move 2 steps closer"* / *"Move 5 steps back"*
- Centering check → *"Move camera a little left"* / *"Move camera right"*
- Height check → *"Move camera up"* / *"Move camera down"*
- Angle check → *"Straighten camera"*
- Stability check → *"Hold steady..."*

Color-coded quadrilateral border: Red = not ready, Yellow = almost there, Green = good.
One instruction at a time. Each criterion shows a small checkmark when passed.
As user adjusts tripod, they re-tap corners (or corners auto-update if edge detection added later).

**Step 4: Auto-lock**
When all criteria green for 1+ second → haptic vibration → Voice: *"Position locked."* → Enable next step.

**Step 5: Reference ball capture (existing behavior)**
Voice: *"Place the ball on the target."* → YOLO detects ball → red bounding box → user taps Confirm.

**Step 6: Live detection starts**
Voice: *"All set. Start kicking!"* → *"Ready — waiting for kick."*

**Step 7: Kick detection (existing behavior)**
Ball kicked → KickDetector gates → ImpactDetector tracks → zone announced → *"You hit seven!"* + crowd cheer + zone highlights yellow + large overlay (3s). Miss → buzzer + *"MISS"*. 3-second cooldown → auto-reset → *"Ready — waiting for kick."*

**Design principles (from research):**
- Voice-first: user is 10m away from phone, cannot read screen
- One instruction at a time: don't overwhelm with all criteria simultaneously
- Color-coded feedback: universally understood, no reading needed
- Auto-confirmation: no manual "I'm positioned right" tap
- Real-world precedent: HomeCourt (AR overlay), PB Vision (CourtFocus lock-on), Google Guided Frame (voice + auto-capture), Scanbot (dynamic state-based instructions)

**Position quality checks (all derived from 4 corner taps, no complex math):**
| Check | Measurement | Ideal Range |
|-------|-------------|-------------|
| Distance | Target width as % of frame | 30-50% |
| Centering | Centroid X vs frame center | Within ~10% |
| Height | Centroid Y vs frame center | Within ~15% |
| Angle | Top edge ≈ bottom edge length | Within ~15% |
| Stability | Corner positions stable | 0.5s no movement |

---

## Key Decisions (Existing)

### Key Decision: Camera Aspect Ratio is 4:3
**Decision date:** 2026-02-23
**Rationale:** `ultralytics_yolo` uses `.photo` session preset on iOS (4032x3024). 16:9 caused ~10% Y-offset.

### Key Decision: SSD/TFLite Path Fully Removed
**Decision date:** 2026-03-05

### Key Decision: Android Coordinate Correction via MethodChannel
**Decision date:** 2026-02-25

### Key Decision: aaptOptions Root Cause Fix
**Decision date:** 2026-02-25

### Key Decision: Android Performance Accepted as-is
**Decision date:** 2026-03-05

### Key Decision: No Git / No GitHub
**Decision date:** 2026-03-05

### Key Decision: Unsplash/API Layer Fully Removed
**Decision date:** 2026-03-09

### Key Decision: Target Zone Detection Approach -- Manual Calibration + Multi-Signal Impact Detection
**Decision date:** 2026-03-09

### Key Decision: Kick-State Gate on ImpactDetector — REVERTED (2026-04-08)
**Decision date:** 2026-04-08
**Rationale:** Attempted to gate ImpactDetector and WallPredictor behind KickDetector state to prevent phantom decisions during idle. Broke grounded kick detection — KickDetector's jerk threshold doesn't reliably trigger for low-velocity shots. Fully reverted to unconditional per-frame processing. KickDetector now only gates result acceptance (audio announcement), not pipeline input.

### Key Decision: directZone as Primary Decision Signal (2026-04-09)
**Decision date:** 2026-04-09
**Rationale:** Video test analysis showed directZone (ball's actual position mapped through homography) was correct 5/5 times. WallPlanePredictor, depth-verified zone, and extrapolation all had accuracy and reliability problems. directZone is the simplest and most accurate signal — no prediction, no extrapolation, just where the ball actually is when it's inside the grid. Decision cascade replaced with: edge exit → last directZone → noResult. If the ball never entered the grid, no decision is made.

### Key Decision: Accept `confirming` in Result Gate (2026-04-09)
**Decision date:** 2026-04-09
**Rationale:** KickDetector requires 3 sustained high-speed frames to reach `active`, but fast kicks often have fewer tracked frames. `confirming` already means a jerk spike was detected (explosive onset = real kick). Combined with directZone requirement (ball must have entered the grid), `confirming` is sufficient — false positives are filtered by requiring non-null directZone.

## Model Files: Developer Machine Setup Required
The YOLO model files are gitignored and must be manually placed:

**Android setup:**
```bash
mkdir -p android/app/src/main/assets
cp /path/to/yolo11n.tflite android/app/src/main/assets/
```

**iOS setup:**
1. Copy `yolo11n.mlpackage` into the `ios/` directory
2. Open `ios/Runner.xcworkspace` in Xcode
3. Confirm `yolo11n.mlpackage` is listed under Runner -> Build Phases -> Copy Bundle Resources
   (Xcode reference already exists: `9883D8872F43899800AEC4E1`)

## Active Environment Variable
```bash
# Run with YOLO (default -- only backend now)
flutter run --dart-define=DETECTOR_BACKEND=yolo
# or simply:
flutter run
```

## Immediate Next Steps — INCREMENTAL, ONE AT A TIME
**Rule: Implement ONE filter, device-test, confirm no regression, then move to next.**

1. **Field test AR filter (2026-04-13)** — AR > 1.8 filter is in place and monitor-tested. Needs field test at real distance with actual kicker to confirm torso false positives are caught and real ball is never rejected.

2. **Mahalanobis rescue validation (ISSUE-026)** — After AR filter is field-validated, re-apply size ratio + velocity direction checks inside `_greedyMatch()`. Code was written and tested this session (176/176 pass) but reverted to maintain one-change-at-a-time. Can be re-applied quickly.

3. **Rethink zone determination** — directZone unreliable for upward kicks. Options: (a) WallPlanePredictor as primary (4/4 correct on Test 1), (b) delay decision until depthRatio ~1.0, (c) trajectory extrapolation.

4. **Guided Setup Flow** — #1 feature after tracking is stable. Voice-guided camera positioning with auto-lock (7-step flow).

### Approaches Validated by Research (for reference)
- **Proven in production:** AR filter, size filter, min track age, velocity consistency (Frigate NVR, Hawk-Eye, Norfair, OC-SORT, Roboflow)
- **What DOESN'T work for us:** Post-ByteTrack init delay that blocks BallIdentifier re-acquisition. Any filter between ByteTrack output and BallIdentifier input must pass ALL tracks through — it can tag/score them but must not remove them from BallIdentifier's candidate pool.
- **Player head (ar:0.9, c:0.98) is unfilterable with geometry alone** — needs either a second-stage crop classifier (MobileNetV2, ~5ms on iPhone 12) or motion channel validation (frame differencing, not available from ultralytics_yolo plugin).
- **Track ID churn is cosmetic** — YOLO dual-class detections create duplicate tracks but BallIdentifier only follows the locked track. High track IDs (e.g., id:55) don't affect functionality.
