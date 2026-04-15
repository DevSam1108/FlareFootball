import 'dart:collection' show ListQueue;

import 'package:flutter/painting.dart' show Offset;

import 'package:tensorflow_demo/models/tracked_position.dart';
import 'package:tensorflow_demo/services/bytetrack_tracker.dart';

/// Identifies which [TrackedObject] from the ByteTrack tracker is the soccer
/// ball and maintains trail history for the trail overlay.
///
/// Ball identification rules (in priority order):
/// 1. If the current ball track ID is still alive → follow it.
/// 2. If lost → find the only moving ball-class track → new ball.
/// 3. If no moving tracks → find nearest non-static track to last known position.
///
/// Trail management mirrors the previous [BallTracker] behaviour so that
/// [TrailOverlay] receives the same [List<TrackedPosition>] data contract.
class BallIdentifier {
  /// Ball-class labels accepted from the YOLO model.
  final Set<String> ballClassNames;

  /// Duration of the sliding time window for trail rendering.
  final Duration trailWindow;

  /// Minimum velocity magnitude to consider a track as "moving."
  static const double _motionThreshold = 0.005;

  /// Minimum squared-distance for trail dedup (same as BallTracker._minDistSq).
  static const double _minDistSq = 0.000025;

  /// Consecutive lost frames before "Ball lost" badge.
  static const int ballLostThreshold = 3;

  /// Consecutive lost frames before trail auto-reset.
  static const int autoResetThreshold = 30;

  /// Frames of Kalman prediction during ball loss before switching to sentinels.
  static const int predictionHorizon = 5;

  // ---- State ----

  int? _currentBallTrackId;
  Offset? _lastBallPosition;
  double? _lastBallBboxArea;
  int _consecutiveMissedFrames = 0;
  TrackedObject? _currentBallTrack;

  /// Session lock: when active, BallIdentifier will NOT re-acquire to any
  /// other trackID. Only the currently locked trackID is followed.
  /// Activated on kick detection, deactivated on HIT/MISS/LOST decision.
  bool _sessionLocked = false;

  final ListQueue<TrackedPosition> _trail = ListQueue<TrackedPosition>();

  BallIdentifier({
    this.ballClassNames = const {'Soccer ball', 'ball', 'tennis-ball'},
    this.trailWindow = const Duration(seconds: 1, milliseconds: 500),
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// The current ball track, or null if ball is not visible.
  TrackedObject? get currentBallTrack => _currentBallTrack;

  /// The current ball track ID, or null.
  int? get currentBallTrackId => _currentBallTrackId;

  /// Last known ball position (from the most recent tracked frame).
  Offset? get lastBallPosition => _lastBallPosition;

  /// Last known ball bbox area.
  double? get lastBallBboxArea => _lastBallBboxArea;

  /// Whether the ball is currently being tracked (state == tracked).
  bool get isBallVisible =>
      _currentBallTrack != null &&
      _currentBallTrack!.state == TrackState.tracked;

  /// Whether the ball has been missing for [ballLostThreshold]+ frames.
  bool get isBallLost => _consecutiveMissedFrames >= ballLostThreshold;

  /// Whether the session lock is currently active.
  bool get isSessionLocked => _sessionLocked;

  /// Activate session lock — stop re-acquiring to other trackIDs.
  void activateSessionLock() {
    _sessionLocked = true;
    print('DIAG-BALLID: session lock ACTIVATED (trackId=$_currentBallTrackId)');
  }

  /// Deactivate session lock — allow normal re-acquisition.
  void deactivateSessionLock() {
    _sessionLocked = false;
    print('DIAG-BALLID: session lock DEACTIVATED');
  }

  /// Current ball velocity from the tracker's Kalman state.
  Offset? get velocity => _currentBallTrack?.velocity;

  /// Current ball center (smoothed by the 8-state Kalman).
  Offset? get smoothedPosition => _currentBallTrack?.center;

  /// Trail history for [TrailOverlay]. Same data contract as BallTracker.trail.
  List<TrackedPosition> get trail => List.unmodifiable(_trail);

  /// Lock onto the ball during reference capture.
  ///
  /// Among all ball-class tracks, selects the one with the largest bbox area
  /// (closest to camera). Called when the user taps "Confirm" during reference
  /// capture.
  void setReferenceTrack(List<TrackedObject> tracks) {
    // During reference capture, accept ANY ball-class tracked detection —
    // including static ones. The real ball may have been stationary on the
    // ground for 1000+ frames and ByteTrack would have flagged it static.
    // The static filter is for live play, not for setup.
    final ballTracks = tracks
        .where((t) =>
            ballClassNames.contains(t.className) &&
            t.state == TrackState.tracked)
        .toList();
    if (ballTracks.isEmpty) return;

    // Largest bbox = closest to camera = the real ball
    ballTracks.sort((a, b) => b.bboxArea.compareTo(a.bboxArea));
    _currentBallTrackId = ballTracks.first.trackId;
    _currentBallTrack = ballTracks.first;
    _lastBallPosition = ballTracks.first.center;
    _lastBallBboxArea = ballTracks.first.bboxArea;
    _consecutiveMissedFrames = 0;
  }

  /// Update ball identification from the latest ByteTrack output.
  ///
  /// Call this every frame with the full list of tracked objects.
  void updateFromTracks(List<TrackedObject> tracks) {
    // Filter to ball-class tracks only
    final ballTracks = tracks
        .where((t) => ballClassNames.contains(t.className))
        .toList();

    // Priority 1: Follow current ball track ID if still alive
    TrackedObject? ball;
    if (_currentBallTrackId != null) {
      ball = _findTrack(ballTracks, _currentBallTrackId!);
    }

    // Priority 2: Current track lost — find the only moving ball-class track
    // SKIPPED when session lock is active (don't re-acquire during kick).
    if (ball == null && _currentBallTrackId != null && !_sessionLocked) {
      // DIAG: Log when the locked ball track is lost, with all candidates.
      final candidateInfo = ballTracks.map((t) =>
          'id:${t.trackId}(${t.bbox.width.toStringAsFixed(3)}x${t.bbox.height.toStringAsFixed(3)} '
          'ar:${(t.bbox.height > 0 ? t.bbox.width / t.bbox.height : 0).toStringAsFixed(1)} '
          'vel:${t.velocityMagnitude.toStringAsFixed(4)} '
          'static:${t.isStatic} '
          'state:${t.state.name} '
          'c:${t.confidence.toStringAsFixed(2)})').join(', ');
      print('DIAG-BALLID: locked trackId=$_currentBallTrackId LOST. '
          'Searching ${ballTracks.length} ball-class tracks: [$candidateInfo]');
      final movingTracks = ballTracks
          .where((t) =>
              !t.isStatic &&
              t.state == TrackState.tracked &&
              t.velocityMagnitude > _motionThreshold)
          .toList();
      if (movingTracks.length == 1) {
        ball = movingTracks.first;
        print('DIAG-BALLID: re-acquired from trackId=$_currentBallTrackId → '
            'trackId=${ball.trackId} '
            'bbox=(${ball.bbox.width.toStringAsFixed(3)}x${ball.bbox.height.toStringAsFixed(3)}) '
            'ar:${(ball.bbox.height > 0 ? ball.bbox.width / ball.bbox.height : 0).toStringAsFixed(1)} '
            'at (${ball.center.dx.toStringAsFixed(3)}, ${ball.center.dy.toStringAsFixed(3)}) '
            'vel=${ball.velocityMagnitude.toStringAsFixed(4)} '
            'reason=single_moving_track');
        _currentBallTrackId = ball.trackId;
      } else if (movingTracks.isEmpty) {
        print('DIAG-BALLID: no moving tracks found (all static or lost)');
      } else {
        print('DIAG-BALLID: ${movingTracks.length} moving tracks — ambiguous, skipping re-acquisition');
      }
    } else if (ball == null && _currentBallTrackId != null && _sessionLocked) {
      // Session locked — do NOT re-acquire. Ride out the loss.
      print('DIAG-BALLID: locked trackId=$_currentBallTrackId LOST but session lock ACTIVE — skipping re-acquisition');
    } else if (ball == null) {
      // No prior ball ID — first-time search
      final movingTracks = ballTracks
          .where((t) =>
              !t.isStatic &&
              t.state == TrackState.tracked &&
              t.velocityMagnitude > _motionThreshold)
          .toList();
      if (movingTracks.length == 1) {
        ball = movingTracks.first;
        _currentBallTrackId = ball.trackId;
      }
    }

    // Priority 3: No single moving track — find nearest non-static to last position
    // SKIPPED when session lock is active (don't re-acquire during kick).
    if (ball == null && _lastBallPosition != null && !_sessionLocked) {
      final candidates = ballTracks
          .where((t) => !t.isStatic && t.state == TrackState.tracked)
          .toList();
      if (candidates.isNotEmpty) {
        candidates.sort((a, b) {
          final da = _distSq(a.center, _lastBallPosition!);
          final db = _distSq(b.center, _lastBallPosition!);
          return da.compareTo(db);
        });
        ball = candidates.first;
        print('DIAG-BALLID: re-acquired from trackId=$_currentBallTrackId → '
            'trackId=${ball.trackId} '
            'bbox=(${ball.bbox.width.toStringAsFixed(3)}x${ball.bbox.height.toStringAsFixed(3)}) '
            'ar:${(ball.bbox.height > 0 ? ball.bbox.width / ball.bbox.height : 0).toStringAsFixed(1)} '
            'at (${ball.center.dx.toStringAsFixed(3)}, ${ball.center.dy.toStringAsFixed(3)}) '
            'dist=${_distSq(ball.center, _lastBallPosition!).toStringAsFixed(6)} '
            'reason=nearest_non_static');
        _currentBallTrackId = ball.trackId;
      }
    }

    _currentBallTrack = ball;

    // Update position/bbox tracking and trail.
    if (ball != null && ball.state == TrackState.tracked) {
      _consecutiveMissedFrames = 0;
      _lastBallPosition = ball.center;
      _lastBallBboxArea = ball.bboxArea;
      _addTrailEntry(ball.center, ball.velocity, isPredicted: false);
    } else if (ball != null && ball.state == TrackState.lost) {
      _consecutiveMissedFrames++;
      if (_consecutiveMissedFrames >= autoResetThreshold) {
        _resetTrail();
      } else if (_consecutiveMissedFrames <= predictionHorizon) {
        _addTrailEntry(ball.center, ball.velocity, isPredicted: true);
      } else {
        _addOcclusionSentinel();
      }
    } else {
      _consecutiveMissedFrames++;
      if (_consecutiveMissedFrames >= autoResetThreshold) {
        _resetTrail();
      } else {
        _addOcclusionSentinel();
      }
    }

    _pruneTrail();
  }

  /// Reset all state (called on re-calibration or dispose).
  void reset() {
    _currentBallTrackId = null;
    _currentBallTrack = null;
    _lastBallPosition = null;
    _lastBallBboxArea = null;
    _consecutiveMissedFrames = 0;
    _sessionLocked = false;
    _trail.clear();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  TrackedObject? _findTrack(List<TrackedObject> tracks, int id) {
    for (final t in tracks) {
      if (t.trackId == id &&
          (t.state == TrackState.tracked || t.state == TrackState.lost)) {
        return t;
      }
    }
    return null;
  }

  double _distSq(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return dx * dx + dy * dy;
  }

  void _addTrailEntry(Offset center, Offset velocity,
      {required bool isPredicted}) {
    if (_trail.isNotEmpty && !_trail.last.isOccluded) {
      final last = _trail.last.normalizedCenter;
      if (_distSq(center, last) < _minDistSq) return;
    }

    _trail.addLast(TrackedPosition(
      normalizedCenter: center,
      timestamp: DateTime.now(),
      isOccluded: false,
      vx: velocity.dx,
      vy: velocity.dy,
      isPredicted: isPredicted,
    ));
  }

  void _addOcclusionSentinel() {
    _trail.addLast(TrackedPosition(
      normalizedCenter: _lastBallPosition ?? Offset.zero,
      timestamp: DateTime.now(),
      isOccluded: true,
      isPredicted: false,
    ));
  }

  void _pruneTrail() {
    final cutoff = DateTime.now().subtract(trailWindow);
    while (_trail.isNotEmpty && _trail.first.timestamp.isBefore(cutoff)) {
      _trail.removeFirst();
    }
  }

  void _resetTrail() {
    _trail.clear();
    _consecutiveMissedFrames = 0;
  }
}
