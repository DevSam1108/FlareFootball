import 'dart:collection' show ListQueue;

import 'package:flutter/painting.dart' show Offset;

import 'package:tensorflow_demo/models/tracked_position.dart';
import 'package:tensorflow_demo/services/kalman_filter.dart';

/// Manages the ball position history for trail rendering.
///
/// Positions are stored in a time-windowed [ListQueue]. Entries older than
/// [trailWindow] are automatically evicted on every [update] or [markOccluded]
/// call. The default window is 1.5 seconds (TRAK-01).
///
/// Ball positions are smoothed by a [BallKalmanFilter] that also predicts
/// through brief occlusions (up to [predictionHorizon] frames). Per-frame
/// velocity is accessible via the [velocity] getter (TRAJ-03).
///
/// When the ball is lost, [markOccluded] inserts Kalman-predicted positions
/// for the first [predictionHorizon] frames, then falls back to occlusion
/// sentinels. After [autoResetThreshold] consecutive missed frames
/// the entire trail is cleared via [reset] (TRAK-05).
///
/// This is a plain Dart class — no Flutter widget dependencies — so it is
/// safe to unit-test in isolation.
class BallTracker {
  /// Duration of the sliding time window. Entries older than this are pruned.
  /// Defaults to 1.5 seconds per TRAK-01.
  final Duration trailWindow;

  /// Number of consecutive missed frames that triggers an automatic [reset].
  /// Resets [_consecutiveMissedFrames] to zero and clears [_history].
  static const int autoResetThreshold = 30;

  /// Maximum number of frames the Kalman filter will predict through during
  /// occlusion before falling back to sentinel behavior. ~170ms at 30fps.
  static const int predictionHorizon = 5;

  /// Minimum squared-distance (in normalized coordinates) between consecutive
  /// trail positions. If the new position is closer than this to the last
  /// recorded position, it is silently dropped to prevent dot-clustering
  /// during slow ball movement. 0.005² = 0.000025 ≈ 0.5% of frame.
  static const double _minDistSq = 0.000025;

  final _history = ListQueue<TrackedPosition>();
  final BallKalmanFilter _kalman = BallKalmanFilter();

  /// Counts consecutive frames where no ball was detected.
  /// Reset to 0 in [update] (ball found) and [reset] (manual/auto clear).
  /// Incremented in [markOccluded] (ball missing).
  /// Never modified inside [_prune] — see research Pitfall 3.
  int _consecutiveMissedFrames = 0;

  BallTracker({
    this.trailWindow = const Duration(seconds: 1, milliseconds: 500),
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Unmodifiable snapshot of the current trail history.
  ///
  /// Painters must not mutate the queue directly. Iterate this list and break
  /// the polyline wherever [TrackedPosition.isOccluded] is true.
  List<TrackedPosition> get trail => List.unmodifiable(_history);

  /// Number of consecutive missed frames before the "Ball lost" badge is shown.
  ///
  /// Must be less than [autoResetThreshold] (30). At 30 fps, 3 frames ≈ 100 ms,
  /// which satisfies the PLSH-01 requirement of badge appearing "within a few
  /// frames" of the ball leaving view.
  static const int ballLostThreshold = 3;

  /// Returns true when the ball has been missing for [ballLostThreshold] or more
  /// consecutive frames.
  ///
  /// Used by the live detection screen to show the "Ball lost" badge. Resets to
  /// false automatically on the next [update] call when the ball is re-detected.
  bool get isBallLost => _consecutiveMissedFrames >= ballLostThreshold;

  /// Returns the [normalizedCenter] of the most recent non-occluded entry,
  /// or null if no such entry exists.
  ///
  /// Used by the screen as a tiebreaker when multiple YOLO detections arrive
  /// in the same frame (TRAK-04 nearest-neighbour logic).
  Offset? get lastKnownPosition {
    for (final entry in _history.toList().reversed) {
      if (!entry.isOccluded) return entry.normalizedCenter;
    }
    return null;
  }

  /// Current Kalman-estimated velocity as an Offset (vx, vy) in normalized
  /// units per frame. Returns null if the filter is not yet initialized.
  ///
  /// Used by downstream consumers (trajectory extrapolation, impact detection).
  Offset? get velocity {
    if (!_kalman.isInitialized) return null;
    final (:vx, :vy) = _kalman.velocity;
    return Offset(vx, vy);
  }

  /// Current Kalman-smoothed position as an Offset (px, py) in normalized
  /// coordinates. Returns null if the filter is not yet initialized.
  ///
  /// Used by the trajectory extrapolator to get the smoothed position rather
  /// than the raw YOLO detection.
  Offset? get smoothedPosition {
    if (!_kalman.isInitialized) return null;
    final (:px, :py) = _kalman.position;
    return Offset(px, py);
  }

  /// Called when a ball IS detected in the current frame.
  ///
  /// Routes the raw YOLO detection through the Kalman filter for smoothing.
  /// The smoothed position is used for the trail entry and dedup comparison.
  void update(Offset normalizedCenter) {
    _consecutiveMissedFrames = 0;

    // Run Kalman predict + update cycle.
    _kalman.predict();
    _kalman.update(normalizedCenter.dx, normalizedCenter.dy);

    // Use the smoothed position for trail entry.
    final (:px, :py) = _kalman.position;
    final smoothed = Offset(px, py);
    final (:vx, :vy) = _kalman.velocity;

    // De-duplicate: skip if the ball barely moved since last recorded point.
    if (_history.isNotEmpty && !_history.last.isOccluded) {
      final last = _history.last.normalizedCenter;
      final dx = smoothed.dx - last.dx;
      final dy = smoothed.dy - last.dy;
      if (dx * dx + dy * dy < _minDistSq) {
        _prune();
        return;
      }
    }

    _history.addLast(
      TrackedPosition(
        normalizedCenter: smoothed,
        timestamp: DateTime.now(),
        vx: vx,
        vy: vy,
      ),
    );
    _prune();
  }

  /// Called when NO ball is detected in the current frame.
  ///
  /// For the first [predictionHorizon] missed frames, inserts Kalman-predicted
  /// positions to continue the trail through brief occlusions. After that,
  /// falls back to occlusion sentinel behavior. After [autoResetThreshold]
  /// consecutive missed frames the trail is cleared entirely (TRAK-05).
  void markOccluded() {
    _consecutiveMissedFrames++;

    if (_consecutiveMissedFrames >= autoResetThreshold) {
      reset();
      return;
    }

    // During the prediction horizon, use Kalman to extrapolate.
    if (_consecutiveMissedFrames <= predictionHorizon &&
        _kalman.isInitialized) {
      _kalman.predict();
      final (:px, :py) = _kalman.position;
      final (:vx, :vy) = _kalman.velocity;

      _history.addLast(
        TrackedPosition(
          normalizedCenter: Offset(px, py),
          timestamp: DateTime.now(),
          isPredicted: true,
          vx: vx,
          vy: vy,
        ),
      );
      _prune();
      return;
    }

    // Beyond prediction horizon: insert occlusion sentinel (existing behavior).
    if (_history.isNotEmpty && !_history.last.isOccluded) {
      _history.addLast(
        TrackedPosition(
          normalizedCenter: _history.last.normalizedCenter,
          timestamp: DateTime.now(),
          isOccluded: true,
        ),
      );
      _prune();
    }
  }

  /// Clears all history and resets the consecutive-miss counter and Kalman state.
  ///
  /// Called automatically when [_consecutiveMissedFrames] reaches
  /// [autoResetThreshold], or can be called manually (e.g. on screen dispose).
  void reset() {
    _history.clear();
    _consecutiveMissedFrames = 0;
    _kalman.reset();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  /// Removes entries from the front of the queue whose [timestamp] falls
  /// before the current time minus [trailWindow].
  ///
  /// CRITICAL: This method must NOT touch [_consecutiveMissedFrames].
  /// That counter tracks frame-level continuity and is only reset in [update]
  /// and [reset] — resetting it here would mask accumulated miss counts
  /// (see research Pitfall 3).
  void _prune() {
    final cutoff = DateTime.now().subtract(trailWindow);
    while (_history.isNotEmpty &&
        _history.first.timestamp.isBefore(cutoff)) {
      _history.removeFirst();
    }
  }
}
