import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/config/detector_config.dart';

void main() {
  group('DetectorConfig', () {
    test('defaults to yolo backend when no env var is set', () {
      expect(DetectorConfig.backend, DetectorBackend.yolo);
    });

    test('label returns YOLO for default backend', () {
      expect(DetectorConfig.label, 'YOLO');
    });

    test('DetectorBackend enum has all expected values', () {
      expect(DetectorBackend.values, containsAll([
        DetectorBackend.yolo,
      ]));
    });
  });
}
