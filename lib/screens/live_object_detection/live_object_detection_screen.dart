import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:tensorflow_demo/models/impact_event.dart';
import 'package:tensorflow_demo/services/diagnostic_logger.dart';
import 'package:tensorflow_demo/services/impact_detector.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:flutter/material.dart';
import 'package:tensorflow_demo/screens/live_object_detection/widgets/calibration_overlay.dart';
import 'package:tensorflow_demo/screens/live_object_detection/widgets/debug_bbox_overlay.dart';
import 'package:tensorflow_demo/screens/live_object_detection/widgets/rotate_device_overlay.dart';
import 'package:tensorflow_demo/screens/live_object_detection/widgets/trail_overlay.dart';
import 'package:tensorflow_demo/services/audio_service.dart';
import 'package:tensorflow_demo/services/bytetrack_tracker.dart';
import 'package:tensorflow_demo/services/diag_log_file.dart';
import 'package:tensorflow_demo/services/ball_identifier.dart';
import 'package:tensorflow_demo/services/homography_transform.dart';
import 'package:tensorflow_demo/services/target_zone_mapper.dart';
import 'package:tensorflow_demo/services/kick_detector.dart';
import 'package:tensorflow_demo/services/trajectory_extrapolator.dart';
import 'package:tensorflow_demo/services/wall_plane_predictor.dart';
import 'package:tensorflow_demo/utils/canvas_dash_utils.dart';
import 'package:tensorflow_demo/utils/diag_log.dart';
import 'package:tensorflow_demo/utils/yolo_coord_utils.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';


class LiveObjectDetectionScreen extends StatefulWidget {
  const LiveObjectDetectionScreen({super.key});

  @override
  State<LiveObjectDetectionScreen> createState() =>
      _LiveObjectDetectionScreenState();
}

class _LiveObjectDetectionScreenState extends State<LiveObjectDetectionScreen> {
  /// ByteTrack multi-object tracker — assigns persistent IDs to all detections.
  final _byteTracker = ByteTrackTracker();

  /// Identifies which ByteTrack track is the soccer ball.
  final _ballId = BallIdentifier();

  /// Multi-signal impact detector (Phase 3 state machine).
  final _impactDetector = ImpactDetector();

  /// Kick gate — filters real kicks from dribbling/carrying/retrieval noise.
  final _kickDetector = KickDetector();

  /// Parabolic trajectory extrapolator — predicts target intersection from position + velocity.
  TrajectoryExtrapolator? _extrapolator;

  /// Pseudo-3D wall-plane predictor — uses bbox area changes for depth, predicts wall impact zone.
  WallPlanePredictor? _wallPredictor;

  final _shareButtonKey = GlobalKey();

  /// Audio feedback service for impact results (Phase 4).
  final _audioService = AudioService.instance;

  /// Ball-class labels for filtering YOLO detections before ByteTrack.
  static const _ballClassNames = {'Soccer ball', 'ball', 'tennis-ball'};

  // ---------------------------------------------------------------------------
  // Debug: bbox overlay toggle. Set to false to disable completely.
  // ---------------------------------------------------------------------------
  static const _debugBboxOverlay = false;

  // ---------------------------------------------------------------------------
  // Debug: zoom test. Set to 0.0 to disable, or a value like 2.0 to test.
  // ---------------------------------------------------------------------------
  // static const _testZoomLevel = 0.0;
  //
  // /// Key for YOLOView — used to access camera features like zoom.
  // final _yoloViewKey = GlobalKey();

  /// All ball-class tracks from the latest ByteTrack frame (for debug overlay).
  List<TrackedObject> _debugBallClassTracks = const [];

  /// All ball-class tracks (state == tracked) in the latest frame, captured
  /// during the awaiting-reference-capture sub-phase. Each entry is the
  /// trackId + its current normalized bbox. Drives the multi-bbox painter:
  /// every entry gets a red bbox unless its trackId == [_selectedTrackId],
  /// in which case it gets the green selected-bbox treatment.
  List<({int trackId, Rect bbox})> _ballCandidates = const [];

  /// The trackId the player tapped during the awaiting-reference-capture
  /// sub-phase. Null when no selection is active. Cleared automatically when
  /// the underlying track is no longer present in the latest frame
  /// (Decision B-i: selection clears on disappearance).
  int? _selectedTrackId;

  /// Periodic audio nudge timer for State 2 ("Tap the ball you want to use").
  /// Fires once after a 30 s grace period, then every 10 s until the player
  /// taps. Always cancelled on first tap, on State 2 → State 1/3 transitions,
  /// in [dispose], and in [_startCalibration] (Recal-1 full reset).
  Timer? _audioNudgeTimer;

  /// Android display rotation (Surface.ROTATION_*: 0=0°, 1=90°, 3=270°).
  /// Used to correct normalizedBox coordinates for landscape direction.
  /// iOS handles this in the plugin layer; this is Android-only.
  static const _displayChannel = MethodChannel('com.flare/display');
  int _androidDisplayRotation = 1; // default to rotation=1 (landscape-left)

  // ---------------------------------------------------------------------------
  // Calibration state for target zone grid.
  // ---------------------------------------------------------------------------

  /// Whether the app is currently collecting corner taps.
  bool _calibrationMode = false;

  /// Accumulated corner taps in normalized [0,1] space. 0-4 items.
  /// Order: top-left, top-right, bottom-right, bottom-left.
  final List<Offset> _cornerPoints = [];

  /// Homography computed from the 4 corner taps. Null before calibration.
  HomographyTransform? _homography;

  /// Zone mapper initialized from the homography. Null before calibration.
  TargetZoneMapper? _zoneMapper;

  static const _cornerLabels = ['Top-Left', 'Top-Right', 'Bottom-Right', 'Bottom-Left'];

  /// Whether the calibration is in the "reference capture" sub-phase.
  /// True after 4 corners are tapped, waiting for user to place ball and
  /// tap Confirm.
  bool _awaitingReferenceCapture = false;

  /// Latest YOLO-detected ball bbox area during reference capture sub-phase.
  /// Null when no ball is detected in the current frame.
  double? _referenceCandidateBboxArea;

  /// The confirmed reference bbox area for runtime depth filtering.
  double? _referenceBboxArea;

  /// Anchor rectangle in normalized [0,1] coords, computed at lock
  /// (Confirm tap) from the locked ball's bbox: 3× bbox width × 1.5×
  /// bbox height, centered on the locked ball's bbox center. Frozen
  /// after lock — does not follow the ball. Null before lock and after
  /// recalibration. Phase 2 of the Anchor Rectangle feature: drawn as
  /// a magenta dashed overlay; no filtering yet. See ADR-076.
  Rect? _anchorRectNorm;

  /// Phase 3 (Anchor Rectangle): spatial filter state.
  /// When true, raw YOLO detections whose bbox center lies outside
  /// [_anchorRectNorm] are dropped in [_toDetections] before ByteTrack
  /// receives them. Set true at lock, false on kick start, re-armed on
  /// decision or safety timeout. Field unused until Steps 2–5 wire it.
  bool _anchorFilterActive = false;

  /// Phase 3 safety timeout — if a kick is confirmed but no decision
  /// fires within 2 s, this timer re-arms the filter and releases the
  /// session lock so the pipeline recovers from stuck-lock scenarios
  /// (ISSUE-030). Null when no kick is in flight.
  Timer? _safetyTimeoutTimer;

  /// Phase 5 (Anchor Rectangle, 2026-04-23): timestamp of the last
  /// "Ball in position" audio fire. Drives the 5 s repeat cadence from
  /// the `onResult` loop via elapsed-time check. Nulled when the locked
  /// ball leaves the anchor rectangle (or becomes untracked) so the next
  /// re-entry fires immediately on the edge. Null-reset in
  /// [_startCalibration] (Recal-1) and [dispose]. See ADR-080.
  DateTime? _lastBallInPositionAudio;

  /// Last time the "multiple objects detected" audio fired. Used to enforce
  /// a 10 s cadence between repeats when more than one detection survives
  /// the anchor filter during waiting state. Lifecycle mirrors
  /// [_lastBallInPositionAudio]: nulled on re-calibration ([_startCalibration],
  /// Recal-1) and on [dispose]. 2026-04-29 — added alongside the multi-object
  /// cleanup nudge that fires before the ball-in-position check.
  DateTime? _lastMultipleObjectsAudio;

  /// Index of the corner currently being dragged, or null if not dragging.
  int? _draggingCornerIndex;

  /// Hit-test radius in normalized [0,1] space for grabbing a corner (~9% of frame).
  /// Tuned from diagnostic data: kTouchSlop (~18px) shifts onPanStart position
  /// ~0.05-0.08 from the intended corner. 0.04 was too tight on iPhone 12.
  static const _dragHitRadius = 0.09;

  /// Vertical offset in logical pixels for the "offset cursor" pattern.
  /// During drag, the corner marker renders this many pixels ABOVE the
  /// finger, reducing finger occlusion. 15px is a subtle shift that peeks
  /// the hollow ring above the fingertip without causing a jarring jump.
  static const _dragVerticalOffsetPx = 30.0;

  /// Whether to show the rotate-to-landscape overlay.
  bool _showRotateOverlay = true;

  /// Whether the full detection pipeline (tracker, trail, impact) is active.
  /// Only true after calibration + reference capture are both complete.
  bool _pipelineLive = false;

  /// DIAG-FPS: Timestamp of the last onResult callback for FPS measurement.
  DateTime? _lastFrameTime;
  int _frameCount = 0;

  /// Whether camera permission has been granted and the YOLO view can render.
  bool _cameraReady = false;

  /// Accelerometer subscription for tilt indicator during calibration.
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  /// Vertical tilt angle in radians. 0 = phone pointing straight ahead (level).
  /// In landscape, gravity is mostly on X axis; Y/Z decomposition gives tilt.
  double _tiltY = 0.0;

  @override
  void initState() {
    super.initState();

    // Begin per-session on-device log capture. Creates a new timestamped
    // `.log` file in the app's Documents directory and starts buffering
    // every `print()` line. Closed in `dispose()`.
    DiagLogFile.instance.start();

    // YOLO path — YOLOView manages its own camera pipeline.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // On Android, poll the display rotation so we can correct normalizedBox
    // coordinates for the current landscape direction.
    if (Platform.isAndroid) {
      _pollDisplayRotation();
    }
    _requestCameraPermission();

    // Accelerometer for tilt indicator — 10Hz, same rate as RotateDeviceOverlay.
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(_onAccelerometerEvent);
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted) {
      setState(() => _cameraReady = true);
      // // Debug: apply test zoom after camera is ready.
      // if (_testZoomLevel > 0.0) {
      //   Future.delayed(const Duration(milliseconds: 500), () {
      //     if (!mounted) return;
      //     final state = _yoloViewKey.currentState;
      //     if (state != null) {
      //       (state as dynamic).setZoomLevel(_testZoomLevel);
      //     }
      //   });
      // }
    } else {
      // Permission denied — show a message and pop back.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required')),
      );
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------------------
  // YOLO helper: pick highest-confidence ball result from detection list.
  // ---------------------------------------------------------------------------

  /// Convert YOLO results to ByteTrack [Detection] list.
  ///
  /// Filters to ball-class detections only and applies Android coordinate
  /// correction to the full bounding box (not just center).
  List<Detection> _toDetections(List<YOLOResult> results) {
    final detections = <Detection>[];
    // Phase 3 (Anchor Rectangle): per-frame spatial-filter counters used for
    // the DIAG-ANCHOR-FILTER summary log. Only meaningful when the filter is
    // active and the anchor rectangle is set.
    int anchorDropped = 0;
    int anchorPassed = 0;
    final anchorDroppedDetails = <String>[];
    final anchorPassedDetails = <String>[];
    final anchorActive = _anchorFilterActive && _anchorRectNorm != null;

    for (final r in results) {
      if (!_ballClassNames.contains(r.className)) continue;

      // Reject elongated bboxes (torso/limb false positives).
      // Real ball AR observed max ~1.5; threshold at 1.8 gives margin.
      final rawBbox = r.normalizedBox;
      if (rawBbox.height > 0) {
        final ar = rawBbox.width / rawBbox.height;
        if (ar > 1.8) continue;
      }

      var bbox = rawBbox;
      // Android coordinate correction: flip entire bbox for rotation=3.
      if (Platform.isAndroid && _androidDisplayRotation == 3) {
        bbox = Rect.fromLTRB(
          1.0 - bbox.right,
          1.0 - bbox.bottom,
          1.0 - bbox.left,
          1.0 - bbox.top,
        );
      }

      // Phase 3: spatial filter — drop detections whose bbox center is
      // outside the anchor rectangle during waiting state. The rectangle is
      // defined in the same (rotation-corrected) coordinate frame as [bbox].
      if (anchorActive && !_anchorRectNorm!.contains(bbox.center)) {
        anchorDropped++;
        anchorDroppedDetails.add(
          '${r.className}@(${bbox.center.dx.toStringAsFixed(3)},'
          '${bbox.center.dy.toStringAsFixed(3)}) '
          'size=(${bbox.width.toStringAsFixed(3)}x${bbox.height.toStringAsFixed(3)}) '
          'conf=${r.confidence.toStringAsFixed(2)}');
        continue;
      }
      if (anchorActive) {
        anchorPassed++;
        anchorPassedDetails.add(
          '${r.className}@(${bbox.center.dx.toStringAsFixed(3)},'
          '${bbox.center.dy.toStringAsFixed(3)}) '
          'size=(${bbox.width.toStringAsFixed(3)}x${bbox.height.toStringAsFixed(3)}) '
          'conf=${r.confidence.toStringAsFixed(2)}');
      }

      detections.add(Detection(
        bbox: bbox,
        confidence: r.confidence,
        className: r.className,
      ));
    }

    // Phase 3: per-frame summary log — only when the filter actually dropped
    // something this frame. Silent on no-drop frames to keep logs readable.
    if (anchorActive) {
      diagLog('DIAG-ANCHOR-FILTER: dropped=$anchorDropped passed=$anchorPassed '
          'rect=${_anchorRectNorm!.left.toStringAsFixed(3)},'
          '${_anchorRectNorm!.top.toStringAsFixed(3)},'
          '${_anchorRectNorm!.right.toStringAsFixed(3)},'
          '${_anchorRectNorm!.bottom.toStringAsFixed(3)} '
          '| passed (inside rect): [${anchorPassedDetails.join(", ")}] '
          '| dropped (outside rect): [${anchorDroppedDetails.join(", ")}]');
    }
    return detections;
  }

  // ---------------------------------------------------------------------------
  // Android display rotation polling.
  // The ultralytics_yolo plugin checks Configuration.ORIENTATION_LANDSCAPE
  // but does NOT distinguish landscape-left from landscape-right. We poll the
  // display rotation via a MethodChannel so the Dart layer can compensate.
  // ---------------------------------------------------------------------------

  Timer? _rotationTimer;

  Future<void> _pollDisplayRotation() async {
    // Initial query.
    await _queryRotation();
    // Poll every 500ms to detect orientation flips.
    _rotationTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _queryRotation(),
    );
  }

  Future<void> _queryRotation() async {
    try {
      final rotation = await _displayChannel.invokeMethod<int>('getRotation');
      if (rotation != null && rotation != _androidDisplayRotation) {
        _androidDisplayRotation = rotation;
      }
    } catch (e) {
      // Silently ignore — channel may not be set up in tests.
    }
  }

  // ---------------------------------------------------------------------------
  // Accelerometer tilt tracking.
  // ---------------------------------------------------------------------------

  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (!mounted) return;
    // In landscape, the phone's X axis has gravity (~9.8 when flat on table).
    // Y axis = left/right tilt, Z axis = forward/backward component.
    // For forward/backward tilt (what matters for aiming):
    // atan2(y, z) gives the tilt angle around the phone's long axis.
    // When phone is held level in landscape: y ≈ 0, z ≈ -9.8 → angle ≈ pi.
    // We normalize so 0 = level (pointing straight ahead).
    final rawAngle = math.atan2(event.y, event.z);
    // Normalize: level landscape = atan2(0, -9.8) = pi. Subtract pi, negate.
    final tilt = -(rawAngle - math.pi);
    // Wrap to [-pi, pi].
    final normalizedTilt = tilt > math.pi ? tilt - 2 * math.pi : tilt;

    // Only update state if change is meaningful (>0.5 degree) to avoid churn.
    if ((normalizedTilt - _tiltY).abs() > 0.009) {
      setState(() => _tiltY = normalizedTilt);
    }
  }

  // ---------------------------------------------------------------------------
  // Calibration methods.
  // ---------------------------------------------------------------------------

  /// Starts calibration mode: clears any previous calibration and begins
  /// collecting corner taps.
  void _startCalibration() {
    setState(() {
      _calibrationMode = true;
      _pipelineLive = false;
      _byteTracker.reset();
      _ballId.reset();
      _cornerPoints.clear();
      _homography = null;
      _zoneMapper = null;
      _impactDetector.forceReset();
      _impactDetector.clearReferenceBboxArea();
      _kickDetector.reset();
      _wallPredictor?.reset();
      _awaitingReferenceCapture = false;
      _referenceCandidateBboxArea = null;
      _referenceBboxArea = null;

      // Phase 1 (Anchor Rectangle, 2026-04-19): Recal-1 — full reset.
      // Clear tap selection + multi-bbox candidates and cancel any pending
      // audio nudge so a fresh calibration starts at State 1 cleanly.
      _ballCandidates = const [];
      _selectedTrackId = null;
      _cancelAudioNudgeTimer();

      // Phase 2 (Anchor Rectangle): clear the anchor rectangle so a fresh
      // calibration starts with no overlay, consistent with Recal-1 full reset.
      _anchorRectNorm = null;

      // Phase 3 (Anchor Rectangle): disarm the spatial filter and cancel
      // any in-flight safety timer so a fresh calibration starts clean.
      _anchorFilterActive = false;
      _safetyTimeoutTimer?.cancel();
      _safetyTimeoutTimer = null;

      // Phase 5 (Anchor Rectangle): clear the ball-in-position audio
      // timestamp so the next lock fires the announcement immediately.
      _lastBallInPositionAudio = null;
      // 2026-04-29: clear the multi-object audio timestamp on the same
      // lifecycle event so the next lock starts with a clean cadence.
      _lastMultipleObjectsAudio = null;
    });
  }

  /// Handles a tap during calibration mode. Converts the canvas pixel
  /// position to normalized [0,1] coordinates and appends to _cornerPoints.
  ///
  /// After the 4th tap, computes the homography and initializes the zone
  /// mapper, then exits calibration mode.
  void _handleCalibrationTap(TapDownDetails details, Size canvasSize) {
    if (!_calibrationMode || _cornerPoints.length >= 4) return;

    final normalized = YoloCoordUtils.fromCanvasPixel(
      details.localPosition,
      canvasSize,
      4.0 / 3.0,
    );

    setState(() {
      _cornerPoints.add(normalized);

      if (_cornerPoints.length == 4) {
        _recomputeHomography();
        // Enter reference capture sub-phase instead of exiting calibration.
        _awaitingReferenceCapture = true;
        _referenceCandidateBboxArea = null;
      }
    });
  }

  /// Recomputes the homography and zone mapper from the current corner points.
  void _recomputeHomography() {
    const dst = [
      Offset(0.0, 0.0), // top-left
      Offset(1.0, 0.0), // top-right
      Offset(1.0, 1.0), // bottom-right
      Offset(0.0, 1.0), // bottom-left
    ];
    _homography = HomographyTransform.fromCorrespondences(_cornerPoints, dst);
    _zoneMapper = TargetZoneMapper(_homography!);

    // Initialize trajectory predictors from calibration data.
    final centroid = Offset(
      _cornerPoints.fold(0.0, (sum, p) => sum + p.dx) / 4,
      _cornerPoints.fold(0.0, (sum, p) => sum + p.dy) / 4,
    );
    _wallPredictor = WallPlanePredictor(opticalCenter: centroid);
    _extrapolator = TrajectoryExtrapolator();

    // Log comprehensive calibration geometry diagnostics.
    _logCalibrationDiagnostics();
  }

  /// Logs comprehensive geometric diagnostics derived from the 4 calibration
  /// corners. This data helps diagnose why results vary between calibrations.
  void _logCalibrationDiagnostics() {
    if (_cornerPoints.length != 4) return;

    final tl = _cornerPoints[0]; // top-left
    final tr = _cornerPoints[1]; // top-right
    final br = _cornerPoints[2]; // bottom-right
    final bl = _cornerPoints[3]; // bottom-left

    // --- Edge lengths (normalized [0,1] space) ---
    final topEdge = (tr - tl).distance;
    final bottomEdge = (br - bl).distance;
    final leftEdge = (bl - tl).distance;
    final rightEdge = (br - tr).distance;

    // --- Diagonal lengths ---
    final diag1 = (br - tl).distance; // TL to BR
    final diag2 = (bl - tr).distance; // TR to BL

    // --- Centroid (center of mass of 4 corners) ---
    final centroidX = (tl.dx + tr.dx + br.dx + bl.dx) / 4;
    final centroidY = (tl.dy + tr.dy + br.dy + bl.dy) / 4;

    // --- Target width & height (avg of parallel edges) ---
    final avgWidth = (topEdge + bottomEdge) / 2;
    final avgHeight = (leftEdge + rightEdge) / 2;

    // --- Aspect ratio (width / height) ---
    // Real target: 1760/1120 = 1.5714
    final aspectRatio = avgHeight > 0 ? avgWidth / avgHeight : 0.0;

    // --- Perspective ratios (indicate camera angle) ---
    // topEdge/bottomEdge: >1 = camera below looking up, <1 = above looking down
    final tbRatio = bottomEdge > 0 ? topEdge / bottomEdge : 0.0;
    // leftEdge/rightEdge: >1 = camera right of center, <1 = camera left
    final lrRatio = rightEdge > 0 ? leftEdge / rightEdge : 0.0;

    // --- Quadrilateral area (Shoelace formula) ---
    final area = 0.5 *
        ((tl.dx * tr.dy - tr.dx * tl.dy) +
            (tr.dx * br.dy - br.dx * tr.dy) +
            (br.dx * bl.dy - bl.dx * br.dy) +
            (bl.dx * tl.dy - tl.dx * bl.dy))
            .abs();

    // --- Target coverage (% of total frame) ---
    // Frame is 1.0 x 1.0 in normalized space, so area IS the fraction.
    final coveragePct = area * 100;

    // --- Centering offset from frame center (0.5, 0.5) ---
    final centerOffsetX = centroidX - 0.5;
    final centerOffsetY = centroidY - 0.5;

    // --- Skew: angle of top edge vs horizontal ---
    final topEdgeAngleDeg =
        math.atan2(tr.dy - tl.dy, tr.dx - tl.dx) * 180 / math.pi;
    final bottomEdgeAngleDeg =
        math.atan2(br.dy - bl.dy, br.dx - bl.dx) * 180 / math.pi;

    // --- Individual corner angles (internal angles of quadrilateral) ---
    double _angleBetween(Offset a, Offset vertex, Offset b) {
      final v1 = Offset(a.dx - vertex.dx, a.dy - vertex.dy);
      final v2 = Offset(b.dx - vertex.dx, b.dy - vertex.dy);
      final dot = v1.dx * v2.dx + v1.dy * v2.dy;
      final cross = v1.dx * v2.dy - v1.dy * v2.dx;
      return math.atan2(cross.abs(), dot) * 180 / math.pi;
    }

    final angleTL = _angleBetween(bl, tl, tr);
    final angleTR = _angleBetween(tl, tr, br);
    final angleBR = _angleBetween(tr, br, bl);
    final angleBL = _angleBetween(br, bl, tl);

    // --- Zone center verification: map each zone center back to camera space ---
    String zoneCentersStr = '';
    if (_homography != null) {
      for (int zone = 1; zone <= 9; zone++) {
        // Compute target-space center for this zone
        final row = TargetZoneMapper.zoneGrid
            .indexWhere((r) => r.contains(zone));
        final col = TargetZoneMapper.zoneGrid[row].indexOf(zone);
        final targetX = (col + 0.5) / 3.0;
        final targetY = (row + 0.5) / 3.0;
        // Map back to camera space
        final camPos = _homography!.inverseTransform(Offset(targetX, targetY));
        zoneCentersStr +=
            '\nflutter: │ zone $zone center -> camera (${camPos.dx.toStringAsFixed(4)}, ${camPos.dy.toStringAsFixed(4)})';
      }
    }

    // --- Homography matrix elements ---
    final matStr = _homography != null
        ? _homography!.matrix.map((e) => e.toStringAsFixed(6)).join(', ')
        : 'null';

    // --- Print comprehensive diagnostic block ---
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:MM:SS.mmm
    print('┌─── CALIBRATION DIAGNOSTICS ───');
    print('│ timestamp=$ts');
    print('│ corners TL=(${tl.dx.toStringAsFixed(4)}, ${tl.dy.toStringAsFixed(4)}) '
        'TR=(${tr.dx.toStringAsFixed(4)}, ${tr.dy.toStringAsFixed(4)}) '
        'BR=(${br.dx.toStringAsFixed(4)}, ${br.dy.toStringAsFixed(4)}) '
        'BL=(${bl.dx.toStringAsFixed(4)}, ${bl.dy.toStringAsFixed(4)})');
    print('│ topEdge=${topEdge.toStringAsFixed(4)} '
        'bottomEdge=${bottomEdge.toStringAsFixed(4)} '
        'leftEdge=${leftEdge.toStringAsFixed(4)} '
        'rightEdge=${rightEdge.toStringAsFixed(4)}');
    print('│ avgWidth=${avgWidth.toStringAsFixed(4)} '
        'avgHeight=${avgHeight.toStringAsFixed(4)} '
        'aspectRatio=${aspectRatio.toStringAsFixed(4)} '
        '(ideal=1.5714)');
    print('│ tbRatio=${tbRatio.toStringAsFixed(4)} '
        'lrRatio=${lrRatio.toStringAsFixed(4)} '
        '(1.0=no perspective)');
    print('│ centroid=(${centroidX.toStringAsFixed(4)}, ${centroidY.toStringAsFixed(4)}) '
        'centerOffset=(${centerOffsetX.toStringAsFixed(4)}, ${centerOffsetY.toStringAsFixed(4)})');
    print('│ area=${area.toStringAsFixed(6)} '
        'coverage=${coveragePct.toStringAsFixed(2)}%');
    print('│ diag1(TL-BR)=${diag1.toStringAsFixed(4)} '
        'diag2(TR-BL)=${diag2.toStringAsFixed(4)} '
        'diagRatio=${(diag2 > 0 ? diag1 / diag2 : 0).toStringAsFixed(4)}');
    print('│ topEdgeAngle=${topEdgeAngleDeg.toStringAsFixed(2)}° '
        'bottomEdgeAngle=${bottomEdgeAngleDeg.toStringAsFixed(2)}°');
    print('│ cornerAngles TL=${angleTL.toStringAsFixed(1)}° '
        'TR=${angleTR.toStringAsFixed(1)}° '
        'BR=${angleBR.toStringAsFixed(1)}° '
        'BL=${angleBL.toStringAsFixed(1)}°');
    print('│ homographyMatrix=[$matStr]');
    print('│ --- Zone centers in camera space ---$zoneCentersStr');
    print('└───────────────────────');
  }

  /// Returns the index of the nearest corner within [_dragHitRadius], or null.
  int? _findNearestCorner(Offset normalizedPosition) {
    double minDist = double.infinity;
    int? nearest;
    for (int i = 0; i < _cornerPoints.length; i++) {
      final dist = (_cornerPoints[i] - normalizedPosition).distance;
      if (dist < minDist) {
        minDist = dist;
        nearest = i;
      }
    }
    return (nearest != null && minDist < _dragHitRadius) ? nearest : null;
  }

  /// Phase 1 (Anchor Rectangle, 2026-04-19): Returns the trackId of the ball
  /// candidate that best matches a tap at [normalizedPosition], or null.
  ///
  /// Tap-2 rule (decisions table row 3):
  ///   1. If the tap lands INSIDE any candidate's bbox, that candidate wins
  ///      (direct hit beats nearest-by-center).
  ///   2. Otherwise, return the candidate whose bbox center is closest to
  ///      the tap, but only if that distance is within [_dragHitRadius].
  ///   3. Otherwise null (no-op).
  ///
  /// Mirrors the structure of [_findNearestCorner] — same single-pass loop,
  /// same radius constant, same null-when-out-of-range contract.
  int? _findNearestBall(Offset normalizedPosition) {
    // Pass 1: direct hit.
    for (final c in _ballCandidates) {
      if (c.bbox.contains(normalizedPosition)) return c.trackId;
    }
    // Pass 2: nearest center within radius.
    double minDist = double.infinity;
    int? nearest;
    for (final c in _ballCandidates) {
      final dist = (c.bbox.center - normalizedPosition).distance;
      if (dist < minDist) {
        minDist = dist;
        nearest = c.trackId;
      }
    }
    return (nearest != null && minDist < _dragHitRadius) ? nearest : null;
  }

  /// Phase 1 (Anchor Rectangle, 2026-04-19): Tap handler for the
  /// awaiting-reference-capture sub-phase. Converts the tap to normalized
  /// coords (same `YoloCoordUtils.fromCanvasPixel` as `_handleCalibrationTap`)
  /// and runs Tap-2 via [_findNearestBall].
  ///
  /// Decision A-i (last-tap-wins): a tap that resolves to any candidate
  /// simply overwrites [_selectedTrackId]. A tap that resolves to nothing
  /// is a no-op — we DO NOT clear an existing selection on an off-target tap
  /// (the player may have been adjusting a corner that the gesture arena
  /// classified as a tap-up).
  void _handleBallTap(TapUpDetails details, Size canvasSize) {
    if (!_awaitingReferenceCapture) return;
    if (_ballCandidates.isEmpty) return;

    final normalized = YoloCoordUtils.fromCanvasPixel(
      details.localPosition,
      canvasSize,
      4.0 / 3.0,
    );
    final hitTrackId = _findNearestBall(normalized);
    if (hitTrackId == null) return;

    setState(() {
      _selectedTrackId = hitTrackId;
      // First tap of this State 2 episode: silence the audio nudge.
      _cancelAudioNudgeTimer();
    });
  }

  /// Phase 1 (Anchor Rectangle, 2026-04-19): Schedule the State 2 tap-prompt
  /// nudge. First fire after a 30 s grace period, then every 10 s until
  /// cancelled (decisions table row 7). Always cancel any previous timer
  /// before starting a new one — guarantees no overlap on rapid State 1↔2
  /// flutters.
  ///
  /// Also resets the per-episode counter in [AudioService] so the device
  /// log shows `AUDIO-STUB #1` at the start of every fresh waiting episode
  /// (helpful for on-device cadence verification while the audio asset is
  /// still a Phase 5 stub).
  void _startAudioNudgeTimer() {
    _cancelAudioNudgeTimer();
    _audioService.resetTapPromptCounter();
    _audioNudgeTimer = Timer(const Duration(seconds: 30), () {
      _audioService.playTapPrompt();
      _audioNudgeTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _audioService.playTapPrompt(),
      );
    });
  }

  /// Phase 1 (Anchor Rectangle, 2026-04-19): Cancel any in-flight audio
  /// nudge timer and clear the field. Safe to call when no timer is active.
  void _cancelAudioNudgeTimer() {
    _audioNudgeTimer?.cancel();
    _audioNudgeTimer = null;
  }

  /// Phase 3: safety timeout callback. Fires when a kick entered
  /// `confirming`/`active` but no decision was made within 2 seconds
  /// (e.g., ISSUE-030 "session lock stuck"). Re-arms the spatial filter
  /// and releases the session lock so the pipeline recovers to a clean
  /// waiting state on its own — no operator intervention required.
  void _onSafetyTimeout() {
    if (!mounted) return;
    diagLog('DIAG-ANCHOR-FILTER: SAFETY TIMEOUT fired — no decision within 2s. '
        'Re-arming filter and releasing session lock.');
    _safetyTimeoutTimer = null;
    if (_anchorRectNorm != null) {
      _anchorFilterActive = true;
    }
    if (_ballId.isSessionLocked) {
      _ballId.deactivateSessionLock();
      _byteTracker.setProtectedTrackId(null);
    }
  }

  /// Called when user taps "Confirm" during reference capture sub-phase.
  /// Captures the player-selected ball's bbox area as the reference and
  /// locks the ByteTrack ball identity onto that specific track.
  ///
  /// Phase 1 (Anchor Rectangle, 2026-04-19): The track is now chosen by the
  /// player via tap-to-select (decisions table row 1: two-step B).
  /// `_referenceCandidateBboxArea` non-null already implies a live selection
  /// (see onResult), so the existing guard remains valid as the
  /// "Confirm enable" signal.
  void _confirmReferenceCapture() {
    if (_referenceCandidateBboxArea == null) return;
    if (_selectedTrackId == null) return;

    // Look up the selected track in the latest ByteTrack frame. If the track
    // disappeared between the last onResult and this Confirm tap (race
    // window), bail out — the next onResult will clear _selectedTrackId
    // (Decision B-i) and the player can re-tap.
    TrackedObject? maybeSelected;
    for (final t in _byteTracker.tracks) {
      if (t.trackId == _selectedTrackId) {
        maybeSelected = t;
        break;
      }
    }
    if (maybeSelected == null) return;
    // Hoist into a final non-nullable local so promotion survives into the
    // setState closure below.
    final TrackedObject selected = maybeSelected;

    // Phase 2 (Anchor Rectangle, ADR-076): look up the locked ball's bbox
    // among the latest candidates and compute the anchor rectangle from it
    // (3.5× bbox width × 1.75× bbox height, centered on bbox center;
    // bumped from 3.0×/1.5× on 2026-04-26 per field tuning — see ADR-077
    // note about bumping when rect is tight for small balls). Done before
    // setState so the new rect is applied atomically.
    Rect? anchorRect;
    for (final c in _ballCandidates) {
      if (c.trackId == _selectedTrackId) {
        anchorRect = Rect.fromCenter(
          center: c.bbox.center,
          width: c.bbox.width * 3.5,
          height: c.bbox.height * 1.75,
        );
        break;
      }
    }

    setState(() {
      _referenceBboxArea = _referenceCandidateBboxArea;
      _impactDetector.setReferenceBboxArea(_referenceBboxArea!);
      _awaitingReferenceCapture = false;
      _calibrationMode = false;
      _pipelineLive = true;
      _anchorRectNorm = anchorRect;
      // Phase 3: arm the spatial filter. Locked ball sits inside the rectangle
      // by construction, so its detections pass naturally from this moment on.
      _anchorFilterActive = anchorRect != null;
      if (anchorRect != null) {
        diagLog('DIAG-ANCHOR-FILTER: ON (locked — anchor rectangle armed, '
            'rect=${anchorRect.left.toStringAsFixed(3)},'
            '${anchorRect.top.toStringAsFixed(3)},'
            '${anchorRect.right.toStringAsFixed(3)},'
            '${anchorRect.bottom.toStringAsFixed(3)})');
      }

      // Lock ByteTrack onto the player-selected track.
      _ballId.setReferenceTrack(selected);

      // Clear Phase 1 reference-capture state — overlays go away, screen
      // returns to the clean post-Confirm view (matches today's behaviour).
      _ballCandidates = const [];
      _selectedTrackId = null;
      _cancelAudioNudgeTimer();

      diagLog('DIAG-BYTETRACK: locked ball trackId=${_ballId.currentBallTrackId} '
          'refBboxArea=${_referenceBboxArea!.toStringAsFixed(6)}');
      // Log full calibration snapshot at pipeline start for diagnostic comparison.
      print('┌─── PIPELINE START ───');
      print('│ refBboxArea=${_referenceBboxArea!.toStringAsFixed(6)}');
      print('│ lockedTrackId=${_ballId.currentBallTrackId}');
      _logCalibrationDiagnostics();
      print('└───────────────────────');
    });
    // 2026-04-30: DiagnosticLogger CSV is unplugged in favor of the new
    // per-session `.log` file written by DiagLogFile (started above in
    // initState). Without this `start()` call, _active stays false so all
    // logFrame/logDecision/stop/filePath calls become natural no-ops and
    // the "Share Log CSV" button hides itself (its visibility is gated on
    // filePath != null). Code is preserved as dead code for now; full
    // removal will happen during a later refactor.
    // DiagnosticLogger.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: !_cameraReady
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        fit: StackFit.expand,
        children: [
          YOLOView(
            // key: _yoloViewKey,
            modelPath: Platform.isIOS ? 'yolo11n' : 'yolo11n.tflite',
            task: YOLOTask.detect,
            // OVLY-03: Suppress native bounding box overlays so only
            // our custom debug dot renders.
            showOverlays: false,
            // Lower from plugin default (0.5) to recover small/marginal
            // ball detections during mid-flight. ByteTrack's two-pass
            // matching handles low-confidence detections via pass 2.
            confidenceThreshold: 0.25,
            onResult: (results) {
              // OVLY-04: Guard against setState-after-dispose.
              if (!mounted) return;

              // DIAG-FPS: Measure actual inference FPS.
              final now = DateTime.now();
              _frameCount++;
              if (_lastFrameTime != null) {
                final ms = now.difference(_lastFrameTime!).inMilliseconds;
                if (_frameCount % 30 == 0) {
                  diagLog('DIAG-FPS: ${(1000 / ms).toStringAsFixed(1)} fps (${ms}ms interval) [frame $_frameCount]');
                }
              }
              _lastFrameTime = now;

              // ---- ByteTrack pipeline ----
              // 1. Convert YOLO results to Detection list (class filter + Android coord correction).
              final detections = _toDetections(results);

              // 2. Run ByteTrack tracker — assigns/maintains persistent track IDs.
              // Pass locked ball track ID so Mahalanobis fallback only applies to it.
              final tracks = _byteTracker.update(
                detections,
                lockedTrackId: _ballId.currentBallTrackId,
                lastMeasuredBallArea: _ballId.lastBallBboxArea,
              );

              setState(() {
                // 3. Reference capture (Phase 1, 2026-04-19):
                //    - Collect ALL ball-class tracked candidates (not just largest)
                //    - Run aliveness check on the player's tap selection (B-i)
                //    - Drive Confirm-button enable via _referenceCandidateBboxArea
                //      (kept as the single source of truth for the existing
                //       enable condition; no downstream consumer changes).
                //    - Manage State 1↔State 2 audio nudge timer transitions.
                if (_awaitingReferenceCapture) {
                  final hadCandidates = _ballCandidates.isNotEmpty;
                  final hadSelection = _selectedTrackId != null;

                  final ballTracks = tracks
                      .where((t) =>
                          _ballClassNames.contains(t.className) &&
                          t.state == TrackState.tracked)
                      .toList();

                  _ballCandidates = [
                    for (final t in ballTracks)
                      (trackId: t.trackId, bbox: t.bbox),
                  ];

                  // Aliveness check (Decision B-i): if the previously tapped
                  // track is no longer present, clear selection.
                  if (_selectedTrackId != null &&
                      !_ballCandidates
                          .any((c) => c.trackId == _selectedTrackId)) {
                    _selectedTrackId = null;
                  }

                  // _referenceCandidateBboxArea drives both the prompt text
                  // colour and the Confirm-button enable. With Phase 1 it
                  // mirrors the SELECTED track's bbox area (not the largest).
                  if (_selectedTrackId != null) {
                    final selected = ballTracks.firstWhere(
                      (t) => t.trackId == _selectedTrackId,
                    );
                    _referenceCandidateBboxArea = selected.bboxArea;
                  } else {
                    _referenceCandidateBboxArea = null;
                  }

                  // Audio nudge timer transitions (all mutually exclusive):
                  //   1→2: candidates appeared → start 30 s grace.
                  //   2→1: candidates disappeared → cancel.
                  //   3→2: aliveness check just cleared the tap selection
                  //        while candidates remain → restart grace so the
                  //        player gets reminded again if they don't re-tap.
                  final hasCandidates = _ballCandidates.isNotEmpty;
                  if (!hadCandidates && hasCandidates) {
                    _startAudioNudgeTimer();
                  } else if (hadCandidates && !hasCandidates) {
                    _cancelAudioNudgeTimer();
                  } else if (hadSelection &&
                      _selectedTrackId == null &&
                      hasCandidates) {
                    _startAudioNudgeTimer();
                  }
                }

                // 4. Live pipeline: identify the ball and feed downstream.
                if (_pipelineLive) {
                  _ballId.updateFromTracks(tracks);

                  // Debug: collect all ball-class tracks for bbox overlay.
                  if (_debugBboxOverlay) {
                    _debugBallClassTracks = tracks
                        .where((t) => _ballClassNames.contains(t.className))
                        .toList();
                  }

                  final ball = _ballId.currentBallTrack;
                  final ballDetected = ball != null && ball.state == TrackState.tracked;
                  final rawPosition = ball?.center;
                  final bboxArea = ball?.bboxArea;
                  final velocity = _ballId.velocity;

                  // Phase 5 (Anchor Rectangle, ADR-080) waiting-state audio
                  // prompts. Combined into a single priority-gated block
                  // 2026-04-29:
                  //
                  //   Priority 1 — multi-object cleanup nudge (NEW).
                  //   If more than one detection survived the anchor filter
                  //   (i.e., 2+ objects inside the anchor rect), prompt the
                  //   player to clear the spot. 10 s cadence. Fires for both
                  //   genuinely separate objects (ball + cone) and dual-class
                  //   misclassifications of a single object (e.g., a cone
                  //   firing as both Soccer ball and tennis-ball at the same
                  //   coordinates) — the player-facing action is identical
                  //   in both cases: remove extras until only the soccer
                  //   ball remains.
                  //
                  //   Priority 2 — "Ball in position" announcement (UNCHANGED).
                  //   Only checked when at most one detection is in the rect
                  //   (i.e., the multi-object branch did not fire). Fires
                  //   immediately on the edge where the locked ball is
                  //   tracked inside the anchor rectangle AND verified
                  //   stationary (isStatic), then repeats every 10 s while
                  //   that state persists. When the ball leaves the
                  //   rectangle, becomes untracked, or starts moving, the
                  //   timestamp nulls so the next re-stabilisation fires
                  //   immediately. The `ball.isStatic` gate (ADR-082,
                  //   2026-04-24) prevents false fires when a ball rolls
                  //   through the rect without stopping — isStatic is
                  //   ByteTrack's sliding-30-frame staticness flag, so this
                  //   waits ~1 s after the ball settles before announcing.
                  //
                  // Note: the `else { _lastBallInPositionAudio = null; }`
                  // branch in priority 2 is the ISSUE-036 cadence-reset bug
                  // (single-frame YOLO miss resets the 10 s cooldown).
                  // Deliberately preserved here — ISSUE-036 is tracked
                  // separately and will be fixed in its own change.
                  // 2026-04-29: Multi-object check DISABLED — suspected of
                  // dropping valid kicks during field testing. The
                  // priority-1 branch below now never executes; control
                  // always falls through to the else branch, which contains
                  // the byte-identical original ball-in-position logic.
                  // To re-enable, restore the original condition on the
                  // next line:
                  //     _anchorFilterActive && _anchorRectNorm != null && detections.length > 1
                  if (false) {
                    // Priority 1: multiple objects in rect.
                    final now = DateTime.now();
                    if (_lastMultipleObjectsAudio == null ||
                        now.difference(_lastMultipleObjectsAudio!) >=
                            const Duration(seconds: 10)) {
                      _audioService.playMultipleObjects();
                      _lastMultipleObjectsAudio = now;
                    }
                  } else {
                    // Priority 2: ball-in-position (existing logic, untouched).
                    final inPosition = ballDetected &&
                        _anchorRectNorm != null &&
                        _anchorRectNorm!.contains(ball.center) &&
                        ball.isStatic;
                    if (inPosition) {
                      final now = DateTime.now();
                      if (_lastBallInPositionAudio == null ||
                          now.difference(_lastBallInPositionAudio!) >=
                              const Duration(seconds: 10)) {
                        _audioService.playBallInPosition();
                        _lastBallInPositionAudio = now;
                      }
                    } else {
                      _lastBallInPositionAudio = null;
                    }
                  }

                  // Compute directZone from ball position through homography.
                  final directZone = rawPosition != null && _zoneMapper != null
                      ? _zoneMapper!.pointToZone(rawPosition)
                      : null;

                  // 5. KickDetector: tracks whether a real kick is in progress.
                  _kickDetector.processFrame(
                    ballDetected: ballDetected,
                    velocity: velocity,
                    ballPosition: rawPosition,
                    goalCenter: _goalCenter,
                    isImpactTracking:
                        _impactDetector.phase == DetectionPhase.tracking,
                  );

                  // 5b. Session lock: activate when kick starts to prevent
                  // BallIdentifier from re-acquiring to false positives.
                  if (_kickDetector.isKickActive &&
                      !_ballId.isSessionLocked) {
                    _ballId.activateSessionLock();
                    _byteTracker.setProtectedTrackId(
                        _ballId.currentBallTrackId);
                  }

                  // Phase 3: spatial filter OFF-trigger. The instant the kick
                  // enters confirming (or active, if we missed the confirming
                  // frame), drop the rectangle filter so the in-flight ball
                  // can be tracked anywhere on screen. Start the 2s safety
                  // timer so the pipeline self-recovers if no decision fires.
                  if (_anchorFilterActive &&
                      (_kickDetector.state == KickState.confirming ||
                          _kickDetector.isKickActive)) {
                    _anchorFilterActive = false;
                    _safetyTimeoutTimer?.cancel();
                    _safetyTimeoutTimer = Timer(
                      const Duration(seconds: 2),
                      _onSafetyTimeout,
                    );
                    diagLog('DIAG-ANCHOR-FILTER: OFF (kick state=${_kickDetector.state.name}) — 2s safety timer armed');
                  } else if (!_anchorFilterActive &&
                             _safetyTimeoutTimer != null &&
                             _kickDetector.state == KickState.idle) {
                    _anchorFilterActive = true;
                    _safetyTimeoutTimer?.cancel();
                    _safetyTimeoutTimer = null;
                    _ballId.deactivateSessionLock();
                    _byteTracker.setProtectedTrackId(null);
                    diagLog('DIAG-ANCHOR-FILTER: ON (kick returned to idle — false-alarm recovery)');
                  }

                  // 6. Trajectory prediction signals.
                  ExtrapolationResult? extrapolation;
                  if (rawPosition != null && velocity != null &&
                      _zoneMapper != null && _extrapolator != null) {
                    extrapolation = _extrapolator!.extrapolate(
                      position: rawPosition,
                      velocity: velocity,
                      zoneMapper: _zoneMapper!,
                    );
                  }

                  int? wallPredictedZone;
                  if (rawPosition != null && bboxArea != null &&
                      _referenceBboxArea != null && _referenceBboxArea! > 0 &&
                      _wallPredictor != null && _zoneMapper != null) {
                    _wallPredictor!.addObservation(
                      cameraPosition: rawPosition,
                      bboxArea: bboxArea,
                      referenceArea: _referenceBboxArea!,
                    );
                    wallPredictedZone =
                        _wallPredictor!.predictWallZone(_zoneMapper!)?.zone;
                  }

                  // 7. ImpactDetector: process every frame.
                  final prevPhase = _impactDetector.phase;
                  _impactDetector.processFrame(
                    ballDetected: ballDetected,
                    velocity: velocity,
                    extrapolation: extrapolation,
                    rawPosition: rawPosition,
                    bboxArea: bboxArea,
                    directZone: directZone,
                    wallPredictedZone: wallPredictedZone,
                    // Piece A (2026-04-29): pass current KickDetector state so
                    // ImpactDetector can gate phantom decisions at the source
                    // instead of the audio kick gate catching them downstream.
                    kickState: _kickDetector.state,
                  );

                  // DIAG: Per-frame tracking during active tracking.
                  if (_impactDetector.phase == DetectionPhase.tracking) {
                    diagLog('DIAG-BYTETRACK: trackId=${ball?.trackId} '
                        'directZone=$directZone '
                        'bboxArea=${bboxArea?.toStringAsFixed(6)} '
                        'vel=(${velocity?.dx.toStringAsFixed(4)}, ${velocity?.dy.toStringAsFixed(4)}) '
                        'sizeVel=(${ball?.sizeVelocity.dx.toStringAsFixed(5)}, ${ball?.sizeVelocity.dy.toStringAsFixed(5)}) '
                        'sizeVelMag=${ball?.sizeVelocity.distance.toStringAsFixed(5)} '
                        'kick=${_kickDetector.state.name} '
                        'raw=(${rawPosition?.dx.toStringAsFixed(3)}, '
                        '${rawPosition?.dy.toStringAsFixed(3)}) '
                        'isStatic=${ball?.isStatic}');
                  }

                  // 7. Result gate: only accept results during confirmed kicks.
                  if (prevPhase != DetectionPhase.result &&
                      _impactDetector.phase == DetectionPhase.result &&
                      _impactDetector.currentResult != null) {
                    print('│ kickState: ${_kickDetector.state.name}');
                    print('│ ballConfidence: ${ball?.confidence.toStringAsFixed(4) ?? "null"}');
                    print('└───────────────────────');
                    if (_kickDetector.isKickActive ||
                        _kickDetector.state == KickState.confirming) {
                      // ACCEPT: real kick → play audio, log decision.
                      _audioService
                          .playImpactResult(_impactDetector.currentResult!);
                      _kickDetector.onKickComplete();
                      _wallPredictor?.reset();
                      _ballId.deactivateSessionLock();
                      _byteTracker.setProtectedTrackId(null);
                      // Phase 3: re-arm spatial filter on decision fired.
                      _safetyTimeoutTimer?.cancel();
                      _safetyTimeoutTimer = null;
                      if (_anchorRectNorm != null) {
                        _anchorFilterActive = true;
                        diagLog('DIAG-ANCHOR-FILTER: ON (decision fired — accepted)');
                      }

                      // Log the impact decision.
                      final event = _impactDetector.currentResult!;
                      final String resultStr;
                      final String reason;
                      final int? zone;
                      switch (event.result) {
                        case ImpactResult.hit:
                          resultStr = 'HIT';
                          zone = event.zone;
                          reason = event.targetPoint != null
                              ? 'extrapolation'
                              : 'direct_zone';
                        case ImpactResult.miss:
                          resultStr = 'MISS';
                          zone = null;
                          reason = 'miss';
                        case ImpactResult.noResult:
                          resultStr = 'noResult';
                          zone = null;
                          reason = 'no_signal';
                      }
                      DiagnosticLogger.instance.logDecision(
                        result: resultStr,
                        zone: zone,
                        reason: reason,
                      );
                    } else {
                      // REJECT: not a real kick → discard silently.
                      final ts = DateTime.now().toIso8601String().substring(11, 23);
                      diagLog('DIAG-AUDIO: impact REJECTED by kick gate (kickState=${_kickDetector.state.name}) ($ts)');
                      _impactDetector.forceReset();
                      _wallPredictor?.reset();
                      _ballId.deactivateSessionLock();
                      _byteTracker.setProtectedTrackId(null);
                      // Phase 3: re-arm spatial filter on decision rejected.
                      _safetyTimeoutTimer?.cancel();
                      _safetyTimeoutTimer = null;
                      if (_anchorRectNorm != null) {
                        _anchorFilterActive = true;
                        diagLog('DIAG-ANCHOR-FILTER: ON (decision fired — rejected)');
                      }
                    }
                  }

                  // Log per-frame pipeline state for off-device analysis.
                  final depthRatio = (bboxArea != null &&
                          _referenceBboxArea != null &&
                          _referenceBboxArea! > 0)
                      ? bboxArea / _referenceBboxArea!
                      : null;
                  DiagnosticLogger.instance.logFrame(
                    ballDetected: ballDetected,
                    rawPos: rawPosition,
                    bboxArea: bboxArea,
                    depthRatio: depthRatio,
                    smoothedPos: _ballId.smoothedPosition,
                    velocity: velocity,
                    phase: _impactDetector.phase.name,
                    directZone: directZone,
                    extrapZone: null,
                    wallPredZone: null,
                    estDepth: null,
                    framesToWall: null,
                    kickConfirmed: _kickDetector.isKickActive,
                    kickState: _kickDetector.state.name,
                    trackId: ball?.trackId,
                    isStatic: ball?.isStatic,
                    confidence: ball?.confidence,
                    bboxW: ball?.bbox.width,
                    bboxH: ball?.bbox.height,
                    sessionLocked: _ballId.isSessionLocked,
                  );
                }
              });
            },
          ),

          // Calibration overlay: center crosshair, tilt indicator, corner
          // markers, green grid, and offset feedback.
          RepaintBoundary(
            child: IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: CalibrationOverlay(
                  cornerPoints: _cornerPoints,
                  zoneMapper: _zoneMapper,
                  highlightZone:
                      _impactDetector.phase == DetectionPhase.result &&
                              _impactDetector.currentResult?.result ==
                                  ImpactResult.hit
                          ? _impactDetector.currentResult!.zone
                          : null,
                  activeCornerIndex: _draggingCornerIndex,
                  showCenterCrosshair: _calibrationMode || _zoneMapper == null,
                  tiltY: _tiltY,
                ),
              ),
            ),
            ),

          // RNDR-04: RepaintBoundary wraps CustomPaint for rendering isolation.
          RepaintBoundary(
            child: IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: TrailOverlay(
                  trail: (_kickDetector.state == KickState.idle &&
                          !(_anchorFilterActive &&
                              _anchorRectNorm != null &&
                              _ballId.currentBallTrack != null &&
                              _anchorRectNorm!
                                  .contains(_ballId.currentBallTrack!.center)))
                      ? const []
                      : _ballId.trail,
                  trailWindow: const Duration(seconds: 1, milliseconds: 500),
                ),
              ),
            ),
          ),

          // Debug: bounding box overlay for all ball-class detections.
          if (_debugBboxOverlay)
            RepaintBoundary(
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: DebugBboxOverlay(
                    ballClassTracks: _debugBallClassTracks,
                    lockedTrackId: _ballId.currentBallTrackId,
                  ),
                ),
              ),
            ),

          // Share Log button — visible once a session has started.
          if (DiagnosticLogger.instance.filePath != null)
            Positioned(
              top: 60,
              left: 12,
              child: GestureDetector(
                onTap: _shareLog,
                child: Container(
                  key: _shareButtonKey,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.share, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Share Log',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // "Ball lost" badge — PLSH-01.
          // Hidden during impact result display to avoid overlapping status.
          if (_ballId.isBallLost &&
              (_zoneMapper == null ||
                  _impactDetector.phase != DetectionPhase.result))
            Positioned(
              top: 12,
              right: 12,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Ball lost',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

          // Large result overlay — centered zone number or MISS text.
          // TEMPORARILY COMMENTED OUT for testing — obscures grid view.
          // Audio + bottom-right badge still announce the result.
          // if (_zoneMapper != null &&
          //     _impactDetector.phase == DetectionPhase.result &&
          //     _impactDetector.currentResult != null)
          //   Center(
          //     child: IgnorePointer(
          //       child: Container(
          //         padding: const EdgeInsets.symmetric(
          //             horizontal: 32, vertical: 20),
          //         decoration: BoxDecoration(
          //           color: Colors.black.withValues(alpha: 0.7),
          //           borderRadius: BorderRadius.circular(20),
          //         ),
          //         child: Text(
          //           _impactDetector.currentResult!.result == ImpactResult.hit
          //               ? '${_impactDetector.currentResult!.zone}'
          //               : _impactDetector.currentResult!.result ==
          //                       ImpactResult.miss
          //                   ? 'MISS'
          //                   : '\u2014',
          //           style: TextStyle(
          //             color: _impactDetector.currentResult!.result ==
          //                     ImpactResult.miss
          //                 ? Colors.red
          //                 : Colors.white,
          //             fontSize: 72,
          //             fontWeight: FontWeight.bold,
          //           ),
          //         ),
          //       ),
          //     ),
          //   ),

          // Status text — shows detection phase when calibrated.
          // Positioned bottom-right to avoid blocking the camera view.
          if (_zoneMapper != null && !_calibrationMode)
            Positioned(
              bottom: 16,
              right: 16,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _impactDetector.statusText,
                    style: TextStyle(
                      color: _impactDetector.phase ==
                                  DetectionPhase.result &&
                              _impactDetector.currentResult?.result ==
                                  ImpactResult.miss
                          ? Colors.red
                          : _impactDetector.phase ==
                                      DetectionPhase.result &&
                                  _impactDetector.currentResult?.result ==
                                      ImpactResult.hit
                              ? Colors.greenAccent
                              : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

          // Touch handler for calibration taps.
          // Only present while collecting corner taps (not during reference capture).
          if (_calibrationMode && !_awaitingReferenceCapture)
            LayoutBuilder(
              builder: (context, constraints) {
                final canvasSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) =>
                      _handleCalibrationTap(details, canvasSize),
                  child: const SizedBox.expand(),
                );
              },
            ),

          // Calibration instruction text.
          // Positioned bottom-right to avoid blocking the camera view.
          if (_calibrationMode)
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  // Phase 1 (Anchor Rectangle, 2026-04-19): three reference-
                  // capture states (decisions table rows 4-6):
                  //   State 1 — no candidates: S1-a "Place ball at kick…"
                  //   State 2 — candidates, none selected: "Tap the ball…"
                  //   State 3 — selection live: "Tap Confirm to proceed…"
                  // Outside the awaiting sub-phase, the calibration text is
                  // unchanged.
                  _awaitingReferenceCapture
                      ? (_ballCandidates.isEmpty
                          ? 'Place ball at kick position, keep it in camera view.'
                          : (_selectedTrackId != null &&
                                  _referenceCandidateBboxArea != null
                              ? 'Tap Confirm to proceed with selected ball.'
                              : 'Tap the ball you want to use'))
                      : 'Tap corner ${_cornerPoints.length + 1} of 4: '
                          '${_cornerLabels[_cornerPoints.length]}',
                  style: TextStyle(
                    color: _awaitingReferenceCapture &&
                            _selectedTrackId != null &&
                            _referenceCandidateBboxArea != null
                        ? Colors.greenAccent
                        : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // Draggable calibration corners during reference capture sub-phase.
          // User can drag any corner to fine-tune position before confirming.
          if (_awaitingReferenceCapture)
            LayoutBuilder(
              builder: (context, constraints) {
                final canvasSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // Phase 1 (Anchor Rectangle, 2026-04-19): Gesture-1 —
                  // trust Flutter's gesture arena. onTapUp + onPanStart
                  // coexist on the same detector. Tap-up without movement
                  // = ball select; movement = corner drag.
                  onTapUp: (details) => _handleBallTap(details, canvasSize),
                  onPanStart: (details) {
                    final normalized = YoloCoordUtils.fromCanvasPixel(
                      details.localPosition,
                      canvasSize,
                      4.0 / 3.0,
                    );
                    final index = _findNearestCorner(normalized);
                    if (index != null) {
                      setState(() => _draggingCornerIndex = index);
                    }
                  },
                  onPanUpdate: (details) {
                    if (_draggingCornerIndex == null) return;
                    final normalized = YoloCoordUtils.fromCanvasPixel(
                      details.localPosition,
                      canvasSize,
                      4.0 / 3.0,
                    );
                    // Offset cursor: render corner 60px above finger to avoid
                    // finger occlusion. Convert pixel offset to normalized space.
                    final offsetNorm =
                        _dragVerticalOffsetPx / canvasSize.height;
                    final offsetPosition = Offset(
                      normalized.dx,
                      (normalized.dy - offsetNorm).clamp(0.0, 1.0),
                    );
                    setState(() {
                      _cornerPoints[_draggingCornerIndex!] = offsetPosition;
                      _recomputeHomography();
                    });
                  },
                  onPanEnd: (_) {
                    setState(() => _draggingCornerIndex = null);
                  },
                  child: const SizedBox.expand(),
                );
              },
            ),

          // Red/green bounding boxes around all ball candidates during
          // reference capture. Each candidate is red unless it is the
          // player-tapped selection, which is green. Lets the player verify
          // which ball is currently selected before tapping Confirm.
          //
          // IgnorePointer keeps tap events flowing to the underlying
          // GestureDetector (corner drag + ball tap).
          if (_awaitingReferenceCapture && _ballCandidates.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final canvasSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return IgnorePointer(
                  child: CustomPaint(
                    size: canvasSize,
                    painter: _ReferenceBboxPainter(
                      bboxes: [
                        for (final c in _ballCandidates)
                          (
                            bbox: c.bbox,
                            isSelected: c.trackId == _selectedTrackId,
                          ),
                      ],
                      cameraAspectRatio: 4.0 / 3.0,
                    ),
                  ),
                );
              },
            ),

          // Anchor rectangle — drawn after lock (Confirm tap) and persists
          // until recalibration or screen exit. Phase 2 of the Anchor
          // Rectangle feature: visual only, no filtering (see ADR-076).
          // IgnorePointer so taps always pass through to underlying handlers.
          if (_anchorRectNorm != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final canvasSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return IgnorePointer(
                  child: CustomPaint(
                    size: canvasSize,
                    painter: _AnchorRectanglePainter(
                      rectNorm: _anchorRectNorm!,
                      cameraAspectRatio: 4.0 / 3.0,
                    ),
                  ),
                );
              },
            ),

          // "Confirm" button for reference capture sub-phase.
          if (_awaitingReferenceCapture)
            Positioned(
              bottom: 16,
              left: 16,
              child: ElevatedButton.icon(
                onPressed: _referenceCandidateBboxArea != null
                    ? _confirmReferenceCapture
                    : null,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Confirm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withValues(alpha: 0.85),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.black26,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
              ),
            ),

          // Calibrate / Re-calibrate button.
          if (!_awaitingReferenceCapture)
            Positioned(
            bottom: 48,
            left: 16,
            child: ElevatedButton.icon(
              onPressed: _calibrationMode ? null : _startCalibration,
              icon: const Icon(Icons.crop_free, size: 18),
              label: Text(
                _zoneMapper != null ? 'Re-calibrate' : 'Calibrate',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.black26,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),
            ),
          ),

          // Back button badge.
          //
          // Z-order note (2026-04-19): Rendered AFTER both full-screen
          // GestureDetectors (calibration corner-tap collector at line ~1171
          // and the awaiting-reference-capture detector at line ~1232) so
          // that the gesture arena resolves taps in the badge area to this
          // button instead of the underlying full-screen handlers. Without
          // this ordering, taps on the badge during calibration / awaiting
          // sub-phase were consumed by the full-screen detectors (which
          // wins arena ties as the later-registered widget) — back was
          // unreachable AND a phantom corner was placed under the badge.
          // Sits below the rotate overlay (which is intentionally topmost).
          Positioned(
            top: 12,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),

          // Rotate-to-landscape overlay (topmost layer).
          // Blocks all interaction until device is physically in landscape.
          if (_showRotateOverlay)
            RotateDeviceOverlay(
              onDismissed: () {
                if (mounted) {
                  setState(() => _showRotateOverlay = false);
                }
              },
            ),
        ],
      ),
    );
  }

  /// Goal center in camera-normalized space (inverse-homography of target center).
  Offset? get _goalCenter {
    if (_homography == null) return null;
    return _homography!.inverseTransform(const Offset(0.5, 0.5));
  }

  Future<void> _shareLog() async {
    final path = await DiagnosticLogger.instance.stop();
    if (path == null) return;
    final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;
    await Share.shareXFiles(
      [XFile(path)],
      subject: 'Flare Diagnostic Log',
      sharePositionOrigin: origin,
    );
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _accelSubscription?.cancel();
    // Phase 1 (Anchor Rectangle, 2026-04-19): cancel the audio nudge timer
    // so a stale Timer cannot survive hot-reload / screen pop and fire
    // playTapPrompt against a disposed AudioService.
    _cancelAudioNudgeTimer();
    // Phase 3 (Anchor Rectangle): cancel the safety timer so it cannot fire
    // against a disposed state after the screen is popped.
    _safetyTimeoutTimer?.cancel();
    _safetyTimeoutTimer = null;
    // Phase 5 (Anchor Rectangle): clear the ball-in-position timestamp.
    _lastBallInPositionAudio = null;
    // 2026-04-29: clear the multi-object timestamp on dispose too.
    _lastMultipleObjectsAudio = null;
    _byteTracker.reset();
    _ballId.reset();
    _impactDetector.forceReset();
    _kickDetector.reset();
    _audioService.dispose();
    DiagnosticLogger.instance.stop();
    // Close per-session on-device log file. Flushes any buffered lines and
    // releases the file handle. Pairs with `DiagLogFile.instance.start()`
    // in `initState`.
    DiagLogFile.instance.stop();

    // Restore orientations for the rest of the app.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    super.dispose();
  }
}

/// Paints bounding boxes around reference ball candidates during the
/// awaiting-reference-capture sub-phase. Each entry is rendered red unless
/// it is the player-selected entry, which is rendered green.
///
/// Phase 1 (Anchor Rectangle, 2026-04-19): extended from a single-bbox
/// painter to a list-of-bboxes painter to support multi-ball display +
/// tap-to-select. Same `YoloCoordUtils.toCanvasPixel` conversion and same
/// stroke style (2.5 px) as the prior single-bbox painter — only the loop
/// + per-item colour pick are new.
class _ReferenceBboxPainter extends CustomPainter {
  /// Each entry: a bbox in normalized [0,1] coords + whether it is the
  /// currently selected candidate (green) or unselected (red).
  final List<({Rect bbox, bool isSelected})> bboxes;
  final double cameraAspectRatio;

  // Reused colour constants — red matches the previous single-bbox painter
  // colour so unselected appearance is unchanged. Green matches the
  // greenAccent used by the prompt text + Confirm button when the user is
  // ready to commit, keeping the visual language consistent.
  static const _redStroke = Color(0xFFFF0000);
  static const _greenStroke = Color(0xFF00E676); // Colors.greenAccent[400]

  _ReferenceBboxPainter({
    required this.bboxes,
    required this.cameraAspectRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (final entry in bboxes) {
      final topLeft = YoloCoordUtils.toCanvasPixel(
        Offset(entry.bbox.left, entry.bbox.top),
        size,
        cameraAspectRatio,
      );
      final bottomRight = YoloCoordUtils.toCanvasPixel(
        Offset(entry.bbox.right, entry.bbox.bottom),
        size,
        cameraAspectRatio,
      );
      paint.color = entry.isSelected ? _greenStroke : _redStroke;
      canvas.drawRect(
        Rect.fromPoints(topLeft, bottomRight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReferenceBboxPainter oldDelegate) {
    if (bboxes.length != oldDelegate.bboxes.length) return true;
    for (int i = 0; i < bboxes.length; i++) {
      if (bboxes[i].bbox != oldDelegate.bboxes[i].bbox ||
          bboxes[i].isSelected != oldDelegate.bboxes[i].isSelected) {
        return true;
      }
    }
    return false;
  }
}

/// Paints the anchor rectangle as a magenta, dashed, 2 px stroke with no
/// fill. The rectangle is provided in normalized [0,1] coords and
/// converted to canvas pixels via [YoloCoordUtils.toCanvasPixel] (same
/// transform used by every other overlay on this screen).
///
/// Phase 2 of the Anchor Rectangle feature: visual only, no filtering.
/// See ADR-076 for the design decisions (bbox-relative sizing, frozen
/// center, screen-axis-aligned, magenta dashed).
class _AnchorRectanglePainter extends CustomPainter {
  /// Anchor rectangle in normalized [0,1] space.
  final Rect rectNorm;
  final double cameraAspectRatio;

  static const _magentaStroke = Color(0xFFFF00FF);

  _AnchorRectanglePainter({
    required this.rectNorm,
    required this.cameraAspectRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final topLeft = YoloCoordUtils.toCanvasPixel(
      Offset(rectNorm.left, rectNorm.top),
      size,
      cameraAspectRatio,
    );
    final bottomRight = YoloCoordUtils.toCanvasPixel(
      Offset(rectNorm.right, rectNorm.bottom),
      size,
      cameraAspectRatio,
    );
    final topRight = Offset(bottomRight.dx, topLeft.dy);
    final bottomLeft = Offset(topLeft.dx, bottomRight.dy);

    final paint = Paint()
      ..color = _magentaStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 4 dashed edges — shared helper keeps dash math identical to the
    // calibration center crosshair.
    drawDashedLine(canvas, topLeft, topRight, paint);
    drawDashedLine(canvas, topRight, bottomRight, paint);
    drawDashedLine(canvas, bottomRight, bottomLeft, paint);
    drawDashedLine(canvas, bottomLeft, topLeft, paint);
  }

  @override
  bool shouldRepaint(covariant _AnchorRectanglePainter oldDelegate) {
    return rectNorm != oldDelegate.rectNorm ||
        cameraAspectRatio != oldDelegate.cameraAspectRatio;
  }
}
