---
phase: 11-kalman-filter-trajectory-tracking
plan: 01
subsystem: ball-tracking
tags: [kalman-filter, math, tdd, dart, pure-dart]
dependency_graph:
  requires: []
  provides: [BallKalmanFilter]
  affects: [lib/services/ball_tracker.dart]
tech_stack:
  added: []
  patterns: [pure-dart-linear-algebra, tdd-red-green, named-records]
key_files:
  created:
    - lib/services/kalman_filter.dart
    - test/kalman_filter_test.dart
  modified: []
decisions:
  - Renamed single-letter Kalman matrix vars (F, P, Q, H, R) to camelCase descriptive names to satisfy Dart linter without compromising readability
  - process_noise_vel = processNoise * 100 -- velocity noise is 100x position noise to model kick dynamics
  - Initial covariance set to 0.1 (position) / 1.0 (velocity) for fast convergence from first measurement
  - Tests require predict/update alternation to estimate velocity (not update-only loop)
metrics:
  duration: ~4 minutes
  completed: 2026-03-09
  tasks_completed: 2
  files_created: 2
  files_modified: 0
requirements:
  - TRAJ-01
---

# Phase 11 Plan 01: BallKalmanFilter -- 4-State Kalman Filter Summary

**One-liner:** Pure Dart 4-state linear Kalman filter (px, py, vx, vy) with inline matrix math for soccer ball position smoothing and velocity estimation.

## What Was Built

`BallKalmanFilter` -- a complete Kalman filter implementation in `lib/services/kalman_filter.dart`:

- **State vector:** [px, py, vx, vy] -- normalized position and velocity per frame
- **State transition:** constant-velocity model (px' = px+vx, py' = py+vy)
- **Measurement model:** direct observation of [px, py] from YOLO detections
- **API:** `predict()`, `update(px, py)`, `position`, `velocity`, `isInitialized`, `reset()`
- **Matrix ops:** all inline, fixed-size -- no external packages, no allocations beyond lists

Test coverage in `test/kalman_filter_test.dart`: 16 tests, all passing.

## TDD Execution

**RED phase (commit 363ac07):** Wrote 16 failing tests covering all specified behaviors:
- Initialization state management
- predict() as safe no-op when uninitialized
- predict() advancing position by velocity
- Multiple consecutive predict() calls accumulating
- update() pulling position toward measurement without teleporting
- Noise smoothing: filtered variance < raw input variance
- Velocity convergence for constant-velocity motion
- reset() clearing all state
- Custom noise parameter acceptance

**GREEN phase (commit 3941b9b):** Implemented BallKalmanFilter:
- All 16 tests pass
- `flutter analyze lib/services/kalman_filter.dart` reports no issues
- 412 lines (min requirement: 80)
- 286 lines of tests (min requirement: 60)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Dart linter violations on single-letter matrix names**
- **Found during:** GREEN phase verification (`flutter analyze`)
- **Issue:** Kalman filter convention uses single-letter names (F, P, Q, H, R) but Dart's `non_constant_identifier_names` / `constant_identifier_names` linters reject them
- **Fix:** Renamed to descriptive camelCase: `_stateTransition` (F), `_covariance` (P), `_processNoiseMat` (Q), `_measurementMat` (H), `_measurementNoiseMat` (R), `_state` (x)
- **Files modified:** `lib/services/kalman_filter.dart`
- **Commit:** 3941b9b

**2. [Rule 1 - Bug] Fixed failing tests due to wrong update-only velocity estimation**
- **Found during:** First GREEN test run (3 tests failing)
- **Issue:** Tests called `update()` multiple times without `predict()` in between; the Kalman filter cannot estimate velocity without a predict step to propagate the previous state
- **Fix:** Updated 3 test cases to use the correct predict/update cycle (call `filter.update()` for first measurement, then `filter.predict(); filter.update()` for subsequent frames)
- **Affected tests:** "predict advances position by velocity", "multiple predict calls accumulate correctly", "velocity converges for constant-velocity motion"
- **Files modified:** `test/kalman_filter_test.dart`
- **Commit:** 3941b9b (same commit, tests and implementation co-fixed)

## Success Criteria Verification

- [x] `flutter test test/kalman_filter_test.dart` passes with 0 failures (16/16)
- [x] `flutter analyze` shows no new errors in kalman_filter.dart
- [x] BallKalmanFilter exposes position, velocity, isInitialized, predict(), update(), reset()
- [x] No external dependencies added to pubspec.yaml

## Self-Check: PASSED

- `lib/services/kalman_filter.dart` -- EXISTS (412 lines, > 80 minimum)
- `test/kalman_filter_test.dart` -- EXISTS (286 lines, > 60 minimum)
- Commit 363ac07 -- FOUND (test RED phase)
- Commit 3941b9b -- FOUND (implementation GREEN phase)
