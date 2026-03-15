# Phase 3: Streaming Anchor Behavior - Research

**Researched:** 2026-03-15
**Domain:** Flutter scroll offset math, filler height computation, user-drag detection, anchor-on-send pattern
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ANCH-01 | When user sends a message, viewport snaps so the user's message is at the top of the viewport | Scroll offset math: `jumpTo(pixels - extentBefore_to_anchor)` — see Architecture Patterns §Anchor Jump Math |
| ANCH-02 | AI response streams below the user message, growing downward within the viewport | Filler shrinks as content grows: `fillerHeight = max(0, viewportDimension - extentAfter - anchoredMessageHeight)` — see Filler Height Computation |
| ANCH-03 | Dynamic filler space is rendered below the AI response to keep the anchor stable during streaming | FillerSliver ValueNotifier already exists from Phase 2; drive it from controller listener — see Streaming Filler Update Pattern |
| ANCH-04 | No auto-scroll occurs during AI streaming — user stays positioned at their sent message | Filler shrinks instead of scroll offset moving — no `jumpTo` during streaming, filler absorbs growth passively |
| ANCH-05 | If AI response exceeds the viewport, user must manually scroll down to see the rest | Filler clamps to 0 via `math.max(0, ...)` — once filler reaches 0, content overflows downward naturally |
| ANCH-06 | When user scrolls up to history then sends a new message, viewport resets to top-anchor pattern with new message at top | `onUserMessageSent()` always re-runs anchor jump regardless of prior scroll position — state machine clears and restarts |
| API-04 | User drag cancels any managed scroll behavior — no re-hijacking until next `onUserMessageSent()` | `NotificationListener<ScrollUpdateNotification>` with `dragDetails != null` check — see User Drag Detection |
</phase_requirements>

---

## Summary

Phase 3 implements the core value proposition of the package: when a user sends a message, the viewport jumps so that message is at the very top of the visible area, then the AI response streams in below it while the viewport does not move. This is achieved with a three-part mechanism: (1) a `jumpTo` targeting the exact pixel offset that places the sent message at `pixels = 0` of the viewport, (2) a `ValueNotifier<double>` driving the filler sliver that shrinks as the AI response grows to passively hold the anchor position steady, and (3) a `NotificationListener` watching `ScrollUpdateNotification.dragDetails` to detect when the user's finger touches the list and cancels managed behavior.

The scroll offset math is the critical path. The package already owns a forward-growing `CustomScrollView` (Phase 2), which means `pixels = 0` is the visual top. To place a message at the top after send, the controller must `jumpTo` a value equal to the sum of heights of all items above the sent message — i.e., `position.pixels + position.extentBefore_to_sent_message`. Because the sent message is always the last item added (index = `itemCount - 1`) and the list is newest-at-bottom, this means `jumpTo(position.maxScrollExtent - position.viewportDimension + sentMessageHeight)` after setting the initial filler to `viewportDimension - sentMessageHeight`. The filler approach removes the need to know heights of items above the anchor at all — filler absorbs what remains below.

The hardest sub-problem is measuring the sent message's height at the time of the jump. The message is the last item in the list. After the `postFrameCallback` that already guards all scroll dispatches (Phase 1 pattern), the item will be laid out. A single `GlobalKey` on the last rendered item is the correct approach here — the concern about GlobalKey scale documented in prior research applies to keys on every item, not a single key on the last item only.

**Primary recommendation:** Use `jumpTo(maxScrollExtent - viewportDimension + sentMsgHeight)` for the anchor snap. Drive `_fillerHeight` from a `ScrollController.addListener` callback that re-reads `position.extentAfter` each frame during streaming. Detect drag via `NotificationListener<ScrollUpdateNotification>` checking `notification.dragDetails != null`. A `bool _anchorActive` flag in `_AiChatScrollViewState` gates all of this.

---

## Standard Stack

### Core (all Flutter SDK built-ins — no new dependencies)

| API | Version | Purpose | Why Standard |
|-----|---------|---------|--------------|
| `ScrollController.addListener` | Flutter SDK | Recompute filler height when scroll metrics change during streaming | Already owned by `_AiChatScrollViewState` from Phase 2; listener fires when `pixels` or content dimensions change |
| `ScrollPosition.pixels` | Flutter SDK | Current scroll offset — authoritative source of truth for all math | Read-only inside listener; direct field on `position` |
| `ScrollPosition.maxScrollExtent` | Flutter SDK | Total scrollable extent; needed for anchor jump target | Available post-layout via `_scrollController.position.maxScrollExtent` |
| `ScrollPosition.viewportDimension` | Flutter SDK | Height of the visible area; needed for filler computation | Available post-layout via `_scrollController.position.viewportDimension` |
| `ScrollPosition.extentAfter` | Flutter SDK | Pixels of content below the current viewport bottom; `= maxScrollExtent - pixels` | Used in filler recomputation during streaming |
| `ScrollController.jumpTo()` | Flutter SDK | Instant snap to anchor offset — no animation, no frame delay | Confirmed correct choice: `animateTo` would cause visible fly animation |
| `NotificationListener<ScrollUpdateNotification>` | Flutter SDK | Detect user drag vs programmatic scroll | `notification.dragDetails != null` means user drag; `null` means programmatic |
| `GlobalKey` (single key on last item) | Flutter SDK | Measure the sent message's height after layout | One key per list is safe; the anti-pattern is one key per item |
| `RenderBox.size.height` | Flutter SDK | Read rendered height of the keyed message widget | Accessed after `postFrameCallback` guarantees layout is complete |
| `math.max(0.0, ...)` | `dart:math` | Clamp filler height to zero — prevents negative SizedBox | Zero-dependency; already part of Dart SDK |

### No New Dependencies

Phase 3 requires zero new packages. All mechanisms are Flutter framework built-ins. The `dart:math` import for `max()` is already standard Dart.

---

## Architecture Patterns

### Recommended Additions to Existing Structure

```
lib/src/
├── controller/
│   └── ai_chat_scroll_controller.dart   # Add: _anchorActive, _anchorIndex fields
├── widgets/
│   ├── ai_chat_scroll_view.dart         # Add: GlobalKey, _anchorActive, NotificationListener
│   └── filler_sliver.dart               # No changes needed (ValueNotifier already wired)
```

No new files are required for Phase 3. All changes are to the two existing source files.

### Pattern 1: Anchor Jump Math

**What:** When `onUserMessageSent()` fires, the sent message is the last item in the list (`itemCount - 1`). After layout, `jumpTo` moves the scroll position so that item's top edge aligns with the viewport top.

**The formula:**

```
targetPixels = maxScrollExtent - viewportDimension + sentMessageHeight
```

**Why this works:** In a forward-growing list, `maxScrollExtent` is how far the content extends past the viewport. Subtracting `viewportDimension` gets you the scroll offset that would place the very last pixel of content at the bottom of the viewport. Then adding back `sentMessageHeight` undershoots by exactly one message height, which places the top of the sent message at the top of the viewport. The filler at this point should equal `viewportDimension - sentMessageHeight` (enough space below to fill the remaining screen).

**Initial filler height at anchor time:**

```
initialFillerHeight = max(0.0, viewportDimension - sentMessageHeight)
```

**Example:**

```dart
// Source: derived from Flutter ScrollMetrics API — api.flutter.dev/flutter/widgets/ScrollMetrics-mixin.html
void _performAnchorJump(double sentMessageHeight) {
  final pos = _scrollController.position;
  final target =
      pos.maxScrollExtent - pos.viewportDimension + sentMessageHeight;
  _scrollController.jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent));

  final initialFiller =
      math.max(0.0, pos.viewportDimension - sentMessageHeight);
  _fillerHeight.value = initialFiller;
}
```

**When to use:** Inside the `addPostFrameCallback` of `onUserMessageSent()`, after verifying `hasClients`. The postFrameCallback pattern is already established in Phase 1.

### Pattern 2: Filler Recomputation During Streaming

**What:** During streaming, as the AI response grows, the last item in the list gets taller. `maxScrollExtent` increases. The filler must shrink to compensate so the scroll offset (which is NOT touched during streaming) continues to show the anchored message at the top.

**The invariant to maintain:**

```
scrollOffset + viewportDimension = pixels_of_sent_message_top + viewportDimension
```

Because `scrollOffset` must not change during streaming (ANCH-04), and the sent message sits right above the AI response which is right above the filler, the constraint is:

```
fillerHeight = max(0.0, viewportDimension - extentAfter - sentMessageHeight)
```

where `extentAfter = maxScrollExtent - pixels`.

**Simplified when anchor is at top of visible area:** Since after the initial jump, `pixels = maxScrollExtent - viewportDimension + sentMessageHeight`, we can observe that `extentAfter = viewportDimension - sentMessageHeight`. During streaming, `maxScrollExtent` grows as content grows. The new filler should be:

```
newFillerHeight = max(0.0, oldFillerHeight - delta)
```

where `delta` = growth in `maxScrollExtent` since last frame. This is the cheapest computation: just track `_lastMaxScrollExtent` and compute delta each time the scroll listener fires.

**Example:**

```dart
// Source: derived from Flutter ScrollPosition API
void _onScrollMetricsChanged() {
  if (!_anchorActive || !_scrollController.hasClients) return;
  final pos = _scrollController.position;
  final delta = pos.maxScrollExtent - _lastMaxScrollExtent;
  if (delta > 0) {
    _fillerHeight.value = math.max(0.0, _fillerHeight.value - delta);
    _lastMaxScrollExtent = pos.maxScrollExtent;
  }
}
```

**Registration:** Add this listener in `_AiChatScrollViewState.initState()` via `_scrollController.addListener(_onScrollMetricsChanged)`. Remove in `dispose()`.

**Throttling:** `ScrollController.addListener` fires on every pixel change. During streaming, this may fire many times per frame. Throttle to one update per frame using a `_fillerUpdateScheduled` bool flag + `SchedulerBinding.instance.scheduleFrameCallback` (same pattern as `addPostFrameCallback` but repeating). This prevents redundant `ValueNotifier` assignments within a single frame.

**Simpler throttle pattern:**

```dart
bool _fillerUpdateScheduled = false;

void _onScrollChanged() {
  if (_fillerUpdateScheduled || !_anchorActive) return;
  _fillerUpdateScheduled = true;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _fillerUpdateScheduled = false;
    _recomputeFiller();
  });
}
```

### Pattern 3: User Drag Detection and Anchor Cancellation (API-04)

**What:** Wrap the `CustomScrollView` in a `NotificationListener<ScrollUpdateNotification>`. When `notification.dragDetails != null`, a physical drag is in progress. Set `_anchorActive = false` and stop all filler recomputation.

**Key insight:** `ScrollUpdateNotification.dragDetails` is non-null if and only if the scroll delta was caused by a user drag gesture. Programmatic `jumpTo` calls produce `ScrollUpdateNotification` with `dragDetails == null`. This distinction is documented in the Flutter API and confirmed by the RefreshIndicator source in the Flutter framework itself.

**Implementation:**

```dart
// Source: api.flutter.dev/flutter/widgets/ScrollUpdateNotification/dragDetails.html
NotificationListener<ScrollUpdateNotification>(
  onNotification: (notification) {
    if (notification.dragDetails != null && _anchorActive) {
      _anchorActive = false;
      // No setState needed — _anchorActive is internal control state only
    }
    return false; // do not absorb the notification
  },
  child: CustomScrollView(
    controller: _scrollController,
    slivers: [...],
  ),
)
```

**Return false:** Always return `false` from `onNotification` so the notification bubbles up. The package must not consume scroll notifications that the consumer app might also be listening to.

**Re-enable:** `_anchorActive` is set back to `true` only inside the `postFrameCallback` of `onUserMessageSent()`, just before the `jumpTo`. This is the only re-activation gate.

**Alternative considered:** `UserScrollNotification` with `direction == ScrollDirection.forward || direction == ScrollDirection.reverse`. This fires when the user's scroll *direction* changes, not on every drag update. It is less precise — a stationary hold after a drag would not produce a direction-change notification. The `ScrollUpdateNotification.dragDetails` approach fires on every drag frame, which is exactly what we want.

### Pattern 4: AnchorActive State Machine

**What:** A single `bool _anchorActive` field in `_AiChatScrollViewState` gates all anchor behavior. The state machine:

```
IDLE  -->  [onUserMessageSent]  -->  ANCHORING (filler recomputes, drag detection live)
ANCHORING  -->  [user drag]  -->  IDLE (filler stops updating)
ANCHORING  -->  [onResponseComplete]  -->  IDLE (streaming done, filler locked)
IDLE  -->  [onUserMessageSent again]  -->  ANCHORING (always resets)
```

**Why this field lives in the widget state (not the controller):** The controller drives the jump; the widget state owns the scroll controller and filler notifier. The anchor flag must be co-located with the resources it guards. Communication from controller to widget state: the controller uses `notifyListeners()` (already established); the widget state adds itself as a listener to the controller in `initState` and reacts.

**Controller changes needed:**

```dart
// In AiChatScrollController — add a field the view can query
bool _streaming = false;
bool get isStreaming => _streaming;

void onUserMessageSent() {
  _streaming = true;
  // existing postFrameCallback + notifyListeners
}

void onResponseComplete() {
  _streaming = false;
  notifyListeners(); // widget state listener clears _anchorActive
}
```

### Pattern 5: Single GlobalKey for Sent Message Height

**What:** The `AiChatScrollView` holds one `GlobalKey _anchorKey`. When `onUserMessageSent()` fires (via the controller listener), the widget sets `_anchorIndex = itemCount - 1`. On the next build, the item builder wraps the item at `_anchorIndex` with a `KeyedSubtree(key: _anchorKey, ...)`. After layout (in the `postFrameCallback`), the height is read via:

```dart
final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
final sentMessageHeight = box?.size.height ?? _defaultMessageHeight;
```

**Fallback:** If `box` is null (item scrolled out of lazy list before the postFrameCallback ran — unlikely since the sent message was just added), use a sensible default (e.g., 60dp). The jump will be slightly off but not catastrophic; the filler will self-correct on the next listener callback.

**Why one key is safe:** The prior research warns against a key per message (1000+ keys registered globally). One key is negligible overhead. The key must be reassigned to the correct index on each send — the `_anchorIndex` field ensures this.

**Important:** The item builder must not always wrap with the key. Only `index == _anchorIndex && _anchorActive` should apply the key. Otherwise the key leaks to old items after the next send.

```dart
itemBuilder: (context, index) {
  final child = widget.itemBuilder(context, index);
  if (index == _anchorIndex && _anchorActive) {
    return KeyedSubtree(key: _anchorKey, child: child);
  }
  return child;
}
```

### Pattern 6: Communication Channel — Controller to Widget State

**What:** `_AiChatScrollViewState` adds itself as a listener to `widget.controller` in `initState`. When the controller calls `notifyListeners()`, the widget state's `_onControllerChanged` handler runs.

```dart
@override
void initState() {
  super.initState();
  _fillerHeight = ValueNotifier(0.0);
  _scrollController = ScrollController();
  _scrollController.addListener(_onScrollChanged);
  widget.controller.attach(_scrollController);
  widget.controller.addListener(_onControllerChanged); // NEW
}

void _onControllerChanged() {
  if (widget.controller.isStreaming) {
    // onUserMessageSent just fired
    _anchorIndex = widget.itemCount - 1;
    _anchorActive = true;
    // postFrameCallback for jump is fired by controller internally
  } else {
    // onResponseComplete just fired
    _anchorActive = false;
  }
  // No setState — _anchorActive is not rendered; only _fillerHeight is rendered
}

@override
void dispose() {
  widget.controller.removeListener(_onControllerChanged); // NEW
  widget.controller.detach();
  _scrollController.removeListener(_onScrollChanged);   // NEW
  _fillerHeight.dispose();
  _scrollController.dispose();
  super.dispose();
}
```

**No setState for `_anchorActive`:** The anchor flag is control state, not render state. Only `_fillerHeight.value = ...` produces visible output. This avoids unnecessary widget rebuilds.

### Anti-Patterns to Avoid

- **Calling `jumpTo` during streaming:** Do not jump on every token. The filler absorbs growth passively — scroll position stays fixed. Only one `jumpTo` per `onUserMessageSent` call.
- **`animateTo` for the anchor snap:** The user expects instant response to sending. A 300ms animation creates a disorienting "fly to top" effect. `jumpTo` is correct.
- **Calling `setState` to update `_anchorActive`:** Control flags do not need to trigger a build. Only the `_fillerHeight` ValueNotifier needs to update the tree.
- **Reading `position.maxScrollExtent` before postFrameCallback:** The extent is stale until layout completes. All scroll reads must be inside `postFrameCallback` or listener callbacks (which fire post-layout).
- **`SliverFillRemaining` for filler:** Documented regression in Flutter 3.10+ (flutter/flutter#141376). Already decided: use `SliverToBoxAdapter(child: SizedBox(height: _fillerHeight))` — Phase 2 already implements this correctly.
- **Full list `setState` for filler update:** Already solved in Phase 2 via `ValueNotifier`/`ValueListenableBuilder`. Do not add any `setState` call that would rebuild the sliver list.
- **Returning `true` from `NotificationListener.onNotification`:** Absorbing the notification would prevent the consumer app from receiving scroll events they may depend on.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Detect user drag | Custom `GestureDetector` around the scroll view | `NotificationListener<ScrollUpdateNotification>` with `dragDetails != null` | Framework already dispatches this; GestureDetector can conflict with scroll gesture recognizers |
| Throttle filler updates | `Timer`-based debounce | `SchedulerBinding.addPostFrameCallback` with a bool guard | Frame-aligned throttle is cheaper, avoids timer jitter, and is the established Flutter pattern |
| Measure item height | Layout pass visitor, custom RenderObject | Single `GlobalKey` + `RenderBox.size.height` in `postFrameCallback` | Safe, documented, zero overhead at this scale |
| Track content growth | `onChange` stream from app layer | `ScrollController.addListener` reading `maxScrollExtent` delta | Framework reports extent changes automatically; no app-layer signaling needed |

**Key insight:** The Flutter scroll system already tracks content dimension changes and notifies listeners. This package needs to react, not instrument.

---

## Common Pitfalls

### Pitfall 1: `maxScrollExtent` Reported as Zero on First Frame

**What goes wrong:** Inside `postFrameCallback`, `position.maxScrollExtent` is `0.0` if the list has not performed layout yet (e.g., when `itemCount` goes from 0 to 1 and the widget re-renders in the same frame as the callback was registered).

**Why it happens:** The `postFrameCallback` fires after the frame is drawn, but the list layout happens during that frame's build+layout phase. If the callback was registered synchronously before `setState(() => messages.add(...))`, it runs in the correct frame. If the callback was registered AFTER `setState`, it fires in the next frame — which is correct and safe.

**How to avoid:** Always register the `postFrameCallback` from within `onUserMessageSent()` (which calls `notifyListeners()`, which calls the widget's `_onControllerChanged`, which should NOT register the callback — the controller itself should register it in `onUserMessageSent()` as it already does in Phase 1). Verify the sequence: app calls `setState` to add message → app calls `controller.onUserMessageSent()` → controller registers `postFrameCallback` → next frame: message is laid out → callback runs and reads correct `maxScrollExtent`.

**Warning signs:** `jumpTo` lands at pixel 0.0 (top of list) instead of near the bottom where the sent message appears.

### Pitfall 2: Filler Grows Negative (SizedBox Height < 0)

**What goes wrong:** When the AI response exceeds the viewport height, `viewportDimension - extentAfter - sentMsgHeight` becomes negative. `SizedBox` with negative height throws a Flutter assertion in debug mode.

**How to avoid:** Always clamp: `math.max(0.0, computedHeight)`. This is ANCH-05 behavior by design — when filler hits 0, the response is now taller than the viewport and the user scrolls manually.

**Warning signs:** Red-screen "BoxConstraints forces an infinite width/height" in debug mode.

### Pitfall 3: Anchor Reinstates After User Scrolls Up

**What goes wrong:** If the scroll listener calls `_recomputeFiller()` without checking `_anchorActive`, and the user scrolled up during streaming, the filler recalculation places the wrong height based on the user's new position.

**How to avoid:** Guard every filler mutation with `if (!_anchorActive) return;`. The `NotificationListener` sets `_anchorActive = false` synchronously on first drag frame, so subsequent listener callbacks are no-ops.

### Pitfall 4: `_anchorIndex` Points to Wrong Item After Rapid Sends

**What goes wrong:** User sends a second message before the first AI response completes. `_anchorIndex` points to `itemCount - 1` at the time of the first send. After the second send adds another item, the index is stale by 1.

**How to avoid:** `onUserMessageSent()` always recomputes `_anchorIndex = widget.itemCount - 1` at call time, not at callback registration time. The `postFrameCallback` must capture this index in a local variable to avoid closure-over-mutable-state:

```dart
// WRONG — captures _anchorIndex by reference, may be stale by callback time
SchedulerBinding.instance.addPostFrameCallback((_) {
  _doJump(_anchorIndex); // _anchorIndex may have changed!
});

// CORRECT — capture immediately
final capturedIndex = _anchorIndex;
SchedulerBinding.instance.addPostFrameCallback((_) {
  _doJump(capturedIndex);
});
```

### Pitfall 5: `ScrollController.addListener` Fires During `jumpTo`

**What goes wrong:** When `jumpTo` is called in the `postFrameCallback`, the scroll listener fires (because `pixels` changes). If `_anchorActive` is already set to `true` and `_recomputeFiller` runs, it reads the new `maxScrollExtent` after the jump but before the filler update — producing a spurious filler recalculation.

**How to avoid:** Set `_anchorActive = true` AFTER the `jumpTo` + initial filler assignment, not before. Or guard the filler recomputation with a `_jumpInProgress` bool flag cleared at the end of the postFrameCallback.

**Simpler approach:** Set the initial `_fillerHeight.value` and call `jumpTo` in the same postFrameCallback, then set `_anchorActive = true` at the end. The listener may fire between these two but since `_anchorActive` is not yet `true`, the listener no-ops.

### Pitfall 6: Sending a Message When List Is Empty

**What goes wrong:** `itemCount - 1 = -1`. `GlobalKey` has no item to key. `maxScrollExtent` is 0.

**How to avoid:** Guard `onUserMessageSent()` with `if (itemCount == 0) return;` — or more precisely, wait for the item to be added (the app adds the message before calling `onUserMessageSent()`). Add an assertion:

```dart
assert(
  _scrollController!.hasClients && _scrollController!.position.maxScrollExtent >= 0,
  'onUserMessageSent() called before message was added to the list',
);
```

---

## Code Examples

### Complete Anchor Jump (in postFrameCallback)

```dart
// Source: Flutter ScrollMetrics API — api.flutter.dev/flutter/widgets/ScrollMetrics-mixin.html
// Source: Flutter ScrollController API — api.flutter.dev/flutter/widgets/ScrollController-class.html

void _executeAnchorJump(int anchorIndex) {
  if (!_scrollController.hasClients) return;

  final pos = _scrollController.position;
  final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final sentMsgHeight = box?.size.height ?? 60.0; // 60dp fallback

  // Target: scroll offset that places the sent message top at the viewport top
  final target = (pos.maxScrollExtent - pos.viewportDimension + sentMsgHeight)
      .clamp(pos.minScrollExtent, pos.maxScrollExtent);

  // Initial filler: remaining viewport below the sent message
  final initialFiller = math.max(0.0, pos.viewportDimension - sentMsgHeight);

  _fillerHeight.value = initialFiller;
  _scrollController.jumpTo(target);
  _anchorActive = true;
  _lastMaxScrollExtent = pos.maxScrollExtent;
}
```

### Filler Recomputation During Streaming

```dart
// Source: Flutter ScrollMetrics extentAfter — api.flutter.dev/flutter/widgets/ScrollMetrics/extentAfter.html

bool _fillerUpdateScheduled = false;
double _lastMaxScrollExtent = 0.0;

void _onScrollChanged() {
  if (!_anchorActive || !_scrollController.hasClients) return;
  if (_fillerUpdateScheduled) return;
  _fillerUpdateScheduled = true;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _fillerUpdateScheduled = false;
    if (!_anchorActive || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final growth = pos.maxScrollExtent - _lastMaxScrollExtent;
    if (growth > 0) {
      _fillerHeight.value = math.max(0.0, _fillerHeight.value - growth);
      _lastMaxScrollExtent = pos.maxScrollExtent;
    }
  });
}
```

### User Drag Detection

```dart
// Source: Flutter ScrollUpdateNotification.dragDetails API
// api.flutter.dev/flutter/widgets/ScrollUpdateNotification/dragDetails.html

NotificationListener<ScrollUpdateNotification>(
  onNotification: (notification) {
    if (notification.dragDetails != null && _anchorActive) {
      setState(() => _anchorActive = false);
      // Note: setState IS needed here if _anchorActive affects the build
      // (e.g., to remove the GlobalKey from the item builder)
      // If it only gates the scroll listener, no setState is needed.
    }
    return false; // never absorb
  },
  child: CustomScrollView(
    controller: _scrollController,
    slivers: [
      SliverList.builder(
        itemCount: widget.itemCount,
        itemBuilder: (context, index) {
          final child = widget.itemBuilder(context, index);
          if (index == _anchorIndex && _anchorActive) {
            return KeyedSubtree(key: _anchorKey, child: child);
          }
          return child;
        },
      ),
      SliverToBoxAdapter(
        child: FillerSliver(fillerHeight: _fillerHeight),
      ),
    ],
  ),
)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ListView(reverse: true)` for chat | Forward-growing `CustomScrollView` with filler | Decided pre-phase | Correct coordinate system; `pixels = 0` is visual top |
| `SliverFillRemaining` for spacer | `SliverToBoxAdapter(SizedBox)` with computed height | Flutter 3.10 regression | No keyboard push bug (GitHub #141376) |
| GlobalKey on every item | Single GlobalKey on anchor item | Decided Phase 3 | O(1) global key overhead vs O(n) |
| Full `setState` on filler change | `ValueNotifier` + `ValueListenableBuilder` | Decided Phase 2 | No list rebuilds during streaming |
| Timer-based debounce | `SchedulerBinding.addPostFrameCallback` with bool guard | Established Flutter pattern | Frame-aligned, no timer jitter |

**Current and confirmed (as of Flutter 3.22+):**

- `ScrollUpdateNotification.dragDetails != null` reliably means user drag — this is used by the Flutter framework's own `RefreshIndicator` (MEDIUM confidence — search verified, framework source corroborates)
- `extentAfter = max(maxScrollExtent - pixels, 0.0)` — formula verified via official API docs (HIGH confidence)
- `ScrollController.addListener` fires on BOTH pixel changes AND extent changes — confirmed (HIGH confidence). Use this for filler recomputation.

---

## Open Questions

1. **Does `ScrollController.addListener` fire when `maxScrollExtent` changes but `pixels` does not?**
   - What we know: Pitfalls research (Pitfall 6) says `addListener` fires on pixel changes. `ScrollMetricsNotification` is a separate channel for extent-only changes.
   - What's unclear: During streaming, does content growth at the bottom change `maxScrollExtent` without changing `pixels`? If so, the scroll listener may not fire, and filler won't update.
   - Recommendation: Wrap the `CustomScrollView` in a `NotificationListener<ScrollMetricsNotification>` as well. React to that notification to trigger filler recomputation. This is the pattern recommended in PITFALLS.md (Pitfall 6). Use BOTH `addListener` (for pixel changes) AND `NotificationListener<ScrollMetricsNotification>` (for extent changes without pixel changes). Apply the same frame-throttle guard to the metrics notification handler.

2. **Does the `itemCount` parameter reflect the post-`setState` count at the time `onUserMessageSent()` is called?**
   - What we know: The app is expected to call `setState` to add the message BEFORE calling `onUserMessageSent()`.
   - What's unclear: `widget.itemCount` in `_AiChatScrollViewState` is captured from the widget — it will only reflect the new count after the widget rebuilds, which happens in the next build frame.
   - Recommendation: The controller should accept an explicit `anchorIndex` parameter in `onUserMessageSent(int anchorIndex)` so the app tells the package which index to anchor to. This is cleaner than the widget inferring `itemCount - 1` and avoids the timing hazard. This is an API decision the planner should make explicit.

3. **How does this interact with iOS bouncing scroll physics near the anchor offset?**
   - What we know: STATE.md flags this as an open concern. Bouncing physics can allow `pixels` to temporarily exceed `maxScrollExtent` during overscroll, which would make `extentAfter` negative.
   - What's unclear: Does the `math.max(0.0, ...)` clamp in `extentAfter` (framework formula) protect us, or do we need additional clamping?
   - Recommendation: Always clamp computed filler to `math.max(0.0, ...)` in our code as well. The framework clamps `extentAfter` but we compute filler from our own deltas. Add explicit clamping throughout. Flag for real-device iOS testing.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (bundled with Flutter SDK) |
| Config file | none — flutter_test is auto-discovered |
| Quick run command | `flutter test test/ai_chat_scroll_anchor_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ANCH-01 | After `onUserMessageSent()`, scroll position places last item at viewport top | widget | `flutter test test/ai_chat_scroll_anchor_test.dart -n "ANCH-01"` | Wave 0 |
| ANCH-02 | Filler shrinks as item count increases while anchor active | widget | `flutter test test/ai_chat_scroll_anchor_test.dart -n "ANCH-02"` | Wave 0 |
| ANCH-03 | FillerSliver height decreases from initial value as content grows during anchor | widget | `flutter test test/ai_chat_scroll_anchor_test.dart -n "ANCH-03"` | Wave 0 |
| ANCH-04 | No `jumpTo` call occurs after anchor is set and items are added | widget | `flutter test test/ai_chat_scroll_anchor_test.dart -n "ANCH-04"` | Wave 0 |
| ANCH-05 | Filler clamps to 0 when AI response height exceeds viewportDimension | unit | `flutter test test/ai_chat_scroll_anchor_test.dart -n "ANCH-05"` | Wave 0 |
| ANCH-06 | Second `onUserMessageSent()` call re-anchors to new last item after prior scroll-up | widget | `flutter test test/ai_chat_scroll_anchor_test.dart -n "ANCH-06"` | Wave 0 |
| API-04 | Drag gesture (simulated via `tester.drag`) cancels anchor; subsequent item insertion does not move scroll | widget | `flutter test test/ai_chat_scroll_anchor_test.dart -n "API-04"` | Wave 0 |

### Filler Math Unit Tests (no widget tree needed)

| Behavior | Test Type | Command |
|----------|-----------|---------|
| `computeFillerHeight(viewport, content) = max(0, viewport - content)` | unit | `flutter test test/viewport_math_test.dart` |
| Filler clamps to 0.0 when content > viewport | unit | `flutter test test/viewport_math_test.dart` |
| Filler delta correctly tracks maxScrollExtent growth | unit | `flutter test test/viewport_math_test.dart` |

### Sampling Rate

- **Per task commit:** `flutter test test/ai_chat_scroll_anchor_test.dart test/viewport_math_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** All tests green before verify-work

### Wave 0 Gaps

- [ ] `test/ai_chat_scroll_anchor_test.dart` — covers ANCH-01 through ANCH-06, API-04
- [ ] `test/viewport_math_test.dart` — unit tests for pure filler height math (no widget tree needed; tests `math.max` logic and delta tracking)

---

## Sources

### Primary (HIGH confidence)

- [Flutter ScrollMetrics mixin API](https://api.flutter.dev/flutter/widgets/ScrollMetrics-mixin.html) — `extentAfter`, `viewportDimension`, `maxScrollExtent` formulas
- [Flutter ScrollMetrics.extentAfter API](https://api.flutter.dev/flutter/widgets/ScrollMetrics/extentAfter.html) — confirmed `= max(maxScrollExtent - pixels, 0.0)`
- [Flutter ScrollController API](https://api.flutter.dev/flutter/widgets/ScrollController-class.html) — `jumpTo`, `addListener`, `hasClients`
- [Flutter ScrollPosition API](https://api.flutter.dev/flutter/widgets/ScrollPosition-class.html) — `pixels`, `viewportDimension`, `maxScrollExtent`
- [Flutter ScrollUpdateNotification.dragDetails API](https://api.flutter.dev/flutter/widgets/ScrollUpdateNotification/dragDetails.html) — confirmed `null` = programmatic, non-null = user drag
- [Flutter UserScrollNotification API](https://api.flutter.dev/flutter/widgets/UserScrollNotification-class.html) — direction property, when it fires
- [Flutter ScrollController.jumpTo API](https://api.flutter.dev/flutter/widgets/ScrollController/jumpTo.html) — instant no-animation scroll
- Phase 1 SUMMARY.md — established `addPostFrameCallback + hasClients` guard pattern
- Phase 2 SUMMARY.md — established `ValueNotifier<double>` filler pattern, `_fillerHeight` already exists
- PITFALLS.md — Pitfall 6: `addListener` vs `ScrollMetricsNotification` for extent changes

### Secondary (MEDIUM confidence)

- [Flutter issue #141376: SliverFillRemaining keyboard regression](https://github.com/flutter/flutter/issues/141376) — confirmed `SliverToBoxAdapter` is correct, not `SliverFillRemaining`
- [Flutter issue #80250: Keep scroll position when adding items](https://github.com/flutter/flutter/issues/80250) — confirms content growth handling pattern
- WebSearch: `ScrollUpdateNotification.dragDetails != null` = user drag; `null` = programmatic — corroborated by Flutter RefreshIndicator source usage

### Tertiary (LOW confidence — flag for validation)

- Filler delta tracking via `maxScrollExtent` growth — derived pattern, not directly documented; validate with widget tests during implementation
- iOS bouncing physics interaction with anchor offset — needs real-device testing; not covered by `flutter_test` (emulates clamping physics by default)

---

## Metadata

**Confidence breakdown:**
- Anchor jump math: HIGH — derived from verified `extentAfter` formula and `jumpTo` API
- Filler recomputation: HIGH — ValueNotifier infrastructure from Phase 2, delta math from verified API
- Drag detection: HIGH — `ScrollUpdateNotification.dragDetails` confirmed via API docs and framework source
- Filler delta tracking: MEDIUM — derived pattern; requires widget test validation
- iOS physics interaction: LOW — requires real-device testing

**Research date:** 2026-03-15
**Valid until:** 2026-04-15 (Flutter scroll APIs are stable; 30-day window is conservative)
