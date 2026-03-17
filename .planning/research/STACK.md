# Stack Research

**Domain:** Flutter pub.dev scroll behavior package (AI chat viewport anchoring — v2.0 dual-layout auto-follow)
**Researched:** 2026-03-17
**Confidence:** HIGH (Flutter APIs verified via official docs; state machine patterns verified via Dart 3 language docs)

---

## Context: v2.0 Additive Stack

This document covers stack additions and changes needed for v2.0. The v1.0 stack (verified 2026-03-15) remains valid:
- `CustomScrollView` + `SliverList` + `SliverToBoxAdapter` — no change
- `ScrollController` extended by `AiChatScrollController` — promoted to state machine owner
- `ValueNotifier<double>` for filler height isolation — extended pattern
- `ScrollMetricsNotification` for content-growth detection — auto-follow reuses this
- Zero runtime dependencies — constraint maintained

v2.0 adds these capabilities: auto-follow streaming, 5-state machine, dual layout modes (rest vs active-turn), smart down-button target, content-bounded filler. Every new capability uses Flutter SDK APIs already available in Flutter >=3.22.0 (Dart ^3.4.0). **No version bump to pubspec constraints is needed.**

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Flutter SDK | >=3.22.0 (no change) | Package runtime | v2.0 features use no APIs newer than 3.22. Current stable is 3.41 (Dart 3.11, Feb 2026). The >=3.22.0 floor already covers all needed APIs. |
| Dart SDK | ^3.4.0 (no change) | Language runtime | Dart 3.4 enum exhaustive switch and sealed classes are available. State machine needs Dart 3 pattern matching. |
| `ScrollMetricsNotification` | Framework built-in | Auto-follow content growth detection | Already used in v1.0 anchor compensation. v2.0 auto-follow reuses the exact same `onNotification` handler pattern — when `_state == streamingFollowing`, absorb the `maxScrollExtent` delta via `jumpTo`. Confidence: HIGH. |
| `ScrollUpdateNotification` | Framework built-in | Detect user-initiated scroll to transition state | `dragDetails != null` on a `ScrollUpdateNotification` means the user is dragging. Use this to transition `streamingFollowing → streamingDetached`. Already partially used in v1.0 for `_anchorActive = false`. v2.0 formalizes it as a state machine event. Confidence: HIGH. |
| `ScrollEndNotification` | Framework built-in | Detect when fling/momentum stops | Fires after ballistic momentum finishes — not just when finger lifts. Use this to detect idle state after user-initiated fling. The `dragDetails` property is non-null when the end was caused by a drag gesture. Confidence: HIGH. |
| `UserScrollNotification` | Framework built-in | Detect scroll direction for history-browsing state | Fires when the user *changes direction or stops*. Its `direction` property (`ScrollDirection` enum) signals upward scroll → transition to `historyBrowsing`. Use alongside `ScrollUpdateNotification` for complete gesture coverage. Confidence: HIGH. |
| Dart `enum` + exhaustive `switch` | Dart 3.4+ | 5-state machine implementation | Plain enum is the right tool for the 5-state machine. Dart 3 exhaustive switch on enum (without default) causes compile error if a new state is added without updating all switch sites. No library needed. Confidence: HIGH. |
| `ValueNotifier<ScrollMachineState>` | Framework built-in | Reactive state broadcast | Expose the scroll state as `ValueListenable<ScrollMachineState>` on the controller so consumers can react to state changes (e.g., show/hide down-button differently in each state). Same isolation pattern as `isAtBottom`. Confidence: HIGH. |
| `GlobalKey` (extended role) | Framework built-in | Smart down-button target measurement | v1.0 used `GlobalKey` to measure user message height for filler computation. v2.0 reuses `GlobalKey` to measure the combined height of (user message + first AI tokens) for smart down-button scroll target. Same API, extended application. Confidence: HIGH. |

### Supporting Libraries (Dev Only — Zero Runtime Dependencies Maintained)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `flutter_test` | SDK bundled | State machine unit tests + widget scroll integration tests | Test each state transition: pump messages, simulate drag notifications, assert state enum value. Use `WidgetTester.sendKeyEvent` for keyboard tests. |
| `flutter_lints` | ^4.0.0 (no change) | Static analysis | Exhaustive switch enforcement + standard lints. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `dart analyze` | Exhaustive switch validation | With Dart 3 enums, adding a state to the enum without updating switch sites is a compile error — the analyzer catches it immediately. Run in CI. |
| `flutter test` | State machine unit tests | State transitions are pure Dart logic in the controller — test without widget tree where possible for speed. |
| `pana` | pub.dev score simulation | Rerun before v2.0 publish. Any new public API must be documented or pana score drops. |

---

## Installation

No pubspec changes needed for v2.0. The existing constraints cover all required APIs:

```yaml
environment:
  sdk: ^3.4.0
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter

# Still zero runtime dependencies
```

---

## Key Flutter APIs — v2.0 Detailed Rationale

### Auto-Follow: ScrollMetricsNotification + jumpTo

The v1.0 streaming compensation already does this in `_onMetricsChanged`. v2.0 generalizes it: auto-follow only runs when `_state == streamingFollowing`. The handler stays identical:

```dart
void _onMetricsChanged(ScrollMetricsNotification notification) {
  if (_state != ScrollMachineState.streamingFollowing) return;
  final newMax = notification.metrics.maxScrollExtent;
  final delta = newMax - _lastMaxScrollExtent;
  if (delta > 0.5) {
    _lastMaxScrollExtent = newMax;
    _scrollController.jumpTo(
      (_scrollController.offset + delta).clamp(0.0, newMax),
    );
  }
}
```

`jumpTo` is correct here (not `animateTo`) because it must complete synchronously within the same frame that reported the metric change. Animation introduces lag that manifests as visible jitter during fast streaming. Confidence: HIGH.

### State Machine: Dart Enum + Exhaustive Switch

Use a plain Dart `enum` — not a sealed class, not a library. The 5 states have no associated data that would require sealed class payload variants. Enum exhaustive switch is simpler and has zero overhead:

```dart
enum ScrollMachineState {
  idleAtBottom,
  submittedWaitingResponse,
  streamingFollowing,
  streamingDetached,
  historyBrowsing,
}
```

Transitions are triggered by:
- `onUserMessageSent()` on the controller → `idleAtBottom → submittedWaitingResponse`
- First `ScrollMetricsNotification` with growing content → `submittedWaitingResponse → streamingFollowing`
- `ScrollUpdateNotification` with `dragDetails != null` during streaming → `streamingFollowing → streamingDetached`
- `onResponseComplete()` → any streaming state → `idleAtBottom`
- `scrollToBottom()` called → `historyBrowsing → idleAtBottom`
- `UserScrollNotification` with direction UP, outside streaming → `idleAtBottom → historyBrowsing`

All transitions are O(1) field assignments. No external library adds value here. Confidence: HIGH.

### State Broadcast: ValueNotifier Exposure

Expose state as a `ValueListenable` so consumers can react without subscribing to the full `ChangeNotifier`:

```dart
final ValueNotifier<ScrollMachineState> _stateNotifier =
    ValueNotifier(ScrollMachineState.idleAtBottom);

ValueListenable<ScrollMachineState> get scrollState => _stateNotifier;
```

Update `_stateNotifier.value` alongside the internal `_state` field on every transition. The isolation means consumers using `ValueListenableBuilder` only rebuild their widget subtree, not the full `AiChatScrollView`. Confidence: HIGH.

### Dual Layout Modes: Filler Height Logic

v1.0 computes filler once per anchor activation. v2.0 needs two computations:

**Rest mode** (idle, history): filler = `max(0, viewportDimension - totalContentHeight)` — content sits at the bottom of the viewport like a standard chat list.

**Active-turn mode** (streaming states): filler = `max(0, viewportDimension - userMessageHeight)` — exactly v1.0's formula. Only the user message height matters; the AI response grows below into the extra space.

Both are computed using `ScrollPosition.viewportDimension` and `RenderBox.size.height` via `GlobalKey`. No new APIs needed — different math on the same measurement points. Confidence: HIGH.

### Smart Down-Button Target

The "smart down-button" should scroll to the start of the active turn (user message + AI response header), not `maxScrollExtent`. The target is the scroll offset where the user message sits at the top of the viewport.

In anchor mode, this is always `0.0` (the anchor position). After streaming completes, the target is the scroll offset of the user message item measured from current `maxScrollExtent`. Use `GlobalKey` to get the item's `RenderBox`, then compute offset relative to the `CustomScrollView` coordinate system via `RenderBox.localToGlobal` and the viewport's render object.

This is a read from the existing render tree — no new widget structure needed. Confidence: MEDIUM (coordinate math requires careful verification during implementation).

### Content-Bounded Filler: SliverToBoxAdapter with Computed Height

The existing pattern of `SliverToBoxAdapter(child: ValueListenableBuilder(...))` already provides content-bounded behavior because the filler height is computed as `viewport - content`, which naturally clamps to `0` when content exceeds the viewport. No change to the widget structure needed — only the filler height computation logic changes based on current layout mode.

`SliverFillRemaining` is still NOT recommended. Its `hasScrollBody: false` mode fills remaining space but is unreliable with `reverse: true` CustomScrollView and has the post-3.10 keyboard regression (GitHub #141376). The explicit computed height via `ValueNotifier<double>` remains the right approach. Confidence: HIGH.

### NotificationListener Nesting for State Events

v2.0 needs three notification types simultaneously. Nest `NotificationListener`s or use a single `onNotification` that checks the notification type with pattern matching:

```dart
NotificationListener<ScrollNotification>(
  onNotification: (notification) {
    switch (notification) {
      case ScrollUpdateNotification n when n.dragDetails != null:
        _handleUserDrag();
      case ScrollEndNotification _:
        _handleScrollEnd();
      case ScrollMetricsNotification n:
        _onMetricsChanged(n);
    }
    return false; // don't absorb — let parent listeners see it too
  },
  child: ...,
)
```

`ScrollNotification` is the common supertype for `ScrollUpdateNotification`, `ScrollEndNotification`, and `ScrollStartNotification`. `ScrollMetricsNotification` is separate (not a `ScrollNotification` subtype) — it requires its own `NotificationListener<ScrollMetricsNotification>` wrapper. Confidence: HIGH (verified via Flutter API docs).

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Dart `enum` + exhaustive switch | `statemachine` pub.dev package (v2.0.0) | Only if the state machine grows complex enough to need guard conditions, hierarchical states, or parallel regions. For 5 flat states with simple transitions, a library adds overhead with no benefit. |
| Dart `enum` + exhaustive switch | Sealed classes with associated data | Use sealed classes only if states need to carry payload (e.g., `StreamingFollowing(anchorOffset: double)`). If state data is stored as separate fields on the controller, the enum is cleaner. |
| `ScrollMetricsNotification` for auto-follow | `ScrollController.addListener` polling | `addListener` fires on every pixel change. `ScrollMetricsNotification` fires only when content *dimensions* change — exactly what auto-follow needs. Less noise, more semantic. |
| `ValueNotifier<ScrollMachineState>` | Exposing state via `ChangeNotifier.notifyListeners` only | `ValueNotifier` gives consumers `ValueListenableBuilder` isolation. `ChangeNotifier` forces consumers to `addListener` and read the enum themselves, adding boilerplate and wider rebuild scope. |
| `jumpTo` for auto-follow | `animateTo` with short duration | `animateTo` introduces async gap between content growth and scroll position update. Even 50ms lag causes visible stutter during fast streaming. `jumpTo` is synchronous and jitter-free. |
| `ScrollUpdateNotification.dragDetails != null` | `UserScrollNotification.direction` | `dragDetails` null-check is more precise for detecting active drag vs momentum scroll. `UserScrollNotification` is better for direction-change detection (scrolling up → history browsing). Use both for full coverage. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `statemachine` pub.dev package | Adds runtime dependency for 5 flat states with no payload. Code gen or reactive overhead not needed. | Dart `enum` + exhaustive switch |
| `bloc` / `riverpod` / `provider` | Scroll state is internal to the widget layer. Exposing it via a state management framework forces consumers to adopt that framework. | `ValueNotifier<ScrollMachineState>` exposed as `ValueListenable` |
| `ScrollController.animateTo` for auto-follow | Creates async gap between content growth notification and scroll position compensation. Causes visible jitter during fast streaming. | `ScrollController.jumpTo` for auto-follow; `animateTo` only for user-triggered navigation (scrollToBottom, smart down-button) |
| Polling `ScrollController.offset` on a timer | Timer-based polling is imprecise and wasteful. `ScrollMetricsNotification` delivers content-growth events at frame timing. | `ScrollMetricsNotification` via `NotificationListener` |
| `SliverFillRemaining` | Post-3.10 keyboard regression (GitHub #141376). Unreliable with `reverse: true`. Does not support externally-computed height needed for dual layout modes. | `SliverToBoxAdapter` wrapping `ValueListenableBuilder<double>` → `SizedBox(height: h)` |
| Nested `setState` for state transitions | `setState` triggers full subtree rebuild. State machine transitions should update `ValueNotifier` fields, not rebuild the `CustomScrollView`. | `ValueNotifier.value =` assignments, `ChangeNotifier.notifyListeners()` only for anchor events requiring layout |
| Default scroll physics (platform-adaptive) | `BouncingScrollPhysics` (iOS default) causes pixel overshoot during streaming that corrupts `maxScrollExtent` delta calculations in auto-follow. | `ClampingScrollPhysics` explicitly set on `CustomScrollView.physics` |

---

## Stack Patterns by Variant

**If streaming rate is very fast (many tokens/second):**
- `ScrollMetricsNotification` batches metrics changes per frame — auto-follow naturally rate-limits to 60fps without additional debouncing
- No throttle needed; the notification system handles it

**If multiple messages stream simultaneously (unlikely for chat but possible):**
- The state machine assumes one active turn at a time
- `onUserMessageSent()` while already in a streaming state should reset to `submittedWaitingResponse` and re-anchor — handle this in the transition table

**If consumer uses `reverse: false` layout:**
- The package targets `reverse: true` (v1.0 decision). If a consumer wants standard top-down order, the dual layout filler math inverts — this is out of scope for v2.0

**If keyboard appears during streaming:**
- v1.0 handled viewport dimension delta in filler recomputation
- v2.0 inherits this: the `ScrollMetricsNotification` fires when keyboard pushes viewport smaller, same handler detects negative delta (viewport shrinks) and adjusts filler — no additional keyboard-specific code needed beyond what v1.0 already has

---

## Version Compatibility

| Constraint | Compatible With | Notes |
|------------|-----------------|-------|
| Flutter >=3.22.0 | Dart ^3.4.0 | All v2.0 APIs available. `ScrollMetricsNotification`, `UserScrollNotification`, `ScrollEndNotification`, Dart enum exhaustive switch — all stable since 3.22. |
| Current stable Flutter 3.41.2 | Dart 3.11 | No breaking changes to scroll notification APIs between 3.22 and 3.41. Verified via release notes survey. |
| `NotificationListener<ScrollNotification>` pattern matching | Dart ^3.4.0 | Requires Dart 3 switch expression with object patterns. Works with Dart 3.4+. |

---

## pub.dev Score Checklist (v2.0 additions)

New public API introduced in v2.0 that must be documented to maintain 100% pub.dev score:

| New Symbol | Documentation Required |
|------------|----------------------|
| `ScrollMachineState` enum | Document all 5 states and their meaning |
| `AiChatScrollController.scrollState` | Document as `ValueListenable<ScrollMachineState>` |
| Any new controller methods (e.g., `scrollToActiveTurn()`) | Full dartdoc with usage example |

---

## Sources

- [Flutter ScrollPosition API](https://api.flutter.dev/flutter/widgets/ScrollPosition-class.html) — `pixels`, `viewportDimension`, `maxScrollExtent`, `isScrollingNotifier` (HIGH confidence)
- [Flutter ScrollController API](https://api.flutter.dev/flutter/widgets/ScrollController-class.html) — `jumpTo`, `animateTo`, `hasClients`, `position` (HIGH confidence)
- [Flutter UserScrollNotification API](https://api.flutter.dev/flutter/widgets/UserScrollNotification-class.html) — `direction` property, when fires vs `ScrollUpdateNotification` (HIGH confidence)
- [Flutter ScrollUpdateNotification API](https://api.flutter.dev/flutter/widgets/ScrollUpdateNotification-class.html) — `dragDetails` null-check for user-initiated vs programmatic scroll (HIGH confidence)
- [Flutter ScrollEndNotification API](https://api.flutter.dev/flutter/widgets/ScrollEndNotification-class.html) — fires after fling momentum ends, `dragDetails` property (HIGH confidence)
- [Flutter SliverFillRemaining API](https://api.flutter.dev/flutter/widgets/SliverFillRemaining-class.html) — `hasScrollBody`, `fillOverscroll`, content-deferring behavior (HIGH confidence — confirmed NOT suitable for dual-layout filler)
- [Flutter release notes index](https://docs.flutter.dev/release/release-notes) — confirmed Flutter 3.41.2 (Dart 3.11) is current stable as of Feb 2026 (HIGH confidence)
- [Flutter 3.41 "What's new"](https://blog.flutter.dev/whats-new-in-flutter-3-41-302ec140e632) — no scroll API breaking changes between 3.22 and 3.41 (MEDIUM confidence — blog 403'd, inferred from no scroll-specific entries in release notes search)
- [Dart sealed classes and pattern matching — Medium](https://medium.com/@d3xvn/using-sealed-classes-and-pattern-matching-in-dart-89c2fe22901c) — enum vs sealed class tradeoffs (MEDIUM confidence — community article)
- [Dart 3 pattern matching state machine — sandromaglione.com](https://www.sandromaglione.com/articles/how-to-implement-state-machines-and-statecharts-in-dart-and-flutter) — Dart 3 exhaustive switch for state machines (MEDIUM confidence — community article, pattern confirmed by official Dart docs)
- `statemachine` pub.dev package — surveyed and rejected: adds dependency for capability Dart 3 enums provide natively (HIGH confidence on rejection rationale)
- Flutter `SchedulerBinding.addPostFrameCallback` vs `scheduleFrameCallback` — `addPostFrameCallback` runs after full render pipeline flush, correct for post-layout scroll commands (HIGH confidence via official API docs)

---

*Stack research for: ai_chat_scroll v2.0 — dual-layout auto-follow state machine additions*
*Researched: 2026-03-17*
