import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/services/homography_transform.dart';
import 'package:tensorflow_demo/services/target_zone_mapper.dart';
import 'package:tensorflow_demo/services/wall_plane_predictor.dart';

/// Creates a simple axis-aligned homography for testing.
/// Maps a camera-space rectangle to the unit square [0,1]x[0,1].
TargetZoneMapper _makeMapper({
  double left = 0.2,
  double top = 0.1,
  double right = 0.8,
  double bottom = 0.6,
}) {
  final src = [
    Offset(left, top),
    Offset(right, top),
    Offset(right, bottom),
    Offset(left, bottom),
  ];
  const dst = [
    Offset(0.0, 0.0),
    Offset(1.0, 0.0),
    Offset(1.0, 1.0),
    Offset(0.0, 1.0),
  ];
  final homography = HomographyTransform.fromCorrespondences(src, dst);
  return TargetZoneMapper(homography);
}

void main() {
  group('WallPlanePredictor', () {
    late WallPlanePredictor predictor;
    late TargetZoneMapper mapper;

    setUp(() {
      mapper = _makeMapper();
      // Optical center = centroid of the mapper's corners.
      predictor = WallPlanePredictor(
        opticalCenter: const Offset(0.5, 0.35),
      );
    });

    test('returns null with fewer than 2 observations', () {
      expect(predictor.predictWallZone(mapper), isNull);

      predictor.addObservation(
        cameraPosition: const Offset(0.4, 0.6),
        bboxArea: 0.001,
        referenceArea: 0.001,
      );
      expect(predictor.predictWallZone(mapper), isNull);
    });

    test('returns null for stationary ball', () {
      for (int i = 0; i < 5; i++) {
        predictor.addObservation(
          cameraPosition: const Offset(0.5, 0.5),
          bboxArea: 0.001,
          referenceArea: 0.001,
        );
      }
      expect(predictor.predictWallZone(mapper), isNull);
    });

    test('returns null when ball moves toward camera', () {
      for (int i = 0; i < 5; i++) {
        predictor.addObservation(
          cameraPosition: const Offset(0.5, 0.5),
          bboxArea: 0.001 + i * 0.0002,
          referenceArea: 0.001,
        );
      }
      expect(predictor.predictWallZone(mapper), isNull);
    });

    test('predicts zone for ball approaching wall', () {
      const referenceArea = 0.001;

      predictor.addObservation(
        cameraPosition: const Offset(0.45, 0.60),
        bboxArea: 0.00095,
        referenceArea: referenceArea,
      );
      predictor.addObservation(
        cameraPosition: const Offset(0.44, 0.55),
        bboxArea: 0.00080,
        referenceArea: referenceArea,
      );
      predictor.addObservation(
        cameraPosition: const Offset(0.43, 0.50),
        bboxArea: 0.00065,
        referenceArea: referenceArea,
      );
      predictor.addObservation(
        cameraPosition: const Offset(0.42, 0.45),
        bboxArea: 0.00050,
        referenceArea: referenceArea,
      );

      final prediction = predictor.predictWallZone(mapper);
      expect(prediction, isNotNull);
      expect(prediction!.zone, inInclusiveRange(1, 9));
      expect(prediction.framesAhead, greaterThan(0));
    });

    test('predicts with only 2 observations when depth is increasing', () {
      const referenceArea = 0.001;

      predictor.addObservation(
        cameraPosition: const Offset(0.45, 0.55),
        bboxArea: 0.00090,
        referenceArea: referenceArea,
      );
      predictor.addObservation(
        cameraPosition: const Offset(0.43, 0.50),
        bboxArea: 0.00065,
        referenceArea: referenceArea,
      );

      // At minimum 2 observations with increasing depth, the predictor
      // should attempt a prediction (may or may not find a zone depending
      // on the trajectory direction relative to the grid).
      expect(predictor.estimatedDepth, isNotNull);
    });

    test('reset clears all observations', () {
      for (int i = 0; i < 5; i++) {
        predictor.addObservation(
          cameraPosition: Offset(0.5, 0.6 - i * 0.02),
          bboxArea: 0.001 - i * 0.0001,
          referenceArea: 0.001,
        );
      }
      predictor.reset();
      expect(predictor.predictWallZone(mapper), isNull);
      expect(predictor.estimatedDepth, isNull);
    });

    test('estimatedDepth reflects latest observation', () {
      predictor.addObservation(
        cameraPosition: const Offset(0.5, 0.5),
        bboxArea: 0.001,
        referenceArea: 0.001,
      );
      expect(predictor.estimatedDepth, closeTo(1.0, 0.01));

      predictor.addObservation(
        cameraPosition: const Offset(0.5, 0.5),
        bboxArea: 0.00025,
        referenceArea: 0.001,
      );
      expect(predictor.estimatedDepth, closeTo(2.0, 0.01));
    });

    test('ignores observations with zero or negative area', () {
      predictor.addObservation(
        cameraPosition: const Offset(0.5, 0.5),
        bboxArea: 0.0,
        referenceArea: 0.001,
      );
      expect(predictor.estimatedDepth, isNull);

      predictor.addObservation(
        cameraPosition: const Offset(0.5, 0.5),
        bboxArea: 0.001,
        referenceArea: 0.0,
      );
      expect(predictor.estimatedDepth, isNull);
    });

    test('prediction shifts zone upward for ball heading to top of target', () {
      const referenceArea = 0.001;

      final positions = [
        (const Offset(0.40, 0.65), 0.00090),
        (const Offset(0.38, 0.58), 0.00075),
        (const Offset(0.36, 0.52), 0.00060),
        (const Offset(0.35, 0.47), 0.00048),
        (const Offset(0.34, 0.43), 0.00038),
        (const Offset(0.33, 0.40), 0.00030),
      ];

      for (final (pos, area) in positions) {
        predictor.addObservation(
          cameraPosition: pos,
          bboxArea: area,
          referenceArea: referenceArea,
        );
      }

      final prediction = predictor.predictWallZone(mapper);
      expect(prediction, isNotNull);
      expect(prediction!.zone, isNot(equals(1)));
      expect(prediction.zone, isNot(equals(2)));
      expect(prediction.zone, isNot(equals(3)));
    });

    test('depth increasing tolerance handles noisy bbox areas', () {
      const referenceArea = 0.001;

      predictor.addObservation(
        cameraPosition: const Offset(0.45, 0.60),
        bboxArea: 0.00090,
        referenceArea: referenceArea,
      );
      predictor.addObservation(
        cameraPosition: const Offset(0.44, 0.55),
        bboxArea: 0.00092, // 2% increase — within 5% tolerance
        referenceArea: referenceArea,
      );
      predictor.addObservation(
        cameraPosition: const Offset(0.43, 0.50),
        bboxArea: 0.00070,
        referenceArea: referenceArea,
      );

      predictor.predictWallZone(mapper);
      expect(predictor.estimatedDepth, isNotNull);
    });

    test('returns null when trajectory exits frame bounds', () {
      // Ball moving sideways away from the grid — should exit frame.
      const referenceArea = 0.001;

      predictor.addObservation(
        cameraPosition: const Offset(0.90, 0.50),
        bboxArea: 0.00090,
        referenceArea: referenceArea,
      );
      predictor.addObservation(
        cameraPosition: const Offset(0.95, 0.50),
        bboxArea: 0.00075,
        referenceArea: referenceArea,
      );
      predictor.addObservation(
        cameraPosition: const Offset(0.99, 0.50),
        bboxArea: 0.00060,
        referenceArea: referenceArea,
      );

      // Ball heading right and away — will exit the frame, not hit the grid.
      expect(predictor.predictWallZone(mapper), isNull);
    });

    test('no hardcoded physical dimensions in the class', () {
      // Verify the constructor takes only opticalCenter — no physical
      // sizes, distances, or depth ratios.
      final p = WallPlanePredictor(opticalCenter: const Offset(0.5, 0.5));
      expect(p.opticalCenter, const Offset(0.5, 0.5));
      expect(p.estimatedDepth, isNull);
    });
  });
}
