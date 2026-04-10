# Active Context

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Current Focus
**Debug bbox overlay and calibration diagnostics added; directZone proven unreliable (2026-04-09).** Extensive kick-by-kick testing across 3 sessions revealed that directZone (the primary decision signal from earlier this session) is fundamentally flawed — it reports the FIRST zone the ball enters (always zone 1 for upward kicks) rather than the impact zone. Results are highly calibration-sensitive: same video produced 5/5 correct (Session 0), 0/5 correct (Session 1), and 3/4 correct (Session 2 Test 1) depending on 4-corner tap positions.

Two diagnostic tools were added this session: (1) **Calibration geometry diagnostics** — logs 15+ geometric parameters at every calibration for cross-session comparison. (2) **Debug bounding box overlay** — visual overlay showing colored bboxes for all ball-class detections (green=locked, yellow=candidates, red=lost) with trackId, bbox dimensions, aspect ratio, confidence, isStatic flag. Togglable via `_debugBboxOverlay` const.

Three critical bugs discovered through visual debugging:
1. **Mahalanobis rescue hijacks ball identity (ISSUE-026)** — locked track jumps from real ball to false positives via Mahalanobis matching. Causes total tracking loss.
2. **isStatic flag never clears (ISSUE-027)** — ByteTrack static classification is one-way. Ball kicked → still isStatic=true on original track.
3. **YOLO false positives on kicker body at high confidence** — head (ar:0.9-1.0, c:0.95+), torso (ar:2.4-3.6, c:0.99+).

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
- **Debug bounding box overlay (2026-04-09)** — Visual debug overlay showing all ball-class detections with colored bboxes (green=locked, yellow=candidate, red=lost), trackId, bbox WxH, aspect ratio, confidence, isStatic. Toggle: `_debugBboxOverlay` const.
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
- **Code quality** — `flutter analyze` 0 errors, 0 warnings, 56 infos. `flutter test` 173/173.
- **Evaluation documentation** — `docs/` and `result/android/` contain evidence from both platforms.

## What Is Partially Done / In Progress
- **directZone decision logic — PROVEN UNRELIABLE** — Reports first zone entered (always zone 1 for upward kicks), not impact zone. 0/5 to 3/4 correct depending on calibration. Needs fundamental rethink.
- **Mahalanobis rescue identity hijacking (ISSUE-026, CRITICAL)** — Locked track jumps to false positives. Causes total tracking loss. Fix: bbox size/aspect ratio validation on rescue.
- **isStatic flag never clears (ISSUE-027)** — One-way static classification on existing tracks. Fix: velocity-threshold clearing.
- **`tennis-ball` accepted at priority 2** — Diagnostic concession from Phase 9; unnecessary but harmless.
- **Ball identifier re-acquisition** — Picks up player walking, target circles on bounce-back. Needs conservative re-acquisition during idle state.
- **False trail dots on non-ball objects** — Orange trail dots appear on player body, poster, and other non-ball objects when BallIdentifier re-acquires to wrong track. Root cause is BallIdentifier track identity, not trail timing.
- **Phantom impact decisions during idle (log pollution)** — ImpactDetector fires decisions during kick=idle. NOT announced (KickDetector result gate blocks). Diagnostic log noise only.
- **Extrapolation overshoot in trail dots** — Video test showed trail dots extending past the grid (zone 8 and beyond) on kicks aimed at zone 5 or 7. The Kalman prediction keeps projecting linearly after the real ball stops. Trail dots are drawn from Kalman predictions, not just real detections.

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

## Immediate Next Steps
1. **Fix Mahalanobis rescue identity hijacking (ISSUE-026)** — Add bbox size/aspect ratio validation before Mahalanobis rescue matches a detection to the locked track. Reject if bboxArea > 3x reference or aspect ratio > 1.5.
2. **Fix isStatic flag (ISSUE-027)** — Add logic to clear isStatic when velocity exceeds threshold for N consecutive frames, or reset on KickDetector confirming transition.
3. **Add YOLO false positive bbox filter** — Reject ball-class detections where bboxArea > 3x reference or aspect ratio > 1.5. Eliminates torso/jacket false positives (ar:2.4-3.6).
4. **Rethink zone determination approach** — directZone unreliable for upward kicks. Options: (a) trajectory extrapolation to wall, (b) WallPlanePredictor as primary (4/4 correct on Test 1), (c) hybrid, (d) delay decision until depthRatio ~1.0.
5. **Test with debug overlay on real field** — Verify if same identity corruption patterns occur with real kicks.
