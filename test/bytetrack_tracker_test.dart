import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/services/bytetrack_tracker.dart';

// Helper: create a Detection at a given center with default size.
Detection _det(double cx, double cy,
    {double w = 0.04, double h = 0.04, double conf = 0.8, String cls = 'Soccer ball'}) {
  return Detection(
    bbox: Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
    confidence: conf,
    className: cls,
  );
}

void main() {
  group('computeIoU', () {
    test('identical rects return 1.0', () {
      final r = const Rect.fromLTRB(0.1, 0.1, 0.3, 0.3);
      expect(computeIoU(r, r), closeTo(1.0, 1e-6));
    });

    test('non-overlapping rects return 0.0', () {
      final a = const Rect.fromLTRB(0.0, 0.0, 0.1, 0.1);
      final b = const Rect.fromLTRB(0.5, 0.5, 0.6, 0.6);
      expect(computeIoU(a, b), 0.0);
    });

    test('partial overlap returns correct value', () {
      final a = const Rect.fromLTRB(0.0, 0.0, 0.2, 0.2); // area 0.04
      final b = const Rect.fromLTRB(0.1, 0.1, 0.3, 0.3); // area 0.04
      // intersection: 0.1x0.1 = 0.01, union: 0.04+0.04-0.01 = 0.07
      expect(computeIoU(a, b), closeTo(0.01 / 0.07, 1e-6));
    });

    test('zero-area rect returns 0.0', () {
      final a = const Rect.fromLTRB(0.1, 0.1, 0.1, 0.1); // zero area
      final b = const Rect.fromLTRB(0.0, 0.0, 0.2, 0.2);
      expect(computeIoU(a, b), 0.0);
    });
  });

  group('ByteTrackTracker - single object', () {
    test('first detection creates a tracked object with ID', () {
      final tracker = ByteTrackTracker();
      final tracks = tracker.update([_det(0.5, 0.5)]);
      expect(tracks.length, 1);
      expect(tracks.first.state, TrackState.tracked);
      expect(tracks.first.trackId, greaterThan(0));
      expect(tracks.first.center.dx, closeTo(0.5, 0.01));
    });

    test('same object across 10 frames maintains same ID', () {
      final tracker = ByteTrackTracker();
      int? firstId;
      for (var i = 0; i < 10; i++) {
        final x = 0.3 + i * 0.02; // moving right slowly
        final tracks = tracker.update([_det(x, 0.5)]);
        expect(tracks.length, 1);
        firstId ??= tracks.first.trackId;
        expect(tracks.first.trackId, firstId);
        expect(tracks.first.state, TrackState.tracked);
      }
    });

    test('velocity estimate converges for constant-motion object', () {
      final tracker = ByteTrackTracker();
      late TrackedObject last;
      for (var i = 0; i < 15; i++) {
        final x = 0.2 + i * 0.01;
        final tracks = tracker.update([_det(x, 0.5)]);
        last = tracks.first;
      }
      // After 15 frames of constant motion, vx should be near 0.01
      expect(last.velocity.dx, closeTo(0.01, 0.005));
      expect(last.velocity.dy, closeTo(0.0, 0.005));
    });

    test('bbox area is tracked correctly', () {
      final tracker = ByteTrackTracker();
      final tracks = tracker.update([_det(0.5, 0.5, w: 0.06, h: 0.04)]);
      expect(tracks.first.bboxArea, closeTo(0.06 * 0.04, 0.001));
    });

    test('sizeVelocity is zero on first detection', () {
      final tracker = ByteTrackTracker();
      final tracks = tracker.update([_det(0.5, 0.5, w: 0.04, h: 0.04)]);
      expect(tracks.first.sizeVelocity.dx, 0.0);
      expect(tracks.first.sizeVelocity.dy, 0.0);
    });

    test('sizeVelocity components positive when bbox grows over time', () {
      final tracker = ByteTrackTracker();
      late TrackedObject last;
      // Bbox grows by 0.002 per frame in both dimensions (ball approaching).
      for (var i = 0; i < 15; i++) {
        final size = 0.04 + i * 0.002;
        final tracks = tracker.update([_det(0.5, 0.5, w: size, h: size)]);
        last = tracks.first;
      }
      expect(last.sizeVelocity.dx, greaterThan(0.0));
      expect(last.sizeVelocity.dy, greaterThan(0.0));
    });

    test('sizeVelocity components negative when bbox shrinks over time', () {
      final tracker = ByteTrackTracker();
      late TrackedObject last;
      // Bbox shrinks by 0.002 per frame in both dimensions (ball receding).
      for (var i = 0; i < 15; i++) {
        final size = 0.08 - i * 0.002;
        final tracks = tracker.update([_det(0.5, 0.5, w: size, h: size)]);
        last = tracks.first;
      }
      expect(last.sizeVelocity.dx, lessThan(0.0));
      expect(last.sizeVelocity.dy, lessThan(0.0));
    });
  });

  group('ByteTrackTracker - track lifecycle', () {
    test('undetected object transitions to lost state', () {
      final tracker = ByteTrackTracker();
      tracker.update([_det(0.5, 0.5)]);
      // Now send empty detections
      final tracks = tracker.update([]);
      expect(tracks.length, 1);
      expect(tracks.first.state, TrackState.lost);
      expect(tracks.first.consecutiveLostFrames, 1);
    });

    test('lost track is removed after maxLostFrames', () {
      final tracker = ByteTrackTracker(maxLostFrames: 5);
      tracker.update([_det(0.5, 0.5)]);
      // Send empty for 6 frames
      late List<TrackedObject> tracks;
      for (var i = 0; i < 7; i++) {
        tracks = tracker.update([]);
      }
      // Track should be removed (not in output)
      expect(tracks.where((t) => t.state != TrackState.removed).length, 0);
    });

    test('lost track re-acquired when detection reappears nearby', () {
      final tracker = ByteTrackTracker();
      // Track for 5 frames
      for (var i = 0; i < 5; i++) {
        tracker.update([_det(0.5, 0.5)]);
      }
      final idBefore = tracker.tracks.first.trackId;
      // Lose for 2 frames
      tracker.update([]);
      tracker.update([]);
      // Reappear near predicted position
      final tracks = tracker.update([_det(0.5, 0.5)]);
      // Should re-acquire same ID
      final reacquired = tracks.where((t) => t.trackId == idBefore);
      expect(reacquired.length, 1);
      expect(reacquired.first.state, TrackState.tracked);
    });
  });

  group('ByteTrackTracker - two-pass matching', () {
    test('high-confidence detection matched in pass 1', () {
      final tracker = ByteTrackTracker();
      tracker.update([_det(0.5, 0.5, conf: 0.9)]);
      final id = tracker.tracks.first.trackId;
      // Next frame: high confidence slightly moved
      final tracks = tracker.update([_det(0.51, 0.5, conf: 0.8)]);
      expect(tracks.first.trackId, id);
    });

    test('low-confidence detection matched in pass 2', () {
      final tracker = ByteTrackTracker();
      // Establish track with high confidence
      for (var i = 0; i < 5; i++) {
        tracker.update([_det(0.5 + i * 0.01, 0.5, conf: 0.9)]);
      }
      final id = tracker.tracks.first.trackId;
      // Next frame: only a low-confidence detection at predicted position
      final tracks = tracker.update([_det(0.55, 0.5, conf: 0.3)]);
      // Should match via pass 2
      final matched = tracks.where((t) => t.trackId == id);
      expect(matched.length, 1);
      expect(matched.first.state, TrackState.tracked);
    });

    test('low-confidence detection does NOT create a new track', () {
      final tracker = ByteTrackTracker();
      // Only low-confidence detections — should not spawn new tracks
      final tracks = tracker.update([_det(0.5, 0.5, conf: 0.3)]);
      expect(tracks.length, 0);
    });
  });

  group('ByteTrackTracker - multi-object', () {
    test('two objects at different positions get different IDs', () {
      final tracker = ByteTrackTracker();
      final tracks = tracker.update([
        _det(0.2, 0.3),
        _det(0.8, 0.7),
      ]);
      expect(tracks.length, 2);
      expect(tracks[0].trackId, isNot(tracks[1].trackId));
    });

    test('two objects maintain separate IDs across 10 frames', () {
      final tracker = ByteTrackTracker();
      int? id1, id2;
      for (var i = 0; i < 10; i++) {
        final tracks = tracker.update([
          _det(0.2 + i * 0.01, 0.3), // object 1 moving right
          _det(0.8 - i * 0.01, 0.7), // object 2 moving left
        ]);
        expect(tracks.length, 2);
        id1 ??= tracks[0].trackId;
        id2 ??= tracks[1].trackId;
        // One of the tracks should be id1, the other id2
        final ids = tracks.map((t) => t.trackId).toSet();
        expect(ids, contains(id1));
        expect(ids, contains(id2));
      }
    });

    test('static object detected with moving object', () {
      final tracker = ByteTrackTracker(staticMinFrames: 10, staticMaxDisplacement: 0.01);
      // Static object at (0.3, 0.4), moving object starting at (0.1, 0.5)
      for (var i = 0; i < 15; i++) {
        tracker.update([
          _det(0.3, 0.4), // static
          _det(0.1 + i * 0.02, 0.5), // moving
        ]);
      }
      final tracks = tracker.tracks;
      expect(tracks.length, 2);
      final staticTrack = tracks.where((t) => t.isStatic).toList();
      final movingTrack = tracks.where((t) => !t.isStatic).toList();
      expect(staticTrack.length, 1);
      expect(movingTrack.length, 1);
      expect(staticTrack.first.center.dx, closeTo(0.3, 0.02));
    });
  });

  group('ByteTrackTracker - static detection', () {
    test('stationary detection flagged as static after sufficient frames', () {
      final tracker = ByteTrackTracker(staticMinFrames: 20, staticMaxDisplacement: 0.01);
      for (var i = 0; i < 25; i++) {
        tracker.update([_det(0.5, 0.5)]);
      }
      expect(tracker.tracks.first.isStatic, isTrue);
    });

    test('moving detection NOT flagged as static', () {
      final tracker = ByteTrackTracker(staticMinFrames: 20, staticMaxDisplacement: 0.01);
      for (var i = 0; i < 25; i++) {
        tracker.update([_det(0.2 + i * 0.02, 0.5)]);
      }
      expect(tracker.tracks.first.isStatic, isFalse);
    });

    test('static flag stays true with minor jitter', () {
      final tracker = ByteTrackTracker(staticMinFrames: 10, staticMaxDisplacement: 0.01);
      // Static for 15 frames
      for (var i = 0; i < 15; i++) {
        tracker.update([_det(0.5, 0.5)]);
      }
      expect(tracker.tracks.first.isStatic, isTrue);
      final staticId = tracker.tracks.first.trackId;
      // Now jitter very slightly — should still match same track via IoU
      for (var i = 0; i < 5; i++) {
        tracker.update([_det(0.5 + i * 0.0005, 0.5)]);
      }
      final track = tracker.tracks.where((t) => t.trackId == staticId);
      expect(track.length, 1);
      expect(track.first.isStatic, isTrue);
    });

    test('static flag clears when object starts moving (static → dynamic)', () {
      final tracker = ByteTrackTracker(staticMinFrames: 10, staticMaxDisplacement: 0.01);
      // Static for 15 frames
      for (var i = 0; i < 15; i++) {
        tracker.update([_det(0.5, 0.5)]);
      }
      expect(tracker.tracks.first.isStatic, isTrue);
      // Now move significantly — simulate ball being kicked
      for (var i = 0; i < 12; i++) {
        tracker.update([_det(0.5 + i * 0.03, 0.5)]);
      }
      final track = tracker.tracks.first;
      expect(track.isStatic, isFalse);
    });

    test('dynamic flag resets to static when object stops (dynamic → static)', () {
      final tracker = ByteTrackTracker(staticMinFrames: 10, staticMaxDisplacement: 0.01);
      // Move for 10 frames
      for (var i = 0; i < 10; i++) {
        tracker.update([_det(0.2 + i * 0.02, 0.5)]);
      }
      expect(tracker.tracks.first.isStatic, isFalse);
      // Now stay still long enough to flush the entire sliding window (default 30)
      final stopX = 0.2 + 9 * 0.02;
      for (var i = 0; i < 35; i++) {
        tracker.update([_det(stopX, 0.5)]);
      }
      expect(tracker.tracks.first.isStatic, isTrue);
    });

    test('full cycle: static → kicked → lands → static again', () {
      final tracker = ByteTrackTracker(staticMinFrames: 10, staticMaxDisplacement: 0.01);
      // Phase 1: ball on ground, stationary
      for (var i = 0; i < 12; i++) {
        tracker.update([_det(0.3, 0.5)]);
      }
      expect(tracker.tracks.first.isStatic, isTrue);

      // Phase 2: ball kicked — fast movement
      for (var i = 0; i < 12; i++) {
        tracker.update([_det(0.3 + i * 0.03, 0.5 - i * 0.02)]);
      }
      expect(tracker.tracks.first.isStatic, isFalse);

      // Phase 3: ball lands and sits still at new position
      final landX = 0.3 + 11 * 0.03;
      final landY = 0.5 - 11 * 0.02;
      for (var i = 0; i < 12; i++) {
        tracker.update([_det(landX, landY)]);
      }
      expect(tracker.tracks.first.isStatic, isTrue);
    });
  });

  group('ByteTrackTracker - Kalman prediction', () {
    test('predict advances track position by velocity', () {
      final tracker = ByteTrackTracker();
      // Establish motion for 10 frames
      for (var i = 0; i < 10; i++) {
        tracker.update([_det(0.3 + i * 0.02, 0.5)]);
      }
      // Now send no detections — track should predict forward
      final lostTracks = tracker.update([]);
      expect(lostTracks.length, 1);
      // Predicted center should be ahead of last detection (0.3 + 9*0.02 = 0.48)
      expect(lostTracks.first.center.dx, greaterThan(0.48));
    });
  });

  group('ByteTrackTracker - reset', () {
    test('reset clears all tracks', () {
      final tracker = ByteTrackTracker();
      tracker.update([_det(0.5, 0.5)]);
      expect(tracker.tracks.length, 1);
      tracker.reset();
      expect(tracker.tracks.length, 0);
    });

    test('new tracks get fresh IDs after reset', () {
      final tracker = ByteTrackTracker();
      tracker.update([_det(0.5, 0.5)]);
      tracker.reset();
      final tracks = tracker.update([_det(0.5, 0.5)]);
      // ID should be 1 again after reset
      expect(tracks.first.trackId, 1);
    });
  });

  group('ByteTrackTracker - empty frames', () {
    test('update with empty detections on first call returns empty', () {
      final tracker = ByteTrackTracker();
      final tracks = tracker.update([]);
      expect(tracks.length, 0);
    });

    test('multiple empty frames in a row do not crash', () {
      final tracker = ByteTrackTracker();
      for (var i = 0; i < 50; i++) {
        final tracks = tracker.update([]);
        expect(tracks, isA<List<TrackedObject>>());
      }
    });
  });

  group('ByteTrackTracker - 9 static circles + 1 moving ball', () {
    test('ball maintains unique ID separate from 9 static circles', () {
      final tracker = ByteTrackTracker(staticMinFrames: 15, staticMaxDisplacement: 0.02);

      // 9 static "circle" detections at fixed positions + 1 moving ball
      final circlePositions = [
        const Offset(0.3, 0.35), const Offset(0.4, 0.35), const Offset(0.5, 0.35), // zones 7,8,9
        const Offset(0.3, 0.45), const Offset(0.4, 0.45), const Offset(0.5, 0.45), // zones 6,5,4
        const Offset(0.3, 0.55), const Offset(0.4, 0.55), const Offset(0.5, 0.55), // zones 1,2,3
      ];

      int? ballId;
      for (var frame = 0; frame < 20; frame++) {
        final dets = <Detection>[
          // 9 static circles
          for (final pos in circlePositions)
            _det(pos.dx, pos.dy, w: 0.028, h: 0.028, conf: 0.6, cls: 'ball'),
          // 1 moving ball
          _det(0.15 + frame * 0.015, 0.6, w: 0.05, h: 0.05, conf: 0.85),
        ];
        final tracks = tracker.update(dets);

        // Find the ball (moving, not static)
        if (frame >= 15) {
          final movingTracks = tracks.where((t) => !t.isStatic && t.state == TrackState.tracked);
          expect(movingTracks.length, greaterThanOrEqualTo(1),
              reason: 'Frame $frame: should have at least 1 moving track');

          ballId ??= movingTracks.first.trackId;
          // Ball should maintain its ID
          expect(movingTracks.any((t) => t.trackId == ballId), isTrue,
              reason: 'Frame $frame: ball should maintain ID $ballId');
        }
      }

      // After 20 frames, verify static classification
      final finalTracks = tracker.tracks;
      final staticTracks = finalTracks.where((t) => t.isStatic).length;
      expect(staticTracks, greaterThanOrEqualTo(7),
          reason: 'Most of the 9 circles should be flagged static');
    });
  });
}
