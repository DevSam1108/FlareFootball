import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tensorflow_demo/services/target_zone_mapper.dart';
import 'package:tensorflow_demo/utils/yolo_coord_utils.dart';

/// CustomPainter for the calibration UI: corner markers, green grid overlay,
/// camera center crosshair, tilt indicator, and post-tap offset feedback.
///
/// During calibration (before 4 corners are collected), renders:
/// - Camera center crosshair (always visible as alignment reference)
/// - Tilt indicator (spirit level showing phone tilt)
/// - Green circle markers at each tapped position with tap-order labels
///
/// After calibration (when [zoneMapper] is non-null), renders:
/// - Green wireframe connecting the 4 outer corners
/// - 2 vertical + 2 horizontal internal grid lines
/// - Zone numbers (1-9) centered in each cell
/// - Offset feedback arrow showing grid-center vs camera-center misalignment
///
/// All coordinates are provided in normalized [0,1] space and converted to
/// canvas pixels via [YoloCoordUtils.toCanvasPixel].
class CalibrationOverlay extends CustomPainter {
  /// Corner points tapped so far (0 to 4 items), in normalized [0,1] space.
  final List<Offset> cornerPoints;

  /// The zone mapper, available once all 4 corners are tapped and the
  /// homography is computed. Null during active calibration.
  final TargetZoneMapper? zoneMapper;

  /// Camera aspect ratio for coordinate conversion. Defaults to 4:3.
  final double cameraAspectRatio;

  /// Zone number (1-9) to highlight with a yellow fill. Null = no highlight.
  final int? highlightZone;

  /// Index of the corner currently being dragged. Null = no drag active.
  /// When non-null, crosshair lines are drawn through this corner.
  final int? activeCornerIndex;

  /// Whether to show the camera center crosshair. Defaults to true.
  final bool showCenterCrosshair;

  /// Vertical tilt angle in radians from accelerometer. 0 = level.
  /// Positive = tilted forward (top of phone away from user).
  final double tiltY;

  const CalibrationOverlay({
    required this.cornerPoints,
    this.zoneMapper,
    this.cameraAspectRatio = 4.0 / 3.0,
    this.highlightZone,
    this.activeCornerIndex,
    this.showCenterCrosshair = true,
    this.tiltY = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Camera center crosshair — bottom layer, always visible as reference.
    if (showCenterCrosshair) {
      _paintCenterCrosshair(canvas, size);
    }

    // Tilt indicator — spirit level in bottom-left corner.
    _paintTiltIndicator(canvas, size);

    _paintCornerMarkers(canvas, size);

    if (zoneMapper != null) {
      if (highlightZone != null) {
        _paintZoneHighlight(canvas, size);
      }
      _paintGrid(canvas, size);
      _paintZoneNumbers(canvas, size);

      // Shape validation feedback — only during calibration phase.
      if (showCenterCrosshair) {
        _paintOffsetFeedback(canvas, size);
      }
    }

    // Crosshair lines through the actively-dragged corner (topmost layer).
    _paintCrosshair(canvas, size);
  }

  void _paintCornerMarkers(Canvas canvas, Size size) {
    if (cornerPoints.isEmpty) return;

    final strokePaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < cornerPoints.length; i++) {
      final pixel = YoloCoordUtils.toCanvasPixel(
        cornerPoints[i],
        size,
        cameraAspectRatio,
      );

      // Hollow ring — no fill so crosshair intersection stays visible.
      canvas.drawCircle(pixel, 10.0, strokePaint);

      // Tap-order label.
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pixel + const Offset(16, -6));
    }
  }

  void _paintZoneHighlight(Canvas canvas, Size size) {
    final corners = zoneMapper!.zoneCorners(highlightZone!);
    if (corners == null) return;

    final highlightPaint = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final path = Path();
    final first =
        YoloCoordUtils.toCanvasPixel(corners[0], size, cameraAspectRatio);
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < corners.length; i++) {
      final p =
          YoloCoordUtils.toCanvasPixel(corners[i], size, cameraAspectRatio);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, highlightPaint);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final mapper = zoneMapper!;

    final gridPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Outer rectangle.
    final corners = mapper.outerCorners;
    final path = Path();
    final first =
        YoloCoordUtils.toCanvasPixel(corners[0], size, cameraAspectRatio);
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < corners.length; i++) {
      final p =
          YoloCoordUtils.toCanvasPixel(corners[i], size, cameraAspectRatio);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, gridPaint);

    // Internal grid lines.
    final innerPaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (final (start, end) in mapper.gridLines) {
      canvas.drawLine(
        YoloCoordUtils.toCanvasPixel(start, size, cameraAspectRatio),
        YoloCoordUtils.toCanvasPixel(end, size, cameraAspectRatio),
        innerPaint,
      );
    }
  }

  void _paintZoneNumbers(Canvas canvas, Size size) {
    final centers = zoneMapper!.zoneCenters;

    for (final entry in centers.entries) {
      final pixel = YoloCoordUtils.toCanvasPixel(
        entry.value,
        size,
        cameraAspectRatio,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${entry.key}',
          style: TextStyle(
            color: Colors.green.withValues(alpha: 0.9),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Center the text on the pixel position.
      tp.paint(
        canvas,
        Offset(pixel.dx - tp.width / 2, pixel.dy - tp.height / 2),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Camera center crosshair — subtle reference lines at canvas center.
  // ---------------------------------------------------------------------------

  void _paintCenterCrosshair(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    final linePaint = Paint()
      ..color = Colors.purple.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;

    // Dashed horizontal line across full width.
    _drawDashedLine(
      canvas,
      Offset(0, centerY),
      Offset(size.width, centerY),
      linePaint,
      dashLength: 8,
      gapLength: 6,
    );

    // Dashed vertical line across full height.
    _drawDashedLine(
      canvas,
      Offset(centerX, 0),
      Offset(centerX, size.height),
      linePaint,
      dashLength: 8,
      gapLength: 6,
    );

    // Small center circle for precise reference.
    final circlePaint = Paint()
      ..color = Colors.purple.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(centerX, centerY), 6.0, circlePaint);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dashLength = 8,
    double gapLength = 6,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final totalLength = math.sqrt(dx * dx + dy * dy);
    final unitDx = dx / totalLength;
    final unitDy = dy / totalLength;

    var drawn = 0.0;
    while (drawn < totalLength) {
      final dashEnd = math.min(drawn + dashLength, totalLength);
      canvas.drawLine(
        Offset(start.dx + unitDx * drawn, start.dy + unitDy * drawn),
        Offset(start.dx + unitDx * dashEnd, start.dy + unitDy * dashEnd),
        paint,
      );
      drawn += dashLength + gapLength;
    }
  }

  // ---------------------------------------------------------------------------
  // Tilt indicator — spirit level showing phone forward/backward tilt.
  // ---------------------------------------------------------------------------

  void _paintTiltIndicator(Canvas canvas, Size size) {
    // Position: bottom-left corner with padding.
    const indicatorWidth = 100.0;
    const indicatorHeight = 24.0;
    const padding = 16.0;
    const left = padding;
    final top = size.height - padding - indicatorHeight;

    // Tilt angle in degrees for thresholds.
    final tiltDegrees = tiltY * 180.0 / math.pi;

    // Color based on tilt magnitude.
    final Color indicatorColor;
    if (tiltDegrees.abs() <= 2.0) {
      indicatorColor = Colors.green;
    } else if (tiltDegrees.abs() <= 5.0) {
      indicatorColor = Colors.yellow;
    } else {
      indicatorColor = Colors.red;
    }

    // Background track.
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, indicatorWidth, indicatorHeight),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      bgRect,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Center tick mark.
    const centerTickX = left + indicatorWidth / 2;
    canvas.drawLine(
      Offset(centerTickX, top + 2),
      Offset(centerTickX, top + indicatorHeight - 2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..strokeWidth = 1.0,
    );

    // Bubble position — clamp tilt to ±15 degrees for the visual range.
    final clampedTilt = tiltDegrees.clamp(-15.0, 15.0);
    // Map tilt to horizontal position within the track.
    // Positive tilt (tilted forward) moves bubble right; negative moves left.
    final bubbleOffset = (clampedTilt / 15.0) * (indicatorWidth / 2 - 10);
    final bubbleX = left + indicatorWidth / 2 + bubbleOffset;
    final bubbleY = top + indicatorHeight / 2;

    // Bubble.
    canvas.drawCircle(
      Offset(bubbleX, bubbleY),
      7.0,
      Paint()..color = indicatorColor.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      Offset(bubbleX, bubbleY),
      7.0,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Label to the right of the indicator.
    final String label;
    if (tiltDegrees.abs() <= 2.0) {
      label = 'LEVEL';
    } else if (tiltDegrees > 0) {
      label = 'TILT DOWN';
    } else {
      label = 'TILT UP';
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: indicatorColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(left + indicatorWidth + 8, top + (indicatorHeight - tp.height) / 2),
    );
  }

  // ---------------------------------------------------------------------------
  // Post-tap shape validation — checks if 4 corners form a proper rectangle.
  // ---------------------------------------------------------------------------

  void _paintOffsetFeedback(Canvas canvas, Size size) {
    final corners = zoneMapper!.outerCorners;
    if (corners.length < 4) return;

    // Convert to pixel space for distance calculations.
    final px = corners
        .map((c) => YoloCoordUtils.toCanvasPixel(c, size, cameraAspectRatio))
        .toList();

    // Edge lengths: TL→TR (top), TR→BR (right), BR→BL (bottom), BL→TL (left).
    final topLen = (px[1] - px[0]).distance;
    final rightLen = (px[2] - px[1]).distance;
    final bottomLen = (px[3] - px[2]).distance;
    final leftLen = (px[0] - px[3]).distance;

    // Shape quality: opposite sides should be roughly similar length.
    // Ratio of 1.0 = perfect rectangle. Tolerance: within 30%.
    final horizRatio = topLen > 0 && bottomLen > 0
        ? (topLen < bottomLen ? topLen / bottomLen : bottomLen / topLen)
        : 0.0;
    final vertRatio = leftLen > 0 && rightLen > 0
        ? (leftLen < rightLen ? leftLen / rightLen : rightLen / leftLen)
        : 0.0;

    // Corner symmetry: all 4 corners should be roughly equidistant from
    // the camera center. Check max/min distance ratio.
    final cameraPx = Offset(size.width / 2, size.height / 2);
    final cornerDists = px.map((p) => (p - cameraPx).distance).toList();
    final maxDist = cornerDists.reduce(math.max);
    final minDist = cornerDists.reduce(math.min);
    final symmetryRatio = minDist > 0 ? minDist / maxDist : 0.0;

    // Determine overall quality.
    final shapeOk = horizRatio >= 0.7 && vertRatio >= 0.7;
    final symmetryOk = symmetryRatio >= 0.6;

    final String label;
    final Color color;

    if (shapeOk && symmetryOk) {
      label = 'CENTERED';
      color = Colors.green;
    } else if (!shapeOk) {
      // Identify which dimension is distorted.
      if (horizRatio < vertRatio) {
        label = 'BAD SHAPE — top/bottom edges uneven';
      } else {
        label = 'BAD SHAPE — left/right edges uneven';
      }
      color = Colors.red;
    } else {
      // Shape OK but not symmetric around center.
      // Find the corner that's farthest from the average distance.
      final avgDist = cornerDists.reduce((a, b) => a + b) / 4;
      var worstIdx = 0;
      var worstDev = 0.0;
      for (int i = 0; i < 4; i++) {
        final dev = (cornerDists[i] - avgDist).abs();
        if (dev > worstDev) {
          worstDev = dev;
          worstIdx = i;
        }
      }
      const cornerNames = ['Top-Left', 'Top-Right', 'Bottom-Right', 'Bottom-Left'];
      label = 'NOT SYMMETRIC — adjust ${cornerNames[worstIdx]}';
      color = Colors.yellow;
    }

    // Render label at camera center.
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withValues(alpha: 0.5),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cameraPx.dx - tp.width / 2, cameraPx.dy + 16));
  }

  /// Draws full-width horizontal and full-height vertical crosshair lines
  /// through the actively-dragged corner. Only called when a corner is
  /// being dragged (activeCornerIndex != null).
  void _paintCrosshair(Canvas canvas, Size size) {
    if (activeCornerIndex == null ||
        activeCornerIndex! < 0 ||
        activeCornerIndex! >= cornerPoints.length) {
      return;
    }

    final corner = cornerPoints[activeCornerIndex!];
    final pixel = YoloCoordUtils.toCanvasPixel(
      corner,
      size,
      cameraAspectRatio,
    );

    final crosshairPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 0.5;

    // Horizontal line (full canvas width).
    canvas.drawLine(
      Offset(0, pixel.dy),
      Offset(size.width, pixel.dy),
      crosshairPaint,
    );
    // Vertical line (full canvas height).
    canvas.drawLine(
      Offset(pixel.dx, 0),
      Offset(pixel.dx, size.height),
      crosshairPaint,
    );
  }

  @override
  bool shouldRepaint(CalibrationOverlay old) => true;
}
