import 'dart:math' show sqrt;
import 'dart:ui' show Offset;

import 'package:tensorflow_demo/services/target_zone_mapper.dart';

/// Result of a wall-plane trajectory prediction.
class WallPrediction {
  /// Predicted impact point in camera-normalized [0,1] coordinates.
  final Offset cameraPoint;

  /// Impact point in target-space [0,1] coordinates.
  final Offset targetPoint;

  /// Target zone number (1-9) at the predicted impact.
  final int zone;

  /// Estimated frames until the ball reaches the wall.
  final int framesAhead;

  const WallPrediction({
    required this.cameraPoint,
    required this.targetPoint,
    required this.zone,
    required this.framesAhead,
  });
}

/// A single 3D observation derived from a 2D detection + depth ratio.
class _Observation3D {
  final double x;
  final double y;
  final double z;

  const _Observation3D({
    required this.x,
    required this.y,
    required this.z,
  });
}

/// Predicts where a ball will hit the wall plane by constructing a pseudo-3D
/// trajectory from per-frame 2D detections + depth ratios.
///
/// **Zero hardcoded parameters.** No physical dimensions (target size, ball
/// size, distances) are assumed. The wall plane is implicitly defined by the
/// homography — a point is "at the wall" when its 2D projection through the
/// homography falls inside the target grid.
///
/// **Algorithm:**
/// 1. Accumulate per-frame (2D position, depth ratio) observations.
/// 2. Convert each to pseudo-3D using depth from bbox area changes.
/// 3. Estimate 3D velocity from recent observations.
/// 4. Iteratively project the 3D trajectory forward in time.
/// 5. At each time step, project back to 2D and check if the point falls
///    inside the target grid (via `pointToZone()`).
/// 6. First intersection = predicted wall impact zone.
///
/// **Depth model:** `area ∝ 1/distance²`.
/// The reference ball (captured at kicker's feet) defines distance = 1.0.
/// As the ball flies toward the wall, it appears smaller and distance increases.
class WallPlanePredictor {
  /// Approximate optical center in camera-normalized [0,1] space.
  /// Derived from the centroid of the 4 calibration corner points — this is
  /// observed data, not a physical assumption.
  final Offset opticalCenter;

  /// Maximum observations to retain (memory/performance limit).
  static const int _maxObservations = 10;

  /// Maximum frames ahead to extrapolate (computational limit).
  static const int _maxFramesAhead = 30;

  WallPlanePredictor({required this.opticalCenter});

  final List<_Observation3D> _observations = [];

  /// Feed a new frame observation.
  ///
  /// [cameraPosition] — ball center in normalized [0,1] camera space.
  /// [bboxArea] — current frame bounding box area (width * height, normalized).
  /// [referenceArea] — reference bounding box area from calibration.
  void addObservation({
    required Offset cameraPosition,
    required double bboxArea,
    required double referenceArea,
  }) {
    if (referenceArea <= 0 || bboxArea <= 0) return;

    final depthRatio = bboxArea / referenceArea;
    final d = 1.0 / sqrt(depthRatio); // relative distance from camera

    final cx = opticalCenter.dx;
    final cy = opticalCenter.dy;

    _observations.add(_Observation3D(
      x: (cameraPosition.dx - cx) * d,
      y: (cameraPosition.dy - cy) * d,
      z: d,
    ));

    if (_observations.length > _maxObservations) {
      _observations.removeAt(0);
    }
  }

  /// Predict which zone the ball will hit on the wall, or null if
  /// insufficient data or the ball is not heading toward the wall.
  ///
  /// Uses iterative forward projection: extrapolates the 3D trajectory
  /// one frame at a time and projects back to 2D, checking if the
  /// projected point falls inside the target grid. The wall depth is
  /// discovered implicitly — no pre-computed wall distance needed.
  WallPrediction? predictWallZone(TargetZoneMapper zoneMapper) {
    if (_observations.length < 2) return null;
    if (!_isDepthIncreasing()) return null;

    final vel = _estimateVelocity();
    if (vel == null) return null;

    final (vx, vy, vz) = vel;
    if (vz <= 0) return null;

    final current = _observations.last;
    final cx = opticalCenter.dx;
    final cy = opticalCenter.dy;

    for (int t = 1; t <= _maxFramesAhead; t++) {
      final xT = current.x + vx * t;
      final yT = current.y + vy * t;
      final zT = current.z + vz * t;

      // Avoid division by zero or negative depth.
      if (zT <= 0.01) continue;

      // Project back to 2D camera coordinates.
      final u = cx + xT / zT;
      final v = cy + yT / zT;

      // Exit if projected point leaves the camera frame.
      if (u < -0.1 || u > 1.1 || v < -0.1 || v > 1.1) return null;

      // Check if the projected point falls inside the target grid.
      final cameraPoint = Offset(u, v);
      final zone = zoneMapper.pointToZone(cameraPoint);
      if (zone != null) {
        final targetPoint = zoneMapper.homography.transform(cameraPoint);
        return WallPrediction(
          cameraPoint: cameraPoint,
          targetPoint: targetPoint,
          zone: zone,
          framesAhead: t,
        );
      }
    }

    return null;
  }

  /// Estimated relative depth of the ball (latest observation).
  double? get estimatedDepth =>
      _observations.isEmpty ? null : _observations.last.z;

  /// Estimated frames to wall — runs the same iterative projection as
  /// [predictWallZone] but only returns the frame count.
  int? estimatedFramesToWall(TargetZoneMapper zoneMapper) {
    return predictWallZone(zoneMapper)?.framesAhead;
  }

  /// Clear all accumulated observations.
  void reset() {
    _observations.clear();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Checks if depth is increasing over recent observations (ball moving
  /// toward wall). Tolerates 5% noise regression in bbox area.
  bool _isDepthIncreasing() {
    final n = _observations.length;
    if (n < 2) return false;

    final checkCount = n >= 3 ? 3 : 2;
    final startIdx = n - checkCount;

    int increasingPairs = 0;
    for (int i = startIdx + 1; i < n; i++) {
      if (_observations[i].z >= _observations[i - 1].z * 0.95) {
        increasingPairs++;
      }
    }

    return increasingPairs >= (checkCount - 1);
  }

  /// Estimates 3D velocity using weighted finite differences.
  /// Recent frame pairs get higher weight.
  (double, double, double)? _estimateVelocity() {
    final n = _observations.length;
    if (n < 2) return null;

    double sumVx = 0, sumVy = 0, sumVz = 0;
    double sumWeight = 0;

    final startIdx = n > 6 ? n - 6 : 0;
    for (int i = startIdx + 1; i < n; i++) {
      final prev = _observations[i - 1];
      final curr = _observations[i];
      final weight = 1.0 + (i - startIdx - 1).toDouble();

      sumVx += (curr.x - prev.x) * weight;
      sumVy += (curr.y - prev.y) * weight;
      sumVz += (curr.z - prev.z) * weight;
      sumWeight += weight;
    }

    if (sumWeight < 1e-12) return null;

    return (sumVx / sumWeight, sumVy / sumWeight, sumVz / sumWeight);
  }
}
