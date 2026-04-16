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
import 'package:tensorflow_demo/services/ball_identifier.dart';
import 'package:tensorflow_demo/services/homography_transform.dart';
import 'package:tensorflow_demo/services/target_zone_mapper.dart';
import 'package:tensorflow_demo/services/kick_detector.dart';
import 'package:tensorflow_demo/services/trajectory_extrapolator.dart';
import 'package:tensorflow_demo/services/wall_plane_predictor.dart';
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

  /// Bounding box of the reference ball candidate during reference capture.
  /// Used to render a red bounding box so the user can verify the correct
  /// object is selected before tapping Confirm.
  Rect? _referenceCandidateBbox;

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

      detections.add(Detection(
        bbox: bbox,
        confidence: r.confidence,
        className: r.className,
      ));
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
      _referenceCandidateBbox = null;
      _referenceBboxArea = null;
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
    print('┌─── CALIBRATION DIAGNOSTICS ───');
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

  /// Called when user taps "Confirm" during reference capture sub-phase.
  /// Captures the currently detected ball's bbox area as the reference
  /// and locks the ByteTrack ball identity.
  void _confirmReferenceCapture() {
    if (_referenceCandidateBboxArea == null) return;
    setState(() {
      _referenceBboxArea = _referenceCandidateBboxArea;
      _impactDetector.setReferenceBboxArea(_referenceBboxArea!);
      _awaitingReferenceCapture = false;
      _calibrationMode = false;
      _pipelineLive = true;

      // Lock ByteTrack onto the ball — picks the largest ball-class track
      // (closest to camera).
      _ballId.setReferenceTrack(_byteTracker.tracks);
      _referenceCandidateBbox = null; // hide red bbox after confirm
      print('DIAG-BYTETRACK: locked ball trackId=${_ballId.currentBallTrackId} '
          'refBboxArea=${_referenceBboxArea!.toStringAsFixed(6)}');
      // Log full calibration snapshot at pipeline start for diagnostic comparison.
      print('┌─── PIPELINE START ───');
      print('│ refBboxArea=${_referenceBboxArea!.toStringAsFixed(6)}');
      print('│ lockedTrackId=${_ballId.currentBallTrackId}');
      _logCalibrationDiagnostics();
      print('│ timestamp=${DateTime.now().toIso8601String()}');
      print('└───────────────────────');
    });
    DiagnosticLogger.instance.start();
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
                  print('DIAG-FPS: ${(1000 / ms).toStringAsFixed(1)} fps (${ms}ms interval) [frame $_frameCount]');
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
                // 3. Reference capture: find largest ball-class track for bbox area.
                if (_awaitingReferenceCapture) {
                  final ballTracks = tracks
                      .where((t) =>
                          _ballClassNames.contains(t.className) &&
                          t.state == TrackState.tracked)
                      .toList();
                  if (ballTracks.isNotEmpty) {
                    ballTracks.sort((a, b) => b.bboxArea.compareTo(a.bboxArea));
                    _referenceCandidateBboxArea = ballTracks.first.bboxArea;
                    _referenceCandidateBbox = ballTracks.first.bbox;
                  } else {
                    _referenceCandidateBboxArea = null;
                    _referenceCandidateBbox = null;
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
                  );

                  // DIAG: Per-frame tracking during active tracking.
                  if (_impactDetector.phase == DetectionPhase.tracking) {
                    print('DIAG-BYTETRACK: trackId=${ball?.trackId} '
                        'directZone=$directZone '
                        'bboxArea=${bboxArea?.toStringAsFixed(6)} '
                        'vel=(${velocity?.dx.toStringAsFixed(4)}, ${velocity?.dy.toStringAsFixed(4)}) '
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
                      _impactDetector.forceReset();
                      _wallPredictor?.reset();
                      _ballId.deactivateSessionLock();
                      _byteTracker.setProtectedTrackId(null);
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
                  trail: _kickDetector.state == KickState.idle
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

          // Back button badge.
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
                  _awaitingReferenceCapture
                      ? (_referenceCandidateBboxArea != null
                          ? 'Ball detected \u2014 tap Confirm'
                          : 'Place ball on target \u2014 point camera at ball')
                      : 'Tap corner ${_cornerPoints.length + 1} of 4: '
                          '${_cornerLabels[_cornerPoints.length]}',
                  style: TextStyle(
                    color: _awaitingReferenceCapture &&
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

          // Red bounding box around the detected ball candidate during
          // reference capture. Lets the user verify the correct object
          // is selected before tapping Confirm.
          if (_awaitingReferenceCapture && _referenceCandidateBbox != null)
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
                      bbox: _referenceCandidateBbox!,
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
    _byteTracker.reset();
    _ballId.reset();
    _impactDetector.forceReset();
    _kickDetector.reset();
    _audioService.dispose();
    DiagnosticLogger.instance.stop();

    // Restore orientations for the rest of the app.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    super.dispose();
  }
}

/// Paints a red bounding box around the reference ball candidate during
/// calibration. Uses [YoloCoordUtils.toCanvasPixel] to convert normalized
/// bbox corners to canvas pixels with FILL_CENTER crop correction.
class _ReferenceBboxPainter extends CustomPainter {
  final Rect bbox;
  final double cameraAspectRatio;

  _ReferenceBboxPainter({
    required this.bbox,
    required this.cameraAspectRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final topLeft = YoloCoordUtils.toCanvasPixel(
      Offset(bbox.left, bbox.top),
      size,
      cameraAspectRatio,
    );
    final bottomRight = YoloCoordUtils.toCanvasPixel(
      Offset(bbox.right, bbox.bottom),
      size,
      cameraAspectRatio,
    );

    final paint = Paint()
      ..color = const Color(0xFFFF0000) // red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawRect(
      Rect.fromPoints(topLeft, bottomRight),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ReferenceBboxPainter oldDelegate) =>
      bbox != oldDelegate.bbox;
}
