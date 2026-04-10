import 'dart:ui' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/services/kick_detector.dart';

void main() {
  late KickDetector detector;

  setUp(() {
    detector = KickDetector();
  });

  // Helper: feed a frame with given velocity magnitude.
  // Velocity is directed toward positive X (rightward).
  void feedVelocity(double mag, {Offset? ballPos, Offset? goalCenter}) {
    detector.processFrame(
      ballDetected: true,
      velocity: Offset(mag, 0),
      ballPosition: ballPos ?? const Offset(0.3, 0.5),
      goalCenter: goalCenter ?? const Offset(0.7, 0.5),
    );
  }

  group('KickDetector', () {
    test('starts in idle state', () {
      expect(detector.state, KickState.idle);
      expect(detector.isKickActive, false);
    });

    test('jerk spike transitions idle → confirming', () {
      // Frame 1-2: zero velocity (builds history)
      feedVelocity(0);
      feedVelocity(0);
      expect(detector.state, KickState.idle);

      // Frame 3: sudden large velocity = jerk spike
      feedVelocity(0.1);
      expect(detector.state, KickState.confirming);
    });

    test('sustained energy + direction → confirming → active', () {
      // Build jerk spike
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1); // jerk spike → confirming
      expect(detector.state, KickState.confirming);

      // Sustain high speed for sustainFrames (3 total including the spike frame)
      // sustainCount was set to 1 on entering confirming, need 2 more
      feedVelocity(0.08);
      feedVelocity(0.07);
      expect(detector.state, KickState.active);
      expect(detector.isKickActive, true);
    });

    test('low velocity in confirming → falls back to idle', () {
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1); // → confirming
      expect(detector.state, KickState.confirming);

      // Speed drops below sustainThreshold
      feedVelocity(0.001);
      expect(detector.state, KickState.idle);
    });

    test('wrong direction → stays confirming, times out to idle', () {
      // Ball at (0.7, 0.5), goal at (0.3, 0.5) — ball is RIGHT of goal.
      // Velocity pointing right (positive X) = AWAY from goal.
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(
        0.1,
        ballPos: const Offset(0.7, 0.5),
        goalCenter: const Offset(0.3, 0.5),
      ); // → confirming
      expect(detector.state, KickState.confirming);

      // Keep feeding frames with wrong direction — should NOT reach active.
      // Need 8 frames in _processConfirming to exceed maxConfirmingFrames (8).
      // _confirmingFrameCount starts at 1 from _processIdle, so 8 more calls
      // reaches 9 which is > 8.
      for (var i = 0; i < 8; i++) {
        feedVelocity(
          0.08,
          ballPos: const Offset(0.7, 0.5),
          goalCenter: const Offset(0.3, 0.5),
        );
      }
      expect(detector.state, KickState.idle);
    });

    test('onKickComplete transitions active → refractory', () {
      // Get to active
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1);
      feedVelocity(0.08);
      feedVelocity(0.07);
      expect(detector.state, KickState.active);

      detector.onKickComplete();
      expect(detector.state, KickState.refractory);
      expect(detector.isKickActive, false);
    });

    test('refractory counts down and returns to idle', () {
      // Get to active then refractory
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1);
      feedVelocity(0.08);
      feedVelocity(0.07);
      detector.onKickComplete();
      expect(detector.state, KickState.refractory);

      // Feed frames until refractory expires
      for (var i = 0; i < KickDetector.refractoryFrames; i++) {
        detector.processFrame(ballDetected: false);
      }
      expect(detector.state, KickState.idle);
    });

    test('ball loss during confirming stays confirming while impact is tracking', () {
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1); // → confirming

      // Ball lost but ImpactDetector is still tracking → stay confirming.
      detector.processFrame(ballDetected: false, isImpactTracking: true);
      expect(detector.state, KickState.confirming);
      detector.processFrame(ballDetected: false, isImpactTracking: true);
      expect(detector.state, KickState.confirming);
    });

    test('ball loss during confirming resets to idle when impact not tracking', () {
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1); // → confirming

      // Ball lost and ImpactDetector is NOT tracking → back to idle.
      detector.processFrame(ballDetected: false, isImpactTracking: false);
      expect(detector.state, KickState.idle);
    });

    test('ball reappears after loss during confirming → continues to active', () {
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1); // → confirming, sustainCount=1

      // Ball lost but impact is tracking → stay confirming
      detector.processFrame(ballDetected: false, isImpactTracking: true);
      expect(detector.state, KickState.confirming);

      // Ball reappears with sustained speed → can still reach active
      feedVelocity(0.08);
      feedVelocity(0.07);
      expect(detector.state, KickState.active);
    });

    test('max active duration safety net → refractory', () {
      // Get to active
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1);
      feedVelocity(0.08);
      feedVelocity(0.07);
      expect(detector.state, KickState.active);

      // Feed frames until maxActiveFrames exceeded
      for (var i = 0; i < KickDetector.maxActiveFrames; i++) {
        detector.processFrame(ballDetected: true, velocity: const Offset(0.05, 0));
      }
      expect(detector.state, KickState.refractory);
    });

    test('isKickActive is true only in active state', () {
      expect(detector.isKickActive, false); // idle

      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1);
      expect(detector.isKickActive, false); // confirming

      feedVelocity(0.08);
      feedVelocity(0.07);
      expect(detector.isKickActive, true); // active

      detector.onKickComplete();
      expect(detector.isKickActive, false); // refractory
    });

    test('reset returns to idle and clears all state', () {
      feedVelocity(0);
      feedVelocity(0);
      feedVelocity(0.1);
      feedVelocity(0.08);
      feedVelocity(0.07);
      expect(detector.state, KickState.active);

      detector.reset();
      expect(detector.state, KickState.idle);
      expect(detector.isKickActive, false);
    });

    test('gradual dribble velocity does not trigger jerk gate', () {
      // Simulate gradual velocity increase (dribbling)
      feedVelocity(0);
      feedVelocity(0.002);
      feedVelocity(0.004);
      feedVelocity(0.006);
      feedVelocity(0.008);
      feedVelocity(0.010);
      // Jerk from gradual increase is small — should stay idle
      expect(detector.state, KickState.idle);
    });

    test('no goalCenter gracefully allows direction check', () {
      // Direction check should return true when goalCenter is null
      feedVelocity(0);
      feedVelocity(0);
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.1, 0),
        ballPosition: const Offset(0.3, 0.5),
        goalCenter: null, // no calibration yet
      );
      expect(detector.state, KickState.confirming);

      // Should still be able to reach active without goalCenter
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.08, 0),
        ballPosition: const Offset(0.3, 0.5),
        goalCenter: null,
      );
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.07, 0),
        ballPosition: const Offset(0.3, 0.5),
        goalCenter: null,
      );
      expect(detector.state, KickState.active);
    });
  });
}
