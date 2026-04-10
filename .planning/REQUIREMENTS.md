# Requirements: Flare Football — Target Zone Impact Detection

**Defined:** 2026-03-09
**Core Value:** Real-time soccer ball detection and tracking must run on-device with acceptable speed and accuracy on both iOS and Android

## v1.3 Requirements

Requirements for target zone impact detection milestone. Each maps to roadmap phases.

### Trajectory Tracking

- [x] **TRAJ-01**: Kalman filter smooths YOLO detections with 4-state model (px, py, vx, vy)
- [ ] **TRAJ-02**: Kalman filter predicts ball position through missed frames (up to ~5 frames)
- [ ] **TRAJ-03**: Ball velocity is tracked per frame and available to impact detection
- [ ] **TRAJ-04**: Parabolic trajectory extrapolated to target plane intersection point

### Impact Detection

- [ ] **IMPACT-01**: Impact detected when ball trajectory intersects calibrated target area
- [ ] **IMPACT-02**: Frame-edge exit filter rejects last detections within 8% of frame edge as misses
- [ ] **IMPACT-03**: Velocity change detection confirms impact (sudden deceleration = real hit)
- [ ] **IMPACT-04**: Impact point mapped to zone 1-9 via homography transform
- [ ] **IMPACT-05**: Miss correctly identified when ball exits frame edge or doesn't intersect target
- [ ] **IMPACT-06**: State machine cycles: Ready -> Tracking -> Result -> Cooldown -> Ready

### Visual Feedback

- [ ] **VISUAL-01**: Detected zone highlights yellow on the calibrated grid overlay
- [ ] **VISUAL-02**: Large zone number displayed as overlay on impact detection
- [ ] **VISUAL-03**: "MISS" text displayed in red when miss is detected
- [ ] **VISUAL-04**: Status text shows current state (Ready / Tracking / Result)
- [ ] **VISUAL-05**: 3-second cooldown auto-resets to Ready state

### Audio Feedback

- [ ] **AUDIO-01**: Number callout (1-9) plays on zone impact
- [ ] **AUDIO-02**: Miss buzzer plays when miss is detected
- [ ] **AUDIO-03**: Audio playback works on both iOS and Android

### Depth Estimation

- [ ] **DEPTH-01**: Ball bounding box area tracked across frames to estimate approach
- [ ] **DEPTH-02**: Distance estimated using known ball size (22cm) + calibration-derived focal length
- [ ] **DEPTH-03**: False impacts filtered when ball depth doesn't reach target distance (+/-0.5m)

## Previous Milestone Requirements (Archived)

### v1.2 — Android Verification (Complete)

- [x] **DIAG-01**: Pre-flight checks pass — aaptOptions, plugin version, model file
- [x] **DIAG-02**: YOLO onResult callback delivers detection results on Galaxy A32
- [x] **DIAG-03**: Android TFLite model returns correct class name strings
- [x] **DIAG-04**: Root cause of onResult silence identified and fixed
- [x] **PRTY-01**: Trail dots and connecting lines accurate on Android
- [x] **PRTY-02**: "Ball lost" badge matches iOS behavior on Android
- [x] **PRTY-03**: Android camera AR confirmed
- [x] **PRTY-04**: Android inference FPS measured and documented

## Future Requirements

Deferred beyond v1.3. Tracked but not in current roadmap.

### Production Upgrades

- **PROD-01**: Automatic CV-based target detection (opencv_dart) — no manual calibration needed
- **PROD-02**: 60fps camera mode for smoother trajectory tracking
- **PROD-03**: Raw frame differencing for additional impact confirmation
- **PROD-04**: ArUco marker-based calibration for precise target registration

### Performance Optimization

- **PERF-01**: Confidence threshold tuning for Android TFLite
- **PERF-02**: Automatic runtime camera AR detection (replace hardcoded constant)
- **PERF-03**: Android-specific ballLostThreshold if FPS difference is problematic

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Automatic target detection (opencv_dart) | ~50MB dependency, lighting-sensitive, deferred to production |
| 60fps camera mode | Requires platform-specific Swift/Kotlin camera code |
| Raw frame differencing | Requires platform camera frame access |
| ArUco markers | Requires opencv_dart + modifying physical target |
| Multi-ball tracking | Single ball is the target use case |
| Re-calibration without restart | Nice-to-have, not core to POC |
| Production UI polish | POC only — not evaluating UI quality |
| SSD MobileNet path work | Frozen since v1.1 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TRAJ-01 | Phase 11 | Pending |
| TRAJ-02 | Phase 11 | Pending |
| TRAJ-03 | Phase 11 | Pending |
| TRAJ-04 | Phase 11 | Pending |
| IMPACT-01 | Phase 12 | Pending |
| IMPACT-02 | Phase 12 | Pending |
| IMPACT-03 | Phase 12 | Pending |
| IMPACT-04 | Phase 12 | Pending |
| IMPACT-05 | Phase 12 | Pending |
| IMPACT-06 | Phase 12 | Pending |
| VISUAL-01 | Phase 12 | Pending |
| VISUAL-02 | Phase 12 | Pending |
| VISUAL-03 | Phase 12 | Pending |
| VISUAL-04 | Phase 12 | Pending |
| VISUAL-05 | Phase 12 | Pending |
| AUDIO-01 | Phase 13 | Pending |
| AUDIO-02 | Phase 13 | Pending |
| AUDIO-03 | Phase 13 | Pending |
| DEPTH-01 | Phase 14 | Pending |
| DEPTH-02 | Phase 14 | Pending |
| DEPTH-03 | Phase 14 | Pending |

**Coverage:**
- v1.3 requirements: 18 total
- Mapped to phases: 18/18
- Unmapped: 0

---
*Requirements defined: 2026-03-09*
*Last updated: 2026-03-09 — roadmap created, traceability populated*
