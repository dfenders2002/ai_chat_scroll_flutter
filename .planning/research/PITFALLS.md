# Pitfalls Research

**Domain:** Flutter scroll package — adding auto-follow, 5-state machine, and dual layout modes to existing v1
**Researched:** 2026-03-17
**Confidence:** HIGH (v1 implementation experience + Flutter engine docs) / MEDIUM (community patterns)

---

## Critical Pitfalls

### Pitfall 1: State Machine Expressed as Parallel Boolean Flags

**What goes wrong:**
The v1 implementation uses two booleans — `_anchorActive` and `_streaming` (on the controller) — that must be kept in sync manually. In v2, a 5-state machine (`idle_at_bottom`, `submitted_waiting_response`, `streaming_following`, `streaming_detached`, `history_browsing`) implemented as more booleans produces impossible combined states. For example: `_anchorActive = true` AND `_streaming = false` AND `_userScrolled = true` — which state is this? No single path handles it cleanly, so multiple code paths start patching each other and the logic diverges silently.

**Why it happens:**
Incrementally adding features. The v1 boolean pair was sufficient. Adding `streaming_detached` requires a third flag (`_userScrolledAway`). Adding `history_browsing` requires a fourth. Booleans multiply; valid combinations shrink; untested combinations produce subtle bugs at the intersection.

**How to avoid:**
Replace the two booleans with a single `ScrollState` enum on the controller at the start of v2, before any new behavior is wired. Define explicit transition rules — which states are valid sources for each transition. Any code path that would create an undocumented combined state becomes a lint-visible invalid transition.

```dart
enum ScrollState {
  idleAtBottom,
  submittedWaitingResponse,
  streamingFollowing,
  streamingDetached,
  historyBrowsing,
}
```

Each method on the controller transitions from a specific set of source states only. Guard clauses assert source state at entry.

**Warning signs:**
- A new `if (_anchorActive && !_streaming)` clause being added to handle an edge case
- The `_onScrollChanged` method checking three or more boolean flags in combination
- A bug that only reproduces when the user scrolls, then sends, then scrolls again quickly

**Phase to address:** The first v2 phase — define the enum and migrate the controller before any new feature code is written. This is the architectural decision that all other v2 behavior depends on. Retrofitting it after auto-follow is built costs a full rewrite of the notification handlers.

---

### Pitfall 2: Auto-Follow Compensation Fighting User Drag

**What goes wrong:**
Auto-follow in `streaming_following` state works by responding to `ScrollMetricsNotification` with delta compensation (the v1 pattern: `newMax - _lastMaxScrollExtent`, then `jumpTo(offset + delta)`). When the user drags while streaming is active, the drag changes both `pixels` and `maxScrollExtent` simultaneously. The notification handler fires during the drag, reads a stale `_lastMaxScrollExtent`, computes a spurious positive delta, and calls `jumpTo` — overriding the user's drag mid-gesture. The scroll position snaps, the user perceives a jerk, and the state never transitions to `streaming_detached`.

**Why it happens:**
The v1 `_onScrollChanged` guard `if (notification.dragDetails != null && _anchorActive) { _anchorActive = false; }` cancels the STATIC anchor. But auto-follow is a different behavior — it fires from `ScrollMetricsNotification`, not `ScrollUpdateNotification`. If the guard only covers the old path, the new auto-follow path remains active during drag.

**How to avoid:**
The `streaming_detached` transition must be triggered by the same `ScrollUpdateNotification` with `dragDetails != null` check that cancels v1 anchor. Crucially, the handler for `ScrollMetricsNotification` must check state before executing compensation — if state is `streaming_detached` or `historyBrowsing`, skip all delta compensation. The drag handler must transition state FIRST, before the metrics notification fires, or the metrics handler must be gated on state, not a boolean.

**Warning signs:**
- Scroll position jumps briefly during user drag while streaming is active
- The `streaming_detached` state is never entered even when user visibly scrolls
- Tests pass in isolation but fail when drag and metrics update fire in the same frame

**Phase to address:** Auto-follow implementation phase. Write a widget test that simulates a drag notification arriving concurrently with a metrics notification before implementing auto-follow. Let that test fail first.

---

### Pitfall 3: Transition Back to Rest Layout Leaves a Phantom Filler

**What goes wrong:**
The active-turn layout requires a filler sliver whose height keeps the user message anchored near the top. When streaming ends and the system transitions from `streaming_following` (or `streaming_detached`) back to `idle_at_bottom` (rest layout — bottom-aligned), the filler height is left at its last computed value. The list has a large empty area above the bottom content. Users can scroll into this empty area. `jumpTo(maxScrollExtent)` after the transition visually resolves this, but the filler is still occupying space — the next `isAtBottom` check reads the extended `maxScrollExtent`, not the content-only extent.

**Why it happens:**
`onResponseComplete()` in v1 just clears `_anchorActive` and removes the `GlobalKey`. There is no filler reset. The filler was designed to persist after streaming because clearing it would cause a visible layout jump. In v2, the "rest layout" is a defined mode — it requires filler to be zero. Without an explicit reset-and-scroll sequence, the phantom filler persists.

**How to avoid:**
Define a `_transitionToRest()` method that: (1) sets `_fillerHeight.value = 0.0`, (2) waits one frame via `addPostFrameCallback`, (3) calls `jumpTo(maxScrollExtent)` to scroll to actual bottom. The transition must be a deliberate two-step with the frame wait, not a synchronous clear. Without the frame wait, `maxScrollExtent` still reflects the old filler height at the time of the jump.

**Warning signs:**
- After streaming ends, scrolling up reveals a large empty gap above message content
- `isAtBottom` reports `true` while the viewport shows content that looks like it should have more below it
- The `scrollToBottom()` call immediately after `onResponseComplete()` overshoots

**Phase to address:** The response-completion / layout transition phase. Add a widget test that measures `maxScrollExtent` before and after `onResponseComplete()` — the post-transition extent must equal the actual content height.

---

### Pitfall 4: ScrollMetricsNotification Fires During filler Resize, Triggering a Second Resize

**What goes wrong:**
When `_fillerHeight.value` is updated (filler shrinks as AI response grows), the sliver layout runs, `maxScrollExtent` changes, and a `ScrollMetricsNotification` fires. If the notification handler also updates `_fillerHeight` (which it does in auto-follow compensation), you have: filler change → metrics notification → filler change → metrics notification. The loop terminates only because the delta eventually reaches the 0.5 threshold. But between cycles, `jumpTo` is called multiple times per frame, producing jitter.

This is a re-entrant notification loop — a known Flutter scroll pattern failure mode documented in flutter/flutter#121419.

**Why it happens:**
The v1 handler uses `if (delta > 0.5)` as a stabiliser, and it works because the filler in v1 never changes inside the metrics notification — filler was driven by `_anchorActive` flag state, not by the notification itself. In v2, auto-follow moves the scroll position in response to metrics changes AND filler is also responding to content growth — two feedback paths can activate each other in the same notification cycle.

**How to avoid:**
Gate all filler updates with a boolean guard: `_fillerUpdateInProgress`. Set it to `true` at the start of a filler update, `false` at the end. The metrics notification handler skips all filler computation if this guard is set. Alternatively, route all filler changes through a single `postFrameCallback` (debounced to one update per frame) so at most one filler change fires per frame.

**Warning signs:**
- Jitter during streaming visible in the Flutter DevTools "rebuild" overlay
- `_fillerHeight.value` changes more than once per frame during streaming (add a counter to detect)
- Frame time spikes to 30+ ms during streaming even with low message count

**Phase to address:** Auto-follow + filler integration phase. Add a frame-rate assertion to the streaming test: during streaming with 10 messages, frame time must stay below 16 ms.

---

### Pitfall 5: Content-Bounded Filler Allows Phantom Scroll Area When Content Is Short

**What goes wrong:**
In the rest layout, a bottom-aligned list with few messages should show content at the bottom of the viewport with no scrollable empty area above. But if the filler from a previous active-turn session was not cleared, or if the filler computation does not re-run when `itemCount` decreases (e.g., messages cleared), the filler persists and creates a scrollable empty area at the top that users cannot explain or interact with meaningfully. This "ghost scroll" region appears empty and breaks `isAtBottom` semantics.

**Why it happens:**
Filler is computed reactively on streaming events — it is never recomputed on `itemCount` changes unless explicitly triggered. When `itemCount` drops (conversation cleared, reload, or test scenario), the filler is never zeroed because no streaming event fired.

**How to avoid:**
In `didUpdateWidget`, compare `widget.itemCount` with `oldWidget.itemCount`. If item count decreases and state is `idleAtBottom`, reset filler to `0.0`. Add a separate path that explicitly validates the filler is content-bounded: filler must not exceed `max(0, viewportHeight - totalContentHeight)`. This can run as a postFrameCallback after any `itemCount` change.

**Warning signs:**
- After clearing a conversation and starting a new one, the list has a scrollable empty region
- `scrollController.position.maxScrollExtent` is non-zero when the list has fewer items than fit in the viewport
- `isAtBottom` returns `false` immediately after clearing all messages

**Phase to address:** Content-bounded spacing phase. Write a test: add 3 messages, trigger anchor, clear all messages, verify `maxScrollExtent == 0.0`.

---

### Pitfall 6: Smart Down-Button Target Uses Absolute Bottom Instead of Active-Turn Composition

**What goes wrong:**
The "smart" down button is supposed to jump to the active-turn composition (user message + beginning of AI response), not to the absolute scroll bottom. If it calls `jumpTo(maxScrollExtent)` (the v1 `scrollToBottom` implementation), it scrolls past the user message to wherever the AI response ended — the user sees the tail of the AI response, not the contextual start of their turn. This defeats the entire value of the smart button.

**Why it happens:**
`scrollToBottom()` is a single method that reuses the same target in both rest mode and active-turn mode. The API does not distinguish between contexts. In rest mode, `maxScrollExtent` is correct. In active-turn mode, it is wrong.

**How to avoid:**
The down-button target must be state-aware. In `streaming_following`, `streaming_detached`, or `submitted_waiting_response`, the target is the stored active-turn anchor offset — the `jumpTo(0.0)` position from when the user sent the message (in the `reverse: true` coordinate system, offset 0 = visual bottom; in the forward system, offset = filler height from bottom). The public API should expose `scrollToActiveAnchor()` as a distinct method from `scrollToBottom()`, or make `scrollToBottom()` state-aware internally.

**Warning signs:**
- Tapping the down button during streaming scrolls past the user message to the end of the AI response
- The down button behavior is different depending on when during streaming the user taps
- Unit tests for `scrollToBottom()` pass but integration test shows wrong scroll target

**Phase to address:** Smart down-button phase. Define the target offset formula for active-turn mode before implementing the button, not after.

---

### Pitfall 7: Transition from `history_browsing` to Active-Turn Broken by Stale AnchorIndex

**What goes wrong:**
When the user is in `history_browsing` state (scrolled up into history) and sends a new message, the expected behavior is a forced re-anchor to the new message at the top. The `_anchorReverseIndex` from the previous turn (pointing to the old user message) may still be set or may have been cleared. If cleared, `_startAnchor()` fires and attaches the `GlobalKey` to `reverseIndex 0` (the new message) — correct. If NOT cleared, the GlobalKey still points to the old message, and `_measureAndAnchor()` measures the wrong item's height, computing the wrong filler value and anchoring to the wrong position.

**Why it happens:**
In v1, `_anchorReverseIndex` is cleared in `onResponseComplete()` via `setState`. But if the user sends a new message before the previous response completes (or during `history_browsing` with no active streaming), `_anchorReverseIndex` may be stale. The state machine transition from `historyBrowsing → submittedWaitingResponse` must explicitly clear old anchor state as part of the transition, not rely on `onResponseComplete()` having run first.

**How to avoid:**
Every transition that leads to re-anchoring must include a state reset step: `_anchorReverseIndex = -1`, `_fillerHeight.value = 0.0`, `_anchorActive = false` (or their v2 equivalents). Define a `_clearAnchorState()` helper called at the start of every `_startAnchor()` invocation, regardless of which state triggered it.

**Warning signs:**
- Second message send anchors to the first message's position, not the second
- Re-anchoring works on the first send but fails on rapid consecutive sends
- Test: send message → scroll to history → send second message → anchor position is wrong

**Phase to address:** State machine foundation phase (before auto-follow is implemented). The transition table for `historyBrowsing → submittedWaitingResponse` must include the state-clear step.

---

### Pitfall 8: Breaking the v1 Public API Without a Major Version Bump

**What goes wrong:**
Adding the 5-state machine requires the controller to track more internal state. The temptation is to add new fields and then modify existing methods (`onUserMessageSent`, `onResponseComplete`, `scrollToBottom`) to behave differently based on the new state. This changes observable behavior without a signature change — consumers who depend on the old behavior get broken silently. The pub.dev semver contract requires a major version bump for breaking behavioral changes, not just signature changes.

**Why it happens:**
Behavioral changes feel like internal improvements. There is no compiler error when `scrollToBottom()` starts jumping to the anchor offset instead of `maxScrollExtent`. Consumers find out at runtime, after upgrading.

**How to avoid:**
Before modifying any existing method, ask: "Does this method's observable behavior change?" If yes, either add a new method and deprecate the old one (non-breaking), or increment the major version. Keep a BREAKING_CHANGES.md note during development. Specifically: `scrollToBottom()` behavior in active-turn mode is a breaking change if it no longer jumps to the absolute bottom.

**Warning signs:**
- An existing test for `scrollToBottom()` is modified rather than a new test added
- CHANGELOG shows new features but no `BREAKING:` entry despite modified method behavior
- A consumer's existing integration breaks after upgrading to v2

**Phase to address:** API design phase at the start of v2. Lock the v1 API surface as a compatibility contract before writing any new code.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keep `_anchorActive` + `_streaming` booleans and add a third `_userScrolledAway` boolean | Incremental change to existing code | Three booleans have 8 combinations; only 5 are valid; the 3 invalid combos produce silent misbehavior at edge cases | Never in v2 — migrate to enum at the start |
| Use a single `scrollToBottom()` for both rest and active-turn contexts | Minimal API surface | Scroll target is wrong in active-turn; smart button UX broken | Never — split or make state-aware |
| Recompute filler synchronously inside `ScrollMetricsNotification` handler | Simpler code path | Re-entrancy loop risk; jitter when filler change triggers another metrics notification | Never — always gate through postFrameCallback |
| Clear filler with `setState` that also rebuilds the full list | One call handles everything | Full-list rebuild on every streaming token or state transition | Never — filler is a ValueNotifier, changes must not trigger list rebuild |
| Skip content-bounded filler validation on `itemCount` changes | Saves one `didUpdateWidget` comparison | Ghost scroll region after conversation clear; `isAtBottom` semantics broken | Never |
| Reuse `_anchorReverseIndex = 0` assumption without clearing on re-send | Works for the first send | Second send from history state anchors to wrong message | Never |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Consumer calls `onUserMessageSent()` during `streaming_following` (rapid send while AI is responding) | Current state machine has no `streaming_following → submittedWaitingResponse` transition rule; call silently no-ops or corrupts state | Define explicit transition for this case: either queue the new anchor or force-complete the current streaming and begin a new anchor sequence |
| Consumer's message list `itemCount` jumps from N to N+2 in one `setState` (user message + optimistic AI stub added together) | `_startAnchor` fires once, sees `reverseIndex 0` = the AI stub, not the user message | Document that the anchor always targets `reverseIndex 1` (the message just before the newest item) OR require consumer to add user message and AI stub in separate frames; either way must be explicit in docs |
| Consumer wraps `AiChatScrollView` in a `PageView` or `TabBarView` | Widget is disposed and remounted on tab switch; `_scrollController` is re-created on remount but `AiChatScrollController` retains stale internal state from previous mount including `_streaming = true` | `detach()` must fully reset controller state including streaming flag; or document that `AiChatScrollController` must be recreated per-route |
| Consumer signals `onResponseComplete()` before the last streaming token is rendered | State transitions to `idleAtBottom`, filler is reset, then final setState from streaming adds one more token which shifts layout | `onResponseComplete()` must be called only after the consumer's message list `setState` for the final token has been committed; document this ordering requirement explicitly |
| Consumer listens to `isAtBottom` to decide whether to show a new-message notification banner | In active-turn states, `isAtBottom` may be `true` even though the user has not seen the full AI response | The down-button / notification logic needs to account for active-turn states separately from rest state; `isAtBottom` alone is insufficient for this use case in v2 |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `setState` used to update `_scrollState` enum causes full widget rebuild including SliverList | Frame drops on every state transition (send, detach, complete) | State transitions that do not change the rendered widget tree (no GlobalKey change, no filler change) must NOT call `setState`; use ChangeNotifier + targeted ValueNotifier updates instead | Visible with 30+ messages; severe with 100+ |
| `ScrollMetricsNotification` fires multiple times per frame during aggressive streaming | Filler computed N times per frame; `jumpTo` called N times per frame | Debounce: set a `_metricsUpdateScheduled` flag, schedule one `postFrameCallback`, clear flag; all notifications in a single frame collapse to one update | Streaming at >20 tokens/second; severity scales with token rate |
| GlobalKey on anchor item retained during `streaming_detached` state when it is no longer needed | GlobalKey registered in global map for entire streaming duration even though no measurement is needed after initial anchor | Clear `_anchorReverseIndex` (and thus remove GlobalKey from the tree) as soon as the initial `_measureAndAnchor()` completes; the key's only job is measurement, not persistence | Scales with number of streaming sessions in a long-lived app |
| `animateTo` called for the rest-layout transition after `onResponseComplete()` while user is dragging | Assertion crash: `isScrolling` conflict; or animation fights user drag | Use `jumpTo` (not `animateTo`) for all programmatic position changes during or immediately after streaming; reserve `animateTo` only for explicit user-initiated actions (e.g. scrollToBottom FAB tap) | Any time user touches screen near end of streaming |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Auto-follow continues while user has scrolled up to read the AI response mid-stream | Scroll position jumps down on each new token; user cannot read content in progress | Transition to `streaming_detached` on first significant upward drag (>8px); do not resume auto-follow unless user explicitly taps the down button |
| Down button visible during `streaming_following` state points to end of response | User taps down button expecting to see their sent message and the start of the response; instead sees the tail of a partial response | During active-turn states, down button jumps to the active-anchor offset (user message at top of viewport), not to `maxScrollExtent` |
| Layout transition to rest (filler clears) is instantaneous on slow devices | One frame with content at the wrong position is visible before the jump completes | Schedule the `jumpTo` in the `postFrameCallback` after filler clear, not synchronously; add a zero-opacity overlay for one frame if visible transition is unacceptable |
| `submitted_waiting_response` state (sent, no AI tokens yet) shows empty space below user message | User interprets empty space as a bug or app freeze | Show a loading indicator in the filler area during `submitted_waiting_response`; the filler widget should expose a state flag to the consumer for this case |
| User sends message while history-browsing; viewport snaps away immediately | User loses scroll context they were reading | At minimum: honour the snap (it is the spec); document it clearly; optionally add a brief visual cue that the viewport has re-anchored (future v2.1 concern) |

---

## "Looks Done But Isn't" Checklist

- [ ] **Auto-follow**: Response grows and viewport follows — but verify that tapping the screen mid-stream transitions to `streaming_detached` and auto-follow STOPS. If the tap still shows follow behavior, the state transition is not wired.
- [ ] **5-state machine**: All 5 states are defined and each method has a transition guard — but verify the INVALID transitions are also tested. Write a test that calls `onUserMessageSent()` from each state and assert that only valid source states produce a state change.
- [ ] **Dual layout rest**: List is bottom-aligned at rest — but verify with 2 messages (content shorter than viewport). The filler must be 0 in rest mode; the few messages must sit at the visual bottom without a scrollable gap above.
- [ ] **Phantom filler**: Streaming ends, rest layout resumes — but verify `maxScrollExtent` equals `totalContentHeight - viewportHeight` (or 0 if content fits). If `maxScrollExtent` is inflated, the filler was not cleared.
- [ ] **Smart down button**: Button appears when user has scrolled away — but verify the scroll TARGET is the active-anchor position (not `maxScrollExtent`) during `streaming_following` and `streaming_detached` states.
- [ ] **Content-bounded spacing**: Short conversation with 3 messages — user should NOT be able to scroll up into empty space. Verify `minScrollExtent == 0` and `maxScrollExtent` reflects only actual content.
- [ ] **History-browsing re-send**: Scroll to top of a 20-message history → send new message → verify new user message anchors at top, not previous user message.
- [ ] **Rapid consecutive sends**: Send message → immediately send second before AI responds → verify second message is anchored correctly and state machine reaches a valid state.
- [ ] **v1 regression**: All v1 widget tests must still pass. Especially: drag during anchor, keyboard open during anchor, `onResponseComplete()` while dragging.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| State machine implemented as boolean flags, shipped in v2 | HIGH | Architectural refactor of controller and view state; likely requires re-thinking all edge case handling; patch release with breaking change |
| Phantom filler after response complete shipped to consumers | MEDIUM | Add `_fillerHeight.value = 0.0` reset to `onResponseComplete()` path + frame-deferred `jumpTo`; patch release; non-breaking behaviorally |
| Auto-follow fighting user drag | MEDIUM | Tighten the state guard in `ScrollMetricsNotification` handler to check `_scrollState`; patch release |
| Smart down button jumps to wrong target | LOW | Override `scrollToBottom()` to be state-aware; or add `scrollToActiveAnchor()` and deprecate `scrollToBottom()` in active-turn contexts; patch release |
| Breaking v1 API behavior without major version bump | HIGH | Major version bump required; communicate via CHANGELOG and README migration guide; consumers must update integration code |
| Re-entrant filler notification loop causing jitter | MEDIUM | Add `_fillerUpdateInProgress` guard; debounce to one update per frame; patch release |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Boolean flags instead of state enum | Phase 1: State machine foundation | Test: call all controller methods from all states; assert no impossible state combination is reachable |
| Auto-follow vs. user drag conflict | Phase 2: Auto-follow implementation | Widget test: simulate `ScrollUpdateNotification` with `dragDetails` during streaming; assert state transitions to `streaming_detached` and `jumpTo` is NOT called afterward |
| Phantom filler after response complete | Phase 3: Rest-layout transition | Widget test: stream 10 tokens → call `onResponseComplete()` → assert `maxScrollExtent` == content height (not inflated) |
| Re-entrant filler notification loop | Phase 2: Auto-follow + filler integration | Frame time test: streaming at 30 tokens/sec with 50 messages; assert <16 ms per frame |
| Content-bounded spacing with short content | Phase 1 or rest-layout phase | Widget test: 2 messages in tall viewport; assert `maxScrollExtent == 0.0` |
| Smart down button wrong target | Phase 4: Smart down button | Integration test: enter streaming → scroll away → tap down button → assert viewport shows user message at top |
| Stale anchor index on re-send from history | Phase 1: State machine + anchor transition | Widget test: send → complete → scroll to history → send again → assert new anchor is at second message, not first |
| Breaking v1 API | Throughout v2 | Run full v1 widget test suite against v2 implementation before any release; must have 0 regressions |

---

## Sources

- v1 PITFALLS.md — established v1 Flutter scroll pitfalls, all still applicable
- v1 implementation (`ai_chat_scroll_view.dart`, `ai_chat_scroll_controller.dart`) — inspected directly; v1 boolean structure is the source of the state-machine pitfall
- [flutter/flutter issue #121419: ScrollController doesn't broadcast change notification after shrinking content](https://github.com/flutter/flutter/issues/121419) — source for re-entrant notification loop pitfall
- [flutter/flutter PR #164392: Fix race condition causing crash when interacting with animating scrollable](https://github.com/flutter/flutter/pull/164392) — scroll animation + user interaction race condition
- [flyerhq/flutter_chat_ui issue #39: Scroll jumps when looking at old messages while new ones arrive](https://github.com/flyerhq/flutter_chat_ui/issues/39) — auto-follow vs. user scroll conflict; established pattern of bypass when user scrolls away
- [flyerhq/flutter_chat_ui issue #577: Every message rebuilds on scroll](https://github.com/flyerhq/flutter_chat_ui/issues/577) — confirms full-list rebuild via setState is an unrecoverable architecture mistake
- [Flutter ScrollController class docs](https://api.flutter.dev/flutter/widgets/ScrollController-class.html) — `hasClients`, notification types, `addListener` limitation
- [Flutter ScrollMetricsNotification class docs](https://api.flutter.dev/flutter/widgets/ScrollMetricsNotification-class.html) — scroll metrics vs scroll position notification distinction
- [smarx.com: Automatic Scroll-To-Bottom in Flutter](https://smarx.com/posts/2020/08/automatic-scroll-to-bottom-in-flutter/) — timing pattern for auto-follow with postFrameCallback
- v1 phase summaries (phases 03, 05) — keyboard compensation math invariant; scheduleFrame requirement; GlobalKey measurement timing

---
*Pitfalls research for: Flutter AI chat scroll package (ai_chat_scroll) — v2.0 dual-layout + auto-follow + 5-state machine milestone*
*Researched: 2026-03-17*
