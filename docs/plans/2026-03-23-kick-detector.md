# Kick Detector Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `KickDetector` service that gates the impact detection pipeline to only process real kicks, filtering out dribbling, carrying, retrieval, and any incidental ball movement between shots.

**Architecture:** A 4-layer signal-processing state machine (`idle → confirming → active → refractory`) built on top of the existing Kalman-filtered velocity. Layer 1 detects explosive onset via jerk (the physics signature of a kick). Layer 2 confirms the ball is actually in sustained motion (not a bounce). Layer 3 verifies the ball is moving toward the goal. Layer 4 enforces a post-kick cooldown to prevent double-firing. The `ImpactDetector.processFrame()` is only called when `KickDetector.isKickActive` is true.

**Tech Stack:** Dart — pure signal processing on `BallTracker.velocity` (already Kalman-filtered). No new packages. Flutter test framework for unit tests.

---

## Background: What Each Layer Does

| Layer | Signal | Eliminates |
|---|---|---|
| Jerk gate | `\|accel[t] - accel[t-1]\|` spike in 1-2 frames | Dribbling, carrying (gradual velocity changes) |
| Energy sustain | Speed stays above floor for 3+ frames after spike | Single-frame YOLO outliers, ball-wall bounces |
| Direction toward goal | `dot(velocity, goalCenter - ballPos) > 0` | Retrievals, lateral movement, kicks away from goal |
| Refractory period | 20-frame cooldown after kick completes | Double-counting, between-shot carry noise |

**Why jerk, not just peak velocity?**
A fast dribble can briefly reach the same peak speed as a gentle kick. Jerk (rate of acceleration change) captures *how fast* the speed was reached — a kick impulse goes 0→max in 1-2 frames, a dribble ramps up over 5-10 frames. This is the #1 discriminating feature from sports analytics literature.

---

## State Machine

```
idle ──[jerk spike]──► confirming ──[sustain OK + toward goal]──► active ──[kick complete]──► refractory
  ▲                         │                                         │                            │
  │                    [sustain fail]                           [ball lost]                        │
  │                    [wrong dir]                                                                 │
  └────────────────────────────────────────────────────────────[20 frames]──────────────────────►┘
```

State definitions:
- **`idle`**: Monitoring for kick onset. Nothing sent to ImpactDetector.
- **`confirming`**: Jerk spike seen. Accumulating sustain frames (max 8 frames to confirm).
- **`active`**: Kick confirmed. `isKickActive = true`. ImpactDetector receives every frame.
- **`refractory`**: Kick window ended. 20-frame cooldown. Nothing sent to ImpactDetector.

---

## Key Constants (all tunable)

```dart
static const double minJerkForKick = 0.020;   // normalized/frame — jerk spike threshold
static const double minSpeedForKick = 0.015;  // normalized/frame — minimum speed during sustain
static const int sustainFramesRequired = 3;   // frames of high speed needed to confirm kick
static const int maxConfirmingFrames = 8;     // max frames to wait for sustain before giving up
static const int maxActiveMissedFrames = 5;   // frames ball is lost before kick window ends
static const int refractoryFrames = 20;       // frames of cooldown after kick ends
```

**Tuning guide (for real-world testing):**
- If real kicks are missed → lower `minJerkForKick` or `minSpeedForKick`
- If dribbles trigger → raise `minJerkForKick` or `sustainFramesRequired`
- If retrievals trigger → check direction filter (ensure zoneMapper is calibrated)
- If two detections per kick → raise `refractoryFrames`

---

## Task 1: Create KickDetector service

**Files:**
- Create: `lib/services/kick_detector.dart`

**Step 1: Create the file with state enum and class skeleton**

```dart
import 'dart:math' show sqrt;
import 'dart:ui' show Offset;

/// States of the kick detection state machine.
enum KickState {
  /// Waiting for kick onset. Nothing sent to ImpactDetector.
  idle,

  /// Jerk spike detected. Accumulating sustain frames to confirm.
  confirming,

  /// Kick confirmed. ImpactDetector is receiving frames.
  active,

  /// Post-kick cooldown. No new kicks accepted.
  refractory,
}

/// Detects real soccer kicks from Kalman-filtered ball velocity.
///
/// Uses 4 layers of signal processing:
/// 1. Jerk gate: explosive onset in 1-2 frames (the physics of a kick impulse)
/// 2. Energy sustain: high speed maintained for [sustainFramesRequired] frames
/// 3. Direction filter: ball moving toward the calibrated goal center
/// 4. Refractory period: [refractoryFrames] cooldown after kick completes
///
/// Only returns [isKickActive] = true when all conditions are satisfied.
/// Plug [isKickActive] into the ImpactDetector gate in the screen.
///
/// This is a plain Dart class — no Flutter dependencies — safe to unit-test.
class KickDetector {
  // ---------------------------------------------------------------------------
  // Tunable thresholds
  // ---------------------------------------------------------------------------

  /// Minimum jerk magnitude to count as kick onset.
  /// Jerk = |accel[t] - accel[t-1]| where accel = |speed[t] - speed[t-1]|.
  /// Raise to ignore weak contacts; lower if real kicks are missed.
  static const double minJerkForKick = 0.020;

  /// Minimum speed (vel_mag) during sustain window.
  /// Ball must be moving this fast every frame after the jerk spike.
  static const double minSpeedForKick = 0.015;

  /// Frames of sustained high speed required to confirm a kick.
  static const int sustainFramesRequired = 3;

  /// Maximum frames allowed in confirming state before giving up.
  static const int maxConfirmingFrames = 8;

  /// Frames ball can be lost (no YOLO detection) before kick window ends.
  static const int maxActiveMissedFrames = 5;

  /// Frames of cooldown after a kick window ends. Prevents double-firing.
  static const int refractoryFrames = 20;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  KickState _state = KickState.idle;
  int _sustainCount = 0;
  int _confirmingFrames = 0;
  int _refractoryCount = 0;
  int _activeMissedFrames = 0;

  double _prevSpeed = 0.0;
  double _prevAccel = 0.0;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Current state of the state machine. Read for logging/debugging.
  KickState get state => _state;

  /// True when a real kick is confirmed and in progress.
  /// Gate ImpactDetector.processFrame() behind this.
  bool get isKickActive => _state == KickState.active;

  /// Process one frame of ball detection data.
  ///
  /// [ballDetected] -- true if YOLO detected a ball this frame.
  /// [velocity]     -- Kalman-filtered velocity (vx, vy), or null.
  /// [ballPosition] -- current ball position in camera-normalized space.
  /// [goalCenter]   -- goal center in camera-normalized space.
  ///                   Compute as: homography.inverseTransform(Offset(0.5, 0.5))
  ///                   Pass null if not yet calibrated (direction check skipped).
  void processFrame({
    required bool ballDetected,
    Offset? velocity,
    Offset? ballPosition,
    Offset? goalCenter,
  }) {
    switch (_state) {
      case KickState.refractory:
        _refractoryCount++;
        if (_refractoryCount >= refractoryFrames) {
          _state = KickState.idle;
          _refractoryCount = 0;
        }
        return;

      case KickState.idle:
        if (!ballDetected || velocity == null) return;
        final speed = _speedOf(velocity);
        final accel = (speed - _prevSpeed).abs();
        final jerk = (accel - _prevAccel).abs();
        _prevAccel = accel;
        _prevSpeed = speed;

        if (jerk >= minJerkForKick && speed >= minSpeedForKick) {
          _state = KickState.confirming;
          _sustainCount = 1; // This frame counts as first sustain frame.
          _confirmingFrames = 0;
        }
        return;

      case KickState.confirming:
        _confirmingFrames++;

        if (!ballDetected || velocity == null) {
          // Ball lost during confirming — not a clean kick onset.
          _resetToIdle();
          return;
        }

        final speed = _speedOf(velocity);
        _prevSpeed = speed;

        if (speed >= minSpeedForKick) {
          _sustainCount++;
        } else {
          // Speed dropped — not sustained. Reset.
          _resetToIdle();
          return;
        }

        // Check direction toward goal if calibrated.
        if (goalCenter != null && ballPosition != null) {
          if (!_isMovingTowardGoal(velocity, ballPosition, goalCenter)) {
            _resetToIdle();
            return;
          }
        }

        if (_sustainCount >= sustainFramesRequired) {
          _state = KickState.active;
          _activeMissedFrames = 0;
          return;
        }

        if (_confirmingFrames >= maxConfirmingFrames) {
          // Took too long to confirm — not an explosive kick.
          _resetToIdle();
        }
        return;

      case KickState.active:
        if (!ballDetected) {
          _activeMissedFrames++;
          if (_activeMissedFrames >= maxActiveMissedFrames) {
            onKickComplete();
          }
        } else {
          _activeMissedFrames = 0;
          if (velocity != null) _prevSpeed = _speedOf(velocity);
        }
        return;
    }
  }

  /// Call when ImpactDetector fires a result (hit/miss/noResult).
  /// Transitions to refractory period immediately.
  void onKickComplete() {
    _state = KickState.refractory;
    _refractoryCount = 0;
    _sustainCount = 0;
    _confirmingFrames = 0;
    _activeMissedFrames = 0;
  }

  /// Full reset to idle. Call on re-calibration or screen dispose.
  void reset() {
    _state = KickState.idle;
    _sustainCount = 0;
    _confirmingFrames = 0;
    _refractoryCount = 0;
    _activeMissedFrames = 0;
    _prevSpeed = 0.0;
    _prevAccel = 0.0;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  double _speedOf(Offset velocity) =>
      sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy);

  /// Returns true if velocity direction points toward the goal center.
  /// Uses dot product: positive = same general direction = toward goal.
  bool _isMovingTowardGoal(
    Offset velocity,
    Offset ballPosition,
    Offset goalCenter,
  ) {
    final toGoalX = goalCenter.dx - ballPosition.dx;
    final toGoalY = goalCenter.dy - ballPosition.dy;
    final dot = velocity.dx * toGoalX + velocity.dy * toGoalY;
    return dot > 0.0;
  }

  void _resetToIdle() {
    _state = KickState.idle;
    _sustainCount = 0;
    _confirmingFrames = 0;
    _prevSpeed = 0.0;
    _prevAccel = 0.0;
  }
}
```

**Step 2: Verify it compiles**

```bash
flutter analyze lib/services/kick_detector.dart
```

Expected: no errors.

---

## Task 2: Write unit tests for KickDetector

**Files:**
- Create: `test/kick_detector_test.dart`

**Step 1: Write the test file**

```dart
import 'dart:ui' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/services/kick_detector.dart';

/// Simulates N frames with the given velocity and ball/goal positions.
void _feedFrames(
  KickDetector detector,
  int count, {
  bool ballDetected = true,
  Offset velocity = const Offset(0.05, 0.0),
  Offset ballPosition = const Offset(0.5, 0.8),
  Offset goalCenter = const Offset(0.5, 0.4),
}) {
  for (int i = 0; i < count; i++) {
    detector.processFrame(
      ballDetected: ballDetected,
      velocity: velocity,
      ballPosition: ballPosition,
      goalCenter: goalCenter,
    );
  }
}

void main() {
  group('KickDetector', () {
    late KickDetector detector;

    setUp(() {
      detector = KickDetector();
    });

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    test('starts in idle state', () {
      expect(detector.state, KickState.idle);
      expect(detector.isKickActive, false);
    });

    // -------------------------------------------------------------------------
    // Real kick detection
    // -------------------------------------------------------------------------

    test('real kick: jerk spike + sustain + toward goal → active', () {
      // Frame 1: near-zero speed (ball at rest).
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.0),
        ballPosition: const Offset(0.5, 0.8),
        goalCenter: const Offset(0.5, 0.4),
      );
      expect(detector.state, KickState.idle);

      // Frame 2: explosive onset — large jerk spike.
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, -0.03), // high speed, toward goal (dy negative = up)
        ballPosition: const Offset(0.5, 0.78),
        goalCenter: const Offset(0.5, 0.4),
      );
      expect(detector.state, KickState.confirming);

      // Feed sustain frames (speed sustained, toward goal).
      _feedFrames(
        detector,
        KickDetector.sustainFramesRequired,
        velocity: const Offset(0.05, -0.03),
        ballPosition: const Offset(0.5, 0.7),
        goalCenter: const Offset(0.5, 0.4),
      );

      expect(detector.state, KickState.active);
      expect(detector.isKickActive, true);
    });

    // -------------------------------------------------------------------------
    // Jerk gate: dribble should NOT trigger
    // -------------------------------------------------------------------------

    test('slow dribble: low jerk, low speed → stays idle', () {
      // Gradual speed buildup over many frames (dribble pattern).
      for (int i = 0; i < 20; i++) {
        final speed = 0.002 * i; // ramps slowly
        detector.processFrame(
          ballDetected: true,
          velocity: Offset(speed, 0.0),
          ballPosition: const Offset(0.5, 0.8),
          goalCenter: const Offset(0.5, 0.4),
        );
      }
      expect(detector.state, KickState.idle);
      expect(detector.isKickActive, false);
    });

    test('moderate dribble: medium speed but low jerk → stays idle', () {
      // Ball moving at moderate speed with no explosive onset.
      _feedFrames(
        detector,
        30,
        velocity: const Offset(0.012, 0.0), // above minSpeed but low jerk
        ballPosition: const Offset(0.5, 0.6),
        goalCenter: const Offset(0.5, 0.4),
      );
      expect(detector.state, KickState.idle);
    });

    // -------------------------------------------------------------------------
    // Direction filter
    // -------------------------------------------------------------------------

    test('kick away from goal → stays idle / resets', () {
      // Frame 1: near-zero speed.
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.0),
        ballPosition: const Offset(0.5, 0.4), // near goal
        goalCenter: const Offset(0.5, 0.4),
      );

      // Frame 2: explosive onset BUT moving AWAY from goal (positive dy = downward = away).
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.0, 0.05), // moving downward, away from goal
        ballPosition: const Offset(0.5, 0.4),
        goalCenter: const Offset(0.5, 0.4),
      );

      if (detector.state == KickState.confirming) {
        // In confirming state — direction check will fire and reset during sustain.
        _feedFrames(
          detector,
          KickDetector.sustainFramesRequired,
          velocity: const Offset(0.0, 0.05),
          ballPosition: const Offset(0.5, 0.5),
          goalCenter: const Offset(0.5, 0.4),
        );
      }

      // Should never reach active — wrong direction.
      expect(detector.state, isNot(KickState.active));
      expect(detector.isKickActive, false);
    });

    test('direction check skipped when goalCenter is null', () {
      // Without a calibrated goal, direction is not checked.
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.0),
        ballPosition: const Offset(0.5, 0.8),
        goalCenter: null,
      );
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, 0.05), // high speed in any direction
        ballPosition: const Offset(0.5, 0.8),
        goalCenter: null,
      );
      // Should enter confirming even without direction check.
      expect(detector.state, KickState.confirming);
    });

    // -------------------------------------------------------------------------
    // Sustain check
    // -------------------------------------------------------------------------

    test('jerk spike but speed drops immediately → stays idle', () {
      // Frame 1: near-zero.
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.0),
        ballPosition: const Offset(0.5, 0.8),
        goalCenter: const Offset(0.5, 0.4),
      );
      // Frame 2: spike (enters confirming).
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, -0.02),
        ballPosition: const Offset(0.5, 0.78),
        goalCenter: const Offset(0.5, 0.4),
      );
      expect(detector.state, KickState.confirming);

      // Frame 3: speed drops (bounce / single-frame artifact).
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.002, 0.0), // below minSpeedForKick
        ballPosition: const Offset(0.5, 0.77),
        goalCenter: const Offset(0.5, 0.4),
      );
      expect(detector.state, KickState.idle);
    });

    test('jerk spike but ball lost during confirming → resets to idle', () {
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.0),
        ballPosition: const Offset(0.5, 0.8),
        goalCenter: const Offset(0.5, 0.4),
      );
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, -0.02),
        ballPosition: const Offset(0.5, 0.78),
        goalCenter: const Offset(0.5, 0.4),
      );
      expect(detector.state, KickState.confirming);

      // Ball disappears.
      detector.processFrame(
        ballDetected: false,
        velocity: null,
        ballPosition: null,
        goalCenter: const Offset(0.5, 0.4),
      );
      expect(detector.state, KickState.idle);
    });

    // -------------------------------------------------------------------------
    // Refractory period
    // -------------------------------------------------------------------------

    test('onKickComplete transitions to refractory', () {
      // Get to active state.
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.0),
        ballPosition: const Offset(0.5, 0.8),
        goalCenter: const Offset(0.5, 0.4),
      );
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, -0.02),
        ballPosition: const Offset(0.5, 0.78),
        goalCenter: const Offset(0.5, 0.4),
      );
      _feedFrames(
        detector,
        KickDetector.sustainFramesRequired,
        velocity: const Offset(0.05, -0.02),
      );
      expect(detector.state, KickState.active);

      // Kick completes.
      detector.onKickComplete();
      expect(detector.state, KickState.refractory);
      expect(detector.isKickActive, false);
    });

    test('refractory ignores high-jerk movement', () {
      // Get to refractory.
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.0),
        ballPosition: const Offset(0.5, 0.8),
        goalCenter: const Offset(0.5, 0.4),
      );
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, -0.02),
        ballPosition: const Offset(0.5, 0.78),
        goalCenter: const Offset(0.5, 0.4),
      );
      _feedFrames(detector, KickDetector.sustainFramesRequired,
          velocity: const Offset(0.05, -0.02));
      detector.onKickComplete();
      expect(detector.state, KickState.refractory);

      // Simulate another "kick" signal during refractory — should be ignored.
      _feedFrames(
        detector,
        KickDetector.refractoryFrames - 1,
        velocity: const Offset(0.08, -0.05),
        ballPosition: const Offset(0.5, 0.5),
        goalCenter: const Offset(0.5, 0.4),
      );
      expect(detector.state, KickState.refractory);
      expect(detector.isKickActive, false);
    });

    test('returns to idle after full refractory period', () {
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.0),
        ballPosition: const Offset(0.5, 0.8),
        goalCenter: const Offset(0.5, 0.4),
      );
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, -0.02),
        ballPosition: const Offset(0.5, 0.78),
        goalCenter: const Offset(0.5, 0.4),
      );
      _feedFrames(detector, KickDetector.sustainFramesRequired,
          velocity: const Offset(0.05, -0.02));
      detector.onKickComplete();

      _feedFrames(
        detector,
        KickDetector.refractoryFrames,
        velocity: const Offset(0.001, 0.0),
      );
      expect(detector.state, KickState.idle);
    });

    // -------------------------------------------------------------------------
    // Ball loss in active state
    // -------------------------------------------------------------------------

    test('ball lost during active completes kick after threshold', () {
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.0),
        ballPosition: const Offset(0.5, 0.8),
        goalCenter: const Offset(0.5, 0.4),
      );
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, -0.02),
        ballPosition: const Offset(0.5, 0.78),
        goalCenter: const Offset(0.5, 0.4),
      );
      _feedFrames(detector, KickDetector.sustainFramesRequired,
          velocity: const Offset(0.05, -0.02));
      expect(detector.state, KickState.active);

      // Ball disappears (hit goal or out of frame).
      _feedFrames(
        detector,
        KickDetector.maxActiveMissedFrames,
        ballDetected: false,
        velocity: null,
      );
      expect(detector.state, KickState.refractory);
    });

    // -------------------------------------------------------------------------
    // Reset
    // -------------------------------------------------------------------------

    test('reset returns to idle from any state', () {
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, -0.02),
        ballPosition: const Offset(0.5, 0.78),
        goalCenter: const Offset(0.5, 0.4),
      );
      detector.reset();
      expect(detector.state, KickState.idle);
      expect(detector.isKickActive, false);
    });
  });
}
```

**Step 2: Run tests — they should FAIL because the file doesn't exist yet**

```bash
flutter test test/kick_detector_test.dart --reporter=compact
```

Expected: errors about missing file or class.

**Step 3: Create `lib/services/kick_detector.dart` with the code from Task 1**

**Step 4: Run tests again — they should PASS**

```bash
flutter test test/kick_detector_test.dart --reporter=compact
```

Expected: all tests pass. If any fail, read the failure message and tune thresholds or logic before continuing.

**Step 5: Commit**

```bash
git add lib/services/kick_detector.dart test/kick_detector_test.dart
git commit -m "feat: add KickDetector service with jerk+sustain+direction+refractory"
```

---

## Task 3: Add kick_confirmed column to DiagnosticLogger

**Files:**
- Modify: `lib/services/diagnostic_logger.dart`

**Step 1: Add `kickConfirmed` parameter to `logFrame()`**

In `diagnostic_logger.dart`, update the header row and the `logFrame` method:

Change the header line from:
```dart
_sink!.writeln(
  'event_type,timestamp_ms,ball_detected,raw_x,raw_y,bbox_area,'
  'depth_ratio,smoothed_x,smoothed_y,vel_x,vel_y,vel_mag,'
  'phase,direct_zone,extrap_zone,result,zone,reason',
);
```

To:
```dart
_sink!.writeln(
  'event_type,timestamp_ms,ball_detected,raw_x,raw_y,bbox_area,'
  'depth_ratio,smoothed_x,smoothed_y,vel_x,vel_y,vel_mag,'
  'phase,direct_zone,extrap_zone,kick_confirmed,kick_state,'
  'result,zone,reason',
);
```

Add `kickConfirmed` and `kickState` parameters to `logFrame()`:

```dart
void logFrame({
  required bool ballDetected,
  Offset? rawPos,
  double? bboxArea,
  double? depthRatio,
  Offset? smoothedPos,
  Offset? velocity,
  required String phase,
  int? directZone,
  int? extrapZone,
  required bool kickConfirmed,   // NEW
  required String kickState,     // NEW  e.g. 'idle', 'confirming', 'active', 'refractory'
}) {
  if (!_active || _sink == null) return;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final velMag = velocity != null ? velocity.distance.toStringAsFixed(6) : '';
  _sink!.writeln([
    'FRAME',
    ts,
    ballDetected ? '1' : '0',
    rawPos?.dx.toStringAsFixed(4) ?? '',
    rawPos?.dy.toStringAsFixed(4) ?? '',
    bboxArea?.toStringAsFixed(6) ?? '',
    depthRatio?.toStringAsFixed(4) ?? '',
    smoothedPos?.dx.toStringAsFixed(4) ?? '',
    smoothedPos?.dy.toStringAsFixed(4) ?? '',
    velocity?.dx.toStringAsFixed(6) ?? '',
    velocity?.dy.toStringAsFixed(6) ?? '',
    velMag,
    phase,
    directZone?.toString() ?? '',
    extrapZone?.toString() ?? '',
    kickConfirmed ? '1' : '0',   // NEW
    kickState,                    // NEW
    '',
    '',
    '',
  ].join(','));
}
```

**Step 2: Run analyzer**

```bash
flutter analyze lib/services/diagnostic_logger.dart
```

Expected: no errors (the screen will have compile errors until Task 4 — that is OK at this stage).

---

## Task 4: Integrate KickDetector into the screen

**Files:**
- Modify: `lib/screens/live_object_detection/live_object_detection_screen.dart`

This task has 4 sub-steps. Make each change carefully.

### Sub-step A: Add import and field

Add to the import block (after existing imports):
```dart
import 'package:tensorflow_demo/services/kick_detector.dart';
```

Add to `_LiveObjectDetectionScreenState` fields (after `_impactDetector`):
```dart
final _kickDetector = KickDetector();
```

### Sub-step B: Compute goal center helper

Add this private method inside `_LiveObjectDetectionScreenState` (alongside the other helper methods like `_shareLog`):

```dart
/// Returns the goal center in camera-normalized space.
/// This is the inverse-homography of the target center (0.5, 0.5).
/// Returns null if not yet calibrated.
Offset? get _goalCenter {
  if (_homography == null) return null;
  return _homography!.inverseTransform(const Offset(0.5, 0.5));
}
```

### Sub-step C: Gate ImpactDetector behind KickDetector

In the `onResult` callback, find this block:

```dart
// Phase 3: Feed impact detector (only when calibrated).
if (_pipelineLive) {
  final prevPhase = _impactDetector.phase;
  _impactDetector.processFrame(
    ballDetected: ball != null,
    ...
  );
```

Replace the outer `if (_pipelineLive)` block with:

```dart
// Phase 3: Feed kick detector — gates whether impact detector runs.
if (_pipelineLive) {
  _kickDetector.processFrame(
    ballDetected: ball != null,
    velocity: _tracker.velocity,
    ballPosition: rawPosition,
    goalCenter: _goalCenter,
  );

  // Phase 4 (impact detection) only runs during confirmed kick windows.
  if (_kickDetector.isKickActive) {
    final prevPhase = _impactDetector.phase;
    _impactDetector.processFrame(
      ballDetected: ball != null,
      velocity: _tracker.velocity,
      extrapolation: _lastExtrapolation,
      rawPosition: rawPosition,
      bboxArea: ball != null
          ? ball.normalizedBox.width * ball.normalizedBox.height
          : null,
      directZone: rawPosition != null && _zoneMapper != null
          ? _zoneMapper!.pointToZone(rawPosition)
          : null,
    );

    // Audio feedback — play once on transition to result.
    if (prevPhase != DetectionPhase.result &&
        _impactDetector.phase == DetectionPhase.result &&
        _impactDetector.currentResult != null) {
      _audioService.playImpactResult(_impactDetector.currentResult!);

      // Tell kick detector this kick is complete → start refractory.
      _kickDetector.onKickComplete();

      // Log the impact decision.
      final event = _impactDetector.currentResult!;
      final String resultStr;
      final String reason;
      final int? zone;
      switch (event.result) {
        case ImpactResult.hit:
          resultStr = 'HIT';
          zone = event.zone;
          reason = event.targetPoint != null
              ? 'extrapolation'
              : 'depth_verified';
        case ImpactResult.miss:
          resultStr = 'MISS';
          zone = null;
          reason = 'miss';
        case ImpactResult.noResult:
          resultStr = 'noResult';
          zone = null;
          reason = 'no_signal';
      }
      DiagnosticLogger.instance.logDecision(
        result: resultStr,
        zone: zone,
        reason: reason,
      );
    }
  }

  // Log per-frame pipeline state for off-device analysis.
  final depthRatio = (rawPosition != null &&
          _referenceBboxArea != null &&
          _referenceBboxArea! > 0 &&
          ball != null)
      ? (ball.normalizedBox.width *
              ball.normalizedBox.height) /
          _referenceBboxArea!
      : null;
  DiagnosticLogger.instance.logFrame(
    ballDetected: ball != null,
    rawPos: rawPosition,
    bboxArea: ball != null
        ? ball.normalizedBox.width * ball.normalizedBox.height
        : null,
    depthRatio: depthRatio,
    smoothedPos: _tracker.smoothedPosition,
    velocity: _tracker.velocity,
    phase: _impactDetector.phase.name,
    directZone: rawPosition != null && _zoneMapper != null
        ? _zoneMapper!.pointToZone(rawPosition)
        : null,
    extrapZone: _lastExtrapolation?.zone,
    kickConfirmed: _kickDetector.isKickActive,     // NEW
    kickState: _kickDetector.state.name,            // NEW
  );
}
```

### Sub-step D: Reset KickDetector in the right places

In `_startCalibration()`, add `_kickDetector.reset();` alongside the existing resets:
```dart
_kickDetector.reset();
```

In `dispose()`, add `_kickDetector.reset();` alongside `_tracker.reset()`.

**Step 5: Run analyzer**

```bash
flutter analyze
```

Expected: zero errors. If there are errors, fix them before continuing.

**Step 6: Run all tests**

```bash
flutter test --reporter=compact
```

Expected: all tests pass (including the existing test suite).

**Step 7: Commit**

```bash
git add lib/services/kick_detector.dart \
        lib/services/diagnostic_logger.dart \
        lib/screens/live_object_detection/live_object_detection_screen.dart \
        test/kick_detector_test.dart
git commit -m "feat: gate impact detection behind KickDetector kick gate"
```

---

## Task 5: Field test and threshold tuning

This task cannot be automated — it requires a real test session.

**What to do:**
1. Build and run the app: `flutter run`
2. Calibrate as normal
3. Do 5-10 test kicks (mix of aerial and ground)
4. After testing, tap **Share Log** → AirDrop to Mac
5. Open the CSV in Numbers/Excel
6. Filter `kick_confirmed = 1` → verify only real kick frames appear
7. Check DECISION rows → only real kicks should appear

**What to look for:**

| Observation | Likely cause | Tuning |
|---|---|---|
| Real kicks not detected | `minJerkForKick` too high OR `minSpeedForKick` too high | Lower both by 20% |
| Carry/dribble still triggering | `minJerkForKick` too low | Raise by 20% |
| Wrong direction kicks firing | Ball close to goal, direction ambiguous | Check `_goalCenter` computation |
| Two decisions per kick | `refractoryFrames` too low | Raise to 30 |
| Kick detected but decision fires late | `maxActiveMissedFrames` too high | Lower to 3 |

**Key column to study in filtered log:**
- `kick_state` shows `idle → confirming → active` transitions — check timing relative to actual kick
- `vel_mag` during `kick_confirmed=1` rows — verifies threshold is sensible

---

## Summary

| Task | Files | What it does |
|---|---|---|
| 1 | `kick_detector.dart` | Core state machine |
| 2 | `test/kick_detector_test.dart` | 10 unit tests |
| 3 | `diagnostic_logger.dart` | Add kick_confirmed + kick_state columns |
| 4 | `live_object_detection_screen.dart` | Wire kick gate + update log calls |
| 5 | Field test | Tune thresholds |

**Total new code: ~150 lines.** No new packages. No changes to YOLO, Kalman, zone mapping, or audio.
