# Phase 6: Overlay Foundation - Context

**Gathered:** 2026-02-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove that a custom Flutter overlay renders visibly and correctly above the camera view on both platforms (iPhone 12, Galaxy A32), and that a single debug dot reliably centers on the detected ball in real-time. This is a correctness gate — coordinates must be proven accurate before any trail state is accumulated in Phase 7. Covers both YOLO and SSD detection pipelines independently.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation details are at Claude's discretion for this phase:
- Debug dot appearance (color, size, opacity)
- Whether to show diagnostic text (coordinates, FPS, confidence) on screen
- Whether YOLO and SSD paths produce identical or slightly different visual output
- How to validate coordinate accuracy (visual inspection vs debug logging)
- Error handling approach when detection returns no results

Key constraints from research that must be honored:
- Use `normalizedBox.center` on YOLO path (already 0-1 coordinates)
- Normalize `renderLocation` by `ScreenParams.screenPreviewSize` on SSD path
- Set `showOverlays: false` on YOLOView (verify availability first)
- Add `if (!mounted) return` guard to all detection callbacks
- Wrap overlay in `RepaintBoundary` for rendering isolation

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. This is a technical validation phase; the focus is on correctness, not aesthetics.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 06-overlay-foundation*
*Context gathered: 2026-02-23*
