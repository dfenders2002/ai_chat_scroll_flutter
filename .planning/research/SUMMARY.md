# Project Research Summary

**Project:** ai_chat_scroll v2.0 — Dual-Layout Scroll Redesign
**Domain:** Flutter pub.dev scroll behavior package (AI chat viewport anchoring)
**Researched:** 2026-03-17
**Confidence:** HIGH

## Executive Summary

The v2.0 milestone for `ai_chat_scroll` is a well-scoped additive extension of a working v1 foundation. The core problem is formalizing what was a two-boolean scroll state (`_anchorActive`, `_streaming`) into a proper 5-state machine (`idleAtBottom`, `submittedWaitingResponse`, `streamingFollowing`, `streamingDetached`, `historyBrowsing`) that can cleanly gate two new behaviors: auto-follow during streaming and intentional detach when the user scrolls away. All required Flutter APIs are available within the already-constrained Flutter >=3.22.0 floor. No pubspec changes, no new runtime dependencies — the entire implementation is native Flutter SDK on top of existing v1 primitives.

The recommended architecture is controller-owns-state, widget-is-reactor. `AiChatScrollController` owns the `ValueNotifier<AiChatScrollState>` and all transition logic; `_AiChatScrollViewState` reacts to state changes and drives layout through two modes: REST (filler = 0, content bottom-aligned) and ACTIVE-TURN (filler = `viewport - userMsgHeight`, top-anchored). This single filler-as-layout-knob pattern means no new widget tree branching is needed — both modes are expressed as different values of the existing `_fillerHeight` ValueNotifier. The key competitive differentiator is the explicit state machine with clean detach/re-attach semantics and the dual-layout model. Claude's own iOS app implements exactly this behavior, but no Flutter package currently provides it.

The top risk is state management drift: incrementally adding boolean flags instead of migrating to the enum at the start of v2. Every feature built on boolean flags will require a rewrite, and invalid state combinations cause subtle, hard-to-reproduce bugs at edge cases. The mitigation is strict: define the `AiChatScrollState` enum and migrate the controller in the first phase, before any new behavioral code is written. Secondary risks include re-entrant `ScrollMetricsNotification` loops during auto-follow and phantom filler after response completion — both have well-defined prevention strategies.

## Key Findings

### Recommended Stack

The v2.0 stack requires zero changes to `pubspec.yaml`. Flutter >=3.22.0 / Dart ^3.4.0 already covers all needed APIs. The implementation is pure Flutter SDK: `ScrollMetricsNotification` + `ScrollUpdateNotification` + `UserScrollNotification` for event sourcing, Dart `enum` with exhaustive `switch` for the state machine, and `ValueNotifier<AiChatScrollState>` for reactive state broadcast. `SliverFillRemaining` remains explicitly rejected due to the post-3.10 keyboard regression (GitHub #141376); the computed `SizedBox` via `ValueListenableBuilder` pattern from v1 is retained unchanged.

**Core technologies:**
- `Dart enum` + exhaustive switch: 5-state machine — adding a new state without updating all switch sites is a compile error; no library needed
- `ScrollMetricsNotification`: auto-follow content-growth detection — already used in v1; v2 gates on `streamingFollowing` state only
- `ScrollUpdateNotification.dragDetails != null`: user drag detection — triggers `streamingFollowing → streamingDetached` transition
- `UserScrollNotification.direction`: scroll direction detection — triggers `idleAtBottom → historyBrowsing` transition
- `ValueNotifier<AiChatScrollState>`: reactive state broadcast — exposes `scrollState` as `ValueListenable` so consuming apps drive FAB/UI without polling
- `jumpTo` (not `animateTo`) for auto-follow compensation — synchronous, no inter-frame lag, no visible jitter during fast streaming
- `ClampingScrollPhysics` explicitly on `CustomScrollView` — prevents `BouncingScrollPhysics` pixel overshoot from corrupting `maxScrollExtent` delta calculations

### Expected Features

The feature research surveyed ChatGPT, Claude (iOS), `react-native-streaming-message-list`, `stream_chat_flutter`, and `flutter_chat_ui`. No existing Flutter package provides dual layout modes combined with a formal state machine and auto-follow with clean detach/re-attach semantics. The closest analog is `react-native-streaming-message-list` (React Native only).

**Must have (table stakes for v2.0):**
- Auto-follow during streaming when user has not scrolled away — ChatGPT, Claude, Gemini all do this; missing it is a visible regression from user expectation
- Scroll-detach on user drag during streaming — failing to stop auto-follow on drag is the single worst scroll UX bug in AI chat apps
- Re-attach to auto-follow when user returns to bottom — required for detach to be a recoverable, usable mechanism
- Scroll-to-bottom FAB visibility via exposed `isAtBottom` / `scrollState` — every major chat app shows this affordance; it is now table stakes, not a differentiator
- Re-anchor from history on new message send — was a v1.0 differentiator; is a v2.0 baseline expectation

**Should have (v2.0 differentiators):**
- Formal 5-state machine with `scrollState` ValueNotifier on controller — no Flutter package exposes this; enables consuming app UI to react to scroll phase
- Dual layout modes (rest vs. active-turn) with explicit transition — no Flutter package models these as distinct visual modes
- Smart down-button target: scroll to active-turn composition, not absolute bottom — mirrors Claude iOS behavior; distinguishes "smart" from naive `maxScrollExtent`
- Content-bounded dynamic spacing — eliminates v1 overscroll-into-empty-space bug
- Response completion transition: active-turn to rest layout — closes the loop; without this the layout stays stuck in active-turn after streaming ends

**Defer (v2.x / v3+):**
- Unread-content boolean indicator — add after v2.0 ships if issues are filed
- Animated layout mode transitions — extremely complex with anchor points changing mid-animation; skip until v2.0 instant transitions prove problematic to real users
- RTL / bidirectional text layout
- Pagination / infinite scroll for message history — distinct technical problem, out of scope
- Desktop / web scroll support — mobile-first is correct; desktop needs separate physics strategy

### Architecture Approach

The v2.0 architecture is additive: no component is deleted. The core sliver composition (`CustomScrollView` + `SliverList` + `FillerSliver`) is unchanged. The two significant mutations are (1) replacing the `_anchorActive` / `_streaming` booleans with `ValueNotifier<AiChatScrollState>` on the controller, and (2) changing the `_onMetricsChanged` guard from a boolean check to a state check. A single new file `lib/src/models/ai_chat_scroll_state.dart` holds the enum. The public API surface adds only one new symbol: `controller.scrollState` (a `ValueListenable<AiChatScrollState>`). All existing method signatures are unchanged.

**Major components:**
1. `AiChatScrollController` — owns the 5-state machine; all transitions are methods on this class; exposes `scrollState` ValueListenable and smart `scrollToBottom()` that targets the active-turn anchor offset in active states
2. `AiChatScrollState` enum (new file) — single vocabulary source for the state machine; exhaustive switch gives compile-time safety against unhandled states
3. `_AiChatScrollViewState` — reacts to controller state; drives REST vs ACTIVE-TURN layout via `_fillerHeight` ValueNotifier; sources scroll notification events back to the controller via named trigger methods
4. `FillerSliver` (unchanged) — still driven by `_fillerHeight`; REST = 0.0, ACTIVE = `max(0, viewport - userMsgHeight)`

### Critical Pitfalls

1. **Boolean flag proliferation instead of state enum** — Adding `_userScrolledAway` and `_historyBrowsing` alongside the existing two booleans produces 8 theoretical flag combinations but only 5 valid scroll states; the 3 invalid combinations cause silent misbehavior at edge cases. Prevention: define `AiChatScrollState` enum and migrate the controller at the very start of v2, before any new behavior is wired. This is the gating architectural decision.

2. **Auto-follow compensation fighting user drag** — `ScrollMetricsNotification` fires during a drag, reads a stale `_lastMaxScrollExtent`, computes a spurious positive delta, calls `jumpTo`, overriding the user's gesture mid-scroll. Prevention: gate `_onMetricsChanged` exclusively on `state == streamingFollowing`; the drag handler must transition to `streamingDetached` before the metrics handler can fire, or state gating makes the metrics handler a no-op when detached.

3. **Phantom filler after response completion** — `onResponseComplete()` clears `_anchorActive` but does not reset `_fillerHeight`. The filler remains non-zero, creating a scrollable empty area above content; `isAtBottom` semantics break. Prevention: `_transitionToRest()` must (1) set `_fillerHeight.value = 0.0`, then (2) wait one `postFrameCallback`, then (3) `jumpTo(maxScrollExtent)`. The frame wait is mandatory because `maxScrollExtent` still reflects old filler height at the time of a synchronous call.

4. **Re-entrant ScrollMetricsNotification loop** — Filler change triggers a metrics notification which triggers another filler change, looping until the 0.5-delta threshold terminates it. Each cycle calls `jumpTo`, causing visible jitter during streaming. Prevention: gate all filler updates with a `_fillerUpdateInProgress` boolean guard, or route all filler changes through a single `postFrameCallback` so at most one filler update fires per frame.

5. **Stale `_anchorReverseIndex` on re-send from history** — If the user sends a new message while `historyBrowsing` without a prior `onResponseComplete()` clearing the anchor, the `GlobalKey` still targets the old user message and `_measureAndAnchor()` computes the wrong filler value. Prevention: define `_clearAnchorState()` and call it at the start of every `_enterActiveMode()` invocation, regardless of which state triggered it.

## Implications for Roadmap

All phases build on a clear dependency chain from architecture research. The state enum must come first — every behavioral gate reads it. The controller state machine must precede any widget behavioral changes. Auto-follow and history detection are independent once widget reactions are in place. Smart down-button and content-bounded spacing validation come last because they depend on the anchor offset stored during active-turn entry.

### Phase 1: State Machine Foundation

**Rationale:** All v2 behavior gates on the state enum. Building auto-follow, detach, or history-browsing before the enum exists forces a rewrite. The state machine is also pure Dart — no widget tests needed; fast to build and verify in isolation. Migrating the two existing booleans to the enum before any new code eliminates boolean proliferation risk permanently.

**Delivers:** `AiChatScrollState` enum (new file), controller state machine replacing `_anchorActive` / `_streaming`, `scrollState` ValueListenable on controller, `_clearAnchorState()` helper, all v1 widget tests passing with zero regressions.

**Addresses:** Exposed `scrollState` controller property (FEATURES.md differentiator); `isAtBottom` + `scrollToBottom()` correctness preservation; v1 API compatibility contract locked.

**Avoids:** Pitfall 1 (boolean proliferation), Pitfall 5 (stale anchor on re-send — `_clearAnchorState()` defined here), Pitfall 8 (breaking v1 API — v1 test suite gates this phase).

### Phase 2: Auto-Follow + Scroll Detach

**Rationale:** Auto-follow is the primary new behavior and the reason for the v2.0 version bump. Detach is its mandatory companion — auto-follow without detach is the worst scroll UX bug in AI chat apps. These behaviors are tightly coupled through the `streamingFollowing ↔ streamingDetached` edge and must be built and tested together.

**Delivers:** Auto-follow in `streamingFollowing` state via gated `_onMetricsChanged`, scroll-detach to `streamingDetached` on `ScrollUpdateNotification.dragDetails != null`, re-attach to `streamingFollowing` when user returns to bottom threshold.

**Uses:** `ScrollMetricsNotification` + `ScrollUpdateNotification` NotificationListener pattern from STACK.md; `jumpTo` for synchronous auto-follow compensation.

**Avoids:** Pitfall 2 (auto-follow vs. drag conflict — drag transitions state before metrics handler fires), Pitfall 4 (re-entrant notification loop — `_fillerUpdateInProgress` guard).

**Research flag:** Standard Flutter notification patterns; no additional phase research needed.

### Phase 3: Dual Layout Modes + Response Completion Transition

**Rationale:** The dual layout (REST vs. ACTIVE-TURN) and the REST-transition on completion are functionally one feature — REST mode is defined by the transition that enters it. Building them together prevents phantom filler from slipping through as a separate, untested integration boundary.

**Delivers:** REST mode (filler = 0, content bottom-aligned), explicit `_transitionToRest()` with frame-deferred `jumpTo`, `historyBrowsing` state detection via `isAtBottom` feedback, response completion settling to REST without phantom filler.

**Avoids:** Pitfall 3 (phantom filler — frame-deferred reset), Pitfall 5 in content-bounded form (ghost scroll region after item count drops — validated via `didUpdateWidget` comparison).

**Research flag:** Standard patterns built on existing filler mechanism; no additional research needed.

### Phase 4: Smart Down-Button + Content-Bounded Spacing Validation

**Rationale:** Both require `_activeTurnScrollOffset` stored during `_enterActiveMode()` which is established in earlier phases. Smart down-button is a cross-cutting verification that the anchor offset is correctly stored and accessed. Content-bounded validation is the formal sign-off that filler ≤ 0 is enforced across all edge cases including conversation clear.

**Delivers:** State-aware `scrollToBottom()` that jumps to active-turn anchor offset (not `maxScrollExtent`) in active states; content-bounded filler invariant verified in short-conversation and conversation-clear scenarios; full "looks done but isn't" checklist from PITFALLS.md executed.

**Avoids:** Pitfall 6 (smart down-button wrong target), ghost scroll after conversation clear.

**Research flag:** The active-turn anchor offset coordinate math under `reverse: true` with iOS bouncing physics is listed as MEDIUM confidence in both STACK.md and ARCHITECTURE.md. If offset calculation from existing `_measureAndAnchor()` code is not straightforward, a targeted research-phase is warranted before implementation.

### Phase 5: Integration + Regression Hardening

**Rationale:** All individual behaviors are built; this phase cross-validates the complete state machine against the "looks done but isn't" checklist from PITFALLS.md and verifies zero v1 regressions.

**Delivers:** Full v1 test suite passing; new integration tests covering rapid consecutive sends, history-browse re-send, drag mid-stream, keyboard open during streaming; `onResponseComplete()` ordering contract documented; integration gotcha for `onUserMessageSent()` during `streamingFollowing` (rapid send) resolved in transition table.

**Avoids:** Pitfall 8 (breaking v1 API — explicit regression gate before any v2.0 release).

**Research flag:** Verification and documentation only; no new APIs.

### Phase Ordering Rationale

- **State machine first** because every behavioral gate reads the enum; building behavior before the enum exists creates debt that must be torn down at rewrite cost.
- **Auto-follow + detach together** because they share the `streamingFollowing ↔ streamingDetached` edge; testing one without the other cannot verify the critical conflict-resolution guarantee.
- **REST layout + completion together** because REST mode is meaningless without the transition that enters it; splitting creates a phase that cannot be independently verified end-to-end.
- **Smart down-button last among features** because it depends on `_activeTurnScrollOffset` being correctly populated by the earlier anchor pipeline.
- **Regression hardening as its own phase** because it crosses all earlier phases; slipping it into individual phases risks gaps at integration boundaries.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4 (smart down-button):** The active-turn anchor offset coordinate math in the `reverse: true` CustomScrollView coordinate system, particularly under iOS `BouncingScrollPhysics`, is MEDIUM confidence per both STACK.md and ARCHITECTURE.md. If the offset calculation is not directly readable from the existing `_measureAndAnchor()` code during Phase 4 planning, run a targeted research-phase before implementation begins.

Phases with standard patterns (skip research-phase):
- **Phase 1 (state machine):** Pure Dart enum + exhaustive switch; fully documented in official Dart docs; zero unknowns.
- **Phase 2 (auto-follow):** `ScrollMetricsNotification` gating is an extension of already-working v1 code; only the guard condition changes.
- **Phase 3 (dual layout):** Filler-as-layout-knob is the existing mechanism; REST = filler 0 is a trivially verified change to an already-working path.
- **Phase 5 (regression):** Verification and documentation only; no new Flutter APIs.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs verified against official Flutter docs; version constraints confirmed compatible through Flutter 3.41.2 (Dart 3.11); no runtime dependency additions needed; `SliverFillRemaining` rejection confirmed via GitHub #141376 |
| Features | MEDIUM-HIGH | Behavioral survey of ChatGPT, Claude, react-native-streaming-message-list confirmed; stream_chat_flutter and flutter_chat_ui docs confirmed FAB as table stakes; some blog sources returned 403 but patterns were corroborated by multiple independent sources |
| Architecture | HIGH | Based on direct reading of all v1 source files; build order derived from actual code dependencies; controller-owns-state pattern is established and already partially present in v1's `_onControllerChanged` structure |
| Pitfalls | HIGH | v1 implementation experience provides high-confidence pitfall identification; re-entrant notification loop sourced from official Flutter issue tracker (#121419); performance pitfalls confirmed by flutter_chat_ui issue #577 |

**Overall confidence:** HIGH

### Gaps to Address

- **Smart down-button coordinate math under `reverse: true`:** ARCHITECTURE.md notes MEDIUM confidence on the exact offset for the active-turn anchor in the `reverse: true` coordinate system under iOS bouncing physics. Needs device validation in Phase 4; not a blocker for Phases 1-3.
- **`onUserMessageSent()` during `streamingFollowing` (rapid send):** The current transition table has no `streamingFollowing → submittedWaitingResponse` rule. Phase 1 must define explicit behavior (queue, force-complete, or reject with documentation) before Phase 2 auto-follow is built on top of it.
- **Consumer ordering contract for `onResponseComplete()`:** Must be called only after the consumer's final streaming `setState` is committed. This is an integration gotcha (documented in PITFALLS.md) that belongs in the public API dartdoc; must be written before v2.0 ships.

## Sources

### Primary (HIGH confidence)
- Flutter ScrollController, ScrollPosition, ScrollMetricsNotification, ScrollUpdateNotification, ScrollEndNotification, UserScrollNotification API docs — verified all v2.0 APIs are available in Flutter >=3.22.0
- `lib/src/controller/ai_chat_scroll_controller.dart` (v1 direct read) — basis for controller architecture decisions
- `lib/src/widgets/ai_chat_scroll_view.dart` (v1 direct read) — filler mechanism and notification handler patterns
- `.planning/STATE.md`, `.planning/PROJECT.md` — accumulated v1 decisions and v2.0 requirements
- flutter/flutter issue #121419 — re-entrant scroll notification loop (official tracker)
- flyerhq/flutter_chat_ui issue #577 — full-list rebuild via setState confirmed catastrophic (official tracker)
- TanStack/virtual Discussion #730 — direct implementation discussion of detach/re-attach pattern with real approaches

### Secondary (MEDIUM confidence)
- react-native-streaming-message-list (GitHub) — closest cross-platform behavioral analog; feature design confirmed
- stream_chat_flutter ScrollToBottomButton docs — confirmed FAB as expected UI affordance
- flyerhq/flutter_chat_ui Discussion #163 — scroll-to-bottom FAB feature request, confirmed shipped in v2
- PromptLayer blog on ChatGPT autoscroll — confirmed detach-on-scroll, re-attach-on-return-to-bottom behavior
- Doctolib engineering blog (Medium) — AI chat scroll patterns on mobile (403 on direct fetch; search summary corroborated patterns)

### Tertiary (LOW confidence)
- Dart 3 pattern matching state machine — sandromaglione.com (community article; pattern confirmed by official Dart docs)
- Flutter 3.41 "What's new" blog — 403 on direct fetch; no scroll breaking changes inferred from release notes survey

---
*Research completed: 2026-03-17*
*Ready for roadmap: yes*
