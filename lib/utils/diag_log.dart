/// Diagnostic logging wrapper.
///
/// Prepends a wall-clock `[HH:MM:SS.mmm]` prefix to every line, then prints
/// to stdout via `print()`. Output is identical to a plain `print` from the
/// terminal's perspective (still appears in `flutter run` console) — only
/// the prefix is added.
///
/// Use for single-line `DIAG-*` diagnostic logs across the app so every line
/// can be cross-referenced with screen recording timestamps. Multi-line
/// boxed blocks (CALIBRATION DIAGNOSTICS, PIPELINE START, IMPACT DECISION)
/// carry their own internal timestamp line and use plain `print` directly.
void diagLog(String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:MM:SS.mmm
  print('[$ts] $msg');
}
