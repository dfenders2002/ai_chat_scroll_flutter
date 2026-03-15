# Stack Research

**Domain:** Flutter pub.dev scroll behavior package (AI chat viewport anchoring)
**Researched:** 2026-03-15
**Confidence:** HIGH (Flutter APIs verified via official docs; package landscape verified via pub.dev)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Flutter SDK | >=3.22.0 | Package runtime | 3.22 is the practical compatibility floor — Dart 3.x null safety is stable, Impeller is GA on iOS/Android in 3.29. Targeting 3.22+ gives broad adoption without sacrificing modern APIs. |
| Dart SDK | ^3.4.0 | Language runtime | Dart 3.4 bundled with Flutter 3.22. Enables records, patterns, and class modifiers — all useful for clean public API design. Set upper bound as `<4.0.0`. |
| `ScrollController` | Framework built-in | Scroll position management | The right abstraction boundary for this package. `AiChatScrollController` extends `ScrollController`, overriding `createScrollPosition()` to inject custom `ScrollPosition` logic. No third-party dependency needed. |
| `ScrollPositionWithSingleContext` | Framework built-in | Custom scroll position | Subclass this (not `ScrollPosition` directly) to override `applyContentDimensions()` and implement the "retain offset on content growth" anchor mechanic. This is the right extension point. |
| `CustomScrollView` + Slivers | Framework built-in | Widget composition | `AiChatScrollView` wraps a `CustomScrollView`. Slivers give exact control over the filler space below the AI response. Use `SliverList` + `SliverToBoxAdapter` for the dynamic spacer. |
| `ScrollPhysics` / `ClampingScrollPhysics` | Framework built-in | Platform-appropriate feel | Use `ClampingScrollPhysics` explicitly (Android default). On iOS, `BouncingScrollPhysics` conflicts with anchor logic — suppress overscroll during the anchor period. |

### Supporting Libraries (Dev Only — Zero Runtime Dependencies)

The package must declare **zero runtime dependencies** beyond Flutter itself. Everything is from the framework.

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `flutter_test` | SDK bundled | Widget and unit testing | All test infrastructure. Use `WidgetTester.drag()`, `WidgetTester.pump()`, and `ScrollController` position assertions for scroll behavior tests. |
| `alchemist` | ^0.8.0 | Golden (visual regression) tests | Optional, for snapshot-testing the filler-space layout. Preferred over deprecated `golden_toolkit`. Only add if golden tests are part of your CI plan. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `dart doc` (built-in) | API documentation generation | Run `dart doc .` from package root. pub.dev auto-builds docs and scores package on coverage — aim for 100% public API documented. |
| `pana` | pub.dev score simulation | Run `dart pub global activate pana && pana .` locally before publishing to simulate the pub.dev score. Catches missing README sections, license, and API doc gaps. |
| `flutter analyze` | Static analysis | Run on CI. Use `analysis_options.yaml` with `very_good_analysis` lints or at minimum the Flutter recommended set. |
| `flutter pub publish --dry-run` | Pre-publish validation | Validates pubspec.yaml, file structure, and package constraints before actual upload. |

---

## Installation

This is a Flutter package, not a consumer app. The pubspec.yaml for the package itself:

```yaml
name: ai_chat_scroll
description: AI-chat-optimized scroll behavior. Anchors the user's message at the top of the viewport while the AI response streams below.
version: 0.1.0
homepage: https://github.com/[yourname]/ai_chat_scroll

environment:
  sdk: ^3.4.0
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

# No runtime dependencies — zero-dependency package
```

For consumers integrating this package:

```yaml
dependencies:
  ai_chat_scroll: ^0.1.0
```

---

## Key Flutter APIs — Detailed Rationale

### ScrollController.createScrollPosition()

This is the primary extension point. Override it to return your custom `ScrollPosition` subclass:

```dart
class AiChatScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _AiChatScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
    );
  }
}
```

This pattern is documented in the official Flutter API and used by the community's `RetainableScrollController` pattern for chat position retention. **Confidence: HIGH.**

### ScrollPosition.applyContentDimensions()

Called by the framework during every layout pass when the scroll extent changes (e.g., AI response grows). This is where the anchor logic lives — when in anchor mode, absorb the `maxScrollExtent` delta by adjusting `pixels` rather than letting the viewport drift:

```dart
@override
bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
  if (_anchoring) {
    final delta = maxScrollExtent - this.maxScrollExtent;
    // Keep user's message pinned: absorb content growth into pixels
    correctPixels(pixels + delta);
  }
  return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
}
```

This is the established technique for "keep item at top while content grows below." **Confidence: HIGH** — pattern confirmed by Flutter issue #80250 and multiple community implementations.

### SliverFillRemaining / SliverToBoxAdapter (filler space)

During streaming, there must be empty space below the AI response so the user's message can sit at the top of the viewport even when the response is short. Use a `SliverToBoxAdapter` wrapping a `SizedBox` whose height is computed dynamically:

```
[SliverList — message history]
[SliverToBoxAdapter — dynamic filler]
```

**Known caveat:** `SliverFillRemaining` behavior changed in Flutter 3.10 (keyboard-push issue, GitHub #141376). Use `SliverToBoxAdapter` with explicit computed height instead — this avoids the 3.10+ regression. **Confidence: HIGH** (confirmed via Flutter issue tracker).

### ViewportOffset / ScrollPosition.pixels

`ViewportOffset` is the interface implemented by `ScrollPosition`. `pixels` is the authoritative scroll offset. Calling `correctPixels()` (not `jumpTo()`) during layout is necessary — `jumpTo()` triggers a new frame and can cause jitter. **Confidence: HIGH** — documented in Flutter internals.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Extend `ScrollPositionWithSingleContext` | Use `scrollview_observer` package | If you want a ready-made chat observer with position-retention already implemented and are OK taking an external dependency in your package. Not viable here — this package must have zero runtime deps. |
| `SliverToBoxAdapter` with computed height | `SliverFillRemaining` | Never for this use case — `SliverFillRemaining` post-3.10 has keyboard handling regressions and does not support the dynamic-height-filler pattern reliably. |
| `CustomScrollView` | `ListView(reverse: true)` | `ListView(reverse: true)` is the naive chat approach. It fights the anchor pattern because the coordinate system is inverted — items grow upward, which means new content pushes the anchor down, not up. Do not use. |
| `ClampingScrollPhysics` (explicit) | Default platform physics | Explicit clamping prevents iOS bounce physics from conflicting with anchor position during streaming. iOS bounce adds pixel overshoot that breaks the `applyContentDimensions` delta calculation. |
| Dart 3.4 / Flutter 3.22 minimum | Dart 3.0 / Flutter 3.10 | Flutter 3.10 has the `SliverFillRemaining` keyboard bug. Setting minimum to 3.22 sidesteps this entirely while still supporting the vast majority of active Flutter apps. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `ListView(reverse: true)` | Inverted coordinate system fights the top-anchor pattern. `pixels` grows in the wrong direction. The filler-space hack becomes extremely complex. | `CustomScrollView` with `SliverList` |
| `SliverFillRemaining` | Post-Flutter 3.10 regression (GitHub #141376): keyboard does not push content up correctly. Behavior is unreliable for dynamic-height use cases. | `SliverToBoxAdapter` wrapping a `SizedBox` with computed height |
| Any state management package (Riverpod, Bloc, Provider) | This package is scroll-behavior only. Adding a state management runtime dependency forces it onto consumers. Internal state (anchor mode on/off) is plain Dart — use `ChangeNotifier` if listeners are needed. | `ChangeNotifier` (Flutter built-in) |
| `scroll_to_index` (pub.dev package) | Last updated May 2022 — effectively unmaintained. Would add a runtime dependency for functionality achievable with `ScrollController.jumpTo()` after computing index offset. | `ScrollController.jumpTo()` + `GlobalKey` for extent computation |
| `anchor_scroll_controller` (pub.dev package) | Last updated Sept 2023 — limited maintenance. Designed for index-based scrolling, not content-relative anchoring. Does not handle the "absorb content growth" mechanic. | Custom `ScrollPosition` subclass |
| `super_sliver_list` (pub.dev package) | Last meaningful update March 2024. Adds a runtime dependency for large-list performance features this package does not need — message lists are short. | Flutter built-in `SliverList` |
| `ScrollController.animateTo()` for anchor snap | Animation duration creates a visible "jump" UX when the user sends a message. The user message should appear snapped, not animated. | `ScrollController.jumpTo()` for the initial snap; animation only for deliberate user-triggered navigation |

---

## Stack Patterns by Variant

**If the consuming app uses `ListView` (not `CustomScrollView`):**
- `AiChatScrollView` must wrap or replace the consumer's list widget
- Provide a builder-style API so the consumer passes a `ListView.builder` factory, not a fully-constructed widget
- Because otherwise you cannot inject your `CustomScrollView` as the underlying scroll primitive

**If the consuming app needs reverse chronological order (newest at bottom):**
- Do NOT use `reverse: true` on `CustomScrollView`
- Instead, reverse the message list in data layer and keep the scroll coordinate system normal (top = index 0 = oldest visible)
- The "newest at bottom" appearance comes from the data order, not from Flutter's scroll direction reversal

**If streaming content causes excessive rebuilds:**
- The dynamic filler `SizedBox` height computation must not trigger a full list rebuild
- Isolate the filler into its own `StatefulWidget` with `setState` scoped to the filler only
- The `SliverList` message items should be stable during streaming

---

## Version Compatibility

| Constraint | Compatible With | Notes |
|------------|-----------------|-------|
| Flutter >=3.22.0 | Dart ^3.4.0 | Bundled together. Dart 3.4 = null safety + records + patterns, all stable. |
| Flutter >=3.29.0 | Dart ^3.7.0 | Latest stable (Feb 2025). Impeller default on iOS/Android. No scroll API breaking changes in 3.29. |
| Flutter <3.10.0 | (avoid) | `SliverFillRemaining` keyboard bug present. Setting `>=3.22.0` minimum safely excludes this range. |

---

## pub.dev Score Checklist

Pana (pub.dev's scoring tool) evaluates:

| Criterion | Requirement | Target |
|-----------|-------------|--------|
| Dart API docs | All public symbols documented | 100% |
| `README.md` | Non-empty, includes usage example | Required for full score |
| `CHANGELOG.md` | Exists, has entry for published version | Required |
| `LICENSE` | Exists, recognized OSS license | MIT recommended |
| Static analysis | Zero warnings/errors | Required |
| Platforms | Declare supported platforms in pubspec | `flutter: {platforms: {android: , ios: }}` |
| Package structure | `lib/`, `test/`, `example/` present | example/ required for full pub points |

---

## Sources

- [Flutter CustomScrollView API](https://api.flutter.dev/flutter/widgets/CustomScrollView-class.html) — CustomScrollView, scrollBehavior, sliver composition (HIGH confidence)
- [Flutter ScrollPosition API](https://api.flutter.dev/flutter/widgets/ScrollPosition-class.html) — applyContentDimensions, correctPixels (HIGH confidence)
- [Flutter ScrollController API](https://api.flutter.dev/flutter/widgets/ScrollController-class.html) — createScrollPosition override pattern (HIGH confidence)
- [Flutter ScrollPhysics API](https://api.flutter.dev/flutter/widgets/ScrollPhysics-class.html) — ClampingScrollPhysics, applyTo override (HIGH confidence)
- [Using slivers to achieve fancy scrolling](https://docs.flutter.dev/ui/layout/scrolling/slivers) — SliverToBoxAdapter, SliverFillRemaining patterns (HIGH confidence)
- [Developing packages & plugins](https://docs.flutter.dev/packages-and-plugins/developing-packages) — pubspec structure, SDK constraints (HIGH confidence)
- [Flutter 3.29.0 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.29.0) — Dart 3.7, no breaking scroll API changes (HIGH confidence)
- [Flutter issue #141376](https://github.com/flutter/flutter/issues/141376) — SliverFillRemaining keyboard regression post-3.10 (HIGH confidence)
- [Flutter issue #80250](https://github.com/flutter/flutter/issues/80250) — Keep scroll position when adding items on top (HIGH confidence)
- [super_sliver_list pub.dev](https://pub.dev/packages/super_sliver_list) — v0.4.1, 292 likes, last updated March 2024 (MEDIUM confidence — maintenance uncertain)
- [scrollview_observer pub.dev](https://pub.dev/packages/scrollview_observer) — v1.26.3, 307 likes, chat observer feature (MEDIUM confidence)
- [scroll_to_index pub.dev](https://pub.dev/packages/scroll_to_index) — v3.0.1, last updated May 2022, effectively unmaintained (HIGH confidence on staleness)
- [Flutter Gems scroll category](https://fluttergems.dev/scrollable-scrollview-scrollbar/) — ecosystem survey (MEDIUM confidence — curated but not official)
- [Flutter internals: Viewports](https://flutter.megathink.com/scrolling/viewports) — ViewportOffset/ScrollPosition architecture (MEDIUM confidence — community docs)

---

*Stack research for: ai_chat_scroll — Flutter pub.dev scroll behavior package*
*Researched: 2026-03-15*
