import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws a dashed line segment from [start] to [end] on [canvas] using the
/// given [paint]. Direction-agnostic — works for horizontal, vertical, or
/// diagonal segments.
///
/// [dashLength] is the length of each drawn dash (default 8 logical px).
/// [gapLength] is the length of the gap between dashes (default 6 logical px).
///
/// Shared helper — consumed by the calibration center crosshair and the
/// anchor rectangle overlay. Keep this the single source of truth for
/// dashed-line rendering in the app.
void drawDashedLine(
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
  if (totalLength == 0) return;
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
