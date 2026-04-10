import 'dart:ui' show Offset;

import 'package:tensorflow_demo/services/homography_transform.dart';

/// Maps between camera-space coordinates and the 3x3 target zone grid.
///
/// The target zone layout is hardcoded:
/// ```
/// Top row (L->R):    7, 8, 9
/// Middle row (L->R): 6, 5, 4
/// Bottom row (L->R): 1, 2, 3
/// ```
///
/// Physical dimensions: 1760mm wide x 1120mm tall.
/// Each zone: ~587mm x 373mm.
///
/// The mapper uses a [HomographyTransform] to convert between camera-space
/// (normalized [0,1] coordinates) and target-space (unit square [0,1]x[0,1]
/// where (0,0) = top-left corner and (1,1) = bottom-right corner).
class TargetZoneMapper {
  final HomographyTransform homography;

  TargetZoneMapper(this.homography);

  /// Zone number layout as a 2D array [row][col], row 0 = top.
  static const List<List<int>> zoneGrid = [
    [7, 8, 9],
    [6, 5, 4],
    [1, 2, 3],
  ];

  /// Given a point in camera-normalized [0,1] space, returns the zone
  /// number (1-9) it falls in, or null if the point is outside the target.
  int? pointToZone(Offset cameraPoint) {
    final target = homography.transform(cameraPoint);

    if (target.dx < 0.0 ||
        target.dx > 1.0 ||
        target.dy < 0.0 ||
        target.dy > 1.0) {
      return null;
    }

    final col = (target.dx * 3.0).floor().clamp(0, 2);
    final row = (target.dy * 3.0).floor().clamp(0, 2);
    return zoneGrid[row][col];
  }

  /// Returns the 4 outer corner points of the target in camera-normalized
  /// [0,1] space. Order: top-left, top-right, bottom-right, bottom-left.
  List<Offset> get outerCorners => [
        homography.inverseTransform(const Offset(0.0, 0.0)),
        homography.inverseTransform(const Offset(1.0, 0.0)),
        homography.inverseTransform(const Offset(1.0, 1.0)),
        homography.inverseTransform(const Offset(0.0, 1.0)),
      ];

  /// Returns the endpoints of the 4 internal grid lines (2 vertical +
  /// 2 horizontal) in camera-normalized [0,1] space.
  ///
  /// Each line is a pair of Offsets: (start, end).
  List<(Offset, Offset)> get gridLines {
    const third = 1.0 / 3.0;
    const twoThirds = 2.0 / 3.0;

    return [
      // Vertical lines (top to bottom).
      (
        homography.inverseTransform(const Offset(third, 0.0)),
        homography.inverseTransform(const Offset(third, 1.0)),
      ),
      (
        homography.inverseTransform(const Offset(twoThirds, 0.0)),
        homography.inverseTransform(const Offset(twoThirds, 1.0)),
      ),
      // Horizontal lines (left to right).
      (
        homography.inverseTransform(const Offset(0.0, third)),
        homography.inverseTransform(const Offset(1.0, third)),
      ),
      (
        homography.inverseTransform(const Offset(0.0, twoThirds)),
        homography.inverseTransform(const Offset(1.0, twoThirds)),
      ),
    ];
  }

  /// Returns the 4 corner points of the given zone in camera-normalized
  /// [0,1] space. Order: top-left, top-right, bottom-right, bottom-left.
  /// Returns null if [zone] is not a valid zone number (1-9).
  List<Offset>? zoneCorners(int zone) {
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        if (zoneGrid[row][col] == zone) {
          return [
            homography.inverseTransform(Offset(col / 3.0, row / 3.0)),
            homography.inverseTransform(Offset((col + 1) / 3.0, row / 3.0)),
            homography
                .inverseTransform(Offset((col + 1) / 3.0, (row + 1) / 3.0)),
            homography.inverseTransform(Offset(col / 3.0, (row + 1) / 3.0)),
          ];
        }
      }
    }
    return null;
  }

  /// Returns the center point of each zone in camera-normalized [0,1]
  /// space, as a Map from zone number to camera-space Offset.
  Map<int, Offset> get zoneCenters {
    final centers = <int, Offset>{};
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final targetCenter = Offset(
          (col + 0.5) / 3.0,
          (row + 0.5) / 3.0,
        );
        centers[zoneGrid[row][col]] =
            homography.inverseTransform(targetCenter);
      }
    }
    return centers;
  }
}
