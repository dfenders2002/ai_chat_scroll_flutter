# Roadmap: ai_chat_scroll

## Overview

Build and publish a Flutter pub.dev package that implements the top-anchor-on-send scroll pattern for AI chat apps. The work moves from the foundational controller architecture through sliver composition, streaming behavior, edge case hardening, and finally pub.dev publishing readiness. Each phase delivers a coherent, verifiable capability that the next phase depends on.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Controller Foundation** - AiChatScrollController with lifecycle hooks, attach/detach delegation, and package scaffold (completed 2026-03-15)
- [ ] **Phase 2: Sliver Composition** - AiChatScrollView with CustomScrollView, SliverList, and isolated FillerSliver
- [ ] **Phase 3: Streaming Anchor Behavior** - Dynamic filler recomputation, suppressed auto-scroll, and manual scroll resume
- [ ] **Phase 4: Polish and Publishing** - Edge cases, example app, dartdoc, and pub.dev readiness
- [ ] **Phase 5: v1.x Enhancements** - Scroll-to-bottom indicator and keyboard-aware compensation

## Phase Details

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
- [ ] 01-01-PLAN.md — Package scaffold, controller, widget stub, barrel export, and unit tests

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
**Plans**: TBD

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
**Plans**: TBD

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
**Plans**: TBD

### Phase 5: v1.x Enhancements
**Goal**: Post-launch enhancements that improve UX for common scenarios — scroll-to-bottom indicator and keyboard-aware anchor compensation
**Depends on**: Phase 4
**Requirements**: ENHN-01, ENHN-02
**Success Criteria** (what must be TRUE):
  1. When the user has scrolled away from the latest messages, a scroll-to-bottom button or indicator appears and tapping it returns the user to the latest message
  2. When the soft keyboard opens or closes, the anchor position adjusts so the user's sent message remains visible at the top of the visible area (not obscured by the keyboard)
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Controller Foundation | 1/1 | Complete   | 2026-03-15 |
| 2. Sliver Composition | 0/? | Not started | - |
| 3. Streaming Anchor Behavior | 0/? | Not started | - |
| 4. Polish and Publishing | 0/? | Not started | - |
| 5. v1.x Enhancements | 0/? | Not started | - |
