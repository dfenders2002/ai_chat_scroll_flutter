# Phase 7: Auto-Follow and Scroll Detach - Research

**Researched:** 2026-03-17
**Domain:** Flutter scroll notification system, state-gated scroll compensation, drag detection
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Auto-follow trigger**
- View detects first content growth via `ScrollMetricsNotification` (maxScrollExtent increases while in submittedWaitingResponse) — no new public API needed for streaming start detection
- Keep `jumpTo(offset+delta)` compensation but gate it strictly on `streamingFollowing` state — fixes current flickering bug by not compensating during other states
- Filler shrinks dynamically as AI response grows: `filler = viewport - userMsg - aiResponse` until filler reaches 0, then pure scroll compensation takes over

**Detach behavior**
- Immediate detach on first drag frame — no pixel threshold, matches Claude app behavior where any touch stops auto-scroll
- Filler freezes at current value on detach — user can scroll freely within existing content+filler bounds, no content jump
- User can re-attach by scrolling back to within `atBottomThreshold` during streaming (not just down-button)

**State transitions in view**
- View calls a new internal controller method when it detects content growth to transition submittedWaitingResponse → streamingFollowing — controller owns all transitions
- View calls `controller.onUserScrolled()` (new public method) on drag detect to transition streamingFollowing → streamingDetached
- `scrollToBottom()` during active streaming transitions to streamingFollowing and resumes compensation

### Claude's Discretion
- Internal naming of helper methods in the view
- Whether `onUserScrolled()` is public or package-private
- Exact implementation of filler shrink formula

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FOLLOW-01 | During `streamingFollowing` state, viewport automatically tracks the growing AI response so newest tokens remain visible | `_onMetricsChanged()` already does this — gating on `scrollState.value == streamingFollowing` is the fix |
| FOLLOW-02 | When user drags upward during streaming, auto-follow stops immediately and state transitions to `streamingDetached` | `ScrollUpdateNotification.dragDetails != null` is the drag signal — already in the view, needs to call `controller.onUserScrolled()` |
| FOLLOW-03 | Auto-follow resumes when user taps down-button or manually scrolls back to live bottom, transitioning state to `streamingFollowing` | `_onScrollChanged()` atBottom check during streaming, plus `scrollToBottom()` controller path |
</phase_requirements>

## Summary

Phase 7 wires the `streamingFollowing` / `streamingDetached` state enum values (created in Phase 6) to actual scroll compensation behavior in `_AiChatScrollViewState`. The core mechanics — `ScrollMetricsNotification`-driven `jumpTo()` compensation, drag detection via `ScrollUpdateNotification.dragDetails`, and the atBottom re-attach check — all exist in the current view. The sole work is replacing the single `_anchorActive` boolean with state-enum guards and adding two new controller-to-view signal paths.

The flickering bug reported in the example app is a direct symptom of the current code: `_onMetricsChanged()` fires on every `maxScrollExtent` change regardless of state, so content size changes outside of streaming (e.g., keyboard animation, rebuild) trigger spurious `jumpTo()` calls. Gating on `streamingFollowing` eliminates this entirely.

The filler-shrink path is already implemented: when `maxScrollExtent` grows and filler is still positive, the delta is absorbed by filler reduction rather than pixel compensation. Phase 7 must ensure this path is also state-gated.

**Primary recommendation:** Replace the `_anchorActive` boolean with `scrollState`-enum checks throughout `_AiChatScrollViewState`, add `onUserScrolled()` to the controller with a `streamingFollowing → streamingDetached` transition, and add a streaming-aware re-attach path to both `_onScrollChanged()` and `scrollToBottom()`.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter/widgets.dart | SDK | `NotificationListener`, `ScrollUpdateNotification`, `ScrollMetricsNotification` | Built-in Flutter scroll notification system |
| flutter/scheduler.dart | SDK | `addPostFrameCallback`, `scheduleFrame` | Safe scroll dispatch from build/layout callbacks |
| flutter/foundation.dart | SDK | `ValueNotifier`, `ChangeNotifier` | Already used for filler isolation and controller events |

No third-party dependencies. This is pure Flutter SDK — all mechanisms are already imported.

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| flutter_test | SDK | Widget tests for scroll simulation | All FOLLOW tests require `WidgetTester` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ScrollMetricsNotification` for content growth | `addListener` on `ScrollController` | Notification fires during layout; listener fires post-layout. Notifications catch the frame content grew; listener is one frame late |
| `ScrollUpdateNotification.dragDetails` for drag | `ScrollStartNotification` | `dragDetails` is null for programmatic scrolls; `ScrollStartNotification` fires for both drag and programmatic, requiring extra disambiguation |

**Installation:** No new packages needed.

## Architecture Patterns

### Recommended Project Structure

No structural changes. Phase 7 modifies two existing files:

```
lib/src/
├── controller/
│   └── ai_chat_scroll_controller.dart   # Add onUserScrolled(), streaming-aware scrollToBottom()
└── widgets/
    └── ai_chat_scroll_view.dart         # Replace _anchorActive bool with state checks
test/
└── auto_follow_test.dart                # New test file for FOLLOW-01/02/03
```

### Pattern 1: State-Gated Scroll Compensation

**What:** Guard all `jumpTo()` and filler mutation calls with an explicit `scrollState.value` check rather than a mutable boolean.
**When to use:** Any time a view-side side-effect must be conditional on controller state.

**Current code (has _anchorActive boolean):**
```dart
// In _onMetricsChanged():
if (!_anchorActive || !_scrollController.hasClients) return;

// In build() NotificationListener:
if (notification.dragDetails != null && _anchorActive) {
  _anchorActive = false;
}
```

**Target code (state-enum gate):**
```dart
// In _onMetricsChanged():
final state = widget.controller.scrollState.value;
if (state != AiChatScrollState.streamingFollowing) return;
if (!_scrollController.hasClients) return;

// In build() NotificationListener:
final state = widget.controller.scrollState.value;
if (notification.dragDetails != null &&
    state == AiChatScrollState.streamingFollowing) {
  widget.controller.onUserScrolled();
}
```

The boolean is effectively replaced by querying the controller's `ValueNotifier<AiChatScrollState>`. No extra state in the view.

### Pattern 2: Content-Growth-Triggered State Transition (submittedWaitingResponse → streamingFollowing)

**What:** `_onMetricsChanged()` detects the first `maxScrollExtent` increase while in `submittedWaitingResponse`. That is the signal that the first AI token has arrived and layout has grown.
**When to use:** The ONLY correct trigger for entering `streamingFollowing`.

```dart
void _onMetricsChanged(ScrollMetricsNotification notification) {
  if (!_scrollController.hasClients) return;
  final state = widget.controller.scrollState.value;

  // First content growth while waiting for response → start following
  if (state == AiChatScrollState.submittedWaitingResponse) {
    final newMax = notification.metrics.maxScrollExtent;
    if (newMax > _lastMaxScrollExtent + 0.5) {
      widget.controller.onStreamingStarted(); // internal: submittedWaiting → streamingFollowing
      _lastMaxScrollExtent = newMax;
      // Compensation fires next frame via new state
    }
    return;
  }

  // Only compensate when actively following
  if (state != AiChatScrollState.streamingFollowing) return;

  final newMax = notification.metrics.maxScrollExtent;
  final delta = newMax - _lastMaxScrollExtent;

  if (delta > 0.5) {
    _lastMaxScrollExtent = newMax;
    final target = _scrollController.offset + delta;
    _scrollController.jumpTo(target.clamp(0.0, newMax));
  } else if (delta < -0.5) {
    _lastMaxScrollExtent = newMax;
  }
}
```

Note: The method name `onStreamingStarted()` (or equivalent) is at Claude's discretion per the CONTEXT.md decisions.

### Pattern 3: Re-Attach on Scroll-Back (FOLLOW-03)

**What:** During `streamingDetached`, check `isAtBottom` on every scroll event. If the user returns to the live bottom, transition back to `streamingFollowing`.
**When to use:** In `_onScrollChanged()` — already fires on every scroll position change.

```dart
void _onScrollChanged() {
  if (!_scrollController.hasClients) return;
  final pos = _scrollController.position;
  final atBottom = pos.pixels >= pos.maxScrollExtent - widget.controller.atBottomThreshold;
  widget.controller.updateIsAtBottom(atBottom);

  // Re-attach: if user scrolled back to bottom during streamingDetached
  final state = widget.controller.scrollState.value;
  if (state == AiChatScrollState.streamingDetached && atBottom) {
    widget.controller.onScrolledToBottom(); // internal: streamingDetached → streamingFollowing
  }
}
```

Note: The existing `_onScrollChanged()` uses `pos.pixels <= widget.controller.atBottomThreshold` which is a reverse-list convention (pixels=0 is the live bottom in `reverse: true` list). Verify sign convention matches Phase 7 re-attach check.

### Pattern 4: scrollToBottom() Re-Attach Path

**What:** When `scrollToBottom()` is called during streaming (either state), transition to `streamingFollowing` after scrolling.
**When to use:** In controller's `scrollToBottom()` method.

```dart
void scrollToBottom() {
  if (_scrollController == null || !_scrollController!.hasClients) return;
  final isActivelyStreaming =
      _scrollState.value == AiChatScrollState.streamingFollowing ||
      _scrollState.value == AiChatScrollState.streamingDetached;

  _scrollController!.animateTo(
    _scrollController!.position.maxScrollExtent,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOut,
  );

  if (isActivelyStreaming) {
    // Re-attach after scroll completes — transition fires immediately,
    // compensation resumes on next _onMetricsChanged() call
    _transition(AiChatScrollState.streamingFollowing);
  }
}
```

### Anti-Patterns to Avoid

- **State in the view alongside state in the controller:** Do NOT keep `_anchorActive` as a fallback; remove it entirely. Two sources of truth for "should I compensate?" are how the flickering bug was introduced.
- **Calling `jumpTo()` in `scrollToBottom()` for the re-attach:** `scrollToBottom()` uses `animateTo()`. The `animateTo()` call itself will trigger `ScrollUpdateNotification` with `dragDetails == null`, which must NOT trigger detach. The drag check gates on `dragDetails != null`, so this is safe — but do not change that guard.
- **Firing `onStreamingStarted()` / `onUserScrolled()` inside `setState()` or `build()`:** Controller transitions must happen from notification handlers or postFrameCallbacks, never from build methods.
- **Double-gating with both `_anchorActive` and state check:** Redundant booleans are what phase 6 was designed to eliminate. Replace, don't augment.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Content growth detection | Custom polling ticker or manual `addListener` comparison | `ScrollMetricsNotification` | Fires synchronously during the layout pass that introduced growth — lowest latency, already wired in the view |
| Drag detection | GestureDetector wrapping the list | `ScrollUpdateNotification.dragDetails != null` | Works correctly with nested scrollable and reverse-scroll coordinate system |
| Re-attach threshold | Custom distance tracker | `atBottomThreshold` already on controller | Reusing the same threshold for "isAtBottom" UI and "re-attach trigger" is consistent by design |

**Key insight:** Every mechanism needed for Phase 7 is already implemented in the current view. Phase 7 is a precision refactor, not a feature build.

## Common Pitfalls

### Pitfall 1: Reverse-List Coordinate System Sign Error

**What goes wrong:** `CustomScrollView(reverse: true)` means `pixels = 0` is the live bottom, `pixels = maxScrollExtent` is the top of history. Code that checks `pos.pixels <= threshold` for "at bottom" is correct for this orientation. Code that compares `pos.pixels >= pos.maxScrollExtent - threshold` is wrong — it detects the top of history, not the live bottom.

**Why it happens:** Developers familiar with normal (non-reversed) lists assume large pixel values = bottom.

**How to avoid:** In `_onScrollChanged()`, the existing `pos.pixels <= widget.controller.atBottomThreshold` is the correct check for "at live bottom" in a reversed list. Keep this convention throughout Phase 7.

**Warning signs:** Re-attach fires immediately on send (before user scrolls) or never fires when user returns to latest message.

### Pitfall 2: `ScrollMetricsNotification` Fires on Viewport Resize Too

**What goes wrong:** `ScrollMetricsNotification` fires whenever `maxScrollExtent` changes — which includes keyboard appearing/disappearing, window resize, and orientation change — not just new content. Without state gating, keyboard dismissal triggers spurious `jumpTo()`.

**Why it happens:** This is a general-purpose notification, not a "new content" notification.

**How to avoid:** The state gate (`streamingFollowing` only) eliminates all spurious compensation by definition. Keyboard events happen during `idleAtBottom` or `historyBrowsing`, so they never reach the compensation branch.

### Pitfall 3: `animateTo()` Triggers Detach

**What goes wrong:** `scrollToBottom()` calls `animateTo()`, which generates `ScrollUpdateNotification` without `dragDetails`. If detach is triggered by any `ScrollUpdateNotification` (not just drag), `animateTo()` would immediately detach the re-attach it just initiated.

**Why it happens:** Over-broad notification guard — forgetting `dragDetails != null` check.

**How to avoid:** The existing guard `notification.dragDetails != null` is correct and must be preserved. Only touch-initiated scroll events have non-null `dragDetails`.

### Pitfall 4: `_lastMaxScrollExtent` Not Reset on Anchor Start

**What goes wrong:** If `_lastMaxScrollExtent` holds a value from a previous session and the new session starts with a higher `maxScrollExtent`, `_onMetricsChanged()` immediately fires a large delta compensation jump before the user sends a message.

**Why it happens:** `_lastMaxScrollExtent` is initialized once in `_measureAndAnchor()` but not on the `submittedWaitingResponse → streamingFollowing` transition.

**How to avoid:** Set `_lastMaxScrollExtent = _scrollController.position.maxScrollExtent` at the moment the state enters `streamingFollowing` (either in the controller callback or at the top of `_onMetricsChanged()` when handling the first transition).

### Pitfall 5: Detach Fires During Filler-Phase Anchor Jump

**What goes wrong:** `_measureAndAnchor()` calls `_scrollController.jumpTo(0.0)`, which can trigger `ScrollUpdateNotification`. If the view at that point is already in `streamingFollowing` state, the detach guard fires and cancels the anchor.

**Why it happens:** Anchor jump is programmatic but goes through the notification system.

**How to avoid:** `ScrollUpdateNotification.dragDetails` is null for `jumpTo()`, so the existing guard `dragDetails != null` prevents this. Do not remove or weaken that guard. As a belt-and-suspenders, `jumpTo()` happens in `submittedWaitingResponse` state (before `streamingFollowing`), so even without the guard, state won't match.

## Code Examples

Verified patterns from existing codebase:

### Existing Drag Detection (current, unchanged)
```dart
// Source: lib/src/widgets/ai_chat_scroll_view.dart line 171-174
NotificationListener<ScrollUpdateNotification>(
  onNotification: (notification) {
    if (notification.dragDetails != null && _anchorActive) {
      _anchorActive = false;  // Phase 7: replace with controller.onUserScrolled()
    }
    return false;
  },
```

### Existing Compensation (current, to be state-gated)
```dart
// Source: lib/src/widgets/ai_chat_scroll_view.dart line 151-164
void _onMetricsChanged(ScrollMetricsNotification notification) {
  if (!_anchorActive || !_scrollController.hasClients) return;  // Phase 7: replace _anchorActive
  final newMax = notification.metrics.maxScrollExtent;
  final delta = newMax - _lastMaxScrollExtent;
  if (delta > 0.5) {
    _lastMaxScrollExtent = newMax;
    final target = _scrollController.offset + delta;
    _scrollController.jumpTo(target.clamp(0.0, newMax));
  } else if (delta < -0.5) {
    _lastMaxScrollExtent = newMax;
  }
}
```

### Existing At-Bottom Check (current, correct sign convention)
```dart
// Source: lib/src/widgets/ai_chat_scroll_view.dart line 142-147
void _onScrollChanged() {
  if (!_scrollController.hasClients) return;
  final pos = _scrollController.position;
  final atBottom = pos.pixels <= widget.controller.atBottomThreshold;  // reverse=true convention
  widget.controller.updateIsAtBottom(atBottom);
}
```

### Controller `_transition()` (existing, reuse)
```dart
// Source: lib/src/controller/ai_chat_scroll_controller.dart line 79-83
void _transition(AiChatScrollState next) {
  if (_scrollState.value == next) return;
  _scrollState.value = next;
  notifyListeners();
}
```

### New `onUserScrolled()` Controller Method (to be added)
```dart
/// Called by [AiChatScrollView] when the user initiates a drag during streaming.
///
/// Transitions [scrollState] from [AiChatScrollState.streamingFollowing] to
/// [AiChatScrollState.streamingDetached]. No-op if not in streamingFollowing.
void onUserScrolled() {
  if (_scrollState.value == AiChatScrollState.streamingFollowing) {
    _transition(AiChatScrollState.streamingDetached);
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `bool _streaming` | `ValueNotifier<AiChatScrollState>` 5-state enum | Phase 6 (2026-03-17) | State-gating now possible without new booleans |
| `bool _anchorActive` (free-standing boolean) | Query `scrollState.value` in notification handlers | Phase 7 (this phase) | Eliminates boolean proliferation, fixes flickering |

**Deprecated/outdated:**
- `_anchorActive`: The boolean field in `_AiChatScrollViewState`. Phase 7 removes it entirely. All three use sites are replaced with `scrollState.value` checks.

## Open Questions

1. **`onStreamingStarted()` vs alternative naming**
   - What we know: CONTEXT.md says "View calls a new internal controller method" for submittedWaiting → streamingFollowing
   - What's unclear: Whether to name it `onStreamingStarted()`, `onFirstToken()`, or something else; whether it should be public or package-private
   - Recommendation: Name it `onContentGrowthDetected()` for precision, make it package-private (no leading underscore — Dart visibility is by library, not class). But this is explicitly Claude's discretion.

2. **Filler shrink during streamingFollowing**
   - What we know: CONTEXT.md says "Filler shrinks dynamically as AI response grows: filler = viewport - userMsg - aiResponse until filler reaches 0, then pure scroll compensation takes over"
   - What's unclear: The existing `_onMetricsChanged()` does NOT currently shrink the filler — it uses `jumpTo(offset+delta)` which moves the viewport, not shrinks the filler. These are two different mechanisms. The current streaming_filler_test.dart tests (ANCH-03/04) verify that filler DOES decrease and pixels stay the same — which implies filler-shrink path is already working via some route.
   - Recommendation: Read the filler-shrink tests carefully before implementation. The filler may be shrinking as a side-effect of the anchor measurement path, not as part of `_onMetricsChanged()`. Do not break the existing ANCH-03/04 tests.

3. **`_lastMaxScrollExtent` initialization timing**
   - What we know: Currently set in `_measureAndAnchor()` after anchor jump. If content grows before `_measureAndAnchor()` completes (multi-frame anchor chain), `_lastMaxScrollExtent` could be stale.
   - What's unclear: Whether this can cause a spurious large delta on the very first `streamingFollowing` compensation.
   - Recommendation: Reset `_lastMaxScrollExtent` at the point of state entry into `streamingFollowing` as a defensive measure.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK) |
| Config file | none — uses default `flutter test` runner |
| Quick run command | `flutter test test/auto_follow_test.dart --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOLLOW-01 | During streamingFollowing, jumpTo compensates each content delta | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-01"` | Wave 0 |
| FOLLOW-01b | No jumpTo fires when state is NOT streamingFollowing | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-01b"` | Wave 0 |
| FOLLOW-02 | Drag during streamingFollowing transitions to streamingDetached immediately | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-02"` | Wave 0 |
| FOLLOW-02b | No jumpTo fires after entering streamingDetached | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-02b"` | Wave 0 |
| FOLLOW-03 | Scrolling back to live bottom during streamingDetached resumes streamingFollowing | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-03"` | Wave 0 |
| FOLLOW-03b | Down-button (scrollToBottom) during streaming resumes streamingFollowing | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-03b"` | Wave 0 |
| REGRESS | All 42 previously-passing tests still pass | suite | `flutter test --no-pub` | Exists (42 passing) |

### Sampling Rate
- **Per task commit:** `flutter test test/auto_follow_test.dart --no-pub`
- **Per wave merge:** `flutter test --no-pub`
- **Phase gate:** Full suite green (42 + new FOLLOW tests) before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/auto_follow_test.dart` — covers FOLLOW-01, FOLLOW-02, FOLLOW-03 and sub-cases
- [ ] No additional fixtures needed — existing `buildTestWidget()` pattern from `anchor_behavior_test.dart` and `streaming_filler_test.dart` is the correct template

## Sources

### Primary (HIGH confidence)
- Direct source read: `lib/src/widgets/ai_chat_scroll_view.dart` — full current implementation
- Direct source read: `lib/src/controller/ai_chat_scroll_controller.dart` — full current implementation
- Direct source read: `lib/src/model/ai_chat_scroll_state.dart` — Phase 6 enum output
- Direct source read: `test/state_machine_test.dart`, `test/streaming_filler_test.dart`, `test/anchor_behavior_test.dart` — test patterns and existing coverage

### Secondary (MEDIUM confidence)
- Flutter SDK: `ScrollMetricsNotification`, `ScrollUpdateNotification.dragDetails` — standard Flutter scroll notification system behavior inferred from current working code and official Flutter docs knowledge

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; all mechanisms are live code already passing 42 tests
- Architecture: HIGH — all four patterns are derived directly from existing code with targeted changes documented
- Pitfalls: HIGH — each pitfall traced to specific lines in current implementation or known Flutter behavior

**Research date:** 2026-03-17
**Valid until:** 2026-06-17 (stable — Flutter scroll API changes infrequently; only invalidated by major Flutter release changing notification behavior)
