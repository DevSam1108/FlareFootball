import 'package:flutter/material.dart';
import 'package:tensorflow_demo/models/tracked_position.dart';
import 'package:tensorflow_demo/utils/yolo_coord_utils.dart';

/// A [CustomPainter] that renders the ball trail as fading dots with
/// connecting line segments.
///
/// [trail] is the position history from [BallTracker]. Each [TrackedPosition]
/// with [isOccluded] == true is an occlusion sentinel — connecting lines are
/// NOT drawn across sentinels (RNDR-03), but the sentinel itself is skipped
/// when drawing dots (RNDR-01).
///
/// [trailWindow] is the same duration used by [BallTracker] so that age is
/// computed consistently: age = elapsed / windowMs, clamped to [0.0, 1.0].
/// Opacity decreases linearly from 1.0 (newest) to 0.0 (window boundary).
///
/// All coordinate mapping delegates to [YoloCoordUtils.toCanvasPixel] which
/// applies FILL_CENTER (BoxFit.cover) crop correction (RNDR-05). Do NOT
/// inline the crop math here — it was verified on device in Phase 6 and must
/// not be duplicated.
///
/// [shouldRepaint] always returns true. [BallTracker.trail] returns
/// [List.unmodifiable] which creates a new wrapper on every call, making
/// reference equality unreliable. Performance isolation is handled by the
/// [RepaintBoundary] that wraps this painter in the YOLO Stack — not by
/// [shouldRepaint] — and [setState] is only called at detection frame rate,
/// not every vsync tick.
class TrailOverlay extends CustomPainter {
  /// Ball position history from [BallTracker.trail].
  final List<TrackedPosition> trail;

  /// Sliding time window duration used by [BallTracker]. Must match the value
  /// passed to the tracker so opacity calculations are consistent.
  final Duration trailWindow;

  /// Camera sensor aspect ratio (width / height). Defaults to 4:3 because the
  /// `ultralytics_yolo` plugin uses `.photo` session preset on iOS, which
  /// captures at 4032×3024 (4:3). See YOLOView.swift line 382.
  final double cameraAspectRatio;

  const TrailOverlay({
    required this.trail,
    required this.trailWindow,
    this.cameraAspectRatio = 4.0 / 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty || size.isEmpty) return;

    final now = DateTime.now();
    final windowMs = trailWindow.inMilliseconds.toDouble();

    // -------------------------------------------------------------------------
    // RNDR-02 + RNDR-03: Draw connecting line segments between consecutive
    // positions, skipping across occlusion sentinels.
    // -------------------------------------------------------------------------
    final linePaint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 1; i < trail.length; i++) {
      final prev = trail[i - 1];
      final curr = trail[i];

      // RNDR-03: Skip line segments that cross an occlusion gap.
      if (prev.isOccluded || curr.isOccluded) continue;

      final age =
          (now.difference(curr.timestamp).inMilliseconds / windowMs)
              .clamp(0.0, 1.0);
      final opacity = (1.0 - age).clamp(0.0, 1.0);

      linePaint.color = Colors.orange.withValues(alpha: opacity * 0.7);

      canvas.drawLine(
        YoloCoordUtils.toCanvasPixel(
            prev.normalizedCenter, size, cameraAspectRatio),
        YoloCoordUtils.toCanvasPixel(
            curr.normalizedCenter, size, cameraAspectRatio),
        linePaint,
      );
    }

    // -------------------------------------------------------------------------
    // RNDR-01: Draw a dot at each non-occluded position with age-based fading.
    // Dot radius tapers with age: newest ~7px, oldest ~2px.
    // -------------------------------------------------------------------------
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (final pos in trail) {
      // RNDR-01: Skip occlusion sentinels — they have no visual representation.
      if (pos.isOccluded) continue;

      final age =
          (now.difference(pos.timestamp).inMilliseconds / windowMs)
              .clamp(0.0, 1.0);
      final opacity = (1.0 - age).clamp(0.0, 1.0);
      final radius = 5.0 * opacity + 2.0;

      dotPaint.color = Colors.orange.withValues(alpha: opacity);

      canvas.drawCircle(
        YoloCoordUtils.toCanvasPixel(
            pos.normalizedCenter, size, cameraAspectRatio),
        radius,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(TrailOverlay old) {
    // Always repaint: BallTracker.trail returns List.unmodifiable() which
    // creates a new wrapper each call, so reference equality is unreliable.
    // RepaintBoundary (in the YOLO Stack) handles rendering isolation.
    return true;
  }
}
