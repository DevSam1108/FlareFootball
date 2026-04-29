import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/models/impact_event.dart';
import 'package:tensorflow_demo/services/impact_detector.dart';
import 'package:tensorflow_demo/services/kick_detector.dart' show KickState;
import 'package:tensorflow_demo/services/trajectory_extrapolator.dart';

void main() {
  group('ImpactDetector', () {
    late ImpactDetector detector;

    setUp(() {
      detector = ImpactDetector(
        resultDisplayDuration: const Duration(milliseconds: 50),
      );
    });

    test('initial state is ready', () {
      expect(detector.phase, DetectionPhase.ready);
      expect(detector.currentResult, isNull);
      expect(detector.statusText, contains('waiting for kick'));
    });

    test('ball with low velocity stays in ready', () {
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.001, 0.001), // below threshold
        rawPosition: const Offset(0.5, 0.5),
      );
      expect(detector.phase, DetectionPhase.ready);
    });

    test('ball with sufficient velocity transitions to tracking', () {
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.01, 0.01),
        rawPosition: const Offset(0.5, 0.5),
      );
      expect(detector.phase, DetectionPhase.tracking);
      expect(detector.statusText, 'Tracking...');
    });

    test('no directZone during tracking produces noResult', () {
      // Track for several frames without directZone (ball never enters grid).
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
        );
      }
      expect(detector.phase, DetectionPhase.tracking);

      // Ball lost.
      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }
      // No directZone was ever set → noResult.
      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.noResult);
    });

    test('edge exit produces miss result', () {
      // Track for enough frames near right edge.
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.95, 0.5), // within 8% of right edge
        );
      }

      // Ball lost.
      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.miss);
      expect(detector.statusText, 'MISS');
    });

    test('phantom decision suppressed when kickState=idle (Piece A, 2026-04-29)',
        () {
      // Reproduces the idle-jitter phantom-decision scenario: ImpactDetector
      // is pushed into tracking phase by stationary-ball detection wobble,
      // then the lost-frame trigger fires several frames later — but no real
      // kick ever happened. Without the gate, this would emit a HIT zone 5
      // decision (lastDirectZone is set during the jitter) and rely on the
      // audio kick gate downstream to silently reject it. With the gate,
      // _makeDecision suppresses construction entirely and resets to ready.
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          directZone: 5,
          kickState: KickState.idle,
        );
      }
      expect(detector.phase, DetectionPhase.tracking);

      // Ball lost — would normally trigger _makeDecision after 5 frames.
      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(
          ballDetected: false,
          kickState: KickState.idle,
        );
      }

      // Gate fires inside _makeDecision → _reset() → back to ready, no
      // result emitted. This is the core of Piece A.
      expect(detector.phase, DetectionPhase.ready);
      expect(detector.currentResult, isNull);
    });

    test('decision still fires when kickState=confirming (gate is permissive)',
        () {
      // Same shape as the test above but with kickState=confirming. The gate
      // must NOT trip — real kicks fire decisions exactly as before.
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          directZone: 5,
          kickState: KickState.confirming,
        );
      }
      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(
          ballDetected: false,
          kickState: KickState.confirming,
        );
      }

      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.hit);
      expect(detector.currentResult!.zone, 5);
    });

    test('directZone hit produces zone result', () {
      // Track with directZone set (ball enters grid).
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          directZone: 5,
        );
      }

      // Ball lost.
      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.hit);
      expect(detector.currentResult!.zone, 5);
      expect(detector.statusText, 'Zone 5');
    });

    test('last directZone wins over earlier directZone', () {
      // Ball passes through zone 1 then zone 6 then zone 7.
      for (int i = 0; i < 3; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, -0.02),
          rawPosition: const Offset(0.3, 0.6),
          directZone: 1,
        );
      }
      for (int i = 0; i < 3; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, -0.02),
          rawPosition: const Offset(0.3, 0.5),
          directZone: 6,
        );
      }
      for (int i = 0; i < 3; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, -0.02),
          rawPosition: const Offset(0.3, 0.4),
          directZone: 7,
        );
      }

      // Ball lost.
      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.hit);
      expect(detector.currentResult!.zone, 7);
    });

    test('no directZone and no edge produces noResult', () {
      // Track for enough frames in center, no directZone.
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
        );
      }

      // Ball lost.
      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.noResult);
      expect(detector.statusText, 'No result');
    });

    test('result expires after cooldown', () async {
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          directZone: 8,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }
      expect(detector.phase, DetectionPhase.result);

      // Wait for cooldown to expire.
      await Future.delayed(const Duration(milliseconds: 100));

      detector.processFrame(ballDetected: false);
      expect(detector.phase, DetectionPhase.ready);
    });

    test('forceReset returns to ready from tracking', () {
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
        );
      }
      expect(detector.phase, DetectionPhase.tracking);

      detector.forceReset();
      expect(detector.phase, DetectionPhase.ready);
      expect(detector.currentResult, isNull);
    });

    test('ball reappearing during lost window cancels decision', () {
      // Enter tracking.
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
        );
      }

      // Ball lost for fewer frames than threshold.
      for (int i = 0; i < ImpactDetector.lostFrameThreshold - 1; i++) {
        detector.processFrame(ballDetected: false);
      }
      expect(detector.phase, DetectionPhase.tracking);

      // Ball reappears -- should stay in tracking.
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.01, 0.01),
        rawPosition: const Offset(0.5, 0.5),
      );
      expect(detector.phase, DetectionPhase.tracking);
    });

    test('does not enter tracking without velocity', () {
      detector.processFrame(
        ballDetected: true,
        rawPosition: const Offset(0.5, 0.5),
      );
      expect(detector.phase, DetectionPhase.ready);
    });

    test('edge threshold works on all four edges', () {
      // Near left edge.
      _trackAndLose(detector, const Offset(0.03, 0.5));
      expect(detector.currentResult!.result, ImpactResult.miss);
      detector.forceReset();

      // Near top edge.
      _trackAndLose(detector, const Offset(0.5, 0.03));
      expect(detector.currentResult!.result, ImpactResult.miss);
      detector.forceReset();

      // Near bottom edge.
      _trackAndLose(detector, const Offset(0.5, 0.97));
      expect(detector.currentResult!.result, ImpactResult.miss);
      detector.forceReset();

      // Near right edge.
      _trackAndLose(detector, const Offset(0.97, 0.5));
      expect(detector.currentResult!.result, ImpactResult.miss);
    });

    test('edge filter takes priority over directZone', () {
      // Track near edge with a directZone set.
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.95, 0.5), // near right edge
          directZone: 5,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      // Edge filter should win -- result is MISS, not hit.
      expect(detector.currentResult!.result, ImpactResult.miss);
    });

    test('directZone cleared on reset does not carry over', () {
      // First kick: ball enters zone 3.
      for (int i = 0; i < 5; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.3, 0.5),
          directZone: 3,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }
      expect(detector.currentResult!.result, ImpactResult.hit);
      expect(detector.currentResult!.zone, 3);

      // Force reset simulating cooldown.
      detector.forceReset();

      // Second kick: ball never enters grid.
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      // Should be noResult — NOT zone 3 from previous kick.
      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.noResult);
    });

    test('ignores frames during result phase', () {
      _trackAndLose(
        detector,
        const Offset(0.5, 0.5),
        directZone: 7,
      );
      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.zone, 7);

      // New ball detection during result phase should be ignored.
      detector.processFrame(
        ballDetected: true,
        velocity: const Offset(0.05, 0.05),
        rawPosition: const Offset(0.2, 0.2),
      );
      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.zone, 7);
    });

    // -----------------------------------------------------------------------
    // Depth-related tests — directZone is now the primary signal, but
    // depth-verified zone is still stored for diagnostics. These tests
    // verify that directZone produces correct results regardless of depth.
    // -----------------------------------------------------------------------

    test('directZone hit works with good depth ratio', () {
      detector.setReferenceBboxArea(0.04);

      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          bboxArea: 0.04, // ratio = 1.0
          directZone: 5,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.hit);
      expect(detector.currentResult!.zone, 5);
    });

    test('directZone hit works with low depth ratio', () {
      detector.setReferenceBboxArea(0.04);

      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          bboxArea: 0.004, // ratio = 0.1
          directZone: 5,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.hit);
      expect(detector.currentResult!.zone, 5);
    });

    test('directZone hit works with high depth ratio', () {
      detector.setReferenceBboxArea(0.01);

      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          bboxArea: 0.03, // ratio = 3.0
          directZone: 5,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.phase, DetectionPhase.result);
      expect(detector.currentResult!.result, ImpactResult.hit);
      expect(detector.currentResult!.zone, 5);
    });

    test('directZone hit works without reference area', () {
      // No setReferenceBboxArea called.
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          bboxArea: 0.001,
          directZone: 5,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.currentResult!.result, ImpactResult.hit);
    });

    test('last bbox area tracked correctly (behind-kicker camera)', () {
      detector.setReferenceBboxArea(0.01);

      // Ball starts large (near kicker/camera), shrinks toward target.
      for (int i = 0; i < 5; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          bboxArea: 0.04,
          directZone: 5,
        );
      }

      // Final frames: ball near target depth.
      for (int i = 0; i < 5; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          bboxArea: 0.012,
          directZone: 5,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.currentResult!.result, ImpactResult.hit);
      expect(detector.currentResult!.zone, 5);
    });

    test('edge filter takes priority over depth filter', () {
      detector.setReferenceBboxArea(0.04);

      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.95, 0.5), // near edge
          bboxArea: 0.04, // good depth
          directZone: 5,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      // Edge filter wins -> MISS.
      expect(detector.currentResult!.result, ImpactResult.miss);
    });

    test('clearReferenceBboxArea disables depth filtering', () {
      detector.setReferenceBboxArea(0.04);
      detector.clearReferenceBboxArea();

      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          ballDetected: true,
          velocity: const Offset(0.01, 0.01),
          rawPosition: const Offset(0.5, 0.5),
          bboxArea: 0.001,
          directZone: 5,
        );
      }

      for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
        detector.processFrame(ballDetected: false);
      }

      expect(detector.currentResult!.result, ImpactResult.hit);
    });
  });
}

/// Helper: track a ball at [position] for enough frames, then lose it.
void _trackAndLose(
  ImpactDetector detector,
  Offset position, {
  ExtrapolationResult? extrapolation,
  int? directZone,
}) {
  for (int i = 0; i < 10; i++) {
    detector.processFrame(
      ballDetected: true,
      velocity: const Offset(0.01, 0.01),
      extrapolation: extrapolation,
      rawPosition: position,
      directZone: directZone,
    );
  }
  for (int i = 0; i < ImpactDetector.lostFrameThreshold; i++) {
    detector.processFrame(ballDetected: false);
  }
}
