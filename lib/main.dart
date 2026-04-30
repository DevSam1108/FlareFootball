import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/diag_log_file.dart';

Future<void> main() async {
  // Wrap the entire app in a zone whose `print` override forwards every line
  // both to the terminal (parent zone) and to the on-device per-session log
  // file (DiagLogFile). The file is created/closed by LiveObjectDetectionScreen
  // and is only written to while a session is active.
  runZonedGuarded(() async {
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
  }, (error, stack) {
    // Forward uncaught errors through the zone's print so they also land in
    // the on-device log file.
    print('UNCAUGHT: $error\n$stack');
  }, zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      parent.print(zone, line);
      DiagLogFile.instance.append(line);
    },
  ));
}
