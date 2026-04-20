# Active Context

> **CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Current Focus
**Anchor Rectangle Feature — Phase 1 (Tap-to-Lock Interaction) implemented + iOS-verified (2026-04-19).** Replaced the auto-pick-largest reference-capture heuristic with explicit player tap-to-select. Two-step UX retained (tap a red bbox → turns green → Confirm commits the lock). All 12 design decisions resolved on 2026-04-17 and recorded in `memory-bank/anchor-rectangle-feature-plan.md`. iOS field verification passed on iPhone 12 (tap flow + back-button fix). Android (Realme 9 Pro+) verification still pending. Phase 2 (anchor rectangle drawing) not started. Also fixed two back-button z-order bugs (one pre-existing, one Phase 1 regression) and added a per-episode counter + timestamp to the audio nudge stub for log-based cadence verification.

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
- Anchor rectangle drawing (Phase 2 — deferred)
- Detection filter using rectangle (Phase 3 — deferred)
- Return-to-anchor cycle (Phase 4 — deferred)
- Real audio asset for tap prompt (Phase 5 — currently a `print` stub with counter + timestamp for testability)

### On-device verification status

**iOS (iPhone 12) — VERIFIED 2026-04-19**
- [x] Phase 1 tap-to-lock flow works end-to-end
- [x] Back button works in all states (calibration mode, awaiting reference capture, live pipeline)

**Android (Realme 9 Pro+) — PENDING**
- [ ] Re-run the same checklist. Specifically watch for:
  - Gesture arena behaviour (Android touch slop differs from iOS — may affect Tap-2 vs corner-drag disambiguation)
  - Audio nudge cadence in `adb logcat` (`AUDIO-STUB #N` lines, 30 s grace + 10 s repeat, counter resets on State 2→1→2 transition)
  - Recal-1 clears selection + cancels nudge timer
  - No regression on kick detection / zone announcement post-Confirm
  - No phantom corner placed under back button during calibration

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
1. **Android parity verification (Realme 9 Pro+)** — run through the same checklist iOS passed. Gesture arena and touch slop differ from iOS; worth confirming before Phase 2 is layered on top.
2. **Outdoor field test** — real kicking session to see how the 30 s grace + 10 s repeat nudge cadence feels in practice, and whether Tap-2 snap tolerance is right for small/distant ball bboxes.
3. **Start Phase 2 (Anchor Rectangle Computation & Display)** — design discussion first, same structure as Phase 1 (12-decision table, player flow, minimal-delta implementation).
4. **Session lock safety timeout (ISSUE-030)** — auto-deactivate if locked track lost >N frames without a decision. Blocks production but not Phase 2 work.
5. **Field-test analysis of directZone accuracy** — still 0/5 to 5/5 depending on calibration. Needs design rethink once anchor rectangle is in place (Phase 3 filter may indirectly improve by removing upstream noise).
