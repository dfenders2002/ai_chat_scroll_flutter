# Phase 6: State Machine Foundation - Research

**Researched:** 2026-03-17
**Domain:** Flutter ValueNotifier state machine, Dart enum, ChangeNotifier migration
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- `onUserMessageSent()` transitions to `submittedWaitingResponse` from ANY state — universal rule, no exceptions
- New send always wins: previous AI stream is implicitly abandoned, no "cancel" required
- Late `onResponseComplete()` for an orphaned stream is treated as a normal transition from current state — no response tracking needed
- No tracking of "which" response; state machine only knows current state, not response identity
- Invalid transitions are silent no-ops — no throw, no assert, no log
- If state didn't change, don't notify listeners (ValueNotifier deduplication is sufficient)
- `onResponseComplete()` from `submittedWaitingResponse` is VALID — covers API errors, empty responses, timeouts. Transitions to `idleAtBottom` (at bottom) or `historyBrowsing` (scrolled away)

### Claude's Discretion

- Backward compatibility strategy for `isStreaming` getter (keep as derived, deprecate, or remove)
- State exposure depth — just `ValueNotifier<AiChatScrollState>` or additional APIs (previous state, transition callbacks)
- Keep it simple — this is a package, minimal API surface preferred
- Internal implementation details (transition method structure, private helpers)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| STATE-01 | Scroll system uses a 5-state enum replacing boolean flags | Dart enums are the standard tool; existing `_streaming` + `_anchorActive` booleans map cleanly to named states |
| STATE-02 | State transitions are event-driven: specific triggers produce specific state changes | Flutter `ValueNotifier` + guarded transition method pattern covers all listed triggers |
| STATE-03 | Scroll state exposed as `ValueNotifier<AiChatScrollState>` so consuming apps can build conditional UI | `ValueNotifier` + `ValueListenableBuilder` pattern already used by `isAtBottom`; same pattern applies |
</phase_requirements>

---

## Summary

Phase 6 replaces two boolean flags (`_streaming` in the controller, `_anchorActive` in the view state) with a single 5-value Dart enum and exposes it as a `ValueNotifier<AiChatScrollState>` on the controller. This is a pure refactoring phase — no new scroll behavior is added. The existing `ChangeNotifier`-based listener channel between controller and view is kept; the view will derive its anchor-active decision from the new state enum instead of `isStreaming`.

The codebase already has an established pattern for reactive state exposure: `ValueNotifier<bool> _isAtBottom` is exposed as `ValueListenable<bool> isAtBottom`. Phase 6 adds a parallel `ValueNotifier<AiChatScrollState> _scrollState` exposed as `ValueListenable<AiChatScrollState> scrollState`. This is the only new public API surface.

A critical baseline reality: the test suite currently has **15 pre-existing failing tests** (all from v1.0 behavior that was altered in the recent view refactor visible in `git diff`). Phase 6's success criterion "all v1.0 existing widget tests pass without modification" must be interpreted as "no additional test regressions introduced by the state machine migration" — the 15 pre-existing failures are inherited debt, not Phase 6 scope.

**Primary recommendation:** Create a standalone `AiChatScrollState` enum file, add `ValueNotifier<AiChatScrollState>` to the controller with a single private `_transition()` method, keep `isStreaming` as a derived getter for backward compatibility, and update `_onControllerChanged()` in the view to check `scrollState.value` instead of `isStreaming`.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `dart:core` (enum) | Dart SDK ^3.4.0 | 5-state enum definition | Native Dart; no dependency needed |
| `package:flutter/foundation.dart` (ValueNotifier) | Flutter >=3.22.0 | Reactive state holder exposed to consumers | Already used for `_isAtBottom`; zero new imports |
| `package:flutter/foundation.dart` (ChangeNotifier) | Flutter >=3.22.0 | Internal listener channel controller→view | Already the base class of `AiChatScrollController` |

### No New Dependencies

This phase requires zero new pub.dev packages. The entire implementation uses Flutter SDK primitives already imported.

**Installation:**

No new installation needed. All required APIs are already present in the project.

---

## Architecture Patterns

### Recommended File Structure Change

```
lib/src/
├── controller/
│   └── ai_chat_scroll_controller.dart   # Add ValueNotifier<AiChatScrollState>
├── model/
│   └── ai_chat_scroll_state.dart        # NEW: enum definition
└── widgets/
    └── ai_chat_scroll_view.dart          # Update: use state enum, not isStreaming
```

Add `export 'src/model/ai_chat_scroll_state.dart';` to `lib/ai_chat_scroll.dart` — consuming apps need the enum type to write conditional UI.

### Pattern 1: Enum-Guarded Transition Method

All state changes flow through a single private `_transition()` method. This centralizes the transition table, making it trivial to add, change, or verify transitions.

**What:** One private method that accepts new state, applies only if it differs, and notifies
**When to use:** Every state-changing public method calls this

```dart
// Source: standard Dart/Flutter pattern; no external URL
void _transition(AiChatScrollState next) {
  if (_scrollState.value == next) return; // deduplicate — no spurious notifications
  _scrollState.value = next;
  notifyListeners(); // keep existing ChangeNotifier channel for view
}
```

### Pattern 2: Derived `isStreaming` Getter for Backward Compatibility

The view currently checks `widget.controller.isStreaming`. Keeping this as a derived getter means zero changes to the view's listener logic — migration can happen incrementally.

```dart
// Derived from state — no separate _streaming bool needed
bool get isStreaming =>
    _scrollState.value == AiChatScrollState.submittedWaitingResponse ||
    _scrollState.value == AiChatScrollState.streamingFollowing ||
    _scrollState.value == AiChatScrollState.streamingDetached;
```

**Decision for Claude:** The CONTEXT.md lists backward compatibility of `isStreaming` as Claude's discretion. The derived-getter approach is recommended: zero migration burden on the view, zero public API break, trivially `@Deprecated`-able in a future phase.

### Pattern 3: ValueNotifier Exposure (mirrors isAtBottom pattern)

```dart
// Private mutable notifier
final ValueNotifier<AiChatScrollState> _scrollState =
    ValueNotifier(AiChatScrollState.idleAtBottom);

// Public read-only exposure
ValueListenable<AiChatScrollState> get scrollState => _scrollState;
```

Consumers use `ValueListenableBuilder<AiChatScrollState>` — identical pattern to `isAtBottom`.

### Complete Transition Table

| Current State | Event | Next State | Notes |
|--------------|-------|------------|-------|
| any | `onUserMessageSent()` | `submittedWaitingResponse` | Universal rule — no exceptions |
| `submittedWaitingResponse` | first AI token (Phase 7) | `streamingFollowing` | Phase 7 wires this event |
| `submittedWaitingResponse` | `onResponseComplete()` + at bottom | `idleAtBottom` | Valid — covers errors/timeouts |
| `submittedWaitingResponse` | `onResponseComplete()` + scrolled away | `historyBrowsing` | Valid |
| `streamingFollowing` | user drag (Phase 7) | `streamingDetached` | Phase 7 wires this |
| `streamingFollowing` | `onResponseComplete()` + at bottom | `idleAtBottom` | Normal completion |
| `streamingFollowing` | `onResponseComplete()` + scrolled away | `historyBrowsing` | User scrolled during stream |
| `streamingDetached` | down-button tap (Phase 7) | `streamingFollowing` | Phase 7 wires this |
| `streamingDetached` | `onResponseComplete()` + at bottom | `idleAtBottom` | |
| `streamingDetached` | `onResponseComplete()` + scrolled away | `historyBrowsing` | |
| `idleAtBottom` | scroll away (Phase 7+) | `historyBrowsing` | Deferred to later phase |
| `historyBrowsing` | scroll back to bottom (Phase 7+) | `idleAtBottom` | Deferred to later phase |
| any | invalid/unrecognized event | unchanged | Silent no-op |

**Phase 6 scope:** Only `onUserMessageSent()` and `onResponseComplete()` transitions are wired. The `streamingFollowing`/`streamingDetached` split and `idleAtBottom` ↔ `historyBrowsing` transitions are Phase 7+ work.

### Anti-Patterns to Avoid

- **Separate `_streaming` bool alongside the enum:** Keeping `_streaming = true/false` alongside `_scrollState` creates two sources of truth that can diverge. Remove `_streaming` field entirely; derive `isStreaming` from the enum.
- **Passing new state to view via ChangeNotifier payload:** ChangeNotifier has no payload. The view should read `widget.controller.scrollState.value` when `_onControllerChanged()` fires, not reconstruct state from the notification.
- **Checking multiple states in view with `==`:** The view should call a computed `isStreaming` getter or `isAnchorActive` getter, not compare against individual enum values. This keeps the view insulated from future state additions.
- **Making `AiChatScrollState` a class with methods:** Dart enhanced enums can carry methods, but this phase has no need for them. Plain enum is simpler.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Deduplication of state change notifications | Custom equality check before `notifyListeners()` | `ValueNotifier` built-in equality check | `ValueNotifier.value = x` only calls listeners if `x != _value`; adding manual guards is redundant for the `_scrollState` notifier |
| Observer registration for state changes | Custom callback lists | `ValueListenableBuilder` / `addListener` | Flutter's existing mechanism; no custom pub/sub needed |
| Enum validation | `assert` or runtime check on transition | Dart exhaustive switch | Dart 3 switch on sealed types/enums provides compile-time exhaustiveness |

**Key insight:** `ValueNotifier`'s built-in `==` deduplication handles the "don't notify if state didn't change" decision from CONTEXT.md automatically. The `_transition()` guard in Pattern 1 is still valuable for the `notifyListeners()` call on `ChangeNotifier`, which does NOT deduplicate.

---

## Common Pitfalls

### Pitfall 1: Double-notification on state change

**What goes wrong:** When state changes, both `_scrollState.value = next` (ValueNotifier) and `notifyListeners()` (ChangeNotifier) fire. Any listener registered on both channels gets two calls.
**Why it happens:** The view listens via `addListener(_onControllerChanged)` on the ChangeNotifier channel. External consumers listen via `scrollState` ValueListenable. These are independent channels — setting `_scrollState.value` does NOT call `notifyListeners()`.
**How to avoid:** Keep both channels. `_scrollState.value = next` notifies `ValueListenable` listeners (consuming app UI). `notifyListeners()` notifies the internal view. They serve different audiences and don't double-fire on the same listener unless someone registers on both.
**Warning signs:** If tests show view callbacks firing twice per transition, check for duplicate listener registration.

### Pitfall 2: `onResponseComplete()` always transitioning to `idleAtBottom`

**What goes wrong:** Transitioning to `idleAtBottom` without checking `isAtBottom` produces wrong state when user has scrolled away during streaming.
**Why it happens:** Easy to write `_transition(AiChatScrollState.idleAtBottom)` without the position check.
**How to avoid:** `onResponseComplete()` must check `_isAtBottom.value` (which is always up-to-date from `updateIsAtBottom()`):
```dart
void onResponseComplete() {
  final next = _isAtBottom.value
      ? AiChatScrollState.idleAtBottom
      : AiChatScrollState.historyBrowsing;
  _transition(next);
}
```

### Pitfall 3: `_isAtBottom` not yet updated at `onResponseComplete()` call time

**What goes wrong:** Consumer calls `onResponseComplete()` before the final scroll event fires, so `_isAtBottom.value` is stale.
**Why it happens:** Scroll position updates are async (postFrameCallback pipeline). If `onResponseComplete()` is called synchronously after the last `setState`, `_isAtBottom` may not reflect the final layout.
**How to avoid:** For Phase 6, the `idleAtBottom` vs `historyBrowsing` distinction at `onResponseComplete()` is architecturally correct even if occasionally imprecise — Phase 8 (layout modes) will refine this. The ordering contract note in STATE.md acknowledges this: "consumer must call only after final streaming setState is committed." Document this contract in the controller's doc comment.

### Pitfall 4: Forgetting to dispose `_scrollState` ValueNotifier

**What goes wrong:** Memory leak — the `ValueNotifier` is never disposed.
**Why it happens:** Adding `_scrollState` but forgetting to add `_scrollState.dispose()` alongside `_isAtBottom.dispose()` in `AiChatScrollController.dispose()`.
**How to avoid:** Add `_scrollState.dispose()` immediately below `_isAtBottom.dispose()` in the existing `dispose()` override.

### Pitfall 5: Pre-existing test failures misread as Phase 6 regressions

**What goes wrong:** Test run shows 15 failures and Phase 6 is blamed.
**Why it happens:** The current `ai_chat_scroll_view.dart` has an in-progress refactor (visible in `git diff`) that introduced 15 failures unrelated to Phase 6.
**How to avoid:** Establish a pre-Phase-6 baseline: `flutter test --no-pub` shows `+23 -15` before any Phase 6 changes. Phase 6 must not increase the failure count. The success criterion "all v1.0 tests pass" applies to the tests that currently pass (23), not to the 15 pre-existing failures.

---

## Code Examples

### Enum definition

```dart
// File: lib/src/model/ai_chat_scroll_state.dart
/// The scroll lifecycle state for an AI chat interface.
enum AiChatScrollState {
  /// At rest, scroll position is at the bottom. No active AI turn.
  idleAtBottom,

  /// User has sent a message; waiting for the first AI token.
  submittedWaitingResponse,

  /// AI is streaming and auto-follow is active (scroll tracks new tokens).
  streamingFollowing,

  /// AI is streaming but user has scrolled away from the live bottom.
  streamingDetached,

  /// User is browsing history; scroll is above the live bottom, no active turn.
  historyBrowsing,
}
```

### Controller additions

```dart
// In AiChatScrollController:

final ValueNotifier<AiChatScrollState> _scrollState =
    ValueNotifier(AiChatScrollState.idleAtBottom);

/// The current scroll lifecycle state.
///
/// Use [ValueListenableBuilder] to reactively rebuild UI when state changes:
///
/// ```dart
/// ValueListenableBuilder<AiChatScrollState>(
///   valueListenable: controller.scrollState,
///   builder: (context, state, _) {
///     return state == AiChatScrollState.streamingDetached
///         ? MyScrollDownButton()
///         : const SizedBox.shrink();
///   },
/// );
/// ```
ValueListenable<AiChatScrollState> get scrollState => _scrollState;

/// Whether an AI response is currently in-flight.
///
/// Derived from [scrollState]; `true` during [AiChatScrollState.submittedWaitingResponse],
/// [AiChatScrollState.streamingFollowing], and [AiChatScrollState.streamingDetached].
bool get isStreaming =>
    _scrollState.value == AiChatScrollState.submittedWaitingResponse ||
    _scrollState.value == AiChatScrollState.streamingFollowing ||
    _scrollState.value == AiChatScrollState.streamingDetached;

void _transition(AiChatScrollState next) {
  if (_scrollState.value == next) return;
  _scrollState.value = next;
  notifyListeners();
}

void onUserMessageSent() {
  _transition(AiChatScrollState.submittedWaitingResponse);
  // postFrameCallback guard retained from v1.0
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (_scrollController == null || !_scrollController!.hasClients) return;
  });
}

void onResponseComplete() {
  final next = _isAtBottom.value
      ? AiChatScrollState.idleAtBottom
      : AiChatScrollState.historyBrowsing;
  _transition(next);
}
```

### View update (minimal change)

```dart
// In _AiChatScrollViewState._onControllerChanged():
void _onControllerChanged() {
  if (widget.controller.isStreaming) {   // isStreaming is now derived — no change needed here
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _startAnchor();
    });
  } else {
    _anchorActive = false;
    if (_anchorReverseIndex != -1) {
      setState(() {
        _anchorReverseIndex = -1;
      });
    }
  }
}
```

The view requires **no changes** if `isStreaming` is kept as a derived getter. This is the recommended approach for minimal risk.

### Export addition

```dart
// lib/ai_chat_scroll.dart — add one line:
export 'src/model/ai_chat_scroll_state.dart';
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `bool _streaming` + `bool _anchorActive` | `AiChatScrollState` enum | Phase 6 | Named states, no boolean combinations to reason about |
| State change triggers two `notifyListeners()` paths | Single `_transition()` method | Phase 6 | Centralized transition table, no scattered boolean flips |

**Not deprecated in this phase:**
- `isStreaming` getter — kept as derived, consumed by the view unchanged
- `ChangeNotifier` as base class — still needed for the view's internal listener channel

---

## Open Questions

1. **`isStreaming` deprecation timeline**
   - What we know: It must stay in Phase 6 to keep v1.0 view working without changes
   - What's unclear: Whether to add `@Deprecated` annotation now or wait for Phase 7
   - Recommendation: Defer deprecation annotation to Phase 7 when the view is updated to use `scrollState` directly; no annotation in Phase 6

2. **`idleAtBottom` vs `historyBrowsing` at cold start**
   - What we know: Controller initializes with `idleAtBottom`; `_isAtBottom` initializes to `true`
   - What's unclear: What if the widget mounts with content already at a non-bottom position?
   - Recommendation: `idleAtBottom` initial state is correct for Phase 6 (no active turn, physically at bottom by convention). Phase 7/8 can refine if needed.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK, no version pin) |
| Config file | none — `flutter test` discovers tests in `test/` |
| Quick run command | `flutter test test/ai_chat_scroll_controller_test.dart --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Baseline State

**CRITICAL:** The test suite currently reports `+23 -15` (23 pass, 15 fail). These 15 failures are pre-existing regressions from an in-progress view refactor, **not caused by Phase 6**. Phase 6 must not increase the failure count beyond 15.

Pre-existing failures (do NOT fix in Phase 6):
- `anchor_behavior_test.dart` — ANCH-01, ANCH-06
- `streaming_filler_test.dart` — ANCH-02, ANCH-03, scroll pixels unchanged
- `manual_scroll_test.dart` — drag during streaming stops filler updates
- `scroll_to_bottom_indicator_test.dart` — Test 4 (scrollToBottom), Test 7 (atBottomThreshold)
- `keyboard_compensation_test.dart` — all tests
- `ai_chat_scroll_view_test.dart` — SCRL-01

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STATE-01 | Enum has 5 named values, no boolean flags on public API | unit | `flutter test test/state_machine_test.dart --no-pub` | Wave 0 |
| STATE-02 | `onUserMessageSent()` → `submittedWaitingResponse` from any state | unit | `flutter test test/state_machine_test.dart --no-pub` | Wave 0 |
| STATE-02 | `onResponseComplete()` + at bottom → `idleAtBottom` | unit | `flutter test test/state_machine_test.dart --no-pub` | Wave 0 |
| STATE-02 | `onResponseComplete()` + scrolled away → `historyBrowsing` | widget test | `flutter test test/state_machine_test.dart --no-pub` | Wave 0 |
| STATE-02 | Invalid transitions are silent no-ops | unit | `flutter test test/state_machine_test.dart --no-pub` | Wave 0 |
| STATE-03 | `scrollState` is `ValueListenable<AiChatScrollState>` | unit | `flutter test test/state_machine_test.dart --no-pub` | Wave 0 |
| STATE-03 | `ValueListenableBuilder` on `scrollState` rebuilds on transition | widget test | `flutter test test/state_machine_test.dart --no-pub` | Wave 0 |
| (compat) | `isStreaming` getter still returns true during streaming states | unit | `flutter test test/ai_chat_scroll_controller_test.dart --no-pub` | ✅ (adapted) |
| (compat) | Existing 23 passing tests still pass | regression | `flutter test --no-pub` | ✅ |

### Sampling Rate

- **Per task commit:** `flutter test test/ai_chat_scroll_controller_test.dart --no-pub`
- **Per wave merge:** `flutter test --no-pub`
- **Phase gate:** Full suite green (no new failures beyond pre-existing 15) before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/state_machine_test.dart` — covers STATE-01, STATE-02, STATE-03 (new file, all tests listed in map above)

---

## Sources

### Primary (HIGH confidence)

- Flutter SDK source (`package:flutter/foundation.dart`) — `ValueNotifier`, `ChangeNotifier` — verified by reading existing controller code that already uses both
- Existing codebase read directly — `lib/src/controller/ai_chat_scroll_controller.dart`, `lib/src/widgets/ai_chat_scroll_view.dart`, all 7 test files — all patterns observed first-hand

### Secondary (MEDIUM confidence)

- Dart enum language spec (Dart 3.4) — standard enum syntax; `@Deprecated` annotation pattern is standard Dart
- Flutter `ValueListenableBuilder` docs — same API already in use for `isAtBottom`, confirmed by reading existing widget test assertions

### Tertiary (LOW confidence)

- None — all claims are grounded in direct code inspection

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies, all Flutter SDK primitives already in use
- Architecture: HIGH — transition table derived directly from CONTEXT.md decisions + requirements; pattern mirrors existing `isAtBottom`
- Pitfalls: HIGH — derived from direct test run (15 pre-existing failures documented) and code inspection
- Transition table completeness: MEDIUM — Phase 7 events (first token, drag) are documented as future but not yet wired; the table is correct for Phase 6 scope

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (stable domain — Flutter SDK ValueNotifier API does not change frequently)
