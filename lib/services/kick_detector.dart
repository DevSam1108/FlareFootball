import 'dart:ui' show Offset;

/// States of the kick detection state machine.
enum KickState {
  /// Waiting for a jerk spike indicating explosive ball onset.
  idle,

  /// Jerk detected; checking energy sustain + direction toward goal.
  confirming,

  /// Kick confirmed — impact detector results should be accepted.
  active,

  /// Cooldown after a kick completes. Ignores all movement.
  refractory,
}

/// 4-layer kick detector built on Kalman-smoothed velocity.
///
/// Layer 1: Jerk gate — explosive onset (idle → confirming)
/// Layer 2: Energy sustain — speed stays high for N frames (confirming → active)
/// Layer 3: Direction toward goal — velocity points at target (checked in confirming)
/// Layer 4: Refractory period — cooldown after kick (active → refractory → idle)
///
/// This is a plain Dart class — no Flutter dependencies — safe to unit-test.
class KickDetector {
  // ---------------------------------------------------------------------------
  // Tuning constants (starting values — adjust via field testing + CSV logs)
  // ---------------------------------------------------------------------------

  /// Jerk threshold to detect explosive onset. Jerk is the rate of change of
  /// acceleration: |accel[t] - accel[t-1]|. Only a real kick produces a large
  /// isolated jerk spike in 1-2 frames.
  static const double jerkThreshold = 0.01;

  /// Minimum velocity magnitude to count as sustained energy.
  static const double sustainThreshold = 0.005;

  /// Consecutive frames of sustained energy needed to confirm a kick.
  static const int sustainFrames = 3;

  /// Max frames in confirming before timing out back to idle.
  static const int maxConfirmingFrames = 8;

  /// Max frames in active before safety-net transition to refractory.
  /// At 30fps this is ~2 seconds — well beyond any real kick flight time.
  /// This is the ONLY exit from active besides onKickComplete().
  /// No missed-frame counter — the kick stays active until the impact
  /// decision is made or this timeout fires.
  static const int maxActiveFrames = 60;

  /// Frames to stay in refractory after a kick completes (~0.67s at 30fps).
  static const int refractoryFrames = 20;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  KickState _state = KickState.idle;

  /// Last 3 velocity magnitudes for jerk computation.
  double _velMag0 = 0, _velMag1 = 0, _velMag2 = 0;

  /// Consecutive frames of sustained energy during confirming.
  int _sustainCount = 0;

  /// Total frames spent in current confirming window.
  int _confirmingFrameCount = 0;

  /// Total frames spent in active state.
  int _activeFrameCount = 0;

  /// Refractory countdown.
  int _refractoryCounter = 0;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Current state of the kick detector.
  KickState get state => _state;

  /// True when a confirmed kick is in progress (state == active).
  bool get isKickActive => _state == KickState.active;

  /// Process one frame of detection data.
  ///
  /// [ballDetected] — true if YOLO detected a ball this frame.
  /// [velocity] — Kalman-smoothed velocity (normalized units/frame), or null.
  /// [ballPosition] — raw normalized ball center, or null.
  /// [goalCenter] — target center in camera space (from homography inverse), or null.
  /// [isImpactTracking] — true if ImpactDetector is currently in tracking phase.
  ///   Used during confirming state: if the ball is lost but ImpactDetector is
  ///   still tracking, the kick confirmation continues (the pipeline is still
  ///   processing the kick). If ImpactDetector has also lost tracking, the
  ///   confirming state resets to idle.
  void processFrame({
    required bool ballDetected,
    Offset? velocity,
    Offset? ballPosition,
    Offset? goalCenter,
    bool isImpactTracking = false,
  }) {
    // Update velocity history for jerk computation.
    _velMag2 = _velMag1;
    _velMag1 = _velMag0;
    _velMag0 = velocity != null ? velocity.distance : 0;

    switch (_state) {
      case KickState.idle:
        _processIdle(ballDetected: ballDetected, velocity: velocity);

      case KickState.confirming:
        _processConfirming(
          ballDetected: ballDetected,
          velocity: velocity,
          ballPosition: ballPosition,
          goalCenter: goalCenter,
          isImpactTracking: isImpactTracking,
        );

      case KickState.active:
        _processActive();

      case KickState.refractory:
        _processRefractory();
    }
  }

  /// Signal that the kick result has been accepted by the impact detector.
  /// Transitions to refractory.
  void onKickComplete() {
    if (_state == KickState.active || _state == KickState.confirming) {
      _enterRefractory();
    }
  }

  /// Reset to idle. Call on recalibration or screen dispose.
  void reset() {
    _state = KickState.idle;
    _velMag0 = 0;
    _velMag1 = 0;
    _velMag2 = 0;
    _sustainCount = 0;
    _confirmingFrameCount = 0;
    _activeFrameCount = 0;
    _refractoryCounter = 0;
  }

  // ---------------------------------------------------------------------------
  // Private state handlers
  // ---------------------------------------------------------------------------

  void _resetToIdle() {
    _state = KickState.idle;
    _sustainCount = 0;
    _confirmingFrameCount = 0;
  }

  void _processIdle({required bool ballDetected, Offset? velocity}) {
    if (!ballDetected || velocity == null) return;

    // Layer 1: Jerk gate — detect explosive onset.
    final jerk = _computeJerk();
    if (jerk > jerkThreshold) {
      _state = KickState.confirming;
      _sustainCount = 1; // current frame counts if speed is high enough
      _confirmingFrameCount = 1;
    }
  }

  void _processConfirming({
    required bool ballDetected,
    Offset? velocity,
    Offset? ballPosition,
    Offset? goalCenter,
    required bool isImpactTracking,
  }) {
    _confirmingFrameCount++;

    // Timeout: too many frames without reaching active → back to idle.
    if (_confirmingFrameCount > maxConfirmingFrames) {
      _resetToIdle();
      return;
    }

    // Ball lost during confirming — stay in confirming as long as the
    // ImpactDetector is still tracking (the pipeline is still processing
    // this kick). Only reset to idle if ImpactDetector has also given up.
    // This replaces a hardcoded missed-frame counter with a dynamic check
    // on the pipeline's actual state.
    if (!ballDetected || velocity == null) {
      if (!isImpactTracking) {
        _resetToIdle();
      }
      return;
    }

    // Layer 2: Energy sustain — speed must stay above threshold.
    if (_velMag0 >= sustainThreshold) {
      _sustainCount++;
    } else {
      // Speed dropped → not a real kick flight.
      _resetToIdle();
      return;
    }

    // Layer 3: Direction toward goal — velocity must point at target.
    final directionValid = _checkDirection(
      velocity: velocity,
      ballPosition: ballPosition,
      goalCenter: goalCenter,
    );

    // Transition to active when all layers pass.
    if (_sustainCount >= sustainFrames && directionValid) {
      _state = KickState.active;
      _activeFrameCount = 0;
      _sustainCount = 0;
      _confirmingFrameCount = 0;
    }
  }

  void _processActive() {
    _activeFrameCount++;

    // Safety net: if active for too long without onKickComplete(), force refractory.
    if (_activeFrameCount >= maxActiveFrames) {
      _enterRefractory();
    }
  }

  void _processRefractory() {
    _refractoryCounter++;
    if (_refractoryCounter >= refractoryFrames) {
      _state = KickState.idle;
      _refractoryCounter = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Compute jerk: rate of change of acceleration.
  /// jerk = |accel[t] - accel[t-1]| where accel[t] = speed[t] - speed[t-1].
  double _computeJerk() {
    final accel0 = _velMag0 - _velMag1;
    final accel1 = _velMag1 - _velMag2;
    return (accel0 - accel1).abs();
  }

  /// Check if velocity direction points toward the goal (within 90° cone).
  /// Returns true if no goal center is available (graceful fallback).
  bool _checkDirection({
    Offset? velocity,
    Offset? ballPosition,
    Offset? goalCenter,
  }) {
    if (velocity == null || ballPosition == null || goalCenter == null) {
      return true; // Can't check direction — allow it.
    }
    final ballToGoal = goalCenter - ballPosition;
    final dot = velocity.dx * ballToGoal.dx + velocity.dy * ballToGoal.dy;
    return dot > 0;
  }

  void _enterRefractory() {
    _state = KickState.refractory;
    _refractoryCounter = 0;
    _activeFrameCount = 0;
  }
}
