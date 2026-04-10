import 'package:flutter_test/flutter_test.dart';
import 'package:tensorflow_demo/services/kalman_filter.dart';

void main() {
  group('BallKalmanFilter', () {
    // -------------------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------------------

    test('isInitialized is false before first update', () {
      final filter = BallKalmanFilter();
      expect(filter.isInitialized, isFalse);
    });

    test('first update initializes position from measurement', () {
      final filter = BallKalmanFilter();
      filter.update(0.5, 0.5);
      expect(filter.isInitialized, isTrue);
      final (:px, :py) = filter.position;
      expect(px, closeTo(0.5, 1e-6));
      expect(py, closeTo(0.5, 1e-6));
    });

    test('first update initializes velocity to zero', () {
      final filter = BallKalmanFilter();
      filter.update(0.3, 0.7);
      final (:vx, :vy) = filter.velocity;
      expect(vx, closeTo(0.0, 1e-6));
      expect(vy, closeTo(0.0, 1e-6));
    });

    test('predict when uninitialized is a safe no-op', () {
      final filter = BallKalmanFilter();
      expect(() => filter.predict(), returnsNormally);
      expect(filter.isInitialized, isFalse);
    });

    // -------------------------------------------------------------------------
    // Predict step
    // -------------------------------------------------------------------------

    test('predict advances position by velocity', () {
      // Alternate predict/update to establish a constant-velocity trajectory.
      // We give the filter a clear constant-velocity trajectory: px increases
      // by 0.1 each frame. After convergence, predict() should advance px.
      final filter = BallKalmanFilter(
        processNoise: 0.0001,
        measurementNoise: 0.0001, // very low noise -> filter trusts measurements
      );
      // First measurement to initialize.
      filter.update(0.1, 0.5);
      // Subsequent frames: predict then update at next position.
      for (int i = 1; i <= 5; i++) {
        filter.predict();
        filter.update(0.1 + i * 0.1, 0.5);
      }
      // Filter should now have velocity close to 0.1 in x, 0 in y.
      final (:vx, :vy) = filter.velocity;
      expect(vx, greaterThan(0.0));
      expect(vy, closeTo(0.0, 0.05));

      final positionBeforePredict = filter.position;
      filter.predict();
      final positionAfterPredict = filter.position;

      // x position should advance by ~vx.
      expect(
        positionAfterPredict.px,
        greaterThan(positionBeforePredict.px),
      );
    });

    test('multiple predict calls accumulate position correctly', () {
      final filter = BallKalmanFilter(
        processNoise: 0.0001,
        measurementNoise: 0.0001,
      );
      // Build velocity ~0.1/frame in x direction using predict/update cycle.
      filter.update(0.1, 0.5);
      for (int i = 1; i <= 5; i++) {
        filter.predict();
        filter.update(0.1 + i * 0.1, 0.5);
      }
      final positionAfterUpdates = filter.position;

      // 5 consecutive predicts should advance position further each time.
      double lastPx = positionAfterUpdates.px;
      for (int i = 0; i < 5; i++) {
        filter.predict();
        final (:px, :py) = filter.position;
        expect(px, greaterThan(lastPx));
        lastPx = px;
      }
    });

    // -------------------------------------------------------------------------
    // Update step (correction)
    // -------------------------------------------------------------------------

    test('update after predict pulls position toward measurement', () {
      final filter = BallKalmanFilter(
        processNoise: 0.01,
        measurementNoise: 0.01,
      );
      // Initialize at (0.5, 0.5).
      filter.update(0.5, 0.5);

      // Predict forward (no velocity, so position stays near 0.5).
      filter.predict();

      // Give a measurement far from current position.
      final positionBeforeUpdate = filter.position;
      filter.update(0.9, 0.9);
      final positionAfterUpdate = filter.position;

      // After update, position should be pulled toward (0.9, 0.9).
      expect(
        positionAfterUpdate.px,
        greaterThan(positionBeforeUpdate.px),
      );
      expect(
        positionAfterUpdate.py,
        greaterThan(positionBeforeUpdate.py),
      );
    });

    test('update does not teleport to measurement -- smooths instead', () {
      // High measurement noise -> filter trusts prediction more.
      final filter = BallKalmanFilter(
        processNoise: 0.0001,
        measurementNoise: 0.5,
      );
      filter.update(0.5, 0.5);
      filter.predict();
      filter.update(0.9, 0.9);
      final (:px, :py) = filter.position;

      // Position should be between prior (0.5) and measurement (0.9).
      expect(px, greaterThan(0.5));
      expect(px, lessThan(0.9));
      expect(py, greaterThan(0.5));
      expect(py, lessThan(0.9));
    });

    // -------------------------------------------------------------------------
    // Position smoothing
    // -------------------------------------------------------------------------

    test('filter smooths noisy measurements -- output jitter < input jitter', () {
      // Generate a constant-position signal with added Gaussian-like noise.
      // The filter should produce less variance than raw input.
      final filter = BallKalmanFilter(
        processNoise: 0.0001,
        measurementNoise: 0.005,
      );

      // Simulated noisy measurements around (0.5, 0.5).
      final noisyX = [
        0.52, 0.48, 0.51, 0.49, 0.53, 0.47, 0.50, 0.52, 0.48, 0.51,
      ];
      final noisyY = [
        0.49, 0.51, 0.50, 0.52, 0.48, 0.51, 0.49, 0.50, 0.53, 0.47,
      ];

      final filteredX = <double>[];
      final filteredY = <double>[];
      for (int i = 0; i < noisyX.length; i++) {
        filter.predict();
        filter.update(noisyX[i], noisyY[i]);
        final (:px, :py) = filter.position;
        filteredX.add(px);
        filteredY.add(py);
      }

      // Compute variance of raw inputs vs filtered outputs.
      double variance(List<double> vals) {
        final mean = vals.reduce((a, b) => a + b) / vals.length;
        return vals.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            vals.length;
      }

      final rawVarX = variance(noisyX);
      final filteredVarX = variance(filteredX);
      final rawVarY = variance(noisyY);
      final filteredVarY = variance(filteredY);

      expect(filteredVarX, lessThan(rawVarX));
      expect(filteredVarY, lessThan(rawVarY));
    });

    // -------------------------------------------------------------------------
    // Velocity estimation
    // -------------------------------------------------------------------------

    test('velocity converges for constant-velocity motion', () {
      final filter = BallKalmanFilter(
        processNoise: 0.0001,
        measurementNoise: 0.0001,
      );

      // Constant velocity: px increases by 0.05 each frame.
      // Use predict/update cycle so the filter can estimate velocity.
      filter.update(0.1, 0.5);
      for (int i = 1; i < 10; i++) {
        filter.predict();
        filter.update(0.1 + i * 0.05, 0.5);
      }

      final (:vx, :vy) = filter.velocity;
      // After 10 observations of constant 0.05/frame velocity, filter should
      // converge close to 0.05.
      expect(vx, closeTo(0.05, 0.02));
      expect(vy, closeTo(0.0, 0.02));
    });

    // -------------------------------------------------------------------------
    // Reset
    // -------------------------------------------------------------------------

    test('reset clears isInitialized', () {
      final filter = BallKalmanFilter();
      filter.update(0.5, 0.5);
      expect(filter.isInitialized, isTrue);
      filter.reset();
      expect(filter.isInitialized, isFalse);
    });

    test('reset clears position and velocity to zero', () {
      final filter = BallKalmanFilter();
      filter.update(0.7, 0.3);
      filter.reset();
      final (:px, :py) = filter.position;
      final (:vx, :vy) = filter.velocity;
      expect(px, closeTo(0.0, 1e-12));
      expect(py, closeTo(0.0, 1e-12));
      expect(vx, closeTo(0.0, 1e-12));
      expect(vy, closeTo(0.0, 1e-12));
    });

    test('predict after reset is still a safe no-op', () {
      final filter = BallKalmanFilter();
      filter.update(0.5, 0.5);
      filter.reset();
      expect(() => filter.predict(), returnsNormally);
      expect(filter.isInitialized, isFalse);
    });

    test('re-initialize after reset works correctly', () {
      final filter = BallKalmanFilter();
      filter.update(0.5, 0.5);
      filter.reset();
      filter.update(0.2, 0.8);
      expect(filter.isInitialized, isTrue);
      final (:px, :py) = filter.position;
      expect(px, closeTo(0.2, 1e-6));
      expect(py, closeTo(0.8, 1e-6));
    });

    // -------------------------------------------------------------------------
    // Custom noise parameters
    // -------------------------------------------------------------------------

    test('constructor accepts custom processNoise and measurementNoise', () {
      expect(
        () => BallKalmanFilter(processNoise: 0.001, measurementNoise: 0.01),
        returnsNormally,
      );
    });

    test('high measurementNoise causes filter to weight prediction more', () {
      // With very high measurement noise, a single measurement should barely
      // move the position from the prior prediction.
      final filter = BallKalmanFilter(
        processNoise: 0.0001,
        measurementNoise: 10.0, // extreme measurement noise
      );
      filter.update(0.5, 0.5);
      filter.predict();
      filter.update(1.0, 1.0); // drastic measurement change
      final (:px, :py) = filter.position;
      // Should barely move from 0.5 due to high measurement noise.
      expect(px, lessThan(0.6));
      expect(py, lessThan(0.6));
    });
  });
}
