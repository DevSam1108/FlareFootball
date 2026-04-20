import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/services/bytetrack_tracker.dart';
import 'package:tensorflow_demo/services/ball_identifier.dart';

// Helper: create a TrackedObject with sensible defaults.
TrackedObject _track({
  required int id,
  double cx = 0.5,
  double cy = 0.5,
  double w = 0.04,
  double h = 0.04,
  double vx = 0.0,
  double vy = 0.0,
  bool isStatic = false,
  TrackState state = TrackState.tracked,
  int totalFramesSeen = 1,
  int consecutiveLostFrames = 0,
  String className = 'Soccer ball',
  double confidence = 0.85,
}) {
  return TrackedObject(
    trackId: id,
    bbox: Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
    center: Offset(cx, cy),
    velocity: Offset(vx, vy),
    bboxArea: w * h,
    isStatic: isStatic,
    state: state,
    totalFramesSeen: totalFramesSeen,
    consecutiveLostFrames: consecutiveLostFrames,
    className: className,
    confidence: confidence,
  );
}

void main() {
  group('BallIdentifier - setReferenceTrack', () {
    // Phase 1 (Anchor Rectangle, 2026-04-19): setReferenceTrack now takes a
    // single TrackedObject chosen by the player via tap-to-select. The
    // previous "auto-pick largest" / class-filter / static-bypass logic has
    // moved up to the screen layer (which handles candidate filtering and
    // tap resolution), so the tests that exercised those behaviours are no
    // longer applicable to BallIdentifier. The tests below cover the new
    // contract: lock onto whichever track the caller passed in.

    test('locks onto the passed track id and records its bbox area', () {
      final bi = BallIdentifier();
      final chosen = _track(id: 7, cx: 0.4, cy: 0.6, w: 0.05, h: 0.05);
      bi.setReferenceTrack(chosen);
      expect(bi.currentBallTrackId, 7);
      expect(bi.currentBallTrack, chosen);
      expect(bi.lastBallPosition, const Offset(0.4, 0.6));
      expect(bi.lastBallBboxArea, closeTo(0.05 * 0.05, 0.0001));
    });

    test('locks regardless of bbox size (selection is the caller\'s job)', () {
      final bi = BallIdentifier();
      // A small/distant ball can be locked just as well as a large one —
      // BallIdentifier no longer prefers larger bboxes.
      final small = _track(id: 3, w: 0.02, h: 0.02);
      bi.setReferenceTrack(small);
      expect(bi.currentBallTrackId, 3);
    });

    test('a second call replaces the prior selection', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.05, h: 0.05));
      expect(bi.currentBallTrackId, 1);
      bi.setReferenceTrack(_track(id: 9, w: 0.06, h: 0.06));
      expect(bi.currentBallTrackId, 9);
    });
  });

  group('BallIdentifier - track following', () {
    test('follows current track ID across frames', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 5, cx: 0.2, cy: 0.7, w: 0.06, h: 0.06));

      for (var i = 0; i < 10; i++) {
        bi.updateFromTracks([
          _track(id: 5, cx: 0.2 + i * 0.02, cy: 0.7 - i * 0.02, vx: 0.02, vy: -0.02),
          _track(id: 10, cx: 0.4, cy: 0.45, isStatic: true, className: 'ball'),
        ]);
        expect(bi.currentBallTrackId, 5);
      }
    });

    test('maintains ball when other tracks appear and disappear', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 3, w: 0.06, h: 0.06));

      bi.updateFromTracks([
        _track(id: 3, cx: 0.3, cy: 0.5, vx: 0.01, vy: -0.01),
        _track(id: 7, cx: 0.4, cy: 0.4, isStatic: true, className: 'ball'),
        _track(id: 8, cx: 0.5, cy: 0.4, isStatic: true, className: 'ball'),
      ]);
      expect(bi.currentBallTrackId, 3);

      bi.updateFromTracks([
        _track(id: 3, cx: 0.31, cy: 0.49, vx: 0.01, vy: -0.01),
        _track(id: 7, cx: 0.4, cy: 0.4, isStatic: true, className: 'ball'),
      ]);
      expect(bi.currentBallTrackId, 3);
    });
  });

  group('BallIdentifier - re-acquisition', () {
    test('re-acquires when track removed and new moving track appears', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1, cx: 0.3, cy: 0.5, vx: 0.03, vy: -0.02)]);

      bi.updateFromTracks([
        _track(id: 10, cx: 0.4, cy: 0.45, isStatic: true, className: 'ball'),
      ]);
      expect(bi.currentBallTrack, isNull);

      bi.updateFromTracks([
        _track(id: 20, cx: 0.15, cy: 0.65, vx: 0.02, vy: -0.01),
        _track(id: 10, cx: 0.4, cy: 0.45, isStatic: true, className: 'ball'),
      ]);
      expect(bi.currentBallTrackId, 20);
    });

    test('re-acquires by proximity when no moving tracks', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, cx: 0.2, cy: 0.7, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1, cx: 0.2, cy: 0.7)]);

      bi.updateFromTracks([
        _track(id: 30, cx: 0.21, cy: 0.69),
        _track(id: 10, cx: 0.8, cy: 0.3, isStatic: true, className: 'ball'),
      ]);
      expect(bi.currentBallTrackId, 30);
    });

    test('static tracks ignored during re-acquisition', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, cx: 0.2, cy: 0.7, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1, cx: 0.2, cy: 0.7)]);

      bi.updateFromTracks([
        _track(id: 5, cx: 0.21, cy: 0.69, isStatic: true, className: 'ball'),
      ]);
      expect(bi.currentBallTrack, isNull);
    });
  });

  group('BallIdentifier - ball lost badge', () {
    test('isBallLost triggers after 3 missed frames', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1)]);
      expect(bi.isBallLost, isFalse);

      bi.updateFromTracks([]);
      expect(bi.isBallLost, isFalse);
      bi.updateFromTracks([]);
      expect(bi.isBallLost, isFalse);
      bi.updateFromTracks([]);
      expect(bi.isBallLost, isTrue);
    });

    test('isBallLost resets when ball re-detected', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1)]);

      for (var i = 0; i < 5; i++) {
        bi.updateFromTracks([]);
      }
      expect(bi.isBallLost, isTrue);

      bi.updateFromTracks([_track(id: 1)]);
      expect(bi.isBallLost, isFalse);
    });
  });

  group('BallIdentifier - trail', () {
    test('trail entries have correct TrackedPosition format', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1, cx: 0.3, cy: 0.5, vx: 0.02, vy: -0.01)]);

      expect(bi.trail.length, 1);
      final entry = bi.trail.first;
      expect(entry.normalizedCenter.dx, closeTo(0.3, 0.01));
      expect(entry.isOccluded, isFalse);
      expect(entry.vx, closeTo(0.02, 0.001));
      expect(entry.isPredicted, isFalse);
    });

    test('trail grows with ball movement', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));

      for (var i = 0; i < 5; i++) {
        bi.updateFromTracks([
          _track(id: 1, cx: 0.2 + i * 0.05, cy: 0.5, vx: 0.05, vy: 0.0),
        ]);
      }
      expect(bi.trail.length, 5);
    });

    test('trail adds occlusion sentinel when ball lost', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1, cx: 0.3, cy: 0.5)]);

      for (var i = 0; i < 7; i++) {
        bi.updateFromTracks([]);
      }
      final occluded = bi.trail.where((t) => t.isOccluded);
      expect(occluded.length, greaterThan(0));
    });

    test('trail auto-resets after 30 missed frames', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1, cx: 0.3, cy: 0.5)]);

      // Lose for exactly 30 frames to trigger auto-reset
      for (var i = 0; i < 30; i++) {
        bi.updateFromTracks([]);
      }
      // Trail should be cleared at the 30th frame
      expect(bi.trail.length, 0);
    });
  });

  group('BallIdentifier - velocity and smoothedPosition', () {
    test('velocity returns current ball track velocity', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1, vx: 0.03, vy: -0.02)]);
      expect(bi.velocity, const Offset(0.03, -0.02));
    });

    test('smoothedPosition returns current ball center', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1, cx: 0.4, cy: 0.6)]);
      expect(bi.smoothedPosition, const Offset(0.4, 0.6));
    });

    test('velocity returns null when no ball tracked', () {
      final bi = BallIdentifier();
      expect(bi.velocity, isNull);
    });
  });

  group('BallIdentifier - reset', () {
    test('reset clears all state', () {
      final bi = BallIdentifier();
      bi.setReferenceTrack(_track(id: 1, w: 0.06, h: 0.06));
      bi.updateFromTracks([_track(id: 1, cx: 0.3, cy: 0.5)]);

      bi.reset();
      expect(bi.currentBallTrackId, isNull);
      expect(bi.currentBallTrack, isNull);
      expect(bi.lastBallPosition, isNull);
      expect(bi.trail.length, 0);
      expect(bi.isBallLost, isFalse);
    });
  });
}
