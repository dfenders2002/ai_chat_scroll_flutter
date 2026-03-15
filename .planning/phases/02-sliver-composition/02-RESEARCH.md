# Phase 2: Sliver Composition - Research

**Researched:** 2026-03-15
**Domain:** Flutter CustomScrollView / Sliver composition for chat UI
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| API-03 | Package exposes `AiChatScrollView` wrapper widget that devs wrap around their own message list | Widget API design section — builder pattern replaces `child:` stub |
| SCRL-01 | Chat displays messages in reverse-chronological order (newest at bottom, older above) | Data-layer reversal pattern, forward-growing CustomScrollView |
| SCRL-02 | No visible scroll jank when new messages are inserted into the list | Isolated FillerSliver via ValueNotifier, SliverList lazy delegate, flutter/flutter#143687 mitigation |
| SCRL-03 | Scroll position is preserved when user has scrolled up into message history | Forward coordinate system + jank-free insertion; no automatic `jumpTo` on insert |
| SCRL-04 | Works correctly on both iOS (bouncing physics) and Android (clamping physics) | Physics inheritance pattern — do not hardcode, inherit from ambient ScrollConfiguration |
</phase_requirements>

---

## Summary

Phase 2 replaces the Phase 1 `child: Widget` stub in `AiChatScrollView` with a real sliver composition: a forward-growing `CustomScrollView` containing a `SliverList.builder` for messages and a `SliverToBoxAdapter`-wrapped filler `SizedBox` whose height is driven by a `ValueNotifier<double>`. The filler is a placeholder for Phase 3 anchor logic — in Phase 2 it is always zero height, but the infrastructure is isolated so Phase 3 can drive it without touching the list.

The key architectural decision resolved by this phase is the public API shape of `AiChatScrollView`: move from `child: Widget` to an `itemBuilder` + `itemCount` pair. This gives `AiChatScrollView` ownership of the `CustomScrollView` rather than wrapping an externally-created list, which is the prerequisite for all sliver composition work. The switch is a breaking change to the stub API and must happen now, before any consumer tests depend on the `child:` signature.

Reverse-chronological display (newest at bottom) is achieved by reversing the data layer (pass messages in reverse order to `itemBuilder`) while keeping the scroll coordinate system forward-growing (`reverse: false`). This is the pattern confirmed by both the prior research and the Flutter `CustomScrollView` docs for chat UIs. Scroll physics are inherited from the ambient `ScrollConfiguration` — the package must not hardcode `BouncingScrollPhysics` or `ClampingScrollPhysics`, as this would override the consuming app's own scroll behavior.

**Primary recommendation:** Replace `child: Widget` with `itemBuilder`/`itemCount`, compose `CustomScrollView` + `SliverList.builder` + `SliverToBoxAdapter(FillerSliver)`, isolate filler via `ValueNotifier<double>`, inherit scroll physics from ambient configuration.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `CustomScrollView` | Flutter SDK | Host for sliver composition | Enables heterogeneous slivers (list + filler) in a single scroll context |
| `SliverList.builder` | Flutter SDK | Lazy message list | Only materialises visible items; correct delegate for dynamic-length chat lists |
| `SliverToBoxAdapter` | Flutter SDK | Wraps filler `SizedBox` | Correct sliver type for a single non-list box; avoids `SliverFillRemaining` regression |
| `ValueNotifier<double>` | Flutter SDK | Filler height source of truth | Allows filler to update without rebuilding the message list |
| `ValueListenableBuilder<double>` | Flutter SDK | Filler sliver widget | Rebuilds only the `SizedBox`, not the list |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `ScrollConfiguration` | Flutter SDK | Ambient physics inheritance | Read in `build()` to confirm no physics override is needed |
| `SliverChildBuilderDelegate` | Flutter SDK | Alternative to `SliverList.builder` | Use `.builder` named constructor instead — cleaner API |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `SliverList.builder` | `SliverFixedExtentList.builder` | Fixed extent is more efficient but requires uniform item height — message bubbles are variable height, so cannot use |
| `SliverToBoxAdapter` | `SliverFillRemaining` | `SliverFillRemaining` has a post-3.10 keyboard regression (flutter/flutter#141376) and does not support dynamic height; never use for this pattern |
| `ValueNotifier` filler isolation | `setState` on `_AiChatScrollViewState` | `setState` rebuilds the entire widget including `SliverList`; triggers the all-items-rebuild bug (flutter/flutter#143687); unacceptable for 50+ messages |

**Installation:** No new packages — all from the Flutter SDK.

---

## Architecture Patterns

### Recommended Project Structure

```
lib/src/
├── controller/
│   └── ai_chat_scroll_controller.dart   # Unchanged from Phase 1
└── widgets/
    ├── ai_chat_scroll_view.dart         # MODIFIED: child -> itemBuilder/itemCount, real sliver composition
    └── filler_sliver.dart               # NEW: isolated FillerSliver widget
```

Phase 2 adds one file (`filler_sliver.dart`) and modifies one file (`ai_chat_scroll_view.dart`). The controller is untouched.

---

### Pattern 1: Builder API for AiChatScrollView (Breaking Change from Stub)

**What:** Replace `child: Widget` with `itemBuilder: IndexedWidgetBuilder` + `itemCount: int`. `AiChatScrollView` constructs the `CustomScrollView` internally. Consumers pass a builder closure.

**When to use:** Always. This is the only API that gives the package ownership of the scroll hierarchy.

**Why now:** Deferring to Phase 3 would require changing an API that has already been used in tests. Doing it in Phase 2 limits the breaking surface to the stub.

**Existing test impact:** The Phase 1 test uses `child: const SizedBox()`. This must be updated to `itemBuilder: (_, __) => const SizedBox.shrink(), itemCount: 0` (or equivalent) as part of this phase's work.

```dart
// Source: architecture decision confirmed by ARCHITECTURE.md + STACK.md
class AiChatScrollView extends StatefulWidget {
  const AiChatScrollView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.itemCount,
  });

  final AiChatScrollController controller;
  final IndexedWidgetBuilder itemBuilder;
  final int itemCount;

  @override
  State<AiChatScrollView> createState() => _AiChatScrollViewState();
}
```

---

### Pattern 2: Forward-Growing CustomScrollView with Dual Sliver Children

**What:** `CustomScrollView` with `reverse: false` (default) containing two slivers: a `SliverList.builder` for messages and a `SliverToBoxAdapter` for the filler. Messages are passed in reverse order by the caller (index 0 = newest message), so the newest message appears at the bottom of the visual list.

**When to use:** This is the sole rendering strategy for Phase 2 and beyond. Do not add `reverse: true`.

**Why forward-growing:** Forward coordinate system (`pixels = 0` at top) makes anchor math trivial in Phase 3. Reversed coordinate systems require computing large offsets that shift every time content is added.

**Reverse-chronological order:** The consuming app passes its `messages` list in reverse order (newest first at index 0). `AiChatScrollView` renders index 0 at the top of the `SliverList`, which visually appears at the bottom of the viewport when scrolled to the end. This is the same data-layer reversal pattern used by production Flutter chat packages.

```dart
// Source: architecture confirmed by ARCHITECTURE.md Pattern 2, STACK.md
@override
Widget build(BuildContext context) {
  return CustomScrollView(
    controller: _scrollController,
    slivers: [
      SliverList.builder(
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      ),
      // Filler: isolated from list rebuilds via ValueNotifier
      SliverToBoxAdapter(
        child: FillerSliver(fillerHeight: _fillerHeight),
      ),
    ],
  );
}
```

---

### Pattern 3: Isolated FillerSliver via ValueNotifier

**What:** `_fillerHeight` is a `ValueNotifier<double>` on `_AiChatScrollViewState`. Its value is `0.0` in Phase 2. `FillerSliver` is a minimal `StatelessWidget` that uses `ValueListenableBuilder` to rebuild only the inner `SizedBox` when the notifier fires.

**When to use:** Always. The isolation is architectural, not an optimisation to add later. Retrofitting it after streaming is implemented requires invasive refactoring.

**Why this matters for Phase 2 even though filler is 0:** The `ValueNotifier` wire-up is established in Phase 2 so Phase 3 can simply call `_fillerHeight.value = computed` without touching the sliver tree or `setState`.

```dart
// Source: PITFALLS.md Pitfall 3, confirmed by ARCHITECTURE.md Pattern 3
class FillerSliver extends StatelessWidget {
  const FillerSliver({super.key, required this.fillerHeight});

  final ValueNotifier<double> fillerHeight;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fillerHeight,
      builder: (context, height, _) => SizedBox(height: height),
    );
  }
}
```

---

### Pattern 4: Scroll Physics Inheritance (Do Not Override)

**What:** Pass no `physics:` argument to `CustomScrollView`. Let the ambient `ScrollConfiguration` determine physics. This results in `BouncingScrollPhysics` on iOS and `ClampingScrollPhysics` on Android automatically.

**When to use:** Always in Phase 2. Phase 3 may need to suppress iOS bounce during anchor snap — that is a Phase 3 concern. For Phase 2, physics inheritance is correct.

**Why not hardcode:** Hardcoding `ClampingScrollPhysics` or `BouncingScrollPhysics` would override the consuming app's `ScrollBehavior`, causing surprising behavior for apps that customise scroll physics at the top level.

```dart
// Source: STACK.md Alternatives Considered, PITFALLS.md Integration Gotchas
CustomScrollView(
  controller: _scrollController,
  // No physics: — inherits from ambient ScrollConfiguration
  slivers: [ ... ],
)
```

---

### Pattern 5: Scroll Position Preserved on Insertion (No Automatic jumpTo)

**What:** When a new message is inserted (`itemCount` increases), the package does nothing — no `jumpTo`, no `scrollTo`. The `CustomScrollView` with a forward-growing coordinate system naturally preserves the user's current pixel offset because the new item is appended at the end of the list (highest index in data layer = oldest message = top of visual list, but from the consumer's reversed data, new message is at index 0).

**Critical clarification:** Because the consumer reverses their data list (newest at index 0), a new message is added at index 0. This shifts all existing items down by one index, which in a forward-growing list pushes all content down — visually appearing to push older messages upward. This is the expected chat UI behavior: existing messages stay in place while the new message appears below them.

However, this means the scroll offset will shift if the user is mid-list. The correct Phase 2 behavior is: if the user is at the bottom (scrolled to `maxScrollExtent`), the new message appears below the viewport and the user must scroll down (or Phase 3 anchor will jump them). If the user has scrolled up into history, the offset is preserved and they see no jump.

**This is SCRL-03 compliance:** Position is preserved because we do not call `jumpTo` on insertion. The consumer is responsible for adding the message to their state; the package renders passively.

---

### Anti-Patterns to Avoid

- **Do not use `reverse: true` on `CustomScrollView`:** Prior research established this fights the anchor math and produces scroll offset drift on every insertion. Already documented in STACK.md and PITFALLS.md.
- **Do not wrap the whole `CustomScrollView` in `setState` to update filler:** This triggers a rebuild of all `SliverList` children due to flutter/flutter#143687 (cacheExtent-independent full rebuild on SliverList item insertion). Use `ValueNotifier` only.
- **Do not call `_scrollController.jumpTo()` during Phase 2:** Phase 2 is passive rendering. Anchor behavior is Phase 3. Any scroll position manipulation in Phase 2 would conflict with Phase 3.
- **Do not pass `physics:` to `CustomScrollView`:** See Pattern 4. Let the ambient `ScrollConfiguration` resolve physics.
- **Do not use `GlobalKey` on individual message items in Phase 2:** Phase 2 does not require item height measurement. Phase 3 will decide the measurement strategy (SizeChangedLayoutNotifier vs height cache map). Do not introduce GlobalKey patterns early.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Lazy list rendering | Custom `ListView` subclass | `SliverList.builder` | Built-in lazy materialisation, correct sliver protocol, repaint boundary management |
| Filler space | Manual pixel calculations in `build()` | `SliverToBoxAdapter(child: SizedBox(height: value))` driven by `ValueNotifier` | Correct sliver geometry, avoids layout-during-build assertion |
| Physics selection by platform | `Platform.isIOS` check + explicit physics | No `physics:` arg — ambient `ScrollConfiguration` | Less error-prone, honours consumer app's theme, correct on all platforms including web/desktop in future |
| Scroll position notification | Custom `ScrollPhysics` subclass | `NotificationListener<ScrollMetricsNotification>` (for Phase 3) | Already documented in PITFALLS.md; correct for detecting extent changes, not just pixel changes |

**Key insight:** Flutter's sliver protocol handles lazy rendering, repaint boundaries, and geometry calculation internally. The package's job is composition, not reimplementation.

---

## Common Pitfalls

### Pitfall 1: Full List Rebuild on Filler Height Change (flutter/flutter#143687)

**What goes wrong:** If `_fillerHeight` is stored as a plain `double` in `_AiChatScrollViewState` and updated via `setState`, Flutter's `SliverList` rebuilds all children regardless of `cacheExtent`. On a 50-message list this causes frame drops visible in DevTools.

**Why it happens:** flutter/flutter#143687 — `CustomScrollView`/`SliverList` rebuilds all elements on insertion/state change, independent of `cacheExtent`. This is a known framework bug, not a configuration option.

**How to avoid:** Use `ValueNotifier<double>` + `ValueListenableBuilder` for the filler (Pattern 3). The `SliverList` builder is never touched when the filler changes.

**Warning signs:** Flutter DevTools "Rebuild Stats" shows all message items rebuilding when filler changes; frame times exceed 16ms during what should be a local update.

---

### Pitfall 2: Inserting at Index 0 Jumps Scroll Position

**What goes wrong:** When the consumer adds a new message at index 0 of their reversed list and calls `setState`, the `SliverList` content height grows. If the user is scrolled to the bottom, the new message pushes the previous content down — this looks like the viewport jumped up.

**Why it happens:** The new item is at the top of the sliver coordinate space (index 0). All existing items shift down, increasing `maxScrollExtent`. The current `pixels` value is now pointing to a different visual position.

**How to avoid:** This is expected behavior in Phase 2 and is the correct foundation for Phase 3. In Phase 2, the expected UX is: user at bottom sees the new message appear below their view (they need to scroll down), or Phase 3 anchor snaps them. If the user is mid-history, their position is preserved (SCRL-03). Do not attempt to compensate in Phase 2 — that is Phase 3 work.

**Warning signs in Phase 2 tests:** The test for SCRL-03 should verify that `_scrollController.position.pixels` does not change after inserting a message when the user is scrolled to mid-list. If it changes, something is calling `jumpTo` unintentionally.

---

### Pitfall 3: Existing Tests Break on child -> itemBuilder Migration

**What goes wrong:** The Phase 1 widget test creates `AiChatScrollView(controller: c, child: const SizedBox())`. After migrating to the `itemBuilder`/`itemCount` API, this test fails to compile.

**Why it happens:** The API is a breaking change to the stub. Phase 1 tests use `child:`.

**How to avoid:** Update the Phase 1 test file as part of Phase 2 work. The updated test should use `itemBuilder: (_, __) => const SizedBox.shrink(), itemCount: 0`. This is expected and planned. Do not add backwards compatibility shims — the `child:` API was explicitly documented as a temporary stub.

**Warning signs:** Compile error on `child:` named parameter after the migration. Fix by updating the test, not by keeping the old parameter.

---

### Pitfall 4: Physics Fighting Between Package and Consumer App

**What goes wrong:** Hardcoding `physics: ClampingScrollPhysics()` inside `CustomScrollView` overrides the consumer app's `MaterialApp`/`CupertinoApp` scroll behavior. On iOS this removes the bounce feel; on Android it has no effect but is still wrong.

**Why it happens:** Developers reach for explicit physics to "ensure correctness" without checking what the ambient `ScrollConfiguration` already provides.

**How to avoid:** Omit the `physics:` parameter entirely in Phase 2 (Pattern 4). Verify on both iOS Simulator (should bounce at edges) and Android Emulator (should clamp at edges) with no explicit physics parameter.

**Warning signs:** Consumer app developer reports that `AiChatScrollView` removes iOS bounce feel; or test on iOS simulator shows no overscroll animation.

---

## Code Examples

Verified patterns from official sources and prior research:

### AiChatScrollView Full Build Method (Phase 2)

```dart
// Source: ARCHITECTURE.md Pattern 2, STACK.md
@override
Widget build(BuildContext context) {
  return CustomScrollView(
    controller: _scrollController,
    // No physics: — inherits from ambient ScrollConfiguration (SCRL-04)
    slivers: [
      SliverList.builder(
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      ),
      SliverToBoxAdapter(
        child: FillerSliver(fillerHeight: _fillerHeight),
      ),
    ],
  );
}
```

### FillerSliver Widget

```dart
// Source: PITFALLS.md Pitfall 3 prevention pattern
/// Internal widget that renders the dynamic filler space.
///
/// Isolated from the message list to prevent full-list rebuilds
/// when filler height changes during AI streaming (Phase 3).
class FillerSliver extends StatelessWidget {
  const FillerSliver({super.key, required this.fillerHeight});

  final ValueNotifier<double> fillerHeight;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fillerHeight,
      builder: (context, height, _) => SizedBox(height: height),
    );
  }
}
```

### _AiChatScrollViewState initState with ValueNotifier

```dart
// Source: ARCHITECTURE.md Pattern 4 (controller lifecycle)
late final ScrollController _scrollController;
late final ValueNotifier<double> _fillerHeight;

@override
void initState() {
  super.initState();
  _scrollController = ScrollController();
  _fillerHeight = ValueNotifier(0.0);
  widget.controller.attach(_scrollController);
}

@override
void dispose() {
  widget.controller.detach();
  _fillerHeight.dispose();
  _scrollController.dispose();
  super.dispose();
}
```

### Updated Phase 1 Test Signature (Required Migration)

```dart
// Updated test — replaces child: const SizedBox() with builder API
await tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: AiChatScrollView(
      controller: controller,
      itemBuilder: (context, index) => const SizedBox.shrink(),
      itemCount: 0,
    ),
  ),
);
```

### Consumer Usage Pattern (for dartdoc example)

```dart
// Source: API-03 requirement — what a developer writes
AiChatScrollView(
  controller: myAiChatScrollController,
  itemCount: messages.length,
  // messages is reversed: messages[0] is newest, messages.last is oldest
  // CustomScrollView renders index 0 at the top of the sliver,
  // which appears at the bottom when scrolled to the end.
  itemBuilder: (context, index) => MessageBubble(messages[index]),
)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ListView(reverse: true)` for chat | Forward-growing `CustomScrollView` + reversed data | Pre-existing decision (STACK.md) | Correct coordinate system for anchor math |
| `SliverFillRemaining` for dynamic spacer | `SliverToBoxAdapter(child: SizedBox(height: computed))` | Flutter 3.10 regression (flutter/flutter#141376) | Avoids keyboard handling bug |
| `setState` for filler updates | `ValueNotifier<double>` + `ValueListenableBuilder` | Pattern response to flutter/flutter#143687 | Prevents full-list rebuild on filler change |
| `child: Widget` stub in AiChatScrollView | `itemBuilder` + `itemCount` builder API | Phase 2 (this phase) | Package owns the CustomScrollView; prerequisite for sliver composition |

**Deprecated/outdated:**
- `child: Widget` parameter on `AiChatScrollView`: Phase 1 stub, replaced by `itemBuilder`/`itemCount` in this phase. Remove the `child:` parameter entirely — no deprecated alias needed at this version.

---

## Open Questions

1. **`findChildIndexCallback` on `SliverList.builder`**
   - What we know: This callback helps Flutter efficiently update items when the list reorders (e.g., when a message at index 5 moves to index 6 after prepend). It takes a `Key` and returns the new index.
   - What's unclear: Whether message items in this package will have meaningful keys. If the consumer provides items via `itemBuilder` without keys, the callback is unused and can be omitted.
   - Recommendation: Omit `findChildIndexCallback` in Phase 2. Phase 3 can add it if scroll-position-preservation during anchor reindexing requires it.

2. **`addAutomaticKeepAlives` on `SliverList.builder`**
   - What we know: Defaults to `true`. Wraps each item in `AutomaticKeepAlive`. For chat lists, messages outside the viewport are not kept alive — this is correct (saves memory).
   - What's unclear: Whether consumers will use `KeepAlive` on their message items (e.g., to preserve video play state). If they do, `addAutomaticKeepAlives: true` (default) respects their `AutomaticKeepAliveClientMixin`.
   - Recommendation: Keep default (`true`). Do not override — this respects consumer item widgets that opt into keep-alive.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK bundled) |
| Config file | pubspec.yaml dev_dependencies (no separate config file) |
| Quick run command | `flutter test test/ai_chat_scroll_controller_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| API-03 | `AiChatScrollView` accepts `itemBuilder`/`itemCount`, renders a scrollable list | widget | `flutter test test/sliver_composition_test.dart` | Wave 0 |
| SCRL-01 | Newest message (index 0 in reversed data) appears at bottom when scrolled to end | widget | `flutter test test/sliver_composition_test.dart` | Wave 0 |
| SCRL-02 | Inserting a new message does not cause full-list rebuild (filler isolation) | widget + DevTools manual | `flutter test test/sliver_composition_test.dart` | Wave 0 |
| SCRL-03 | Scroll position (pixels) unchanged after message insert when user is mid-list | widget | `flutter test test/sliver_composition_test.dart` | Wave 0 |
| SCRL-04 | No `physics:` hardcoded; widget inherits ambient ScrollConfiguration | widget | `flutter test test/sliver_composition_test.dart` | Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test test/sliver_composition_test.dart`
- **Per wave merge:** `flutter test` (full suite including Phase 1 controller tests)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/sliver_composition_test.dart` — covers API-03, SCRL-01, SCRL-02, SCRL-03, SCRL-04
- [ ] Update `test/ai_chat_scroll_controller_test.dart` — migrate `child: const SizedBox()` to `itemBuilder`/`itemCount` API

*(No new framework install needed — flutter_test already present from Phase 1)*

---

## Sources

### Primary (HIGH confidence)

- [Flutter CustomScrollView API](https://api.flutter.dev/flutter/widgets/CustomScrollView-class.html) — center parameter, dual-SliverList chat pattern, anchor parameter, reverse parameter
- [Flutter SliverList API](https://api.flutter.dev/flutter/widgets/SliverList-class.html) — `.builder` constructor, `findChildIndexCallback`, lazy materialisation
- [Flutter SliverList.builder constructor](https://api.flutter.dev/flutter/widgets/SliverList/SliverList.builder.html) — full parameter list
- [Flutter ValueListenableBuilder API](https://api.flutter.dev/flutter/widgets/ValueListenableBuilder-class.html) — isolated rebuild pattern
- [Flutter SliverToBoxAdapter API](https://api.flutter.dev/flutter/widgets/SliverToBoxAdapter-class.html) — wrapping box widgets as slivers
- `.planning/research/STACK.md` — confirmed patterns: CustomScrollView, SliverToBoxAdapter, ValueNotifier isolation, no SliverFillRemaining
- `.planning/research/ARCHITECTURE.md` — confirmed patterns: builder API shape, filler sliver isolation, forward coordinate system
- `.planning/research/PITFALLS.md` — confirmed pitfalls: full-list rebuild, SliverFillRemaining regression, physics override

### Secondary (MEDIUM confidence)

- [flutter/flutter#143687](https://github.com/flutter/flutter/issues/143687) — CustomScrollView/SliverList rebuilds all elements regardless of cacheExtent on insertion — validates ValueNotifier isolation necessity
- [flutter/flutter#141376](https://github.com/flutter/flutter/issues/141376) — SliverFillRemaining keyboard regression post-3.10 — validates SliverToBoxAdapter choice
- [flutter/flutter#88038](https://github.com/flutter/flutter/issues/88038) — SliverFillRemaining + reverse CustomScrollView geometry bug — additional validation

### Tertiary (LOW confidence)

- WebSearch results on CustomScrollView chat patterns — cross-verified with official docs; no standalone findings used

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are Flutter built-ins verified via official docs and prior research
- Architecture: HIGH — patterns confirmed by ARCHITECTURE.md and STACK.md, which were researched against official Flutter docs
- Pitfalls: HIGH — flutter/flutter GitHub issues cited for the two major risks (full-list rebuild, SliverFillRemaining)
- API design decision (child -> itemBuilder): HIGH — deferred in Phase 1 summary, confirmed as required for Phase 2

**Research date:** 2026-03-15
**Valid until:** 2026-09-15 (stable Flutter APIs; re-validate if Flutter SDK major version changes)
