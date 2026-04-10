# Project Brief

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Project Name
Flare Football -- On-Device Object Detection (Feasibility POC)

## One-Line Summary
A Flutter proof-of-concept application evaluating whether real-time, on-device AI can detect soccer balls (and related objects) from a live camera feed on mobile devices, using a custom-trained YOLO11n model.

## Purpose
This is a **feasibility study**, not a production app. The goal is to determine whether on-device ML inference is accurate enough and fast enough to support a soccer-context detection feature in the Flare Football product. It is not intended for end-users; it exists to answer the question: *"Can we do this well enough, on device, to be worth building into the real product?"*

## Core Research Questions
1. Can YOLO11n (a nano-scale YOLO model) run in real-time on a mobile device without unacceptable latency or battery impact?
2. Is the custom-trained model accurate enough to reliably detect soccer balls (and related objects) in real-world pitch/game conditions?
3. Does the Flutter + `ultralytics_yolo` integration work seamlessly on both Android (TFLite) and iOS (Core ML) with acceptable performance parity?
4. Is landscape-mode camera orientation suitable for the detection use case?

## Scope
**In scope:**
- Live camera feed object detection using YOLO11n
- Android + iOS dual-platform support
- Ball position trail overlay with motion tracking
- "Ball lost" visual indicator

**Out of scope:**
- Production UI/UX polish
- User accounts, auth, or data persistence
- Uploading or storing detection results
- Video recording or playback
- Any backend server-side inference
- Static image analysis (removed with SSD cleanup)

## Success Criteria
- YOLO11n runs at an acceptable frame rate in real-time on both Android and iOS
- Detections for `Soccer ball`, `ball`, and `tennis-ball` are consistently accurate
- No crashes or critical failures on representative target devices
- The integration architecture is sound enough to carry forward into the real Flare Football product

## Project Status
**COMPLETE -- All research questions answered positively.** The POC demonstrates that YOLO11n real-time soccer ball detection is viable on both iOS and Android. The codebase has been cleaned to YOLO-only (SSD/MobileNet legacy code fully removed on 2026-03-05). The `DETECTOR_BACKEND` switching infrastructure is preserved for future extensibility.

## Repository
Local Flutter project (no git / no GitHub by developer decision). Model binary files (`yolo11n.tflite`, `yolo11n.mlpackage`) must be placed manually on the developer machine.
