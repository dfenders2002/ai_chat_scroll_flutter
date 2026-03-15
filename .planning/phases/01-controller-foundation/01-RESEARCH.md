# Phase 1: Controller Foundation - Research

**Researched:** 2026-03-15
**Domain:** Flutter package scaffold + ChangeNotifier-based scroll controller with attach/detach lifecycle
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| API-01 | Package exposes `AiChatScrollController` with `onUserMessageSent()` method to trigger anchor behavior | ChangeNotifier delegation pattern; postFrameCallback dispatch; hasClients guard — all verified via Flutter API docs |
| API-02 | Package exposes `AiChatScrollController` with `onResponseComplete()` method to signal end of AI streaming | Same controller class; method clears internal streaming flag and no-ops gracefully if not attached |
| QUAL-04 | Package has zero runtime dependencies (Flutter SDK only) | pubspec.yaml `dependencies:` block contains only `flutter: sdk: flutter`; confirmed via Dart package layout docs |
</phase_requirements>

---

## Summary

Phase 1 builds the foundational skeleton of the `ai_chat_scroll` package: the pub.dev-ready package scaffold, the `AiChatScrollController` class, and the correct attach/detach wiring between the controller and an internal `ScrollController` owned by the (stub) widget. No actual scroll math, filler, or sliver composition happens in this phase — those are Phase 2 and 3 concerns.

The controller follows the **delegate pattern**: `AiChatScrollController extends ChangeNotifier` (not `ScrollController`). It holds a private `ScrollController?` reference that gets injected by `AiChatScrollView.initState()` via `attach()` and cleaned up via `detach()`. This mirrors how `TextEditingController` and `ItemScrollController` work in the Flutter ecosystem — callers get a clean domain API with no raw scroll primitives leaking through.

All scroll commands dispatched from the controller must go through `WidgetsBinding.instance.addPostFrameCallback` with a `hasClients` guard. This is the non-negotiable pattern for avoiding the "Cannot call scroll methods during layout" crash. It must be established in Phase 1 because every later phase builds on it.

**Primary recommendation:** Build controller + package scaffold together in one phase, stub `AiChatScrollView` as a minimal `StatefulWidget` that manages the attach/detach lifecycle, and verify with a unit test that the controller no-ops when not attached.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Flutter SDK | >=3.22.0 | Package runtime | 3.22 is the practical compatibility floor — Dart 3.x null safety, Impeller GA on iOS/Android in 3.29. Broad adoption without sacrificing modern APIs. |
| Dart SDK | ^3.4.0 | Language runtime | Bundled with Flutter 3.22. Enables records, patterns, class modifiers — clean public API design. Upper bound `<4.0.0`. |
| `ChangeNotifier` | Framework built-in | Controller notification | `AiChatScrollController extends ChangeNotifier`. Allows `AiChatScrollView` to listen for state changes without requiring a third-party state management solution. |
| `ScrollController` | Framework built-in | Internal scroll delegation | Owned privately by `AiChatScrollView`. Injected into `AiChatScrollController` via `attach()`. Drives `jumpTo` after layout settles. |
| `WidgetsBinding.addPostFrameCallback` | Framework built-in | Safe scroll dispatch | Guarantees scroll commands are deferred until after layout, preventing build-phase crash. |

### Supporting (Dev Only — Zero Runtime Dependencies)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `flutter_test` | SDK bundled | Widget and unit testing | Controller unit tests, widget lifecycle tests. Use `WidgetTester.pump()` and `ScrollController.hasClients` assertions. |
| `flutter_lints` | ^4.0.0 | Static analysis lints | Dev dependency. Provides the Flutter-recommended lint set for `analysis_options.yaml`. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ChangeNotifier` (delegate) | Extend `ScrollController` directly | Extending `ScrollController` exposes raw scroll primitives to callers and conflates domain logic with framework infrastructure. Delegate is cleaner. |
| `flutter_lints` | `very_good_analysis` | `very_good_analysis` is stricter; good choice but requires more lint suppressions for a first package. `flutter_lints` is the standard baseline. |

**Installation (package pubspec.yaml):**
```bash
# No consumer installation needed — this IS the package.
# The pubspec.yaml for the package:
```
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
```

---

## Architecture Patterns

### Recommended Project Structure

```
lib/
├── ai_chat_scroll.dart              # Barrel: exports ONLY AiChatScrollController + AiChatScrollView
└── src/
    ├── controller/
    │   └── ai_chat_scroll_controller.dart   # AiChatScrollController (ChangeNotifier, delegate)
    └── widgets/
        └── ai_chat_scroll_view.dart         # AiChatScrollView stub (StatefulWidget, owns ScrollController)
example/
├── lib/
│   └── main.dart                    # Minimal stub (can be near-empty in Phase 1)
├── pubspec.yaml
└── README.md
test/
└── controller_test.dart             # Unit tests: attach, detach, no-op before attach, dispose
pubspec.yaml
README.md
LICENSE
CHANGELOG.md
analysis_options.yaml
```

**Phase 1 scope note:** `src/widgets/filler_sliver.dart`, `src/models/`, and `src/utils/` are Phase 2+ concerns. Do not create them in Phase 1.

### Pattern 1: Delegate — AiChatScrollController extends ChangeNotifier

**What:** The controller holds a private `ScrollController?` that is injected at widget mount time. It does NOT extend `ScrollController`. Public API is domain-only: `onUserMessageSent()`, `onResponseComplete()`.

**When to use:** Always — this is the only pattern for this package.

**Example:**
```dart
// Source: Architecture research + Flutter ScrollController docs
class AiChatScrollController extends ChangeNotifier {
  ScrollController? _scrollController;

  /// Called by AiChatScrollView during initState.
  void attach(ScrollController scrollController) {
    _scrollController = scrollController;
  }

  /// Called by AiChatScrollView during dispose.
  void detach() {
    _scrollController = null;
  }

  /// Triggers anchor behavior after the user sends a message.
  /// Safe to call before widget mounts — no-ops gracefully.
  void onUserMessageSent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController == null || !_scrollController!.hasClients) return;
      // Phase 3 will implement actual jump logic here.
      // Phase 1: method exists and does not crash.
    });
    notifyListeners();
  }

  /// Signals that the AI response has finished streaming.
  void onResponseComplete() {
    // Phase 3 will clear streaming state here.
    // Phase 1: method exists and does not crash.
    notifyListeners();
  }

  @override
  void dispose() {
    _scrollController = null;
    super.dispose();
  }
}
```

### Pattern 2: Widget-Owned ScrollController with attach/detach Lifecycle

**What:** `AiChatScrollView` (stub) creates an internal `ScrollController` in `initState`, calls `widget.controller.attach(...)`, and calls `widget.controller.detach()` plus `_scrollController.dispose()` in `dispose()`.

**When to use:** This is the Phase 1 widget scaffold. The sliver composition is a Phase 2 concern — the stub only wires lifecycle.

**Example:**
```dart
// Source: Architecture research (mirrors TextEditingController/TextField pattern)
class _AiChatScrollViewState extends State<AiChatScrollView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.controller.attach(_scrollController);
  }

  @override
  void dispose() {
    widget.controller.detach();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 1 stub: renders children directly.
    // Phase 2 will replace this with CustomScrollView + slivers.
    return widget.child;
  }
}
```

### Pattern 3: Barrel Export — Public API Surface Control

**What:** `lib/ai_chat_scroll.dart` is the ONLY public file. It exports exactly two symbols.

**When to use:** Required from the start. Adding any `src/` import in `lib/ai_chat_scroll.dart` that is not `AiChatScrollController` or `AiChatScrollView` is a scope violation.

**Example:**
```dart
// lib/ai_chat_scroll.dart
library ai_chat_scroll;

export 'src/controller/ai_chat_scroll_controller.dart';
export 'src/widgets/ai_chat_scroll_view.dart';
```

### Pattern 4: addPostFrameCallback + hasClients Guard

**What:** Every scroll command is deferred one frame and guarded.

**When to use:** Every time `_scrollController` is used to dispatch a scroll. No exceptions.

**Example:**
```dart
// Source: PITFALLS.md Pitfall 1 + Flutter issue #30528
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (_scrollController == null || !_scrollController!.hasClients) return;
  _scrollController!.jumpTo(targetPixels);
});
```

### Anti-Patterns to Avoid

- **Extending ScrollController directly:** Exposes `animateTo`, `jumpTo`, `position` to callers who shouldn't need them. Use the delegate pattern.
- **Calling jumpTo synchronously in onUserMessageSent:** Layout has not run yet — the scroll position is stale. Always defer via `addPostFrameCallback`.
- **Missing `hasClients` guard:** If the controller is called before the widget mounts (developer error), it crashes instead of no-oping. The package should be robust to this.
- **Exporting src/ files directly:** Any `import 'package:ai_chat_scroll/src/...'` by a consumer breaks encapsulation. Only the barrel export should be public.
- **Missing `super.dispose()` in controller:** Leaks `ChangeNotifier` listeners. Produces "used after dispose" errors in consumer apps.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Post-frame scroll dispatch | Custom timer/Future.delayed | `WidgetsBinding.instance.addPostFrameCallback` | Timer duration is device-speed-dependent and races with layout; `addPostFrameCallback` is guaranteed to fire after layout, before the next paint |
| Controller attachment to widget | Custom event bus or global singleton | `attach()`/`detach()` called directly from widget lifecycle | Global singletons prevent multiple simultaneous instances; widget lifecycle is the correct scope |
| Change notification | Custom `StreamController` or `ValueNotifier` | `ChangeNotifier` (built-in Flutter) | `ChangeNotifier` integrates with `ListenableBuilder` and is the pattern Flutter's own controllers use |
| Package scaffold structure | Custom layout | Dart package layout conventions (`lib/src/`, barrel export, `example/`, `test/`) | pub.dev scoring requires these exact paths; deviating loses pub points |

**Key insight:** Every "helpful" shortcut in scroll programming introduces device-speed race conditions or lifecycle gaps. The standard Flutter patterns exist precisely because the naive approaches fail in production.

---

## Common Pitfalls

### Pitfall 1: Build-Phase Scroll Call Crash

**What goes wrong:** `ScrollController.jumpTo()` called without `addPostFrameCallback` causes a Flutter assertion error ("Cannot call scroll methods during layout"). Silent in release, red screen in debug.

**Why it happens:** `onUserMessageSent()` is called synchronously when the developer adds a message to their list. The new message has not been laid out yet.

**How to avoid:** Establish `addPostFrameCallback` + `hasClients` guard as the ONLY dispatch pattern in Phase 1. All later phases inherit this pattern automatically.

**Warning signs:** Scroll position stuck at 0.0 after message send; works on fast devices, fails on slow ones.

### Pitfall 2: Missing dispose() / detach() Causing Memory Leaks

**What goes wrong:** `AiChatScrollController.dispose()` is not called by the developer (common mistake). Or `_scrollController.dispose()` is not called in the widget's `dispose()`. This produces "A ScrollController was used after being disposed" errors.

**Why it happens:** `ChangeNotifier` holds a listener list. If `dispose()` is not called, listeners are never released.

**How to avoid:** Implement `dispose()` in both `AiChatScrollController` (calls `super.dispose()`, nulls `_scrollController`) and in `_AiChatScrollViewState` (calls `widget.controller.detach()`, then `_scrollController.dispose()`). Test this with a widget test that unmounts the widget and verifies no error.

**Warning signs:** "A ChangeNotifier was used after being disposed" in consumer apps; memory growth over many navigation cycles.

### Pitfall 3: Public Barrel Exporting Internal Symbols

**What goes wrong:** A developer imports `package:ai_chat_scroll/src/controller/ai_chat_scroll_controller.dart` directly. Now internal refactoring becomes a breaking API change.

**Why it happens:** If the barrel export is incomplete or the `src/` files are accidentally public, consumers reach for them.

**How to avoid:** The `lib/ai_chat_scroll.dart` barrel is the ONLY export file. All implementation lives in `lib/src/`. Add a test that verifies no non-barrel import path resolves to a public symbol.

**Warning signs:** Consumer imports referencing `src/` paths; pub.dev docs showing internal implementation classes.

### Pitfall 4: QUAL-04 Violated by Transitive Dependency

**What goes wrong:** A dev dependency (e.g., a test utility package) is accidentally listed under `dependencies:` instead of `dev_dependencies:`. This adds a runtime dependency, violating QUAL-04.

**Why it happens:** Copy-paste error in pubspec.yaml; unfamiliarity with the distinction.

**How to avoid:** `dependencies:` must contain ONLY `flutter: sdk: flutter`. Run `dart pub deps --style=list` and verify the direct dependency count is 1 (Flutter itself). This is verifiable automatically.

**Warning signs:** `dart pub deps` shows more than Flutter in the direct dependency tree.

### Pitfall 5: onUserMessageSent Called Before Widget Mounts

**What goes wrong:** Consumer calls `controller.onUserMessageSent()` immediately after instantiation, before the widget tree is built. Without a null/hasClients guard, this crashes.

**Why it happens:** Developers instantiate controllers in their state `initState()` and may call methods before the first frame.

**How to avoid:** The `addPostFrameCallback` + `hasClients` guard already handles this — if `_scrollController` is null or has no clients, the scroll command is silently skipped. Document this behavior explicitly in dartdoc: "Safe to call before the widget is mounted."

---

## Code Examples

Verified patterns from architecture and pitfalls research:

### Controller — Full Phase 1 Implementation

```dart
// lib/src/controller/ai_chat_scroll_controller.dart
// Source: .planning/research/ARCHITECTURE.md Pattern 1

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Controls scroll behavior for an AI chat interface.
///
/// Attach to an [AiChatScrollView] by passing this controller to its
/// constructor. The controller is inert until the widget mounts.
///
/// All methods are safe to call before the widget is mounted — they no-op
/// gracefully rather than throwing.
class AiChatScrollController extends ChangeNotifier {
  ScrollController? _scrollController;

  /// Attaches this controller to the [ScrollController] owned by
  /// [AiChatScrollView]. Called automatically during widget initialization.
  void attach(ScrollController scrollController) {
    assert(_scrollController == null,
        'AiChatScrollController is already attached. Call detach() first.');
    _scrollController = scrollController;
  }

  /// Detaches from the [ScrollController]. Called automatically when
  /// [AiChatScrollView] is disposed.
  void detach() {
    _scrollController = null;
  }

  /// Triggers the top-anchor behavior after the user sends a message.
  ///
  /// Call this after adding the user's message to your message list.
  /// Safe to call before the widget is mounted — no-ops gracefully.
  void onUserMessageSent() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController == null || !_scrollController!.hasClients) return;
      // Phase 3 will implement the anchor jump here.
    });
    notifyListeners();
  }

  /// Signals that the AI response has finished streaming.
  ///
  /// After this call, the package stops maintaining the anchor position
  /// and the user can scroll freely.
  void onResponseComplete() {
    // Phase 3 will clear streaming state here.
    notifyListeners();
  }

  @override
  void dispose() {
    _scrollController = null;
    super.dispose();
  }
}
```

### Widget — Phase 1 Stub

```dart
// lib/src/widgets/ai_chat_scroll_view.dart
// Source: .planning/research/ARCHITECTURE.md Pattern 4

import 'package:flutter/widgets.dart';
import '../controller/ai_chat_scroll_controller.dart';

/// A wrapper widget that connects [AiChatScrollController] to a scrollable
/// message list.
///
/// Wrap your message list with this widget and pass the same
/// [AiChatScrollController] instance that your screen uses.
class AiChatScrollView extends StatefulWidget {
  const AiChatScrollView({
    super.key,
    required this.controller,
    required this.child,
  });

  final AiChatScrollController controller;

  /// The child widget (your message list). In Phase 2, this will be
  /// replaced with a builder API for sliver composition.
  final Widget child;

  @override
  State<AiChatScrollView> createState() => _AiChatScrollViewState();
}

class _AiChatScrollViewState extends State<AiChatScrollView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.controller.attach(_scrollController);
  }

  @override
  void dispose() {
    widget.controller.detach();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 1 stub: pass-through.
    // Phase 2 replaces this with CustomScrollView + SliverList + FillerSliver.
    return widget.child;
  }
}
```

### Barrel Export

```dart
// lib/ai_chat_scroll.dart
library ai_chat_scroll;

export 'src/controller/ai_chat_scroll_controller.dart';
export 'src/widgets/ai_chat_scroll_view.dart';
```

### Unit Test — Controller Lifecycle

```dart
// test/controller_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_scroll/ai_chat_scroll.dart';

void main() {
  group('AiChatScrollController', () {
    test('does not crash when onUserMessageSent called before attach', () {
      final controller = AiChatScrollController();
      expect(() => controller.onUserMessageSent(), returnsNormally);
      controller.dispose();
    });

    test('does not crash when onResponseComplete called before attach', () {
      final controller = AiChatScrollController();
      expect(() => controller.onResponseComplete(), returnsNormally);
      controller.dispose();
    });

    test('attach and detach do not throw', () {
      final controller = AiChatScrollController();
      final scrollController = ScrollController();
      expect(() => controller.attach(scrollController), returnsNormally);
      expect(() => controller.detach(), returnsNormally);
      controller.dispose();
      scrollController.dispose();
    });

    testWidgets('widget mounts and disposes without error', (tester) async {
      final controller = AiChatScrollController();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AiChatScrollView(
            controller: controller,
            child: const SizedBox(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Unmount
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  });
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `class MyController extends ScrollController` | `class MyController extends ChangeNotifier` + internal `ScrollController` delegate | Established pattern; popularized by `scrollable_positioned_list` | Cleaner public API; no raw scroll primitives leaking to consumers |
| `Future.delayed(Duration(milliseconds: X))` before scroll | `WidgetsBinding.instance.addPostFrameCallback` | Flutter 1.x → stable; `SchedulerBinding` available since early Flutter | Race-condition-free; guaranteed post-layout |
| Single-file packages | `lib/src/` with barrel export | Dart package conventions (current) | pub.dev shows only public API; internal refactoring is non-breaking |
| `flutter_lints: ^2.0.0` | `flutter_lints: ^4.0.0` | Flutter 3.22+ | Stricter but aligned with current Flutter recommendations |

**Deprecated/outdated:**
- `Future.delayed` for scroll timing: fragile, race condition baked in — replaced by `addPostFrameCallback` universally.
- `ScrollController` subclassing for domain controllers: conflates framework infrastructure with domain logic.

---

## Open Questions

1. **AiChatScrollView child vs builder API**
   - What we know: Phase 1 stub uses `child: Widget`. Phase 2 replaces the scroll primitive with `CustomScrollView`.
   - What's unclear: Whether Phase 2 should change the public `AiChatScrollView` API from `child:` to a builder (e.g., `itemBuilder:`, `itemCount:`), which would be a breaking change to Phase 1's signature.
   - Recommendation: In Phase 1, use a builder-style constructor signature (`itemBuilder`, `itemCount`) even if the implementation stubs it out. This avoids a breaking API change in Phase 2. The stub implementation can ignore the builder and render a placeholder.

2. **SchedulerBinding vs WidgetsBinding for addPostFrameCallback**
   - What we know: Both expose `addPostFrameCallback`. `SchedulerBinding` is lower-level; `WidgetsBinding` is the standard Flutter app entry point.
   - What's unclear: Which is more appropriate in a package context where the consuming app controls the binding.
   - Recommendation: Use `SchedulerBinding.instance.addPostFrameCallback` — it is the binding that actually owns the frame scheduler, and is available in both widget and non-widget contexts. `WidgetsBinding.instance` is a superset but slightly heavier. Either works; `SchedulerBinding` is the more precise choice.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK bundled, no version pin needed) |
| Config file | none — flutter test uses default discovery |
| Quick run command | `flutter test test/controller_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| API-01 | `onUserMessageSent()` exists, is callable, no-ops before attach without error | unit | `flutter test test/controller_test.dart` | Wave 0 |
| API-02 | `onResponseComplete()` exists, is callable, no-ops before attach without error | unit | `flutter test test/controller_test.dart` | Wave 0 |
| QUAL-04 | `dependencies:` contains only `flutter: sdk: flutter`; `dart pub deps` shows no extra direct dependencies | smoke | `dart pub deps --style=list` (manual verify) | N/A — pubspec check |

### Sampling Rate

- **Per task commit:** `flutter test test/controller_test.dart`
- **Per wave merge:** `flutter test && dart analyze`
- **Phase gate:** Full suite green + `dart analyze` zero warnings before moving to Phase 2

### Wave 0 Gaps

- [ ] `test/controller_test.dart` — covers API-01, API-02 (attach, detach, no-op, dispose lifecycle)
- [ ] `analysis_options.yaml` — lint configuration (flutter_lints baseline)
- [ ] Framework install: already available via `flutter: sdk: flutter` and `flutter_test: sdk: flutter` — no additional install needed

---

## Sources

### Primary (HIGH confidence)

- [Flutter ScrollController API](https://api.flutter.dev/flutter/widgets/ScrollController-class.html) — `attach`, `detach`, `hasClients`, `createScrollPosition` pattern
- [Flutter SchedulerBinding API](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addPostFrameCallback.html) — `addPostFrameCallback` semantics
- [Dart Package Layout Conventions](https://dart.dev/tools/pub/package-layout) — `lib/src/`, barrel export, `example/`, `test/` structure
- [Developing packages and plugins (Flutter docs)](https://docs.flutter.dev/packages-and-plugins/developing-packages) — pubspec.yaml structure, SDK constraints, zero-dependency pattern
- `.planning/research/ARCHITECTURE.md` — Delegate pattern (Pattern 1, Pattern 4), attach/detach lifecycle, build order
- `.planning/research/PITFALLS.md` — Pitfall 1 (build-phase crash), Pitfall 5 (hasClients guard), dispose/detach checklist

### Secondary (MEDIUM confidence)

- `.planning/research/STACK.md` — pubspec.yaml template, flutter_lints version, pana scoring checklist
- [scrollable_positioned_list pub.dev](https://pub.dev/packages/scrollable_positioned_list) — `ItemScrollController` as reference implementation of the delegate pattern

### Tertiary (LOW confidence)

- None for Phase 1 — foundational Flutter patterns are HIGH confidence.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Flutter built-ins only; pubspec pattern from official Dart docs
- Architecture: HIGH — delegate pattern verified via Flutter API docs and ARCHITECTURE.md research
- Pitfalls: HIGH — build-phase crash and dispose leak are verified Flutter issues; barrel export is Dart convention

**Research date:** 2026-03-15
**Valid until:** 2026-06-15 (stable Flutter APIs; scroll internals rarely break between minor versions)
