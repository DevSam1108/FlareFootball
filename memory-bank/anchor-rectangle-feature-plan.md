# Anchor Rectangle Feature — Step-by-Step Plan

> **Status:** Design phase — no code written yet. Each phase to be discussed and agreed in full before implementation.
>
> **Goal:** Eliminate false positives by restricting detection to a player-defined anchor zone on the ground, so the app only ever tracks the one ball the player has chosen for the session.
>
> **Origin:** Ground testing 2026-04-17 revealed that decision logic, session lock stuck state, and false positives are the three core remaining issues. This plan targets false positives. Decision logic and session lock fixes are tracked separately.

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

**What this phase adds:**
- On tap-lock, compute rectangle (60×30 cm → pixels via ball-bbox scaling)
- Rectangle center = tapped ball's bbox center
- Long side = horizontal (to accommodate ball + marker layout)
- Draw rectangle overlay on screen
- Remaining red boxes on other balls disappear once locked

**What this phase does NOT touch:**
- Detection is still global (rectangle drawn but not used for filtering yet)
- Pipeline runs as before

**Outcome:** Visual confirmation on the field — player can see if rectangle size feels right before any filtering is turned on.

**Open questions:**
- Rectangle color/stroke style?
- Rectangle orientation — horizontal in screen space, or follow target orientation from calibration corners?

---

## Phase 3 — Rectangle Filter During Waiting State (Core FP Elimination)

**What this phase adds:**
- During waiting state: detections outside rectangle dropped before reaching BallIdentifier / ByteTrack
- Detections inside rectangle proceed normally
- Filter turns OFF when kick detector transitions to `confirming`
- Filter turns ON again after decision is announced

**What this phase does NOT touch:**
- Kick detector, impact detector (receive fewer detections but logic unchanged)
- Session lock + Mahalanobis rescue (unchanged)

**Outcome:** **False positives are eliminated at the source.** Orange cones, ground-level objects, bounced-back balls — all filtered unless inside rectangle.

**Open questions:**
- If locked trackID AND a non-locked detection both inside rectangle, what wins? (Likely: only locked trackID matters.)
- What if locked ball drifts outside rectangle before kick (wind, slope)? Re-announce "bring back"?

---

## Phase 4 — Return-to-Anchor After Decision

**What this phase adds:**
- After decision + result display ends, app enters "waiting for ball return" state
- Rectangle filter turns on again
- New ball detection inside rectangle evaluated:
  - Partially inside → announce "Ball far from locked position, bring closer to the marker"
  - Fully inside + stable for N frames → lock onto new trackID, cycle repeats

**What this phase does NOT touch:**
- Anchor rectangle position (stays where it was set — does not move between kicks)

**Outcome:** Full cycle: kick → decision → wait → next kick. Indirectly helps the session-lock-stuck issue because waiting state is now well-defined.

**Open questions:**
- Stability frame count N — reuse existing or introduce new?
- Re-announcement cadence for "ball far" — every 2s like tap prompt?

---

## Phase 5 — Audio Announcements & Edge Cases

**What this phase adds:**
- New audio assets: "Tap the ball to continue", "Ball far from locked position, bring closer to the marker", "Ball found, proceed with the kick"
- Wired into AudioService
- Edge cases: re-calibration resets everything, back button cleans up

**What this phase does NOT touch:**
- Anything new — just polish

**Outcome:** Feature-complete anchor rectangle system.

**Open questions:**
- TTS-generated or recorded audio? (Current zone announcements are TTS + crowd cheer composite.)
- "Ball found, proceed with the kick" — every time, or only first lock of session?

---

## Phase Summary

| Phase | Delivers | Testable Standalone |
|---|---|---|
| 1 | Tap-to-lock handshake | Yes — tap works, badge updates |
| 2 | Rectangle drawn on screen | Yes — visual only |
| 3 | **FP elimination via rectangle filter** | Yes — measurable FP drop |
| 4 | Return-to-anchor cycle | Yes — full kick loop |
| 5 | Audio + polish | Yes — UX complete |

---

## Recommended Sequencing

Phases 1 and 2 can be considered together (tightly coupled — tap handshake + rectangle visualization), then pause for field test before Phase 3 turns on actual filtering. This catches any rectangle sizing issues before detection is gated.

---

## Out of Scope (Tracked Separately)

- **Decision logic fix** — `direct_zone` reports first entered zone at depth 0.4, not impact zone
- **Session lock safety timeout** — lock persists when no decision fires
- **Trail suppression gaps** — dots appear during brief confirming spurts mid-result-phase

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
