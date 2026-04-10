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

  /// Release the underlying audio player resources.
  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
