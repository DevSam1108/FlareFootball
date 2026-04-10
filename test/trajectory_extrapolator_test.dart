import 'package:flutter_test/flutter_test.dart';

import 'package:tensorflow_demo/services/homography_transform.dart';
import 'package:tensorflow_demo/services/target_zone_mapper.dart';
import 'package:tensorflow_demo/services/trajectory_extrapolator.dart';

void main() {
  group('TrajectoryExtrapolator', () {
    /// Identity homography: target = full camera frame.
    TargetZoneMapper identityMapper() {
      final h = HomographyTransform.fromCorrespondences(
        const [
          Offset(0.0, 0.0),
          Offset(1.0, 0.0),
          Offset(1.0, 1.0),
          Offset(0.0, 1.0),
        ],
        const [
          Offset(0.0, 0.0),
          Offset(1.0, 0.0),
          Offset(1.0, 1.0),
          Offset(0.0, 1.0),
        ],
      );
      return TargetZoneMapper(h);
    }

    /// Right-half homography: target occupies x=[0.5, 1.0], y=[0.0, 1.0].
    TargetZoneMapper rightHalfMapper() {
      final h = HomographyTransform.fromCorrespondences(
        const [
          Offset(0.5, 0.0),
          Offset(1.0, 0.0),
          Offset(1.0, 1.0),
          Offset(0.5, 1.0),
        ],
        const [
          Offset(0.0, 0.0),
          Offset(1.0, 0.0),
          Offset(1.0, 1.0),
          Offset(0.0, 1.0),
        ],
      );
      return TargetZoneMapper(h);
    }

    test('ball inside identity target hits immediately', () {
      final extrapolator = TrajectoryExtrapolator();
      final mapper = identityMapper();

      final result = extrapolator.extrapolate(
        position: const Offset(0.5, 0.5),
        velocity: const Offset(0.05, 0.0),
        zoneMapper: mapper,
      );

      // Ball is already inside the target (full frame).
      expect(result, isNotNull);
      expect(result!.framesAhead, equals(1));
      expect(result.zone, inInclusiveRange(1, 9));
    });

    test('ball moving right toward right-half target hits after some frames', () {
      final extrapolator = TrajectoryExtrapolator(gravity: 0.0);
      final mapper = rightHalfMapper();

      final result = extrapolator.extrapolate(
        position: const Offset(0.1, 0.5),
        velocity: const Offset(0.05, 0.0),
        zoneMapper: mapper,
      );

      expect(result, isNotNull);
      // Ball needs to travel from x=0.1 to x>=0.5 at 0.05/frame.
      // At t=8: x = 0.1 + 0.05*8 = 0.5 -> enters target.
      expect(result!.framesAhead, greaterThanOrEqualTo(8));
      expect(result.zone, inInclusiveRange(1, 9));
      expect(result.cameraPoint.dx, greaterThanOrEqualTo(0.5));
    });

    test('ball moving away from target returns null', () {
      final extrapolator = TrajectoryExtrapolator();
      final mapper = rightHalfMapper();

      final result = extrapolator.extrapolate(
        position: const Offset(0.4, 0.5),
        velocity: const Offset(-0.05, 0.0), // moving left, away from target
        zoneMapper: mapper,
      );

      expect(result, isNull);
    });

    test('stationary ball returns null', () {
      final extrapolator = TrajectoryExtrapolator();
      final mapper = identityMapper();

      final result = extrapolator.extrapolate(
        position: const Offset(0.5, 0.5),
        velocity: const Offset(0.0005, 0.0), // below threshold
        zoneMapper: mapper,
      );

      expect(result, isNull);
    });

    test('parabolic arc produces lower y than linear prediction', () {
      // Ball launched upward-right, gravity pulls it down.
      final extrapolator = TrajectoryExtrapolator(gravity: 0.002);
      final mapper = rightHalfMapper();

      // Velocity: right and upward (negative y = up in camera space).
      final result = extrapolator.extrapolate(
        position: const Offset(0.1, 0.5),
        velocity: const Offset(0.05, -0.01),
        zoneMapper: mapper,
      );

      expect(result, isNotNull);
      final t = result!.framesAhead.toDouble();

      // Linear y prediction (no gravity): y = 0.5 + (-0.01) * t
      final linearY = 0.5 + (-0.01) * t;
      // Parabolic y: y = 0.5 + (-0.01) * t + 0.5 * 0.002 * t^2
      // gravity > 0 means y is pulled higher (larger) than linear.
      expect(result.cameraPoint.dy, greaterThan(linearY),
          reason: 'Gravity should pull the y-coordinate down (higher value)');
    });

    test('max frames exceeded returns null', () {
      // Ball moving very slowly toward a distant target.
      final extrapolator = TrajectoryExtrapolator(
        gravity: 0.0,
        maxFrames: 10,
      );
      final mapper = rightHalfMapper();

      final result = extrapolator.extrapolate(
        position: const Offset(0.1, 0.5),
        velocity: const Offset(0.002, 0.0), // very slow
        zoneMapper: mapper,
      );

      // At t=10: x = 0.1 + 0.002*10 = 0.12, far from target at x=0.5.
      expect(result, isNull);
    });

    test('zone number is correct for center hit', () {
      final extrapolator = TrajectoryExtrapolator(gravity: 0.0);
      final mapper = identityMapper();

      // Ball at center of frame heading right -> zone 5 (center of grid).
      final result = extrapolator.extrapolate(
        position: const Offset(0.4, 0.5),
        velocity: const Offset(0.05, 0.0),
        zoneMapper: mapper,
      );

      expect(result, isNotNull);
      // At the center of the frame the zone should be 5.
      expect(result!.zone, equals(5));
    });
  });
}
