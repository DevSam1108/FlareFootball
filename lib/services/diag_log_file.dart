import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Per-session diagnostic log file writer.
///
/// Captures every `print()` line emitted by the app while the live detection
/// screen is active and writes it to a timestamped `.log` text file in the
/// app's Documents directory. Used by the zone interceptor installed in
/// `main.dart` so the on-device file is a 1:1 replica of what would appear
/// in the `flutter run` terminal during a debug session.
///
/// Lifecycle:
///   * `start()` — called from `LiveObjectDetectionScreen.initState`. Creates
///     a new file named `diag_<YYYY-MM-DD>_<HH-MM-SS>.log` and begins
///     accepting buffered appends.
///   * `append(line)` — called from the zone interceptor for every `print()`.
///     Appended to an in-memory buffer (cheap), never directly written to
///     disk on the print thread.
///   * `stop()` — called from `LiveObjectDetectionScreen.dispose`. Cancels
///     the timer, flushes any buffered lines, and closes the file.
///
/// A periodic 500 ms timer flushes the buffer to disk in batches to avoid
/// per-print disk I/O during high-volume frames (kicks emit ~30 prints/s).
/// Disposing the screen also forces an immediate final flush so no lines are
/// lost when the user backs out.
class DiagLogFile {
  DiagLogFile._();
  static final DiagLogFile instance = DiagLogFile._();

  /// Periodic flush cadence. Lines accumulated in memory are written to
  /// disk every [_flushInterval]; on a hard crash, at most this much
  /// log data may be lost.
  static const Duration _flushInterval = Duration(milliseconds: 500);

  IOSink? _sink;
  String? _filePath;
  final List<String> _buffer = <String>[];
  Timer? _flushTimer;
  bool _active = false;

  /// True between [start] and [stop]. While inactive, [append] is a no-op.
  bool get isActive => _active;

  /// Absolute path of the current session's log file, or `null` if no
  /// session is active.
  String? get filePath => _filePath;

  /// Opens a new timestamped log file in the Documents directory and starts
  /// the periodic flush timer. Idempotent — calling while already active
  /// is a no-op.
  ///
  /// `_active` is set true synchronously so [append] starts accepting lines
  /// into the in-memory buffer immediately, even while the async file open
  /// is still in flight. The first periodic flush after the sink is ready
  /// drains everything that accumulated during that brief window.
  Future<void> start() async {
    if (_active) return;
    _active = true;
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final stamp = '${now.year}-${_pad(now.month)}-${_pad(now.day)}'
        '_${_pad(now.hour)}-${_pad(now.minute)}-${_pad(now.second)}';
    _filePath = '${dir.path}/diag_$stamp.log';
    _sink = File(_filePath!).openWrite();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  /// Appends [line] to the in-memory buffer. The line is not written to
  /// disk immediately — the periodic timer or [stop] will flush it.
  void append(String line) {
    if (!_active) return;
    _buffer.add(line);
  }

  /// Flushes the buffer, cancels the timer, and closes the file. Returns
  /// the absolute path of the closed file (or `null` if not active).
  Future<String?> stop() async {
    if (!_active) return null;
    _active = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _flush();
    await _sink?.flush();
    await _sink?.close();
    final path = _filePath;
    _sink = null;
    _filePath = null;
    return path;
  }

  void _flush() {
    if (_buffer.isEmpty || _sink == null) return;
    for (final line in _buffer) {
      _sink!.writeln(line);
    }
    _buffer.clear();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
