import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/models/impact_event.dart';
import 'package:tensorflow_demo/services/audio_service.dart';

void main() {
  group('AudioService', () {
    test('singleton identity', () {
      expect(identical(AudioService.instance, AudioService.instance), isTrue);
    });

    test('noResult does not trigger audio player', () async {
      final event = ImpactEvent(
        result: ImpactResult.noResult,
        timestamp: DateTime.now(),
      );
      // noResult is a no-op — no AudioPlayer created, no platform call.
      await AudioService.instance.playImpactResult(event);
    });

    test('hit without zone is silent', () async {
      final event = ImpactEvent(
        result: ImpactResult.hit,
        zone: null,
        timestamp: DateTime.now(),
      );
      // zone guard prevents playback — no AudioPlayer created.
      await AudioService.instance.playImpactResult(event);
    });
  });
}
