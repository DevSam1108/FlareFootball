import 'dart:ui' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/utils/yolo_coord_utils.dart';

void main() {
  group('YoloCoordUtils.fromCanvasPixel', () {
    const cameraAR = 4.0 / 3.0;

    test('round-trip at center (landscape widget)', () {
      const size = Size(800, 400);
      const original = Offset(0.5, 0.5);
      final pixel = YoloCoordUtils.toCanvasPixel(original, size, cameraAR);
      final roundTrip = YoloCoordUtils.fromCanvasPixel(pixel, size, cameraAR);
      expect(roundTrip.dx, closeTo(original.dx, 1e-6));
      expect(roundTrip.dy, closeTo(original.dy, 1e-6));
    });

    test('round-trip at corners (landscape widget)', () {
      const size = Size(800, 400);
      for (final norm in const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(0, 1),
        Offset(1, 1),
      ]) {
        final pixel = YoloCoordUtils.toCanvasPixel(norm, size, cameraAR);
        final roundTrip =
            YoloCoordUtils.fromCanvasPixel(pixel, size, cameraAR);
        expect(roundTrip.dx, closeTo(norm.dx, 1e-6));
        expect(roundTrip.dy, closeTo(norm.dy, 1e-6));
      }
    });

    test('round-trip with portrait-shaped widget', () {
      const size = Size(400, 800);
      const original = Offset(0.3, 0.7);
      final pixel = YoloCoordUtils.toCanvasPixel(original, size, cameraAR);
      final roundTrip = YoloCoordUtils.fromCanvasPixel(pixel, size, cameraAR);
      expect(roundTrip.dx, closeTo(original.dx, 1e-6));
      expect(roundTrip.dy, closeTo(original.dy, 1e-6));
    });

    test('round-trip with exact camera aspect ratio widget', () {
      // Widget AR exactly matches camera AR: no crop at all.
      const size = Size(800, 600); // 4:3
      const original = Offset(0.25, 0.75);
      final pixel = YoloCoordUtils.toCanvasPixel(original, size, cameraAR);
      final roundTrip = YoloCoordUtils.fromCanvasPixel(pixel, size, cameraAR);
      expect(roundTrip.dx, closeTo(original.dx, 1e-6));
      expect(roundTrip.dy, closeTo(original.dy, 1e-6));
    });
  });
}
