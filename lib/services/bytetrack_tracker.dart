import 'dart:collection';
import 'dart:math';
import 'dart:ui' show Offset, Rect;

import 'package:tensorflow_demo/utils/diag_log.dart';

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// A single YOLO detection fed into the tracker each frame.
class Detection {
  final Rect bbox;
  final double confidence;
  final String className;

  const Detection({
    required this.bbox,
    required this.confidence,
    required this.className,
  });
}

/// Lifecycle state of a tracked object.
enum TrackState { tracked, lost, removed }

/// Public snapshot of a tracked object exposed by [ByteTrackTracker].
class TrackedObject {
  final int trackId;
  final Rect bbox;
  final Offset center;
  final Offset velocity;
  /// Kalman-smoothed rate of change of bbox dimensions per frame:
  /// `dx` = width-velocity (vw), `dy` = height-velocity (vh).
  /// Positive components = bbox growing (object approaching the camera).
  /// Negative components = bbox shrinking (object receding).
  /// Phase 1 exposure (2026-05-01): not yet consumed by any pipeline stage —
  /// surfaced for diagnostic logging and future positive-impact-trigger work.
  final Offset sizeVelocity;
  final double bboxArea;
  final bool isStatic;
  final TrackState state;
  final int totalFramesSeen;
  final int consecutiveLostFrames;
  final String className;
  final double confidence;

  const TrackedObject({
    required this.trackId,
    required this.bbox,
    required this.center,
    required this.velocity,
    required this.sizeVelocity,
    required this.bboxArea,
    required this.isStatic,
    required this.state,
    required this.totalFramesSeen,
    required this.consecutiveLostFrames,
    required this.className,
    required this.confidence,
  });

  double get velocityMagnitude =>
      sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy);
}

// ---------------------------------------------------------------------------
// 8-state Kalman filter (per track, inline math)
// ---------------------------------------------------------------------------

/// 8‑state linear Kalman filter: [cx, cy, w, h, vx, vy, vw, vh].
///
/// Constant‑velocity model for all 8 states (dt = 1 frame).
/// Measurement is [cx, cy, w, h] from a YOLO bounding box.
///
/// All matrices are flat [List<double>] row‑major — no external packages.
class _Kalman8 {
  // Noise tunables
  static const double _posNoise = 0.0001;
  static const double _sizeNoise = 0.0001;
  static const double _velNoise = 0.01;
  static const double _measNoise = 0.005;

  // State (8x1)
  final List<double> _x = List.filled(8, 0.0);

  // Covariance (8x8 row-major = 64 entries)
  final List<double> _P = List.filled(64, 0.0);

  bool isInitialized = false;

  // -- Fixed matrices (computed lazily on first use) --

  // State transition F (8x8):
  // [ I4  I4 ]   cx' = cx + vx,  w' = w + vw, etc.
  // [ 0   I4 ]
  static final List<double> _F = _buildF();
  static final List<double> _Ft = _transpose8x8(_F);

  // Process noise Q (8x8 diagonal)
  static final List<double> _Q = _buildQ();

  // Measurement H (4x8): selects [cx, cy, w, h] from state.
  // Not stored explicitly — H is an identity selector (rows 0-3 of state),
  // so H*x, H*P, P*Ht, and K*H are computed via direct indexing.

  // Measurement noise R (4x4 diagonal)
  static final List<double> _R = [
    _measNoise, 0, 0, 0, //
    0, _measNoise, 0, 0, //
    0, 0, _measNoise, 0, //
    0, 0, 0, _measNoise,
  ];

  // ---- builders ----

  static List<double> _buildF() {
    final f = List.filled(64, 0.0);
    for (var i = 0; i < 8; i++) {
      f[i * 8 + i] = 1.0; // identity diagonal
      if (i < 4) f[i * 8 + (i + 4)] = 1.0; // dt block
    }
    return f;
  }

  static List<double> _buildQ() {
    final q = List.filled(64, 0.0);
    q[0 * 8 + 0] = _posNoise; // cx
    q[1 * 8 + 1] = _posNoise; // cy
    q[2 * 8 + 2] = _sizeNoise; // w
    q[3 * 8 + 3] = _sizeNoise; // h
    q[4 * 8 + 4] = _velNoise; // vx
    q[5 * 8 + 5] = _velNoise; // vy
    q[6 * 8 + 6] = _velNoise; // vw
    q[7 * 8 + 7] = _velNoise; // vh
    return q;
  }

  // ---- init ----

  void initFromDetection(Rect bbox) {
    final cx = bbox.center.dx;
    final cy = bbox.center.dy;
    final w = bbox.width;
    final h = bbox.height;

    _x[0] = cx;
    _x[1] = cy;
    _x[2] = w;
    _x[3] = h;
    for (var i = 4; i < 8; i++) _x[i] = 0.0; // zero velocity

    // Initial covariance: moderate uncertainty on position/size,
    // high uncertainty on velocity.
    for (var i = 0; i < 64; i++) _P[i] = 0.0;
    _P[0 * 8 + 0] = 0.01; // cx
    _P[1 * 8 + 1] = 0.01; // cy
    _P[2 * 8 + 2] = 0.01; // w
    _P[3 * 8 + 3] = 0.01; // h
    _P[4 * 8 + 4] = 1.0; // vx
    _P[5 * 8 + 5] = 1.0; // vy
    _P[6 * 8 + 6] = 1.0; // vw
    _P[7 * 8 + 7] = 1.0; // vh

    isInitialized = true;
  }

  // ---- predict ----

  void predict() {
    if (!isInitialized) return;
    // x = F * x
    final nx = _mulMV8(_F, _x);
    for (var i = 0; i < 8; i++) _x[i] = nx[i];

    // P = F * P * Ft + Q
    final fp = _mulMM8(_F, _P);
    final fpft = _mulMM8(fp, _Ft);
    for (var i = 0; i < 64; i++) _P[i] = fpft[i] + _Q[i];
  }

  // ---- update ----

  void update(Rect bbox) {
    if (!isInitialized) {
      initFromDetection(bbox);
      return;
    }
    final z = [bbox.center.dx, bbox.center.dy, bbox.width, bbox.height];

    // Innovation y = z - H*x  (4x1)
    final hx = _mulHx(_x);
    final y = [z[0] - hx[0], z[1] - hx[1], z[2] - hx[2], z[3] - hx[3]];

    // S = H * P * Ht + R  (4x4)
    final hp = _mulHP(_P); // 4x8 * 8x8 → keep only the 4x4 result via H structure
    final s = _mul4x4Add(hp, _R);

    // K = P * Ht * S^-1  (8x4)
    final sInv = _inv4x4(s);
    if (sInv == null) return; // singular — skip update
    final pht = _mulPHt(_P);
    final k = _mulM8x4_M4x4(pht, sInv); // 8x4

    // x = x + K * y
    for (var i = 0; i < 8; i++) {
      double sum = 0.0;
      for (var j = 0; j < 4; j++) sum += k[i * 4 + j] * y[j];
      _x[i] += sum;
    }

    // P = (I - K*H) * P
    final kh = _mulKH(k); // 8x8
    final iMinusKH = List.filled(64, 0.0);
    for (var i = 0; i < 8; i++) iMinusKH[i * 8 + i] = 1.0;
    for (var i = 0; i < 64; i++) iMinusKH[i] -= kh[i];
    final newP = _mulMM8(iMinusKH, _P);
    for (var i = 0; i < 64; i++) _P[i] = newP[i];
  }

  // ---- state access ----

  Rect get predictedBbox {
    final w = _x[2].abs().clamp(0.001, 1.0);
    final h = _x[3].abs().clamp(0.001, 1.0);
    return Rect.fromCenter(center: Offset(_x[0], _x[1]), width: w, height: h);
  }

  Offset get center => Offset(_x[0], _x[1]);
  Offset get velocity => Offset(_x[4], _x[5]);
  /// Rate of change of bbox dimensions: vw (state 6) and vh (state 7).
  /// Already computed by the constant-velocity model on every predict() —
  /// this getter just surfaces the values that were already in [_x].
  Offset get sizeVelocity => Offset(_x[6], _x[7]);
  double get width => _x[2];
  double get height => _x[3];

  /// Compute the squared Mahalanobis distance from a detection measurement
  /// to the current predicted state, using the innovation covariance
  /// S = H * P * Hᵀ + R.
  ///
  /// Returns the squared distance (compare against chi-squared threshold).
  /// Returns null if the covariance is singular.
  double? mahalanobisDistSq(Rect detBbox) {
    if (!isInitialized) return null;

    // Measurement vector
    final z = [detBbox.center.dx, detBbox.center.dy, detBbox.width, detBbox.height];

    // Innovation: y = z - H*x
    final y = [z[0] - _x[0], z[1] - _x[1], z[2] - _x[2], z[3] - _x[3]];

    // Innovation covariance: S = H*P*Hᵀ + R (4x4)
    // Since H selects first 4 rows, S = P[0:4, 0:4] + R
    final s = List.filled(16, 0.0);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        s[i * 4 + j] = _P[i * 8 + j] + _R[i * 4 + j];
      }
    }

    // S⁻¹
    final sInv = _inv4x4(s);
    if (sInv == null) return null;

    // d² = yᵀ * S⁻¹ * y
    // First: S⁻¹ * y (4x1)
    final sInvY = List.filled(4, 0.0);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        sInvY[i] += sInv[i * 4 + j] * y[j];
      }
    }

    // Then: yᵀ * (S⁻¹ * y) (scalar)
    double distSq = 0.0;
    for (var i = 0; i < 4; i++) {
      distSq += y[i] * sInvY[i];
    }

    return distSq;
  }

  // ---- matrix helpers (inline, no allocation beyond result) ----

  // 8x8 * 8x1 → 8x1
  static List<double> _mulMV8(List<double> m, List<double> v) {
    final r = List.filled(8, 0.0);
    for (var i = 0; i < 8; i++) {
      double s = 0.0;
      final base = i * 8;
      for (var j = 0; j < 8; j++) s += m[base + j] * v[j];
      r[i] = s;
    }
    return r;
  }

  // 8x8 * 8x8 → 8x8
  static List<double> _mulMM8(List<double> a, List<double> b) {
    final r = List.filled(64, 0.0);
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 8; j++) {
        double s = 0.0;
        for (var k = 0; k < 8; k++) s += a[i * 8 + k] * b[k * 8 + j];
        r[i * 8 + j] = s;
      }
    }
    return r;
  }

  // Transpose 8x8
  static List<double> _transpose8x8(List<double> m) {
    final r = List.filled(64, 0.0);
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 8; j++) r[j * 8 + i] = m[i * 8 + j];
    }
    return r;
  }

  // H*x (4x8 * 8x1 → 4x1) — H selects first 4 elements
  static List<double> _mulHx(List<double> x) => [x[0], x[1], x[2], x[3]];

  // H*P (4x8 * 8x8) → first 4 rows of P, then multiply by Ht and add R
  // Returns S = H*P*Ht + R as 4x4 (simplified because H is an identity selector)
  static List<double> _mul4x4Add(List<double> hp, List<double> r) {
    // hp here is actually the top-left 4x4 block of P (since H selects rows 0-3)
    // S[i][j] = P[i][j] + R[i][j]  for i,j in 0..3
    final s = List.filled(16, 0.0);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        s[i * 4 + j] = hp[i * 4 + j] + r[i * 4 + j];
      }
    }
    return s;
  }

  // H*P → extracts top-left 4x4 of the 8x8 covariance
  // Returns flat 4x4 (16 elements)
  static List<double> _mulHP(List<double> p) {
    final r = List.filled(16, 0.0);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        r[i * 4 + j] = p[i * 8 + j];
      }
    }
    return r;
  }

  // P * Ht → 8x8 * 8x4 → 8x4 (32 elements)
  // Since Ht = first 4 columns of identity, P*Ht = first 4 columns of P
  static List<double> _mulPHt(List<double> p) {
    final r = List.filled(32, 0.0);
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 4; j++) {
        r[i * 4 + j] = p[i * 8 + j];
      }
    }
    return r;
  }

  // 8x4 * 4x4 → 8x4
  static List<double> _mulM8x4_M4x4(List<double> a, List<double> b) {
    final r = List.filled(32, 0.0);
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 4; j++) {
        double s = 0.0;
        for (var k = 0; k < 4; k++) s += a[i * 4 + k] * b[k * 4 + j];
        r[i * 4 + j] = s;
      }
    }
    return r;
  }

  // K*H → 8x4 * 4x8 → 8x8
  // Since H selects first 4 columns, K*H just places K columns into first 4 cols
  static List<double> _mulKH(List<double> k) {
    final r = List.filled(64, 0.0);
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 4; j++) {
        r[i * 8 + j] = k[i * 4 + j];
      }
    }
    return r;
  }

  // Invert 4x4 matrix (Cramer's rule). Returns null if singular.
  static List<double>? _inv4x4(List<double> m) {
    final a = m[0], b = m[1], c = m[2], d = m[3];
    final e = m[4], f = m[5], g = m[6], h = m[7];
    final i = m[8], j = m[9], k = m[10], l = m[11];
    final mm = m[12], n = m[13], o = m[14], p = m[15];

    final kplo = k * p - l * o;
    final jpln = j * p - l * n;
    final jokn = j * o - k * n;
    final iplm = i * p - l * mm;
    final iomk = i * o - k * mm;
    final injm = i * n - j * mm;

    final det = a * (f * kplo - g * jpln + h * jokn) -
        b * (e * kplo - g * iplm + h * iomk) +
        c * (e * jpln - f * iplm + h * injm) -
        d * (e * jokn - f * iomk + g * injm);

    if (det.abs() < 1e-12) return null;
    final invDet = 1.0 / det;

    return [
      (f * kplo - g * jpln + h * jokn) * invDet,
      -(b * kplo - c * jpln + d * jokn) * invDet,
      (b * (g * p - h * o) - c * (f * p - h * n) + d * (f * o - g * n)) *
          invDet,
      -(b * (g * l - h * k) - c * (f * l - h * j) + d * (f * k - g * j)) *
          invDet,
      -(e * kplo - g * iplm + h * iomk) * invDet,
      (a * kplo - c * iplm + d * iomk) * invDet,
      -(a * (g * p - h * o) - c * (e * p - h * mm) + d * (e * o - g * mm)) *
          invDet,
      (a * (g * l - h * k) - c * (e * l - h * i) + d * (e * k - g * i)) *
          invDet,
      (e * jpln - f * iplm + h * injm) * invDet,
      -(a * jpln - b * iplm + d * injm) * invDet,
      (a * (f * p - h * n) - b * (e * p - h * mm) + d * (e * n - f * mm)) *
          invDet,
      -(a * (f * l - h * j) - b * (e * l - h * i) + d * (e * j - f * i)) *
          invDet,
      -(e * jokn - f * iomk + g * injm) * invDet,
      (a * jokn - b * iomk + c * injm) * invDet,
      -(a * (f * o - g * n) - b * (e * o - g * mm) + c * (e * n - f * mm)) *
          invDet,
      (a * (f * k - g * j) - b * (e * k - g * i) + c * (e * j - f * i)) *
          invDet,
    ];
  }
}

// ---------------------------------------------------------------------------
// Internal track representation
// ---------------------------------------------------------------------------

class _STrack {
  static int _nextId = 1;

  final int id;
  final _Kalman8 kalman = _Kalman8();
  TrackState state;
  String className;
  double confidence;
  int totalFramesSeen;
  int consecutiveLostFrames;
  final ListQueue<double> _recentDisplacements;
  Offset _prevCenter;
  bool isStatic;

  _STrack(Detection det, {int displacementWindow = 30})
      : id = _nextId++,
        state = TrackState.tracked,
        className = det.className,
        confidence = det.confidence,
        totalFramesSeen = 1,
        consecutiveLostFrames = 0,
        _recentDisplacements = ListQueue<double>(),
        _displacementWindowSize = displacementWindow,
        _prevCenter = det.bbox.center,
        isStatic = false {
    kalman.initFromDetection(det.bbox);
  }

  final int _displacementWindowSize;

  void predict() => kalman.predict();

  void update(Detection det) {
    kalman.update(det.bbox);
    confidence = det.confidence;
    className = det.className;
    state = TrackState.tracked;
    consecutiveLostFrames = 0;
    totalFramesSeen++;

    // Track recent displacement for static detection (sliding window)
    final c = kalman.center;
    final dx = c.dx - _prevCenter.dx;
    final dy = c.dy - _prevCenter.dy;
    _recentDisplacements.addLast(sqrt(dx * dx + dy * dy));
    if (_recentDisplacements.length > _displacementWindowSize) {
      _recentDisplacements.removeFirst();
    }
    _prevCenter = c;
  }

  void markLost() {
    state = TrackState.lost;
    consecutiveLostFrames++;
  }

  /// Two-way static classification based on sliding window displacement.
  /// Evaluates displacement over the most recent [minFrames] frames.
  /// Static when window is full and total recent displacement < [maxDisp].
  /// Clears automatically when displacement exceeds threshold.
  void evaluateStatic({int minFrames = 30, double maxDisp = 0.02}) {
    if (_recentDisplacements.length < minFrames) return;
    final recentTotal = _recentDisplacements.fold(0.0, (a, b) => a + b);
    isStatic = recentTotal < maxDisp;
  }

  Rect get predictedBbox => kalman.predictedBbox;

  TrackedObject toPublic() => TrackedObject(
        trackId: id,
        bbox: kalman.predictedBbox,
        center: kalman.center,
        velocity: kalman.velocity,
        sizeVelocity: kalman.sizeVelocity,
        bboxArea: kalman.width.abs() * kalman.height.abs(),
        isStatic: isStatic,
        state: state,
        totalFramesSeen: totalFramesSeen,
        consecutiveLostFrames: consecutiveLostFrames,
        className: className,
        confidence: confidence,
      );
}

// ---------------------------------------------------------------------------
// IoU computation
// ---------------------------------------------------------------------------

/// Standard intersection-over-union between two [Rect]s.
///
/// Returns 0.0 when there is no overlap or either rect has zero area.
double computeIoU(Rect a, Rect b) {
  final interLeft = max(a.left, b.left);
  final interTop = max(a.top, b.top);
  final interRight = min(a.right, b.right);
  final interBottom = min(a.bottom, b.bottom);

  final interW = max(0.0, interRight - interLeft);
  final interH = max(0.0, interBottom - interTop);
  final interArea = interW * interH;

  if (interArea <= 0.0) return 0.0;

  final areaA = a.width * a.height;
  final areaB = b.width * b.height;
  final unionArea = areaA + areaB - interArea;

  if (unionArea <= 0.0) return 0.0;
  return interArea / unionArea;
}

// ---------------------------------------------------------------------------
// ByteTrack Tracker
// ---------------------------------------------------------------------------

/// Complete ByteTrack multi-object tracker (Zhang et al., 2022).
///
/// Maintains persistent track IDs across frames using:
/// - 8-state Kalman filter per track (cx, cy, w, h, vx, vy, vw, vh)
/// - Two-pass IoU matching (high-confidence then low-confidence)
/// - Track lifecycle (tracked → lost → removed)
/// - Static track detection for background false positives
class ByteTrackTracker {
  /// Minimum IoU for pass-1 (high-confidence) matching.
  final double highIoUThreshold;

  /// Minimum IoU for pass-2 (low-confidence) matching.
  final double lowIoUThreshold;

  /// Confidence boundary between high and low detections.
  final double confidenceSplit;

  /// Frames a lost track survives before removal.
  final int maxLostFrames;

  /// Minimum frames before evaluating a track for static classification.
  final int staticMinFrames;

  /// Maximum cumulative displacement for a track to be classified as static.
  final double staticMaxDisplacement;

  ByteTrackTracker({
    this.highIoUThreshold = 0.3,
    this.lowIoUThreshold = 0.2,
    this.confidenceSplit = 0.5,
    this.maxLostFrames = 30,
    this.staticMinFrames = 30,
    this.staticMaxDisplacement = 0.02,
  });

  /// Frames a protected (locked ball) track survives before removal.
  /// Double the default [maxLostFrames] to cover typical ball flights.
  static const int protectedMaxLostFrames = 60;

  /// Track ID that gets extended survival time. Set via [setProtectedTrackId].
  int? _protectedTrackId;

  final List<_STrack> _trackedTracks = [];
  final List<_STrack> _lostTracks = [];
  List<TrackedObject> _lastPublicSnapshot = const [];

  /// All currently non-removed tracks as public snapshots.
  List<TrackedObject> get tracks => _lastPublicSnapshot;

  /// Process a new frame of detections. Returns all active tracked objects.
  ///
  /// [lockedTrackId] — if provided, only this track is eligible for
  /// Mahalanobis fallback matching (Stage 2). All other tracks use IoU only.
  /// This prevents static circle tracks from being pulled to wrong positions
  /// by the wide Mahalanobis gate.
  List<TrackedObject> update(List<Detection> detections, {int? lockedTrackId, double? lastMeasuredBallArea}) {
    // 1. Predict all existing tracks
    for (final t in _trackedTracks) t.predict();
    for (final t in _lostTracks) t.predict();

    // 2. Split detections by confidence
    final highDets = <Detection>[];
    final lowDets = <Detection>[];
    for (final d in detections) {
      if (d.confidence >= confidenceSplit) {
        highDets.add(d);
      } else {
        lowDets.add(d);
      }
    }

    // 3. Pass 1: match high-confidence detections to tracked tracks
    final matchedTrackIndices = <int>{};
    final matchedDetIndices = <int>{};

    _greedyMatch(
      tracks: _trackedTracks,
      dets: highDets,
      iouThreshold: highIoUThreshold,
      matchedTrackIdx: matchedTrackIndices,
      matchedDetIdx: matchedDetIndices,
      lockedTrackId: lockedTrackId,
      lastMeasuredBallArea: lastMeasuredBallArea,
    );

    // Collect unmatched tracked tracks
    final unmatchedTracked = <_STrack>[];
    for (var i = 0; i < _trackedTracks.length; i++) {
      if (!matchedTrackIndices.contains(i)) {
        unmatchedTracked.add(_trackedTracks[i]);
      }
    }

    // 4. Pass 2: match low-confidence detections to unmatched tracked + lost
    final pass2Tracks = [...unmatchedTracked, ..._lostTracks];
    final matchedPass2TrackIdx = <int>{};
    final matchedPass2DetIdx = <int>{};

    _greedyMatch(
      tracks: pass2Tracks,
      dets: lowDets,
      iouThreshold: lowIoUThreshold,
      matchedTrackIdx: matchedPass2TrackIdx,
      matchedDetIdx: matchedPass2DetIdx,
      lockedTrackId: lockedTrackId,
      lastMeasuredBallArea: lastMeasuredBallArea,
    );

    // Also try matching remaining high-confidence detections to lost tracks
    final remainingHighDets = <Detection>[];
    final remainingHighOrigIdx = <int>[];
    for (var i = 0; i < highDets.length; i++) {
      if (!matchedDetIndices.contains(i)) {
        remainingHighDets.add(highDets[i]);
        remainingHighOrigIdx.add(i);
      }
    }
    final matchedLostIdx = <int>{};
    final matchedRemHighIdx = <int>{};
    _greedyMatch(
      tracks: _lostTracks,
      dets: remainingHighDets,
      iouThreshold: highIoUThreshold,
      matchedTrackIdx: matchedLostIdx,
      matchedDetIdx: matchedRemHighIdx,
      lockedTrackId: lockedTrackId,
      lastMeasuredBallArea: lastMeasuredBallArea,
    );

    // 5. Mark truly unmatched tracks as lost
    final stillUnmatched = <_STrack>[];
    for (var i = 0; i < unmatchedTracked.length; i++) {
      if (!matchedPass2TrackIdx.contains(i)) {
        unmatchedTracked[i].markLost();
        stillUnmatched.add(unmatchedTracked[i]);
      }
    }
    for (var i = 0; i < _lostTracks.length; i++) {
      final offsetIdx = unmatchedTracked.length + i;
      if (!matchedPass2TrackIdx.contains(offsetIdx) &&
          !matchedLostIdx.contains(i)) {
        _lostTracks[i].markLost();
      }
    }

    // 6. Create new tracks from unmatched high-confidence detections
    final newTracks = <_STrack>[];
    for (var i = 0; i < remainingHighDets.length; i++) {
      if (!matchedRemHighIdx.contains(i)) {
        newTracks.add(_STrack(remainingHighDets[i]));
      }
    }

    // 7. Rebuild track lists
    final nextTracked = <_STrack>[];
    final nextLost = <_STrack>[];

    // Tracks that were matched in pass 1
    for (var i = 0; i < _trackedTracks.length; i++) {
      if (matchedTrackIndices.contains(i)) {
        nextTracked.add(_trackedTracks[i]);
      }
    }

    // Tracks matched in pass 2
    for (var i = 0; i < pass2Tracks.length; i++) {
      if (matchedPass2TrackIdx.contains(i)) {
        nextTracked.add(pass2Tracks[i]);
      }
    }

    // Lost tracks re-matched from remaining high dets
    for (var i = 0; i < _lostTracks.length; i++) {
      if (matchedLostIdx.contains(i)) {
        _lostTracks[i].state = TrackState.tracked;
        nextTracked.add(_lostTracks[i]);
      }
    }

    // New tracks
    nextTracked.addAll(newTracks);

    // Lost tracks: previously lost + newly lost, minus removed
    for (final t in _lostTracks) {
      if (t.state == TrackState.lost &&
          !matchedLostIdx.contains(_lostTracks.indexOf(t))) {
        if (t.consecutiveLostFrames > _effectiveMaxLost(t)) {
          t.state = TrackState.removed;
        } else {
          nextLost.add(t);
        }
      }
    }
    for (final t in stillUnmatched) {
      if (t.consecutiveLostFrames > _effectiveMaxLost(t)) {
        t.state = TrackState.removed;
      } else {
        nextLost.add(t);
      }
    }

    // 8. Evaluate static flag
    for (final t in nextTracked) {
      t.evaluateStatic(
        minFrames: staticMinFrames,
        maxDisp: staticMaxDisplacement,
      );
    }
    for (final t in nextLost) {
      t.evaluateStatic(
        minFrames: staticMinFrames,
        maxDisp: staticMaxDisplacement,
      );
    }

    _trackedTracks
      ..clear()
      ..addAll(nextTracked);
    _lostTracks
      ..clear()
      ..addAll(nextLost);

    // 9. Build public snapshot
    _lastPublicSnapshot = [
      for (final t in _trackedTracks) t.toPublic(),
      for (final t in _lostTracks) t.toPublic(),
    ];
    return _lastPublicSnapshot;
  }

  /// Set the protected track ID. This track gets [protectedMaxLostFrames]
  /// survival time instead of [maxLostFrames]. Pass null to clear protection.
  void setProtectedTrackId(int? id) {
    _protectedTrackId = id;
  }

  /// Returns the effective max lost frames for a track — extended for the
  /// protected track, default for all others.
  int _effectiveMaxLost(_STrack t) {
    if (_protectedTrackId != null && t.id == _protectedTrackId) {
      return protectedMaxLostFrames;
    }
    return maxLostFrames;
  }

  /// Reset all tracks and ID counter.
  void reset() {
    _trackedTracks.clear();
    _lostTracks.clear();
    _lastPublicSnapshot = const [];
    _protectedTrackId = null;
    _STrack._nextId = 1;
  }

  // ---- Two-stage matching: IoU first, Mahalanobis fallback ----
  //
  // Stage 1: Pure IoU matching — keeps static objects (target circles) locked
  //          to their own positions with IoU ≈ 1.0.
  // Stage 2: Mahalanobis distance fallback — ONLY for tracks that Stage 1
  //          failed to match. Rescues fast-moving objects (kicked ball) where
  //          IoU drops to 0 because displacement exceeds bbox width.
  //
  // Chi-squared threshold for 4 DOF (cx, cy, w, h) at 95% confidence = 9.488.
  // Statistical constant from probability theory, not a tuning parameter.
  static const double _chi2Threshold95 = 9.488;

  void _greedyMatch({
    required List<_STrack> tracks,
    required List<Detection> dets,
    required double iouThreshold,
    required Set<int> matchedTrackIdx,
    required Set<int> matchedDetIdx,
    int? lockedTrackId,
    double? lastMeasuredBallArea,
  }) {
    if (tracks.isEmpty || dets.isEmpty) return;

    // ---- Stage 1: Pure IoU matching ----
    final iouCandidates = <(int, int, double)>[];
    for (var ti = 0; ti < tracks.length; ti++) {
      final predicted = tracks[ti].predictedBbox;
      for (var di = 0; di < dets.length; di++) {
        final iou = computeIoU(predicted, dets[di].bbox);
        if (iou >= iouThreshold) {
          iouCandidates.add((ti, di, iou));
        }
      }
    }

    iouCandidates.sort((a, b) => b.$3.compareTo(a.$3));

    for (final (ti, di, _) in iouCandidates) {
      if (matchedTrackIdx.contains(ti) || matchedDetIdx.contains(di)) continue;
      tracks[ti].update(dets[di]);
      matchedTrackIdx.add(ti);
      matchedDetIdx.add(di);
    }

    // ---- Stage 2: Mahalanobis fallback — ONLY for locked ball track ----
    // Rescues the ball during explosive kick acceleration where IoU=0.
    // All other tracks (circles, etc.) use IoU-only and go to lost if unmatched.
    if (lockedTrackId == null ||
        matchedDetIdx.length >= dets.length) {
      return;
    }

    final mahalCandidates = <(int, int, double)>[];
    for (var ti = 0; ti < tracks.length; ti++) {
      if (matchedTrackIdx.contains(ti)) continue;
      // ONLY the locked ball track gets Mahalanobis rescue
      if (tracks[ti].id != lockedTrackId) continue;

      for (var di = 0; di < dets.length; di++) {
        if (matchedDetIdx.contains(di)) continue;

        // Bbox area ratio check — reject if detection size is too different
        // from the ball's last measured size. Uses real measurement instead of
        // Kalman predicted area (which drifts during pure predictions).
        // Falls back to Kalman predicted area if no measurement available.
        final refArea = lastMeasuredBallArea ??
            (tracks[ti].kalman.width.abs() * tracks[ti].kalman.height.abs());
        final detArea = dets[di].bbox.width * dets[di].bbox.height;
        final areaRatio = refArea > 0 ? detArea / refArea : 0.0;
        if (areaRatio > 2.0 || areaRatio < 0.3) continue;

        final mahalSq = tracks[ti].kalman.mahalanobisDistSq(dets[di].bbox);
        if (mahalSq != null && mahalSq <= _chi2Threshold95) {
          mahalCandidates.add((ti, di, mahalSq));
        }
      }
    }

    mahalCandidates.sort((a, b) => a.$3.compareTo(b.$3));

    for (final (ti, di, mahalSq) in mahalCandidates) {
      if (matchedTrackIdx.contains(ti) || matchedDetIdx.contains(di)) continue;
      tracks[ti].update(dets[di]);
      matchedTrackIdx.add(ti);
      matchedDetIdx.add(di);

      diagLog('DIAG-MATCH: Mahalanobis rescue trackId=${tracks[ti].id} '
          'mahal²=${mahalSq.toStringAsFixed(4)} '
          'det=(${dets[di].bbox.center.dx.toStringAsFixed(3)}, '
          '${dets[di].bbox.center.dy.toStringAsFixed(3)})');
    }
  }
}
