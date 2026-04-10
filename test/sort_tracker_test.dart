import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/services/sort_tracker.dart';

void main() {
  group('Detection', () {
    test('computes center, width, height, area from bbox', () {
      const d = Detection(
        left: 0.1,
        top: 0.2,
        right: 0.3,
        bottom: 0.5,
        confidence: 0.9,
        className: 'Soccer ball',
      );
      expect(d.cx, closeTo(0.2, 1e-9));
      expect(d.cy, closeTo(0.35, 1e-9));
      expect(d.w, closeTo(0.2, 1e-9));
      expect(d.h, closeTo(0.3, 1e-9));
      expect(d.area, closeTo(0.06, 1e-9));
    });
  });

  group('STrack', () {
    test('predict advances position by velocity', () {
      final tracker = SortTracker();
      // Create a track by updating with a detection
      tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Give it velocity by updating with a shifted detection
      tracker.update([
        const Detection(
          left: 0.42, top: 0.4, right: 0.62, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      final track = tracker.confirmedTracks.first;
      // Center should be near 0.52 (moved right by ~0.02)
      expect(track.cx, closeTo(0.52, 0.02));
      expect(track.cy, closeTo(0.5, 0.02));
    });
  });

  group('SortTracker', () {
    late SortTracker tracker;

    setUp(() {
      tracker = SortTracker();
    });

    test('creates a new track from a single detection', () {
      final result = tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      expect(result, hasLength(1));
      expect(result.first.trackId, 1);
      expect(result.first.className, 'Soccer ball');
      expect(result.first.cx, closeTo(0.5, 0.01));
      expect(result.first.cy, closeTo(0.5, 0.01));
    });

    test('tracks a single object across frames', () {
      // Frame 1: ball at center
      tracker.update([
        const Detection(
          left: 0.45, top: 0.45, right: 0.55, bottom: 0.55,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Frame 2: ball moved slightly right
      tracker.update([
        const Detection(
          left: 0.47, top: 0.45, right: 0.57, bottom: 0.55,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Frame 3: ball moved more right
      final result = tracker.update([
        const Detection(
          left: 0.49, top: 0.45, right: 0.59, bottom: 0.55,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Should still be ONE track with ID 1
      expect(result, hasLength(1));
      expect(result.first.trackId, 1);
      // Should have positive vx (moving right)
      expect(result.first.vx, greaterThan(0));
    });

    test('creates separate tracks for non-overlapping detections', () {
      final result = tracker.update([
        const Detection(
          left: 0.1, top: 0.1, right: 0.2, bottom: 0.2,
          confidence: 0.9, className: 'Soccer ball',
        ),
        const Detection(
          left: 0.7, top: 0.7, right: 0.8, bottom: 0.8,
          confidence: 0.8, className: 'ball',
        ),
      ]);

      expect(result, hasLength(2));
      expect(result[0].trackId, isNot(result[1].trackId));
    });

    test('marks track as lost after detection disappears', () {
      // Frame 1: detection present
      tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Frame 2: no detections
      tracker.update([]);

      // Track should still exist but be lost
      expect(tracker.tracks, hasLength(1));
      expect(tracker.tracks.first.state, TrackState.lost);
      expect(tracker.confirmedTracks, isEmpty);
    });

    test('recovers lost track when detection reappears', () {
      // Frame 1
      tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);
      final id = tracker.confirmedTracks.first.trackId;

      // Frame 2: lost
      tracker.update([]);
      expect(tracker.confirmedTracks, isEmpty);

      // Frame 3: reappears at nearby position
      final result = tracker.update([
        const Detection(
          left: 0.42, top: 0.4, right: 0.62, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Should recover same track ID
      expect(result, hasLength(1));
      expect(result.first.trackId, id);
    });

    test('removes track after maxTimeLost frames', () {
      tracker = SortTracker(maxTimeLost: 5);

      tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // 6 empty frames (> maxTimeLost)
      for (int i = 0; i < 6; i++) {
        tracker.update([]);
      }

      expect(tracker.tracks, isEmpty);
    });

    test('two-pass matching: low-confidence detection matches existing track', () {
      tracker = SortTracker(highConfThreshold: 0.5);

      // Frame 1: high-confidence creates track
      tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);
      final id = tracker.confirmedTracks.first.trackId;

      // Frame 2: only low-confidence detection at same position
      final result = tracker.update([
        const Detection(
          left: 0.41, top: 0.41, right: 0.61, bottom: 0.61,
          confidence: 0.35, className: 'Soccer ball',
        ),
      ]);

      // Should match via second-pass
      expect(result, hasLength(1));
      expect(result.first.trackId, id);
    });

    test('low-confidence detection alone does NOT create new track', () {
      tracker = SortTracker(highConfThreshold: 0.5);

      final result = tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.35, className: 'Soccer ball',
        ),
      ]);

      // Low-confidence should not create new tracks
      expect(result, isEmpty);
      expect(tracker.tracks, isEmpty);
    });

    test('distinguishes ball from stationary circle by motion divergence', () {
      // ISSUE-022 scenario: moving ball + stationary target circle.
      // Bboxes are 0.1 wide; ball moves 0.03/frame so IoU overlap is
      // sufficient for the tracker to match across frames.

      // Frame 1: ball near kicker, circle at target
      tracker.update([
        const Detection(
          left: 0.10, top: 0.40, right: 0.20, bottom: 0.50,
          confidence: 0.8, className: 'Soccer ball',
        ),
        const Detection(
          left: 0.70, top: 0.40, right: 0.80, bottom: 0.50,
          confidence: 0.6, className: 'Soccer ball',
        ),
      ]);

      // Frame 2: ball moved 0.03 rightward, circle stays
      tracker.update([
        const Detection(
          left: 0.13, top: 0.40, right: 0.23, bottom: 0.50,
          confidence: 0.8, className: 'Soccer ball',
        ),
        const Detection(
          left: 0.70, top: 0.40, right: 0.80, bottom: 0.50,
          confidence: 0.6, className: 'Soccer ball',
        ),
      ]);

      // Frame 3: ball moved another 0.03
      tracker.update([
        const Detection(
          left: 0.16, top: 0.40, right: 0.26, bottom: 0.50,
          confidence: 0.8, className: 'Soccer ball',
        ),
        const Detection(
          left: 0.70, top: 0.40, right: 0.80, bottom: 0.50,
          confidence: 0.6, className: 'Soccer ball',
        ),
      ]);

      // Frame 4: continued motion
      final result = tracker.update([
        const Detection(
          left: 0.19, top: 0.40, right: 0.29, bottom: 0.50,
          confidence: 0.8, className: 'Soccer ball',
        ),
        const Detection(
          left: 0.70, top: 0.40, right: 0.80, bottom: 0.50,
          confidence: 0.6, className: 'Soccer ball',
        ),
      ]);

      // Should have TWO separate tracks
      expect(result, hasLength(2));
      final ids = result.map((t) => t.trackId).toSet();
      expect(ids, hasLength(2)); // Different IDs

      // The moving track should have positive vx
      final movingTrack = result.firstWhere(
        (t) => t.vx > 0.005,
        orElse: () => throw StateError('No moving track found'),
      );
      expect(movingTrack.vx, greaterThan(0)); // moving right

      // The stationary track should have near-zero velocity
      final stationaryTrack = result.firstWhere(
        (t) => t.vx.abs() < 0.005,
        orElse: () => throw StateError('No stationary track found'),
      );
      expect(stationaryTrack.speed, lessThan(0.01));
    });

    test('IoU matching prefers overlapping bbox over distant one', () {
      // Frame 1: single detection
      tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.5, bottom: 0.5,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Frame 2: two detections — one overlapping, one far away
      tracker.update([
        const Detection(
          left: 0.41, top: 0.41, right: 0.51, bottom: 0.51,
          confidence: 0.9, className: 'Soccer ball',
        ),
        const Detection(
          left: 0.8, top: 0.8, right: 0.9, bottom: 0.9,
          confidence: 0.9, className: 'ball',
        ),
      ]);

      final confirmed = tracker.confirmedTracks;
      // Original track should match the nearby detection
      final originalTrack = confirmed.firstWhere((t) => t.trackId == 1);
      expect(originalTrack.cx, closeTo(0.46, 0.03));
    });

    test('reset clears all tracks', () {
      tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);
      expect(tracker.tracks, isNotEmpty);

      tracker.reset();
      expect(tracker.tracks, isEmpty);
    });

    test('track age increments each frame', () {
      tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      for (int i = 0; i < 5; i++) {
        tracker.update([
          Detection(
            left: 0.4 + i * 0.01, top: 0.4, right: 0.6 + i * 0.01, bottom: 0.6,
            confidence: 0.9, className: 'Soccer ball',
          ),
        ]);
      }

      // Track has existed for 6 frames (1 creation + 5 updates with predict)
      expect(tracker.confirmedTracks.first.age, 5);
    });

    test('Kalman filter provides velocity estimate', () {
      // Frame 1: start
      tracker.update([
        const Detection(
          left: 0.3, top: 0.4, right: 0.4, bottom: 0.5,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Frames 2-5: consistent rightward motion
      for (int i = 1; i <= 4; i++) {
        tracker.update([
          Detection(
            left: 0.3 + i * 0.03, top: 0.4,
            right: 0.4 + i * 0.03, bottom: 0.5,
            confidence: 0.9, className: 'Soccer ball',
          ),
        ]);
      }

      final track = tracker.confirmedTracks.first;
      // Should have converged to ~0.03 rightward velocity
      expect(track.vx, closeTo(0.03, 0.015));
      expect(track.vy, closeTo(0.0, 0.01));
    });

    test('handles empty detection list gracefully', () {
      final result = tracker.update([]);
      expect(result, isEmpty);
    });

    test('Kalman extrapolation through brief occlusion', () {
      // Build up a moving track
      for (int i = 0; i < 5; i++) {
        tracker.update([
          Detection(
            left: 0.2 + i * 0.04, top: 0.4,
            right: 0.3 + i * 0.04, bottom: 0.5,
            confidence: 0.9, className: 'Soccer ball',
          ),
        ]);
      }

      final beforeOcclusion = tracker.confirmedTracks.first;
      final cxBefore = beforeOcclusion.cx;

      // Occlusion: 2 empty frames
      tracker.update([]);
      tracker.update([]);

      // The track should still be in the list (lost but not removed)
      final lostTrack = tracker.tracks.firstWhere((t) => t.trackId == 1);
      // Predicted position should have advanced beyond pre-occlusion position
      expect(lostTrack.cx, greaterThan(cxBefore));
    });

    test('track width/height are tracked by Kalman', () {
      // Frame 1: large bbox
      tracker.update([
        const Detection(
          left: 0.3, top: 0.3, right: 0.5, bottom: 0.5,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Frame 2: bbox getting smaller (ball moving away)
      tracker.update([
        const Detection(
          left: 0.32, top: 0.32, right: 0.48, bottom: 0.48,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      // Frame 3: even smaller
      tracker.update([
        const Detection(
          left: 0.34, top: 0.34, right: 0.46, bottom: 0.46,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);

      final track = tracker.confirmedTracks.first;
      // vw and vh should be negative (shrinking)
      expect(track.vw, lessThan(0));
      expect(track.vh, lessThan(0));
    });

    test('minHitStreak filters newly created tracks', () {
      tracker = SortTracker(minHitStreak: 3);

      // Frame 1: new track created, hit streak = 1 (creation counts as first hit)
      var result = tracker.update([
        const Detection(
          left: 0.4, top: 0.4, right: 0.6, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);
      expect(result, isEmpty); // hit streak 1 < 3

      // Frame 2: hit streak = 2
      result = tracker.update([
        const Detection(
          left: 0.41, top: 0.4, right: 0.61, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);
      expect(result, isEmpty); // hit streak 2 < 3

      // Frame 3: hit streak = 3
      result = tracker.update([
        const Detection(
          left: 0.42, top: 0.4, right: 0.62, bottom: 0.6,
          confidence: 0.9, className: 'Soccer ball',
        ),
      ]);
      expect(result, hasLength(1)); // now confirmed
    });
  });
}
