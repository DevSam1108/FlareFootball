import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/services/homography_transform.dart';
import 'package:tensorflow_demo/services/target_zone_mapper.dart';

void main() {
  group('TargetZoneMapper', () {
    late TargetZoneMapper mapper;

    setUp(() {
      // Axis-aligned rectangle: source = [0.1..0.9] x [0.1..0.9].
      final h = HomographyTransform.fromCorrespondences(
        const [
          Offset(0.1, 0.1),
          Offset(0.9, 0.1),
          Offset(0.9, 0.9),
          Offset(0.1, 0.9),
        ],
        const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      );
      mapper = TargetZoneMapper(h);
    });

    test('zone 1 (bottom-left) maps correctly', () {
      // Bottom-left: target-space col=0, row=2 -> zone 1.
      expect(mapper.pointToZone(const Offset(0.2, 0.8)), equals(1));
    });

    test('zone 5 (center) maps correctly', () {
      expect(mapper.pointToZone(const Offset(0.5, 0.5)), equals(5));
    });

    test('zone 9 (top-right) maps correctly', () {
      expect(mapper.pointToZone(const Offset(0.8, 0.2)), equals(9));
    });

    test('zone 7 (top-left) maps correctly', () {
      expect(mapper.pointToZone(const Offset(0.2, 0.2)), equals(7));
    });

    test('zone 3 (bottom-right) maps correctly', () {
      expect(mapper.pointToZone(const Offset(0.8, 0.8)), equals(3));
    });

    test('outside target returns null', () {
      expect(mapper.pointToZone(const Offset(0.05, 0.05)), isNull);
      expect(mapper.pointToZone(const Offset(0.95, 0.95)), isNull);
    });

    test('gridLines returns 4 line pairs', () {
      expect(mapper.gridLines.length, equals(4));
    });

    test('zoneCenters returns 9 entries for zones 1-9', () {
      final centers = mapper.zoneCenters;
      expect(centers.length, equals(9));
      expect(centers.keys.toSet(), equals({1, 2, 3, 4, 5, 6, 7, 8, 9}));
    });

    test('outerCorners returns 4 points', () {
      expect(mapper.outerCorners.length, equals(4));
    });

    test('outerCorners match original source points', () {
      final corners = mapper.outerCorners;
      expect(corners[0].dx, closeTo(0.1, 1e-6)); // top-left
      expect(corners[0].dy, closeTo(0.1, 1e-6));
      expect(corners[1].dx, closeTo(0.9, 1e-6)); // top-right
      expect(corners[1].dy, closeTo(0.1, 1e-6));
      expect(corners[2].dx, closeTo(0.9, 1e-6)); // bottom-right
      expect(corners[2].dy, closeTo(0.9, 1e-6));
      expect(corners[3].dx, closeTo(0.1, 1e-6)); // bottom-left
      expect(corners[3].dy, closeTo(0.9, 1e-6));
    });
  });
}
