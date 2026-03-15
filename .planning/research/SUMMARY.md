# Project Research Summary

**Project:** ai_chat_scroll — Flutter pub.dev scroll behavior package
**Domain:** Flutter scroll/viewport management for AI chat (pub.dev package)
**Researched:** 2026-03-15
**Confidence:** HIGH

## Executive Summary

The `ai_chat_scroll` package solves a well-defined, unsolved problem in the Flutter ecosystem: anchoring the user's outgoing message at the top of the viewport while an AI response streams below it. No existing Flutter package implements this pattern cleanly. The closest analog is the React Native `react-native-streaming-message-list`, which confirms the pattern is viable and identifies the key mechanisms — top-anchor-on-send, dynamic filler space, and suppressed auto-scroll during streaming. Expert Flutter packages build this entirely from framework primitives (`CustomScrollView`, `ScrollPosition`, `SliverToBoxAdapter`) with zero runtime dependencies, which is both achievable and the correct approach for pub.dev adoption.

The recommended implementation follows a delegation pattern: `AiChatScrollController` extends `ChangeNotifier` (not `ScrollController`) and owns a private `ScrollController` injected by `AiChatScrollView` at mount time. The filler space is a `SliverToBoxAdapter` wrapping a `ValueListenableBuilder` driven by a `ValueNotifier<double>` — isolated from the message list to prevent full-list rebuilds on every streaming token. The anchor mechanic uses `jumpTo` via `addPostFrameCallback` (never from the build phase), computing target offset from `ScrollPosition.viewportDimension` and accumulated content height.

The two highest-risk decisions are the scroll axis direction (forward-growing `CustomScrollView` beats `ListView(reverse: true)` for this use case) and the filler isolation strategy. Both must be locked in during Phase 1 — wrong choices here require architectural rewrites. Everything else — lifecycle hooks, pub.dev packaging, edge cases — is well-documented and low-risk.

## Key Findings

### Recommended Stack

The package requires Flutter `>=3.22.0` / Dart `^3.4.0` as a minimum. This floor excludes the `SliverFillRemaining` keyboard regression (Flutter 3.10, issue #141376) while supporting the vast majority of active Flutter apps. Zero runtime dependencies is mandatory for pub.dev adoption: every mechanism — scroll position management, sliver composition, physics — is available from the Flutter framework itself.

**Core technologies:**
- `CustomScrollView` + `SliverList` + `SliverToBoxAdapter`: scroll composition — the only viable alternative to `ListView(reverse: true)` for the top-anchor pattern; gives explicit control over filler space
- `ScrollController` (internal, plain): scroll position driver — owned by `AiChatScrollView`, never subclassed; uses `jumpTo` via `addPostFrameCallback`
- `ChangeNotifier` (Dart built-in): public controller base — provides listener infrastructure without exposing raw scroll API to consumers
- `ValueNotifier<double>` + `ValueListenableBuilder`: filler isolation — ensures filler updates during streaming do not trigger full list rebuilds
- `flutter_lints` + `pana` + `dart doc`: pub.dev toolchain — required to achieve pub points score sufficient for discoverability

### Expected Features

**Must have (table stakes — v1):**
- Reverse-list ordering (newest at bottom, oldest above) — universal chat convention, foundational for all other behavior
- `AiChatScrollController` with `onUserMessageSent()` and `onResponseComplete()` lifecycle hooks — the primary integration surface
- `AiChatScrollView` wrapper widget over `CustomScrollView` — lightweight drop-in; exposes item builder API
- Top-anchor-on-send: viewport snaps so user message is flush at top — the core differentiator; no Flutter package does this
- Dynamic filler space during streaming: `SliverToBoxAdapter` shrinks as AI response grows — required for anchor stability
- No auto-scroll during AI streaming — the anti-pattern this package exists to eliminate
- Manual scroll resume: user drag cancels managed scroll, no re-hijacking until next `onUserMessageSent()` — critical for long responses
- New-message-while-in-history reset: anchor pattern reactivates even if user was reading old messages
- No scroll jank on message insertion — baseline quality bar
- pub.dev package structure with working example app — required for pub points

**Should have (v1.x after validation):**
- "Scroll to bottom" FAB/indicator — simple to add, not blocking for core UX
- Keyboard-aware scroll compensation — Flutter's `resizeToAvoidBottomInset` may already cover most cases
- Anchor snap animation curve — `jumpTo` may feel abrupt; `animateTo` with short curve is an easy enhancement
- RTL/bidirectional layout support — directional flag in `AiChatScrollView`

**Defer (v2+):**
- Pagination / infinite scroll for older message history — distinct technical problem, significant added complexity
- Desktop and web scroll support — mobile-first is correct for v1; desktop requires separate physics strategy
- Accessibility announcements via `SemanticsService` — valuable but non-blocking for initial launch

**Confirmed anti-features (never build):**
- Built-in message bubble UI — violates single-responsibility; `flutter_chat_ui` owns that space
- Built-in streaming/AI integration — couples scroll (UI) to networking; consumers own their streaming
- Auto-scroll-to-bottom during streaming — the exact anti-pattern this package replaces
- Configurable scroll physics — premature API surface explosion before real-world usage data

### Architecture Approach

The architecture separates domain logic from Flutter framework mechanics at a clean boundary. `AiChatScrollController` (a `ChangeNotifier`) holds domain state and high-level event methods; it delegates all scroll position manipulation to a private `ScrollController` injected by `AiChatScrollView` at widget mount. The `AiChatScrollView` owns sliver composition: a `SliverList` for messages and a `SliverToBoxAdapter` filler whose height is driven by a `ValueNotifier`. All filler recomputation uses `ScrollMetricsNotification` (not `addListener`, which misses extent changes). Scroll commands always go through `addPostFrameCallback` to guarantee layout has settled before position is updated.

**Major components:**
1. `AiChatScrollController` (`ChangeNotifier`) — public API; accepts `onUserMessageSent(int index)` / `onResponseComplete()`; computes target pixel offsets; drives internal scroll controller; holds `ScrollAnchorState` (anchor index, filler height, streaming flag)
2. `AiChatScrollView` (`StatefulWidget`) — owns `CustomScrollView`; creates and attaches internal `ScrollController`; manages `_fillerHeight` via `ValueNotifier`; wires `NotificationListener<ScrollMetricsNotification>` for dimension changes
3. `FillerSliver` (`SliverToBoxAdapter` + `ValueListenableBuilder`) — isolated filler widget; self-updates from `ValueNotifier<double>` without triggering list rebuilds
4. `viewport_math.dart` (pure functions) — computes `max(0, viewportHeight - contentBelowAnchor)`; unit-testable without widget tree
5. `example/` app — minimal fake message list with simulated streaming ticker; required for pub.dev pub points

**Project structure (barrel-export pattern):**
- `lib/ai_chat_scroll.dart` — public barrel; exports only `AiChatScrollController` and `AiChatScrollView`
- `lib/src/controller/`, `lib/src/widgets/`, `lib/src/models/`, `lib/src/utils/` — private implementation

### Critical Pitfalls

1. **Calling `jumpTo`/`animateTo` inside the build phase** — crashes with "Cannot call scroll methods during layout"; always use `WidgetsBinding.instance.addPostFrameCallback` and guard with `controller.hasClients`. Establish this pattern in Phase 1 before any other scroll behavior is built.

2. **Using `ListView(reverse: true)` as the foundation** — `reverse: true` inverts the coordinate system, making top-anchor math require constant recalculation as AI content grows; use forward-growing `CustomScrollView` with explicit filler. This is a Phase 1 architectural decision — wrong choice requires a full rewrite.

3. **Full-list rebuild on every streaming token** — naive `setState` on the entire list causes frame drops visible at ~20 messages, severe at 100+; isolate filler as a `ValueListenableBuilder` driven by a `ValueNotifier<double>`. Design this in Phase 2 from the start — retrofitting requires invasive refactoring.

4. **Using `SliverFillRemaining` for the filler space** — post-Flutter 3.10 regression (issue #88038 and #141376): incorrect geometry with reversed views, keyboard handling broken; use `SliverToBoxAdapter(child: SizedBox(height: computed))` exclusively.

5. **Using `controller.addListener` to detect content height changes** — `addListener` fires on pixel changes only, not on extent/dimension changes (keyboard show, content growth); use `NotificationListener<ScrollMetricsNotification>` for anything depending on viewport dimensions or `maxScrollExtent`.

6. **Missing `hasClients` guard and `dispose()` cleanup** — calling controller methods before widget mounts crashes; not calling `super.dispose()` leaks listeners. Both must be in place before the package is published.

## Implications for Roadmap

Based on combined research, the architecture's dependency chain maps directly to a clear phase sequence. Controller logic must be solid before the widget depends on it; filler computation depends on a working sliver list; streaming behavior is a superset of static anchoring.

### Phase 1: Core Scroll Controller and Foundation

**Rationale:** All other behavior depends on the controller attach/detach lifecycle and the correct scroll axis decision. These cannot be changed later without a breaking API change. Research explicitly flags both as Phase 1 requirements (PITFALLS.md pitfall-to-phase mapping).

**Delivers:** `AiChatScrollController` (ChangeNotifier with attach/detach), internal `ScrollController` wiring, `onUserMessageSent()` / `onResponseComplete()` methods, `addPostFrameCallback` dispatch pattern, `hasClients` guards, dispose cleanup, `NotificationListener<ScrollMetricsNotification>` wiring, and package scaffold (`pubspec.yaml`, barrel export, `analysis_options.yaml`).

**Addresses features:** Controller lifecycle hooks (P1), package structure (P1)

**Avoids pitfalls:** Build-phase scroll crash, wrong axis direction, missing `hasClients` guard, `addListener` vs. `ScrollMetricsNotification` confusion, missing dispose

### Phase 2: AiChatScrollView and Sliver Composition

**Rationale:** The view widget depends on a working controller (Phase 1). Filler isolation must be designed here — not retrofitted. The `SliverToBoxAdapter` / `ValueNotifier` pattern must be in place before streaming behavior is added.

**Delivers:** `AiChatScrollView` (`StatefulWidget`), `CustomScrollView` + `SliverList` composition (forward-growing, no `reverse: true`), `FillerSliver` with `ValueListenableBuilder`, `viewport_math.dart` pure functions, static anchor positioning (filler without streaming), basic reverse-list ordering.

**Uses:** `CustomScrollView`, `SliverList`, `SliverToBoxAdapter`, `SliverChildBuilderDelegate`, `LayoutBuilder` / `ScrollPosition.viewportDimension`

**Implements:** `AiChatScrollView`, `FillerSliver`, `ScrollAnchorState` model

**Avoids pitfalls:** `SliverFillRemaining` regression, full-list rebuild on filler update, multiple `ScrollController` attachment

### Phase 3: Streaming Behavior and Anchor Stability

**Rationale:** Streaming is a superset of static anchoring (Phase 2). Validate the simpler case first, then layer in dynamic filler shrinking, the no-auto-scroll constraint, and manual scroll resume.

**Delivers:** Dynamic filler recomputation as AI response grows (filler shrinks per streaming token), suppressed auto-scroll during streaming, `UserScrollNotification` detection for manual scroll resume, new-message-while-in-history reset to top-anchor pattern, scroll jank elimination verified via DevTools timeline.

**Addresses features:** Top-anchor-on-send (P1), dynamic filler space (P1), no auto-scroll during streaming (P1), manual scroll resume (P1), new-message-while-in-history (P1)

**Avoids pitfalls:** Full-list rebuild during streaming, `animateTo` during user drag assertion crash, auto-scroll fighting user intent

### Phase 4: Edge Cases, Polish, and pub.dev Publishing

**Rationale:** Edge cases (empty list, single message, keyboard show/hide, long AI response) can only be validated once the core streaming behavior is stable. pub.dev publishing prep must happen last because `pana` score depends on complete documentation and a working example.

**Delivers:** Edge case handling (empty list, single message, scroll-up-then-send, long AI response exceeding viewport), working `example/` app with simulated streaming, full dartdoc coverage on all public symbols, `CHANGELOG.md`, `LICENSE`, `README.md` with integration example, `pana` score >= 120/160, `dart pub publish --dry-run` with 0 warnings.

**Addresses features:** pub.dev package structure (P1), no scroll jank on insertion (P1)

**Avoids pitfalls:** Low pub.dev score, undocumented public API, example app missing, missing `dispose()` in published package

### Phase 5: v1.x Enhancements (Post-Validation)

**Rationale:** Add only after real-world adoption provides signal on what is actually needed. All P2 features are additive and non-breaking.

**Delivers:** "Scroll to bottom" FAB/indicator, keyboard-aware scroll compensation (if `resizeToAvoidBottomInset` proves insufficient), anchor snap animation curve option, RTL support flag.

**Addresses features:** Scroll-to-bottom FAB (P2), keyboard compensation (P2), animation curve (P2), RTL (P2)

### Phase Ordering Rationale

- **Controller before view** — the delegation pattern (`attach`/`detach`) requires the controller API to be stable before `AiChatScrollView` depends on it; inverting this order makes both components unstable simultaneously
- **Static anchor before streaming** — streaming is dynamic filler + static anchor; validating the simpler static case catches viewport math errors before streaming complexity obscures their source
- **Streaming before edge cases** — edge cases are variations of the streaming flow; testing them before the core flow is validated produces misleading test failures
- **All functionality before pub.dev prep** — `pana` scores documentation completeness and example correctness; these can only be finalized once the API surface is stable

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (Streaming behavior):** Item height measurement for variable-height messages during anchor computation is the principal unsolved complexity. Research identified `GlobalKey` as problematic at scale and `ScrollPosition.extentAfter` as an approximation. Specific measurement strategy (e.g., `SizeChangedLayoutNotifier`, height cache `Map<int, double>`) needs validation against real streaming scenarios before implementation.
- **Phase 3 (Streaming behavior):** Throttling filler recomputation to one update per frame (`SchedulerBinding.addPostFrameCallback`) needs implementation and performance validation — the pattern is known but the exact debounce strategy for high-frequency streaming tokens is not pinned down.

Phases with standard patterns (can skip research-phase):
- **Phase 1 (Controller foundation):** `ChangeNotifier` delegation pattern is fully documented; `addPostFrameCallback` guard is a standard Flutter pattern confirmed by official sources. No unknowns.
- **Phase 2 (Sliver composition):** `CustomScrollView` + `SliverToBoxAdapter` patterns are verified against official Flutter docs and issue tracker. `ValueNotifier`/`ValueListenableBuilder` isolation is a standard Flutter pattern. No unknowns.
- **Phase 4 (pub.dev publishing):** `pana` scoring criteria, `dart doc`, pubspec structure — all documented in official Dart/Flutter publishing guides. No unknowns.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All core APIs verified via official Flutter docs and Flutter issue tracker; zero-dependency approach confirmed by pub.dev ecosystem survey; `SliverFillRemaining` regression confirmed via issue #141376 |
| Features | MEDIUM-HIGH | Table stakes and differentiators verified via Flutter ecosystem survey and React Native analog; internal Claude/ChatGPT implementation inferred from behavior observation, not source access |
| Architecture | HIGH | Flutter scroll internals well-documented in official API and megathink.com Flutter Internals; delegation pattern confirmed by `scrollable_positioned_list` precedent; data flow is deterministic |
| Pitfalls | HIGH | Most pitfalls backed by specific Flutter issue tracker references (issues #88038, #143687, #30528, #99158, etc.); pub.dev scoring pitfalls confirmed by official `pana` documentation |

**Overall confidence:** HIGH

### Gaps to Address

- **Variable-height item measurement strategy:** Research identified the problem (GlobalKey at scale is expensive; `extentAfter` is approximate) but did not pin down the exact implementation for the height cache. Validate during Phase 3 planning — options are `SizeChangedLayoutNotifier` callback, `RenderBox` measurement in `addPostFrameCallback`, or requiring consumers to provide item height hints via the builder API.
- **Keyboard interaction with anchor offset:** The interaction between `MediaQuery.viewInsets` (keyboard height), `ScrollMetricsNotification`, and anchor recomputation is identified as important but the exact trigger sequence is not fully mapped. Build and test on a real device with software keyboard early in Phase 3.
- **iOS bounce physics during streaming:** Research flags that `BouncingScrollPhysics` overscroll can break the `applyContentDimensions` delta calculation. The recommendation is to use `ClampingScrollPhysics` explicitly, but the correct way to do this without overriding the consumer's ambient `ScrollConfiguration` needs implementation-time validation.

## Sources

### Primary (HIGH confidence)
- [Flutter ScrollPosition API](https://api.flutter.dev/flutter/widgets/ScrollPosition-class.html) — `applyContentDimensions`, `correctPixels`, `viewportDimension`, `extentAfter`
- [Flutter ScrollController API](https://api.flutter.dev/flutter/widgets/ScrollController-class.html) — `createScrollPosition`, `hasClients`, `attach`/`detach`
- [Flutter CustomScrollView API](https://api.flutter.dev/flutter/widgets/CustomScrollView-class.html) — sliver composition, `anchor` param, `center` sliver
- [Using slivers to achieve fancy scrolling](https://docs.flutter.dev/ui/layout/scrolling/slivers) — `SliverToBoxAdapter`, `SliverFillRemaining` patterns
- [Developing packages and plugins](https://docs.flutter.dev/packages-and-plugins/developing-packages) — pubspec structure, SDK constraints
- [Flutter issue #141376](https://github.com/flutter/flutter/issues/141376) — `SliverFillRemaining` keyboard regression post-3.10
- [Flutter issue #80250](https://github.com/flutter/flutter/issues/80250) — keep scroll position when adding items on top
- [Flutter issue #88038](https://github.com/flutter/flutter/issues/88038) — `SliverFillRemaining` with reverse `CustomScrollView`
- [Flutter issue #143687](https://github.com/flutter/flutter/issues/143687) — `CustomScrollView`/`SliverList` rebuilds all elements on insertion
- [Flutter issue #30528](https://github.com/flutter/flutter/issues/30528) — `ScrollController.jumpTo()` cannot be called from `didUpdateWidget`
- [Flutter Internals — Viewports](https://flutter.megathink.com/scrolling/viewports) — CENTER sliver anchor, `RenderViewport` architecture
- [Flutter Internals — Scrollable](https://flutter.megathink.com/scrolling/scrollable) — `ScrollController`/`ScrollPosition`/`ViewportOffset` relationships
- [Dart Package Layout Conventions](https://dart.dev/tools/pub/package-layout) — `lib/src` structure, example directory
- [pub.dev Package Scores and Pub Points](https://pub.dev/help/scoring) — scoring criteria, `pana` requirements

### Secondary (MEDIUM confidence)
- [scrollview_observer on pub.dev](https://pub.dev/packages/scrollview_observer) — ecosystem reference; chat observer pattern; streaming position preservation
- [lorien_chat_list on pub.dev](https://pub.dev/packages/lorien_chat_list) — ecosystem reference; `bottomEdgeThreshold` pattern
- [flutter_chat_ui on pub.dev](https://pub.dev/packages/flutter_chat_ui) — scope boundary reference; confirms UI and scroll are separate concerns
- [scrollable_positioned_list on pub.dev](https://pub.dev/packages/scrollable_positioned_list) — `ItemScrollController` delegation pattern precedent
- [Flutter Gems scroll category](https://fluttergems.dev/scrollable-scrollview-scrollbar/) — ecosystem survey
- [Tips and Tricks for Flutter Chat UI (Ximya, Medium)](https://medium.com/@ximya/tips-and-tricks-for-implementing-a-successful-chat-ui-in-flutter-190cd81bdc64) — implementation patterns
- [Things you should know before publishing on pub.dev (Roman Cinis, Medium)](https://tsinis.medium.com/things-you-should-know-before-publishing-a-package-on-pub-dev-95ab195e216d) — pub.dev publishing patterns

### Tertiary (LOW confidence — needs validation)
- [react-native-streaming-message-list on GitHub](https://github.com/bacarybruno/react-native-streaming-message-list) — HIGH confidence for feature design pattern; LOW for direct Flutter applicability (different runtime); confirms top-anchor + dynamic filler pattern is viable
- [Conversational AI UI comparison 2025 (IntuitionLabs)](https://intuitionlabs.ai/articles/conversational-ai-ui-comparison-2025) — market context; internal Claude/ChatGPT scroll behavior inferred, not sourced

---
*Research completed: 2026-03-15*
*Ready for roadmap: yes*
