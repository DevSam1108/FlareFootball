# GSD State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-09)

**Core value:** Real-time soccer ball detection and tracking must run on-device with acceptable speed and accuracy on both iOS and Android
**Current focus:** v1.3 Target Zone Impact Detection -- Phase 11 (Kalman Filter and Trajectory Tracking)

## Current Position

Phase: 11 of 14 (Kalman Filter and Trajectory Tracking)
Plan: 02 (next)
Status: In progress -- Plan 01 complete
Last activity: 2026-03-09 -- Phase 11 Plan 01 complete (BallKalmanFilter TDD)

Progress: [███████████░░░░░░░░░] 50%+ (11/14 phases, 1/N plans in Phase 11)

## Performance Metrics

**v1.1 Velocity:**
- Total plans completed: 6
- Phases: 3 (06, 07, 08)
- Timeline: 2026-02-23 -> 2026-02-24

**v1.2 Velocity:**
- Total plans completed: 4
- Phases: 2 (09, 10)
- Timeline: 2026-02-25 -> 2026-03-09

**v1.3 Velocity:**
- Total plans completed: 1
- Phases: 0 complete, 1 in progress (11)
- Timeline: 2026-03-09 -> ongoing

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 06-overlay-foundation | 2/2 | ~6 min | ~3 min |
| 07-trail-accumulation-and-rendering | 3/3 | ~53 min | ~18 min |
| 08-polish | 1/1 | ~10 min | ~10 min |
| 09-android-inference-diagnosis-and-fix | 2/2 | ~15 min | ~7.5 min |
| 11-kalman-filter-trajectory-tracking | 1/N | ~4 min | ~4 min |

## Accumulated Context

### Decisions

- Manual calibration chosen over retrained YOLO / opencv_dart / dual models
- Multi-signal impact detection (trajectory + depth + edge-filter + velocity)
- Start with 30fps, defer 60fps to avoid platform-specific camera code
- Calibration-based focal length derivation (not camera intrinsics API)
- Phase 1 calibration (homography + grid overlay) device-verified on both platforms
- Kalman matrix vars use descriptive camelCase names (not single-letter F/P/Q/H/R) to satisfy Dart linter
- Velocity noise = processNoise * 100 to model kick dynamics (rapid acceleration)
- Kalman filter velocity estimation requires predict/update alternation per frame

### Pending Todos

None -- Plan 11-01 complete. Ready for Plan 11-02.

### Blockers/Concerns

- Tracking quality described as "very poor" on iPhone 12 -- Kalman filter may help, but could be a model limitation
- Galaxy A32 FPS (~5-20fps on Helio G80) may affect trajectory smoothness

## Session Continuity

Last session: 2026-03-09
Stopped at: Completed 11-01-PLAN.md -- BallKalmanFilter TDD (16 tests, 0 failures)
Resume file: None
