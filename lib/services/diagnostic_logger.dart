import 'dart:io';

import 'package:flutter/painting.dart' show Offset;
import 'package:path_provider/path_provider.dart';

/// Writes per-frame and per-decision diagnostic data to a CSV file
/// in the app's documents directory for off-device analysis.
///
/// Session lifecycle:
///   await DiagnosticLogger.instance.start();   // begin session
///   DiagnosticLogger.instance.logFrame(...);   // called each live frame
///   DiagnosticLogger.instance.logDecision(...) // called on each impact decision
///   final path = await DiagnosticLogger.instance.stop(); // flush & close
///
/// The file is named flare_diag_YYYYMMDD_HHMMSS.csv and placed in the app's
/// Documents directory. On iOS this is accessible via Files app or AirDrop.
/// On Android it is accessible via the device file manager.
class DiagnosticLogger {
  static final DiagnosticLogger instance = DiagnosticLogger._();
  DiagnosticLogger._();

  IOSink? _sink;
  String? _filePath;
  bool _active = false;

  bool get isActive => _active;
  String? get filePath => _filePath;

  /// Opens a new CSV file and writes the header row.
  Future<void> start() async {
    if (_active) return;
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final stamp =
        '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    _filePath = '${dir.path}/flare_diag_$stamp.csv';
    _sink = File(_filePath!).openWrite();
    _sink!.writeln(
      'event_type,timestamp_ms,ball_detected,raw_x,raw_y,bbox_area,'
      'depth_ratio,smoothed_x,smoothed_y,vel_x,vel_y,vel_mag,'
      'phase,direct_zone,extrap_zone,wall_pred_zone,est_depth,'
      'frames_to_wall,kick_confirmed,kick_state,'
      'result,zone,reason',
    );
    _active = true;
  }

  /// Logs one row of per-frame detection state.
  /// Only call when the pipeline is live (post-calibration).
  void logFrame({
    required bool ballDetected,
    Offset? rawPos,
    double? bboxArea,
    double? depthRatio,
    Offset? smoothedPos,
    Offset? velocity,
    required String phase,
    int? directZone,
    int? extrapZone,
    int? wallPredZone,
    double? estDepth,
    int? framesToWall,
    required bool kickConfirmed,
    required String kickState,
  }) {
    if (!_active || _sink == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final velMag = velocity != null ? velocity.distance.toStringAsFixed(6) : '';
    _sink!.writeln([
      'FRAME',
      ts,
      ballDetected ? '1' : '0',
      rawPos?.dx.toStringAsFixed(4) ?? '',
      rawPos?.dy.toStringAsFixed(4) ?? '',
      bboxArea?.toStringAsFixed(6) ?? '',
      depthRatio?.toStringAsFixed(4) ?? '',
      smoothedPos?.dx.toStringAsFixed(4) ?? '',
      smoothedPos?.dy.toStringAsFixed(4) ?? '',
      velocity?.dx.toStringAsFixed(6) ?? '',
      velocity?.dy.toStringAsFixed(6) ?? '',
      velMag,
      phase,
      directZone?.toString() ?? '',
      extrapZone?.toString() ?? '',
      wallPredZone?.toString() ?? '',
      estDepth?.toStringAsFixed(4) ?? '',
      framesToWall?.toString() ?? '',
      kickConfirmed ? '1' : '0',
      kickState,
      '',
      '',
      '',
    ].join(','));
  }

  /// Logs one row for an impact decision event.
  void logDecision({
    required String result,
    int? zone,
    required String reason,
  }) {
    if (!_active || _sink == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    _sink!.writeln([
      'DECISION',
      ts,
      '', '', '', '', '', '', '', '', '', '',
      'result',
      '', '', '', '', '', // direct_zone, extrap_zone, wall_pred_zone, est_depth, frames_to_wall
      '', '', // kick_confirmed, kick_state (empty for DECISION rows)
      result,
      zone?.toString() ?? '',
      reason,
    ].join(','));
  }

  /// Flushes and closes the file. Returns the file path, or null if not active.
  Future<String?> stop() async {
    if (!_active) return _filePath; // return path even if already stopped
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _active = false;
    return _filePath;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
