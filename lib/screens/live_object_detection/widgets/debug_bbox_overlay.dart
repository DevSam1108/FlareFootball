import 'package:flutter/material.dart';
import 'package:tensorflow_demo/services/bytetrack_tracker.dart';
import 'package:tensorflow_demo/utils/yolo_coord_utils.dart';

/// Debug overlay that draws bounding boxes around all ball-class detections.
///
/// - **Green box** = BallIdentifier's locked track (what the app considers "the ball")
/// - **Yellow box** = Other ball-class detections (candidates for re-acquisition)
/// - Each box shows: trackId, bbox dimensions, confidence, isStatic flag
///
/// Enable/disable via [_debugBboxOverlay] flag in live_object_detection_screen.dart.
class DebugBboxOverlay extends CustomPainter {
  final List<TrackedObject> ballClassTracks;
  final int? lockedTrackId;
  final double cameraAspectRatio;

  DebugBboxOverlay({
    required this.ballClassTracks,
    required this.lockedTrackId,
    this.cameraAspectRatio = 4.0 / 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ballClassTracks.isEmpty) return;

    final lockedPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final candidatePaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final lostPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final track in ballClassTracks) {
      final isLocked = track.trackId == lockedTrackId;
      final isLost = track.state == TrackState.lost;

      // Convert normalized bbox corners to canvas pixels.
      final topLeft = YoloCoordUtils.toCanvasPixel(
        Offset(track.bbox.left, track.bbox.top),
        size,
        cameraAspectRatio,
      );
      final bottomRight = YoloCoordUtils.toCanvasPixel(
        Offset(track.bbox.right, track.bbox.bottom),
        size,
        cameraAspectRatio,
      );

      final rect = Rect.fromPoints(topLeft, bottomRight);

      // Choose paint based on state.
      final paint = isLocked
          ? (isLost ? lostPaint : lockedPaint)
          : candidatePaint;

      // Draw bounding box.
      canvas.drawRect(rect, paint);

      // Build label text.
      final bboxW = track.bbox.width;
      final bboxH = track.bbox.height;
      final aspect = bboxH > 0 ? (bboxW / bboxH) : 0.0;
      final label = 'id:${track.trackId} '
          '${bboxW.toStringAsFixed(3)}x${bboxH.toStringAsFixed(3)} '
          'ar:${aspect.toStringAsFixed(1)} '
          'c:${track.confidence.toStringAsFixed(2)}'
          '${track.isStatic ? ' S' : ''}'
          '${isLocked ? ' [LOCKED]' : ''}';

      // Draw label background + text above the box.
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: isLocked ? Colors.green : Colors.yellow,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black87,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      // Position label above the box, clamped to screen.
      final labelX = rect.left.clamp(0.0, size.width - textPainter.width);
      final labelY = (rect.top - textPainter.height - 2)
          .clamp(0.0, size.height - textPainter.height);

      textPainter.paint(canvas, Offset(labelX, labelY));
    }
  }

  @override
  bool shouldRepaint(covariant DebugBboxOverlay oldDelegate) => true;
}
