# Pitfalls Research

**Domain:** Flutter scroll package — AI chat top-anchor behavior
**Researched:** 2026-03-15
**Confidence:** HIGH (Flutter engine issues) / MEDIUM (pub.dev publishing patterns)

---

## Critical Pitfalls

### Pitfall 1: Calling jumpTo/animateTo Inside the Build Phase

**What goes wrong:**
`ScrollController.jumpTo()` or `animateTo()` called synchronously inside `build()`, `initState()`, or during a `setState()` rebuild triggers a Flutter assertion error: "Cannot call scroll methods during layout." The symptom is a red-screen crash in debug or a silent incorrect position in release.

**Why it happens:**
Developers reach for scroll manipulation immediately after `setState(() { messages.add(newMessage); })` without understanding Flutter's frame pipeline. The list has not been laid out yet at that point, so the scroll extent is stale or undefined.

**How to avoid:**
Always dispatch scroll commands through `WidgetsBinding.instance.addPostFrameCallback`. For the `onUserMessageSent()` path specifically, the sequence must be: setState to add the message → wait one frame for layout → then jumpTo. Never call scroll methods without first checking `controller.hasClients`.

```dart
void onUserMessageSent() {
  setState(() => _messages.add(userMessage));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_controller.hasClients) {
      _controller.jumpTo(_targetAnchorOffset);
    }
  });
}
```

**Warning signs:**
- "ScrollController not attached" assertion during hot-reload test
- Scroll position stuck at 0.0 after message send
- Works on fast devices, fails on slow ones (race between layout and scroll call)

**Phase to address:** Core scroll logic phase (the first implementation phase). Establish this pattern before any other scroll behavior is built.

---

### Pitfall 2: reverse: true Fights the "Top Anchor" Mental Model

**What goes wrong:**
`ListView(reverse: true)` is the standard chat list pattern (newest at bottom, `offset 0.0` = bottom of list). But the project's anchor requirement — snap user message to the TOP of the viewport — inverts the intuition. In a reversed list, "top of viewport" is a large offset value, not a small one. Developers apply `reverse: true` then find they cannot easily pin content to the visual top.

**Why it happens:**
`reverse: true` changes the axis direction so items grow from the bottom up. `jumpTo(0)` means "show the newest item at the bottom." Snapping the user's message to the visual top in a reversed list requires computing the item's position within the scroll extent and jumping to a non-zero, dynamically recalculated offset — which changes as the AI response streams in.

**How to avoid:**
Decide on the axis direction strategy before writing any scroll logic. Two viable approaches:
1. **Non-reversed list with controlled scrolling**: Keep `reverse: false`, place newest message at the top manually, and use `jumpTo` to position it. Simpler offset math.
2. **Reversed list with explicit anchor offset**: Use `reverse: true` for correct keyboard-avoidance behavior, but implement a dedicated method that calculates the correct offset for the anchored message's top position.

Do not mix assumptions — pick one model and make it explicit in the controller's internal documentation.

**Warning signs:**
- `jumpTo(0)` after send leaves the user message at the bottom, not the top
- Anchor offset drifts upward as the AI response grows (because the item above the response is pushing up in a reversed list)
- Different behavior between iOS (bouncing physics) and Android (clamping physics) near the anchor point

**Phase to address:** Core scroll logic phase — this is the foundational architecture decision that all other behavior depends on.

---

### Pitfall 3: Dynamic Filler Space Causing Layout Jank During Streaming

**What goes wrong:**
As the AI response streams in (growing line by line), the filler space below it must shrink correspondingly to maintain the anchor position. If this filler update triggers a full list rebuild — rather than a targeted `setState` on just the filler widget — every message widget in the list rebuilds on every streaming token. With 50+ messages this is visually janky and produces measurable frame drops.

**Why it happens:**
Naive implementation wraps the whole list in a `setState` triggered by the streaming callback. Flutter's `SliverChildBuilderDelegate` rebuilds are not free, and `CustomScrollView` has a known bug (flutter/flutter#143687) where inserting items causes a rebuild of all elements regardless of `cacheExtent`.

**How to avoid:**
Isolate the filler space as its own `StatefulWidget` (or `ValueListenableBuilder`) driven by a `ValueNotifier<double>`. The streaming token updates only the notifier; the list itself does not rebuild. The filler widget self-updates independently of the list.

```dart
final ValueNotifier<double> _fillerHeight = ValueNotifier(initialFiller);

// In list:
ValueListenableBuilder<double>(
  valueListenable: _fillerHeight,
  builder: (_, height, __) => SizedBox(height: height),
)
```

**Warning signs:**
- Frame times spike during AI streaming (check Flutter DevTools timeline)
- All message widgets show rebuild highlights in "Rebuild Stats" mode
- CPU usage climbs linearly with message count during streaming

**Phase to address:** Filler space / streaming phase. Design the filler as isolated from the start; retrofitting it later requires invasive refactoring.

---

### Pitfall 4: SliverFillRemaining Behaves Incorrectly with reverse: true

**What goes wrong:**
`SliverFillRemaining` combined with a reversed `CustomScrollView` does not correctly calculate its fill amount (flutter/flutter#88038). It fills space based on non-reversed geometry, producing either excess blank space at the top or overflow, depending on content height.

**Why it happens:**
`SliverFillRemaining` was designed for non-reversed contexts. Its geometry calculation (`SliverConstraints`) does not account for the flipped axis direction in the way the package needs.

**How to avoid:**
Do not use `SliverFillRemaining` for the filler space. Instead use a `SliverToBoxAdapter` wrapping a `SizedBox` with a calculated height, updated via a `ValueNotifier`. The height is computed as: `viewportHeight - anchoredMessageHeight - responseHeight` (clamped to 0).

**Warning signs:**
- Initial load shows a blank gap at the top that is exactly viewport height
- Filler space does not shrink as response grows
- Overflow errors in debug mode when response exceeds viewport height

**Phase to address:** Filler space / sliver architecture phase. Prototype with `SliverToBoxAdapter` explicitly; do not reach for `SliverFillRemaining` as a shortcut.

---

### Pitfall 5: ScrollController Attached to Multiple ScrollViews Simultaneously

**What goes wrong:**
If the `AiChatScrollController` is passed to both the inner `ListView`/`CustomScrollView` and an outer wrapping widget (e.g., a `Scrollbar`), Flutter throws: "The ScrollController is attached to multiple scroll views." The assertion fires only at runtime, not at compile time.

**Why it happens:**
A `ScrollController` instance maintains a list of attached `ScrollPosition` objects. It can only handle multiple positions if subclassed and `createScrollPosition` is overridden. The default implementation crashes on the second attach.

**How to avoid:**
The `AiChatScrollView` wrapper must own exactly one `ScrollController` reference and expose it to exactly one scrollable child. Document this constraint in the API. If a `Scrollbar` is needed, use `PrimaryScrollController.passthrough` pattern or create a separate controller for the scrollbar.

**Warning signs:**
- "ScrollController attached to multiple scroll views" assertion in debug
- Appears when user wraps `AiChatScrollView` in their own `Scrollbar` widget
- Error only triggers after second frame (first attach succeeds, second fails)

**Phase to address:** API design phase and documented in the package's README with an explicit "Do not wrap in Scrollbar" note.

---

### Pitfall 6: Scroll Metrics Notifications Not Received via addListener

**What goes wrong:**
`controller.addListener(callback)` fires when the scroll *offset* changes but does NOT fire when the scroll *extent* (maxScrollExtent, viewportDimension) changes — for example when the keyboard appears/disappears or when the AI response changes the content height. Code that reads `controller.position.maxScrollExtent` inside a scroll listener may read a stale value.

**Why it happens:**
`ScrollController.notifyListeners()` is called only on position pixel changes. `ScrollMetricsNotification` is a separate notification type that must be listened to via `NotificationListener<ScrollMetricsNotification>` on the widget tree.

**How to avoid:**
For any logic that depends on viewport dimensions or content height (such as computing the filler size), use `NotificationListener<ScrollMetricsNotification>` instead of `controller.addListener`. Reserve `addListener` only for tracking scroll offset changes.

**Warning signs:**
- Anchor offset is correct at first load but wrong after keyboard appears
- Filler height does not update when the device rotates
- `maxScrollExtent` reads as `0.0` during the first frame callback

**Phase to address:** Core scroll logic phase — establish the correct notification pattern at the start.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `Future.delayed(Duration(milliseconds: 1))` before jumpTo | Avoids post-frame boilerplate | Fragile — delay may be too short on slow devices; race condition baked in | Never — use `addPostFrameCallback` instead |
| Single `setState` on entire list for filler updates | Simple to implement | Full list rebuilds on every streaming token; degrades with message count | Never — use ValueNotifier/ValueListenableBuilder |
| Hardcoded anchor offset constant | Fast to ship | Breaks when message bubble height is dynamic (long messages, images) | Never — measure actual item height via RenderObject |
| `ListView` instead of `CustomScrollView` | Simpler API | Cannot mix heterogeneous slivers (filler + list); harder to extend | Only in proof-of-concept prototype, never in shipped package |
| Skip `hasClients` check | One less line | Crash when controller is used before widget mounts | Never — the package's controller will be used by developers unfamiliar with lifecycle |
| Publish at `0.0.1` with no example | Faster first publish | Low pub.dev score; developers cannot evaluate the package | Never — the example is required for pub points |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Developer's streaming callback → controller | Calling `onResponseComplete()` from an `async` function that may be on a non-UI isolate | Document that all controller methods must be called on the main isolate; add an assert in debug mode |
| Developer's `ListView.builder` inside `AiChatScrollView` | Passing a separate `ScrollController` to the inner list, bypassing `AiChatScrollController` | The wrapper must claim the scroll controller; README must show the correct integration pattern with `controller.scrollController` |
| Keyboard avoidance (`resizeToAvoidBottomInset`) | The anchor offset is calculated pre-keyboard-show, then viewport shrinks, making the anchor wrong | Listen for `ScrollMetricsNotification` to detect viewport height change and recompute anchor |
| iOS vs Android scroll physics | Using `BouncingScrollPhysics` explicitly in the package, which overrides the developer's app-level `ScrollBehavior` | Let the developer's ambient `ScrollConfiguration` apply; do not hardcode physics in the wrapper |
| `GlobalKey` on anchored message for height measurement | `GlobalKey.currentContext` is `null` for items not yet laid out (lazy list) | The anchored message must always be rendered; use `itemCount` and ensure the message at send index is within visible range before jumping |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full list rebuild on each streaming token | Jank during AI response streaming; frame times >16ms | Isolate filler as ValueListenableBuilder; ensure message list only rebuilds on message count change | Visible at ~20 messages; severe at 100+ |
| `cacheExtent` too low for jump-to behavior | Item at jump target is not built yet; `GlobalKey.currentContext` returns null | Increase `cacheExtent` to at least the full viewport height, or use index-based positioning instead of GlobalKey | First jump after large scroll gap |
| Measuring item height with `GlobalKey` in `postFrameCallback` | Correct on first frame, wrong if item reflowed (e.g., text wrap changes on keyboard show) | Re-measure in `ScrollMetricsNotification` handler when viewport width changes | Device rotation or split-screen |
| `animateTo` during user drag | `isScrolling` assertion crash | Check `controller.position.isScrolling` or use `jumpTo` (cancels ongoing scroll) for the snap-to-anchor action | User swipes during AI streaming |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Auto-scrolling during streaming when user has manually scrolled up | User loses their position reading older messages when a new streaming token arrives | Track user scroll intent: if user scrolled up from the anchor, do not auto-adjust; only maintain anchor on the initial send |
| Animation on the "snap to top" action | 300ms animation creates a disconnect between tap and result; user sees their message fly upward | Use `jumpTo` (instant) not `animateTo` for the send anchor — it must feel immediate |
| No visual feedback during the anchor calculation frame | One frame of wrong position visible before jump fires | Set initial scroll offset via `initialScrollOffset` on the controller where possible, rather than jumping after first frame |
| Filler space visible as white gap before first response token | Feels like a loading bug | Filler should be 0 until after first user message is sent; or use a loading indicator in the filler area |

---

## "Looks Done But Isn't" Checklist

- [ ] **Anchor on send:** The message is at the top of the viewport — but verify on a device with a software keyboard visible. The anchor offset changes when keyboard height changes.
- [ ] **Streaming growth:** Response grows downward visually — but verify the anchor message does NOT move upward as response grows (the filler must shrink, not the message move).
- [ ] **Scroll-up-then-send:** User scrolls to history, sends message — verify viewport jumps to anchor the new message, not to scroll extent bottom.
- [ ] **Long AI response:** Response exceeds viewport — verify user can manually scroll down to read the rest without the package fighting them.
- [ ] **pub.dev score:** `dart pub publish --dry-run` shows 0 warnings — but verify `pana` score separately; dry-run does not catch documentation score deductions.
- [ ] **Example app:** App runs with `flutter run` from the `example/` directory without modification — pub.dev shows the example in the package view.
- [ ] **Dispose:** `AiChatScrollController.dispose()` calls `super.dispose()` — missing this leaks listeners and produces "A ScrollController was used after being disposed" errors in consumer apps.
- [ ] **API surface:** All public methods and classes have dartdoc comments — pub.dev deducts pub points for undocumented public APIs.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Build-phase scroll crash shipped to consumers | HIGH | Patch release (0.x.y+1), add `hasClients` guard + `addPostFrameCallback`; communicate via CHANGELOG |
| Wrong axis direction chosen (reverse vs non-reverse) | HIGH | Architectural rewrite of scroll math; likely a breaking API change requiring major version bump |
| Filler implemented as full-list setState | MEDIUM | Extract filler widget; replace setState calls with ValueNotifier updates; non-breaking if internal |
| pub.dev score <80 points after first publish | LOW | Add docs, fix analysis warnings, publish new version; score updates automatically |
| API method name conflicts with developer's naming conventions | MEDIUM | Deprecate old names in 0.x release, add new names; remove in 1.0 |
| `SliverFillRemaining` used and broken on reverse | MEDIUM | Replace with `SliverToBoxAdapter(child: SizedBox(height: computed))` + `ValueListenableBuilder`; internal change |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Scroll call in build phase | Phase 1: Core scroll controller | Widget test: message send triggers no assertion errors in debug mode |
| Wrong axis direction for anchor | Phase 1: Core scroll controller | Manual test: after send, user message is at visual top of viewport |
| Full-list rebuild during streaming | Phase 2: Filler space + streaming behavior | DevTools timeline: frame time stays <16ms with 50 messages streaming |
| SliverFillRemaining + reverse bug | Phase 2: Filler space implementation | Visual test: no blank gap at top on first load; filler shrinks as response grows |
| Multiple ScrollController attachment | Phase 3: AiChatScrollView wrapper | Integration test: wrapping in a Scrollbar does not crash |
| ScrollMetrics not received via addListener | Phase 1: Core scroll controller | Test: anchor offset recalculates correctly after keyboard show/hide |
| Missing hasClients guard | Phase 1: Core scroll controller | Unit test: calling `onUserMessageSent()` before widget is mounted does not crash |
| Low pub.dev score | Phase 4: Package publishing prep | Run `dart pub publish --dry-run`; run `pana` locally; score must be ≥120/160 before publish |
| Missing dispose | Phase 1: Core scroll controller | Widget test: dispose controller after widget removal; no "used after dispose" error |
| Undocumented public API | Phase 4: Package publishing prep | `dart doc` generates with 0 warnings; all public symbols have descriptions |

---

## Sources

- [Flutter ScrollController class docs](https://api.flutter.dev/flutter/widgets/ScrollController-class.html) — hasClients, onAttach/onDetach, ScrollMetrics notification distinction
- [Flutter issue #99158: scroll position jumping with dynamic content](https://github.com/flutter/flutter/issues/99158)
- [Flutter issue #88038: SliverFillRemaining with reverse CustomScrollView](https://github.com/flutter/flutter/issues/88038)
- [Flutter issue #143687: CustomScrollView/SliverList rebuilds all elements on insertion](https://github.com/flutter/flutter/issues/143687)
- [Flutter issue #113141: ListView jumpTo abnormal position after item height change](https://github.com/flutter/flutter/issues/113141)
- [Flutter issue #30528: ScrollController.jumpTo() cannot be called from didUpdateWidget](https://github.com/flutter/flutter/issues/30528)
- [Flutter issue #86527: ListView scroll jump to index 0 on backward scroll](https://github.com/flutter/flutter/issues/86527)
- [Flutter issue #45814: TalkBack accessibility broken with reverse ListView](https://github.com/flutter/flutter/issues/45814)
- [Flutter issue #97873: Scrollbar ScrollController no ScrollPosition attached](https://github.com/flutter/flutter/issues/97873)
- [scrollview_observer pub.dev package](https://pub.dev/packages/scrollview_observer) — chat scroll position preservation patterns
- [Tips and Tricks for Flutter Chat UI — Ximya on Medium](https://medium.com/@ximya/tips-and-tricks-for-implementing-a-successful-chat-ui-in-flutter-190cd81bdc64)
- [Things you should know before publishing on pub.dev — Roman Cinis on Medium](https://tsinis.medium.com/things-you-should-know-before-publishing-a-package-on-pub-dev-95ab195e216d)
- [pub.dev Package Scores & Pub Points documentation](https://pub.dev/help/scoring)
- [Dart publishing packages guide](https://dart.dev/tools/pub/publishing)
- [Dart package versioning and semver](https://dart.dev/tools/pub/versioning)
- [Flutter issue #69412: BouncingScrollPhysics broken in CustomScrollView](https://github.com/flutter/flutter/issues/69412)

---
*Pitfalls research for: Flutter AI chat scroll package (ai_chat_scroll)*
*Researched: 2026-03-15*
