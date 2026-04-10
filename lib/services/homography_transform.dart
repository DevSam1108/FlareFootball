import 'dart:ui' show Offset;

/// Computes a 3x3 perspective homography matrix from 4 source-destination
/// point pairs using the Direct Linear Transform (DLT) algorithm.
///
/// The transform maps points from source space (e.g., tapped camera
/// coordinates in normalized [0,1]) to destination space (e.g., a unit
/// square representing the target sheet).
///
/// All math is pure Dart -- no external matrix or linear algebra packages.
class HomographyTransform {
  /// The 3x3 homography matrix stored as a flat row-major List<double>
  /// of length 9: [h00, h01, h02, h10, h11, h12, h20, h21, h22].
  final List<double> matrix;

  HomographyTransform._(this.matrix);

  /// Cached inverse matrix, computed lazily on first call to
  /// [inverseTransform].
  List<double>? _inverse;

  /// Factory that computes the homography from exactly 4 source-destination
  /// point pairs using the 8-parameter DLT algorithm.
  ///
  /// [src] -- 4 points in source coordinate space.
  /// [dst] -- 4 corresponding points in destination space.
  factory HomographyTransform.fromCorrespondences(
    List<Offset> src,
    List<Offset> dst,
  ) {
    if (src.length != 4 || dst.length != 4) {
      throw ArgumentError('Exactly 4 point pairs required');
    }

    // Build the 8x9 augmented matrix for the linear system A*h = b.
    // Each point pair contributes 2 rows. We solve for h0..h7 with h8 = 1.
    final augmented = List.generate(8, (_) => List.filled(9, 0.0));

    for (int i = 0; i < 4; i++) {
      final sx = src[i].dx;
      final sy = src[i].dy;
      final dx = dst[i].dx;
      final dy = dst[i].dy;
      final row1 = i * 2;
      final row2 = row1 + 1;

      // Row for dx equation:
      // sx*h00 + sy*h01 + h02 + 0 + 0 + 0 - sx*dx*h20 - sy*dx*h21 = dx
      augmented[row1][0] = sx;
      augmented[row1][1] = sy;
      augmented[row1][2] = 1.0;
      augmented[row1][3] = 0.0;
      augmented[row1][4] = 0.0;
      augmented[row1][5] = 0.0;
      augmented[row1][6] = -sx * dx;
      augmented[row1][7] = -sy * dx;
      augmented[row1][8] = dx; // RHS

      // Row for dy equation:
      // 0 + 0 + 0 + sx*h10 + sy*h11 + h12 - sx*dy*h20 - sy*dy*h21 = dy
      augmented[row2][0] = 0.0;
      augmented[row2][1] = 0.0;
      augmented[row2][2] = 0.0;
      augmented[row2][3] = sx;
      augmented[row2][4] = sy;
      augmented[row2][5] = 1.0;
      augmented[row2][6] = -sx * dy;
      augmented[row2][7] = -sy * dy;
      augmented[row2][8] = dy; // RHS
    }

    final h = _solveLinearSystem(augmented, 8);

    // h8 = 1.0 (normalization).
    return HomographyTransform._(
      [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0],
    );
  }

  /// Applies the forward transform: source space -> destination space.
  Offset transform(Offset point) => _applyMatrix(matrix, point);

  /// Applies the inverse transform: destination space -> source space.
  Offset inverseTransform(Offset point) {
    _inverse ??= _invert3x3(matrix);
    return _applyMatrix(_inverse!, point);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Applies a 3x3 matrix to a 2D point using homogeneous coordinates.
  static Offset _applyMatrix(List<double> m, Offset p) {
    final x = m[0] * p.dx + m[1] * p.dy + m[2];
    final y = m[3] * p.dx + m[4] * p.dy + m[5];
    final w = m[6] * p.dx + m[7] * p.dy + m[8];
    if (w.abs() < 1e-12) return Offset.zero;
    return Offset(x / w, y / w);
  }

  /// Solves an n x (n+1) augmented matrix via Gaussian elimination with
  /// partial pivoting. Returns the n-element solution vector.
  static List<double> _solveLinearSystem(
    List<List<double>> aug,
    int n,
  ) {
    // Forward elimination with partial pivoting.
    for (int col = 0; col < n; col++) {
      // Find pivot row.
      int maxRow = col;
      double maxVal = aug[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        final val = aug[row][col].abs();
        if (val > maxVal) {
          maxVal = val;
          maxRow = row;
        }
      }
      if (maxVal < 1e-12) {
        throw ArgumentError(
          'Singular matrix: corners may be collinear. Please re-calibrate.',
        );
      }
      // Swap rows.
      if (maxRow != col) {
        final tmp = aug[col];
        aug[col] = aug[maxRow];
        aug[maxRow] = tmp;
      }
      // Eliminate below.
      for (int row = col + 1; row < n; row++) {
        final factor = aug[row][col] / aug[col][col];
        for (int j = col; j <= n; j++) {
          aug[row][j] -= factor * aug[col][j];
        }
      }
    }

    // Back substitution.
    final result = List.filled(n, 0.0);
    for (int row = n - 1; row >= 0; row--) {
      double sum = aug[row][n];
      for (int j = row + 1; j < n; j++) {
        sum -= aug[row][j] * result[j];
      }
      result[row] = sum / aug[row][row];
    }
    return result;
  }

  /// Inverts a 3x3 matrix using the adjugate/determinant formula.
  static List<double> _invert3x3(List<double> m) {
    final det = m[0] * (m[4] * m[8] - m[5] * m[7]) -
        m[1] * (m[3] * m[8] - m[5] * m[6]) +
        m[2] * (m[3] * m[7] - m[4] * m[6]);

    if (det.abs() < 1e-12) {
      throw ArgumentError('Matrix is singular and cannot be inverted.');
    }

    final invDet = 1.0 / det;
    return [
      (m[4] * m[8] - m[5] * m[7]) * invDet,
      (m[2] * m[7] - m[1] * m[8]) * invDet,
      (m[1] * m[5] - m[2] * m[4]) * invDet,
      (m[5] * m[6] - m[3] * m[8]) * invDet,
      (m[0] * m[8] - m[2] * m[6]) * invDet,
      (m[2] * m[3] - m[0] * m[5]) * invDet,
      (m[3] * m[7] - m[4] * m[6]) * invDet,
      (m[1] * m[6] - m[0] * m[7]) * invDet,
      (m[0] * m[4] - m[1] * m[3]) * invDet,
    ];
  }
}
