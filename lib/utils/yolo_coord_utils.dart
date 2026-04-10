import 'dart:ui' show Offset, Size;

/// Shared coordinate utility for mapping YOLO normalized detection coordinates
/// to canvas pixel coordinates, accounting for FILL_CENTER (BoxFit.cover) crop.
///
/// YOLOView renders using FILL_CENTER scaling: the camera preview is scaled so
/// the entire widget is covered while maintaining aspect ratio. One dimension
/// fills the widget exactly; the other is scaled beyond the widget edge and
/// cropped symmetrically. Normalized coordinates from the model are relative
/// to the full uncropped camera frame, so the crop offset must be subtracted
/// when converting to widget-local pixel coordinates.
///
/// This math is extracted from [DebugDotPainter.paint()] and verified on
/// iPhone 12 in Phase 6. The camera aspect ratio MUST match the plugin's
/// session preset: `.photo` on iOS → 4:3 (4032×3024). Using 16:9 here
/// causes a ~10% upward Y-offset in landscape mode.
class YoloCoordUtils {
  YoloCoordUtils._();

  /// Maps a normalized ball-center coordinate to canvas pixel coordinates.
  ///
  /// [normalized] — ball center in [0.0, 1.0] x [0.0, 1.0] relative to the
  /// full camera frame (as reported by YOLOView's normalizedBox).
  ///
  /// [canvasSize] — pixel dimensions of the CustomPaint canvas (matches the
  /// YOLOView widget bounds).
  ///
  /// [cameraAspectRatio] — camera sensor width / height (e.g. 16.0 / 9.0).
  /// Defaults to 16/9, which covers iPhone 12 and Galaxy A32 standard video.
  static Offset toCanvasPixel(
    Offset normalized,
    Size canvasSize,
    double cameraAspectRatio,
  ) {
    final widgetAR = canvasSize.width / canvasSize.height;
    double pixelX, pixelY;

    if (widgetAR > cameraAspectRatio) {
      // Widget wider than camera -> scaled by width, height cropped.
      final scaledHeight = canvasSize.width / cameraAspectRatio;
      final cropY = (scaledHeight - canvasSize.height) / 2.0;
      pixelX = normalized.dx * canvasSize.width;
      pixelY = normalized.dy * scaledHeight - cropY;
    } else {
      // Widget taller than camera -> scaled by height, width cropped.
      final scaledWidth = canvasSize.height * cameraAspectRatio;
      final cropX = (scaledWidth - canvasSize.width) / 2.0;
      pixelX = normalized.dx * scaledWidth - cropX;
      pixelY = normalized.dy * canvasSize.height;
    }

    return Offset(pixelX, pixelY);
  }

  /// Maps a canvas pixel coordinate back to normalized [0,1] space,
  /// accounting for FILL_CENTER (BoxFit.cover) crop.
  ///
  /// This is the algebraic inverse of [toCanvasPixel]. Used for converting
  /// touch event coordinates to the normalized space used by BallTracker
  /// and HomographyTransform.
  static Offset fromCanvasPixel(
    Offset pixel,
    Size canvasSize,
    double cameraAspectRatio,
  ) {
    final widgetAR = canvasSize.width / canvasSize.height;
    double normX, normY;

    if (widgetAR > cameraAspectRatio) {
      final scaledHeight = canvasSize.width / cameraAspectRatio;
      final cropY = (scaledHeight - canvasSize.height) / 2.0;
      normX = pixel.dx / canvasSize.width;
      normY = (pixel.dy + cropY) / scaledHeight;
    } else {
      final scaledWidth = canvasSize.height * cameraAspectRatio;
      final cropX = (scaledWidth - canvasSize.width) / 2.0;
      normX = (pixel.dx + cropX) / scaledWidth;
      normY = pixel.dy / canvasSize.height;
    }

    return Offset(normX, normY);
  }
}
