# False Positive Filtering Implementation Plan

## Overview

Add two layers of false positive filtering to the soccer ball detection pipeline:
- **Layer 1 (Pre-ByteTrack Gate):** Reject obviously wrong detections before they enter the tracker
- **Layer 2 (Track Quality System):** Post-ByteTrack quality scoring to suppress unstable tracks

---

## Answers to Design Questions

### Q1: Frame Differencing Feasibility

The `ultralytics_yolo` plugin (v0.2.0) does NOT expose raw camera frames — it only delivers `List<YOLOResult>` via the `onResult` callback. Implementing actual frame differencing would require:
- A second camera stream (complex, battery-heavy, not worth it)
- Forking the plugin (maintenance burden)

**Decision: Use ByteTrack's velocity data as a proxy for motion validation.** After ByteTrack's `update()`, every `TrackedObject` already has `velocity` and `velocityMagnitude` from the Kalman filter. For Layer 1 (pre-ByteTrack), we cannot validate motion since we have no track history yet. Instead, Layer 1 focuses on geometric rejection (AR and size), while Layer 2 handles motion-based validation using track velocity history.

### Q2: Layer 1 Location

**Decision: Separate filter function between `_toDetections()` and `_byteTracker.update()`.** Reasons:
- `_toDetections()` should remain a pure YOLO-to-Detection converter (single responsibility)
- A separate `DetectionFilter` class is testable in isolation
- The filter needs access to `_referenceBboxArea` which `_toDetections()` does not have

### Q3: Track Quality System Location

**Decision: New standalone `TrackQualityGate` class in `lib/services/track_quality_gate.dart`.** Reasons:
- BallIdentifier handles *identity* (which track is the ball), not *quality*
- ByteTrack handles *association* (matching detections to tracks), not *quality scoring*
- A separate class maintains single responsibility and is independently testable
- It sits between ByteTrack output and BallIdentifier input

### Q4: Initialization Delay Implementation

**Decision: Inside `TrackQualityGate`.** The gate filters the `List<TrackedObject>` before it reaches `BallIdentifier.updateFromTracks()`. Tracks with `totalFramesSeen < initDelay` are excluded from the list passed to BallIdentifier. They still exist in ByteTrack (so they continue building history), but are invisible to the rest of the pipeline.

The debug overlay should show these immature tracks in a distinct color (e.g., gray/dim) with a label like "INIT 2/5" so the developer can see them forming.

### Q5: Rolling Median Implementation

**Decision: New `TrackQualityHistory` class inside `track_quality_gate.dart` using a sorted insertion list.** Each tracked ID gets a `TrackQualityHistory` that stores the last N frames of AR, size, and confidence. The median is computed via a sorted list (O(N log N) insert, O(1) median read). N=15 frames is sufficient (~0.5s at 30fps). The gate checks if current-frame values drift beyond configurable sigma of the rolling median.

### Q6: Mahalanobis Rescue Validation

**Decision: Add size ratio and velocity direction checks as additional gates within the existing `_greedyMatch()` Stage 2 block.** After line 830 (where `mahalSq` passes the chi2 threshold), add:
1. Size ratio check: detection area / track's last known area must be within [0.33, 3.0]
2. Velocity direction consistency: dot product of track velocity and displacement vector must be > 0 (ball moving roughly toward the detection, not away from it)

These checks are cheap and only apply to the locked ball track (same scope as existing Mahalanobis rescue).

### Q7: Passing Reference Ball Area to Layer 1

**Decision: `DetectionFilter` is constructed with a mutable reference area setter, similar to how `ImpactDetector.setReferenceBboxArea()` works.** The screen calls `_detectionFilter.setReferenceBboxArea(area)` in `_confirmReferenceCapture()`, same place it already calls `_impactDetector.setReferenceBboxArea()`.

Before calibration, the filter uses a fallback: reject detections with area > 2% of frame area (1.0 * 1.0 = 1.0 in normalized coords, so fallback max area = 0.02).

---

## File Changes

### New File 1: `lib/services/detection_filter.dart`

**Purpose:** Layer 1 pre-ByteTrack geometric rejection.

```dart
/// Pre-ByteTrack detection filter that rejects geometrically impossible
/// ball detections before they can create spurious tracks.
///
/// Filters applied:
/// - Aspect ratio (AR) rejection: AR > maxAspectRatio → reject
/// - Size rejection: area > sizeMultiplier * referenceArea → reject
/// - Before calibration, uses fallbackMaxArea as absolute ceiling
class DetectionFilter {
  /// Maximum width/height aspect ratio for a valid ball detection.
  final double maxAspectRatio;

  /// Maximum detection area as a multiple of reference ball area.
  final double maxSizeMultiplier;

  /// Absolute maximum area (normalized) before calibration provides reference.
  final double fallbackMaxArea;

  double? _referenceBboxArea;

  DetectionFilter({
    this.maxAspectRatio = 2.5,
    this.maxSizeMultiplier = 5.0,
    this.fallbackMaxArea = 0.02,
  });

  void setReferenceBboxArea(double area) { _referenceBboxArea = area; }
  void clearReferenceBboxArea() { _referenceBboxArea = null; }

  /// Filter a list of detections, returning only those that pass geometric checks.
  List<Detection> apply(List<Detection> detections) {
    return detections.where(_passes).toList();
  }

  bool _passes(Detection det) {
    final w = det.bbox.width;
    final h = det.bbox.height;
    if (w <= 0 || h <= 0) return false;

    // AR check (use max of w/h, h/w to handle both orientations)
    final ar = w > h ? w / h : h / w;
    if (ar > maxAspectRatio) return false;

    // Size check
    final area = w * h;
    final maxArea = _referenceBboxArea != null
        ? _referenceBboxArea! * maxSizeMultiplier
        : fallbackMaxArea;
    if (area > maxArea) return false;

    return true;
  }
}
```

**Constructor parameters** (not hardcoded): `maxAspectRatio`, `maxSizeMultiplier`, `fallbackMaxArea`.

### New File 2: `lib/services/track_quality_gate.dart`

**Purpose:** Layer 2 post-ByteTrack track quality scoring.

```dart
/// Post-ByteTrack track quality gate that filters TrackedObject lists
/// before they reach BallIdentifier.
///
/// Features:
/// - Initialization delay: tracks invisible until N consecutive detections
/// - Rolling median monitoring: AR, size, confidence over last N frames
/// - Drift rejection: drop visibility if median drifts outside configurable range
class TrackQualityGate {
  /// Minimum consecutive detections before a track becomes visible.
  final int initDelayFrames;

  /// Rolling window size for median computation.
  final int medianWindowSize;

  /// Maximum AR median before a track is suppressed.
  final double maxMedianAR;

  /// Maximum size ratio (current / median) before suppression.
  final double maxSizeDriftRatio;

  /// Minimum confidence median before suppression.
  final double minMedianConfidence;

  // Per-track history: trackId -> TrackQualityHistory
  final Map<int, _TrackQualityHistory> _histories = {};

  TrackQualityGate({
    this.initDelayFrames = 4,
    this.medianWindowSize = 15,
    this.maxMedianAR = 2.0,
    this.maxSizeDriftRatio = 2.5,
    this.minMedianConfidence = 0.3,
  });

  /// Filter tracks, returning only those that pass quality checks.
  /// Also returns the full list with quality metadata for debug overlay.
  List<TrackedObject> apply(List<TrackedObject> tracks) {
    _pruneStaleHistories(tracks);

    final result = <TrackedObject>[];
    for (final track in tracks) {
      final history = _histories.putIfAbsent(
        track.trackId, () => _TrackQualityHistory(medianWindowSize));
      history.record(track);

      // Initialization delay: skip tracks that haven't been seen enough
      if (track.totalFramesSeen < initDelayFrames) continue;

      // Rolling median checks (only if we have enough history)
      if (history.sampleCount >= 3) {
        if (history.medianAR > maxMedianAR) continue;
        if (history.medianConfidence < minMedianConfidence) continue;
        // Size drift: current frame size vs median
        final sizeRatio = track.bboxArea / history.medianArea;
        if (sizeRatio > maxSizeDriftRatio || sizeRatio < 1.0 / maxSizeDriftRatio) continue;
      }

      result.add(track);
    }
    return result;
  }

  /// Check if a track is still in initialization phase (for debug overlay).
  bool isInitializing(int trackId) {
    final h = _histories[trackId];
    return h == null || h.sampleCount < initDelayFrames;
  }

  /// Get init progress for debug overlay: "3/5" style string.
  String initProgress(int trackId, int totalFramesSeen) {
    return '$totalFramesSeen/$initDelayFrames';
  }

  void reset() { _histories.clear(); }

  void _pruneStaleHistories(List<TrackedObject> currentTracks) {
    final activeIds = currentTracks.map((t) => t.trackId).toSet();
    _histories.removeWhere((id, _) => !activeIds.contains(id));
  }
}

class _TrackQualityHistory {
  final int maxSize;
  final List<double> _ars = [];
  final List<double> _areas = [];
  final List<double> _confidences = [];

  _TrackQualityHistory(this.maxSize);

  int get sampleCount => _ars.length;

  void record(TrackedObject track) {
    final w = track.bbox.width;
    final h = track.bbox.height;
    final ar = (h > 0) ? (w > h ? w / h : h / w) : 1.0;

    _addCapped(_ars, ar);
    _addCapped(_areas, track.bboxArea);
    _addCapped(_confidences, track.confidence);
  }

  double get medianAR => _median(_ars);
  double get medianArea => _median(_areas);
  double get medianConfidence => _median(_confidences);

  void _addCapped(List<double> list, double value) {
    list.add(value);
    if (list.length > maxSize) list.removeAt(0);
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }
}
```

### Modified File 1: `lib/services/bytetrack_tracker.dart`

**Changes to `_greedyMatch()` Stage 2 (lines 812-848):**

Add two validation checks after the Mahalanobis distance passes (line 830):

```dart
// After: if (mahalSq != null && mahalSq <= _chi2Threshold95) {
// Add BEFORE adding to mahalCandidates:

// Size consistency: detection area vs track's last known area
final detArea = dets[di].bbox.width * dets[di].bbox.height;
final trackArea = tracks[ti].kalman.width.abs() * tracks[ti].kalman.height.abs();
if (trackArea > 0) {
  final sizeRatio = detArea / trackArea;
  if (sizeRatio > 3.0 || sizeRatio < 1.0 / 3.0) continue; // size too different
}

// Velocity direction consistency: displacement should roughly align with velocity
final trackVel = tracks[ti].kalman.velocity;
final velMag = sqrt(trackVel.dx * trackVel.dx + trackVel.dy * trackVel.dy);
if (velMag > 0.005) { // only check if track is actually moving
  final disp = Offset(
    dets[di].bbox.center.dx - tracks[ti].kalman.center.dx,
    dets[di].bbox.center.dy - tracks[ti].kalman.center.dy,
  );
  final dot = trackVel.dx * disp.dx + trackVel.dy * disp.dy;
  if (dot < 0) continue; // detection is behind the track's direction of travel
}
```

This adds ~10 lines inside the existing for-loop at lines 826-833. No new methods needed.

### Modified File 2: `lib/screens/live_object_detection/live_object_detection_screen.dart`

**Change 1: Add imports and instantiate new services (near line 1-26)**
```dart
import 'package:tensorflow_demo/services/detection_filter.dart';
import 'package:tensorflow_demo/services/track_quality_gate.dart';
```

**Change 2: Add fields (near lines 38-48)**
```dart
final _detectionFilter = DetectionFilter();
final _trackQualityGate = TrackQualityGate();
```

**Change 3: Insert filter between _toDetections and _byteTracker.update (line 556-560)**

Current:
```dart
final detections = _toDetections(results);
final tracks = _byteTracker.update(detections, ...);
```

New:
```dart
final rawDetections = _toDetections(results);
final detections = _detectionFilter.apply(rawDetections);
final tracks = _byteTracker.update(detections, ...);
```

**Change 4: Insert quality gate before BallIdentifier (line 585)**

Current:
```dart
_ballId.updateFromTracks(tracks);
```

New:
```dart
final qualityTracks = _trackQualityGate.apply(tracks);
_ballId.updateFromTracks(qualityTracks);
```

**Important:** The debug overlay (line 588-592) should still receive ALL ball-class tracks (including filtered ones) so the developer can see what was rejected. Add a field to distinguish:
```dart
if (_debugBboxOverlay) {
  _debugBallClassTracks = tracks  // ALL tracks, not qualityTracks
      .where((t) => _ballClassNames.contains(t.className))
      .toList();
}
```

**Change 5: Wire reference area in `_confirmReferenceCapture()` (after line 499)**
```dart
_detectionFilter.setReferenceBboxArea(_referenceBboxArea!);
```

**Change 6: Reset in calibration reset flow (near line 281-294)**
```dart
_detectionFilter.clearReferenceBboxArea();
_trackQualityGate.reset();
```

### Modified File 3: `lib/screens/live_object_detection/widgets/debug_bbox_overlay.dart`

**Add visual indicators for filtered/initializing tracks:**

- Accept `TrackQualityGate` reference (or a `Set<int> suppressedTrackIds` and `Map<int, String> initProgressLabels`) as constructor parameters
- Tracks suppressed by quality gate: render in **gray** with dashed stroke
- Tracks in initialization: render in **dim cyan** with label "INIT 3/4"
- This requires the screen to pass the quality gate's metadata alongside the track list

**Simpler alternative (preferred):** Pass two sets to the overlay:
```dart
DebugBboxOverlay({
  required this.ballClassTracks,
  required this.lockedTrackId,
  this.suppressedTrackIds = const {},     // NEW
  this.initializingTrackIds = const {},   // NEW
  this.cameraAspectRatio = 4.0 / 3.0,
});
```

The screen computes these sets by comparing `tracks` vs `qualityTracks`:
```dart
final suppressedIds = tracks.map((t) => t.trackId).toSet()
    .difference(qualityTracks.map((t) => t.trackId).toSet());
```

### New File 3: `test/detection_filter_test.dart`

Test cases:
1. Passes a normal ball detection (AR ~1.0, small area)
2. Rejects AR > 2.5 (wide rectangle)
3. Rejects AR > 2.5 (tall rectangle — h/w check)
4. Rejects area > 5x reference area
5. Rejects area > fallback max when no reference set
6. Passes area just under 5x reference
7. Passes AR = 2.49 (edge case)
8. Zero-size bbox rejected
9. Empty list in → empty list out
10. Mixed valid/invalid detections — only valid survive

### New File 4: `test/track_quality_gate_test.dart`

Test cases:
1. Track with totalFramesSeen < initDelayFrames is filtered out
2. Track with totalFramesSeen >= initDelayFrames passes
3. Track with high median AR is filtered after enough history
4. Track with low median confidence is filtered
5. Track with size drift (sudden 3x jump) is filtered
6. Stable track passes all checks
7. reset() clears all histories
8. Stale track histories are pruned when track disappears
9. isInitializing() returns correct state
10. Edge case: exactly at threshold values

### Modified Test File: `test/bytetrack_tracker_test.dart`

Add tests for enhanced Mahalanobis rescue:
1. Mahalanobis rescue rejects detection with 4x size ratio
2. Mahalanobis rescue rejects detection behind velocity direction
3. Mahalanobis rescue still works for reasonable size/direction match

---

## Data Flow (Complete Pipeline After Changes)

```
YOLOView.onResult(List<YOLOResult>)
    │
    ▼
_toDetections(results)  →  List<Detection>     [class filter + coord correction]
    │
    ▼
_detectionFilter.apply(detections)              [NEW: AR reject, size reject]
    │
    ▼
_byteTracker.update(filteredDetections)         [ByteTrack with enhanced Mahalanobis]
    │                                            [NEW: size ratio + velocity direction checks]
    ▼
List<TrackedObject> tracks
    │
    ├──► Debug overlay (ALL tracks, with suppressed/init indicators)
    │
    ▼
_trackQualityGate.apply(tracks)                 [NEW: init delay, rolling median]
    │
    ▼
List<TrackedObject> qualityTracks
    │
    ▼
_ballId.updateFromTracks(qualityTracks)         [Ball identity selection]
    │
    ▼
Downstream pipeline (kick detector, trajectory, impact, etc.)
```

---

## Implementation Sequence

### Step 1: DetectionFilter (Layer 1)
1. Create `lib/services/detection_filter.dart`
2. Create `test/detection_filter_test.dart` — write and run tests
3. Wire into `live_object_detection_screen.dart` (3 insertion points)
4. Run `flutter analyze` and full test suite

### Step 2: TrackQualityGate (Layer 2 — init delay + rolling median)
1. Create `lib/services/track_quality_gate.dart`
2. Create `test/track_quality_gate_test.dart` — write and run tests
3. Wire into `live_object_detection_screen.dart` (2 insertion points)
4. Run `flutter analyze` and full test suite

### Step 3: Enhanced Mahalanobis Rescue (Layer 2 — rescue validation)
1. Modify `_greedyMatch()` in `bytetrack_tracker.dart` (lines 826-833)
2. Add tests to `test/bytetrack_tracker_test.dart`
3. Run `flutter analyze` and full test suite

### Step 4: Debug Overlay Enhancement
1. Add `suppressedTrackIds` and `initializingTrackIds` to `DebugBboxOverlay`
2. Add gray/cyan color coding and INIT labels
3. Wire the metadata from screen to overlay
4. Visual verification on device

### Step 5: Integration Verification
1. Run full test suite (should be 176 + ~23 new = ~199 tests, 0 failures)
2. `flutter analyze` — 0 errors, 0 warnings
3. On-device testing: verify false positives are suppressed
4. Verify real ball detection is not degraded

---

## Risk Mitigation

**Risk: Over-filtering real ball detections**
- Mitigation: All thresholds are constructor parameters, easily tunable
- The init delay of 4 frames adds only ~130ms latency at 30fps
- AR threshold of 2.5 is very permissive (real ball AR is 0.8-1.2)

**Risk: Quality gate fighting BallIdentifier**
- Mitigation: Quality gate filters the track LIST before BallIdentifier sees it. BallIdentifier's logic is unchanged — it just receives fewer candidates.

**Risk: Rolling median computation cost**
- Mitigation: Window of 15 entries, sorted on each median query. With typically 1-5 ball-class tracks, this is negligible (~75 sort operations per frame worst case).

**Risk: Debug overlay becoming too complex**
- Mitigation: New visual indicators (gray/cyan) are additive — existing green/yellow/red behavior is unchanged.
