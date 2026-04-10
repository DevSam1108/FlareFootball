import 'dart:ui' show Offset;

/// Immutable value type representing a single ball position in the trail history.
///
/// [normalizedCenter] is a normalized [Offset] in the range [0.0, 1.0] for
/// both axes, representing the ball center relative to the full camera frame.
///
/// [timestamp] records when this position was captured, used by [BallTracker]
/// for time-windowed eviction (entries older than [trailWindow] are pruned).
///
/// [isOccluded] is true for sentinel entries inserted when the ball is lost.
/// Sentinels signal the trail painter to break the polyline rather than
/// drawing a line across a detection gap.
class TrackedPosition {
  final Offset normalizedCenter;
  final DateTime timestamp;
  final bool isOccluded;

  /// Estimated velocity at this position (normalized units per frame).
  /// Null for legacy entries or when Kalman filter is not yet initialized.
  final double? vx;
  final double? vy;

  /// True when this position was predicted by the Kalman filter during
  /// occlusion rather than backed by a YOLO measurement.
  final bool isPredicted;

  const TrackedPosition({
    required this.normalizedCenter,
    required this.timestamp,
    this.isOccluded = false,
    this.vx,
    this.vy,
    this.isPredicted = false,
  });
}
