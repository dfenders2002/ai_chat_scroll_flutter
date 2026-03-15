# Architecture Research

**Domain:** Flutter scroll behavior package (pub.dev)
**Researched:** 2026-03-15
**Confidence:** HIGH (Flutter scroll internals well-documented in official sources and megathink.com Flutter Internals)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Consumer App Layer                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  AiChatScrollView (wrapper widget)                       │   │
│  │  - Owns the CustomScrollView + SliverList composition   │   │
│  │  - Accepts AiChatScrollController from caller           │   │
│  │  - Exposes builder for message list items               │   │
│  └─────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│                    Package Public API Layer                      │
│  ┌──────────────────────────┐  ┌──────────────────────────┐    │
│  │  AiChatScrollController  │  │   AiChatScrollView        │    │
│  │  - onUserMessageSent()   │  │   - wraps CustomScrollView│    │
│  │  - onResponseComplete()  │  │   - manages slivers       │    │
│  │  - holds scroll state    │  │   - exposes item builder  │    │
│  └────────────┬─────────────┘  └──────────────┬───────────┘    │
│               │ references                      │ uses           │
│               └──────────────────┬─────────────┘               │
├──────────────────────────────────┼──────────────────────────────┤
│                    Package Internal Layer                        │
│  ┌───────────────────────────────┼───────────────┐             │
│  │  ScrollAnchorState            │               │             │
│  │  - _anchorIndex               │               │             │
│  │  - _fillerHeight              │               │             │
│  │  - _isStreaming flag          │               │             │
│  └───────────────────────────────┘               │             │
│  ┌───────────────────────────────────────────────┴──────────┐  │
│  │  FillerSliver (SliverToBoxAdapter)                        │  │
│  │  - AnimatedContainer or SizedBox with computed height    │  │
│  │  - grows/shrinks as AI response streams                  │  │
│  └──────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    Flutter Framework Layer                       │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ ScrollCtrl  │  │ ScrollPosition│  │  RenderViewport        │ │
│  │ (internal)  │  │ (pixels, max) │  │  center sliver anchor  │ │
│  └──────┬──────┘  └──────┬───────┘  └────────┬───────────────┘ │
│         │                │                    │                 │
│         └────────────────┴──── ViewportOffset ┘                 │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `AiChatScrollController` | Public API. Accepts application events (message sent, response complete). Computes target scroll pixel from anchor index. Drives jumpTo/animateTo on internal ScrollController. | Plain Dart class extending `ChangeNotifier`. Holds reference to internal `ScrollController`. Does NOT subclass `ScrollController` — delegates instead. |
| `AiChatScrollView` | Wrapper widget. Owns the sliver composition. Listens to `AiChatScrollController` changes and rebuilds filler. Provides the `ScrollController` to Flutter's scroll machinery. | `StatefulWidget`. Creates internal `ScrollController` in `initState`. Passes controller to `CustomScrollView`. |
| `ScrollAnchorState` | Internal mutable state: which message index is anchored, whether streaming is active, filler height. | Private class or fields on `_AiChatScrollViewState`. Not exposed in public API. |
| `FillerSliver` | A synthetic sliver that occupies vertical space below the anchor message so the anchor message sits at the top of viewport without being the last item. | `SliverToBoxAdapter` wrapping a `SizedBox` whose height is computed from viewport height minus remaining content height. |
| Internal `ScrollController` | Standard Flutter scroll controller owned by `AiChatScrollView`. Provides access to `ScrollPosition.pixels` and `maxScrollExtent` for computations. | `ScrollController()` — plain, no subclassing required. |
| `ScrollPosition` (Flutter) | Manages current offset in pixels, minScrollExtent, maxScrollExtent. Notified when content dimensions change. | Flutter framework — not modified. |
| `RenderViewport` (Flutter) | Lays out slivers. Tracks `center` sliver as coordinate origin. `anchor` param shifts where offset=0 appears. | Flutter framework — used via `CustomScrollView.anchor`. |

## Recommended Project Structure

```
lib/
├── ai_chat_scroll.dart              # Public barrel: exports controller + view widget only
└── src/
    ├── controller/
    │   └── ai_chat_scroll_controller.dart   # AiChatScrollController (ChangeNotifier)
    ├── widgets/
    │   ├── ai_chat_scroll_view.dart         # AiChatScrollView (StatefulWidget)
    │   └── filler_sliver.dart               # Internal sliver for filler space
    ├── models/
    │   └── scroll_anchor_state.dart         # Value object: anchor index, filler height, streaming
    └── utils/
        └── viewport_math.dart               # Pure functions: filler height calculation
example/
├── lib/
│   └── main.dart                    # Minimal demo: counter messages + simulated streaming
├── pubspec.yaml
└── README.md
test/
├── controller_test.dart
├── filler_calculation_test.dart
└── widget_test.dart
pubspec.yaml
README.md
LICENSE
CHANGELOG.md
```

### Structure Rationale

- **`lib/ai_chat_scroll.dart` (barrel):** Only this file is public. Everything under `lib/src/` is private implementation. Consumers do `import 'package:ai_chat_scroll/ai_chat_scroll.dart'` and see only `AiChatScrollController` and `AiChatScrollView`.
- **`src/controller/`:** Separated from widgets so it can be tested without Flutter widget test harness. Pure Dart logic lives here.
- **`src/widgets/`:** Two widgets: the main view and the internal filler sliver. Filler is its own file because filler height calculation is non-trivial and benefits from isolation.
- **`src/utils/viewport_math.dart`:** Pure functions for computing filler height — unit-testable without a widget tree.
- **`example/`:** pub.dev requires a working example. Keep it minimal: a fake message list + a simulated streaming ticker.

## Architectural Patterns

### Pattern 1: Delegate, Don't Subclass ScrollController

**What:** `AiChatScrollController` holds an internal `ScrollController` as a private field and calls `jumpTo`/`animateTo` on it. It does not extend `ScrollController`.

**When to use:** When the package needs a clean, domain-specific API (`onUserMessageSent`, `onResponseComplete`) without exposing raw scroll primitives to callers.

**Trade-offs:** Requires the internal controller to be wired up at widget creation time (passed from `AiChatScrollView` to `AiChatScrollController` after the widget mounts). Slightly more complex initialization, but results in a cleaner public API.

**Example:**
```dart
class AiChatScrollController extends ChangeNotifier {
  ScrollController? _scrollController; // injected by AiChatScrollView

  // Called by AiChatScrollView during initState
  void attach(ScrollController scrollController) {
    _scrollController = scrollController;
  }

  void onUserMessageSent(int anchoredMessageIndex) {
    // compute target pixel offset for anchoredMessageIndex
    // then:
    _scrollController?.jumpTo(targetPixels);
    notifyListeners();
  }
}
```

### Pattern 2: CustomScrollView with Dual-Sliver Composition for Top Anchoring

**What:** Use `CustomScrollView` with a forward-growing `SliverList` (message list, newest at top) and a `SliverToBoxAdapter` filler below the anchor message. The filler fills exactly enough space so the anchor message rests at the top of the viewport.

**When to use:** This is the core pattern for the top-anchor-on-send behavior. It avoids fighting `ListView(reverse: true)` physics and gives explicit control over where content appears.

**Trade-offs:** Requires computing filler height manually (viewport height - content height below anchor). Content dimension changes during streaming require filler to be recomputed. Layout callbacks (`LayoutBuilder` or `RenderObject` measurements) are needed.

**Example:**
```dart
CustomScrollView(
  controller: _internalScrollController,
  slivers: [
    SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => widget.itemBuilder(context, index),
        childCount: widget.itemCount,
      ),
    ),
    // Filler sliver: computed height so anchor message sits at top
    SliverToBoxAdapter(
      child: SizedBox(height: _fillerHeight),
    ),
  ],
)
```

### Pattern 3: Filler Height Computation via LayoutBuilder + ScrollMetrics

**What:** After a user sends a message, measure the remaining visible space below the anchor message using `ScrollPosition.viewportDimension` and accumulated item heights (or `RenderObject` coordinates). Set the filler height to `max(0, viewportHeight - contentBelowAnchor)`.

**When to use:** Whenever anchoring fires (`onUserMessageSent`). Filler must be recomputed each time the AI response grows during streaming, because growing content shrinks the required filler.

**Trade-offs:** Item height measurement is imperfect without explicit `RenderBox` lookups. For items with unknown heights, a `GlobalKey` per message (or a measurement-first pass) is needed. This is the principal complexity of the package.

**Example:**
```dart
double _computeFillerHeight({
  required double viewportHeight,
  required double contentHeightBelowAnchor,
}) {
  return math.max(0.0, viewportHeight - contentHeightBelowAnchor);
}
```

### Pattern 4: ChangeNotifier Controller Attached via Widget Lifecycle

**What:** `AiChatScrollView.initState` creates the internal `ScrollController`, then calls `widget.controller.attach(_internalScrollController)`. On `dispose`, it calls `widget.controller.detach()` and disposes the internal controller.

**When to use:** Mirrors Flutter's own controller-widget attachment pattern (same as `TextEditingController` with `TextField`). Familiar to Flutter developers.

**Trade-offs:** The controller is inert until a widget mounts. If the caller calls `onUserMessageSent` before mounting, it should no-op gracefully rather than throw.

## Data Flow

### On User Message Sent

```
App calls controller.onUserMessageSent(messageIndex)
    ↓
AiChatScrollController computes targetPixels
  (using _scrollController.position.pixels + offset to anchor)
    ↓
_scrollController.jumpTo(targetPixels)
    ↓
ScrollPosition.pixels updates → RenderViewport re-lays-out slivers
    ↓
AiChatScrollController notifyListeners()
    ↓
_AiChatScrollViewState rebuilds filler SizedBox with new _fillerHeight
    ↓
Viewport settles: anchor message at top, filler occupies remaining space
```

### During AI Response Streaming

```
App setState() adds tokens to last message → widget rebuilds
    ↓
SliverList child for last message grows in height
    ↓
Content height below anchor increases
    ↓
Filler height must shrink to compensate (or scroll offset absorbs it)
    ↓
Controller listens to _scrollController (addListener) for position changes
    ↓
Recomputes _fillerHeight → setState → filler SizedBox shrinks
    ↓
Viewport stays stable: anchor message remains at top
```

### On Response Complete

```
App calls controller.onResponseComplete()
    ↓
AiChatScrollController clears streaming flag
    ↓
Filler height final value locked (no further recomputation)
    ↓
User may scroll freely — no forced anchoring
```

### Key Data Flows Summary

1. **App → Controller → ScrollController → Flutter framework:** Application events drive scroll position changes. The framework is never touched directly by callers.
2. **Flutter framework → Controller → Widget state:** `ScrollPosition` changes (dimension updates during streaming) flow back to the controller's listener, which triggers filler recomputation.
3. **Widget state → Sliver tree:** `_fillerHeight` in `_AiChatScrollViewState` is the single source of truth that drives the filler `SizedBox`. Only one `setState` path modifies it.

## Scaling Considerations

This package has no backend or user scale — "scale" means message count and streaming frequency.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| <100 messages | Default `SliverList` with `SliverChildBuilderDelegate` — lazy building handles this fine |
| 100-1000 messages | Same — Flutter's sliver lazy-building only renders visible items; no changes needed |
| 1000+ messages | Consider `SliverList.builder` with item extent hints if items have uniform height. Non-uniform heights will still work but layout passes are more expensive. |

### Scaling Priorities

1. **First bottleneck:** Item height measurement during anchoring. If items have variable heights, the package must accumulate heights or use `RenderBox` lookups. This is a correctness concern, not just performance.
2. **Second bottleneck:** Rapid streaming (many tokens/sec) causing many `setState` calls to update filler height. Debounce or throttle filler recomputation to one update per frame using `SchedulerBinding.addPostFrameCallback`.

## Anti-Patterns

### Anti-Pattern 1: Using ListView(reverse: true) as the Foundation

**What people do:** Build the anchor behavior on top of `ListView(reverse: true)`, then try to fight the reversed coordinate system to get top-anchoring.

**Why it's wrong:** `reverse: true` flips the scroll axis, meaning scroll offset 0 is at the bottom. Anchoring a message to the "top" requires computing a position in an inverted system. Every new item added below the anchor shifts the offset, requiring constant correction. The physics fights you at every step.

**Do this instead:** Use a forward-growing `CustomScrollView` (default `reverse: false`) with explicit filler management. The coordinate system stays intuitive: offset 0 is the top, and the anchor message is positioned there by jumping to 0 after filler is set.

### Anti-Pattern 2: Subclassing ScrollController for Domain Logic

**What people do:** `class AiChatScrollController extends ScrollController` to add `onUserMessageSent()` directly.

**Why it's wrong:** `ScrollController` is tightly coupled to widget lifecycle (attach/detach). Subclassing exposes all raw scroll methods (`animateTo`, `jumpTo`, `position`) to callers who shouldn't need them. It conflates domain logic with framework infrastructure.

**Do this instead:** `AiChatScrollController extends ChangeNotifier`, owns a private `ScrollController`, and exposes only domain methods. This is the pattern used by `scrollable_positioned_list`'s `ItemScrollController`.

### Anti-Pattern 3: GlobalKey per Message for Height Measurement

**What people do:** Attach a `GlobalKey` to every message widget to call `context.size` for height lookups during anchor computation.

**Why it's wrong:** `GlobalKey` instances are expensive (registered in a global map). With 1000+ messages, this creates observable overhead. Keys also cause widget identity issues if the list reorders.

**Do this instead:** Use `ScrollPosition.viewportDimension` and `ScrollPosition.extentAfter` for approximate filler computation. For exact item heights, maintain a `Map<int, double>` cache populated via `SizeChangedLayoutNotifier` or `LayoutBuilder` on individual items. Only measure what is visible.

### Anti-Pattern 4: Calling jumpTo Before the Widget Tree Settles

**What people do:** Call `controller.onUserMessageSent()` synchronously during `setState` (e.g., in the same frame as adding a message to the list).

**Why it's wrong:** The scroll position reflects the old content dimensions. `jumpTo` to the computed target lands in the wrong place because layout hasn't run yet.

**Do this instead:** Defer the scroll after adding the message using `WidgetsBinding.instance.addPostFrameCallback(() => controller.onUserMessageSent(...))`. This guarantees the sliver list has laid out the new item before the scroll offset is updated.

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `AiChatScrollController` ↔ `AiChatScrollView` | `attach(ScrollController)` / `detach()` called by widget lifecycle | Controller is inert before attach; must no-op if not attached |
| `AiChatScrollController` ↔ App | `onUserMessageSent(int index)`, `onResponseComplete()` — caller-facing methods | App should wrap these in `addPostFrameCallback` if calling during build |
| `_AiChatScrollViewState` ↔ `FillerSliver` | `_fillerHeight` state variable → `SizedBox.height` | Single source of truth; all filler updates go through one `setState` |
| Internal `ScrollController` ↔ Flutter framework | Standard Flutter attachment via `CustomScrollView.controller` | No modifications to framework scroll machinery |

### Key Flutter APIs Used (No Modifications)

| API | How Used |
|-----|----------|
| `ScrollController` | Owned internally, drives `jumpTo`/`animateTo` |
| `ScrollPosition.pixels` | Read to compute anchor target offset |
| `ScrollPosition.viewportDimension` | Read to compute filler height |
| `ScrollPosition.extentAfter` | Read to know how much content is below current position |
| `CustomScrollView` | Host for sliver composition; `controller` wired to internal `ScrollController` |
| `SliverList` with `SliverChildBuilderDelegate` | Lazy message list |
| `SliverToBoxAdapter` | Wraps filler `SizedBox` |
| `WidgetsBinding.addPostFrameCallback` | Defers scroll after layout |

## Build Order (Phase Dependencies)

The architecture has a clear dependency chain that drives implementation order:

```
1. Package scaffold + barrel export
        ↓
2. AiChatScrollController (ChangeNotifier, no UI dependencies)
   → Unit-testable in isolation
        ↓
3. Internal ScrollController wiring + attach/detach lifecycle
   → Integration-testable with a minimal scrollable
        ↓
4. AiChatScrollView + SliverList composition (forward-growing, no filler yet)
   → Validates basic rendering
        ↓
5. Filler sliver + height computation (viewport math)
   → Validates anchor positioning without streaming
        ↓
6. Streaming simulation: filler shrinks as content grows
   → Validates stable anchor during dynamic content
        ↓
7. Edge cases: scroll to history then re-anchor, empty list, single message
        ↓
8. Example app + pub.dev publication structure
```

**Rationale for this order:** Controller logic (step 2-3) must be solid before the widget depends on it. Filler computation (step 5) depends on a working sliver list (step 4) to have real viewport dimensions to measure against. Streaming behavior (step 6) is a superset of static anchoring (step 5) — validate simpler case first.

## Sources

- [Flutter Internals — Viewports](https://flutter.megathink.com/scrolling/viewports) — CENTER sliver anchor, RenderViewport architecture (HIGH confidence)
- [Flutter Internals — Scrollable](https://flutter.megathink.com/scrolling/scrollable) — ScrollController/ScrollPosition/ViewportOffset relationships (HIGH confidence)
- [ScrollController class — Dart API](https://api.flutter.dev/flutter/widgets/ScrollController-class.html) — createScrollPosition, attach/detach, positions (HIGH confidence)
- [ScrollPosition class — Dart API](https://api.flutter.dev/flutter/widgets/ScrollPosition-class.html) — pixels, viewportDimension, extentAfter, correctPixels (HIGH confidence)
- [CustomScrollView class — Dart API](https://api.flutter.dev/flutter/widgets/CustomScrollView-class.html) — center, anchor params, dual-SliverList pattern (HIGH confidence)
- [SliverFillRemaining class — Dart API](https://api.flutter.dev/flutter/widgets/SliverFillRemaining-class.html) — hasScrollBody, fillOverscroll behavior (HIGH confidence)
- [scrollable_positioned_list — pub.dev](https://pub.dev/packages/scrollable_positioned_list) — ItemScrollController delegation pattern (MEDIUM confidence, via package docs)
- [Dart Package Layout Conventions](https://dart.dev/tools/pub/package-layout) — lib/src structure, example directory (HIGH confidence)

---
*Architecture research for: Flutter AI chat scroll package (ai_chat_scroll)*
*Researched: 2026-03-15*
