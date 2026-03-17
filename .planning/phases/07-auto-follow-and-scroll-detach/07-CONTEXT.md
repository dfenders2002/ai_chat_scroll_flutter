# Phase 7: Auto-Follow and Scroll Detach - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

During streaming the viewport automatically tracks the growing AI response, detaches immediately when the user drags away, and re-attaches when the user returns to the live bottom. This phase wires the streamingFollowing/streamingDetached states from Phase 6 to actual scroll behavior in the view.

</domain>

<decisions>
## Implementation Decisions

### Auto-follow trigger
- View detects first content growth via `ScrollMetricsNotification` (maxScrollExtent increases while in submittedWaitingResponse) — no new public API needed for streaming start detection
- Keep `jumpTo(offset+delta)` compensation but gate it strictly on `streamingFollowing` state — fixes current flickering bug by not compensating during other states
- Filler shrinks dynamically as AI response grows: `filler = viewport - userMsg - aiResponse` until filler reaches 0, then pure scroll compensation takes over

### Detach behavior
- Immediate detach on first drag frame — no pixel threshold, matches Claude app behavior where any touch stops auto-scroll
- Filler freezes at current value on detach — user can scroll freely within existing content+filler bounds, no content jump
- User can re-attach by scrolling back to within `atBottomThreshold` during streaming (not just down-button)

### State transitions in view
- View calls a new internal controller method when it detects content growth to transition submittedWaitingResponse → streamingFollowing — controller owns all transitions
- View calls `controller.onUserScrolled()` (new public method) on drag detect to transition streamingFollowing → streamingDetached
- `scrollToBottom()` during active streaming transitions to streamingFollowing and resumes compensation

### Claude's Discretion
- Internal naming of helper methods in the view
- Whether `onUserScrolled()` is public or package-private
- Exact implementation of filler shrink formula

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_onMetricsChanged()` in view — already compensates scroll, needs gating on state
- `_anchorActive` boolean — to be replaced by state checks
- `_fillerHeight` ValueNotifier — filler isolation pattern stays
- `_anchorKey` GlobalKey + `_measureAndAnchor()` — anchor measurement reusable

### Established Patterns
- `addPostFrameCallback` + `hasClients` guard for all scroll dispatch
- `ValueNotifier<double>` + `ValueListenableBuilder` for filler isolation
- `ScrollUpdateNotification.dragDetails != null` for drag detection
- `ScrollMetricsNotification` for content growth detection
- `_transition()` in controller for all state changes

### Integration Points
- `_onControllerChanged()` listens to controller ChangeNotifier — currently checks `isStreaming`
- `_onMetricsChanged()` — needs to check `scrollState` instead of `_anchorActive`
- `_onScrollChanged()` — needs to trigger re-attach when at bottom during streaming
- `scrollToBottom()` in controller — needs to trigger re-attach during streaming

</code_context>

<specifics>
## Specific Ideas

- User reported flickering in example app during streaming — gating compensation on streamingFollowing state should fix this
- User reported message going off screen on send — multi-frame anchor establishment needs tightening
- Keep it simple — this is a package, minimal API surface
- Test through the example app

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-auto-follow-and-scroll-detach*
*Context gathered: 2026-03-17*
