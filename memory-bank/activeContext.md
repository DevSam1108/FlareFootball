# Active Context

> **CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Current Focus
**Piece A applied 2026-04-29 (kickState idle gate at `_makeDecision`) — partial validation, then a real kick was eaten and we discovered the gate is too narrow. Audio cadence bug (ball-in-position double-fire) also discovered same session, fix designed but not yet applied. Path A (ADR-083/084/085) still in place; mechanism A field validation still owed.**

This session (2026-04-29) covered three distinct phantom-decision / audio scenarios, applied one fix (Piece A), discovered it eats real kicks in a race condition, designed two more fixes (Piece A widening + audio cadence), and updated the open-issue table to reflect Phase 3 already mitigating four older items. Field validation of Piece A is incomplete: the original idle-jitter case is fixed, but a real kick at zone 6 was suppressed when KickDetector dropped to idle one frame before ImpactDetector's lost-frame trigger fired. See ISSUE-035.

### Session 2026-04-29 — scenarios discussed, analyses, and proposed fixes

This is the consolidated record of every scenario walked through with the user this session, in the order they came up. Each entry has: what the user reported / log evidence, the analysis, the proposed fix, and current status.

#### Scenario 1 — Pure stationary-ball jitter phantom decision (ORIGINAL ISSUE)
- **Evidence:** First log of the session showed `kickState=idle` throughout, but ImpactDetector printed a full `IMPACT DECISION` block with `noResult (ball never entered grid)` followed by `AUDIO-DIAG: impact REJECTED by kick gate (kickState=idle)`. Ball was sitting still inside the anchor rect. lostFrames went 1→2→3→4→5/5 over a few frames of YOLO misses, lost-frame trigger fired, decision constructed, audio gate downstream rejected it.
- **Analysis:** ImpactDetector's `minVelocityMagnitudeSq = 0.000009` (≈vMag 0.003 in normalised coords, ≈1–3 pixels at 720p) is low enough that sub-pixel YOLO bbox wobble on a stationary ball trips entry into `tracking` phase. Once in tracking, the lost-frame trigger fires whenever ball is missed for 5 consecutive frames — which happens routinely for a stationary ball because YOLO doesn't always detect every frame. Path A's disabling of trigger A (velocity-drop) closes mechanism A but doesn't help here — this is mechanism B (lost-frame). The audio kick gate at the screen catches the rejection, so the user hears nothing, but the IMPACT DECISION block still pollutes the log and ImpactDetector wastes work.
- **Discussion of approaches (rejected band-aids):**
  - *Raise `minVelocityMagnitudeSq` threshold* — every value is wrong for some real kick (slow grounded kicks fall below; jitter sometimes overlaps fast kicks).
  - *Gate `processFrame` on `KickDetector.state` (ADR-061 territory)* — already tried, broke 3/5 grounded kicks because KickDetector's jerk threshold misses slow shots. Reverted.
  - *Geometric "departure from anchor rectangle" gate* — discussed, but user pushed back on architectural redesign and asked for the simplest reuse of an existing variable.
- **Proper fix (Piece A, applied 2026-04-29):** The codebase already gates audio, trails, session lock, anchor filter on `KickDetector.state`. The IMPACT DECISION block is the one place where this gate is applied late (downstream at audio) instead of at the source. Move it to the source: pass `kickState` into `ImpactDetector.processFrame`, gate at the top of `_makeDecision`. See ADR-086.
- **Status:** ✅ APPLIED. Field-validated for the exact scenario in the original log (same idle-jitter pattern produces `DIAG-IMPACT [PHANTOM SUPPRESSED]` line and zero IMPACT DECISION blocks). 177/177 tests passing.

#### Scenario 2 — Bounce-back (already closed, formally re-confirmed this session)
- **Evidence:** User asked whether bounce-back outside the rect was still an open issue. Code-trace review (2026-04-29) confirmed it is fully handled by Phase 3 — at the moment a real IMPACT DECISION fires (accept branch `:1091` or reject branch `:1134`), `_anchorFilterActive = true` is re-armed. The bounce-back ball lands outside the rect by definition; its YOLO detections are dropped at `_toDetections` before ByteTrack ever sees them; BallIdentifier has no candidates to lock onto (lock was released same line); ImpactDetector is never invoked.
- **Analysis:** Bounce-back inside the rect is also handled — KickDetector is in refractory after `onKickComplete`; can't re-confirm immediately; if ball settles before refractory expires, `isStatic` keeps it from re-confirming.
- **Memory updates done:** `issueLog.md` ISSUE-021 flipped from "Identified, not yet fixed" → "✅ FIXED BY PHASE 3"; `progress.md` Known Issues entries struck through with resolution pointers; `CLAUDE.md` issue table row updated to "🟢 MITIGATED BY PHASE 3 (2026-04-22)".
- **Status:** ✅ FORMALLY CLOSED on 2026-04-29.

#### Scenario 3 — Player nudges ball inside rectangle (idle → confirming → idle flicker)
- **Evidence:** Hypothetical scenario raised by the user — player nudges the ball to position it within the rect; KickDetector trips on the nudge motion (hits `confirming`), nudge ends, ball settles, KickDetector returns to `idle`.
- **Analysis:** Phase 3's idle-edge recovery (lines 1013–1022) re-arms the filter, releases the session lock, cancels the safety timer. But it does NOT call `_impactDetector.forceReset()` — so ImpactDetector keeps its leftover `tracking` phase state (`trackFrames`, `peakVelocitySq`, `_trackingStartTime`). The `maxTrackingDuration = 3 s` safety net then resets ImpactDetector silently 3 s later (no decision fires, just `_reset()` per code path) so the leftover state self-heals. Lost-frame trigger doesn't fire because the ball is detected continuously (inside rect, filter ON allows it through). Edge-exit trigger doesn't fire because the ball is centred in the rect, far from frame edges.
- **Conclusion:** With Piece A applied, no phantom decision can fire in this scenario via any current trigger. The leftover ImpactDetector state is wasted work for 3 s but is not harmful.
- **Proposed enhancement (Piece B, NOT applied):** Add `_impactDetector.forceReset()` to the idle-edge recovery block at line ~1019. Symmetric with the decision-fired reject branch (which does call `forceReset()` at line 1126). Cleans state at the false-alarm boundary. Purely a tidiness/state-hygiene improvement; user-facing behaviour identical.
- **Status:** Piece B designed, NOT applied. User said "let's do A first only for now."

#### Scenario 4 — "Ball in position" audio fired twice in 4 seconds (cadence is supposed to be 10 s)
- **Evidence:** User log of 2026-04-29 showed two `AUDIO-DIAG: ball_in_position fired` lines at 15:15:50.766 and 15:15:54.869 — only 4.1 s apart. Between them, the ball physically drifted from (0.358, 0.729) → (0.363, 0.737) over ~60 frames, and there were 1–2 single-frame YOLO misses (`passed=0` lines).
- **Analysis (root cause traced in `live_object_detection_screen.dart` lines 958–972):** The trigger code is:
  ```
  final inPosition = ballDetected && _anchorRectNorm!.contains(ball.center) && ball.isStatic;
  if (inPosition) { ... fire if 10 s elapsed since last; ... }
  else { _lastBallInPositionAudio = null; }   ← BUG
  ```
  The `else` branch resets the cadence timestamp to `null` on **any** frame where `inPosition` is false — including transient causes (single-frame YOLO miss, brief drift, brief `isStatic=false`). One missed YOLO frame anywhere in the 10-second window resets the cooldown. Since YOLO routinely misses single frames, the 10 s cadence almost never holds in practice.
- **Initial proposed fix (rejected):** Just delete the `else` branch. User correctly pushed back: "the whole point of having else block was to cover the scenario when the ball is kicked and the player again positions the ball — it should call out 'ball in position' again, and the new timer should start."
- **Revised fix (designed 2026-04-29, NOT applied):** Two changes:
  1. Delete the `else` branch (stops brief flickers from resetting).
  2. Add `_lastBallInPositionAudio = null;` inside the existing OFF-trigger block (line 1006), where `_anchorFilterActive` flips false because KickDetector reached `confirming` or `active` — this is the unique signature of a real kick attempt. Brief YOLO misses don't trip the filter, so they leave the cadence alone; real kicks reset it; player replaces ball post-kick → fires immediately.
- **Status:** Bug confirmed via code trace and user log. Fix designed (2 lines net change). NOT YET APPLIED. User to give go-ahead.

#### Scenario 5 — Real kick at zone 6 EATEN by Piece A (race condition)
- **Evidence:** Field test log of 2026-04-29 (immediately after Piece A applied). Ball physically traversed 1 → 6, passing through grid. Log shows:
  - Ball started static inside rect at (0.386, 0.730), then accelerated upward
  - `DIAG-ANCHOR-FILTER: OFF (kick state=confirming)` — kick confirmed, filter dropped
  - ByteTrack: `kick=confirming` for many frames
  - Mahalanobis rescue successfully matched the fast-flying detection at (0.410, 0.648)
  - `lastDirectZone` progressed: null → null → 1 → 1 → 1 → **6**
  - One frame later: `DIAG-BALLID: session lock DEACTIVATED` and `DIAG-ANCHOR-FILTER: ON (kick returned to idle — false-alarm recovery)`
  - Same frame: `DIAG-IMPACT [MISSING] lostFrames=5/5 lastDirectZone=6` then `DIAG-IMPACT [PHANTOM SUPPRESSED] trigger fired with kickState=idle`
  - **The real HIT zone 6 was suppressed.**
- **Analysis (root cause):** Three safeguards collided on a single real-kick frame:
  1. **KickDetector** internally transitioned `confirming` → `idle` one frame too early (probably a timeout / low-velocity-fallback / "ball missing too long even with `isImpactTracking=true`"; exact KickDetector trigger not yet identified — separate investigation owed).
  2. **Phase 3 idle-edge recovery** (lines 1013–1022) saw `kickState=idle` on the next frame, re-armed the filter, deactivated the session lock — interpreting the transition as a false alarm.
  3. **Piece A** in the same frame saw `kickState=idle` at decision-firing time and suppressed the lost-frame decision.
  Each safeguard is correct in isolation. Together they ate a real kick.
- **Fundamental design flaw in Piece A:** The gate reads **instantaneous** `kickState` at decision-firing time. The "real kick happened" property is **historical** (a kick reached confirming/active at *some* point during the current tracking session), not instantaneous. Reading instantaneous state means every flicker that aligns with a decision-firing frame eats the decision.
- **Proposed fix (Piece A widening, NOT applied):** Track inside `ImpactDetector` a single boolean `_kickConfirmedDuringTracking`. Set it whenever observed `kickState != KickState.idle`. Clear it on `_reset()`. Gate becomes:
  ```
  Suppress decision IF kickState IS idle now AND was idle the entire tracking session.
  ```
  Allows decisions when a kick was confirmed at any point, regardless of current state. Handles all four scenarios correctly: pure jitter (suppressed), normal real kick (allowed), kick where KickDetector flips early (allowed — THE FIX), nudge case (allowed but no trigger fires anyway, max-duration self-resets).
- **Companion bug (separate, not yet investigated):** KickDetector itself dropped to idle when `isImpactTracking=true`. Existing test "ball loss during confirming stays confirming while impact is tracking" suggests this shouldn't happen. Possible causes: a different timeout (max-confirming-duration, low-velocity-fallback, etc.), or a brief `isImpactTracking=false` window. Worth investigating as its own bug.
- **Status:** Bug confirmed via direct field log. Piece A widening designed. NOT YET APPLIED. KickDetector internal trigger not yet investigated.

### Path A — what was diagnosed (with direct evidence) — kept from prior session

**Two firing mechanisms, both visible in logs:**

| Mechanism | Trigger path | Root cause |
|---|---|---|
| A — velocity-drop | `_onBallDetected` → velMagSq < 0.4 × peak (line 271–277) | Peak set in frames 2–3 (ball accelerating from rest); apparent screen velocity then naturally drops below 40% mid-flight due to perspective foreshortening + Kalman smoothing. Trigger fires while ball has only just entered zone 1. |
| B — lost-frame via state flip | `_onBallMissing` → 5 missed frames (line 297–299) | When ByteTrack's match fails for the locked track in either pass (fast motion, Mahalanobis below threshold), `track.state` flips to `lost`. Screen passes `ballDetected=false` to ImpactDetector. Screen still computes `directZone` from Kalman-predicted position — but `_onBallMissing` was never updating `_lastDirectZone`. Zone progression (1→6→7) was silently dropped. Trigger fires at lost-frame threshold with stale zone (1). |

**Side-channel facts established this session:**
- Audio is in lockstep with decision (2 ms lag, measured directly on every kick). Audio pipeline is NOT the bug.
- 5 zone signals exist (`directZone`, `wallPredictedZone`, `extrapolation.zone`, `lastDirectZone`, `lastDepthVerifiedZone`). Decision logic at `_makeDecision()` consults only `_lastDirectZone` (and edge filter). The other 4 are stored but never read at decision time.
- `lastDepthVerifiedZone` is structurally null in our setup — the depth thresholds (0.7–1.3) don't match behind-kicker geometry where ball-at-wall depthRatio ≈ 0.3–0.45.
- ByteTrack state machine: `tracked` → `lost` happens when track unmatched in pass 1 AND pass 2 (line 674 of `bytetrack_tracker.dart`); `lost` → `tracked` on rescue (line 715); `lost` → `removed` on `consecutiveLostFrames > maxLost` (lines 728/736). Mahalanobis rescue lines in the log mean rescue *succeeded* — state stayed/returned to `tracked`. Missing rescue lines in [MISSING] sequences mean rescue *did not* match.
- ADR-061 attempted gating ImpactDetector behind KickDetector and was reverted (broke 3/5 grounded kicks). Any future "ImpactDetector should be asleep during waiting" work must coordinate with this prior failure.

### What was applied (Path A)

**Three diagnostic additions (still in place):**
1. **`AUDIO-DIAG`** prints at every audio-fire site (`audio_service.dart:playImpactResult` for hit/miss/noResult; `live_object_detection_screen.dart` reject-branch). Each timestamped HH:MM:SS.mmm.
2. **`IMPACT DECISION` block timestamp** appended to the existing block in `impact_detector.dart:_makeDecision()`.
3. **`DIAG-IMPACT [DETECTED]` / `[MISSING ]`** per-frame traces inside `_onBallDetected` and `_onBallMissing` showing the trigger arithmetic (velRatio for A, lostFrames for B), zone state, and bbox state. These are the diagnostic prints that decisively distinguished mechanisms A and B.

**Two atomic code fixes (Path A):**

- **Change 1 + Option A extension** (`_onBallMissing` zone tracking) — `processFrame` now passes `directZone`, `rawPosition`, and `bboxArea` to `_onBallMissing`. Inside, all three update their stored counterparts (`_lastDirectZone`, `_lastRawPosition`, `_lastBboxArea`) with the same null-safety rule used by `_onBallDetected`. Closes the silent zone-drop bug for mechanism B and keeps every variable in the IMPACT DECISION block fresh (preserving them as inputs for future hit-detection design work — the user pushed back on my initial "leave them stale" recommendation, correctly so).
- **Change 2** (velocity-drop trigger disabled) — original block at lines 271–277 commented out with detailed inline rationale. Decisions now fire via: edge-exit (in `_makeDecision`), lost-frame trigger (in `_onBallMissing`, 5 missed frames), or `maxTrackingDuration` safety net (3 s). Original code preserved for reversibility if validation reveals we still need an impact-trigger.

**One CLAUDE.md note:**
- New "Pending Code-Health Work" section ahead of "What Is Out of Scope" describing Path B (cleanup of `_onBallDetected`/`_onBallMissing` two-branch split) as deferred future work. Lists dead signals, references the prior failed attempt (ADR-061), and locks in the validation rule that any future ImpactDetector refactor must capture pre/post traces using the same diagnostic harness.

### Field validation (iPhone 12, 2026-04-28)

**One state-flip kick captured post-fix** (12:16:16):
- Ball physically traversed zones 1 → 6 → 7, hit zone 7. Trace shows F4 [DETECTED] `_lastDirectZone=1` → F5–F8 [MISSING] sequence updating `_lastDirectZone` through 6 → 7 → 7 → 7 (null doesn't overwrite) → F9 lost-frame trigger fires.
- `IMPACT DECISION` block: `lastDirectZone: 7`. `AUDIO-DIAG: impact result=hit zone=7 (12:16:16.725)`. **Pre-fix this exact scenario announced zone 1; post-fix it announced zone 7.** Mechanism B confirmed fixed.

**Velocity-drop scenario validation: still pending.** User attempted but captured an idle-ball-jitter trace (kick=idle throughout) instead of a real flat kick. The idle-ball log incidentally demonstrated Change 2 is at least passively working (no decision fires under noise that would have fired pre-fix), but a real flat-kick log is still needed to validate mechanism A is fixed in flight.

### Open follow-up (latent, not blocking)

- **ImpactDetector enters `tracking` phase on idle-ball detection-noise jitter** — entry threshold `minVelocityMagnitudeSq = 0.000009` is sensitive enough to be crossed by sub-pixel detection wobble on a stationary ball. Under old code this caused phantom decisions during waiting (silently rejected by the result gate). Under Path A no decision fires (Change 2 disabled the relevant trigger), so it's wasted work + log noise rather than wrong audio. The user correctly observed this is a Phase 3 design intent gap — anchor filter goes to sleep on the input side during waiting (`_anchorFilterActive=true`), but ImpactDetector itself never received a parallel "sleep during waiting" gate. Folded into the Path B notes in `CLAUDE.md`.

## What Is Fully Working
- YOLO11n live camera detection on iOS (iPhone 12). Android (Realme 9 Pro+) parity verified through 2026-04-16; Phase 1 / Phase 5 / Path A changes not yet re-verified on Android.
- ByteTrack multi-object tracker with 8-state Kalman filter
- BallIdentifier with 3-priority identification, session lock, and single-track `setReferenceTrack(TrackedObject)` API driven by player tap
- Ball trail overlay with kick-state-based visibility (dots only during kicks)
- "Ball lost" badge after 3 consecutive missed frames
- 4-corner calibration with DLT homography transform
- 9-zone target mapping via TargetZoneMapper
- ImpactDetector (Phase 3 state machine) with directZone decision — **now correctly tracks zone progression through state-flip frames after Path A Change 1 + Option A extension (2026-04-28)**
- KickDetector (4-state gate: idle/confirming/active/refractory)
- Audio feedback for impact results (zone callouts + miss buzzer)
- DiagnosticLogger CSV export with Share Log
- Pre-ByteTrack AR > 1.8 filter (rejects torso/limb false positives)
- Session lock prevents re-acquisition during active kicks
- Protected track extends ByteTrack survival for locked ball
- Landscape orientation lock with proper restore
- Camera permission handling
- Rotate-to-landscape overlay with accelerometer
- Phase 1 tap-to-lock reference capture, Phase 2 magenta anchor rectangle, Phase 3 spatial filter (with idle-edge recovery + safety timeout + resting-ball trail dot), Phase 5 audio prompts (tap-prompt + "Ball in position", isStatic-gated)
- Back button works in every screen state (calibration, awaiting reference capture, live pipeline)
- **(NEW 2026-04-28) Decision-trace diagnostic harness** — `AUDIO-DIAG`, `DIAG-IMPACT [DETECTED]`/[MISSING ]`, timestamped IMPACT DECISION block. Lets us see audio-decision sync, distinguish trigger paths per frame, and validate any future ImpactDetector change empirically against pre/post log captures.

## What Is Partially Done / In Progress
- **Piece A — kickState idle gate at `_makeDecision`** (applied 2026-04-29, ADR-086). Original idle-jitter scenario field-validated. **BUT a real kick was eaten** in the same session (ISSUE-035) due to a race with KickDetector's internal transition + Phase 3 idle-edge recovery. Gate is too narrow — must be widened to track "kickConfirmedDuringTracking" flag. Widening designed, NOT applied. Considering whether to revert Piece A first or apply the widening as a follow-up.
- **Audio cadence "ball in position" double-fire bug (ISSUE-036)** — root-caused 2026-04-29 to the `else` branch in `live_object_detection_screen.dart` lines 970–972 resetting `_lastBallInPositionAudio = null` on transient `inPosition=false` flickers. 2-line fix designed (delete else + add reset on filter OFF). NOT applied.
- **KickDetector internal transition investigation** — owed. Real-kick log showed KickDetector transitioned confirming → idle while `_impactDetector.phase == DetectionPhase.tracking`. Existing test asserts this shouldn't happen. Need to read KickDetector source and identify the actual trigger.
- **ImpactDetector accuracy fix (Path A applied 2026-04-28)** — mechanism B (state-flip → lost-frame trigger with stale zone) field-validated working. Mechanism A (velocity-drop trigger disabled) validation pending — needs one real flat-kick log where all frames stay [DETECTED] and the trace shows the trigger no longer fires.
- **Anchor Rectangle Phase 5** — code complete, iOS-verified. Android verification pending.
- **Bbox area ratio check on Mahalanobis rescue** — Fixed (2.0/0.3 threshold, last-measured-area). 5/5 kicks tracked across 3 monitor-test runs (2026-04-16).
- **Session lock safety timeout** — Phase 3's 2 s safety timer + idle-edge `else if` cover most stuck-lock scenarios; the residual case (genuine kick that never fires a decision) may already be mitigated by Path A — needs re-verification.
- **directZone accuracy** — was the symptom of the bug fixed by Path A. Pre-fix it was "stuck at zone 1"; post-fix the field-verified case correctly announced zone 7. Validation across more zones (4, 5, 9) still owed.
- **False positive trail dots during active kicks** — still open, pre-existing issue.
- **ImpactDetector enters tracking on idle-ball jitter** — latent gap from Phase 3 incomplete "asleep during waiting" implementation; documented in CLAUDE.md Path B notes; not currently producing wrong audio.

## Known Gaps
- iOS `NSCameraUsageDescription` has placeholder text ("your usage description here") — must update before any external build
- `tennis-ball` priority 2 in class filter (harmless diagnostic concession)
- Free Apple Dev cert expires every 7 days — re-run `flutter run` to re-sign
- Phantom impact decisions during kick=idle (log noise only, not announced) — partially mitigated by Path A Change 2 (no longer fires) but ImpactDetector still enters tracking phase wastefully
- Share Log button is dev-only; not intended to ship to production
- Mid-session Re-calibrate does NOT call `DiagnosticLogger.instance.stop()` (only `dispose` does), so Share Log button stays visible during a mid-session Re-calibrate → corner taps could land under it. Niche and dev-only; not fixing
- 4 of 5 zone signals (`_lastWallPredictedZone`, `_bestExtrapolation`, `_lastDepthVerifiedZone`, plus `_velocityHistory` accumulator) computed every frame, never consulted at decision time — documented in CLAUDE.md Path B notes for future cleanup

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
1. **Decide on Piece A path forward (URGENT — real kicks currently being eaten).** Options: (a) widen the gate to track historical "kickConfirmedDuringTracking" flag (1 boolean field + 2 lines in `impact_detector.dart`); (b) revert Piece A entirely until widening is ready; (c) investigate KickDetector's premature idle transition first and fix that instead. Recommendation: (a) + (c) — widen Piece A to be robust, separately fix KickDetector. Awaiting user decision.
2. **Apply audio cadence fix (ISSUE-036).** Delete the buggy `else` branch (lines 970–972) AND add `_lastBallInPositionAudio = null;` inside the filter OFF block at line 1006. ~2 lines net. Designed but not applied.
3. **Investigate KickDetector premature `confirming → idle` transition** while `isImpactTracking=true`. Read `lib/services/kick_detector.dart` for the actual trigger. Likely candidates: a timeout, low-velocity-fallback, or `isImpactTracking` flickering.
4. **Capture a real flat-kick log to validate Path A Change 2 (velocity-drop trigger disabled).** A center-zone (4 or 5) shot where all frames stay [DETECTED] — `kick=confirming` → `kick=active`, no Mahalanobis rescue gaps. Expected trace: velRatio crosses below 0.4 mid-flight (around F5–F6) but trigger does NOT fire; ball continues to be tracked through real zones; decision eventually fires via lost-frame or edge-exit with the correct impact zone. Without this, mechanism A is only theoretically resolved.
2. **Capture additional zone-variety kicks** — at least one each to zones 2/3 (right-side low) and 4/5/6 (middle row). Expected: `lastDirectZone` at decision time matches visually observed impact. This builds confidence that the fix generalizes beyond the one verified case (zone 7 from 1→6→7 trajectory).
3. **Android (Realme 9 Pro+) parity verification** — run all phases (1/2/3/5) plus Path A end-to-end; specifically watch that `_toDetections` rotation correction interacts cleanly with the unchanged anchor filter, and that the new diagnostic prints fire at the same state transitions on Android as on iOS.
4. **Plan Path B (deferred refactor) as a future phase** — see `CLAUDE.md` "Pending Code-Health Work" section. Either restructure the two-branch split into a single unconditional state-update path, or at minimum delete the dead signals (`_lastWallPredictedZone`, `_bestExtrapolation`, `_lastDepthVerifiedZone`, `_velocityHistory`) and the services that feed them (`wall_plane_predictor.dart`, `trajectory_extrapolator.dart`). Validation rule (capture pre/post traces with the existing diag harness) is locked in.
5. **Optional Path A polish (non-blocking):** the ImpactDetector idle-tracking issue is wasted work but not currently producing wrong audio; bundle the fix with Path B rather than treating as a separate change.

### Prior context — Anchor Rectangle Phase 5 (2026-04-23 → 2026-04-24)
Audio announcements shipped in four atomic commits, all iOS-verified on iPhone 12. Scope reduced from three prompts to two during design (the "Ball far, bring closer" nudge was deferred pending field evidence it's needed). Two flow-gap bugs surfaced and were fixed in the same session (ISSUE-032 / ADR-081 — State 3→2 nudge restart; ISSUE-033 / ADR-082 — `isStatic` gate on "Ball in position"). User tuned cadence to 10 s and shortened "Ball in position" phrase. Inline trigger via timestamp-in-loop pattern (ADR-080), no Timers added.

### Prior context — Anchor Rectangle Phase 3 polish (2026-04-22)
Three small additive refinements landed and iOS-verified. (1) `else if` idle-edge recovery in the OFF-trigger block — re-arms filter on false-alarm kick flickers without waiting the full 2 s safety window. (2) Resting-ball orange dot re-enabled — `TrailOverlay` idle-suppression gate relaxed to render trail when `_anchorFilterActive && ball ∈ rect`. (3) `DIAG-ANCHOR-FILTER` log enriched — emits every frame the filter is active (not only on drops), labels passed/dropped, includes bbox size.

### Prior context (Phase 3 main, Phase 2, Phase 1)
- **Phase 3 (2026-04-22):** Spatial filter drops raw YOLO detections whose bbox center is outside `_anchorRectNorm` before ByteTrack sees them. Confirmed silently dropping target-circle FPs (ISSUE-022, the #1 field-test blocker pre-Phase-3) on every frame at fixed positions. Six iOS smoke tests passed.
- **Phase 2 (2026-04-20):** magenta dashed anchor rectangle drawn at lock, sized 3× bbox width × 1.5× bbox height, frozen, screen-axis-aligned. Visual only. ADR-076.
- **Phase 1 (2026-04-19):** iOS-verified. Replaced auto-pick-largest heuristic with explicit player tap-to-select (two-step UX: tap red bbox → turns green → Confirm commits). All 12 design decisions resolved (ADR-073). Two back-button z-order bugs fixed (ADR-074, ISSUE-031). Audio nudge stub with per-episode counter + timestamp (ADR-075).

### Failed Approach (2026-04-13, earlier session) — DO NOT REPEAT
2-layer filter (DetectionFilter + TrackQualityGate + Mahalanobis rescue validation). Init delay broke BallIdentifier re-acquisition. Player head (ar:0.9) unfilterable with geometry. Must implement ONE filter at a time.

### Failed Approach (2026-04-08, earlier session) — DO NOT REPEAT
Kick-state gate on ImpactDetector (gated processFrame behind KickDetector state). Broke 3/5 grounded kicks because KickDetector's jerk threshold was too aggressive for low-velocity shots. Reverted. See ADR-061. Any future "ImpactDetector should be asleep during waiting" work must coordinate with this — the anchor filter state (`_anchorFilterActive`) may be a more robust gate than KickDetector state alone.
