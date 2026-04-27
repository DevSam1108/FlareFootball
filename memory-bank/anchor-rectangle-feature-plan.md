# Anchor Rectangle Feature — Step-by-Step Plan

> **Status (2026-04-24):** Phases 1, 2, 3, and 5 implemented and iOS-verified on iPhone 12. **Phase 3 polish** (false-alarm recovery via `else if`, resting-ball orange dot, enriched per-frame log) landed 2026-04-22 and field-proven. **Phase 4 evaluated and SKIPPED as a standalone phase** — its mechanics are already implicit in Phase 3 + Mahalanobis rescue. **Phase 5 shipped in four atomic commits 2026-04-23 → 2026-04-24** with scope reduced to two prompts (tap-prompt + "Ball in position"); the "Ball far, bring closer" nudge from skipped Phase 4 was deferred pending field evidence it's needed (ADR-079). Two flow-gap bugs surfaced and were fixed in the same session (ISSUE-032 / ADR-081, ISSUE-033 / ADR-082). Android (Realme 9 Pro+) verification still pending for all phases.
>
> **Goal:** Eliminate false positives by restricting detection to a player-defined anchor zone on the ground, so the app only ever tracks the one ball the player has chosen for the session.
>
> **Origin:** Ground testing 2026-04-17 revealed that decision logic, session lock stuck state, and false positives are the three core remaining issues. This plan targets false positives. Decision logic and session lock fixes are tracked separately.
>
> **Result to date:** The #1 field-test blocker — target circle false positives (ISSUE-022) — is now silently dropped on every frame at their fixed banner positions, confirmed in multiple iPhone 12 field runs (2026-04-22). The rectangle filter is the first spatial filter in the pipeline and sits cleanly upstream of ByteTrack without modifying any existing FP defence. Phase 5's two audio prompts (tap-prompt + "Ball in position") close out the player-feedback loop; remaining work on the feature is Android verification and an optional revisit of the deferred "Ball far" nudge.
>
> **What is NOT addressed by this feature plan:** ImpactDetector decision-timing fix (directZone fires mid-flight at zone 1, not impact zone) — this is now the project's #1 blocker but is orthogonal to anchor-rectangle work. Tracked separately in `activeContext.md`.

---

## Design Philosophy

Instead of rejecting false positives after they're detected, the app only ever accepts detections from the one ball the player has tapped. The detection pipeline is "asleep" outside the anchor rectangle during waiting states, and only "wakes" for full-frame tracking once a real kick begins.

**Core cycle:**
```
Calibrate → Place ball → Tap ball → Rectangle drawn → Wait (rectangle filter ON)
   → Kick confirmed (rectangle filter OFF) → Ball tracked anywhere
   → Decision announced → Return to waiting (rectangle filter ON)
   → Ball placed back near anchor → Stable for N frames → Next kick
```

---

## Agreed Design Decisions

| Decision | Value |
|---|---|
| Anchor rectangle size | 60 cm × 30 cm (real-world) |
| Rectangle pixel sizing method | Option A — ball-bbox scaling (ball ≈ 22 cm diameter) |
| Lock condition | Entire bbox inside rectangle (not just center point) |
| Stability before lock | Reuse existing N-frame check |
| Rectangle drawn on screen | Yes (for player visual reference) |
| Rectangle filter active | During waiting states only (OFF during kick flight) |
| Post-decision behavior | Detection restricted to rectangle zone |
| Tap missed → prompt | "Tap the ball to continue" every 2 seconds until tapped |
| Ball partially/outside rectangle | Announce "Ball far from locked position, bring closer to the marker" |
| Ball fully inside rectangle | Announce "Ball found, proceed with the kick" |

---

## Deferred Items

| Item | Reason |
|---|---|
| Camera movement handling | Low-likelihood scenario; revisit after core flow works |

---

## Phase 1 — Tap-to-Lock Interaction (Foundation)

**What this phase adds:**
- After calibration completes, app enters "awaiting ball tap" state
- All ball-class detections get red bounding boxes drawn
- Player taps screen → app snaps tap to nearest ball within `_dragHitRadius` (Tap-2), turns that bbox green; tap on a different ball reassigns (last-tap-wins)
- Player taps Confirm → green bbox commits the trackID into BallIdentifier; pipeline starts
- If no tap within 30s of entering State 2 → audio prompt repeats every 10s until first tap

**What this phase does NOT touch:**
- YOLO detection pipeline (still detects everything)
- Kick detector, impact detector, trail logic
- Session lock (unchanged)

**Outcome:** App knows which ball the player chose. No anchor rectangle yet, no filtering yet — just the tap handshake.

**Resolved decisions (2026-04-17):**

| # | Decision | Choice |
|---|---|---|
| 1 | Lock flow | **B** — Two-step: tap selects, Confirm commits (Confirm button retained, not replaced by tap) |
| 2 | Visual differentiation | **B-α** — Red bbox = unselected, Green bbox = selected (same stroke, only colour changes) |
| 3 | Tap target | **Tap-2** — Inside bbox always wins; otherwise nearest ball whose bbox center is within `_dragHitRadius = 0.09` (~thumb-width); taps outside that radius are no-ops |
| 4 | State 1 prompt | **S1-a** — "Place ball at kick position, keep it in camera view." |
| 5 | State 2 prompt | "Tap the ball you want to use" |
| 6 | State 3 prompt | "Tap Confirm to proceed with selected ball." |
| 7 | Audio nudges | **Audio-2** — State 2 only; 30s grace before first nudge, 10s repeat; nudge timer restarts from zero on every State 1↔2 transition; stops on first tap |
| 8 | Re-calibration mid-session | **Recal-1** — Full reset (corners + tap selection + BallIdentifier state) |
| 9 | Tap a different ball before Confirm | **A-i** — Last tap wins; previous green reverts to red, new tap turns green |
| 10 | Selected ball disappears before Confirm | **B-i** — Selection clears, Confirm greys out, prompt reverts to State 2; player must re-tap when ball reappears |
| 11 | Locked ball disappears after Confirm | Keep today's behavior unchanged in Phase 1; richer recovery deferred to Phase 4 (Return-to-Anchor) |
| 12 | Gesture overlap (corner drag vs ball tap) | **Gesture-1** — Trust Flutter's gesture arena; `onTap` + `onPanStart` coexist on the same `GestureDetector`. Tap-up without movement = ball select; movement = corner drag. No special carve-out for overlapping regions. |

**Player flow (4 visible states):**

1. **State 1 — Waiting for ball.** Prompt: "Place ball at kick position, keep it in camera view." No bboxes drawn. No audio. Confirm button disabled.
2. **State 2 — Ball(s) detected, none selected.** All ball-class tracks (TrackState.tracked) get **red** bboxes. Prompt: "Tap the ball you want to use." Confirm button disabled. After 30s of no tap, audio "Tap the ball to continue" plays and repeats every 10s until first tap. State 1→2 transition restarts the 30s timer from zero.
3. **State 3 — Ball selected, awaiting Confirm.** Tapped ball's bbox turns **green**; other ball bboxes stay red. Prompt: "Tap Confirm to proceed with selected ball." Confirm button enabled. Re-tap on a different ball reassigns selection (last-tap-wins). If the selected ball's track disappears, drop back to State 2.
4. **State 4 — Confirmed.** All bboxes clear, prompt clears, pipeline starts. Screen returns to today's clean post-Confirm view. Phase 2 will draw the anchor rectangle here; Phase 1 leaves the view empty as today.

---

## Phase 2 — Anchor Rectangle Computation & Display

**Status:** Spec finalized 2026-04-20 (open questions resolved). Implementation not started.

**What this phase adds:**
- On tap-lock (State 4 entry from Phase 1), compute an anchor rectangle from the locked ball's bbox.
- **Size:** `3 × bbox.width` wide × `1.5 × bbox.height` tall, where bbox is the locked ball's bbox at lock time. Multipliers are the starting defaults; tunable on the field.
- **Center:** frozen at the locked ball's bbox center at lock time. Does **not** follow the ball afterwards.
- **Orientation:** axis-aligned to the screen (landscape frame). Long side horizontal.
- **Style:** magenta stroke, dashed, 2 px, no fill.
- **On lock:** the red bboxes drawn on other (non-selected) ball tracks disappear.
- Draw the rectangle as a new overlay above the camera view.

**What this phase does NOT touch:**
- Detection is still global (rectangle drawn but not used for filtering yet)
- Pipeline runs as before

**Lifecycle:**
- Rectangle is drawn continuously from lock (State 4 entry) until recalibration (full reset per Phase 1) or screen exit/dispose.
- It persists through the kick, the decision, and Phase 4's return-to-anchor flow.

**Outcome:** Visual confirmation on the field — player can see if rectangle size feels right before any filtering is turned on.

**Design notes / rationale:**
- **No real-world cm conversion.** Earlier drafts said "60×30 cm via ball-bbox scaling," which implicitly assumed a fixed ball diameter. The architecture never assumes a ball size (see `memory/project_no_fixed_ball_size.md`). Bbox-relative multipliers give correct perspective scaling automatically (the ball's bbox already encodes the ball's depth) without needing a cm reference.
- **Screen-axis-aligned, not target-aligned.** Filtering region is identical either way; screen-aligned keeps the Phase 3 hit test trivially axis-aligned.
- **Frozen, not follow.** "Anchor" is meaningful only if the rectangle is a fixed region. A rectangle that follows the ball cannot filter the ball leaving its area.
- **Magenta dashed.** Distinct from every color currently in use on the screen (red = bbox, green = calibration/confirm, yellow = unlocked track, orange = trail, purple = calibration debug, white/black = chrome). Dashed signals "region" rather than "detection box."

**Resolved open questions (previously listed):**
- Color/stroke style → magenta, dashed, 2 px, no fill.
- Orientation → screen-axis-aligned (landscape frame).

---

## Phase 3 — Rectangle Filter During Waiting State (Core FP Elimination)

**Status:** Implemented and iOS field-verified 2026-04-22 (iPhone 12). Console diagnostics wired; CSV diagnostics deferred as optional follow-up. Android (Realme 9 Pro+) pending.

**Field verification summary (2026-04-22, iPhone 12):**
- Test 1 (ON at lock) — pass.
- Test 2 (filter drops outside-rect decoys) — pass. Log shows `dropped=N passed=M` with per-detection class/center/confidence.
- Test 3b (kick not caught) — pass. Filter stayed ON throughout; locked track died cleanly; recovery on ball return worked; **target circle false positives (ISSUE-022) visibly dropped every frame at fixed positions (~0.5, 0.45)** — confirms Phase 3 is silently killing the #1 field-test blocker.
- Test 3 (normal kick, soft) — pass. Full `ON → OFF (confirming) → ON (decision accepted)` cycle observed. Safety timer armed and correctly un-fired because decision came within 2 s. Reject-path re-arm also observed for a phantom kick where KickDetector stayed idle but ImpactDetector fired `noResult`.
- Test 4 (safety timeout fire) — not triggered in this session; deferred to opportunistic observation during normal play. No active reproduction required.
- Tests 5 & 6 (re-calibration reset, screen dispose) — pass. No stale state, no stale timers.

**Open items observed on the field (none block Phase 3):**
- Rect is tight for small balls. Multipliers `3× bbox.width × 1.5× bbox.height` give ~0.09 × 0.06 for a ball of bbox width 0.03 — ball center drifts a few pixels outside the edge in some idle frames and filter drops those. Mahalanobis rescue recovers the track when ball re-enters rect. Consider bumping to 4×/2× if this recurs.
- Reject-path log wording (`ON (decision fired — rejected)`) is emitted even when filter was already ON (no actual transition). Cosmetic; optional to refine.
- Drop log verbosity at ~30 lines/sec during sustained drops (e.g., target circles present every frame). Consider throttling to "only on count change" if console noise becomes a problem.

**What this phase adds:**
- A spatial gate on raw YOLO detections: if a detection's **bbox center** lies outside the anchor rectangle, it is dropped inside `_toDetections` **before reaching ByteTrack**.
- The gate is state-driven (ON/OFF per below) and is the first *spatial* filter in the whole pipeline. All existing FP defenses (class filter, AR > 1.8 reject, Mahalanobis rescue with area-ratio 2.0/0.3, isStatic sliding window, session lock) remain in place — this is additive.
- A 2-second **safety timeout** self-recovers the pipeline when a kick is confirmed but no decision ever fires (today's ISSUE-030 "session lock stuck" scenario).

**What this phase does NOT touch:**
- Kick detector, impact detector, BallIdentifier re-acquisition logic (they simply receive fewer detections; their own logic is unchanged).
- ByteTrack internals (Mahalanobis rescue, 8-state Kalman).
- Trail overlay and debug bbox overlay (they consume from BallIdentifier/ByteTrack and inherit the filter automatically).
- Rectangle geometry — unchanged from Phase 2.

**Hit-test rule:**
- **Center-in-rect.** A detection passes if the center point of its (Android-rotation-corrected) bbox lies inside `_anchorRectNorm`. Any overlap / fully-inside rules were considered and rejected as too loose / too strict for per-frame filtering given the generous `3× width × 1.5× height` Phase 2 rectangle. Ball jitter of 5–10% of bbox width per frame is well within this margin.
- The locked ball is inside the rectangle by construction at lock time, so it passes naturally — **no special bypass for the locked trackID is required.**

**Filter state machine:**

| Trigger | Filter | Session lock |
|---|---|---|
| Phase 2 lock committed (anchor rectangle drawn) | ON | off |
| KickDetector state → `confirming` | **OFF** | on |
| ImpactDetector fires HIT / MISS / NO_RESULT decision | ON | off |
| 2 s elapsed since `confirming` with no decision fired (safety timeout) | ON | off |
| Re-calibration (Recal-1 full reset) | reset — rectangle cleared, filter inactive until next lock | off |

**Timing notes:**
- Re-arm point on the happy path is the **instant the decision fires internally**, not audio start or audio end. This cuts bounce-back FPs (which appear within 100–300 ms of impact) before they can enter ByteTrack.
- Safety timeout is 2 seconds from `confirming`, measured by wall clock. When it fires it re-arms the filter **and** releases the session lock — treating the in-flight kick as dead so BallIdentifier can re-acquire on the next real ball.
- Safety timeout does NOT produce audio in Phase 3. Any "no result, try again" announcement is deferred to Phase 5.

**Scenario analysis (cross-checked with real-play failure modes):**

| Scenario | Today's behavior | With Phase 3 |
|---|---|---|
| Normal kick → decision | Works (zone accuracy caveats separate) | Works; bounce-back & post-impact noise dropped immediately on re-arm |
| Player kicks but KickDetector never transitions to `confirming` | Silent; locked trackID lingers; noise can be re-acquired while waiting | Silent; ball's flight detections dropped (outside rect) → locked trackID dies; when ball is returned **into the rectangle**, BallIdentifier re-acquires cleanly. Ball resting **outside** the rectangle is invisible until returned — by design (Phase 4 formalises this). |
| Ball hits target but ImpactDetector never fires (ISSUE-030) | Session lock stuck; filter would be stuck OFF; pipeline degrades to today's noisy state | After 2 s the safety timeout re-arms the filter and releases session lock; pipeline returns to clean waiting state without operator intervention |

**Diagnostics (required for field verification):**
- **Console `print`:** one line per frame **only when** the filter drops ≥ 1 detection, summarising count dropped vs. passed and current filter state. Tag `DIAG-ANCHOR-FILTER`.
- **DiagnosticLogger CSV:** per-frame column(s) capturing drop count, pass count, and filter state (ON/OFF). Enables post-session analysis of whether real balls were wrongly dropped and which FPs were correctly blocked.
- **Prominent log** on every state transition (ON→OFF, OFF→ON, safety-timeout fire, re-calibration reset) on both console and CSV.

**Resolved open questions (previously listed):**
- Locked trackID vs. non-locked detection both inside rectangle → Priority 1 in BallIdentifier already handles this (locked ID wins); no extra logic needed in the filter.
- Locked ball drifting outside rectangle before kick → judged unrealistic given the `3×1.5` bbox margin. If it ever happens in field testing, handle via Phase 5 audio prompt ("bring closer to marker"), not by extending Phase 3.

**Out of scope for Phase 3 (tracked separately or in later phases):**
- Any audio — deferred to Phase 5.
- Ball-return-to-anchor stability detection — that is Phase 4.
- Changing rectangle geometry or anchor position — Phase 2 owns this.

---

## Phase 4 — Return-to-Anchor After Decision  ❌ SKIPPED (2026-04-22)

**Status:** Evaluated 2026-04-22 after Phase 3 + polish landed. **Decided NOT to implement as a standalone phase.** The mechanics this phase originally intended to add are already working implicitly as a result of Phase 3 + BallIdentifier's Mahalanobis rescue. See ADR-078 for the full rationale.

**Why skipped — what Phase 3 already delivers in production:**
- **"Waiting for ball return" state.** Filter re-arms ON at the decision-fired edge (both accept and reject paths), plus on the idle-edge `else if` branch added during Phase 3 polish. That IS the waiting state — no new sub-state needed.
- **Automatic re-acquisition when ball re-enters rect.** Confirmed in both field runs on 2026-04-22: `trackId=1 LOST` during out-of-rect travel, then `re-acquired from trackId=1 → trackId=N ... reason=nearest_non_static` the instant the ball's center crosses back into the rect. BallIdentifier's existing rescue logic handles it without Phase 4 code.
- **Rectangle persists across kicks.** Already the default behaviour since Phase 2 — `_anchorRectNorm` is only cleared by Recal-1 or screen dispose. No geometry work per kick.
- **Recal-1 during waiting.** Already a full-reset path that clears rect, filter flag, and session lock.

**What Phase 4 would have genuinely added, and where it now lives:**
- **"Ball far, bring closer" voice nudge** with a partially-in-rect predicate → **folded into Phase 5** (it's an audio feature; the predicate is ~5 lines of code that belongs next to the prompt).
- **Explicit `awaiting-return` sub-state** → rejected as ceremony. Nothing downstream needs it.
- **Stability detector on return before re-lock** → rejected. BallIdentifier's existing stability gating handles it; layering a second mechanism would duplicate logic.

**Decision recorded in ADR-078.** Skipping does not lose any field-visible behaviour.

---

## Phase 5 — Audio Announcements & Edge Cases

**Status:** Implemented and iOS-verified on iPhone 12 across four atomic commits (2026-04-23 → 2026-04-24). Scope reduced from three prompts to two during design; the "Ball far, bring closer" nudge (folded in from skipped Phase 4) was deferred pending field evidence it's needed. Android (Realme 9 Pro+) verification pending.

**What shipped (final scope, two prompts):**

1. **Tap-prompt audio (Commit 1, 2026-04-23, ADR-079).**
   - `AudioService.playTapPrompt()` upgraded from Phase 1's `print` stub to real playback of `assets/audio/tap_to_continue.m4a` (Samantha TTS, rate 170, no cheer layer).
   - Per-episode counter + timestamp `print` retained because audio playback can't be verified from screen recordings alone.
   - First fire at t+30 s in State 2; repeats every 10 s until ball tap; counter resets on State 1↔2 transitions.
2. **"Ball in position" announcement (Commit 2, 2026-04-23, ADR-080).**
   - New `AudioService.playBallInPosition()` plays `assets/audio/ball_in_position.m4a` (~1 s; phrase shortened by user 2026-04-24 from "Ball in position, you can kick the ball" to just "Ball in position").
   - Trigger lives **inline in `onResult`** via a single `DateTime? _lastBallInPositionAudio` field driving a 10 s cadence check (user tuned from initial 5 s on 2026-04-24). **No `Timer`, no `_startXxx`/`_cancelXxx` methods** — codified as `feedback_reuse_existing_first.md`.
   - Null-resets in `_startCalibration` (Recal-1) and `dispose`.
3. **State 3→2 audio nudge restart fix (Commit 3, 2026-04-24, ISSUE-032 / ADR-081).**
   - Flow gap: tap selects ball (State 2→3) cancels the nudge timer; if the selected track flickers out of `_ballCandidates`, Decision B-i silently clears `_selectedTrackId` and drops UI back to State 2, but the existing 1↔2 transition block didn't cover the 3→2 case (`hadCandidates == hasCandidates`).
   - Fix: 4 lines — capture `final hadSelection = _selectedTrackId != null;` at top of block, plus a mutually-exclusive `else if (hadSelection && _selectedTrackId == null && hasCandidates) _startAudioNudgeTimer();` branch.
4. **`isStatic` gate on "Ball in position" (Commit 4, 2026-04-24, ISSUE-033 / ADR-082).**
   - Flow gap: a ball rolling through the rect briefly satisfied the geometric `inPosition` conjunction, audio fired on those frames, but ball was already past the rect by the time the speaker played — a non-looking player would kick into a region the spatial filter then drops.
   - Fix: 1 line — added `&& ball.isStatic` (ByteTrack's sliding-30-frame staticness flag) as a fourth clause to the `inPosition` conjunction. Accepts ~1 s warm-up delay between settle and audio fire (desirable: a mid-roll pause won't falsely trigger).

**Deferred (not shipped in Phase 5):**
- **"Ball far from locked position, bring closer to the marker" nudge** (folded in from skipped Phase 4). Per ADR-079, deferred pending field evidence it's needed. Partially-in-rect vs fully-in-rect predicate (~5 lines) was specced but not implemented.
- **"Ball found, proceed with the kick" prompt.** Replaced in scope by the simpler "Ball in position" announcement.

**Verification:**
- `flutter analyze` — 0 errors / 0 warnings / 93 infos (all pre-existing or intentional `avoid_print` for diagnostic prints).
- `flutter test` — 175/175 passing across all four commits. No new tests added — Phase 5 trigger logic lives inline in `onResult`; adding tests would require refactoring the screen for testability, violating `feedback_no_refactor_bundling.md`.
- iOS field-verified on iPhone 12: tap-prompt cadence confirmed in logs; "Ball in position" fired 4 times across ~20 s of gameplay at expected edges (lock, cadence on steady ball, return-to-anchor after each kick); ISSUE-032 and ISSUE-033 reproduced and fixed in same session.

**Implementation footprint:**
- `lib/services/audio_service.dart` — `playTapPrompt` wired, new `playBallInPosition()`.
- `lib/screens/live_object_detection/live_object_detection_screen.dart` — inline trigger, `_lastBallInPositionAudio` field, null-resets, State 3→2 `else if` branch, `isStatic` clause.
- `assets/audio/tap_to_continue.m4a` + `assets/audio/ball_in_position.m4a` (new files).
- All four commits strictly additive — no refactors, no architectural change.

**ADRs:** 079 (scope reduction + asset wiring policy + retained diagnostic print), 080 (timestamp-in-loop pattern), 081 (State 3→2 nudge restart), 082 (isStatic gate).

---

## Phase Summary

| Phase | Delivers | Status |
|---|---|---|
| 1 | Tap-to-lock handshake | ✅ Implemented + iOS-verified 2026-04-19 |
| 2 | Rectangle drawn on screen | ✅ Implemented + iOS-verified 2026-04-20 |
| 3 | **FP elimination via rectangle filter** | ✅ Implemented + iOS-verified 2026-04-22 (+ polish same day). Target-circle FPs (ISSUE-022) killed on every frame in field runs. |
| 4 | Return-to-anchor cycle | ❌ Skipped 2026-04-22 — mechanics already implicit in Phase 3 + Mahalanobis rescue. "Ball far" nudge folded into Phase 5. |
| 5 | Audio + polish (two prompts shipped; "Ball far" nudge deferred) | ✅ Implemented + iOS-verified 2026-04-23 → 2026-04-24 (4 commits, ADR-079/080/081/082) |

**Android (Realme 9 Pro+) verification** pending for all phases.

---

## Recommended Sequencing (historical — for reference)

Phases 1 and 2 were considered together (tightly coupled — tap handshake + rectangle visualization), then field-tested before Phase 3 turned on actual filtering. This caught rectangle sizing behaviour before detection was gated. **Actually followed in practice — worked as planned.**

Phase 3 polish was scoped opportunistically the same day it landed, after a field session surfaced three rough edges. Done as small additive edits (`else if` branch + trail gate relax + log upgrade). **ADR-078 records the rationale.**

Phase 4 skip decision came from re-reading the spec against working Phase 3 code. **ADR-078 records the rationale.**

---

## Out of Scope (Tracked Separately)

- **Decision logic fix** — `direct_zone` stores the FIRST zone the ball entered (not the last/impact zone) AND decisions fire at `trackingFrames=4–5` with `depthRatio≈0.45` — well before the ball reaches wall depth. Both issues re-confirmed in the consecutive-hit field run 2026-04-22 (two back-to-back `HIT zone 1` decisions when the ball actually crossed zones 1 → 6 → 7). **Now the single biggest blocker — promoted to #1 immediate next step in activeContext.md.**
- **Session lock safety timeout** — Phase 3's 2 s safety timer + the Phase 3 polish idle-edge `else if` both release session lock on their paths. The remaining stuck-lock scenario (genuine kick that never produces a decision) may already be mitigated by the Phase 3 safety timeout. Re-evaluate before writing a separate fix.
- **Trail suppression gaps** — Phase 3 polish partially addressed this by re-enabling the orange dot on the resting ball inside the rect. Dots during brief confirming spurts mid-result-phase remain a separate issue.

These are separate work streams and not addressed by this anchor rectangle feature.

---

## Phase 1 Discussion Notes (carry-over from prior session)

### Current flow (as of 2026-04-17, verified from code)

After calibration corners are tapped:
1. `_awaitingReferenceCapture = true` in `live_object_detection_screen.dart`
2. Text shown bottom-right: "Place ball on target — point camera at ball" (ambiguous wording — user flagged this)
3. "Confirm" button shown, greyed out
4. When ball detected → `_referenceCandidateBbox` (singular) populated, red box drawn around one ball, text changes to "Ball detected — tap Confirm", Confirm button turns green
5. Player taps Confirm → `_confirmReferenceCapture()` runs:
   - Saves `_referenceBboxArea`
   - Calls `_ballId.setReferenceTrack(_byteTracker.tracks)` — **auto-picks largest ball-class track (closest to camera)**
   - Exits `_awaitingReferenceCapture`, starts pipeline

### Phase 1 change summary

| Aspect | Stays | Changes | Drops |
|---|---|---|---|
| `_awaitingReferenceCapture` flag | ✅ reuse | — | — |
| Red bbox drawing | ✅ reuse | Extend: show red box on ALL ball detections, not just one | — |
| `_referenceBboxArea` storage | ✅ reuse | — | — |
| Pipeline start after lock | ✅ unchanged | — | — |
| Calibration corner tapping | ✅ unchanged | — | — |
| `_referenceCandidateBbox` (singular) | — | Becomes list of all ball-class tracks (for red bboxes) + a separate `_selectedTrackId` for the green bbox | — |
| Tap handler | — | NEW: `onTap` added alongside existing `onPan*` on the awaiting-state `GestureDetector`. Snap rule: Tap-2 (inside bbox always wins; otherwise nearest within `_dragHitRadius = 0.09`). | — |
| `_ballId.setReferenceTrack()` | — | Receives the tapped track (looked up by `_selectedTrackId`), not auto-picked largest | — |
| "Confirm" button | ✅ retained (B — two-step) | Enable rule changes: enabled iff `_selectedTrackId` is non-null AND that track is currently `tracked` in ByteTrack | — |
| Auto-pick-largest inside setReferenceTrack | — | — | ❌ replaced by user's tap choice |
| Instruction text wording | — | State 1: "Place ball at kick position, keep it in camera view." (S1-a). State 2: "Tap the ball you want to use." State 3: "Tap Confirm to proceed with selected ball." | Current "Place ball on target — point camera at ball" wording dropped |
| Audio nudge | — | NEW: in State 2, `AudioService.playTapPrompt()` (asset TBD in Phase 5) fires after 30s grace, repeats every 10s, stops on first tap. Phase 1 may stub this if audio asset is not yet recorded. | — |

### Open questions — RESOLVED 2026-04-17

1. **Multi-ball behavior today** — ✅ Verified by reading code. `ultralytics_yolo` returns all detections; `_toDetections` (line 583) converts every ball-class detection; ByteTrack's `tracks` list contains all of them. The "pick largest" behavior lives in the screen at lines 596–604 (sort by `bboxArea` descending, take first), not in `BallIdentifier`. `_pickBestBallYolo` does not exist in the current code — that name in CLAUDE.md is stale. Phase 1 will iterate the same ball-class filter to draw red boxes on **all** tracked ball-class tracks.
2. **Final text wording** — ✅ Decisions table rows 4–6.
3. **Tap timeout behavior** — ✅ Decisions table row 7 (Audio-2: 30s grace, 10s repeat, State 2 only, restart on transition).
4. **Re-calibration behavior** — ✅ Decisions table row 8 (Recal-1: full reset).
5. **Snap tolerance** — ✅ Decisions table row 3 (Tap-2: inside bbox always wins; otherwise nearest within `_dragHitRadius = 0.09`).

### New design notes surfaced during 2026-04-17 discussion

- **Gesture coexistence (decisions table row 12):** The awaiting-state `GestureDetector` (line ~1051) currently owns `onPanStart/Update/End` for corner dragging. Phase 1 adds `onTap` to the same widget. Flutter's gesture arena disambiguates automatically (movement → pan, tap-up without movement → tap). No special carve-out needed.
- **`_ReferenceBboxPainter` (line ~1106) becomes a list painter:** Currently paints one bbox; needs to paint a list of `(bbox, color)` pairs — red for unselected, green for the selected track. Selection identity is the **trackID**, not a bbox snapshot — this matches downstream pipeline semantics and lets the green bbox track the ball as it moves slightly between tap and Confirm.
- **State 4 (Confirmed) is unchanged from today:** All overlays clear, prompt clears, pipeline starts. Phase 1 does not touch post-Confirm behavior. The anchor rectangle drawn in this state belongs to Phase 2.

### Key file touched

`lib/screens/live_object_detection/live_object_detection_screen.dart` — all Phase 1 changes live here. `_confirmReferenceCapture()` at line ~521 is the main function to refactor.

### Reminders for next session

- Do NOT write code without explicit user permission
- Discuss Phase 1 fully before touching any file
- Do not touch anything outside the Phase 1 scope
- Decision logic, session lock, and trail suppression are separate — do not conflate
