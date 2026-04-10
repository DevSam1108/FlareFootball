import 'dart:ui' show Offset;

/// The outcome of an impact detection decision.
enum ImpactResult {
  /// Ball trajectory intersected the target — a zone was hit.
  hit,

  /// Ball exited the frame near an edge — missed the target.
  miss,

  /// Ball was lost but no definitive hit or miss could be determined.
  noResult,
}

/// Immutable value type representing the result of an impact detection event.
class ImpactEvent {
  /// Whether this was a hit, miss, or inconclusive.
  final ImpactResult result;

  /// Target zone number (1-9). Non-null only for [ImpactResult.hit].
  final int? zone;

  /// Predicted impact point in camera-normalized [0,1] space.
  /// Non-null only for [ImpactResult.hit].
  final Offset? cameraPoint;

  /// Predicted impact point in target-space [0,1] coordinates.
  /// Non-null only for [ImpactResult.hit].
  final Offset? targetPoint;

  /// When this impact event was created.
  final DateTime timestamp;

  const ImpactEvent({
    required this.result,
    this.zone,
    this.cameraPoint,
    this.targetPoint,
    required this.timestamp,
  });
}
