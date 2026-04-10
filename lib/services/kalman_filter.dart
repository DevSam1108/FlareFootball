/// A 4-state linear Kalman filter for soccer ball position smoothing and
/// velocity estimation.
///
/// The filter maintains state vector [px, py, vx, vy] where:
/// - px, py: ball position in normalized [0,1] camera coordinates
/// - vx, vy: ball velocity in normalized units per frame
///
/// State transition model (constant velocity, dt = 1 frame):
///   px' = px + vx
///   py' = py + vy
///   vx' = vx
///   vy' = vy
///
/// Measurement model: YOLO detections provide [px, py] directly.
/// The measurement matrix selects only the position components of the state.
///
/// All linear algebra uses flat [List<double>] arrays with inline operations.
/// No external packages are used -- this is pure Dart math suitable for
/// frame-rate execution without allocation pressure.
///
/// Typical usage:
/// ```dart
/// final kf = BallKalmanFilter();
/// // Each frame:
/// kf.predict();                      // advance by one frame
/// kf.update(detectedPx, detectedPy); // correct with YOLO measurement
/// final (:px, :py) = kf.position;   // smoothed position
/// final (:vx, :vy) = kf.velocity;   // estimated velocity
/// ```
class BallKalmanFilter {
  // ---------------------------------------------------------------------------
  // Noise parameters
  // ---------------------------------------------------------------------------

  /// Process noise variance for position states (px, py).
  ///
  /// Low value means the filter trusts the constant-velocity prediction more.
  /// Default 0.0001: ball position deviates little from linear prediction
  /// within a single frame.
  final double _processNoisePos;

  /// Process noise variance for velocity states (vx, vy).
  ///
  /// Higher than position noise because kicks cause rapid acceleration.
  /// Default 0.01.
  final double _processNoiseVel;

  /// Measurement noise variance for YOLO position detections.
  ///
  /// Captures YOLO bounding box center jitter (~0.5% of frame).
  /// Default 0.005.
  final double _measurementNoise;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// State vector [px, py, vx, vy]. Length 4.
  late List<double> _state;

  /// State covariance matrix (4x4, row-major). Length 16.
  late List<double> _covariance;

  /// Whether the filter has received its first [update] call.
  bool _isInitialized = false;

  // ---------------------------------------------------------------------------
  // Fixed matrices (computed once, reused every frame)
  // ---------------------------------------------------------------------------

  /// State transition matrix (4x4, row-major, constant velocity, dt=1).
  ///
  /// Implements: px'=px+vx, py'=py+vy, vx'=vx, vy'=vy.
  ///
  /// [1 0 1 0]
  /// [0 1 0 1]
  /// [0 0 1 0]
  /// [0 0 0 1]
  late final List<double> _stateTransition;

  /// Process noise covariance (4x4, row-major, diagonal).
  ///
  /// Diagonal: [posNoise, posNoise, velNoise, velNoise].
  late final List<double> _processNoiseMat;

  /// Measurement matrix (2x4, row-major).
  ///
  /// Selects px and py from the state vector.
  ///
  /// [1 0 0 0]
  /// [0 1 0 0]
  static const List<double> _measurementMat = [
    1.0, 0.0, 0.0, 0.0, //
    0.0, 1.0, 0.0, 0.0,
  ];

  /// Measurement noise covariance (2x2, row-major, diagonal).
  late final List<double> _measurementNoiseMat;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  /// Creates a [BallKalmanFilter] with tunable noise parameters.
  ///
  /// [processNoise] splits into separate position and velocity noise:
  ///   - Position noise = [processNoise] (low -- ball doesn't teleport)
  ///   - Velocity noise = [processNoise] * 100 (higher -- kicks change velocity)
  ///
  /// [measurementNoise] is the variance of YOLO detection jitter.
  BallKalmanFilter({
    double processNoise = 0.0001,
    double measurementNoise = 0.005,
  })  : _processNoisePos = processNoise,
        _processNoiseVel = processNoise * 100.0,
        _measurementNoise = measurementNoise {
    _stateTransition = [
      1.0, 0.0, 1.0, 0.0, //
      0.0, 1.0, 0.0, 1.0, //
      0.0, 0.0, 1.0, 0.0, //
      0.0, 0.0, 0.0, 1.0,
    ];

    _processNoiseMat = [
      _processNoisePos, 0.0, 0.0, 0.0, //
      0.0, _processNoisePos, 0.0, 0.0, //
      0.0, 0.0, _processNoiseVel, 0.0, //
      0.0, 0.0, 0.0, _processNoiseVel,
    ];

    _measurementNoiseMat = [
      _measurementNoise, 0.0, //
      0.0, _measurementNoise,
    ];

    _state = List.filled(4, 0.0);
    _covariance = List.filled(16, 0.0);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// True after the first [update] call. False before first update and after
  /// [reset].
  bool get isInitialized => _isInitialized;

  /// Current smoothed ball position as a named record (px, py).
  ///
  /// Returns (0.0, 0.0) when [isInitialized] is false.
  ({double px, double py}) get position => (px: _state[0], py: _state[1]);

  /// Current estimated ball velocity as a named record (vx, vy).
  ///
  /// Velocity is in normalized units per frame. Returns (0.0, 0.0) when
  /// [isInitialized] is false.
  ({double vx, double vy}) get velocity => (vx: _state[2], vy: _state[3]);

  /// Advances the filter state by one frame using the constant-velocity model.
  ///
  /// Call once per frame before [update]. Safe to call multiple consecutive
  /// times to extrapolate position during occlusion.
  ///
  /// No-op if [isInitialized] is false.
  void predict() {
    if (!_isInitialized) return;

    // state = F * state  (4x4 * 4x1)
    _state = _mat4x4MulVec4(_stateTransition, _state);

    // covariance = F * covariance * F^T + Q  (4x4 * 4x4 * 4x4 + 4x4)
    final fp = _mat4x4Mul(_stateTransition, _covariance);
    final ft = _mat4x4Transpose(_stateTransition);
    final fpft = _mat4x4Mul(fp, ft);
    _covariance = _mat4x4Add(fpft, _processNoiseMat);
  }

  /// Corrects the filter state with a YOLO ball position measurement.
  ///
  /// On the first call, initializes the state directly from the measurement
  /// with zero velocity and moderate initial covariance. Subsequent calls
  /// apply the standard Kalman update equations.
  ///
  /// [px] and [py] are normalized ball position in [0, 1].
  void update(double px, double py) {
    if (!_isInitialized) {
      _initFromMeasurement(px, py);
      return;
    }

    // Innovation: y = z - H * state  (z is [px, py])
    final innovX = px - _state[0];
    final innovY = py - _state[1];

    // Innovation covariance: S = H * covariance * H^T + R  (2x2)
    final hp = _mat2x4Mul2x4(_measurementMat, _covariance); // 2x4
    final ht = _mat4x2Transpose(_measurementMat);            // 4x2 (H^T)
    final s = _mat2x4Mul4x2(hp, ht);                        // 2x2
    final sTotal = _mat2x2Add(s, _measurementNoiseMat);      // S + R

    // Kalman gain: K = covariance * H^T * S^{-1}  (4x4 * 4x2 * 2x2 -> 4x2)
    final pht = _mat4x4Mul4x2(_covariance, ht);  // 4x2
    final sInv = _mat2x2Inverse(sTotal);          // 2x2
    final gain = _mat4x2Mul2x2(pht, sInv);        // 4x2 Kalman gain

    // State update: state = state + K * y  (4x2 * 2x1 -> 4x1)
    _state[0] += gain[0] * innovX + gain[1] * innovY;
    _state[1] += gain[2] * innovX + gain[3] * innovY;
    _state[2] += gain[4] * innovX + gain[5] * innovY;
    _state[3] += gain[6] * innovX + gain[7] * innovY;

    // Covariance update: covariance = (I - K * H) * covariance
    final kh = _mat4x2Mul2x4(gain, _measurementMat); // 4x4
    final iMinusKh = _mat4x4SubFromIdentity(kh);      // I - K*H
    _covariance = _mat4x4Mul(iMinusKh, _covariance);
  }

  /// Clears all state back to uninitialized.
  ///
  /// Called on screen dispose or when tracking is lost beyond recovery.
  /// After reset, [isInitialized] is false and [predict] is a no-op.
  void reset() {
    _isInitialized = false;
    _state = List.filled(4, 0.0);
    _covariance = List.filled(16, 0.0);
  }

  // ---------------------------------------------------------------------------
  // Initialization helper
  // ---------------------------------------------------------------------------

  void _initFromMeasurement(double px, double py) {
    _state = [px, py, 0.0, 0.0];

    // Initial covariance: moderate uncertainty in position, higher in velocity.
    // This allows the filter to converge quickly once motion is observed.
    const posUncertainty = 0.1;
    const velUncertainty = 1.0;
    _covariance = [
      posUncertainty, 0.0, 0.0, 0.0, //
      0.0, posUncertainty, 0.0, 0.0, //
      0.0, 0.0, velUncertainty, 0.0, //
      0.0, 0.0, 0.0, velUncertainty,
    ];
    _isInitialized = true;
  }

  // ---------------------------------------------------------------------------
  // Inline matrix operations -- all fixed-size, no allocation beyond lists
  // ---------------------------------------------------------------------------

  /// Multiplies a 4x4 matrix [a] by a 4x1 vector [v]. Returns 4x1 vector.
  static List<double> _mat4x4MulVec4(List<double> a, List<double> v) {
    return [
      a[0] * v[0] + a[1] * v[1] + a[2] * v[2] + a[3] * v[3],
      a[4] * v[0] + a[5] * v[1] + a[6] * v[2] + a[7] * v[3],
      a[8] * v[0] + a[9] * v[1] + a[10] * v[2] + a[11] * v[3],
      a[12] * v[0] + a[13] * v[1] + a[14] * v[2] + a[15] * v[3],
    ];
  }

  /// Multiplies two 4x4 matrices [a] and [b]. Returns 4x4 matrix.
  static List<double> _mat4x4Mul(List<double> a, List<double> b) {
    final c = List.filled(16, 0.0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += a[row * 4 + k] * b[k * 4 + col];
        }
        c[row * 4 + col] = sum;
      }
    }
    return c;
  }

  /// Transposes a 4x4 matrix [a]. Returns 4x4 matrix.
  static List<double> _mat4x4Transpose(List<double> a) {
    return [
      a[0],  a[4],  a[8],  a[12],
      a[1],  a[5],  a[9],  a[13],
      a[2],  a[6],  a[10], a[14],
      a[3],  a[7],  a[11], a[15],
    ];
  }

  /// Adds two 4x4 matrices element-wise. Returns 4x4 matrix.
  static List<double> _mat4x4Add(List<double> a, List<double> b) {
    final c = List.filled(16, 0.0);
    for (int i = 0; i < 16; i++) {
      c[i] = a[i] + b[i];
    }
    return c;
  }

  /// Computes I - [a] for a 4x4 matrix. Returns 4x4 matrix.
  static List<double> _mat4x4SubFromIdentity(List<double> a) {
    final c = List.filled(16, 0.0);
    for (int i = 0; i < 16; i++) {
      c[i] = -a[i];
    }
    c[0] += 1.0;
    c[5] += 1.0;
    c[10] += 1.0;
    c[15] += 1.0;
    return c;
  }

  /// Multiplies 2x4 matrix [h] by 4x4 matrix [p]. Returns 2x4 matrix.
  ///
  /// [h] layout: [h00, h01, h02, h03, h10, h11, h12, h13] (length 8).
  /// [p] layout: 4x4 row-major (length 16).
  static List<double> _mat2x4Mul2x4(List<double> h, List<double> p) {
    final c = List.filled(8, 0.0);
    for (int row = 0; row < 2; row++) {
      for (int col = 0; col < 4; col++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += h[row * 4 + k] * p[k * 4 + col];
        }
        c[row * 4 + col] = sum;
      }
    }
    return c;
  }

  /// Transposes 2x4 matrix [h] (length 8) to 4x2 (length 8).
  ///
  /// Input row-major [h00, h01, h02, h03, h10, h11, h12, h13].
  /// Output row-major 4x2: [h00, h10, h01, h11, h02, h12, h03, h13].
  static List<double> _mat4x2Transpose(List<double> h) {
    return [
      h[0], h[4],
      h[1], h[5],
      h[2], h[6],
      h[3], h[7],
    ];
  }

  /// Multiplies 2x4 matrix [hp] by 4x2 matrix [ht]. Returns 2x2 matrix.
  static List<double> _mat2x4Mul4x2(List<double> hp, List<double> ht) {
    return [
      hp[0]*ht[0] + hp[1]*ht[2] + hp[2]*ht[4] + hp[3]*ht[6],
      hp[0]*ht[1] + hp[1]*ht[3] + hp[2]*ht[5] + hp[3]*ht[7],
      hp[4]*ht[0] + hp[5]*ht[2] + hp[6]*ht[4] + hp[7]*ht[6],
      hp[4]*ht[1] + hp[5]*ht[3] + hp[6]*ht[5] + hp[7]*ht[7],
    ];
  }

  /// Adds two 2x2 matrices element-wise. Returns 2x2 matrix.
  static List<double> _mat2x2Add(List<double> a, List<double> b) {
    return [a[0]+b[0], a[1]+b[1], a[2]+b[2], a[3]+b[3]];
  }

  /// Inverts a 2x2 matrix using the direct formula.
  ///
  /// For matrix [[a, b], [c, d]], inverse = (1/det) * [[d, -b], [-c, a]].
  /// Throws [StateError] if the matrix is singular (det < 1e-12).
  static List<double> _mat2x2Inverse(List<double> m) {
    final det = m[0] * m[3] - m[1] * m[2];
    if (det.abs() < 1e-12) {
      throw StateError('Innovation covariance is singular; cannot invert.');
    }
    final invDet = 1.0 / det;
    return [
       m[3] * invDet,
      -m[1] * invDet,
      -m[2] * invDet,
       m[0] * invDet,
    ];
  }

  /// Multiplies 4x4 matrix [p] by 4x2 matrix [ht]. Returns 4x2 matrix.
  static List<double> _mat4x4Mul4x2(List<double> p, List<double> ht) {
    final c = List.filled(8, 0.0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 2; col++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += p[row * 4 + k] * ht[k * 2 + col];
        }
        c[row * 2 + col] = sum;
      }
    }
    return c;
  }

  /// Multiplies 4x2 matrix [k] by 2x2 matrix [sInv]. Returns 4x2 matrix.
  static List<double> _mat4x2Mul2x2(List<double> k, List<double> sInv) {
    return [
      k[0]*sInv[0] + k[1]*sInv[2],  k[0]*sInv[1] + k[1]*sInv[3],
      k[2]*sInv[0] + k[3]*sInv[2],  k[2]*sInv[1] + k[3]*sInv[3],
      k[4]*sInv[0] + k[5]*sInv[2],  k[4]*sInv[1] + k[5]*sInv[3],
      k[6]*sInv[0] + k[7]*sInv[2],  k[6]*sInv[1] + k[7]*sInv[3],
    ];
  }

  /// Multiplies 4x2 matrix [k] by 2x4 matrix [h]. Returns 4x4 matrix.
  static List<double> _mat4x2Mul2x4(List<double> k, List<double> h) {
    final c = List.filled(16, 0.0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        double sum = 0.0;
        for (int m = 0; m < 2; m++) {
          sum += k[row * 2 + m] * h[m * 4 + col];
        }
        c[row * 4 + col] = sum;
      }
    }
    return c;
  }
}
