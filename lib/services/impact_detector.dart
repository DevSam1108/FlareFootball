import 'dart:ui' show Offset;

import 'package:tensorflow_demo/models/impact_event.dart';
import 'package:tensorflow_demo/services/kick_detector.dart' show KickState;
import 'package:tensorflow_demo/services/trajectory_extrapolator.dart';
import 'package:tensorflow_demo/utils/diag_log.dart';

/// Phases of the impact detection state machine.
enum DetectionPhase {
  /// Waiting for ball to be detected moving toward target.
  ready,

  /// Ball is being tracked with sufficient velocity.
  tracking,

  /// Impact decision made, displaying result for [resultDisplayDuration].
  result,
}

/// Multi-signal impact detector for target zone hit detection.
///
/// State machine: Ready -> Tracking -> Result -> Ready (after cooldown).
///
/// Uses three signals:
/// 1. **Frame-edge exit filter**: Ball near frame edge -> MISS (flew past).
/// 2. **Depth estimation filter** (Phase 5): Last bbox area vs reference ->
///    ball must reach target depth for a valid HIT.
/// 3. **Trajectory extrapolation**: Does the predicted path intersect the target?
///
/// Velocity magnitudes are accumulated but not gated on.
///
/// This is a plain Dart class -- no Flutter dependencies -- safe to unit-test.
class ImpactDetector {
  /// Minimum frames of tracking before a decision can be made.
  /// At 30fps this is ~100ms of ball flight.
  /// Research basis (ADR-047): Kalman filter velocity converges after 3-4
  /// measurements (Bar-Shalom et al. 2001). Real soccer kicks complete
  /// flight in 6-9 frames at 30fps; requiring 8 rejected 60% of valid kicks.
  static const int minTrackingFrames = 3;

  /// Minimum squared velocity magnitude (normalized units/frame)^2 to enter
  /// tracking mode. 0.003^2 = 0.000009.
  static const double minVelocityMagnitudeSq = 0.000009;

  /// Frame edge threshold: position within this fraction of frame edge is
  /// considered an edge exit (MISS). 8% of frame.
  static const double edgeThreshold = 0.08;

  /// Consecutive missed frames before making an impact decision.
  /// At 30fps this is ~167ms of no ball detection.
  static const int lostFrameThreshold = 5;

  /// Minimum depth ratio (last bbox area / reference bbox area) for a valid
  /// HIT. Below this, the ball never got close enough to the target.
  static const double minDepthRatio = 0.7;

  /// Maximum depth ratio for a valid HIT. Above this, the ball is still
  /// mid-flight (closer to camera than the wall).
  static const double maxDepthRatio = 1.3;

  /// Maximum time in tracking phase before auto-reset to ready.
  /// A kicked ball reaches the target in 0.5-1.5s; 3s is generous margin.
  /// Prevents indefinite stuck-in-tracking states.
  static const Duration maxTrackingDuration = Duration(seconds: 3);

  /// Duration to display result before resetting to ready.
  final Duration resultDisplayDuration;

  ImpactDetector({
    this.resultDisplayDuration = const Duration(seconds: 3),
  });

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  DetectionPhase _phase = DetectionPhase.ready;
  int _trackingFrameCount = 0;
  DateTime? _trackingStartTime;
  int _lostFrameCount = 0;
  final List<double> _velocityHistory = [];
  ExtrapolationResult? _bestExtrapolation;
  Offset? _lastRawPosition;
  ImpactEvent? _currentResult;
  DateTime? _resultTimestamp;

  /// Reference bounding box area captured during calibration. Null before
  /// reference capture. Set via [setReferenceBboxArea].
  double? _referenceBboxArea;

  /// Most recent bbox area observed during the current tracking window.
  /// In behind-kicker camera position, the ball shrinks as it approaches the
  /// target, so the last-seen size (not peak) best represents target depth.
  double _lastBboxArea = 0.0;

  /// Zone number from direct position mapping, verified by depth ratio.
  /// Only set when the ball's position maps to a zone AND depth ratio confirms
  /// the ball is near the wall (not mid-flight passing through the grid region).
  int? _lastDepthVerifiedZone;

  /// Zone predicted by the WallPlanePredictor (perspective-corrected 3D
  /// trajectory extrapolation to wall plane). Takes priority over
  /// depth-verified direct mapping because it accounts for perspective
  /// distortion of mid-flight ball positions.
  int? _lastWallPredictedZone;

  /// Last non-null directZone observed during tracking. This is the ball's
  /// actual position mapped through the homography — no prediction, no
  /// extrapolation. Highest-priority decision signal.
  int? _lastDirectZone;

  /// Peak squared velocity observed during the current tracking window.
  /// Used to detect impact: velocity dropping to <40% of peak = wall hit.
  double _peakVelocitySq = 0.0;

  /// Most recent KickDetector state from the caller, captured at the top of
  /// every [processFrame] call. Used by [_makeDecision] (Piece A, 2026-04-29)
  /// to suppress phantom decisions that fire while no kick is in progress —
  /// e.g., when detection jitter on a stationary ball pushes ImpactDetector
  /// into [DetectionPhase.tracking] and the lost-frame trigger eventually
  /// fires with `kickState == idle`. Defaults to [KickState.confirming] so
  /// callers that don't supply the state (older tests) behave as before
  /// (gate is permissive).
  KickState _currentKickState = KickState.confirming;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Current phase of the state machine.
  DetectionPhase get phase => _phase;

  /// Current impact result, or null if not in result phase.
  ImpactEvent? get currentResult => _currentResult;

  /// Human-readable status text for the UI.
  String get statusText {
    switch (_phase) {
      case DetectionPhase.ready:
        return 'Ready \u2014 waiting for kick';
      case DetectionPhase.tracking:
        return 'Tracking...';
      case DetectionPhase.result:
        if (_currentResult == null) return '';
        switch (_currentResult!.result) {
          case ImpactResult.hit:
            return 'Zone ${_currentResult!.zone}';
          case ImpactResult.miss:
            return 'MISS';
          case ImpactResult.noResult:
            return 'No result';
        }
    }
  }

  /// Process a single frame of detection data.
  ///
  /// [ballDetected] -- true if YOLO detected a ball this frame.
  /// [velocity] -- Kalman-smoothed velocity (normalized units/frame), or null.
  /// [extrapolation] -- current trajectory extrapolation result, or null.
  /// [rawPosition] -- raw (coord-corrected) YOLO detection center, or null.
  void processFrame({
    required bool ballDetected,
    Offset? velocity,
    ExtrapolationResult? extrapolation,
    Offset? rawPosition,
    double? bboxArea,
    int? directZone,
    int? wallPredictedZone,
    KickState kickState = KickState.confirming,
  }) {
    // Capture caller's KickDetector state for this frame. Read by
    // _makeDecision to suppress phantom decisions during idle.
    _currentKickState = kickState;

    // Check cooldown expiration.
    if (_phase == DetectionPhase.result) {
      if (_resultTimestamp != null &&
          DateTime.now().difference(_resultTimestamp!) >=
              resultDisplayDuration) {
        _reset();
      }
      return;
    }

    // Check tracking timeout — self-healing safety net.
    if (_phase == DetectionPhase.tracking &&
        _trackingStartTime != null &&
        DateTime.now().difference(_trackingStartTime!) >= maxTrackingDuration) {
      _reset();
      return;
    }

    if (ballDetected) {
      _onBallDetected(
        velocity: velocity,
        extrapolation: extrapolation,
        rawPosition: rawPosition,
        bboxArea: bboxArea,
        directZone: directZone,
        wallPredictedZone: wallPredictedZone,
      );
    } else {
      // Bug fix (2026-04-28, Path A Change 1): pass directZone through to
      // _onBallMissing so it can keep _lastDirectZone fresh while ByteTrack's
      // track is in `lost` state but still Kalman-predicting positions
      // (which the screen still maps to a directZone every frame). Without
      // this, when fast motion flips the track to `lost` mid-flight, the
      // ball's zone progression (e.g., 1 → 6 → 7) is silently dropped and
      // the lost-frame trigger fires with a stale zone (typically 1).
      _onBallMissing(
        extrapolation: extrapolation,
        directZone: directZone,
        rawPosition: rawPosition,
        bboxArea: bboxArea,
      );
    }
  }

  /// Force reset to ready state. Call when re-calibrating or leaving screen.
  void forceReset() => _reset();

  /// Sets the reference bounding box area from calibration.
  void setReferenceBboxArea(double area) {
    _referenceBboxArea = area;
  }

  /// Clears the reference bounding box area. Call on re-calibration.
  void clearReferenceBboxArea() {
    _referenceBboxArea = null;
  }

  /// Whether a reference bounding box area has been set.
  bool get hasReferenceBboxArea => _referenceBboxArea != null;

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _onBallDetected({
    Offset? velocity,
    ExtrapolationResult? extrapolation,
    Offset? rawPosition,
    double? bboxArea,
    int? directZone,
    int? wallPredictedZone,
  }) {
    _lostFrameCount = 0;
    if (rawPosition != null) _lastRawPosition = rawPosition;
    if (bboxArea != null) {
      _lastBboxArea = bboxArea;
    }

    // Direct zone: ball's actual position mapped through homography.
    // Highest priority — no prediction, just where the ball actually is.
    if (directZone != null) {
      _lastDirectZone = directZone;
    }

    // Wall-predicted zone: perspective-corrected 3D trajectory prediction.
    // Kept as diagnostic data but no longer used for decisions.
    if (wallPredictedZone != null) {
      _lastWallPredictedZone = wallPredictedZone;
    }

    // Depth-verified direct zone: when the ball's position maps to a zone
    // AND depth ratio confirms it's near the wall, store it. Kept as
    // fallback behind wall-predicted zone.
    if (directZone != null &&
        _referenceBboxArea != null &&
        _referenceBboxArea! > 0) {
      final ratio = _lastBboxArea / _referenceBboxArea!;
      if (ratio >= minDepthRatio && ratio <= maxDepthRatio) {
        _lastDepthVerifiedZone = directZone;
      }
    }

    if (velocity == null) return; // Kalman not initialized yet.

    final velMagSq = velocity.dx * velocity.dx + velocity.dy * velocity.dy;
    _velocityHistory.add(velMagSq);
    if (_velocityHistory.length > 20) _velocityHistory.removeAt(0);

    _bestExtrapolation = extrapolation;

    switch (_phase) {
      case DetectionPhase.ready:
        if (velMagSq >= minVelocityMagnitudeSq) {
          _phase = DetectionPhase.tracking;
          _trackingFrameCount = 1;
          _trackingStartTime = DateTime.now();
        }
      case DetectionPhase.tracking:
        _trackingFrameCount++;
        // Track peak velocity and detect impact via velocity drop.
        if (velMagSq > _peakVelocitySq) _peakVelocitySq = velMagSq;
        // DIAG (additive): per-frame trace of the _onBallDetected path.
        // Fires before the trigger check so every detected tracking frame is
        // visible. Lets us see in the log which path the frame took, what
        // got updated, and whether velocity-drop trigger A would fire.
        diagLog('DIAG-IMPACT [DETECTED] '
            'phase=${_phase.name} '
            'trackFrames=$_trackingFrameCount '
            'directZone=$directZone (just-set _lastDirectZone=$_lastDirectZone) '
            'velMagSq=${velMagSq.toStringAsFixed(6)} '
            'peakVelSq=${_peakVelocitySq.toStringAsFixed(6)} '
            'velRatio=${_peakVelocitySq > 0 ? (velMagSq / _peakVelocitySq).toStringAsFixed(3) : "n/a"} '
            '(< 0.4 fires trigger A)');
        // Bug fix (2026-04-28, Path A Change 2): velocity-drop trigger
        // DISABLED. The original intent ("velMagSq < 0.4 × peak = ball hit
        // the wall") was a heuristic stand-in for impact, but in practice
        // it fires during normal mid-flight motion in our behind-kicker
        // camera setup:
        //   1. Peak gets set in frames 2–3 when the ball accelerates from
        //      rest — the highest screen velocity in the entire kick.
        //   2. As the ball flies up/away, apparent screen velocity decreases
        //      due to perspective foreshortening (the ball is receding).
        //   3. Kalman smoothing further dampens transient velocity spikes.
        //   4. By frame 5–6 the ratio naturally crosses below 0.4, well
        //      before the ball has reached the wall.
        // Field evidence (2026-04-27, kicks 2 & 4 of 4): trigger fired at
        // trackFrames=5 with depthRatio≈0.45 — i.e., ball was ~halfway
        // through flight, not at the wall. _lastDirectZone was still the
        // entry zone (1), giving a HIT zone 1 announcement when the ball
        // was actually on its way to zones 5/8/9.
        // Decisions now fire only via: (a) edge-exit in _makeDecision,
        // (b) lost-frame trigger in _onBallMissing (5 missed frames),
        // (c) maxTrackingDuration safety net (3 s). Original code preserved
        // below for reversibility — if validation kicks reveal we still
        // need an impact-detection trigger, restore it with a stricter
        // threshold (e.g., < 0.2 × peak AND trackFrames > 8 AND depth
        // verified).
        // ORIGINAL CODE (DISABLED):
        // if ((_lastDirectZone != null || _lastWallPredictedZone != null || _lastDepthVerifiedZone != null) &&
        //     _peakVelocitySq > minVelocityMagnitudeSq &&
        //     velMagSq < _peakVelocitySq * 0.4 &&
        //     _trackingFrameCount >= minTrackingFrames) {
        //   _makeDecision();
        //   return;
        // }
      case DetectionPhase.result:
        break; // Unreachable (handled above).
    }
  }

  void _onBallMissing({
    ExtrapolationResult? extrapolation,
    int? directZone,
    Offset? rawPosition,
    double? bboxArea,
  }) {
    if (_phase != DetectionPhase.tracking) return;

    // ADR-047, Fix 3: During occlusion, retain the last valid extrapolation.
    // Absence of detection is not new trajectory information. If a new
    // Kalman-predicted extrapolation is available, use it (it may refine
    // the prediction). Otherwise, keep whatever we had.
    if (extrapolation != null) {
      _bestExtrapolation = extrapolation;
    }
    // (If extrapolation is null, we intentionally keep _bestExtrapolation
    // unchanged — unlike _onBallDetected which sets it unconditionally.)

    // Bug fix (2026-04-28, Path A Change 1): keep _lastDirectZone fresh
    // even on `missing` frames. The screen computes directZone every frame
    // from the (possibly Kalman-predicted) ball position; ByteTrack flipping
    // its track to `lost` is an internal state-machine detail, not a signal
    // that zone information has stopped being meaningful. Same null-safety
    // rule as _onBallDetected — a null directZone (ball off-grid) does NOT
    // overwrite the last good zone.
    if (directZone != null) {
      _lastDirectZone = directZone;
    }

    // Bug fix extension (2026-04-28, Option A): keep _lastRawPosition and
    // _lastBboxArea fresh during [MISSING] frames too. Same reasoning as
    // directZone — these are inputs to other decision signals (edge-exit
    // filter, depth ratio, future hit-detection methods that may combine
    // position/bbox/zone signals). Freezing them at the last [DETECTED]
    // frame removes those signals from the design palette. Same null-
    // safety rule: a transient null does NOT overwrite the last good value.
    if (rawPosition != null) {
      _lastRawPosition = rawPosition;
    }
    if (bboxArea != null) {
      _lastBboxArea = bboxArea;
    }

    _lostFrameCount++;
    // DIAG (additive): per-frame trace of the _onBallMissing path. Fires
    // before the lost-frame trigger check so we see every missing frame on
    // the way to the threshold. After Option A, all state fields are kept
    // fresh in this branch — the values printed here are current.
    diagLog('DIAG-IMPACT [MISSING ] '
        'phase=${_phase.name} '
        'trackFrames=$_trackingFrameCount (frozen) '
        'lostFrames=$_lostFrameCount/$lostFrameThreshold '
        'lastDirectZone=$_lastDirectZone '
        'lastBboxArea=${_lastBboxArea.toStringAsFixed(6)}');
    if (_lostFrameCount >= lostFrameThreshold) {
      _makeDecision();
    }
  }

  void _makeDecision() {
    // Phantom-decision suppression (Piece A, 2026-04-29). When a trigger
    // fires while KickDetector reports idle, the trigger is firing on
    // detection jitter or stale state — not on a real kick. Suppress the
    // entire decision construction (no IMPACT DECISION block printed, no
    // result emitted) and reset to ready so the trigger doesn't keep
    // re-firing every frame. This mirrors the audio kick gate at the
    // screen level (which today rejects the same condition downstream
    // with `DIAG-AUDIO: impact REJECTED by kick gate`) but moves the gate
    // to the source so log noise and any future stale-state pollution
    // are cleaned up at the same point.
    if (_currentKickState == KickState.idle) {
      diagLog('DIAG-IMPACT [PHANTOM SUPPRESSED] '
          'trigger fired with kickState=idle; resetting to ready '
          '(trackFrames=$_trackingFrameCount, lostFrames=$_lostFrameCount, '
          'lastDirectZone=$_lastDirectZone)');
      _reset();
      return;
    }

    // DIAG: Log decision context.
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:MM:SS.mmm
    print('┌─── IMPACT DECISION ───');
    print('│ timestamp=$ts');
    print('│ trackingFrames: $_trackingFrameCount (min: $minTrackingFrames)');
    print('│ lastRawPosition: $_lastRawPosition');
    print('│ lastBboxArea: ${_lastBboxArea.toStringAsFixed(6)}');
    print('│ referenceBboxArea: ${_referenceBboxArea?.toStringAsFixed(6) ?? "null"}');
    if (_referenceBboxArea != null && _referenceBboxArea! > 0) {
      final ratio = _lastBboxArea / _referenceBboxArea!;
      print('│ depthRatio: ${ratio.toStringAsFixed(4)} (allowed: $minDepthRatio - $maxDepthRatio)');
    }
    if (_lastRawPosition != null) {
      final p = _lastRawPosition!;
      print('│ edgeDistances: left=${p.dx.toStringAsFixed(3)} right=${(1.0 - p.dx).toStringAsFixed(3)} top=${p.dy.toStringAsFixed(3)} bottom=${(1.0 - p.dy).toStringAsFixed(3)} (threshold: $edgeThreshold)');
    }
    print('│ peakVelocitySq: ${_peakVelocitySq.toStringAsFixed(8)}');
    print('│ bestExtrapolation: ${_bestExtrapolation != null ? "zone ${_bestExtrapolation!.zone} (target: ${_bestExtrapolation!.targetPoint}, camera: ${_bestExtrapolation!.cameraPoint}, framesAhead: ${_bestExtrapolation!.framesAhead})" : "null"}');
    print('│ lastDirectZone: $_lastDirectZone');
    print('│ lastWallPredictedZone: $_lastWallPredictedZone');
    print('│ lastDepthVerifiedZone: $_lastDepthVerifiedZone');

    // Signal: Frame-edge exit filter.
    // If the last known ball position is near any frame edge, the ball exited
    // the camera view rather than hitting the target.
    if (_lastRawPosition != null && _isNearEdge(_lastRawPosition!)) {
      print('│ DECISION: MISS (edge exit)');
      print('└───────────────────────');
      _setResult(ImpactEvent(
        result: ImpactResult.miss,
        timestamp: DateTime.now(),
      ));
      return;
    }

    // Signal: Last observed directZone (highest priority).
    // The ball's actual position mapped through the homography — no
    // prediction, no extrapolation. If the ball entered the grid at any
    // point during tracking, this is the most reliable signal.
    if (_lastDirectZone != null) {
      print('│ DECISION: HIT zone $_lastDirectZone (last observed directZone)');
      print('└───────────────────────');
      _setResult(ImpactEvent(
        result: ImpactResult.hit,
        zone: _lastDirectZone!,
        cameraPoint: _lastRawPosition,
        timestamp: DateTime.now(),
      ));
      return;
    }

    // No directZone observed — ball never entered the grid.
    print('│ DECISION: noResult (ball never entered grid)');
    print('└───────────────────────');
    _setResult(ImpactEvent(
      result: ImpactResult.noResult,
      timestamp: DateTime.now(),
    ));
  }

  bool _isNearEdge(Offset pos) {
    return pos.dx < edgeThreshold ||
        pos.dx > (1.0 - edgeThreshold) ||
        pos.dy < edgeThreshold ||
        pos.dy > (1.0 - edgeThreshold);
  }

  void _setResult(ImpactEvent event) {
    _phase = DetectionPhase.result;
    _currentResult = event;
    _resultTimestamp = DateTime.now();
  }

  void _reset() {
    _phase = DetectionPhase.ready;
    _trackingFrameCount = 0;
    _trackingStartTime = null;
    _lostFrameCount = 0;
    _velocityHistory.clear();
    _bestExtrapolation = null;
    _lastRawPosition = null;
    _currentResult = null;
    _resultTimestamp = null;
    _lastBboxArea = 0.0;
    _lastDirectZone = null;
    _lastDepthVerifiedZone = null;
    _lastWallPredictedZone = null;
    _peakVelocitySq = 0.0;
  }
}
