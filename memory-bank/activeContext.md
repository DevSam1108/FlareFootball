# Active Context

> **CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Current Focus
**Anchor Rectangle Phase 5 — audio announcements, all four commits landed and iOS-verified (2026-04-23 / 2026-04-24).** Phase 5 scope reduced during design discussion to just two prompts (the "Ball far" nudge was deferred pending field evidence it's needed). Two flow-gap bugs surfaced in field testing and were fixed in the same session.

- **Commit 1 (2026-04-23, iOS-verified) — tap-prompt asset wiring.** `playTapPrompt()` wired to `assets/audio/tap_to_continue.m4a` (Samantha TTS, rate 170, no cheer). Per-episode counter + timestamp `print` retained because audio playback cannot be verified from screen recordings. First audio fired at t+30 s in State 2, repeated every 10 s until ball tap, counter reset correctly on State 1↔2 transitions. See ADR-079.
- **Commit 2 (2026-04-23, iOS-verified) — "Ball in position" announcement.** New `AudioService.playBallInPosition()` plays `assets/audio/ball_in_position.m4a` (shortened to just "Ball in position" by the user on 2026-04-24; ~1 s clip). Screen-side trigger lives inline in the existing `onResult` `if (_pipelineLive)` block — single `DateTime? _lastBallInPositionAudio` field driving a 10 s cadence check (user tuned from the initial 5 s on 2026-04-24 for less nagging during long idle stretches). No Timer, no cancel methods (ADR-080). Null-resets in `_startCalibration` (Recal-1) and `dispose`. Field verification captured 4 fires across ~20 s of gameplay at expected edges (lock, cadence on steady ball, return-to-anchor after each kick).
- **Commit 3 (2026-04-24, iOS-verified) — State 3→2 audio nudge restart fix (ISSUE-032).** Flow gap: once user taps a ball (State 2→3), the nudge timer is cancelled by `_handleBallTap`; if the selected track then flickers out of `_ballCandidates`, the aliveness check (Decision B-i) silently clears `_selectedTrackId` and drops UI back to State 2, but the existing 1↔2 timer-transition block doesn't cover the 3→2 case — `hadCandidates == hasCandidates == true`, so no restart fires. User left in silent State 2 with no audio reminder. Fix: `final hadSelection = _selectedTrackId != null;` capture at top of block, plus a mutually-exclusive `else if (hadSelection && _selectedTrackId == null && hasCandidates) _startAudioNudgeTimer();` branch at the end of the existing chain. 4 lines of functional code, zero changes to other audio plumbing, no new state. See ADR-081.
- **Commit 4 (2026-04-24, iOS-verified) — `isStatic` gate on "Ball in position" (ISSUE-033).** Flow gap: a ball rolled through the anchor rect without stopping, and the audio fired on the brief frames the center crossed in — ball already outside on the other side by the time the speaker played. A non-looking player would hear "Ball in position" and kick, but the spatial filter drops the detection because the ball is no longer in rect. Fix: added `&& ball.isStatic` as a fourth clause to the existing `inPosition` conjunction. Reuses ByteTrack's sliding-30-frame staticness flag — no new state, no threshold tuning. Accepts ~1 s delay between ball settling and audio firing (staticness window warming up), which is desirable (a ball pausing mid-roll won't falsely trigger). 1 line of functional code. See ADR-082.

**Phase 5 implementation pattern (codified as `feedback_reuse_existing_first.md`):** prefer reusing the existing `onResult` per-frame loop with a single timestamp field for cadence, instead of adding new `Timer` objects + `_startXxx()` / `_cancelXxx()` methods. Applied in Commit 2's trigger: the condition itself (`ballDetected && inside rect && isStatic`) is the single truth source; when it becomes false the timestamp nulls and the next true-edge fires immediately.

**Verification:** `flutter analyze` — 0 errors / 0 warnings / 93 infos (all pre-existing or intentional `avoid_print`). `flutter test` — 175/175 passing. All four commits are strictly additive — no refactors, no architectural change.

Next: Android (Realme 9 Pro+) verification of all four Phase 5 commits.

### Prior context — Anchor Rectangle Phase 3 polish (2026-04-22, later in day)
Three small additive refinements landed and iOS-verified. After the main Phase 3 implementation, a follow-up session tightened three rough edges:
1. **False-alarm kick recovery (`else if` branch).** When KickDetector flickers into `confirming` for 1–2 frames and returns to `idle` without a decision (e.g. player foot-dribbling the ball), the filter now re-arms on the idle edge instead of sitting OFF for the full 2 s safety window. Same block as the OFF-trigger — one `else if`, mirrors the release-semantics of the decision-accept path (cancels timer, releases session lock, clears protected track).
2. **Orange trail dot on resting ball re-enabled.** `TrailOverlay`'s idle-suppression gate (ADR-069/070) was relaxed so the trail renders during `kick=idle` **only when** `_anchorFilterActive && _anchorRectNorm != null && ball.center ∈ rect`. Because trail positions on a stationary ball overlap at one pixel, this produces the flickering orange dot the user remembered from pre-2026-04-15 builds. Previous FP-on-player-head risk is neutralised by the rect constraint.
3. **`DIAG-ANCHOR-FILTER` log upgrade.** The log now emits every frame the filter is active (not only on drops), includes bbox size `(w×h)` for both passed and dropped detections, and labels the two lists as `passed (inside rect)` / `dropped (outside rect)` for unambiguous reading. Surfaces frames where YOLO emits zero ball-class detections (`passed=0 dropped=0`) — which is what actually explains earlier "passed=0 while ball visible" spells (upstream YOLO miss, not filter bug).

**Field tests (2026-04-22, iPhone 12) after the three polish changes:**
- **First run** — explicitly exercised the new `else if` idle-edge recovery. Log captured the full sequence: `re-acquired from trackId=1 → trackId=5` → `OFF (kick state=confirming) — 2s safety timer armed` → `session lock DEACTIVATED` → **`ON (kick returned to idle — false-alarm recovery)`**. The brief confirming-flicker triggered by the ball rolling back into rect was correctly classified as a false alarm and the filter re-armed immediately without waiting for the 2 s safety timer. **Verified working.**
- **Consecutive-hit run** — two kicks captured end-to-end; filter behaviour clean throughout both cycles. Real ball consistently passed every frame when YOLO emitted it; target-circle FPs consistently dropped; ball-return re-acquisition from trackId=1 → trackId=2 clean at rect boundary. No flicker in this particular run, but the branch is already field-proven from the first run. **The decision logic itself remains broken** — both kicks declared `HIT zone 1` when the ball actually crossed zones 1 → 6 → 7 on the way out of frame; decisions fired at `trackingFrames = 4/5` with `depthRatio ≈ 0.45`, i.e. mid-flight before the ball reached wall depth. That is the known "directZone = first zone entered" + premature-fire bug from CLAUDE.md; orthogonal to all anchor-rectangle work.

**Prior context (main Phase 3 implementation, 2026-04-22 earlier):** Spatial filter drops raw YOLO detections whose bbox center is outside `_anchorRectNorm` before ByteTrack sees them. State machine: ON at lock → OFF at KickDetector `confirming`/`active` (2 s safety timer armed) → ON at decision fire (accept or reject path) or 2 s timeout. Six iOS smoke tests passed. **Bonus win confirmed in the field:** target circle false positives (ISSUE-022, the #1 field-test blocker) are now silently dropped every frame at their fixed on-banner positions. Android (Realme 9 Pro+) verification still pending. Phase 4 (Return-to-Anchor) evaluated and deemed **mostly redundant** with what Phase 3 already delivers — re-acquisition into rect, filter re-arm on decision, and rect persistence across kicks were all verified working without Phase 4 code. The only genuinely-new Phase-4 deliverable (a "ball far, bring closer" voice prompt) is a Phase 5 audio concern, not a Phase 4 mechanics concern. Decision: **skip Phase 4 as a standalone phase**; fold its one real deliverable into Phase 5.

**Prior context (Phase 2, 2026-04-20):** magenta dashed anchor rectangle drawn at lock time, sized 3× bbox width × 1.5× bbox height, frozen, screen-axis-aligned. Visual only; ADR-076.

**Prior context (Phase 1, 2026-04-19):** iOS-verified. Replaced auto-pick-largest heuristic with explicit player tap-to-select (two-step UX: tap red bbox → turns green → Confirm commits). All 12 Phase 1 design decisions resolved and recorded in `memory-bank/anchor-rectangle-feature-plan.md` + ADR-073. Two back-button z-order bugs fixed (ADR-074). Audio nudge stub has per-episode counter + timestamp for log-based cadence verification (ADR-075).

### What Was Done This Session (2026-04-22, follow-up) — Phase 3 polish
1. **`else if` branch in the Phase 3 OFF-trigger block** (`live_object_detection_screen.dart`, adjacent to the existing `if (_anchorFilterActive && (KickState.confirming || isKickActive))`). Fires when `!_anchorFilterActive && _safetyTimeoutTimer != null && kick.state == KickState.idle`. Effect: re-arm filter, cancel/null the safety timer, release session lock, clear protected track, print `DIAG-ANCHOR-FILTER: ON (kick returned to idle — false-alarm recovery)`. Rationale: the safety timer was a 2 s dead window during which filter stayed OFF even after a false-alarm kick resolved back to idle. Now the filter mirrors kick state in both directions.
2. **`TrailOverlay` idle-rect exception** (`live_object_detection_screen.dart`, Stack where `trail:` is passed to `TrailOverlay`). Gate changed from `kick.state == idle ? [] : trail` to also pass `trail` when `_anchorFilterActive && _anchorRectNorm != null && currentBallTrack != null && _anchorRectNorm!.contains(currentBallTrack!.center)`. Effect: the orange dot re-appears on the resting ball inside the rect; when the ball is outside the rect (between kicks), idle suppression still applies.
3. **`DIAG-ANCHOR-FILTER` log upgrade** (`_toDetections`):
   - Added `anchorPassedDetails` list alongside existing `anchorDroppedDetails`.
   - Both dropped and passed entries now include `size=(w×h)` (same format/precision as the existing position/confidence fields).
   - Log gate changed from `if (anchorDropped > 0)` to `if (anchorActive)` — fires every frame the filter is ON. Makes `passed=0 dropped=0` frames (YOLO detection miss) visible.
   - Label rename: `dropped: [...]` → `dropped (outside rect): [...]`, new `passed (inside rect): [...]` prepended.
4. **Phase 4 scope review** — walked through the plan's Phase 4 spec ("Return-to-Anchor") against what Phase 3 already delivers. Conclusion: filter re-arm on decision + BallIdentifier's Mahalanobis rescue already provide implicit re-acquisition into the rect; rect persistence across kicks is already working; explicit partially-in-rect vs fully-in-rect predicate is only useful for the "ball far, bring closer" nudge which is audio (Phase 5). Decision: skip Phase 4 as a standalone phase, fold its one real deliverable into Phase 5.

### What Was Done This Session (2026-04-22, main) — Phase 3
Incremental implementation in small reviewed steps, no refactors of working code:

1. **State plumbing** in `_LiveObjectDetectionScreenState`:
   - `bool _anchorFilterActive = false;`
   - `Timer? _safetyTimeoutTimer;`
2. **ON trigger at lock** — `_confirmReferenceCapture()` sets `_anchorFilterActive = anchorRect != null;` alongside the existing `_anchorRectNorm = anchorRect;`. Emits `DIAG-ANCHOR-FILTER: ON (locked — …)` with rect bounds.
3. **OFF trigger at kick start** — new adjacent block next to the existing session-lock activation; fires on `KickState.confirming` OR `isKickActive`, guarded by `_anchorFilterActive` itself as the edge detector. Starts 2 s `Timer` and emits `DIAG-ANCHOR-FILTER: OFF (kick state=…)` log.
4. **Re-arm on decision** — two tiny additions inside the existing accept/reject branches of the result gate. Sets flag true, cancels timer. Emits `ON (decision fired — accepted|rejected)`.
5. **Safety timeout handler** — new private method `_onSafetyTimeout()` next to `_cancelAudioNudgeTimer`. Re-arms filter, releases session lock, clears protected track. Self-recovers the pipeline after 2 s of stuck decision.
6. **Reset + dispose** — cleared in `_startCalibration` and `dispose`; mirrors pattern of existing timers.
7. **The actual filter** — inside `_toDetections`, AFTER Android rotation correction, BEFORE `detections.add(...)`: `if (anchorActive && !_anchorRectNorm!.contains(bbox.center)) continue;`. Counters `anchorDropped` / `anchorPassed` + per-detection details accumulated; single summary print per frame when drops > 0.
8. **Enriched drop log** — each dropped detection logged with class, center, confidence so we can verify visually which specific object was dropped and which passed.
9. **Session-end field testing (iPhone 12)** — six smoke tests run and passed; target circle FPs confirmed to be silently filtered.

### Phase 3 footprint
- **1 source file modified (`live_object_detection_screen.dart`). No new files. No new tests.**
- **Zero refactors of working code.** All changes are additive (new fields, new blocks adjacent to existing ones, new private method). The aspect-ratio filter, class filter, Android rotation correction, session lock, Mahalanobis rescue, and `isKickActive` condition are all unchanged.
- **Zero architectural changes.** No new services, no new patterns, no new dependencies.
- **`memory-bank/feedback_no_refactor_bundling.md`** added to user memory to codify "additive-only changes during feature work" rule.

### Phase 3 — what is NOT yet done
- DiagnosticLogger CSV columns (Step 7 of the original plan) — deferred as optional. Console logs are sufficient for current verification needs.
- Android (Realme 9 Pro+) verification
- Field-tuning of `3× × 1.5×` rect multipliers (observation: rect is tight for small balls; Mahalanobis rescue still recovers, so not a blocker)
- Throttle drop log under sustained same-count drops (QoL, not correctness)
- "Rejected" log wording refinement when filter was already ON (cosmetic)
- Return-to-anchor cycle (Phase 4)
- Audio announcements (Phase 5)

### What Was Done This Session (2026-04-19)
1. **Design discussion & spec** — Walked through all 12 Phase 1 decisions: lock flow (B), visual (B-α), tap rule (Tap-2), prompts (S1-a + State 2/3 text), audio (Audio-2: 30 s / 10 s), re-cal (Recal-1), two-tap (A-i), ball-disappears (B-i), post-Confirm, gesture arena (Gesture-1). Recorded in `memory-bank/anchor-rectangle-feature-plan.md`.
2. **`lib/services/ball_identifier.dart`** — `setReferenceTrack(List<TrackedObject>)` → `setReferenceTrack(TrackedObject)`. Removed in-method filter/sort/take-largest; caller is now responsible for selection.
3. **`lib/services/audio_service.dart`** — Added `playTapPrompt()` stub + per-episode counter `_tapPromptCallCount` + `resetTapPromptCounter()`. Prints `AUDIO-STUB #N: Tap the ball to continue (HH:MM:SS.mmm)` so cadence is verifiable from device log alone.
4. **`lib/screens/live_object_detection/live_object_detection_screen.dart`** —
   - State: `_ballCandidates` (list of `(trackId, bbox)`), `_selectedTrackId` (int?), `_audioNudgeTimer` (Timer?).
   - `_ReferenceBboxPainter` refactored from single bbox → `List<({Rect bbox, bool isSelected})>`; per-item colour (red `0xFFFF0000` unselected, green `0xFF00E676` selected).
   - `onResult` collects ALL ball-class tracked candidates; aliveness-checks `_selectedTrackId` (B-i); drives State 1↔2 audio timer transitions; `_referenceCandidateBboxArea` now mirrors the SELECTED track.
   - `_findNearestBall`: mirrors `_findNearestCorner`. Tap-2 (inside-bbox direct hit first; else nearest-by-center within `_dragHitRadius = 0.09`).
   - `_handleBallTap`: last-tap-wins (A-i). Off-target tap = no-op.
   - `_startAudioNudgeTimer` / `_cancelAudioNudgeTimer`: 30 s grace + 10 s repeat. Resets the `AudioService` per-episode counter on start.
   - GestureDetector at line ~1191: added `onTapUp` alongside existing `onPanStart/Update/End` (Gesture-1).
   - Prompt text: 3-state ternary (S1-a / "Tap the ball you want to use" / "Tap Confirm to proceed with selected ball"). State 3 shows in greenAccent.
   - `_confirmReferenceCapture`: resolves `_selectedTrackId` → `TrackedObject` in current frame, bails on race-window disappearance, passes to new `setReferenceTrack(track)` API, cancels nudge timer.
   - `_startCalibration` (Recal-1): clears tap selection + cancels nudge timer.
   - `dispose`: cancels nudge timer.
   - **Back-button z-order fix:** moved `Positioned` back-button block from early in the Stack (line ~1015) to just before the rotate overlay. Closes ISSUE-031 (both pre-existing calibration-mode case and Phase 1 awaiting-capture regression).
   - **Drive-by cleanup:** removed unused legacy field `_referenceCandidateBbox` (1 declaration + 2 dead `= null` writes).
5. **`test/ball_identifier_test.dart`** — Rewrote 4 obsolete auto-pick-largest tests as 3 new contract tests for the new signature. Updated 14 other call sites from `[_track(...)]` to `_track(...)`.

### Phase 1 footprint
- **3 source files + 1 test file touched. No new files. No new assets.**
- **~110 lines net code delta after honest reuse accounting.** +409 / −114 across the whole session (includes markdown + doc-comments + memory-bank updates).
- **0 architectural changes.** No new services, no new patterns, no new dependencies.

### Phase 1 — what is NOT yet done (out of scope for this phase)
- ~~Anchor rectangle drawing (Phase 2 — deferred)~~ → **DONE 2026-04-20**
- Detection filter using rectangle (Phase 3 — deferred)
- Return-to-anchor cycle (Phase 4 — deferred)
- Real audio asset for tap prompt (Phase 5 — currently a `print` stub with counter + timestamp for testability)

### What Was Done This Session (2026-04-20) — Phase 2
1. **Design discussion & spec** — Resolved all four Phase 2 open questions in a discussion-only session:
   - Rectangle size: **bbox-relative multipliers** (3× width × 1.5× height), not a cm-based conversion. Avoids the implicit fixed-ball-diameter assumption the plan draft had. Perspective scales automatically with the locked ball's bbox.
   - Center behavior: **frozen** at lock-time bbox center (does not follow the ball). "Anchor" is meaningful only as a fixed region.
   - Orientation: **screen-axis-aligned** (long side horizontal). Filtering region identical to target-aligned; hit test trivially axis-aligned for Phase 3.
   - Style: **magenta, dashed, 2 px stroke, no fill**. Distinct from every existing color on the screen.
   Recorded in `memory-bank/anchor-rectangle-feature-plan.md` Phase 2 section + ADR-076.
2. **`lib/utils/canvas_dash_utils.dart` (new file)** — Shared `drawDashedLine(canvas, start, end, paint, {dashLength, gapLength})` helper. Lifted byte-for-byte from `calibration_overlay.dart`'s private `_drawDashedLine`. Single source of truth for dashed-line rendering.
3. **`lib/screens/live_object_detection/widgets/calibration_overlay.dart`** — Removed private `_drawDashedLine`. Imported and called the shared util. Center crosshair behaviorally unchanged (same dash length, gap, color, thickness).
4. **`lib/screens/live_object_detection/live_object_detection_screen.dart`** —
   - State: `Rect? _anchorRectNorm` — anchor rectangle in normalized [0,1] coords.
   - `_resetAllState()`: nulls `_anchorRectNorm` (Recal-1 full reset).
   - `_confirmReferenceCapture()`: finds the selected candidate in `_ballCandidates`, computes `Rect.fromCenter(center, width × 3, height × 1.5)`, assigns into `_anchorRectNorm` inside the `setState`.
   - Stack: new `if (_anchorRectNorm != null)` block wrapping `LayoutBuilder` → `IgnorePointer` → `CustomPaint(painter: _AnchorRectanglePainter(...))`, positioned before the Confirm button. Rectangle visible post-lock, independent of other state.
   - New private class `_AnchorRectanglePainter` — magenta (`0xFFFF00FF`) stroke, 2 px, no fill. Paints 4 edges via `drawDashedLine` using `YoloCoordUtils.toCanvasPixel` for normalized → canvas conversion. `shouldRepaint` compares `rectNorm` + `cameraAspectRatio`.
   - Import: `package:tensorflow_demo/utils/canvas_dash_utils.dart`.

### Phase 2 footprint
- **2 source files modified + 1 new file. No tests touched (visual-only change, no behavior to unit-test).**
- **0 architectural changes.** No new services, no new patterns, no new dependencies.
- **Code reuse:** shared dash helper consumed by both calibration crosshair and anchor rectangle — single source of truth.

### Phase 2 — what is NOT yet done
- Detection filter using rectangle (Phase 3 — next)
- Return-to-anchor cycle (Phase 4)
- Audio announcements & edge cases (Phase 5)
- Field-tuning of the 3× / 1.5× multipliers (waits until Phase 3 so we can see filtering behavior in context)
- Android verification

### On-device verification status

**iOS (iPhone 12) — VERIFIED 2026-04-19 (Phase 1) + 2026-04-20 (Phase 2) + 2026-04-22 (Phase 3)**
- [x] Phase 1 tap-to-lock flow works end-to-end
- [x] Back button works in all states (calibration mode, awaiting reference capture, live pipeline)
- [x] Phase 2 magenta dashed anchor rectangle renders at locked ball's position (screenshot confirmed 2026-04-20)
- [x] Center calibration crosshair unchanged after shared-util refactor
- [x] **Phase 3 smoke tests (2026-04-22):**
  - Test 1 — ON trigger at lock: pass
  - Test 2 — filter drops outside-rect decoy detections: pass
  - Test 3b — kick-not-caught path (filter stays ON, locked track dies, recovery on ball return): pass; **target circles visibly dropped at fixed positions**
  - Test 3 — normal kick path: full `ON → OFF → ON` cycle observed, safety timer armed and correctly un-fired, reject path also exercised
  - Test 4 — safety timeout fire: not reproduced in this session; deferred to opportunistic observation
  - Test 5 — re-calibration reset: pass
  - Test 6 — dispose cleanup: pass

**Android (Realme 9 Pro+) — PENDING (all phases)**
- [ ] Re-run the same checklist. Specifically watch for:
  - Gesture arena behaviour (Android touch slop differs from iOS — may affect Tap-2 vs corner-drag disambiguation)
  - Audio nudge cadence in `adb logcat` (`AUDIO-STUB #N` lines, 30 s grace + 10 s repeat, counter resets on State 2→1→2 transition)
  - Recal-1 clears selection + cancels nudge timer
  - No regression on kick detection / zone announcement post-Confirm
  - No phantom corner placed under back button during calibration
  - Phase 2 magenta rectangle renders (and recalibration clears it)
  - Phase 3 `DIAG-ANCHOR-FILTER` log lines appear at the same state transitions as on iOS
  - Phase 3 filter does not wrongly drop the locked ball on Android (check `passed=1` dominates during waiting)

### Previous focus (2026-04-16) — context preserved
**Mahalanobis area ratio fix — last-measured-area approach implemented and monitor-tested.** Iterative fix for silent kicks caused by over-aggressive bbox area ratio check on Mahalanobis rescue. Three approaches tested: (1) relaxed Kalman threshold 3.5/0.3 → 4/5 kicks detected but false positive dots returned, (2) last-measured-area with tight 2.0/0.5 → 3/5 (lower bound too tight, ball shrinks during flight), (3) last-measured-area with 2.0/0.3 → 5/5 kicks detected across 3 test runs. False positive dots still appear (open issue). Ground testing scheduled for 2026-04-17.

### Previous Session (2026-04-15)
1. Session lock in BallIdentifier — `_sessionLocked` flag blocks Priority 2/3 re-acquisition during kicks
2. Protected track in ByteTrackTracker — locked track survives 60 frames instead of 30
3. Bbox area ratio check on Mahalanobis rescue (initial version with Kalman predicted area, 2.0/0.5)
4. Trail suppression during kick=idle
5. Monitor+video test: 3/5 kicks, 0 false positive dots, 2 silent kicks identified

### Failed Approach (2026-04-13, earlier session) — DO NOT REPEAT
2-layer filter (DetectionFilter + TrackQualityGate + Mahalanobis rescue validation). Init delay broke BallIdentifier re-acquisition. Player head (ar:0.9) unfilterable with geometry. Must implement ONE filter at a time.

### What Remains / Open Issues
1. **False positive trail dots still appearing** — Dots visible during kicks on non-ball objects. Open issue.
2. **Session lock needs safety timeout** — Auto-deactivate if locked track is lost for N frames without a decision (ISSUE-030). Prevents permanent lock from bounce-back false kicks.
3. **Bounce-back false kick detection** — KickDetector sees bounce-back motion as a new kick. Consider refractory period or direction check to reject bounce-backs.
4. **Player head false positives (ar:0.9, c:0.98)** — Passes AR filter. Unfilterable with geometry alone.
5. **directZone accuracy** — Reports first zone entered, not impact zone. 0/5 to 5/5 correct depending on calibration.
6. **Android verification of Phase 1 + back-button fix** — iOS passed; Android pending.

## What Is Fully Working
- YOLO11n live camera detection on iOS (iPhone 12). Android (Realme 9 Pro+) parity verified through 2026-04-16; Phase 1 changes not yet re-verified on Android.
- ByteTrack multi-object tracker with 8-state Kalman filter
- BallIdentifier with 3-priority identification, session lock, and (NEW 2026-04-19) single-track `setReferenceTrack(TrackedObject)` API driven by player tap
- Ball trail overlay with kick-state-based visibility (dots only during kicks)
- "Ball lost" badge after 3 consecutive missed frames
- 4-corner calibration with DLT homography transform
- 9-zone target mapping via TargetZoneMapper
- ImpactDetector (Phase 3 state machine) with directZone decision
- KickDetector (4-state gate: idle/confirming/active/refractory)
- Audio feedback for impact results (zone callouts + miss buzzer)
- DiagnosticLogger CSV export with Share Log
- Pre-ByteTrack AR > 1.8 filter (rejects torso/limb false positives)
- Session lock prevents re-acquisition during active kicks
- Protected track extends ByteTrack survival for locked ball
- Landscape orientation lock with proper restore
- Camera permission handling
- Rotate-to-landscape overlay with accelerometer
- **(NEW 2026-04-19) Phase 1 tap-to-lock reference capture** — iOS-verified. Multi-bbox red/green painter, Tap-2 snap rule, last-tap-wins, ball-disappears-clears-selection, Recal-1 full reset.
- **(NEW 2026-04-19) Back button** — works in every state including calibration mode and awaiting reference capture (previously blocked by full-screen GestureDetectors).
- **(NEW 2026-04-19) Audio nudge stub with per-episode counter + timestamp** — verifiable from device log alone without a wrist watch.

## What Is Partially Done / In Progress
- **Anchor Rectangle Phase 1** — ✅ Code complete, iOS-verified. Android verification pending. Phases 2–5 not started.
- **Bbox area ratio check on Mahalanobis rescue** — ✅ Fixed (2.0/0.3 threshold, last-measured-area). 5/5 kicks tracked across 3 monitor-test runs.
- **Session lock safety timeout** — Not yet implemented (ISSUE-030 open). Lock can get stuck permanently if no decision fires.
- **directZone accuracy** — Reports first zone entered, not impact zone. Calibration-sensitive. Needs rethink.
- **Bounce-back false detection** — Ball rebound triggers second decision cycle. Not addressed.
- **False positive trail dots during active kicks** — Still appearing. Open issue.
- **Real audio asset for tap-prompt nudge** — Stubbed with `print`. Phase 5 will replace with recorded `audio/tap_to_continue.m4a`.

## Known Gaps
- iOS `NSCameraUsageDescription` has placeholder text ("your usage description here") — must update before any external build
- `tennis-ball` priority 2 in class filter (harmless diagnostic concession)
- Free Apple Dev cert expires every 7 days — re-run `flutter run` to re-sign
- Phantom impact decisions during kick=idle (log noise only, not announced)
- Share Log button is dev-only; not intended to ship to production
- Mid-session Re-calibrate does NOT call `DiagnosticLogger.instance.stop()` (only `dispose` does), so Share Log button stays visible during a mid-session Re-calibrate → corner taps could land under it. Niche and dev-only; not fixing.

## Model Files: Developer Machine Setup Required
**Android:**
```bash
mkdir -p android/app/src/main/assets
cp /path/to/yolo11n.tflite android/app/src/main/assets/
```

**iOS:**
1. Copy `yolo11n.mlpackage` into `ios/` directory
2. Open `ios/Runner.xcworkspace` in Xcode
3. Confirm model appears under Runner → Build Phases → Copy Bundle Resources

## Active Environment Variable
```bash
flutter run --dart-define=DETECTOR_BACKEND=yolo
# or simply:
flutter run
```

## Immediate Next Steps
1. **Fix ImpactDetector decision timing + fallback priority** — this is now the single biggest blocker. Both consecutive-hit field tests (2026-04-22) decided `HIT zone 1` when the ball crossed 1 → 6 → 7. `lastDirectZone` stores the FIRST zone entered (not last), and decisions fire at `trackingFrames=4–5` with `depthRatio ≈ 0.45` — i.e. mid-flight, long before the ball reaches wall depth. Extrapolator (zone 7) and WallPredictor (zone 6) suggested plausible alternates in every case but lost to the `directZone` fallback. Needs design discussion, then a targeted fix in `impact_detector.dart`.
2. **Android parity verification (Realme 9 Pro+)** — run all phases end-to-end, watching for Android-specific rotation-correction edge cases in Phase 3 (`_toDetections` applies rotation flip before the center-in-rect test — confirm drop counts match iOS on the same scene).
3. **Skip Phase 4 as a standalone phase** (decision made 2026-04-22) and go straight to **Phase 5 (audio + edge cases)**. Fold Phase 4's one real deliverable ("ball far, bring closer" nudge with a partially-in-rect predicate) into Phase 5 as ~5 lines of extra code.
4. **Session lock safety timeout (ISSUE-030)** — Phase 3's 2 s filter-safety-timeout + the new idle-edge recovery both already release session lock on their respective paths. The remaining stuck-lock scenario (session lock left ON after a genuine kick that never produced a decision) may already be mitigated. Re-evaluate whether a separate fix is still needed before writing one.
5. **Optional Phase 3 polish (non-blocking):** CSV diagnostic columns, drop-log throttling, reject-path log wording, field-tuning of 3×/1.5× rect multipliers.
