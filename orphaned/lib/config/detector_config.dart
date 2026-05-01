// lib/config/detector_config.dart

/// Available detection backends.
/// Add new enum values here to support additional backends in the future.
enum DetectorBackend { yolo }

class DetectorConfig {
  static const String _raw =
      String.fromEnvironment('DETECTOR_BACKEND', defaultValue: 'yolo');

  static DetectorBackend get backend {
    switch (_raw.toLowerCase()) {
      case 'yolo':
      default:
        return DetectorBackend.yolo;
    }
  }

  static String get label {
    switch (backend) {
      case DetectorBackend.yolo:
        return 'YOLO';
    }
  }
}
