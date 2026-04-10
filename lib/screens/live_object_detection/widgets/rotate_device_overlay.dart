import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Full-screen overlay that prompts the user to rotate the device to landscape.
///
/// Uses accelerometer data from [sensors_plus] to detect the physical device
/// orientation (since [MediaQuery.orientation] is useless when the UI
/// orientation is locked via [SystemChrome.setPreferredOrientations]).
///
/// Once the device is physically held in landscape for [_debounceDuration],
/// the overlay fades out and invokes [onDismissed]. If the device is already
/// in landscape on the first accelerometer reading, the overlay dismisses
/// immediately (no debounce).
class RotateDeviceOverlay extends StatefulWidget {
  /// Called once after the overlay has fully faded out.
  final VoidCallback onDismissed;

  const RotateDeviceOverlay({super.key, required this.onDismissed});

  @override
  State<RotateDeviceOverlay> createState() => _RotateDeviceOverlayState();
}

class _RotateDeviceOverlayState extends State<RotateDeviceOverlay>
    with SingleTickerProviderStateMixin {
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  /// Timestamp when we first observed a stable landscape reading.
  DateTime? _landscapeStartTime;

  /// Whether the overlay has started its dismiss sequence.
  bool _dismissing = false;

  /// Whether the first accelerometer event has been received.
  bool _firstEvent = true;

  /// Duration the device must be stably in landscape before dismissing.
  static const _debounceDuration = Duration(milliseconds: 500);

  /// Fade-out animation duration.
  static const _fadeDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: _fadeDuration,
      value: 1.0, // start fully visible
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _fadeController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        widget.onDismissed();
      }
    });

    // Listen to accelerometer at ~10 Hz (100ms sampling).
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(_onAccelerometerEvent);
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (_dismissing) return;

    // When phone is in landscape, gravity acts along the X axis.
    // When phone is in portrait, gravity acts along the Y axis.
    final isPhysicallyLandscape = event.x.abs() > event.y.abs();

    // Fast path: if the phone is already landscape on first reading,
    // dismiss immediately without debounce.
    if (_firstEvent && isPhysicallyLandscape) {
      _firstEvent = false;
      _dismiss();
      return;
    }
    _firstEvent = false;

    if (isPhysicallyLandscape) {
      _landscapeStartTime ??= DateTime.now();

      final elapsed = DateTime.now().difference(_landscapeStartTime!);
      if (elapsed >= _debounceDuration) {
        _dismiss();
      }
    } else {
      // Device went back to portrait — reset debounce.
      _landscapeStartTime = null;
    }
  }

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;

    // Cancel accelerometer to save battery.
    _accelSubscription?.cancel();
    _accelSubscription = null;

    // Fade out (1.0 -> 0.0).
    _fadeController.reverse();
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          // Rotate content 90° clockwise so it appears upright when the
          // user is physically holding the phone in portrait (the UI is
          // already locked to landscape by SystemChrome).
          child: Transform.rotate(
            angle: -1.5708, // -90° in radians (-pi/2)
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.screen_rotation,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                const SizedBox(height: 24),
                Text(
                  'Rotate your device\nto landscape',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
