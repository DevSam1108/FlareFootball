# Issue Log

Recurring issues, root causes, and verified solutions. Check here before researching online.

---

## ISSUE-038: ImpactDetector Trigger Gap — Decisions Only Fire on Ball-Lost or Ball-At-Edge, Never Positively at Impact

**Date:** 2026-04-29 (architectural finding from late-session analysis)
**Platform:** N/A — design-level issue affecting all platforms
**Symptom:** In scenarios where the ball is detected continuously through impact + bounce-back + rolling (no missed frames), the impact decision either fires very late or with the wrong zone announced. Two field logs from 2026-04-29 demonstrate concrete cases:
- **Zone-6 kick (ISSUE-035 log)** — KickDetector dropped to idle one frame too early; lost-frame trigger eventually fired with kickState=idle → suppressed by Piece A.
- **Zone-8 kick (FP-stuck-tracker log)** — target-fabric circles fed fake `[DETECTED]` frames for ~50 frames after the real ball was gone; lost-frame trigger fired ~1.6 s late, kickState=refractory by then, audio gate rejected.

**Root Cause:** `ImpactDetector._makeDecision()` is called from only TWO paths today (after Path A disabled the velocity-drop trigger in ADR-083):
1. **Lost-frame trigger** in `_onBallMissing` — fires when `_lostFrameCount >= 5`.
2. **Edge-exit** — checked INSIDE `_makeDecision` after another trigger has already fired.

`maxTrackingDuration` (3 s) calls `_reset()` instead of `_makeDecision()`, so it doesn't actually fire a decision — it silently abandons the tracking session.

There is **no positive trigger** for "the ball reached its target and came to rest." All current triggers are negative (something must STOP — ball lost, ball off-screen). If the ball stays in `[DETECTED]` state continuously, the system has no way to decide.

**Why physics usually saves the system:**
- High-velocity kicks: ball is at smallest in-frame size near impact + motion blur → YOLO misses ~1–3 frames → if 5 align, lost-frame fires at impact.
- Ball flies past wall: leaves frame → guaranteed missed frames.

**Where the gap matters (where physics doesn't save):**
- Slow grounded kicks (no motion blur, ball stays detected, rolls back on ground).
- FP-stuck-tracker scenarios (target-fabric circles, cones, banner artefacts feed fake `[DETECTED]` frames after real ball is gone).
- Very high-quality detection / good lighting / large ball.

**Wrong-zone consequence:** When the lost-frame trigger eventually fires, `_lastDirectZone` is whatever zone the ball was last seen in. Path A (ADR-084) keeps `_lastDirectZone` fresh through `[MISSING]` frames, so during bounce-back, as the ball traverses zones 8 → 7 → 4 → 1 on its way down, `_lastDirectZone` overwrites with each new zone. By the time the trigger fires, the value is whatever the ball was last in before exiting the grid — typically a bottom-row zone (1, 2, or 3), not the impact zone (which was 8 at the actual physics moment).

**Proposed fix (NOT applied):** Add a **positive trigger** to `ImpactDetector` in `_onBallDetected`:
```
if (directZone != null && ball.isStatic && trackFrames > minStaticFrames) {
  _makeDecision();
}
```
- Fires at the actual impact moment, when the ball has come to rest in a grid zone.
- `_lastDirectZone` at that moment is still the impact zone (no bounce-back overwrite yet).
- Decision lands while KickDetector is still in `confirming/active` — gate accepts, audio plays, zone highlights.
- Tunable: `minStaticFrames` should be ~3–5 frames (~100–170 ms at 30 fps) — long enough to confirm staticness, short enough to fire before bounce-back.

**Status:** 🟠 OPEN — architectural fix designed, not applied. User has not yet asked for implementation. Discussion only.

**Related:**
- ADR-083 (velocity-drop trigger disabled — was originally the positive trigger for impact, now needs replacement).
- ADR-085 (Path B refactor deferred — could naturally include the positive trigger).
- ISSUE-035 (Piece A eats real kicks — symptom of the same trigger gap, where decision lands too late).
- ISSUE-037 (foot-locked-as-ball cascade — same trigger gap creates 60-frame stuck states).

---

## ISSUE-037: Foot/Non-Ball Object Locked as Ball Triggers Full False-Kick Cascade

**Date:** 2026-04-29
**Platform:** iOS (iPhone 12) — field test
**Symptom:** Player walked toward the kick area without kicking. App falsely detected a "kick", got stuck in tracking phase for 60+ frames, fired `ball_in_position` audio for what was actually a foot/shoe, ran the safety-timeout cascade, and ended in dual-class detection (`Soccer ball` + `tennis-ball` at same coordinates). Full log shows BallIdentifier re-acquired `trackId=9` with `bbox=(0.049×0.068)` and `ar:0.7` at (0.472, 0.752) via `reason=nearest_non_static`. The "ball" then moved horizontally x=0.402 → 0.328 over ~12 frames, growing in bbox area (0.0021 → 0.0034) — geometrically a leg/foot stepping toward the camera. KickDetector confirmed and went `active`. ImpactDetector entered tracking. `directZone=null` for all 75 frames (object never entered grid).

**Root Cause:** Three compounding issues:

1. **BallIdentifier's `nearest_non_static` re-acquisition has no shape filter for elongated-vertical objects.** Existing AR filter only rejects `AR > 1.8` (torso). Objects with `AR < 0.6` (foot, shoe) and `AR ≈ 0.9` (player head — see ISSUE-028) pass through. The "nearest_non_static" criterion combined with no shape gate means whatever is moving and closest to the previous lock position becomes the new lock — foot/leg motion qualifies trivially.

2. **Once locked, KickDetector trips on the foot's horizontal motion.** No shape check downstream. Foot's lateral velocity easily crosses the jerk threshold and sustains energy long enough to reach `active`.

3. **ImpactDetector cannot escape its tracking phase** because `directZone=null` (foot/leg is below the grid in image coordinates, near y=0.72), edge-exit can't fire (object centered, far from edges), and `[DETECTED]` keeps refreshing as the foot is continuously visible. Trapped for 60 frames until `maxActiveFrames` safety-net pushes KickDetector to refractory. (Same as ISSUE-038's symptom.)

**Cone confounder (separate but related):** User confirmed a physical cone sits at the kick spot. Field log shows it being dual-classed: `[Soccer ball@(0.331,0.723) size=(0.047x0.059) conf=0.99, tennis-ball@(0.331,0.723) size=(0.048x0.058) conf=0.80]`. The cone is the **terminal state** of the cascade (visible at the end), not the trigger (cones don't walk). It contributes during waiting state but didn't cause the cascade itself — the foot did.

**Recommended actions discussed (none applied):**
1. **Tighten BallIdentifier shape gate** — reject `ar < 0.6 || ar > 1.5` during `nearest_non_static` re-acquisition. Closes both foot/shoe (ar:0.7) and torso (ar:2.4+). Player head (ar:0.9) still escapes — same root issue as ISSUE-028.
2. **Physically remove the cone** from inside the rect during testing — eliminates one decoy class.
3. **Multi-object cleanup nudge** (ADR-087) — addresses the cone but not the foot. Currently disabled via `if (false)` after user concern about kick-drops.

**Status:** 🟠 OPEN. NOT FIXED. Tighten-the-shape-gate fix is the highest-priority lever; closes the largest class of false locks.

**Related:**
- ISSUE-028 (player head ar:0.9 same root) — REVERTED prior attempt because init-delay broke re-acquisition. Lesson: any new filter must pass ALL tracks through to BallIdentifier; can tag/score but must not remove from candidate pool.
- ISSUE-038 (ImpactDetector trigger gap) — explains why a false lock causes a 60-frame stuck state instead of self-resolving quickly.
- ADR-087 (multi-object nudge added then disabled) — partial mitigation for the cone aspect.

---

## ISSUE-036: "Ball in Position" Audio Fires Twice Within Seconds (10 s Cadence Broken by Single-Frame YOLO Misses)

**Date:** 2026-04-29
**Platform:** iOS (iPhone 12) — field test
**Symptom:** Player heard "Ball in position" twice back-to-back, with the second announcement starting before the first finished or just after. The configured cadence was 10 s minimum between announcements (ADR-080 / ADR-082), so this should not have happened. User log captured timestamps at 15:15:50.766 and 15:15:54.869 — only 4.1 s apart.

**Root Cause:** The trigger code in `lib/screens/live_object_detection/live_object_detection_screen.dart` (lines 958–972):
```dart
final inPosition = ballDetected && _anchorRectNorm!.contains(ball.center) && ball.isStatic;
if (inPosition) {
  if (_lastBallInPositionAudio == null || now.difference(_lastBallInPositionAudio!) >= 10s) {
    _audioService.playBallInPosition();
    _lastBallInPositionAudio = now;
  }
} else {
  _lastBallInPositionAudio = null;   // ← BUG
}
```
The `else` branch resets the cadence timestamp to `null` on **any** frame where `inPosition` is false. That includes harmless transients:
- Single-frame YOLO miss (`passed=0` in the DIAG-ANCHOR-FILTER log)
- Brief sub-pixel drift causing momentary `isStatic=false`
- Ball briefly outside rect during physical drift

In the field log: between the two firings the ball physically drifted (0.358, 0.729) → (0.363, 0.737) over ~60 frames, with 1–2 single-frame YOLO misses visible. Each YOLO miss reset the cadence to `null`. Next time `inPosition` was true, the null check triggered immediate firing.

**Originally intended behaviour (per user, confirmed during fix discussion):** the `else` was placed there to fire "Ball in position" *immediately* after a real kick (ball replaced, fresh announcement). But it was applied too broadly — to every false-frame instead of just to "real kick happened" events.

**Fix designed (NOT YET APPLIED):**
1. Delete the `else` branch (3 lines).
2. Add `_lastBallInPositionAudio = null;` inside the existing OFF-trigger block at line ~1006, where `_anchorFilterActive` flips false because `KickDetector.state == confirming || isKickActive`. This is the unique signature of a real kick attempt — brief YOLO misses don't trip the filter.

After fix:
- Real kick + ball replaced → fires immediately ✅
- Brief YOLO miss while in position → cadence persists ✅
- Sub-pixel drift → cadence persists ✅
- False-alarm KickDetector flicker (rare) → fires once on next in-position frame, harmless

**Status:** Root cause confirmed via code trace + field log. Fix designed (~2 lines net change). NOT YET APPLIED. Awaiting user "go ahead."

**Related:** ADR-080 (timestamp-in-loop pattern), ADR-082 (`isStatic` gate), ISSUE-033 (related `isStatic` bug).

---

## ISSUE-035: Real Kick Suppressed by Piece A Phantom-Decision Gate (Race Condition with KickDetector + Phase 3 Idle-Edge Recovery)

**Date:** 2026-04-29
**Platform:** iOS (iPhone 12) — field test, immediately after Piece A applied
**Symptom:** Player kicked the ball; ball physically traversed zones 1 → 6 (passed through grid). No audio announcement fired. Log shows `DIAG-IMPACT [PHANTOM SUPPRESSED]` with `lastDirectZone=6` — Piece A suppressed a real HIT zone 6 decision.

**Field log timeline (single critical frame at the end of a real kick):**
- F-N: lostFrames=4/5, ByteTrack `kick=confirming`, `lastDirectZone=1`, ball flying upward
- F-N+1, all in same frame:
  1. `KickDetector.processFrame()` (line 980) — internally transitions `confirming` → `idle`
  2. Phase 3 idle-edge recovery (line 1015) sees `kickState=idle` → re-arms filter, deactivates session lock, prints `DIAG-ANCHOR-FILTER: ON (kick returned to idle — false-alarm recovery)`
  3. `ImpactDetector.processFrame()` (line 1050) called with `kickState=idle`
  4. `_onBallMissing` runs, `lostFrames` hits 5/5, `_lastDirectZone` updates to 6 (Path A keeps it fresh)
  5. `_makeDecision` called → Piece A gate sees `kickState=idle` → `[PHANTOM SUPPRESSED]`
  6. Real HIT zone 6 lost.

**Root Cause:** Two issues stacked:

1. **Piece A's gate is too narrow.** It checks `_currentKickState == KickState.idle` — the **instantaneous** state at decision-firing time. The "real kick happened" property is **historical** (a kick reached confirming/active at *some* point during the current tracking session), not instantaneous. Reading instantaneous state means every flicker that aligns with a decision-firing frame eats the decision.

2. **KickDetector dropped to idle prematurely while `isImpactTracking=true`.** The existing test "ball loss during confirming stays confirming while impact is tracking" asserts this shouldn't happen, but in the field log it did. The exact trigger inside KickDetector is not yet identified — likely candidates: max-confirming-duration timeout, low-velocity-fallback, or a momentary `isImpactTracking=false` window. Worth investigating as its own bug.

**Fix designed for Piece A (NOT applied):** Track inside `ImpactDetector` a single boolean `_kickConfirmedDuringTracking`. Set it whenever observed `kickState != KickState.idle`. Clear it in `_reset()`. Gate becomes:
```
Suppress decision IF kickState IS idle now AND was idle the entire tracking session.
```

This handles all four scenarios correctly:

| Scenario | kickState history | Flag | Decision |
|---|---|---|---|
| Pure idle jitter (original phantom) | idle, idle, idle... | false | suppressed ✅ |
| Normal real kick | idle → confirming → ... → confirming when fires | true | allowed ✅ |
| **This bug** (KickDetector flips to idle one frame early) | idle → confirming → ... → idle | true | **allowed ✅** (the fix) |
| Nudge case (briefly hits confirming) | idle → confirming briefly → idle | true; but no trigger fires (ball still in rect, no lost-frames) | reset by max-duration; no phantom |

**Companion bug to investigate (separate):** KickDetector premature transition. Even with Piece A widened, KickDetector dropping to idle during a real kick is wrong behaviour. Read `lib/services/kick_detector.dart` to find the actual trigger.

**Status:** Bug confirmed via direct field log. Piece A widening designed (1 boolean field + 2 line updates inside `impact_detector.dart`). NOT YET APPLIED. KickDetector internal transition not yet investigated. Awaiting user decision on path forward (widen Piece A vs. revert vs. investigate KickDetector first).

**Related:** ADR-086 (Piece A gate, the version being widened), ADR-061 (prior failed attempt to gate ImpactDetector behind KickDetector), ISSUE-034 (Path A — separate ImpactDetector accuracy bug).

---

## ISSUE-034: ImpactDetector Premature Firing — Two Mechanisms Producing "HIT zone 1" When Ball Hit Elsewhere

**Date:** 2026-04-22 first observed in field test; full root-cause diagnosis 2026-04-27 → 2026-04-28; Path A fix applied 2026-04-28. One state-flip scenario field-validated post-fix. Velocity-drop scenario validation still pending.
**Platform:** iOS (iPhone 12), monitor-video reproduction. Android (Realme 9 Pro+) untested post-fix.
**Symptom:** `IMPACT DECISION` block consistently announced `HIT zone 1` regardless of actual impact zone. Field test of 2026-04-22 (two consecutive lobbed kicks crossing 1→6→7) declared `HIT zone 1` both times. Re-tested 2026-04-27 (4 kicks across various trajectories) — every kick fired with `lastDirectZone=1` even when ball physically reached zones 7, 9, 2.

**Root Cause:** TWO distinct firing mechanisms, both reproducible in logs once `DIAG-IMPACT [DETECTED]` and `[MISSING ]` per-frame traces were added to `impact_detector.dart`:

1. **Mechanism A — velocity-drop trigger (`_onBallDetected` → `velMagSq < 0.4 × peak`, line 271–277).** Peak was set in frames 2–3 when ball was accelerating from rest (highest screen velocity in the entire kick). Apparent screen velocity then naturally decreased in mid-flight due to (a) perspective foreshortening as ball recedes from camera, (b) Kalman smoothing dampening transient spikes, (c) gravity at apex of lobbed kicks. By frames 5–6 the ratio crossed below 0.4 — trigger fired while `_lastDirectZone` was still 1 (the bottom-row entry zone, the only one the ball had reached).

2. **Mechanism B — state-flip → lost-frame trigger.** When ByteTrack's match failed for the locked track in BOTH pass 1 (high-conf IoU) AND pass 2 (low-conf / Mahalanobis) — which happens during fast motion when Kalman prediction diverges from actual detection — `track.state` flipped to `lost`. Screen passed `ballDetected=false` (= `ball.state != TrackState.tracked`) to ImpactDetector, routing the frame through `_onBallMissing`. **`_onBallMissing` only incremented `_lostFrameCount`; it never updated `_lastDirectZone`, `_lastRawPosition`, or `_lastBboxArea`.** The screen still computed `directZone` from the (Kalman-predicted) ball position every frame, BYTETRACK log lines clearly showed the ball passing through zones 6, 7 — but ImpactDetector ignored those updates. After 5 missed frames, lost-frame trigger fired with `_lastDirectZone=1` (frozen since the last `_onBallDetected` call).

**Critical false-trail eliminated during diagnosis:** initial hypothesis was that audio was lagging behind the decision (i.e., audio plays the wrong zone because it reads stale state by the time it dispatches). `AUDIO-DIAG` timestamps proved audio fires within 2 ms of the IMPACT DECISION block. Audio pipeline is correct — the bug is entirely in when and what the detector decides.

**Solution that worked (Path A — minimal additive fix):**
1. **Path A Change 1 + Option A extension:** `_onBallMissing` now accepts `directZone`, `rawPosition`, `bboxArea` and updates each `_last*` field with same null-safety rule as `_onBallDetected`. Closes mechanism B's silent zone-drop. User pushed back on initial proposal to update only `directZone`, correctly identifying that stale `rawPosition` and `bboxArea` would remove edge-exit detection and depth-ratio calculation from the design palette for future hit-detection iterations.
2. **Path A Change 2:** velocity-drop trigger at lines 271–277 disabled (commented out with inline rationale + field evidence). Decisions now fire only via edge-exit, lost-frame trigger, or `maxTrackingDuration` (3 s).

Original code preserved for reversibility. See ADR-083, ADR-084.

**Path B (deferred):** restructure of `_onBallDetected`/`_onBallMissing` two-branch split (an artifact of the pre-ByteTrack era when "missing" meant "ball gone"), OR minimum cleanup of dead signals (`_lastWallPredictedZone`, `_bestExtrapolation`, `_lastDepthVerifiedZone`, `_velocityHistory`). Documented in `CLAUDE.md` "Pending Code-Health Work" section. Locked-in validation rule: any future `ImpactDetector` refactor must capture pre/post traces using the diagnostic harness shipped 2026-04-28. See ADR-085.

**Verified (partial):** Mechanism B field-validated on iPhone 12 (2026-04-28, 12:16:16). Same physical scenario (1→6→7 trajectory, hit zone 7) that previously announced zone 1 now correctly announces zone 7 with `lastDirectZone=7`, `bestExtrapolation: zone 7`, `AUDIO-DIAG: impact result=hit zone=7`. Mechanism A validation pending — needs a flat-kick log where all frames stay [DETECTED] (no Mahalanobis rescue gaps). `flutter analyze` clean (99 infos, all `avoid_print` on intentional diagnostic lines), 175/175 tests passing.

**Related:** ADR-061 (a previous attempt to gate `ImpactDetector` behind `KickDetector` state was reverted because it broke 3/5 grounded kicks). Any future "ImpactDetector should be asleep during waiting" work must coordinate with this prior failure — `_anchorFilterActive` may be a more robust gate than `KickDetector` state alone.

---

## ISSUE-033: "Ball in Position" Audio Fires on a Ball Rolling Through the Anchor Rect Without Stopping

**Date:** 2026-04-24
**Platform:** iOS (iPhone 12) — reported from field test; fixed in same session.
**Symptom:** Player was gently pushing the ball back toward the kick position with their foot. The ball rolled *through* the anchor rectangle without stopping. The app announced "Ball in position" on the brief frames the ball's center was inside the rect, but by the time the audio finished playing (~1 s clip), the ball had already exited the rect on the other side. A non-looking player (using audio alone) would hear the announcement and kick, but the Phase 3 spatial filter would drop the detection because the ball is no longer in rect — kick unregistered, silent failure.

**Root Cause:** The Phase 5 Commit 2 trigger condition was purely geometric: `ballDetected && _anchorRectNorm!.contains(ball.center)`. No check for whether the ball is actually stationary. The instant the center crossed the rect boundary, the condition became true and the audio fired, regardless of velocity.

**Solution that worked:** Added `&& ball.isStatic` as a fourth clause to the existing `inPosition` conjunction in `onResult` (`lib/screens/live_object_detection/live_object_detection_screen.dart`). `isStatic` is ByteTrack's sliding-30-frame staticness flag — already computed, no new state or threshold tuning needed. Accepts ~1 s delay between ball settling and audio firing (the staticness window warming up), which is desirable: a ball that briefly sits still before continuing to roll also won't falsely trigger. 1 line of functional code. See ADR-082.

**Verified:** iOS-verified on iPhone 12 (2026-04-24) — rolling-ball-through-rect scenario produced no audio (ball never marked `isStatic`); genuinely-settled ball produced audio after ~1 s warm-up. `flutter analyze` clean, 175/175 tests passing.

---

## ISSUE-032: Tap-Prompt Audio Stuck Silent After State 3→State 2 Transition (Tap + Flicker Scenario)

**Date:** 2026-04-24
**Platform:** iOS (iPhone 12) — reported from field test; fixed in same session.
**Symptom:** After the user taps a ball (State 2→3, green bbox, Confirm enabled), if the selected ball's track briefly flickers out of `_ballCandidates` (e.g. brief occlusion, low-confidence frame), the UI drops back to State 2 with all-red bboxes. The 30 s / 10 s tap-prompt audio nudge *does not restart* in this State 2 — the user is left with no audio reminder to re-tap, even though they are in the "please tap a ball" state. Can persist indefinitely as long as candidates never actually go to zero.

**Root Cause:** The audio nudge timer lifecycle in `onResult` (inside the `if (_awaitingReferenceCapture)` block) was keyed on candidate presence transitions only:
- `!hadCandidates && hasCandidates` → start (State 1→2)
- `hadCandidates && !hasCandidates` → cancel (State 2→1)

`_handleBallTap` cancelled the timer on first tap (State 2→3). The aliveness check (Decision B-i) at the top of the same `onResult` block silently cleared `_selectedTrackId` when the tapped track disappeared, dropping UI back to State 2. But from the timer's point of view nothing changed — `hadCandidates == hasCandidates == true` — so neither existing branch fired, and the timer stayed cancelled forever.

**Solution that worked:** Added the State 3→2 transition as a third mutually-exclusive `else if` branch to the existing transition chain in `lib/screens/live_object_detection/live_object_detection_screen.dart`:
1. `final hadSelection = _selectedTrackId != null;` captured at the top of the block (before the aliveness check).
2. `else if (hadSelection && _selectedTrackId == null && hasCandidates) _startAudioNudgeTimer();` appended to the existing transition chain.

Mutually exclusive with the other branches (hasCandidates/!hasCandidates are opposite). 4 lines of functional code, zero changes to `_handleBallTap`, `_startAudioNudgeTimer`, `_cancelAudioNudgeTimer`, or `AudioService`. No new state field. See ADR-081.

**Verified:** iOS field-verified on iPhone 12 (2026-04-24) — after triggering a flicker that cleared selection, the first `AUDIO-STUB #1` line fired at t+30 s and continued on 10 s cadence until re-tap.

---

## ISSUE-031: Back Button Unreachable During Calibration Mode + Awaiting Reference Capture (Z-Order Bug)

**Date:** 2026-04-19
**Platform:** iOS (iPhone 12) — reported + verified on device
**Symptom:** Two related bugs uncovered during Phase 1 review:
1. **Calibration mode (corners 0-3 tapped):** Tapping the top-left back-button badge places a calibration corner at the badge's location instead of popping the screen. The button is visually present but unreachable.
2. **Awaiting reference capture (4 corners done, before tap-to-lock):** Same — tapping the back-button badge does nothing. A Phase 1 regression: before Phase 1, that state's full-screen `GestureDetector` had only `onPanStart/Update/End`; Phase 1 added `onTapUp` for ball selection, which introduced a tap recognizer that competes with the back-button's `onTap`.

**Root Cause:** Flutter's gesture arena resolves competing tap recognizers by registration order — the widget rendered LATER in the Stack wins. In the live-detection screen's Stack, the back-button `Positioned` block was rendered at line ~1015, BEFORE two full-screen `GestureDetector`s:
- Line ~1171 — calibration corner-tap collector (`onTapDown`)
- Line ~1232 — awaiting-reference-capture detector (`onPanStart/Update/End` + Phase 1's new `onTapUp`)

Both use `HitTestBehavior.translucent`, which controls visual hit-test propagation but does NOT stop the gesture arena from picking one winner. Since both full-screen detectors were registered later than the back button, they consumed every tap — including taps on the back-button area — regardless of visual overlap.

**Evidence:** User tapped the back-button badge during corner-tap calibration and a phantom corner was placed at the badge's location. Same during awaiting reference capture, but there the Phase 1 `onTapUp` consumed the tap (ball-selection logic ran with a no-op because no candidate was near that coordinate).

**Fix:** Single `Positioned` widget moved in `live_object_detection_screen.dart`. The back-button block now renders AFTER both full-screen `GestureDetector`s but BEFORE the rotate-to-landscape overlay (which stays topmost). Z-order change only — visually identical (still 40×40 black circle, top-left). Gesture arena now resolves taps in the badge area to the back button as intended.

**Side Benefit:** No phantom corner can be placed at the back-button's location during calibration, because the back button now consumes the tap before the corner detector sees it.

**Drive-by cleanup:** Removed the now-unused legacy `_referenceCandidateBbox` field (1 declaration + 2 dead `= null` writes) during the same edit.

**Status:** ✅ FIXED (2026-04-19). iOS device-verified on iPhone 12. Android verification pending.

**Related:** ADR-074 (Back-button z-order via Stack re-ordering), ADR-073 (Phase 1 Anchor Rectangle tap-to-lock design — introduced the `onTapUp` regression).

**Lessons:**
1. **Full-screen `GestureDetector`s must be layered carefully.** Every interactive widget rendered earlier than a full-screen detector is visually present but gesture-inaccessible.
2. **`HitTestBehavior.translucent` ≠ "taps pass through to both widgets."** The arena still picks one winner per gesture. Translucent only controls hit-test *propagation* for bounding purposes, not gesture-winner resolution.
3. **When adding a tap recognizer (`onTap`/`onTapUp`/`onTapDown`) to an existing full-screen detector, audit every earlier-rendered tappable widget** to see if it's now unreachable. Drag-only handlers (`onPanStart/...`) don't compete with taps, so adding a tap recognizer can silently break existing buttons.

---

## ISSUE-030: Session Lock Stuck ON After Bounce-Back False Kick

**Date:** 2026-04-15 (logged); 2026-04-22 (mitigated by Phase 3); formal verification log still owed.
**Platform:** iOS (iPhone 12, monitor+video test)
**Symptom:** After a legitimate HIT decision, ball bounces back from wall. KickDetector detects bounce-back motion as a new kick, activating session lock on the bounce-back trackID. Bounce-back ball quickly lost. Session lock remains ON permanently (200+ frames of "skipping re-acquisition"). Next real kick is completely silent — no tracking, no dots, no decision.

**Root Cause:** Session lock only deactivates when ImpactDetector makes a decision. If the locked track (bounce-back ball) disappears before ImpactDetector can fire, no decision is ever made, and the lock stays on forever.

**Evidence:** Log shows `DIAG-BALLID: locked trackId=31 LOST but session lock ACTIVE — skipping re-acquisition` repeated 200+ times across frames 2070-2310.

**Mitigation (Phase 3, 2026-04-22):** Two recovery paths added in `live_object_detection_screen.dart` that did not exist when this issue was logged:
1. **Idle-edge `else if`** (line ~1013): when a flickered/false kick returns to `KickState.idle` without firing a decision, `_anchorFilterActive` is re-armed AND `_ballId.deactivateSessionLock()` is called explicitly. This covers the most common bounce-back path — the bounce-back motion briefly trips KickDetector, then settles back to idle without a real decision.
2. **2 s safety timer** (line ~1008): armed at the OFF-trigger; if no decision fires within 2 s of leaving idle, `_onSafetyTimeout` runs and clears the session lock. Covers any path where the kick state machine doesn't return cleanly to idle.

**Path A interaction (2026-04-28):** the additional fix to `_onBallMissing` (now updates `_lastDirectZone`/`_lastRawPosition`/`_lastBboxArea` from passed-through values, see ADR-084) may also have closed the original residual case — a genuine in-flight kick whose track flips through `lost` and never produces a decision. With Path A, the lost-frame trigger now has fresh state to fire from. Re-test should confirm the original 200+-frame stuck scenario is no longer reproducible.

**Status:** 🟢 MITIGATED BY PHASE 3 + Path A — one verification log of the original bounce-back scenario (legit HIT → bounce-back → next kick) still owed to formally close. Until that capture is in hand, treat as mitigated rather than fixed.

**Related:** ADR-077 / ADR-078 (Phase 3 spatial filter + idle-edge recovery + safety timer), ADR-083 / ADR-084 (Path A ImpactDetector fix).

---

## ISSUE-029: Bbox Area Ratio Check Too Aggressive — Blocks Legitimate Fast Kick Tracking

**Date:** 2026-04-15
**Platform:** iOS (iPhone 12, monitor+video test)
**Symptom:** During fast kicks, ball tracking goes silent after 2-3 frames. Only Kalman predictions, no real YOLO detections matched. Ball flies to target untracked, no decision made.

**Root Cause:** The area ratio check (2.0/0.5 threshold) on Mahalanobis rescue compares detection area against Kalman PREDICTED area. During fast flight, Kalman's predicted bbox shrinks rapidly due to vw/vh velocity components (ball appears smaller as it approaches wall). After a few prediction-only frames, predicted area diverges so far that real YOLO detections get rejected. Example: Kalman predicted area = 0.000220, real detection area = 0.001000, ratio = 4.5x → blocked.

**Evidence:** Log shows 5 consecutive frames with identical velocity (Kalman predictions, no matched detections) during confirmed ball flight. Ball visibly hit zone 7 but app showed no tracking.

**Fix iterations (2026-04-16):**
1. Relaxed Kalman threshold (3.5/0.3) → 4/5 kicks, but false positive dots returned
2. Last-measured-area with tight bounds (2.0/0.5) → 3/5 kicks (lower bound too tight, ball shrinks in flight)
3. Last-measured-area with relaxed lower bound (2.0/0.3) → **5/5 kicks across 3 test runs** ✅

**Fix:** `ByteTrackTracker.update()` and `_greedyMatch()` accept `lastMeasuredBallArea` from `BallIdentifier.lastBallBboxArea`. Area ratio compares against real measurement with Kalman fallback. Threshold: upper 2.0 (blocks hijacking at 3.8x+), lower 0.3 (allows ball shrinking during flight).

**Status:** ✅ FIXED (2026-04-16). Ground testing scheduled 2026-04-17.

---

## ISSUE-028: 2-Layer False Positive Filter Broke Ball Re-acquisition (REVERTED)

**Date:** 2026-04-13
**Platform:** iOS (iPhone 12)
**Symptom:** After implementing DetectionFilter (pre-ByteTrack AR + size reject) + TrackQualityGate (post-ByteTrack init delay + rolling median) + Mahalanobis rescue validation, ball tracking became severely unstable. Track IDs cycled from 1 to 15 in one session. BallIdentifier locked onto a poster on the wall (id:6, ar:0.8, c:0.99) and player's head (id:14, ar:0.9, c:0.98). Real ball detections were stuck at [INIT 2] and never reached BallIdentifier.

**Root Cause:** TrackQualityGate's initialization delay (4 frames) blocked new tracks from reaching BallIdentifier. When the original ball lock was lost (player walked in front), the real ball reappeared as a new ByteTrack track but was held at [INIT] for 4 frames. During that window, BallIdentifier re-acquired to whatever was already available — poster, head, etc. Additionally, DetectionFilter may have intermittently rejected the real ball on borderline frames, causing ByteTrack to lose and recreate tracks (explaining the id churn).

**Evidence:** 6 screenshots from device testing:
1. Ball correctly locked (id:1) — baseline good
2. Real ball (id:2) stuck at [INIT 2], locked track (id:1) drifted to ar:0.3
3. Ball lock lost entirely, player head (id:3) passed all filters
4. Poster locked as ball (id:6, ar:0.8, c:0.99) — total identity corruption
5. id:11 with AR 3.8 passed Layer 1 (should have been rejected at AR > 2.5 threshold)
6. Player head (id:14, ar:0.9, c:0.98) passed all filters as yellow candidate

**Fix:** Fully reverted all changes. 4 modified files restored via `git checkout`, 4 new files deleted. 176/176 tests passing.

**Lessons:**
1. **Never block tracks from BallIdentifier** — init delay starves re-acquisition. Any post-ByteTrack filter must pass ALL tracks through; can tag/score but must not remove from candidate pool.
2. **Player head (ar:0.9) is unfilterable with geometry** — needs second-stage classifier or motion channel.
3. **Implement ONE filter at a time** — test on device before adding the next. Multi-layer simultaneous changes make it impossible to isolate which filter caused which problem.
4. **Mahalanobis rescue validation (size + velocity) is the safest first step** — it only restricts rescue matching inside ByteTrack, doesn't touch pipeline flow or BallIdentifier at all.

**Status:** ✅ REVERTED (2026-04-13). Codebase clean. 176/176 tests passing.

---

## ISSUE-027: isStatic Flag Never Clears on Existing ByteTrack Tracks

**Date:** 2026-04-09
**Platform:** iOS (iPhone 12)
**Symptom:** When the ball is kicked, the locked track (original trackId from calibration) retains `isStatic=true` even though the ball is in motion. KickDetector reaches `confirming` but may drop back to `idle` before the decision fires, blocking announcements. Only NEW tracks born during motion get `isStatic=false`. Additionally, `isStatic` never re-triggers on subsequent stationary periods — once `false`, stays `false` forever because `_cumulativeDisplacement` retains displacement from previous movement.

**Root Cause:** Two bugs in `_STrack.evaluateStatic()`: (1) `isStatic` was a one-way flag — `if (!isStatic && ...)` only set to `true`, never cleared. (2) `_cumulativeDisplacement` was a lifetime accumulator that only grew — after any movement, the total exceeded `maxDisp` forever, preventing re-classification as static.

**Evidence:** Debug bbox overlay showed `S` (isStatic) label on locked ball track during flight. Test 1 Kick 1: `kick=confirming` coexisted with `isStatic=true`, `kickState` dropped to `idle` by decision time. New trackIds born in flight had `isStatic=false` and reached `kickState=active` normally.

**Solution:** Replaced lifetime `_cumulativeDisplacement` accumulator with sliding window `ListQueue<double>` (capacity = 30 frames). `evaluateStatic()` now sums only the recent window and sets `isStatic` based on whether total < threshold, making it fully two-way. Approach inspired by Frigate NVR's production static object detection. Research confirmed no standard tracker (ByteTrack/SORT/DeepSORT/OC-SORT/Norfair) has static classification.

**Status:** ✅ FIXED (2026-04-13). Device-verified on iPhone 12. 3 new unit tests added. 176/176 passing.

---

## ISSUE-026: Mahalanobis Rescue Hijacks Ball Identity (CRITICAL)

**Date:** 2026-04-09
**Platform:** iOS (iPhone 12)
**Symptom:** Locked ball track jumps from real soccer ball to false positives (video player controls, wall marks, kicker's body) via Mahalanobis distance matching. Real ball becomes orphaned and untracked. Subsequent kicks produce noResult or total tracking failure.

**Root Cause:** Mahalanobis rescue is too lenient — accepts matches with mahal²=0.10-0.33+ allowing locked track to jump to distant false detections. `lockedTrackId` restricts WHICH TRACK gets rescued but not WHAT DETECTION it matches to.

**Evidence:** Debug bbox overlay confirmed: (1) Green [LOCKED] box on video player controls while real ball had yellow box, (2) Green box jumping from ball to zone 6 false positive and back, creating false trail dots, (3) After corruption, BallIdentifier stayed locked on wrong track for 100+ frames.

**Solution:** Pending. Options: (a) bbox size validation (reject >3x reference), (b) aspect ratio validation (reject ar >1.5), (c) max Mahalanobis threshold (cap mahal²), (d) position continuity check.

**Status:** Identified. CRITICAL priority — causes total tracking failure.

---

## ISSUE-025: Kick-State Gate Broke Grounded Kick Detection (REVERTED)

**Date:** 2026-04-08
**Platform:** iOS (iPhone 12)
**Symptom:** After adding kick-state gate (ImpactDetector/WallPredictor only run when `KickDetector.state == confirming || active`), 3 out of 5 kicks went undetected — specifically grounded/low-velocity shots.

**Root Cause:** KickDetector's `jerkThreshold = 0.01` requires an explosive velocity spike to transition from idle → confirming. Grounded shots have lower velocity onset and less abrupt acceleration than aerial kicks. The jerk threshold never fires, so `kickEngaged` stays `false`, ImpactDetector never receives frames, and the pipeline is completely silent for those kicks.

**Fix:** Fully reverted the kick-state gate. ImpactDetector and WallPredictor now run unconditionally every frame (same as pre-experiment baseline). KickDetector only controls whether the result is announced (audio gate), not whether the pipeline processes frames.

**Lesson:** Gating pipeline INPUT on KickDetector state is too aggressive. KickDetector should only gate pipeline OUTPUT (result acceptance). The phantom decisions during idle that motivated the gate are log pollution, not functional bugs — the app correctly never announced them.

**Verified:** ✅ Reverted and confirmed 172/172 tests passing.

---

## ISSUE-024: Trail Dot Gating on kickEngaged Killed All Visualization (REVERTED)

**Date:** 2026-04-08
**Platform:** iOS (iPhone 12)
**Symptom:** After adding `kickEngaged` parameter to `BallIdentifier.updateFromTracks()`, zero trail dots appeared during any kicks. Complete loss of visual ball tracking.

**Root Cause:** Two compounding issues:
1. `_ballId.updateFromTracks(tracks, kickEngaged: ...)` was called BEFORE `_kickDetector.processFrame()`, so it read the previous frame's kick state (1-frame lag).
2. Kick windows are very short (3-5 frames for video-on-monitor testing), and with the 1-frame lag, the effective window was even shorter.
3. The underlying goal (preventing false dots on non-ball objects) was misdiagnosed — the root cause is BallIdentifier re-acquiring to wrong tracks (player body, poster), not trail timing.

**Fix:** Fully reverted `kickEngaged` parameter. Trail dots always added when ball is tracked, regardless of kick state.

**Verified:** ✅ Reverted and confirmed 172/172 tests passing.

---

## ISSUE-023: Ball Track Lost During Fast Kick Flight (ByteTrack IoU Failure)

**Date:** 2026-04-06
**Platform:** iOS (iPhone 12)
**Symptom:** After implementing ByteTrack, the ball is tracked correctly when stationary or moving slowly (player retrieving ball), but the track is LOST during fast kick flight. No orange trail dots appear during the kick. Every kick produces `noResult` because `directZone` is always null — the ball's tracked position never enters the calibrated grid.

**Root Cause:** ByteTrack's 8-state Kalman filter predicts near-zero velocity when the ball is stationary before a kick. When the ball suddenly accelerates (kick), it moves ~0.12 normalized units in 1 frame — roughly 2x the ball's bbox width (~0.06). The predicted bbox is still at the kicking spot, so IoU between predicted and actual detection is ZERO. ByteTrack cannot match the detection to the existing track, creates a new track with a new ID, and the original ball track goes to `lost` then `removed`. BallIdentifier re-acquires to a new trackId, but by then the ball may be mid-flight with a small bbox, or already bouncing back.

**Evidence:**
- Terminal log shows `trackId` jumping from 1 → 26 → 28 → 29 → 39 → 52 across one session
- CSV shows `directZone=null` for ALL tracking frames across 3 kicks
- Screenshots show trail dots only at kicking spot (stationary ball) and during slow ball retrieval, NOT during fast flight
- Ball IS visible in the camera frame during flight (screenshots prove YOLO detects it)

**Why slow movement works:** Player retrieving ball moves ~0.01 per frame vs bbox ~0.06. IoU stays ~0.7+. ByteTrack matches perfectly.

**Potential Solutions:**
1. Fall back to centroid-distance matching when IoU=0 for the locked ball track
2. Temporarily boost Kalman process noise on KickDetector jerk signal (lets velocity prediction catch up)
3. Widen IoU search radius during kick phase
4. Hybrid matching: IoU when available, centroid distance as fallback for fast motion

**Fix Iteration 1 (Mahalanobis merged with IoU):** Added `mahalanobisDistSq()` to Kalman, used as dual gate (`mahalOk || iouOk`) in `_greedyMatch`. Ball track maintained through kicks. BUT circle tracks also got Mahalanobis-rescued — wide covariance gate allowed circles to match to wrong circle detections, creating scattered false dots.

**Fix Iteration 2 (Mahalanobis restricted to locked track):** Changed to two-stage matching: Stage 1 pure IoU (all tracks), Stage 2 Mahalanobis (ONLY `lockedTrackId`). Added `lockedTrackId` parameter threaded through `update()` → `_greedyMatch()`. Live screen passes `_ballId.currentBallTrackId`. Circle tracks can only match via IoU — if IoU fails they go to `lost` state.

**Status:** Fix iteration 2 implemented. Pending device test.

---

## ISSUE-022: Target Circle False Positives — YOLO Detects Banner Circles as Soccer Balls (CRITICAL BLOCKER)

**Date:** 2026-04-04
**Platform:** iOS (iPhone 12) — likely affects Android too
**Symptom:** Orange trail dots appear on the target banner's red LED-ringed circles even when no real ball is in flight. During kicks, trail dots scatter between the real ball and circle false positives. Zone announcements fire prematurely with wrong zones. Shaking the camera toward the target creates false trails hopping between circles, triggering zone announcements with no ball kicked.

**Root Cause:** The 9 red LED-ringed circles (~20-25cm diameter) on the Flare Player target banner are round shapes that YOLO detects as `Soccer ball` or `ball` at confidence ≥0.25. These detections:
1. Compete with the real ball in `_pickBestBallYolo` — especially when the real ball approaches the target area, circle detections are spatially closer to the last known position
2. Are INSIDE the calibrated grid area — `_applyPhaseFilter()` spatial gating cannot distinguish them from the real ball arriving at the target
3. Appear ON the wall surface (depth ratio ~1.0), INSIDE a zone (directZone not null), and stationary — identical to "ball has impacted the target" for the pipeline
4. Corrupt BallTracker, Kalman filter, WallPlanePredictor, and ImpactDetector with false position data

**Evidence:** 41 screenshots in `/Users/shashank/Documents/app behaviour images/False positive on goal post/`. Field test: Phase 1 = 7/18 (38.9%) accuracy with zone 6 bias, Phase 2 = 1/9 (11.1%) accuracy with zone 1/2 bias. Bias changes with camera height — proves detections are on target circles, not real ball trajectories.

**Solution:** Pending design. Possible approaches: geometric exclusion zone (reject detections inside calibrated grid when ball is not near target), bbox size filtering (circles have stable size vs moving ball), motion-based filtering (circles are stationary vs moving ball), confidence threshold increase, or model retraining.

**Status:** Identified. #1 BLOCKER for zone accuracy. Solution not yet designed or approved.

---

## ISSUE-021: Bounce-Back False Detection (Ball Detected on Rebound, Not Initial Impact)

**Date:** 2026-04-01 (logged); 2026-04-22 (resolved by Phase 3); 2026-04-29 (formally closed by code-trace review).
**Platform:** iOS (iPhone 12)
**Symptom:** Ball hits zone 6 on the wall but YOLO misses the initial impact (ball too fast/small at the wall). After the ball bounces back toward the camera (getting larger, moving downward in frame), YOLO re-detects it and the pipeline reports zone 2 instead of zone 6.

**Root Cause:** YOLO loses the ball near the wall (small bbox, motion blur). The ball bounces back and is re-detected closer to the camera. The WallPlanePredictor accumulates observations from the rebound (depth decreasing = ball coming back), which fails the `_isDepthIncreasing()` check. However, the ImpactDetector may still have stale `_lastWallPredictedZone` from before the loss, or the rebound trajectory enters the grid from the bottom.

**Resolution (Phase 3, 2026-04-22):** This entire failure mode is closed by the Phase 3 spatial filter, traced end-to-end on 2026-04-29:

1. The instant a real IMPACT DECISION fires, both the accept branch (`live_object_detection_screen.dart:1091`) and the reject branch (`:1134`) re-arm `_anchorFilterActive = true`. The very next frame, the anchor filter is ON.
2. With the filter ON, every YOLO detection whose bbox center is outside `_anchorRectNorm` is dropped at `_toDetections` (line ~264) **before ByteTrack ever sees it**.
3. A bounce-back ball physically lands away from the kick spot — bbox center is outside the rect by definition. So the bounce-back detections are dropped, ByteTrack never sees them, BallIdentifier has no candidates to lock onto (lock was released on the same line that re-armed the filter), and ImpactDetector is never invoked. **There is no pipeline path from a bounce-back outside the rect to a second decision.**
4. Bounce-back inside the rect (rare — ball would have to roll all the way back to the kick spot) is also handled: KickDetector is in `refractory` after `onKickComplete`, so it can't immediately re-confirm; if the ball settles inside the rect before refractory expires, `isStatic` keeps it from re-confirming; if it's still rolling when refractory expires, that's indistinguishable from the player legitimately starting their next kick — treating it as a kick is correct.

**Status:** ✅ FIXED BY PHASE 3 (2026-04-22). No legacy "WallPlanePredictor stale data" workaround needed — the rebound never reaches WallPlanePredictor in the first place. WallPlanePredictor.reset() is also called on the same decision-fired lines as a defence-in-depth safeguard.

**Related:** ADR-077 (Phase 3 spatial filter), ADR-078 (Phase 3 polish — idle-edge recovery + safety timer). See also CLAUDE.md "Bounce-back false detection" row in the issues table (🟢 MITIGATED BY PHASE 3, downgraded from "Identified 2026-04-01" on 2026-04-29).

---

## ISSUE-020: False Positive YOLO Detections on Non-Ball Objects (Kicker Body/Head)

**Date:** 2026-04-01
**Platform:** iOS (iPhone 12)
**Symptom:** Orange trail dots appear on the kicker's body, hands, head, and random wall patterns during Ready and Tracking phases. Creates visual noise and can confuse the tracking pipeline.

**Root Cause:** `confidenceThreshold: 0.25` in YOLOView accepts marginal detections. At low confidence, YOLO misclassifies round-ish shapes (head, hands, clothing folds) as `Soccer ball` or `ball`.

**Solution:** Added `_applyPhaseFilter()` in `_pickBestBallYolo`. Phase-aware filtering:
- Ready phase: confidence floor 0.50 + spatial gate (10% of frame radius from last known position)
- Tracking phase: confidence floor 0.25 + spatial gate (15% of frame radius from Kalman-predicted position)
- No prior position: confidence floor 0.50, no spatial gate

**Status:** FIXED — verified in Session 3 field test (no false dots observed).

---

## ISSUE-019: Zone Accuracy Bug 3 Root Cause — Perspective Error in Mid-Flight Mapping

**Date:** 2026-04-01
**Platform:** iOS (iPhone 12)
**Symptom:** Ball hitting upper zones (6, 7, 8) consistently reported as bottom zones (1, 2). Session 1: 1/5 correct (20%). Every high-zone kick mapped to zone 1 or 2.

**Root Cause:** The 2D homography maps image points to the wall plane, but only correctly for points ACTUALLY ON the wall. The ball is detected mid-flight, NOT at the wall. Due to perspective, a ball heading toward zone 8 at mid-flight appears LOWER in the camera frame than zone 8's actual position on the wall. The homography maps this lower position to zone 1 or 2.

Both `directZone` (maps raw position through homography) and the old `TrajectoryExtrapolator` (projects 2D camera velocity) suffer from this: `directZone` captures the grid-entry position (bottom), and the extrapolator under-predicts vertical displacement because 2D velocity decelerates due to perspective foreshortening.

**Solution:** `WallPlanePredictor` service (3 iterations):
- v1: Estimated wall depth from hardcoded `wallDepthRatio=0.25`. Fixed Y-axis error but fragile.
- v2: Computed wallDepthRatio from physical dimensions. Still hardcoded physical assumptions.
- v3 (current): Zero hardcoded parameters. Iterative forward projection — extrapolates pseudo-3D trajectory one frame at a time, projects back to 2D, checks `pointToZone()`. Wall discovered implicitly when projected point enters the grid.

**Status:** LARGELY FIXED. Session 3: 3/5 exact correct (60%), 4/5 within 1 zone (80%). Remaining: boundary precision and bounce-back detection (separate issues).

---

## ISSUE-001: Android `onResult` Never Fires (Silent YOLO Inference Failure)

**Date:** 2026-02-25
**Platform:** Android (Galaxy A32)
**Symptom:** `YOLOView` renders but `onResult` callback never fires. No errors in logcat. Camera preview works fine.

**Root Cause:** Gradle's AAPT compresses `.tflite` files by default. The compressed model cannot be memory-mapped by TFLite, so inference silently fails.

**Solution:** Add to `android/app/build.gradle`:
```groovy
android {
    aaptOptions {
        noCompress 'tflite'
    }
}
```

**Why it's easy to miss:** No error is thrown. The camera preview works. Only the inference callback is silent.

---

## ISSUE-002: iOS "Unable to Verify App" After ~7 Days

**Date:** 2026-03-11
**Platform:** iOS (iPhone 12)
**Symptom:** App icon tap shows "Unable to Verify" dialog. Tapping "Verify App" in Settings fails with network error even when WiFi is connected.

**Root Cause:** Free Apple Developer account provisioning profiles expire after **7 days**. Once expired, iOS cannot verify the signing certificate and blocks app launch. The network error is misleading — the profile is expired, not unreachable.

**Solution:**
1. Delete the app from the iPhone (long-press icon -> Remove App -> Delete App)
2. Re-run `flutter run` from Mac with iPhone connected via USB
3. This generates a fresh 7-day provisioning profile

**Prevention:** Re-deploy via `flutter run` at least once every 7 days. A paid Apple Developer account ($99/year) extends profiles to 1 year.

**What does NOT work:**
- Restarting the iPhone
- Toggling WiFi
- Tapping "Verify App" repeatedly in Settings

---

## ISSUE-003: iOS Camera Not Working After App Reinstall (No Permission Dialog)

**Date:** 2026-03-11
**Platform:** iOS (iPhone 12)
**Symptom:** Camera screen shows blank/pink background. Terminal logs: `Camera permission not determined. Please request permission first.` followed by `Failed to set up camera - permission may be denied or camera unavailable.` No permission dialog appears on the phone.

**Root Cause (multi-factor):**
1. Deleting an app from iOS **wipes its camera permission** from the TCC database, resetting to `.notDetermined`
2. The `ultralytics_yolo` plugin (v0.2.0) does **NOT** request camera permission on iOS — it only checks the status and silently fails if `.notDetermined` (see `VideoCapture.swift` lines 86-95)
3. The Android side of the same plugin DOES request permissions internally — this is a platform asymmetry bug in the plugin
4. Previously, permission was granted on the very first install and persisted across all subsequent `flutter run` deploys — until the app was deleted

**Solution:** Add explicit camera permission request using `permission_handler`:

1. Add dependency in `pubspec.yaml`:
   ```yaml
   permission_handler: ^11.3.1
   ```

2. Add iOS Podfile macro (required for `permission_handler` to compile camera permission code):
   ```ruby
   # In post_install block:
   target.build_configurations.each do |config|
     config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
       '$(inherited)',
       'PERMISSION_CAMERA=1',
     ]
   end
   ```

3. Request permission before rendering `YOLOView`:
   ```dart
   import 'package:permission_handler/permission_handler.dart';

   bool _cameraReady = false;

   Future<void> _requestCameraPermission() async {
     final status = await Permission.camera.request();
     if (!mounted) return;
     if (status.isGranted) {
       setState(() => _cameraReady = true);
     }
   }
   ```

4. Gate `YOLOView` on `_cameraReady` flag to prevent rendering before permission is granted.

5. Run `pod install` in `ios/` directory after adding the dependency.

**Why it worked before without this fix:** Permission was granted once on the original install and iOS remembered it across every `flutter run`. Deleting the app broke this chain.

---

## ISSUE-004: CocoaPods `pod install` Fails with UTF-8 Encoding Error

**Date:** 2026-03-11
**Platform:** macOS (Apple M5)
**Symptom:** `pod install` crashes with `Encoding::CompatibilityError: Unicode Normalization not appropriate for ASCII-8BIT`

**Root Cause:** Terminal session locale is not set to UTF-8. Ruby 4.0 / CocoaPods 1.16.2 requires UTF-8 encoding.

**Solution:** Set locale before running pod install:
```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
pod install
```

**Prevention:** Add to `~/.zshrc`:
```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

---

## ISSUE-005: Android Trail Coordinates Mirrored/Offset in Landscape

**Date:** 2026-02-25
**Platform:** Android (Galaxy A32)
**Symptom:** Ball trail dots appear at wrong positions — mirrored or offset from actual ball location in landscape mode.

**Root Cause:** `ultralytics_yolo` returns `normalizedBox` coordinates without accounting for Android display rotation. In landscape-left (rotation=1) coordinates are correct, but in landscape-right (rotation=3) they need `(1-x, 1-y)` flip.

**Solution:** MethodChannel polling of `Surface.ROTATION_*` from `MainActivity.kt` + coordinate flip:
```dart
// In MainActivity.kt: MethodChannel returns Display.rotation
// In Dart:
if (_androidDisplayRotation == 3) {
  dx = 1.0 - dx;
  dy = 1.0 - dy;
}
```

**Note:** iOS handles rotation in the plugin layer — this fix is Android-only.

---

## ISSUE-006: Camera Aspect Ratio Mismatch (~10% Y-Offset on iOS)

**Date:** 2026-02-23
**Platform:** iOS (iPhone 12)
**Symptom:** Trail dots consistently offset by ~10% vertically from actual ball position.

**Root Cause:** Code assumed 16:9 camera aspect ratio, but `ultralytics_yolo` uses `.photo` session preset on iOS which outputs 4032x3024 (4:3).

**Solution:** Changed `YoloCoordUtils` camera aspect ratio from 16:9 to 4:3. All FILL_CENTER crop calculations updated accordingly.

---

## ISSUE-007: Stale Extrapolation Causes False HIT Results

**Date:** 2026-03-09
**Platform:** Both
**Symptom:** Ball on the left side of the goal (far from calibrated target on the right) still produces a false HIT at zone 3.

**Root Cause:** `ImpactDetector._onBallDetected()` had `if (extrapolation != null) _bestExtrapolation = extrapolation;` — only updated when non-null. A stale extrapolation from an earlier frame (when the ball briefly headed toward the target) persisted after the ball changed direction.

**Solution:** Changed to `_bestExtrapolation = extrapolation;` (always use latest, including null). When trajectory no longer intersects the target, the stale value is cleared.

---

## ISSUE-008: Audio "MISS" Not Playing / Playing Wrong Zone

**Date:** 2026-03-09
**Platform:** Both
**Symptom:** MISS audio sometimes doesn't play, or plays the previous zone's audio instead of "miss".

**Root Cause:** `AudioPlayer` retains its previous source state. Calling `play()` with a new source while the previous source is still loaded can cause race conditions.

**Solution:** Call `stop()` before `play()` in `AudioService` to ensure clean player state when switching between different audio sources.

---

## ISSUE-010: Back Button Blocked During Reference Capture Sub-Phase

**Date:** 2026-03-13
**Platform:** Both (iOS and Android)
**Symptom:** After tapping all 4 calibration corners, the back button (top-left arrow) stops responding. User cannot go back to home screen until the full calibration is completed (ball detection + confirm).

**Root Cause:** The full-screen `GestureDetector` for calibration corner taps (`LayoutBuilder` + `GestureDetector` + `SizedBox.expand()`) was conditionally shown with `if (_calibrationMode)`. After 4 corners are placed, `_calibrationMode` is still `true` (it only becomes `false` after confirming reference capture). This full-screen touch handler sits above the back button in the Stack z-order, intercepting all taps.

**Solution:** Narrowed the condition to `if (_calibrationMode && !_awaitingReferenceCapture)`. The full-screen tap handler is now only present while corners are actively being collected (0-3 corners). Once all 4 corners are placed and the reference capture sub-phase begins, the tap handler is removed from the widget tree, allowing the back button to receive taps again.

**Verified:** 81/81 tests passing. Back button works in all states: before calibration, during reference capture, after calibration, during tracking/results.

---

## ISSUE-012: Impact Detection Fails on 9/10 Real Soccer Ball Kicks

**Date:** 2026-03-17
**Platform:** Both (iOS iPhone 12, Android Realme 9 Pro+)
**Symptom:** Only 1 out of 10 real soccer ball kicks correctly detected as HIT. Remaining 9 showed "No result" or "reset". Trail dots and extrapolation visually showed correct ball path, but decision pipeline rejected.

**Root Causes (3 compounding issues identified via terminal diagnostic logs):**

1. **`minTrackingFrames = 8` too high (60% of failures):** Fast kicks complete flight in 6-9 frames at 30fps. Ball tracked for only 1-7 frames → rejected as "insufficient frames". Literature consensus (Hawk-Eye, TrackNet, Kamble survey of 50+ papers): minimum should be 3 frames for Kalman velocity convergence.

2. **Depth ratio filter blocks valid hits (20% of failures):** `minDepthRatio = 0.3` rejected ratios of 0.2735 and 0.1886 — balls that reached the wall depth but appeared smaller due to motion blur reducing bbox size. No published single-camera ball tracking system uses bbox area ratio as a depth gate. Already covered by trajectory extrapolation.

3. **`_bestExtrapolation` overwritten with null (10% of failures):** Despite 159 tracking frames and valid depth ratio, extrapolation was null because line 187 overwrites unconditionally. Valid prediction from frame 100 destroyed when frame 159 returned null. Additionally, extrapolation not recomputed during occlusion using Kalman state.

4. **Gravity overshoot in extrapolator (wrong zone):** `gravity = 0.001` with `t = 30` frames adds 0.45 to Y — nearly half frame height. Caused zone 4 hit to be reported as zone 3.

**Solution:** ADR-047 — 4 evidence-backed fixes. See `activeContext.md` for full research citations.

**Fixes implemented (2026-03-17):**
- ✅ Fix 1: `minTrackingFrames` 8→3 in `impact_detector.dart`
- ✅ Fix 2: Depth ratio filter disabled in `impact_detector.dart` (diagnostic logging preserved)
- ✅ Fix 3: Extrapolation retained during occlusion in `impact_detector.dart` + recomputed from Kalman state in `live_object_detection_screen.dart`
- ⏳ Fix 4: Gravity/maxFrames in `trajectory_extrapolator.dart` — DEFERRED

**Post-fix results:** iOS indoor test: 4/6 correct HITs (67%), up from 1/10 (10%). Fix 2 directly saved 2 detections. 2 remaining failures had only 1 tracking frame.

**Additional fix already applied:** `confidenceThreshold: 0.25` added to `YOLOView` (was plugin default 0.5). Plugin source verified: Dart layer at `yolo_controller.dart:12` overrides native iOS default of 0.25.

---

## ISSUE-009: Rotate Overlay Text Appears Upside Down in Portrait

**Date:** 2026-03-10
**Platform:** iOS (iPhone 12)
**Symptom:** The "Rotate your device" overlay text and icon appear upside down when holding phone in portrait.

**Root Cause:** Used `Transform.rotate(pi/2)` but the UI is locked to landscape, so content needs to be rotated the opposite direction to read upright in portrait.

**Solution:** Changed to `Transform.rotate(-pi/2)`. Device-verified.

---

## ISSUE-011: iOS Draggable Corners Not Working (Hit Radius Too Small)

**Date:** 2026-03-14
**Platform:** iOS (iPhone 12)
**Symptom:** Draggable calibration corners worked perfectly on Android but not on iOS. Only 1 of 4 corners could occasionally be dragged, and only after multiple attempts. Not smooth.

**Initial Misdiagnosis:** iOS `UiKitView` platform view gesture recognizers competing with Flutter's `PanGestureRecognizer` during the `kTouchSlop` ambiguity window. Research revealed Flutter issue #57931 (PlatformView pan interruption) was fixed in Flutter engine v1.21+, and the project uses Flutter 3.38 — so this was NOT the root cause.

**Diagnostic Approach:** Added temporary DIAG-DRAG prints to `onPanStart` to log:
1. Whether the callback fires at all
2. The touch position (local + normalized) and corner positions
3. Hit-test result (nearest index + distances to each corner)

**Diagnostic Findings:**
- `onPanStart` fires EVERY TIME on iOS — no gesture arena competition
- `_findNearestCorner()` returns `null` every time because all distances exceed the `0.04` threshold
- Closest attempt was distance `0.0408` (just `0.0008` over the `0.04` threshold)
- Distances ranged from `0.0408` to `0.0851`

**Root Cause:** `_dragHitRadius = 0.04` was too small. Flutter's `kTouchSlop` (~18px) shifts the reported `onPanStart` position ~0.05-0.08 away from where the user intended to touch. On iOS with a 4:3 camera feed, this shift in normalized space consistently exceeded the 0.04 threshold. Android was less affected because its `kTouchSlop` behavior differed slightly (or the user's finger was incidentally closer to corners during testing).

**Solution:** Increased `_dragHitRadius` from `0.04` to `0.09` (~9% of frame in normalized space). This covers all observed distances with margin. Removed DIAG-DRAG diagnostic prints after diagnosis.

**Lesson:** When platform-specific touch behavior differs, add diagnostic instrumentation before assuming gesture system bugs. The `kTouchSlop` offset is a known Flutter behavior that affects all `GestureDetector` pan callbacks, but its impact in normalized coordinate space depends on screen resolution and camera aspect ratio.

---

## ISSUE-013: Finger Occlusion Makes Corner Dragging Imprecise on Both Platforms

**Date:** 2026-03-19
**Platform:** Both (iOS iPhone 12, Android Realme 9 Pro+)
**Symptom:** During real-world field testing, user cannot precisely align calibration corners with goalpost corners because: (1) 60px offset cursor causes corner to jump far from its position on initial tap — bottom corners become unreachable due to limited screen space, (2) solid green filled circle hides the crosshair intersection point where precise alignment is needed.

**Root Cause (two sub-issues):**
1. `_dragVerticalOffsetPx = 60.0` is too large — on a phone in landscape, 60px is a significant portion of the screen height. When tapping a bottom corner, the corner jumps up 60px, and the user must drag downward to bring it back, but there's almost no screen space below the finger.
2. `CalibrationOverlay._paintCornerMarkers()` draws a solid filled circle (radius 8px) on top of the crosshair intersection, completely obscuring the precision alignment point.

**Solution:**
1. Reduced `_dragVerticalOffsetPx` from 60.0 to 30.0 (user tested 15px first — too subtle; 30px confirmed good on both platforms)
2. Removed `fillPaint` and `canvas.drawCircle(pixel, 8.0, fillPaint)` — corners are now hollow green rings (stroke only, radius 10px) always, not just during drag

**Verified:** 81/81 tests passing. Device-verified on iPhone 12 and Realme 9 Pro+.

---

## ISSUE-016: Result Overlay Stuck on Screen Forever After KickDetector Integration

**Date:** 2026-03-23
**Platform:** iOS (iPhone 12)
**Symptom:** After a kick result is shown (zone number or MISS), the overlay never clears. It stays on screen indefinitely and the app never returns to "Ready — waiting for kick".

**Root Cause:** `ImpactDetector`'s 3-second result display timeout lived inside `processFrame()`. After KickDetector integration, `processFrame()` was gated behind `_kickDetector.isKickActive`. Once a result fires, the kick completes → `isKickActive=false` → `processFrame()` never called again → timeout never checked → overlay stuck forever.

**Solution:** Added `tickResultTimeout()` method to `ImpactDetector`:
```dart
void tickResultTimeout() {
  if (_phase != DetectionPhase.result) return;
  if (_resultTimestamp != null &&
      DateTime.now().difference(_resultTimestamp!) >= resultDisplayDuration) {
    _reset();
  }
}
```
Called every frame in `live_object_detection_screen.dart` outside the kick gate:
```dart
_impactDetector.tickResultTimeout(); // Always — outside kick gate
if (_kickDetector.isKickActive) { ... }
```

**Verified:** Fixed in code (2026-03-23). Awaiting device re-test.

---

## ISSUE-017: Share Log Broken on iOS 26.3.1 (sharePositionOrigin Enforcement)

**Date:** 2026-03-23
**Platform:** iOS (iPhone 12, iOS 26.3.1)
**Symptom:** Tapping "Share Log" button crashes with:
```
PlatformException(error, sharePositionOrigin: argument must be set,
{{0,0},{0,0}} must be non-zero and within coordinate space of source view: {{0,0},{844,390}}, null, null)
```

**Root Cause:** iOS 26.3.1 now enforces `sharePositionOrigin` must be a non-zero `Rect` within screen bounds when calling `Share.shareXFiles` in landscape mode. The existing `_shareLog()` call passed no `sharePositionOrigin`, which defaults to `Rect.zero`. iOS 26.3.1 started rejecting this.

**Note:** Hardcoding coordinates (e.g., `Rect.fromLTWH(12, 60, 90, 28)`) was considered and rejected — breaks on different screen sizes and orientations.

**Solution:** Used `GlobalKey` + `RenderBox` to derive the button's actual position at tap time:
```dart
final _shareButtonKey = GlobalKey(); // field on state class

// In _shareLog():
final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : Rect.zero;
await Share.shareXFiles([XFile(path)], subject: 'Flare Diagnostic Log',
    sharePositionOrigin: origin);
```
`key: _shareButtonKey` attached to the share button's `Container` widget. Works on any screen size, orientation, and device.

**Verified:** Fixed in code (2026-03-23). Awaiting device re-test.

---

## ISSUE-018: Off-by-One Between KickDetector and ImpactDetector (Ball-Loss Path Never Fires)

**Date:** 2026-03-23
**Platform:** Both
**Symptom:** When a kick completes with ball loss (ball disappears into the target zone), ImpactDetector never makes a decision. The kick gate closes on the same frame ImpactDetector would have triggered.

**Root Cause:** `KickDetector.maxActiveMissedFrames = 5` equals `ImpactDetector.lostFrameThreshold = 5`. On the 5th consecutive missed frame:
1. `KickDetector.processFrame()` calls `onKickComplete()` → `isKickActive = false`
2. Screen's `if (_kickDetector.isKickActive)` check is now false
3. `ImpactDetector.processFrame()` is NOT called for the 5th frame
4. `ImpactDetector._lostFrameCount` reaches only 4 (not 5), so `_makeDecision()` never fires

**Effect:** Kick 3 in field test (ball hit around zone 7 intersection) was completely missed — the ball disappeared into the target and the app never triggered.

**Proposed Fix:** Change `maxActiveMissedFrames` from 5 to 8 in `kick_detector.dart`. This gives ImpactDetector enough frames to hit its own threshold before the kick gate closes. The extra 3 frames (100ms at 30fps) of tolerance does not cause meaningful false detections since the refractory period follows immediately.

**Status:** Identified. Pending user approval. Not yet fixed.

---

## ISSUE-015: Trajectory Extrapolation Predicts Wrong Zone Numbers

**Date:** 2026-03-20
**Platform:** Both (iOS iPhone 12, Android Realme 9 Pro+)
**Symptom:** iOS: Extrapolation consistently predicts wrong zones (e.g., predicts zone 8, ball actually hits zone 5). The extrapolation dots form correctly showing the predicted trajectory, but the prediction diverges from actual ball path. Android: Completely unable to detect any hits at all.

**Root Cause (iOS — wrong zones):** Trajectory extrapolation amplifies small angular errors in the Kalman velocity estimate quadratically over 30+ frames. A 2-degree error at mid-flight, extrapolated over 30 frames at 6m distance, shifts the predicted impact by ~210mm — more than half a zone width (196mm per third). The gravity term (`0.5 * 0.001 * t²`) compounds this by adding up to 0.45 to Y over 30 frames.

**Root Cause (Android — no detections):** TFLite inference on Snapdragon 695 is ~4-8x slower than CoreML on A14 Bionic (~50ms vs ~6ms per frame). The `ultralytics_yolo` plugin uses `STRATEGY_KEEP_ONLY_LATEST` backpressure on Android, dropping 50-70% of camera frames. During a 250ms kick, Android gets only 1-2 detection frames (vs 6-8 on iOS), often below `minTrackingFrames=3`.

**Solution:** ADR-051 — Depth-verified direct zone mapping. Re-enabled depth ratio as a "trust qualifier": when ball's camera position maps to a zone AND depth ratio confirms near-wall depth (ratio within [0.3, 1.5]), that zone takes priority over trajectory extrapolation. `maxDepthRatio` tightened from 2.5 to 1.5.

**Verified:** 81/81 tests passing. Pending outdoor device verification.

---

## ISSUE-014: Detection Pipeline Fires Before Calibration (False MISS/noResult During Setup)

**Date:** 2026-03-19
**Platform:** Both (iOS iPhone 12, Android Realme 9 Pro+)
**Symptom:** Immediately after tapping "Start Detection" and entering the camera screen, orange trail dots appear for any detected ball, "Ball lost" badge flickers, and false MISS/noResult announcements fire — even though the user hasn't calibrated or confirmed the reference ball yet.

**Root Cause:** The `onResult` callback fed YOLO detections unconditionally into `BallTracker.update()` and `BallTracker.markOccluded()` from camera open. The `ImpactDetector` was gated on `_zoneMapper != null` but this became true as soon as 4 corners were tapped (before reference ball confirm), allowing impact detection during the reference capture sub-phase.

**Solution:** Added `_pipelineLive` boolean gate (defaults `false`). Set `true` only in `_confirmReferenceCapture()`, reset to `false` in `_startCalibration()`. All tracker, extrapolation, and impact detector calls wrapped in `if (_pipelineLive)`. Exception: reference capture bbox area grab remains outside the gate (needed for "Ball detected" UI during Stage 3). Also added `_tracker.reset()` in `_startCalibration()` to clear trail dots on re-calibrate.

**Verified:** 81/81 tests passing. Device-verified on iPhone 12 and Realme 9 Pro+.
