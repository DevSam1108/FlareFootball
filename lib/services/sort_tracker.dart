import 'dart:math' show max, min;

/// A detection bounding box in normalized [0,1] coordinates.
///
/// Used as input to [SortTracker.update] — each frame provides a list of these
/// from YOLO detections.
class Detection {
  /// Bounding box: left, top, right, bottom in normalized [0,1] space.
  final double left, top, right, bottom;

  /// Detection confidence from YOLO (0.0–1.0).
  final double confidence;

  /// YOLO class name (e.g. 'Soccer ball', 'ball', 'tennis-ball').
  final String className;

  const Detection({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
    required this.className,
  });

  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
  double get w => right - left;
  double get h => bottom - top;
  double get area => w * h;
}

/// Track lifecycle state in the ByteTrack algorithm.
enum TrackState {
  /// Actively matched with detections.
  tracked,

  /// Temporarily lost — kept alive for [SortTracker.maxTimeLost] frames.
  lost,

  /// Permanently removed — will not be matched again.
  removed,
}

/// A single tracked object with 8-state Kalman filter.
///
/// State vector: [cx, cy, w, h, vx, vy, vw, vh] where:
/// - cx, cy: bounding box center in normalized [0,1]
/// - w, h: bounding box width and height in normalized [0,1]
/// - vx, vy: velocity of center (per frame)
/// - vw, vh: rate of change of width and height (per frame)
class STrack {
  /// Unique track identifier, assigned by [SortTracker].
  final int trackId;

  /// Current lifecycle state.
  TrackState state;

  /// Number of consecutive frames this track has been matched.
  int hitStreak = 0;

  /// Number of consecutive frames without a matching detection.
  int timeSinceUpdate = 0;

  /// Total number of frames this track has existed.
  int age = 0;

  /// YOLO class name of the most recent matched detection.
  String className;

  /// Confidence of the most recent matched detection.
  double confidence;

  // -- Kalman state (8-dimensional) --

  /// State vector [cx, cy, w, h, vx, vy, vw, vh]. Length 8.
  List<double> _x;

  /// Error covariance matrix (8x8 row-major). Length 64.
  // ignore: non_constant_identifier_names
  List<double> _P;

  bool _initialized = false;

  STrack._({
    required this.trackId,
    required Detection detection,
  })  : className = detection.className,
        confidence = detection.confidence,
        state = TrackState.tracked,
        hitStreak = 1,
        _x = List.filled(8, 0.0),
        _P = List.filled(64, 0.0) {
    _initFromDetection(detection);
  }

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  double get cx => _x[0];
  double get cy => _x[1];
  double get w => _x[2];
  double get h => _x[3];
  double get vx => _x[4];
  double get vy => _x[5];
  double get vw => _x[6];
  double get vh => _x[7];

  double get left => cx - w / 2;
  double get top => cy - h / 2;
  double get right => cx + w / 2;
  double get bottom => cy + h / 2;

  double get area => w * h;

  bool get isTracked => state == TrackState.tracked;
  bool get isLost => state == TrackState.lost;

  /// Speed magnitude in normalized units per frame.
  double get speed {
    return _sqrt(vx * vx + vy * vy);
  }

  // ---------------------------------------------------------------------------
  // Kalman filter operations
  // ---------------------------------------------------------------------------

  /// Advances the track state by one frame (constant velocity model).
  void predict() {
    if (!_initialized) return;

    // State prediction: x = F * x
    // F is identity + velocity integration:
    //   cx' = cx + vx,  cy' = cy + vy
    //   w'  = w  + vw,  h'  = h  + vh
    //   velocities unchanged
    _x[0] += _x[4];
    _x[1] += _x[5];
    _x[2] += _x[6];
    _x[3] += _x[7];

    // Covariance prediction: P = F * P * F^T + Q
    // Since F = I + off-diag, we compute F*P*F^T inline.
    _predictCovariance();

    age++;
    timeSinceUpdate++;
  }

  /// Corrects the track state with a matched detection.
  void update(Detection det) {
    if (!_initialized) {
      _initFromDetection(det);
      return;
    }

    // Measurement vector z = [cx, cy, w, h]
    final z = [det.cx, det.cy, det.w, det.h];

    // Innovation: y = z - H * x (H selects first 4 states)
    final y = [
      z[0] - _x[0],
      z[1] - _x[1],
      z[2] - _x[2],
      z[3] - _x[3],
    ];

    // Innovation covariance: S = H * P * H^T + R (4x4)
    // H selects rows 0-3 of P -> S = P[0:4, 0:4] + R
    final s = List.filled(16, 0.0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        s[i * 4 + j] = _P[i * 8 + j];
      }
    }
    // Add measurement noise R (diagonal)
    s[0] += _rPos;
    s[5] += _rPos;
    s[10] += _rSize;
    s[15] += _rSize;

    // Kalman gain: K = P * H^T * S^-1 (8x4)
    // P * H^T = P[:, 0:4]
    final pht = List.filled(32, 0.0); // 8x4
    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 4; j++) {
        pht[i * 4 + j] = _P[i * 8 + j];
      }
    }

    final sInv = _mat4x4Inverse(s);
    final k = _mat8x4Mul4x4(pht, sInv); // 8x4

    // State update: x = x + K * y
    for (int i = 0; i < 8; i++) {
      double sum = 0.0;
      for (int j = 0; j < 4; j++) {
        sum += k[i * 4 + j] * y[j];
      }
      _x[i] += sum;
    }

    // Covariance update: P = (I - K * H) * P
    // K*H is 8x8 where (K*H)[i][j] = K[i][j] for j<4, 0 for j>=4
    final kh = List.filled(64, 0.0);
    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 4; j++) {
        kh[i * 8 + j] = k[i * 4 + j];
      }
    }
    // I - KH
    final iMinusKH = List.filled(64, 0.0);
    for (int i = 0; i < 64; i++) {
      iMinusKH[i] = -kh[i];
    }
    for (int i = 0; i < 8; i++) {
      iMinusKH[i * 8 + i] += 1.0;
    }
    // P = (I-KH) * P
    _P = _mat8x8Mul(iMinusKH, _P);

    // Update metadata
    className = det.className;
    confidence = det.confidence;
    timeSinceUpdate = 0;
    hitStreak++;
    state = TrackState.tracked;
  }

  /// Returns the predicted bounding box as [left, top, right, bottom].
  List<double> get predictedBbox => [left, top, right, bottom];

  // ---------------------------------------------------------------------------
  // Noise parameters
  // ---------------------------------------------------------------------------

  /// Measurement noise for position (cx, cy).
  static const double _rPos = 0.001;

  /// Measurement noise for size (w, h).
  static const double _rSize = 0.01;

  /// Process noise for position.
  static const double _qPos = 0.0001;

  /// Process noise for size.
  static const double _qSize = 0.0004;

  /// Process noise for velocity.
  static const double _qVel = 0.01;

  /// Process noise for size velocity.
  static const double _qSizeVel = 0.001;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  void _initFromDetection(Detection det) {
    _x = [det.cx, det.cy, det.w, det.h, 0.0, 0.0, 0.0, 0.0];

    // Initial covariance: moderate position uncertainty, higher velocity.
    _P = List.filled(64, 0.0);
    _P[0] = 0.01;   // cx
    _P[9] = 0.01;   // cy
    _P[18] = 0.01;  // w
    _P[27] = 0.01;  // h
    _P[36] = 1.0;   // vx — high uncertainty, no velocity observed yet
    _P[45] = 1.0;   // vy
    _P[54] = 0.1;   // vw
    _P[63] = 0.1;   // vh

    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Covariance prediction: P = F * P * F^T + Q
  // ---------------------------------------------------------------------------

  void _predictCovariance() {
    // F = I + B where B[0][4]=1, B[1][5]=1, B[2][6]=1, B[3][7]=1
    // F*P: for i<4, row_i' = row_i + row_{i+4}
    // Then (F*P)*F^T: for j<4, col_j' = col_j + col_{j+4}
    //
    // We do this in-place in two passes.

    // Pass 1: F * P (row mixing)
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 8; j++) {
        _P[i * 8 + j] += _P[(i + 4) * 8 + j];
      }
    }

    // Pass 2: (F*P) * F^T (column mixing)
    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 4; j++) {
        _P[i * 8 + j] += _P[i * 8 + (j + 4)];
      }
    }

    // Add process noise Q (diagonal)
    _P[0] += _qPos;
    _P[9] += _qPos;
    _P[18] += _qSize;
    _P[27] += _qSize;
    _P[36] += _qVel;
    _P[45] += _qVel;
    _P[54] += _qSizeVel;
    _P[63] += _qSizeVel;
  }

  // ---------------------------------------------------------------------------
  // Matrix math (fixed-size, inline)
  // ---------------------------------------------------------------------------

  static List<double> _mat8x8Mul(List<double> a, List<double> b) {
    final c = List.filled(64, 0.0);
    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 8; j++) {
        double sum = 0.0;
        for (int k = 0; k < 8; k++) {
          sum += a[i * 8 + k] * b[k * 8 + j];
        }
        c[i * 8 + j] = sum;
      }
    }
    return c;
  }

  static List<double> _mat8x4Mul4x4(List<double> a, List<double> b) {
    final c = List.filled(32, 0.0);
    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 4; j++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += a[i * 4 + k] * b[k * 4 + j];
        }
        c[i * 4 + j] = sum;
      }
    }
    return c;
  }

  /// Inverts a 4x4 matrix using cofactor expansion.
  static List<double> _mat4x4Inverse(List<double> m) {
    // Using the analytical formula for 4x4 inverse
    final a = m[0], b = m[1], c = m[2], d = m[3];
    final e = m[4], f = m[5], g = m[6], h = m[7];
    final i = m[8], j = m[9], k = m[10], l = m[11];
    final mm = m[12], n = m[13], o = m[14], p = m[15];

    final kplo = k * p - l * o;
    final jpln = j * p - l * n;
    final jokn = j * o - k * n;
    final iplm = i * p - l * mm;
    final iokm = i * o - k * mm;
    final injm = i * n - j * mm;

    final det = a * (f * kplo - g * jpln + h * jokn) -
        b * (e * kplo - g * iplm + h * iokm) +
        c * (e * jpln - f * iplm + h * injm) -
        d * (e * jokn - f * iokm + g * injm);

    if (det.abs() < 1e-15) {
      // Near-singular: return large diagonal (heavily damped)
      final result = List.filled(16, 0.0);
      for (int idx = 0; idx < 4; idx++) {
        result[idx * 4 + idx] = 1e6;
      }
      return result;
    }

    final invDet = 1.0 / det;

    final gpho = g * p - h * o;
    final fphm = f * p - h * n; // reuse n for m[13]
    final fogn = f * o - g * n;
    final ephm = e * p - h * mm;
    final eogl = e * o - g * mm; // reuse mm
    final enfm = e * n - f * mm;

    final ghfl = g * l - h * k; // wrong: should use h
    final fhlj = f * l - h * j;
    final fkgj = f * k - g * j;
    final ehli = e * l - h * i;
    final ekgi = e * k - g * i;
    final ejfi = e * j - f * i;

    return [
      (f * kplo - g * jpln + h * jokn) * invDet,
      -(b * kplo - c * jpln + d * jokn) * invDet,
      (b * gpho - c * fphm + d * fogn) * invDet,
      -(b * ghfl - c * fhlj + d * fkgj) * invDet,

      -(e * kplo - g * iplm + h * iokm) * invDet,
      (a * kplo - c * iplm + d * iokm) * invDet,
      -(a * gpho - c * ephm + d * eogl) * invDet,
      (a * ghfl - c * ehli + d * ekgi) * invDet,

      (e * jpln - f * iplm + h * injm) * invDet,
      -(a * jpln - b * iplm + d * injm) * invDet,
      (a * fphm - b * ephm + d * enfm) * invDet,
      -(a * fhlj - b * ehli + d * ejfi) * invDet,

      -(e * jokn - f * iokm + g * injm) * invDet,
      (a * jokn - b * iokm + c * injm) * invDet,
      -(a * fogn - b * eogl + c * enfm) * invDet,
      (a * fkgj - b * ekgi + c * ejfi) * invDet,
    ];
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0.0;
    // Newton's method, 8 iterations — sufficient for doubles.
    double r = x;
    for (int i = 0; i < 8; i++) {
      r = (r + x / r) * 0.5;
    }
    return r;
  }
}

// =============================================================================
// SortTracker — ByteTrack multi-object tracker
// =============================================================================

/// ByteTrack-style multi-object tracker.
///
/// Each frame, call [update] with the list of YOLO [Detection]s. The tracker
/// performs:
/// 1. Predict all existing tracks forward one frame.
/// 2. First association: match high-confidence detections to tracks via IoU.
/// 3. Second association: match remaining low-confidence detections to
///    unmatched tracks via IoU (the key ByteTrack insight).
/// 4. Create new tracks from unmatched high-confidence detections.
/// 5. Mark unmatched tracks as lost; remove tracks lost too long.
///
/// All coordinates are in normalized [0,1] space matching YOLO output.
class SortTracker {
  /// Minimum IoU for first-pass (high-confidence) matching.
  final double highMatchThreshold;

  /// Minimum IoU for second-pass (low-confidence) matching.
  final double lowMatchThreshold;

  /// Confidence threshold separating high/low detections for two-pass matching.
  final double highConfThreshold;

  /// Maximum frames a track can be lost before removal.
  final int maxTimeLost;

  /// Minimum hit streak before a track is considered confirmed.
  final int minHitStreak;

  int _nextId = 1;

  /// All active tracks (tracked + lost). Removed tracks are pruned.
  final List<STrack> _tracks = [];

  SortTracker({
    this.highMatchThreshold = 0.25,
    this.lowMatchThreshold = 0.15,
    this.highConfThreshold = 0.45,
    this.maxTimeLost = 30,
    this.minHitStreak = 1,
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// All currently tracked objects (tracked + lost, not removed).
  List<STrack> get tracks => List.unmodifiable(_tracks);

  /// Only actively tracked objects (state == tracked, hit streak >= minHitStreak).
  List<STrack> get confirmedTracks => _tracks
      .where((t) => t.isTracked && t.hitStreak >= minHitStreak)
      .toList();

  /// Process one frame of detections. Returns the list of confirmed tracks.
  List<STrack> update(List<Detection> detections) {
    // 1. Predict all existing tracks forward.
    for (final t in _tracks) {
      t.predict();
    }

    // 2. Split detections into high and low confidence.
    final highDets = <Detection>[];
    final lowDets = <Detection>[];
    for (final d in detections) {
      if (d.confidence >= highConfThreshold) {
        highDets.add(d);
      } else {
        lowDets.add(d);
      }
    }

    // 3. First association: high-confidence detections <-> all tracked tracks.
    final trackedTracks =
        _tracks.where((t) => t.state == TrackState.tracked).toList();
    final (matched1, unmatchedTracks1, unmatchedDets1) =
        _associate(trackedTracks, highDets, highMatchThreshold);

    // Apply matched pairs.
    for (final (trackIdx, detIdx) in matched1) {
      trackedTracks[trackIdx].update(highDets[detIdx]);
    }

    // 4. Second association: low-confidence detections <-> unmatched tracked tracks.
    final remainingTracks =
        unmatchedTracks1.map((i) => trackedTracks[i]).toList();
    final (matched2, unmatchedTracks2, _) =
        _associate(remainingTracks, lowDets, lowMatchThreshold);

    for (final (trackIdx, detIdx) in matched2) {
      remainingTracks[trackIdx].update(lowDets[detIdx]);
    }

    // 5. Try to match lost tracks with unmatched high-confidence detections.
    final lostTracks =
        _tracks.where((t) => t.state == TrackState.lost).toList();
    final unmatchedHighDets = unmatchedDets1.map((i) => highDets[i]).toList();
    final (matched3, _, unmatchedDetsFromLost) =
        _associate(lostTracks, unmatchedHighDets, highMatchThreshold);

    for (final (trackIdx, detIdx) in matched3) {
      lostTracks[trackIdx].update(unmatchedHighDets[detIdx]);
    }

    // 6. Mark unmatched tracked tracks as lost.
    for (final i in unmatchedTracks2) {
      final t = remainingTracks[i];
      t.state = TrackState.lost;
      t.hitStreak = 0;
    }

    // 7. Create new tracks from truly unmatched high-confidence detections.
    for (final i in unmatchedDetsFromLost) {
      _tracks.add(STrack._(
        trackId: _nextId++,
        detection: unmatchedHighDets[i],
      ));
    }

    // 8. Remove tracks that have been lost too long.
    for (final t in _tracks) {
      if (t.state == TrackState.lost && t.timeSinceUpdate > maxTimeLost) {
        t.state = TrackState.removed;
      }
    }
    _tracks.removeWhere((t) => t.state == TrackState.removed);

    return confirmedTracks;
  }

  /// Clears all tracks and resets ID counter.
  void reset() {
    _tracks.clear();
    _nextId = 1;
  }

  // ---------------------------------------------------------------------------
  // Hungarian-free greedy IoU association
  // ---------------------------------------------------------------------------

  /// Associates tracks with detections using greedy IoU matching.
  ///
  /// Returns (matched pairs, unmatched track indices, unmatched detection indices).
  (List<(int, int)>, List<int>, List<int>) _associate(
    List<STrack> tracks,
    List<Detection> dets,
    double minIoU,
  ) {
    if (tracks.isEmpty || dets.isEmpty) {
      return (
        [],
        List.generate(tracks.length, (i) => i),
        List.generate(dets.length, (i) => i),
      );
    }

    // Compute IoU cost matrix.
    final costs = <(double, int, int)>[];
    for (int ti = 0; ti < tracks.length; ti++) {
      for (int di = 0; di < dets.length; di++) {
        final iou = _computeIoU(tracks[ti], dets[di]);
        if (iou >= minIoU) {
          costs.add((iou, ti, di));
        }
      }
    }

    // Greedy: sort by descending IoU, assign greedily.
    costs.sort((a, b) => b.$1.compareTo(a.$1));

    final matchedTracks = <int>{};
    final matchedDets = <int>{};
    final matched = <(int, int)>[];

    for (final (_, ti, di) in costs) {
      if (matchedTracks.contains(ti) || matchedDets.contains(di)) continue;
      matched.add((ti, di));
      matchedTracks.add(ti);
      matchedDets.add(di);
    }

    final unmatchedTracks = <int>[];
    for (int i = 0; i < tracks.length; i++) {
      if (!matchedTracks.contains(i)) unmatchedTracks.add(i);
    }
    final unmatchedDets = <int>[];
    for (int i = 0; i < dets.length; i++) {
      if (!matchedDets.contains(i)) unmatchedDets.add(i);
    }

    return (matched, unmatchedTracks, unmatchedDets);
  }

  /// Computes IoU between a track's predicted bbox and a detection bbox.
  double _computeIoU(STrack track, Detection det) {
    final x1 = max(track.left, det.left);
    final y1 = max(track.top, det.top);
    final x2 = min(track.right, det.right);
    final y2 = min(track.bottom, det.bottom);

    if (x2 <= x1 || y2 <= y1) return 0.0;

    final intersection = (x2 - x1) * (y2 - y1);
    final trackArea = track.area;
    final detArea = det.area;
    final union = trackArea + detArea - intersection;

    if (union <= 0) return 0.0;
    return intersection / union;
  }
}
