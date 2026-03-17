# Phase 6: State Machine Foundation - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace boolean flags (`_streaming`, `_anchorActive`) with a formal 5-state enum (`idleAtBottom`, `submittedWaitingResponse`, `streamingFollowing`, `streamingDetached`, `historyBrowsing`) and expose it as a reactive `ValueNotifier<AiChatScrollState>`. All v1.0 tests must pass without modification.

</domain>

<decisions>
## Implementation Decisions

### Rapid-send behavior
- `onUserMessageSent()` transitions to `submittedWaitingResponse` from ANY state — universal rule, no exceptions
- New send always wins: previous AI stream is implicitly abandoned, no "cancel" required
- Late `onResponseComplete()` for an orphaned stream is treated as a normal transition from current state — no response tracking needed
- No tracking of "which" response; state machine only knows current state, not response identity

### Invalid transition handling
- Invalid transitions are silent no-ops — no throw, no assert, no log
- If state didn't change, don't notify listeners (ValueNotifier deduplication is sufficient)
- `onResponseComplete()` from `submittedWaitingResponse` is VALID — covers API errors, empty responses, timeouts. Transitions to `idleAtBottom` (at bottom) or `historyBrowsing` (scrolled away)

### Claude's Discretion
- Backward compatibility strategy for `isStreaming` getter (keep as derived, deprecate, or remove)
- State exposure depth — just `ValueNotifier<AiChatScrollState>` or additional APIs (previous state, transition callbacks)
- Keep it simple — this is a package, minimal API surface preferred
- Internal implementation details (transition method structure, private helpers)

</decisions>

<specifics>
## Specific Ideas

- User wants to test through the example app — keep implementation simple and testable
- "THIS IS A PACKAGE NEEDS TO BE SIMPLE" — minimal API surface, don't over-engineer the state machine
- Match Claude iOS/Android app behavior for rapid-send (new send always wins)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ValueNotifier<bool> _isAtBottom` — pattern for reactive state exposure already established in controller
- `ChangeNotifier` base class on `AiChatScrollController` — listeners pattern in place

### Established Patterns
- `addPostFrameCallback` + `hasClients` guard for all scroll dispatch
- `notifyListeners()` used to signal view state from controller (isStreaming changes)
- Filler isolation via `ValueNotifier<double>` + `ValueListenableBuilder`

### Integration Points
- `_streaming` boolean in controller → replaced by state enum
- `_anchorActive` boolean in view state → derived from state enum
- `_onControllerChanged()` in view checks `isStreaming` → will check state enum instead
- `_onScrollChanged()` updates `isAtBottom` → may also trigger state transitions (idle ↔ historyBrowsing)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-state-machine-foundation*
*Context gathered: 2026-03-17*
