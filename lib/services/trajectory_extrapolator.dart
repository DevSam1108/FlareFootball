import 'dart:ui' show Offset;

import 'package:tensorflow_demo/services/target_zone_mapper.dart';

/// Result of a trajectory extrapolation that successfully intersects the
/// calibrated target area.
class ExtrapolationResult {
  /// Predicted intersection point in camera-normalized [0,1] coordinates.
  final Offset cameraPoint;

  /// Intersection point in target-space [0,1] coordinates.
  final Offset targetPoint;

  /// Target zone number (1-9) at the intersection.
  final int zone;

  /// Number of frames into the future the intersection occurs.
  final int framesAhead;

  const ExtrapolationResult({
    required this.cameraPoint,
    required this.targetPoint,
    required this.zone,
    required this.framesAhead,
  });
}

/// Extrapolates a ball's parabolic trajectory to predict where it will
/// intersect the calibrated target plane.
///
/// Uses a constant-velocity model in x with a gravity term in y:
///   x(t) = px + vx * t
///   y(t) = py + vy * t + 0.5 * gravity * t^2
///
/// where t is in frame units. The gravity constant is tunable and represents
/// the downward pull in camera-normalized units per frame^2.
class TrajectoryExtrapolator {
  /// Gravity constant in normalized units per frame^2. Positive = downward
  /// in camera space. Default 0.001 produces a subtle arc over ~30 frames.
  final double gravity;

  /// Maximum number of frames to extrapolate before giving up.
  final int maxFrames;

  /// Minimum velocity magnitude to attempt extrapolation. Below this the
  /// ball is essentially stationary and no meaningful trajectory exists.
  static const double _minVelocityMagnitude = 0.001;

  TrajectoryExtrapolator({
    this.gravity = 0.001,
    this.maxFrames = 60,
  });

  /// Extrapolates the ball trajectory from [position] with [velocity] and
  /// returns where it intersects the target area defined by [zoneMapper],
  /// or null if the trajectory misses or the ball is stationary.
  ///
  /// [position] and [velocity] should come from the Kalman-smoothed tracker
  /// state (BallTracker.smoothedPosition / .velocity).
  ExtrapolationResult? extrapolate({
    required Offset position,
    required Offset velocity,
    required TargetZoneMapper zoneMapper,
  }) {
    // Early exit for stationary ball.
    final velMag = velocity.dx * velocity.dx + velocity.dy * velocity.dy;
    if (velMag < _minVelocityMagnitude * _minVelocityMagnitude) return null;

    for (int t = 1; t <= maxFrames; t++) {
      final x = position.dx + velocity.dx * t;
      final y = position.dy + velocity.dy * t + 0.5 * gravity * t * t;

      // Check if point has exited the camera frame with margin.
      if (x < -0.1 || x > 1.1 || y < -0.1 || y > 1.1) return null;

      final cameraPoint = Offset(x, y);

      // Check if point falls inside the target area.
      final zone = zoneMapper.pointToZone(cameraPoint);
      if (zone != null) {
        final targetPoint = zoneMapper.homography.transform(cameraPoint);
        return ExtrapolationResult(
          cameraPoint: cameraPoint,
          targetPoint: targetPoint,
          zone: zone,
          framesAhead: t,
        );
      }
    }

    // No intersection within maxFrames.
    return null;
  }
}
