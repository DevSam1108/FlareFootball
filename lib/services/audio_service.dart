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
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:MM:SS.mmm
    switch (event.result) {
      case ImpactResult.hit:
        if (event.zone != null) {
          print('AUDIO-DIAG: impact result=hit zone=${event.zone} ($ts)');
          _player ??= AudioPlayer();
          await _player!.stop();
          await _player!.play(AssetSource('audio/zone_${event.zone}.m4a'));
        }
      case ImpactResult.miss:
        print('AUDIO-DIAG: impact result=miss ($ts)');
        _player ??= AudioPlayer();
        await _player!.stop();
        await _player!.play(AssetSource('audio/miss.m4a'));
      case ImpactResult.noResult:
        print('AUDIO-DIAG: impact result=noResult — silent ($ts)');
        break;
    }
  }

  /// Phase 5 (Anchor Rectangle, 2026-04-23): plays the State 2 tap-prompt
  /// nudge ("Tap the ball to continue"). Wired to the Samantha-TTS asset
  /// `assets/audio/tap_to_continue.m4a`.
  ///
  /// The per-episode counter + timestamp print is retained from the Phase 1
  /// stub because audio playback cannot be verified from screen recordings;
  /// the log line remains the only signal that the 30s grace + 10s repeat
  /// cadence is firing correctly. Counter resets via [resetTapPromptCounter]
  /// at the start of each new State 2 episode so the device log shows
  /// `AUDIO-STUB #1` at the beginning of every fresh waiting cycle.
  Future<void> playTapPrompt() async {
    _tapPromptCallCount++;
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:MM:SS.mmm
    print('AUDIO-STUB #$_tapPromptCallCount: Tap the ball to continue ($ts)');
    _player ??= AudioPlayer();
    await _player!.stop();
    await _player!.play(AssetSource('audio/tap_to_continue.m4a'));
  }

  /// Phase 1 (Anchor Rectangle, 2026-04-19): reset the per-episode tap-prompt
  /// counter. Called from the screen at the start of every new State 2
  /// episode so the counter visibly restarts at #1, signalling "this is a
  /// fresh waiting cycle" to anyone reading the log during verification.
  void resetTapPromptCounter() {
    _tapPromptCallCount = 0;
  }

  /// Phase 5 (Anchor Rectangle, 2026-04-23): plays the return-to-anchor
  /// success announcement ("Ball in position"). Wired to the Samantha-TTS
  /// asset `assets/audio/ball_in_position.m4a`.
  ///
  /// Fired by the screen from its `onResult` per-frame loop via a timestamp-
  /// based 10 s cadence check (see ADR-080). Also gated by `ball.isStatic`
  /// (ADR-082) so a ball rolling through the rect does not trigger. A
  /// minimal `print` is retained here because audio playback cannot be
  /// verified from screen recordings; the log line is the only signal that
  /// the cadence is firing on-device.
  Future<void> playBallInPosition() async {
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:MM:SS.mmm
    print('AUDIO-DIAG: ball_in_position fired ($ts)');
    _player ??= AudioPlayer();
    await _player!.stop();
    await _player!.play(AssetSource('audio/ball_in_position.m4a'));
  }

  /// Plays the "multiple objects detected at the kick spot" prompt.
  /// Fired by the screen during waiting state when more than one detection
  /// survives the anchor filter (i.e., 2+ objects inside the anchor rect).
  /// Asks the player to clear the spot and keep only the soccer ball.
  /// Cadence is enforced by the caller (10 s minimum between repeats).
  /// 2026-04-29 — added alongside the multi-object cleanup nudge.
  Future<void> playMultipleObjects() async {
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:MM:SS.mmm
    print('AUDIO-DIAG: multiple_objects fired ($ts)');
    _player ??= AudioPlayer();
    await _player!.stop();
    await _player!.play(AssetSource('audio/multiple_objects.m4a'));
  }

  /// Release the underlying audio player resources.
  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
