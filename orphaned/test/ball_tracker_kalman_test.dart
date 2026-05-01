import 'package:flutter_test/flutter_test.dart';

import 'package:tensorflow_demo/services/ball_tracker.dart';

void main() {
  group('BallTracker Kalman integration', () {
    late BallTracker tracker;

    setUp(() {
      tracker = BallTracker();
    });

    test('smoothing reduces jitter compared to raw inputs', () {
      // Feed 20 positions along y=0.5 with random jitter.
      final rawPositions = <Offset>[];
      final jitterPattern = [
        0.008, -0.006, 0.009, -0.007, 0.005,
        -0.008, 0.006, -0.009, 0.007, -0.005,
        0.008, -0.006, 0.009, -0.007, 0.005,
        -0.008, 0.006, -0.009, 0.007, -0.005,
      ];

      for (int i = 0; i < 20; i++) {
        final raw = Offset(0.1 + i * 0.02, 0.5 + jitterPattern[i]);
        rawPositions.add(raw);
        tracker.update(raw);
      }

      final trail = tracker.trail;
      // Measure perpendicular distance from ideal line y=0.5
      double rawVariance = 0;
      for (final pos in rawPositions) {
        final diff = pos.dy - 0.5;
        rawVariance += diff * diff;
      }
      rawVariance /= rawPositions.length;

      double smoothedVariance = 0;
      int count = 0;
      for (final entry in trail) {
        if (!entry.isOccluded) {
          final diff = entry.normalizedCenter.dy - 0.5;
          smoothedVariance += diff * diff;
          count++;
        }
      }
      if (count > 0) smoothedVariance /= count;

      expect(smoothedVariance, lessThan(rawVariance),
          reason: 'Smoothed positions should have less variance than raw');
    });

    test('occlusion prediction produces 5 predicted positions', () {
      // Feed 10 positions moving right at ~0.02/frame.
      for (int i = 0; i < 10; i++) {
        tracker.update(Offset(0.2 + i * 0.02, 0.5));
      }

      // Occlude for 5 frames.
      for (int i = 0; i < 5; i++) {
        tracker.markOccluded();
      }

      final trail = tracker.trail;
      final predicted =
          trail.where((e) => e.isPredicted).toList();

      expect(predicted.length, equals(5));

      // All predicted positions should have isOccluded = false.
      for (final p in predicted) {
        expect(p.isOccluded, isFalse);
      }

      // Predicted x-coordinates should advance roughly by 0.02 per frame.
      for (int i = 1; i < predicted.length; i++) {
        final dx =
            predicted[i].normalizedCenter.dx - predicted[i - 1].normalizedCenter.dx;
        expect(dx, greaterThan(0.005),
            reason: 'Predicted positions should advance in x');
      }
    });

    test('prediction stops after horizon, sentinels inserted', () {
      // Feed 10 positions moving right.
      for (int i = 0; i < 10; i++) {
        tracker.update(Offset(0.2 + i * 0.02, 0.5));
      }

      // Occlude for 8 frames (beyond the 5-frame horizon).
      for (int i = 0; i < 8; i++) {
        tracker.markOccluded();
      }

      final trail = tracker.trail;
      final predicted = trail.where((e) => e.isPredicted).toList();
      final sentinels = trail.where((e) => e.isOccluded).toList();

      // Exactly 5 predicted positions.
      expect(predicted.length, equals(5));

      // At least 1 occlusion sentinel after the predictions.
      expect(sentinels.length, greaterThanOrEqualTo(1));
    });

    test('velocity API returns correct direction', () {
      // Feed 10 positions moving diagonally (right and down).
      for (int i = 0; i < 10; i++) {
        tracker.update(Offset(0.2 + i * 0.02, 0.3 + i * 0.01));
      }

      final vel = tracker.velocity;
      expect(vel, isNotNull);
      expect(vel!.dx, greaterThan(0), reason: 'Moving right, vx > 0');
      expect(vel.dy, greaterThan(0), reason: 'Moving down, vy > 0');
    });

    test('smoothedPosition returns Kalman state', () {
      tracker.update(const Offset(0.5, 0.5));

      final pos = tracker.smoothedPosition;
      expect(pos, isNotNull);
      expect(pos!.dx, closeTo(0.5, 0.05));
      expect(pos.dy, closeTo(0.5, 0.05));
    });

    test('reset clears velocity and trail', () {
      for (int i = 0; i < 5; i++) {
        tracker.update(Offset(0.2 + i * 0.02, 0.5));
      }
      expect(tracker.velocity, isNotNull);
      expect(tracker.trail, isNotEmpty);

      tracker.reset();

      expect(tracker.velocity, isNull);
      expect(tracker.smoothedPosition, isNull);
      expect(tracker.trail, isEmpty);
    });

    test('isBallLost behavior is preserved', () {
      // Feed some positions.
      for (int i = 0; i < 5; i++) {
        tracker.update(Offset(0.2 + i * 0.02, 0.5));
      }
      expect(tracker.isBallLost, isFalse);

      // Miss ballLostThreshold frames — isBallLost triggers.
      // Note: during prediction horizon, missed frames still count toward
      // ballLostThreshold, so isBallLost can trigger during prediction.
      for (int i = 0; i < BallTracker.ballLostThreshold; i++) {
        tracker.markOccluded();
      }
      expect(tracker.isBallLost, isTrue);

      // Re-detect the ball — isBallLost resets.
      tracker.update(const Offset(0.5, 0.5));
      expect(tracker.isBallLost, isFalse);
    });

    test('auto-reset at threshold still works', () {
      tracker.update(const Offset(0.5, 0.5));

      // Miss autoResetThreshold frames.
      for (int i = 0; i < BallTracker.autoResetThreshold; i++) {
        tracker.markOccluded();
      }

      expect(tracker.trail, isEmpty);
      expect(tracker.velocity, isNull);
      expect(tracker.smoothedPosition, isNull);
    });
  });
}
