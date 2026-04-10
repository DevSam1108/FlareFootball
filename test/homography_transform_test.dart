import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/services/homography_transform.dart';

void main() {
  group('HomographyTransform', () {
    test('identity: unit square to unit square preserves points', () {
      final h = HomographyTransform.fromCorrespondences(
        const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
        const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      );
      final result = h.transform(const Offset(0.5, 0.5));
      expect(result.dx, closeTo(0.5, 1e-6));
      expect(result.dy, closeTo(0.5, 1e-6));
    });

    test('identity preserves corner points', () {
      final h = HomographyTransform.fromCorrespondences(
        const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
        const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      );
      for (final corner in const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
      ]) {
        final result = h.transform(corner);
        expect(result.dx, closeTo(corner.dx, 1e-6));
        expect(result.dy, closeTo(corner.dy, 1e-6));
      }
    });

    test('scale: double-size square maps center correctly', () {
      final h = HomographyTransform.fromCorrespondences(
        const [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
        const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      );
      final result = h.transform(const Offset(1.0, 1.0));
      expect(result.dx, closeTo(0.5, 1e-6));
      expect(result.dy, closeTo(0.5, 1e-6));
    });

    test('translation: offset rectangle maps correctly', () {
      final h = HomographyTransform.fromCorrespondences(
        const [
          Offset(0.2, 0.2),
          Offset(0.8, 0.2),
          Offset(0.8, 0.8),
          Offset(0.2, 0.8),
        ],
        const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      );
      // Center of source rectangle -> center of unit square.
      final result = h.transform(const Offset(0.5, 0.5));
      expect(result.dx, closeTo(0.5, 1e-6));
      expect(result.dy, closeTo(0.5, 1e-6));
    });

    test('perspective: trapezoid maps source corners to unit square', () {
      const src = [
        Offset(0.1, 0.1),
        Offset(0.9, 0.15),
        Offset(0.85, 0.85),
        Offset(0.15, 0.9),
      ];
      const dst = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
      final h = HomographyTransform.fromCorrespondences(src, dst);

      // Each source corner should map to its corresponding destination.
      for (int i = 0; i < 4; i++) {
        final result = h.transform(src[i]);
        expect(result.dx, closeTo(dst[i].dx, 1e-6));
        expect(result.dy, closeTo(dst[i].dy, 1e-6));
      }
    });

    test('inverse round-trip: transform then inverseTransform returns original',
        () {
      final h = HomographyTransform.fromCorrespondences(
        const [
          Offset(0.1, 0.2),
          Offset(0.8, 0.15),
          Offset(0.85, 0.9),
          Offset(0.15, 0.85),
        ],
        const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      );
      const original = Offset(0.4, 0.6);
      final roundTrip = h.inverseTransform(h.transform(original));
      expect(roundTrip.dx, closeTo(original.dx, 1e-6));
      expect(roundTrip.dy, closeTo(original.dy, 1e-6));
    });

    test('inverseTransform maps destination corners back to source', () {
      const src = [
        Offset(0.1, 0.2),
        Offset(0.8, 0.15),
        Offset(0.85, 0.9),
        Offset(0.15, 0.85),
      ];
      const dst = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
      final h = HomographyTransform.fromCorrespondences(src, dst);

      for (int i = 0; i < 4; i++) {
        final result = h.inverseTransform(dst[i]);
        expect(result.dx, closeTo(src[i].dx, 1e-6));
        expect(result.dy, closeTo(src[i].dy, 1e-6));
      }
    });

    test('throws on wrong number of points', () {
      expect(
        () => HomographyTransform.fromCorrespondences(
          const [Offset(0, 0), Offset(1, 0)],
          const [Offset(0, 0), Offset(1, 0)],
        ),
        throwsArgumentError,
      );
    });
  });
}
