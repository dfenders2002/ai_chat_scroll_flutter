# Architecture Research

**Domain:** Flutter scroll behavior package — v2.0 Dual-Layout Scroll Redesign
**Researched:** 2026-03-17
**Confidence:** HIGH (based on direct reading of all existing source files and v1 phase summaries)

---

## Context: What Already Exists (v1 Architecture)

The following components are fully implemented and tested in v1:

| Component | File | Status |
|-----------|------|--------|
| `AiChatScrollController` | `lib/src/controller/ai_chat_scroll_controller.dart` | Keep, extend |
| `AiChatScrollView` / `_AiChatScrollViewState` | `lib/src/widgets/ai_chat_scroll_view.dart` | Keep, extend |
| `FillerSliver` | `lib/src/widgets/filler_sliver.dart` | Keep as-is |
| `ValueNotifier<double> _fillerHeight` | Inside `_AiChatScrollViewState` | Keep, logic changes |
| `_anchorActive` flag | Inside `_AiChatScrollViewState` | Replace with state machine |
| `isStreaming` bool | On `AiChatScrollController` | Replace with state machine |
| `isAtBottom` ValueListenable | On `AiChatScrollController` | Keep, expose via state |
| `scrollToBottom()` | On `AiChatScrollController` | Keep, update target |

The v2.0 work **adds** behavior on top of this foundation. No component is deleted outright — the core sliver composition (CustomScrollView + SliverList + FillerSliver) and the controller/widget attachment pattern are preserved unchanged.

---

## Standard Architecture

### System Overview (v2.0)

```
┌─────────────────────────────────────────────────────────────────┐
│                     Consumer App Layer                           │
│  - Calls onUserMessageSent() / onResponseComplete()             │
│  - Listens to scrollState / isAtBottom ValueListenables         │
│  - Builds their own down-button FAB from exposed signals        │
└──────────────────────────┬──────────────────────────────────────┘
                           │ public API
┌──────────────────────────▼──────────────────────────────────────┐
│               AiChatScrollController (ChangeNotifier)            │
│                                                                  │
│  scrollState: ValueListenable<AiChatScrollState>  ← new        │
│  isAtBottom:  ValueListenable<bool>               ← v1, keep   │
│                                                                  │
│  onUserMessageSent()     ← transitions state machine            │
│  onResponseComplete()    ← transitions state machine            │
│  scrollToBottom()        ← jumps to active-turn anchor, not 0   │
│                                                                  │
│  attach(ScrollController) / detach()   ← unchanged              │
└──────────────────────────┬──────────────────────────────────────┘
                           │ ChangeNotifier listener
┌──────────────────────────▼──────────────────────────────────────┐
│               _AiChatScrollViewState (StatefulWidget)           │
│                                                                  │
│  _AiChatScrollState (state machine reactions)  ← new           │
│  _fillerHeight: ValueNotifier<double>          ← v1, keep      │
│  _anchorKey: GlobalKey                         ← v1, keep      │
│  _lastMaxScrollExtent: double                  ← v1, keep      │
│  _lastViewportDimension: double                ← v1, keep      │
│  _activeTurnAnchorOffset: double               ← new           │
│                                                                  │
│  Layout mode:                                                    │
│    REST     → filler = 0, list bottom-aligns naturally          │
│    ACTIVE   → filler = viewport - userMsgHeight, scroll=max     │
└──────────────────────────┬──────────────────────────────────────┘
                           │ drives
┌──────────────────────────▼──────────────────────────────────────┐
│               CustomScrollView (reverse: true)                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  SliverToBoxAdapter → FillerSliver (ValueListenableBuilder)│  │
│  │  SliverList.builder  → message items (itemBuilder)         │  │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities (v2.0 Additions)

| Component | Responsibility | Modification vs v1 |
|-----------|----------------|-------------------|
| `AiChatScrollController` | Public API. Owns and transitions the 5-state machine. Exposes `scrollState` ValueListenable. Smart `scrollToBottom()` that jumps to active-turn anchor position, not absolute 0. | Add `AiChatScrollState` enum + `ValueNotifier<AiChatScrollState>`. Replace `_streaming` bool with state machine. |
| `AiChatScrollState` | Enum of 5 scroll states: `idleAtBottom`, `submittedWaitingResponse`, `streamingFollowing`, `streamingDetached`, `historyBrowsing`. Encapsulates which behaviors are active. | New file: `lib/src/models/ai_chat_scroll_state.dart` |
| `_AiChatScrollViewState` | Widget state. Reacts to `scrollState` transitions from controller. Drives layout mode (rest vs active-turn), auto-follow during streaming, and viewport anchoring. | Existing file. Replace `_anchorActive` bool with state-reactive methods. Add auto-follow trigger. Add `_activeTurnAnchorOffset` for smart down-button. |
| `FillerSliver` | Unchanged. Still driven by `_fillerHeight` ValueNotifier. | No changes needed. |
| `_fillerHeight` ValueNotifier | REST mode: 0.0. ACTIVE mode: `viewport - userMsgHeight`. Auto-follow: shrinks as AI response grows (existing `_onMetricsChanged` logic). | Logic changes: filler resets to 0 on transition to REST. |

---

## Recommended Project Structure (v2.0)

```
lib/
├── ai_chat_scroll.dart              # Barrel: adds AiChatScrollState to exports
└── src/
    ├── controller/
    │   └── ai_chat_scroll_controller.dart   # Extended: state machine + scrollToBottom update
    ├── models/
    │   └── ai_chat_scroll_state.dart        # NEW: AiChatScrollState enum
    ├── widgets/
    │   ├── ai_chat_scroll_view.dart         # Extended: state reactions, auto-follow, layout modes
    │   └── filler_sliver.dart               # Unchanged
    └── utils/
        └── viewport_math.dart               # Optional: extract filler calculation if it grows
test/
├── state_machine_test.dart          # NEW: transition table tests (pure Dart)
├── auto_follow_test.dart            # NEW: streaming follow behavior
├── dual_layout_test.dart            # NEW: rest vs active-turn layout
├── down_button_test.dart            # NEW: scrollToBottom anchor target
├── keyboard_compensation_test.dart  # Existing: unchanged
├── scroll_to_bottom_indicator_test.dart  # Existing: update assertions if needed
└── ...existing tests...
```

---

## Architectural Patterns

### Pattern 1: 5-State Machine in the Controller

**What:** `AiChatScrollController` owns a `ValueNotifier<AiChatScrollState>` and drives all transitions. The widget observes the state and reacts — it does not contain transition logic.

**When to use:** Any time behavior depends on "what mode are we in". Replaces ad-hoc boolean flags (`_anchorActive`, `_streaming`) that proliferate as features grow.

**Trade-offs:** Adds one new enum and replaces two booleans. Slightly more code upfront; pays off immediately when adding auto-follow (third state), detach-on-drag (fourth state), and history-browsing (fifth state) — each is just a transition rule, not a new boolean.

**State transition table:**

```
Event                         From State(s)                   To State
─────────────────────────────────────────────────────────────────────
onUserMessageSent()           any                             submittedWaitingResponse
first AI token arrives        submittedWaitingResponse        streamingFollowing
user drags during streaming   streamingFollowing              streamingDetached
onResponseComplete()          streamingFollowing              idleAtBottom
onResponseComplete()          streamingDetached               idleAtBottom
user scrolls away from bottom idleAtBottom                    historyBrowsing
user scrolls back to bottom   historyBrowsing                 idleAtBottom
onUserMessageSent()           historyBrowsing                 submittedWaitingResponse
```

**Where transitions live:** `AiChatScrollController` — all state transitions are methods or reactions on the controller. The widget calls controller methods; it does not directly mutate state.

**Example:**
```dart
enum AiChatScrollState {
  idleAtBottom,
  submittedWaitingResponse,
  streamingFollowing,
  streamingDetached,
  historyBrowsing,
}

class AiChatScrollController extends ChangeNotifier {
  final _scrollState = ValueNotifier(AiChatScrollState.idleAtBottom);
  ValueListenable<AiChatScrollState> get scrollState => _scrollState;

  void onUserMessageSent() {
    _scrollState.value = AiChatScrollState.submittedWaitingResponse;
    notifyListeners(); // widget reacts: trigger anchor jump
  }

  // Called by widget when first streaming metrics change arrives
  void _onStreamingBegan() {
    if (_scrollState.value == AiChatScrollState.submittedWaitingResponse) {
      _scrollState.value = AiChatScrollState.streamingFollowing;
    }
  }

  // Called by widget when user drags during streaming
  void _onUserDragDuringStreaming() {
    if (_scrollState.value == AiChatScrollState.streamingFollowing) {
      _scrollState.value = AiChatScrollState.streamingDetached;
    }
  }
}
```

**Integration point:** The controller owns the state machine. The widget is a pure reactor — it listens and drives layout, never transitions state directly except through controller calls.

### Pattern 2: Dual Layout Modes via Filler Reset

**What:** Two layout modes are expressed purely through the filler height value — no separate widget tree branching required.

- **REST mode** (`idleAtBottom`, `historyBrowsing`): `_fillerHeight = 0`. The CustomScrollView's `reverse: true` physics naturally bottom-aligns content. No filler means content grows from the bottom.
- **ACTIVE-TURN mode** (`submittedWaitingResponse`, `streamingFollowing`, `streamingDetached`): `_fillerHeight = max(0, viewport - userMsgHeight)`. The user's sent message sits at the top of the viewport.

**Trade-offs:** Very low complexity — the existing filler infrastructure handles both modes. The only new logic is explicitly resetting filler to 0 on transition to REST.

**Transition to REST (on response complete):**
```dart
// In _AiChatScrollViewState, reacting to onResponseComplete:
_fillerHeight.value = 0.0;
_activeTurnAnchorOffset = null;
```

**Transition to ACTIVE (on user sends message):**
```dart
// Existing _startAnchor() logic, renamed _enterActiveMode():
// 1. Attach GlobalKey to anchor item
// 2. Measure userMsgHeight
// 3. _fillerHeight.value = max(0, viewport - userMsgHeight)
// 4. jumpTo(maxScrollExtent)
// 5. Record _activeTurnAnchorOffset = current scroll offset
```

### Pattern 3: Auto-Follow via ScrollMetricsNotification (Extended v1 Behavior)

**What:** The existing `_onMetricsChanged` handler already implements auto-follow (compensates scroll offset when `maxScrollExtent` grows during streaming). v2.0 makes this conditional on state: only active in `streamingFollowing`, not in `streamingDetached`.

**v1 behavior:**
```dart
void _onMetricsChanged(ScrollMetricsNotification n) {
  if (!_anchorActive) return;  // boolean gate
  // ... delta compensation ...
}
```

**v2.0 behavior:**
```dart
void _onMetricsChanged(ScrollMetricsNotification n) {
  final state = widget.controller.scrollState.value;
  if (state != AiChatScrollState.streamingFollowing) return;  // state gate
  // ... same delta compensation logic, unchanged ...
}
```

The auto-follow code itself does not change — only the gate condition changes from a boolean to a state check.

**Triggering `streamingFollowing` from `submittedWaitingResponse`:** The first `ScrollMetricsNotification` with a positive delta (content growing) signals that AI tokens have begun arriving. The widget calls `controller._onStreamingBegan()` at that point.

### Pattern 4: Smart Down-Button via Stored Anchor Offset

**What:** `scrollToBottom()` in v1 jumps to `maxScrollExtent` (absolute bottom). In v2.0, when in ACTIVE-TURN mode, it should jump to the active-turn composition point (just above the AI response start), not to the very bottom of the growing AI response.

**Implementation:** Store `_activeTurnAnchorOffset` in the widget state when the anchor jump executes. Expose it back to the controller via a callback or make `scrollToBottom()` stateful.

**Simplest approach:** Add an optional `double? activeTurnScrollOffset` field to `AiChatScrollController`. The widget writes it when the anchor jump completes. `scrollToBottom()` uses it when non-null.

```dart
// In AiChatScrollController:
double? _activeTurnScrollOffset;

void scrollToBottom() {
  if (_scrollController == null || !_scrollController!.hasClients) return;
  final target = _activeTurnScrollOffset ?? _scrollController!.position.maxScrollExtent;
  _scrollController!.animateTo(target, duration: ..., curve: ...);
}
```

**Integration point:** Widget sets `controller._activeTurnScrollOffset` at end of `_executeAnchorJump()`. Widget clears it when transitioning back to REST mode.

### Pattern 5: Content-Bounded Spacing (Filler ≥ 0 Invariant)

**What:** The filler is `max(0, viewport - userMsgHeight)`. When the AI response grows enough that the user message plus response fills the viewport, the filler reaches 0 and stays there. No negative filler, no scrollable empty area below content.

**Status:** This is already enforced in v1 (`math.max(0.0, viewport - userMsgHeight)`). v2.0 must preserve this invariant through all state transitions.

**Critical moment:** When `onResponseComplete()` fires, filler resets to 0 explicitly. If filler was already 0 (AI response exceeded viewport height), this is a no-op — correct behavior.

---

## Data Flow

### On User Message Sent (v2.0)

```
App: setState() adds user message to list
    ↓
App: controller.onUserMessageSent()
    ↓
AiChatScrollController:
  - _scrollState → submittedWaitingResponse
  - notifyListeners()
    ↓
_AiChatScrollViewState._onControllerChanged():
  - Detects submittedWaitingResponse
  - addPostFrameCallback → _enterActiveMode()
    ↓
_enterActiveMode():
  - setState(_anchorReverseIndex = 0) → GlobalKey attaches to user msg
  - addPostFrameCallback → _measureAndAnchor()
    ↓
_measureAndAnchor():
  - Measures userMsgHeight via GlobalKey RenderBox
  - _fillerHeight.value = max(0, viewport - userMsgHeight)
  - addPostFrameCallback → jumpTo(maxScrollExtent)
  - _activeTurnScrollOffset stored on controller
    ↓
Viewport: user message at top, filler occupies space below it
```

### During Streaming (v2.0)

```
App: setState() appends tokens to AI response message
    ↓
SliverList child grows → ScrollMetricsNotification fires
    ↓
_AiChatScrollViewState._onMetricsChanged():
  - Check scrollState == streamingFollowing
  - If state == submittedWaitingResponse AND delta > 0:
      → controller._onStreamingBegan()   (first token)
  - delta compensation: jumpTo(offset + delta)   (auto-follow)
    ↓
Viewport: user message stays at top, AI response grows below it
    ↓
User drags during streaming:
  → NotificationListener<ScrollUpdateNotification> fires
  → dragDetails != null → controller._onUserDragDuringStreaming()
  → state: streamingFollowing → streamingDetached
  → _onMetricsChanged gate fails → no more auto-follow
```

### On Response Complete (v2.0)

```
App: controller.onResponseComplete()
    ↓
AiChatScrollController:
  - _scrollState → idleAtBottom
  - notifyListeners()
    ↓
_AiChatScrollViewState._onControllerChanged():
  - Detects idleAtBottom
  - _fillerHeight.value = 0.0          (REST layout)
  - controller._activeTurnScrollOffset = null
  - setState(_anchorReverseIndex = -1)  (remove GlobalKey)
    ↓
Viewport: settles to REST layout (bottom-aligned, no filler)
```

### History Browse → Re-Send (v2.0)

```
User scrolls up → isAtBottom becomes false
  → controller receives updateIsAtBottom(false)
  → if state == idleAtBottom: _scrollState → historyBrowsing

User sends message while browsing history:
  → controller.onUserMessageSent()
  → _scrollState: historyBrowsing → submittedWaitingResponse
  → Same anchor pipeline as "On User Message Sent" above
  → Force-jumps from any position to active-turn anchor
```

### Key Data Flows Summary

1. **State drives layout:** All behavioral branching reads `scrollState`. No scattered `_anchorActive` booleans.
2. **Widget writes state triggers only through controller methods:** Widget never sets `_scrollState` directly — only calls named methods on the controller.
3. **Filler is the single layout knob:** REST = filler 0, ACTIVE = filler computed. No secondary layout mechanism needed.
4. **Auto-follow is unchanged code, changed gate:** The delta-compensation in `_onMetricsChanged` is unmodified from v1 — only the guard condition changes.

---

## Component Modification Map

### Components That Change

| Component | What Changes | Why |
|-----------|-------------|-----|
| `AiChatScrollController` | Replace `_streaming: bool` with `_scrollState: ValueNotifier<AiChatScrollState>`. Add `_onStreamingBegan()`, `_onUserDragDuringStreaming()` internal triggers. Add `_activeTurnScrollOffset`. Update `scrollToBottom()` to use anchor offset. | State machine replaces booleans. Smart down-button needs anchor offset. |
| `_AiChatScrollViewState` | Replace `_anchorActive` bool with state machine reactions. Gate `_onMetricsChanged` on `streamingFollowing`. Add `historyBrowsing` detection in `_onScrollChanged`. Reset filler to 0 on REST transition. Store `_activeTurnScrollOffset`. | All behavior changes flow from state machine. |

### Components That Do NOT Change

| Component | Reason Unchanged |
|-----------|-----------------|
| `FillerSliver` | Still driven by `_fillerHeight` ValueNotifier. No behavior change. |
| `CustomScrollView` composition | `reverse: true`, SliverList + SliverToBoxAdapter — unchanged. |
| `attach()` / `detach()` lifecycle | Controller attachment pattern is identical. |
| `isAtBottom` ValueListenable | Still driven by `_onScrollChanged`. |
| `_measureAndAnchor()` pipeline | Unchanged — still measures via GlobalKey, sets filler, jumpTo. |
| `viewportDimension` keyboard compensation | Unchanged — `_onViewportDimensionChanged()` logic is identical. |
| Public API shape (`onUserMessageSent`, `onResponseComplete`) | Same method signatures. State machine is an internal implementation detail. |

### New Components

| Component | File | Purpose |
|-----------|------|---------|
| `AiChatScrollState` enum | `lib/src/models/ai_chat_scroll_state.dart` | 5-state machine enum. Exported from barrel. |

---

## Build Order (Phase Dependencies)

The new features have clear dependencies that dictate build order:

```
1. AiChatScrollState enum (new file, pure Dart)
   → No dependencies. Unit-testable in isolation.
   → Defines the vocabulary all other phases use.
        ↓
2. State machine in AiChatScrollController
   → Replace _streaming bool with ValueNotifier<AiChatScrollState>
   → Add transition methods
   → Existing tests must still pass (same external API)
        ↓
3. Widget state reactions (replace _anchorActive with state gate)
   → _onMetricsChanged gates on streamingFollowing
   → _onControllerChanged reacts to state, not isStreaming
   → REST transition: filler → 0 on idleAtBottom
        ↓
4. Auto-follow streaming (streamingFollowing → streamingDetached on drag)
   → Depends on step 3 (state gate in _onMetricsChanged)
   → Depends on step 2 (streamingDetached state exists)
        ↓
5. historyBrowsing state detection
   → Depends on step 2 (historyBrowsing state exists)
   → Hooks into existing _onScrollChanged
        ↓
6. Smart down-button (scrollToBottom uses anchor offset)
   → Depends on step 3 (anchor offset stored during _enterActiveMode)
   → Depends on step 2 (state check in scrollToBottom)
        ↓
7. Content-bounded spacing validation
   → Verify filler=0 is enforced on REST transition (step 3)
   → Verify no negative filler in edge cases (already enforced by max(0,...))
        ↓
8. Response completion transition (REST layout after streaming)
   → Validate filler reset + GlobalKey removal on onResponseComplete()
   → Mostly covered by step 3; explicit visual validation needed
```

**Rationale:** The state enum (step 1) and controller state machine (step 2) are pure-Dart and can be built/tested without widget tests. The widget reactions (step 3) depend on the controller's new state shape. Auto-follow (step 4) and history detection (step 5) are independent after step 3 and can be built in parallel. Smart down-button (step 6) requires the anchor offset stored in step 3. Validation steps (7, 8) are cross-cutting and come last.

---

## Anti-Patterns (v2.0-Specific)

### Anti-Pattern 1: Boolean Proliferation Instead of State Machine

**What people do:** Add `_isFollowing`, `_isDetached`, `_isHistory` as separate booleans alongside the existing `_anchorActive` and `_streaming`.

**Why it's wrong:** With 5 conceptual states and 2 boolean flags already present, adding 3 more creates 32 theoretical combinations but only ~5 valid ones. Bugs from invalid state combinations become almost certain. Each new feature requires reasoning about all flag combinations.

**Do this instead:** Replace ALL the booleans with `AiChatScrollState`. One enum, 5 named values, explicit transition table. Invalid states are impossible by construction.

### Anti-Pattern 2: Putting Transition Logic in the Widget

**What people do:** Put `if (scrollState == x) { scrollState = y; }` directly in `_AiChatScrollViewState` scroll handlers.

**Why it's wrong:** Transitions become scattered across both controller and widget. Testing transitions requires a widget test harness, not a unit test. The public API is no longer the only place state changes.

**Do this instead:** All transitions in `AiChatScrollController`. Widget calls named controller methods when triggering conditions are detected (user drag, first streaming token). State transitions are unit-testable without Flutter.

### Anti-Pattern 3: Resetting Filler to Non-Zero on Response Complete

**What people do:** On `onResponseComplete()`, leave the filler at its last streaming value (non-zero) and let subsequent messages "naturally" flow.

**Why it's wrong:** The filler represents virtual space below the last user message. If it stays non-zero after streaming ends, new messages sent later will anchor incorrectly — the viewport math assumes filler=0 in REST mode.

**Do this instead:** Explicitly set `_fillerHeight.value = 0.0` as the first action when transitioning to `idleAtBottom`. The reset is cheap and makes subsequent anchor computations correct.

### Anti-Pattern 4: Auto-Follow in All Active States

**What people do:** Run the delta-compensation logic whenever `scrollState` is any active state (submittedWaitingResponse, streamingFollowing, streamingDetached).

**Why it's wrong:** In `streamingDetached`, the user has explicitly scrolled away to read the response. Continuing to chase the scroll position overrides the user's intent — this is the exact behavior v2.0 is designed to prevent.

**Do this instead:** Gate auto-follow exclusively on `streamingFollowing`. When the user drags, transition to `streamingDetached` and the gate immediately stops auto-follow.

---

## Integration Points (v2.0)

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `AiChatScrollController` ↔ `_AiChatScrollViewState` | Controller exposes `scrollState` ValueListenable; widget listens via `addListener`. Widget calls named trigger methods on controller (`_onStreamingBegan`, `_onUserDragDuringStreaming`). | These trigger methods are internal (prefixed `_` or package-private). Not part of the public API. |
| `AiChatScrollController` ↔ App | Same public API as v1: `onUserMessageSent()`, `onResponseComplete()`, `scrollToBottom()`, `isAtBottom`, plus new `scrollState` ValueListenable. | `scrollState` is the only new public surface. |
| `_AiChatScrollViewState` ↔ `FillerSliver` | Unchanged: `_fillerHeight` ValueNotifier drives filler `SizedBox`. | REST transition adds explicit `_fillerHeight.value = 0.0`. |
| `AiChatScrollController._activeTurnScrollOffset` ↔ widget | Widget writes this internal field via a setter or internal method during anchor jump. Controller reads it in `scrollToBottom()`. | Keep the field internal (`_`). Expose write access via a package-internal setter if needed. |

### What the Consuming App Sees (v2.0 Public API Delta)

| Addition | Type | Purpose |
|----------|------|---------|
| `AiChatScrollState` enum | New export | Allows app to observe state for conditional UI |
| `controller.scrollState` | `ValueListenable<AiChatScrollState>` | Observable current state |

Everything else is the same as v1. `onUserMessageSent()`, `onResponseComplete()`, `isAtBottom`, `scrollToBottom()`, `atBottomThreshold` are unchanged in signature.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| State machine placement (controller) | HIGH | Controller-owns-state is established Flutter pattern; widget-as-reactor matches existing `_onControllerChanged` structure |
| Filler as layout mode knob | HIGH | Filler is already the sole layout mechanism; REST=0, ACTIVE=computed follows naturally |
| Auto-follow gate change (boolean → state) | HIGH | Existing `_onMetricsChanged` code is unchanged; only the guard condition changes |
| Smart down-button via stored anchor offset | MEDIUM | Pattern is straightforward but the exact offset math under BouncingScrollPhysics (iOS) needs device validation |
| `historyBrowsing` detection via `isAtBottom` | HIGH | `isAtBottom` already fires on every scroll change; adding a state transition there is trivial |
| Build order | HIGH | Dependency chain is clear from reading the existing code |

---

## Sources

- `lib/src/controller/ai_chat_scroll_controller.dart` — v1 controller, direct read (HIGH confidence)
- `lib/src/widgets/ai_chat_scroll_view.dart` — v1 widget state, direct read (HIGH confidence)
- `lib/src/widgets/filler_sliver.dart` — v1 filler widget, direct read (HIGH confidence)
- `.planning/phases/05-v1x-enhancements/05-01-SUMMARY.md` — isAtBottom/scrollToBottom decisions (HIGH confidence)
- `.planning/phases/05-v1x-enhancements/05-02-SUMMARY.md` — keyboard compensation math invariant (HIGH confidence)
- `.planning/STATE.md` — accumulated decisions from v1 (HIGH confidence)
- `.planning/PROJECT.md` — v2.0 feature requirements (HIGH confidence)

---
*Architecture research for: ai_chat_scroll v2.0 — Dual-Layout Scroll Redesign*
*Researched: 2026-03-17*
