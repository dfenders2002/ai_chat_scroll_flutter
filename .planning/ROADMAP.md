# Roadmap: ai_chat_scroll

## Milestones

- ✅ **v1.0 — AI Chat Scroll MVP** - Phases 1-5 (shipped 2026-03-15)
- 🚧 **v2.0 — Dual-Layout Scroll Redesign** - Phases 6-10 (in progress)

## Phases

<details>
<summary>✅ v1.0 — AI Chat Scroll MVP (Phases 1-5) — SHIPPED 2026-03-15</summary>

### Phase 1: Controller Foundation
**Goal**: A working AiChatScrollController exists with correct attach/detach lifecycle, the addPostFrameCallback scroll dispatch pattern, and a publishable package scaffold
**Depends on**: Nothing (first phase)
**Requirements**: API-01, API-02, QUAL-04
**Success Criteria** (what must be TRUE):
  1. A developer can instantiate AiChatScrollController and call onUserMessageSent() and onResponseComplete() without errors
  2. The controller attaches and detaches from its internal ScrollController correctly — no memory leaks on dispose
  3. The package builds with zero runtime dependencies (Flutter SDK only) and passes dart analyze with no warnings
  4. The barrel export (lib/ai_chat_scroll.dart) exposes only AiChatScrollController and AiChatScrollView publicly
**Plans:** 1/1 plans complete

Plans:
- [x] 01-01-PLAN.md — Package scaffold, controller, widget stub, barrel export, and unit tests

### Phase 2: Sliver Composition
**Goal**: AiChatScrollView renders a message list in reverse-chronological order using forward-growing CustomScrollView with an isolated FillerSliver — no jank on insertion
**Depends on**: Phase 1
**Requirements**: API-03, SCRL-01, SCRL-02, SCRL-03, SCRL-04
**Success Criteria** (what must be TRUE):
  1. A developer wraps their ListView replacement with AiChatScrollView and messages display newest-at-bottom with older messages above
  2. Inserting a new message at the bottom does not cause visible scroll jank or jump when the user is at the latest position
  3. When the user has scrolled up into history, their scroll position is preserved after a new message is inserted
  4. The widget behaves correctly on both iOS (bouncing physics) and Android (clamping physics) without scroll physics fighting
  5. The FillerSliver updates its height without triggering a full message list rebuild
**Plans:** 1/1 plans complete

Plans:
- [x] 02-01-PLAN.md — Sliver composition: FillerSliver, builder API migration, and widget tests

### Phase 3: Streaming Anchor Behavior
**Goal**: Sending a message snaps the user's message to the top of the viewport, AI response grows below it without auto-scroll, and user drag correctly cancels managed scroll behavior
**Depends on**: Phase 2
**Requirements**: ANCH-01, ANCH-02, ANCH-03, ANCH-04, ANCH-05, ANCH-06, API-04
**Success Criteria** (what must be TRUE):
  1. When the user sends a message, the viewport immediately snaps so that message is flush at the top — no scroll chase, no delay
  2. As the AI response streams in below the user's message, the filler shrinks and the response grows — the user's message stays at the top of the viewport throughout
  3. During streaming, no automatic scrolling occurs — the user remains anchored at their sent message
  4. If the AI response grows longer than the viewport, the user can manually scroll down to read the rest and the package does not re-hijack scroll position
  5. When the user has scrolled up to read old messages and then sends a new message, the viewport resets and the new message anchors at the top
  6. A user drag during a managed scroll immediately cancels that scroll — the package does not resume control until onUserMessageSent() is called again
**Plans:** 2/2 plans complete

Plans:
- [x] 03-01-PLAN.md — Anchor jump, streaming filler recomputation, and controller state (ANCH-01 through ANCH-06)
- [x] 03-02-PLAN.md — User drag cancellation via NotificationListener (API-04)

### Phase 4: Polish and Publishing
**Goal**: The package handles all edge cases correctly, has a working example app, full dartdoc coverage, and passes pub.dev quality checks
**Depends on**: Phase 3
**Requirements**: QUAL-01, QUAL-02, QUAL-03, QUAL-05
**Success Criteria** (what must be TRUE):
  1. The example app runs on both iOS and Android simulators and demonstrates the anchor behavior with simulated AI streaming
  2. Every public symbol (AiChatScrollController, AiChatScrollView, onUserMessageSent, onResponseComplete) has dartdoc documentation
  3. dart pub publish --dry-run completes with zero warnings or errors
  4. The pana score is >= 120/160 (pub points sufficient for discoverability)
  5. README.md contains a minimal integration example that a developer can copy-paste to get the behavior working
**Plans:** 2/2 plans complete

Plans:
- [x] 04-01-PLAN.md — Metadata polish (README, CHANGELOG, pubspec) and dartdoc audit
- [x] 04-02-PLAN.md — Example app with streaming simulation and final pub.dev verification

### Phase 5: v1.x Enhancements
**Goal**: Post-launch enhancements that improve UX for common scenarios — scroll-to-bottom indicator API and keyboard-aware anchor compensation
**Depends on**: Phase 4
**Requirements**: ENHN-01, ENHN-02
**Success Criteria** (what must be TRUE):
  1. When the user has scrolled away from the latest messages, controller.isAtBottom reports false and scrollToBottom() returns to latest — devs build their own FAB using this signal
  2. When the soft keyboard opens or closes, the anchor position adjusts so the user's sent message remains visible at the top of the visible area (not obscured by the keyboard)
**Plans:** 2/2 plans complete

Plans:
- [x] 05-01-PLAN.md — Scroll-to-bottom indicator API (isAtBottom ValueListenable + scrollToBottom method)
- [x] 05-02-PLAN.md — Keyboard-aware anchor compensation via viewportDimension change detection

</details>

### v2.0 — Dual-Layout Scroll Redesign (In Progress)

**Milestone Goal:** Redesign the scroll system around two layout modes (rest vs. active-turn) with auto-follow streaming, a 5-state machine, smart down-button, and content-bounded dynamic spacing.

#### Phase 6: State Machine Foundation
**Goal**: The scroll system is governed by a formal 5-state enum that replaces boolean flags, with all transitions defined and exposed as a reactive ValueNotifier
**Depends on**: Phase 5
**Requirements**: STATE-01, STATE-02, STATE-03
**Success Criteria** (what must be TRUE):
  1. A consuming app can read controller.scrollState and observe one of five named states (idleAtBottom, submittedWaitingResponse, streamingFollowing, streamingDetached, historyBrowsing) — no boolean flags exposed
  2. Calling onUserMessageSent() transitions state to submittedWaitingResponse and calling onResponseComplete() while at bottom transitions to idleAtBottom — confirmed by widget test assertions on the ValueNotifier
  3. All v1.0 existing widget tests pass without modification — no public API signatures changed
  4. dart analyze reports zero warnings or errors after the migration
**Plans:** 1/1 plans complete

Plans:
- [ ] 06-01-PLAN.md — AiChatScrollState enum, controller migration from booleans, scrollState ValueListenable, full transition table

#### Phase 7: Auto-Follow and Scroll Detach
**Goal**: During streaming the viewport automatically tracks the growing AI response, detaches immediately when the user drags away, and re-attaches when the user returns to the live bottom
**Depends on**: Phase 6
**Requirements**: FOLLOW-01, FOLLOW-02, FOLLOW-03
**Success Criteria** (what must be TRUE):
  1. During streamingFollowing state, each new AI token that pushes content below the current viewport is immediately compensated — the newest text is always visible without the user scrolling
  2. When the user drags upward during streaming, auto-follow stops on the very next frame and state changes to streamingDetached — the viewport does not jump or fight the drag
  3. After detaching, tapping the down-button or manually scrolling back to the live bottom resumes auto-follow and transitions state back to streamingFollowing
  4. Auto-follow compensation never fires while in streamingDetached state — no spurious jumpTo calls corrupt user-initiated scroll position
**Plans:** 1/1 plans complete

Plans:
- [ ] 07-01-PLAN.md — State-gated auto-follow compensation, drag detach, scroll-back re-attach (TDD)

#### Phase 8: Dual Layout Modes and Response Completion
**Goal**: The chat viewport operates in two visually distinct modes — rest (bottom-aligned) and active-turn (user message near top with reading area below) — and transitions cleanly between them on response completion, with all offsets accounting for the inputbar and keyboard
**Depends on**: Phase 7
**Requirements**: LAYOUT-01, LAYOUT-02, LAYOUT-03, LAYOUT-04, INPUT-01
**Success Criteria** (what must be TRUE):
  1. In rest mode (idleAtBottom or historyBrowsing), the last message sits directly above the inputbar — no empty filler space is visible or scrollable below it
  2. After onUserMessageSent(), the user's sent message appears near the top of the viewport with the AI response growing below in a clear reading area — the inputbar and keyboard do not obscure the anchor position
  3. When onResponseComplete() is called and the user is at the live bottom, the layout transitions to rest mode — filler is zeroed and content settles above the inputbar with no phantom scrollable area remaining
  4. With a short conversation (fewer messages than fill the viewport), the user cannot scroll down into empty space in any state
  5. When the keyboard is open during an active-turn, the anchor offset correctly accounts for keyboard height and safe area so the user's message is not hidden behind the keyboard
**Plans**: TBD

Plans:
- [ ] 08-01: REST mode layout (filler = 0), ACTIVE-TURN mode (filler = viewport - userMsgHeight), layout mode switching
- [ ] 08-02: Response completion transition (_transitionToRest with frame-deferred jumpTo), content-bounded filler invariant, INPUT-01 offset calculations

#### Phase 9: Smart Down-Button
**Goal**: The down-button visibility signal fires when new content exists below the viewport, and the down-button action jumps to the active-turn composition view rather than absolute scroll bottom
**Depends on**: Phase 8
**Requirements**: DBUTTON-01, DBUTTON-02
**Success Criteria** (what must be TRUE):
  1. When the user is in streamingDetached state with new tokens arriving below, the down-button visibility signal is true — the consuming app can show a FAB without polling
  2. Tapping the down-button during an active streaming turn scrolls to show the user's sent message near the top with the current AI response start visible — not to the very bottom of all content
  3. Tapping the down-button in rest mode or historyBrowsing (no active turn) scrolls to the absolute latest message as expected
**Plans**: TBD

Plans:
- [ ] 09-01: State-aware scrollToBottom() targeting active-turn anchor offset in active states, down-button visibility signal for streamingDetached with new content

#### Phase 10: Integration and Regression Hardening
**Goal**: All v2.0 behaviors hold together under edge-case sequences, v1.0 behavior is fully preserved, and the public API contract is documented for the new state machine
**Depends on**: Phase 9
**Requirements**: (cross-validation — all 13 v2.0 requirements verified together)
**Success Criteria** (what must be TRUE):
  1. Rapid consecutive sends (onUserMessageSent() called before previous onResponseComplete()) do not corrupt scroll state or produce an invalid state transition
  2. A user who sends a message, scrolls into history, then sends another message while still browsing history gets a clean re-anchor to the new active turn with no filler artifacts
  3. All v1.0 public API symbols (AiChatScrollController, AiChatScrollView, onUserMessageSent, onResponseComplete, isAtBottom, scrollToBottom) behave identically to v1.0 for consumers not using the new state API
  4. The controller.scrollState dartdoc accurately describes each state, every transition trigger, and the onResponseComplete() ordering contract
**Plans**: TBD

Plans:
- [ ] 10-01: Integration test suite (rapid send, history-browse re-send, drag mid-stream, keyboard during streaming), full v1 regression gate, API documentation audit

## Progress

**Execution Order:**
Phases execute in numeric order: 6 -> 7 -> 8 -> 9 -> 10

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Controller Foundation | v1.0 | 1/1 | Complete | 2026-03-15 |
| 2. Sliver Composition | v1.0 | 1/1 | Complete | 2026-03-15 |
| 3. Streaming Anchor Behavior | v1.0 | 2/2 | Complete | 2026-03-15 |
| 4. Polish and Publishing | v1.0 | 2/2 | Complete | 2026-03-15 |
| 5. v1.x Enhancements | v1.0 | 2/2 | Complete | 2026-03-15 |
| 6. State Machine Foundation | 1/1 | Complete   | 2026-03-17 | - |
| 7. Auto-Follow and Scroll Detach | 1/1 | Complete   | 2026-03-17 | - |
| 8. Dual Layout Modes and Response Completion | v2.0 | 0/TBD | Not started | - |
| 9. Smart Down-Button | v2.0 | 0/TBD | Not started | - |
| 10. Integration and Regression Hardening | v2.0 | 0/TBD | Not started | - |
