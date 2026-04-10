# Product Context

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## The Product: Flare Football
Flare Football is a sports technology product. This object detection POC is being built to evaluate a capability that could be integrated into the broader Flare Football platform -- specifically, the ability to detect soccer-relevant objects (balls) in real time from a user's device camera.

## Why This POC Exists
The Flare Football team wants to know if on-device AI detection is viable before committing engineering resources to building it into the main product. This app is the "try before you build" step. It uses a real custom-trained model (not a toy demo model) to get a truthful signal about accuracy and performance.

## The Problem Being Solved
Soccer/football analysis currently requires either manual tagging or expensive server-side video processing. If on-device detection works well enough, Flare Football could enable features like:
- Real-time ball tracking during matches or training
- Automated highlight detection ("ball touched", "shot taken")
- Player/ball position analytics captured passively on a phone
- Lightweight, offline-capable detection that doesn't require cloud round-trips
- **Target zone impact detection** -- detecting which zone of a numbered goal target the ball hits during shooting practice

## Who Uses This POC
This is an **internal engineering/product feasibility tool**. The "users" are the Flare Football team members evaluating the technology -- developers, product managers, and potentially investors or stakeholders reviewing a demo. It is not intended for end consumers of the Flare Football product.

## Detection Classes
The custom YOLO11n model detects **3 classes**, embedded directly in the model:
| Class | Notes |
|---|---|
| `Soccer ball` | Primary target -- the main object of interest |
| `ball` | General ball detection -- likely also fires on soccer balls depending on context |
| `tennis-ball` | Present from training data; likely incidental but may fire in certain conditions |

The model was trained on a **custom soccer-focused dataset**, distinct from general COCO-class datasets.

## User Experience Goals

### For ball detection (COMPLETE):
1. **Real-time detection** -- ball trail and position tracking live on camera with minimal lag
2. **Accuracy** -- detections fire on real soccer balls with low false-positive rate
3. **Stability** -- no crashes during a typical 5-10 minute demo session
4. **Both platforms** -- evidence that it works on both iOS and Android

### For target zone detection (NEXT):
1. **Zone identification** -- correctly identify which of 9 zones the ball hits (~90% accuracy target)
2. **Audio callout** -- phone speaks the zone number immediately after impact
3. **Visual feedback** -- zone highlights on screen + large number overlay
4. **Miss detection** -- correctly identify when the ball misses the target
5. **False-positive rejection** -- don't report a hit when the ball flies past without hitting

## UI Structure
```
Home Screen (minimal launcher)
+-- Soccer icon + title ("Soccer Ball Detection")
+-- Subtitle ("Real-time YOLO11n on-device detection")
+-- "Start Detection" button -> Live Detection Screen
      +-- YOLOView widget (full-screen landscape camera)
      +-- Trail overlay (fading orange dots + connecting lines)
      +-- "Ball lost" badge (top-right, appears when ball exits frame)
      +-- Back button badge (top-left, circular arrow icon, navigates to home)
      +-- "Calibrate Target" button (bottom-left)
      +-- Green wireframe grid overlay (9 zones, after calibration)
      +-- Zone highlight (yellow glow on hit zone, 3s)
      +-- Large number overlay (centered, 3s)
      +-- Status indicator (bottom-right: "Ready" / "Tracking..." / "MISS")
      +-- Calibration instructions (bottom-right: "Tap corner 1 of 4: Top-Left")
      +-- Audio callout ("You hit one!" + crowd cheer through "You hit nine!" + crowd cheer, or buzzer for miss)
```

## Target Sheet (Physical Product)
- **Dimensions:** 1760mm wide x 1120mm tall
- **Layout:** 3x3 grid of numbered zones with red LED-ringed circles and gold numbers on black background
- **Zone numbering:**
  ```
  Top:    7  8  9
  Middle: 6  5  4
  Bottom: 1  2  3
  ```
- Being manufactured by a factory. For testing, a hand-drawn rectangle with numbers on a wall works identically.

## Setup for Use
1. Phone on a **tripod behind the kicker**, landscape mode, pointing at the goal with target
2. Open app, tap "Start Detection", tap "Calibrate Target"
3. Tap 4 corners of the target on screen
4. Green grid appears. Status: "Ready -- waiting for kick"
5. Kick ball. App tracks, detects impact zone, calls out number.
6. Auto-resets after 3 seconds for next kick.

## Key Product Decisions Already Made
- **YOLO11n was chosen** over larger YOLO variants (11s, 11m, 11l, 11x) deliberately -- nano size prioritizes speed and device compatibility over maximum accuracy
- **Landscape-only orientation** was adopted for the YOLO live detection screen -- this matches how a phone would realistically be held to film a pitch
- **On-device inference only** -- no server calls for detection; fully offline-capable
- **Platform-native model formats** -- TFLite for Android, Core ML (mlpackage) for iOS -- using the most optimised format per platform rather than one cross-platform format
- **SSD/MobileNet path fully removed** -- Legacy code from the base repo was cleaned out on 2026-03-05
- **Unsplash/API layer fully removed** -- Demo scaffolding removed on 2026-03-09
- **Manual calibration for target registration** -- User taps 4 corners. Pure math, no CV dependency, no platform code. Upgrade path: ArUco markers + opencv_dart for auto-detection.
- **Multi-signal impact detection** -- Trajectory + depth + edge-filter + velocity. Rejects false positives where ball flies past without hitting.
- **Pre-composited celebratory audio clips** -- "You hit N!" + crowd cheer for zones 1-9, miss buzzer. Generated via macOS TTS + Pixabay SFX, composited with ffmpeg. Replace with professional recordings for production.

## Comparable Products (from research)
- **myKicks** (iOS): Phone on tripod, ARKit+CoreML, post-processes penalty kicks. 5-7% error.
- **HomeCourt** (basketball): Single phone camera + CoreML, detects shots through hoop. Trajectory analysis.
- **KickerAce** (iOS): Phone camera + neural network, measures penalty kick precision.
- **DribbleUp**: Phone camera CV tracks ball at feet (no sensors in ball).
- All of these prove single-phone-camera ball tracking is commercially viable.

## POC Conclusion (Ball Detection Phase)
The POC has been evaluated and **all core research questions are answered positively**:
- YOLO11n runs in real-time on both iOS and Android
- Detection accuracy is acceptable (Soccer ball at 0.868 confidence)
- The Flutter + ultralytics_yolo integration works on both platforms
- Landscape-mode camera orientation is suitable for the use case
- The architecture is clean and suitable to carry forward into the real product
