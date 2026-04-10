import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supported values:
  //  - yolo    -> YOLO backend (yolo11n model)
  // Add new backends here in the future.
  const backend = String.fromEnvironment(
    'DETECTOR_BACKEND',
    defaultValue: 'yolo',
  );
  log('DETECTOR_BACKEND = $backend', name: 'main');

  // Initialize the selected backend.
  if (backend == 'yolo') {
    // YOLO backend loads its model when YOLOView is used.
  } else {
    log('Unknown DETECTOR_BACKEND: $backend — falling back to yolo', name: 'main');
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const MyApp());
}
