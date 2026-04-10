# Phase 8: Polish - Research

**Researched:** 2026-02-24
**Domain:** Flutter overlay widget, BallTracker state exposure, Positioned badge pattern
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PLSH-01 | User can see a "Ball lost" badge overlay when tracking has lost the ball for multiple consecutive frames | Requires: (1) a public `isBallLost` getter on BallTracker, (2) a Positioned badge widget in the YOLO Stack, (3) badge visibility driven by tracker state via setState |

</phase_requirements>

---

## Summary

Phase 8 is a contained, single-concern addition to the existing YOLO live detection screen. The goal is to surface the "ball lost" tracking state to the evaluator via a visible badge overlay. The entire implementation lives inside two existing files: `BallTracker` (add a public getter) and `live_object_detection_screen.dart` (add a conditional `Positioned` widget to the existing YOLO `Stack`).

The `_consecutiveMissedFrames` counter already exists in `BallTracker` and is correctly maintained on every frame — it increments on each `markOccluded()` call and resets on `update()`. However, it is currently private. The screen has no way to read it. The only required structural change is to expose a derived boolean (`isBallLost`) as a public getter on `BallTracker`, keyed on a configurable threshold (e.g., `>= 3` frames). No architectural changes, no new files, no new dependencies.

The badge itself follows the identical pattern as the existing backend label badge already in the YOLO Stack: a `Positioned` widget containing a `Container` with `Colors.black54` background and `BorderRadius.circular(8)`. The badge appears/disappears via the existing `setState` that fires on every YOLO result callback — no additional state management is needed.

**Primary recommendation:** Add `isBallLost` getter to `BallTracker` with a `ballLostThreshold` constant (default 3 frames), then add a conditional `Positioned` badge in the YOLO Stack driven by `_tracker.isBallLost`. Zero new files, zero new dependencies.

---

## Standard Stack

### Core (no new dependencies needed)

| Library | Version | Purpose | Notes |
|---------|---------|---------|-------|
| `flutter/material.dart` | SDK | `Positioned`, `Container`, `Text`, `Colors`, `BorderRadius` | All badge widgets are already in scope — no imports to add |
| `BallTracker` | project | Tracks consecutive missed frames | Needs one new public getter |

### Supporting

No new packages required. The badge is pure Flutter widget composition using types already imported in the screen file.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Public getter on BallTracker | Read `trail` list and infer state from sentinel count | Reading trail is unreliable: sentinels are evicted after `trailWindow`; misses > 30 frames clear the trail entirely. Direct counter is authoritative. |
| Boolean getter `isBallLost` | Integer getter `consecutiveMissedFrames` | Integer exposes internal state unnecessarily; boolean is the only thing the screen needs. Keeps encapsulation clean. |
| Inline threshold in getter | Separate `ballLostThreshold` constant | Named constant is self-documenting and easier to tune without hunting through code. |
| `AnimatedOpacity` / `AnimatedContainer` | Plain `Visibility` or `if` conditional | POC does not need animation polish. Plain conditional is simpler and matches existing backend badge pattern exactly. |
| New widget file for badge | Inline `Positioned` widget in screen | Badge is 10–15 lines. Extracting to a file adds indirection with no benefit at this scale. |

---

## Architecture Patterns

### Recommended Project Structure

No new files required. Changes touch only:

```
lib/
├── services/
│   └── ball_tracker.dart          # Add isBallLost getter + ballLostThreshold constant
└── screens/live_object_detection/
    └── live_object_detection_screen.dart  # Add conditional badge Positioned widget in YOLO Stack
```

### Pattern 1: Public Derived-Boolean Getter on BallTracker

**What:** Expose a computed boolean from the private `_consecutiveMissedFrames` counter.

**When to use:** Any time screen UI needs to know "is ball lost" without exposing the raw counter.

**Example:**

```dart
// In lib/services/ball_tracker.dart

/// Number of consecutive missed frames that triggers the "Ball lost" badge.
/// Must be less than [autoResetThreshold] (30). A value of 3 means the badge
/// appears within ~100ms at 30fps — fast enough for the evaluator to notice.
static const int ballLostThreshold = 3;

/// True when the ball has been missing for [ballLostThreshold] or more
/// consecutive frames. Used by the screen to show the "Ball lost" badge.
/// Resets to false the next time [update] is called (ball re-detected).
bool get isBallLost => _consecutiveMissedFrames >= ballLostThreshold;
```

**Key constraint:** `ballLostThreshold` MUST be less than `autoResetThreshold` (30). If it were equal, the badge would flash only at the instant of reset, which is never visible. Any value from 2–5 frames gives the desired "within a few frames" behaviour at 30fps (67–167ms).

### Pattern 2: Conditional Positioned Badge in YOLO Stack

**What:** Add a `Positioned` widget to the existing YOLO `Stack` that shows/hides based on `_tracker.isBallLost`. The badge appears at a fixed screen position, styled consistently with the existing backend label badge.

**When to use:** Any persistent status indicator that must overlay the camera feed without affecting layout.

**Example:**

```dart
// In _LiveObjectDetectionScreenState.build(), inside the YOLO Stack children list.
// Place AFTER the TrailOverlay RepaintBoundary so it renders on top.

if (_tracker.isBallLost)
  Positioned(
    top: 12,
    right: 12,                     // right side — backend label is top-left
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Ball lost',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  ),
```

**Why `right: 12` not `left: 12`:** The backend label badge already occupies `top: 12, left: 12`. Placing the "Ball lost" badge at `top: 12, right: 12` avoids visual collision and creates a natural left/right split (status | tracking state).

**Why `if (_tracker.isBallLost)` not `Visibility`:** The `if` form in a list literal is idiomatic Flutter; it adds/removes the widget from the tree entirely. `Visibility(visible: ...)` keeps the widget in the tree with zero size, which is fine but unnecessary for a simple badge.

### Pattern 3: No Additional setState Needed

**What:** The badge visibility update piggybacks on the `setState` that already fires in the `onResult` callback.

**Why this works:**

```dart
// Already in onResult:
onResult: (results) {
  if (!mounted) return;
  final ball = _pickBestBallYolo(results);
  setState(() {
    if (ball != null) {
      _tracker.update(...);     // resets _consecutiveMissedFrames → isBallLost becomes false
    } else {
      _tracker.markOccluded();  // increments _consecutiveMissedFrames → isBallLost may become true
    }
  });
},
```

Every YOLO frame fires `onResult`, which calls `setState`. The `build` method reads `_tracker.isBallLost` on every rebuild. The badge appears/disappears automatically within one frame of the threshold being crossed. No polling, no timer, no stream.

### Anti-Patterns to Avoid

- **Reading trail to infer ball-lost state:** The trail is time-windowed and evicts entries. After `autoResetThreshold` (30 frames), the trail is cleared entirely — this means an empty trail does NOT mean "ball lost right now". The `_consecutiveMissedFrames` counter is the authoritative source.
- **Exposing `consecutiveMissedFrames` as int:** The screen only needs a boolean. Exposing the raw integer invites callers to re-implement threshold logic externally, creating two sources of truth.
- **Using a Timer or periodic rebuild:** The badge visibility is already driven by the YOLO result callback. Adding a timer would create redundant rebuilds and complicate lifecycle management.
- **Removing IgnorePointer from the badge:** The badge is a purely informational overlay. It must NOT consume touch events. The badge should be wrapped in `IgnorePointer` (or, since it is a `Positioned` inside a `Stack` above a `YOLOView`, verify that `YOLOView` gesture handling works correctly — in practice the existing `IgnorePointer` that wraps the trail overlay covers the trail layer; the badge is a separate `Positioned` child and will consume taps by default). **The badge must be wrapped in `IgnorePointer` to pass through touches to YOLOView.**
- **Placing badge inside RepaintBoundary with the trail:** The trail `RepaintBoundary` exists to isolate expensive CustomPaint repaints. Adding the badge inside it would cause the RepaintBoundary layer to repaint on every frame, defeating its purpose. The badge is a separate `Positioned` sibling in the Stack, not a child of the trail RepaintBoundary.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Badge show/hide animation | Custom animation controller | Plain `if` conditional | POC requirement says "badge appears/disappears" — no animation specified. Adding AnimatedSwitcher or AnimationController is scope creep. |
| State reactivity | MobX observable on BallTracker | Existing setState in onResult | MobX is scoped to HomeScreen per architecture rules. The detection screen uses setState. The existing setState already fires per frame. |

**Key insight:** This phase adds ~25 lines of code across 2 files. Any approach that adds more complexity than that is over-engineered for a POC polish item.

---

## Common Pitfalls

### Pitfall 1: Threshold at or Above autoResetThreshold

**What goes wrong:** If `ballLostThreshold >= autoResetThreshold (30)`, the badge would only become visible for exactly one frame (the frame the counter reaches 30), then `reset()` clears the counter back to 0. The badge would never appear in practice.

**Why it happens:** The developer sets a "conservative" high threshold to avoid false positives, not realising it collides with the auto-reset.

**How to avoid:** Document in code that `ballLostThreshold` MUST be `< autoResetThreshold`. A value of 2–5 is appropriate. 3 frames ≈ 100ms at 30fps.

**Warning signs:** Badge never visible even when clearly no ball on screen.

### Pitfall 2: Badge Consuming Touch Events

**What goes wrong:** `YOLOView` receives no touch events after the badge appears because the badge's `Container` absorbs them.

**Why it happens:** A `Positioned` widget inside a `Stack` absorbs pointer events by default at its hit-test region. The existing trail overlay is wrapped in `IgnorePointer` (committed decision from Phase 7), but the new badge widget is separate.

**How to avoid:** Wrap the `Positioned` badge in `IgnorePointer`. Since it is informational-only, it should never handle touches.

**Warning signs:** Tap/swipe on the camera area stops working whenever the badge is visible.

### Pitfall 3: Badge Inside Trail RepaintBoundary

**What goes wrong:** Trail CustomPainter repaints on every frame (shouldRepaint always true), defeating the RepaintBoundary.

**Why it happens:** Developer puts the badge inside the `RepaintBoundary` → `IgnorePointer` → `CustomPaint` tree for the trail overlay.

**How to avoid:** The badge is a separate `Positioned` sibling in the Stack, **not** a child of the trail layer. The Stack in the YOLO build has this structure:

```
Stack
├── YOLOView
├── RepaintBoundary (trail layer — existing)
│   └── IgnorePointer
│       └── CustomPaint (TrailOverlay)
├── Positioned (backend label badge — existing, top-left)
└── Positioned (Ball lost badge — new, top-right, wrapped in IgnorePointer)
```

**Warning signs:** Trail layer repaints observed when badge appears/disappears (can be detected with Flutter DevTools repaint rainbow).

### Pitfall 4: Checking trail.isEmpty Instead of isBallLost

**What goes wrong:** Badge triggers when the trail evicts old entries (no ball for >1.5s but trail simply aged out), or fails to trigger because the trail clears at reset and `isEmpty` becomes false again immediately if the ball is found.

**Why it happens:** Developer reads the existing `_tracker.trail.isEmpty` instead of `_tracker.isBallLost`, not realising trail emptiness has multiple causes.

**How to avoid:** Always use the dedicated `isBallLost` getter. It is backed by the authoritative `_consecutiveMissedFrames` counter, not the trail contents.

---

## Code Examples

### Complete BallTracker Addition

```dart
// Source: project analysis — lib/services/ball_tracker.dart

/// Number of consecutive missed frames that triggers the "Ball lost" badge.
/// Must be less than [autoResetThreshold] (30).
/// At 30fps, 3 frames ≈ 100ms — within the "few frames" requirement (PLSH-01).
static const int ballLostThreshold = 3;

/// True when the ball has been missing for [ballLostThreshold] or more
/// consecutive frames (PLSH-01).
/// Returns false as soon as [update] is called (ball re-detected).
bool get isBallLost => _consecutiveMissedFrames >= ballLostThreshold;
```

### Complete Badge Widget (YOLO Stack child)

```dart
// Source: project analysis — live_object_detection_screen.dart, YOLO build branch

// "Ball lost" badge — PLSH-01.
// IgnorePointer: badge must not consume touch events from YOLOView.
if (_tracker.isBallLost)
  IgnorePointer(
    child: Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Ball lost',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  ),
```

**Note on `withValues(alpha:)`:** The existing codebase has already migrated from deprecated `withOpacity()` to `withValues(alpha:)` (confirmed in progress.md). The badge must use `withValues(alpha:)` for consistency and lint compliance.

### Correct Stack Order (YOLO build branch)

```dart
Stack(
  fit: StackFit.expand,
  children: [
    YOLOView(/* ... */),                       // camera layer (bottom)
    RepaintBoundary(                           // trail layer (existing)
      child: IgnorePointer(
        child: CustomPaint(painter: TrailOverlay(...)),
      ),
    ),
    Positioned(                               // backend label (existing, top-left)
      top: 12, left: 12,
      child: Container(/* "YOLO" label */),
    ),
    if (_tracker.isBallLost)                  // ball-lost badge (new, top-right)
      IgnorePointer(
        child: Positioned(
          top: 12, right: 12,
          child: Container(/* "Ball lost" */),
        ),
      ),
  ],
),
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| `withOpacity()` | `withValues(alpha:)` | Already migrated in this codebase — badge must use `withValues` |
| Hard-coded threshold in build | Named constant on BallTracker | Self-documenting; consistent with existing `autoResetThreshold` constant pattern |

---

## Open Questions

1. **Should the threshold be `>= 3` or `> 0` (show on first miss)?**
   - What we know: The requirement says "within a few frames." `> 0` means instant (one-frame miss shows badge), which may be too sensitive for legitimate occlusion during normal play. `>= 3` (~100ms) filters single-frame false negatives.
   - What's unclear: Whether single-frame misses are common in real footage.
   - Recommendation: Use `ballLostThreshold = 3`. It is easily tunable via the constant. The evaluator can observe whether it is too sensitive or too slow and report back.

2. **`IgnorePointer` placement: wrapping `Positioned` or inside it?**
   - What we know: `IgnorePointer` outside `Positioned` means the hit-test area is ignored entirely. `IgnorePointer` inside `Positioned` wrapping the `Container` also works. Both are functionally equivalent.
   - Recommendation: Place `IgnorePointer` **outside** `Positioned` to be consistent with the existing trail overlay pattern (see Phase 7 decision: "IgnorePointer wraps trail CustomPaint").

---

## Sources

### Primary (HIGH confidence)

- Direct code analysis: `lib/services/ball_tracker.dart` — `_consecutiveMissedFrames` is private; `autoResetThreshold = 30` is a named constant; `update()` resets counter; `markOccluded()` increments counter
- Direct code analysis: `lib/screens/live_object_detection/live_object_detection_screen.dart` — YOLO Stack structure, existing backend badge pattern (`Positioned` top-left with `Container`), `setState` in `onResult` callback
- Direct code analysis: `.planning/STATE.md` accumulated decisions — IgnorePointer decision from Phase 7, `withValues(alpha:)` migration, no MobX outside HomeScreen
- Direct code analysis: `memory-bank/activeContext.md` — Phase 8 next steps description, `_tracker.isBallLost` mentioned as basis for badge
- `.planning/REQUIREMENTS.md` — PLSH-01: badge within "a few frames", disappears on re-detection

### Secondary (MEDIUM confidence)

- Flutter documentation pattern: `Positioned` inside `Stack` with `IgnorePointer` is idiomatic for non-interactive overlays — well-established Flutter pattern, consistent with existing project code

### Tertiary (LOW confidence)

- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all types already in scope
- Architecture: HIGH — patterns verified directly in existing production code (backend badge, IgnorePointer, setState, RepaintBoundary structure)
- Pitfalls: HIGH — all pitfalls derived from direct code inspection (private counter, RepaintBoundary structure, touch event handling, trail vs counter semantics)

**Research date:** 2026-02-24
**Valid until:** N/A — this is internal project research against stable code; valid until Phase 8 plan is executed
