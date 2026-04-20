import 'package:audioplayers/audioplayers.dart';
import 'package:tensorflow_demo/models/impact_event.dart';

/// Singleton audio service for impact result feedback.
///
/// Plays zone number callouts (1-9) on hits and a buzzer on misses.
/// Silent for inconclusive ([ImpactResult.noResult]) results.
///
/// The [AudioPlayer] is created lazily on first playback to avoid
/// triggering platform channels before they are needed.
class AudioService {
  AudioService._();

  static final instance = AudioService._();

  AudioPlayer? _player;

  /// Per-State-2-episode counter for the audio nudge stub. Reset to 0 at the
  /// start of each new awaiting-reference-capture episode (via
  /// [resetTapPromptCounter]) and incremented on every [playTapPrompt] call.
  /// Used purely for on-device verification of the 30s grace + 10s repeat
  /// cadence in Phase 1 of the Anchor Rectangle feature; will be removed
  /// when Phase 5 wires a real audio asset.
  int _tapPromptCallCount = 0;

  /// Play the appropriate audio clip for the given impact result.
  ///
  /// - [ImpactResult.hit]: plays "One" through "Nine" voice clip.
  /// - [ImpactResult.miss]: plays "Miss" voice clip.
  /// - [ImpactResult.noResult]: no audio.
  Future<void> playImpactResult(ImpactEvent event) async {
    switch (event.result) {
      case ImpactResult.hit:
        if (event.zone != null) {
          _player ??= AudioPlayer();
          await _player!.stop();
          await _player!.play(AssetSource('audio/zone_${event.zone}.m4a'));
        }
      case ImpactResult.miss:
        _player ??= AudioPlayer();
        await _player!.stop();
        await _player!.play(AssetSource('audio/miss.m4a'));
      case ImpactResult.noResult:
        break;
    }
  }

  /// Phase 1 (Anchor Rectangle, 2026-04-19) stub for the State 2 tap-prompt
  /// nudge. The asset will be recorded in Phase 5; until then this prints a
  /// diagnostic line so on-device verification can confirm the 30s grace +
  /// 10s repeat cadence by reading the device log.
  ///
  /// Each line includes a per-episode counter (`#1`, `#2`, ...) and an HH:MM:SS
  /// timestamp so the cadence is self-documenting in the log without
  /// needing a wrist watch. Counter resets via [resetTapPromptCounter] at
  /// the start of each new State 2 episode.
  Future<void> playTapPrompt() async {
    // TODO Phase 5: replace with AssetSource('audio/tap_to_continue.m4a').
    _tapPromptCallCount++;
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:MM:SS.mmm
    print('AUDIO-STUB #$_tapPromptCallCount: Tap the ball to continue ($ts)');
  }

  /// Phase 1 (Anchor Rectangle, 2026-04-19): reset the per-episode tap-prompt
  /// counter. Called from the screen at the start of every new State 2
  /// episode so the counter visibly restarts at #1, signalling "this is a
  /// fresh waiting cycle" to anyone reading the log during verification.
  void resetTapPromptCounter() {
    _tapPromptCallCount = 0;
  }

  /// Release the underlying audio player resources.
  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
