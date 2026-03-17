# ai_chat_scroll

## What This Is

A Flutter package for pub.dev that provides AI-chat-optimized scroll behavior for mobile apps. When a user sends a message, their message anchors to the top of the viewport and the AI response streams downward below it — no auto-scroll chasing the response. This solves a UX problem that has no clean solution in Flutter today: the "top-anchor-on-send" pattern used by apps like Claude's mobile client.

## Core Value

When a user sends a message in an AI chat, that message snaps to the top of the viewport and the AI response grows below it — the user is never disoriented or auto-scrolled away from their own message.

## Current Milestone: v2.0 — Dual-Layout Scroll Redesign

**Goal:** Redesign the scroll system around two layout modes (rest vs active-turn) with auto-follow streaming, a 5-state machine, smart down-button, and content-bounded dynamic spacing.

**Target features:**
- Two layout modes: rest (bottom-aligned) and active-turn (user message near top, AI streams below)
- Auto-follow during streaming — viewport tracks growing AI response
- 5-state machine: idle_at_bottom, submitted_waiting_response, streaming_following, streaming_detached, history_browsing
- Smart down-button that jumps to active turn composition (not absolute bottom)
- Content-bounded dynamic spacing — filler from viewport positioning, not static padding
- Response completion transition — settles to rest layout after streaming ends
- Inputbar/keyboard/safe-area awareness in all offset calculations

## Requirements

### Validated

- ✓ Reverse list support (newest at bottom) — v1.0
- ✓ Top-anchor-on-send: viewport snaps user message to top — v1.0
- ✓ AI response streams below user message — v1.0
- ✓ Dynamic filler space management during streaming — v1.0
- ✓ AiChatScrollController with onUserMessageSent()/onResponseComplete() — v1.0
- ✓ AiChatScrollView wrapper widget with itemBuilder/itemCount API — v1.0
- ✓ User drag cancels managed scroll behavior — v1.0
- ✓ Scroll-to-bottom indicator (isAtBottom + scrollToBottom) — v1.0
- ✓ Keyboard-aware anchor compensation — v1.0
- ✓ Package published on pub.dev with docs, example, zero deps — v1.0

### Active

- [ ] Two layout modes: rest (bottom-aligned) and active-turn (user message near top with reading area)
- [ ] Auto-follow during streaming — viewport tracks AI response growth
- [ ] 5-state machine with clean transitions between scroll states
- [ ] Smart down-button: jumps to active turn composition (user msg + AI start), not absolute bottom
- [ ] Content-bounded dynamic spacing — no scrollable empty area below content
- [ ] Response completion: transition from active-turn to rest layout
- [ ] Inputbar/keyboard/safe-area awareness in all offset calculations
- [ ] Re-anchor from any scroll position on send (force jump to active turn)

### Out of Scope

- Chat UI components (message bubbles, input fields, avatars) — scroll logic only
- Streaming/AI integration — consuming app handles that and signals the controller
- Message state management — devs manage their own message list
- Desktop/web scroll behavior — mobile-first
- Animated anchor transitions — v2.1 candidate

### Out of Scope

- Chat UI components (message bubbles, input fields, avatars) — this is scroll logic only
- Streaming/AI integration — the consuming app handles that and signals the controller
- Message state management — devs manage their own message list
- Desktop/web scroll behavior — targeting mobile (iOS/Android) first
- Pagination / infinite scroll for loading older messages — may revisit in v2

## Context

- This is the author's first pub.dev package
- The behavior is inspired by Claude's iOS/Android mobile app: on sending a message, the user's message sits at the top of the viewport with the AI response streaming below
- Flutter's built-in `ListView(reverse: true)` and sliver-based approaches don't cleanly support this "top-anchor" pattern — you end up fighting the scroll physics
- The author has a separate app with full chat/streaming logic already built; this package extracts just the scroll behavior
- Target audience: Flutter developers building AI chat interfaces who want this specific scroll UX

## Constraints

- **Platform**: Flutter (Dart), targeting iOS and Android
- **Distribution**: pub.dev package with proper pubspec.yaml, LICENSE, README, example
- **Dependencies**: Minimize external dependencies — rely on Flutter framework APIs (ScrollController, CustomScrollView, Slivers)
- **API surface**: Must be simple to integrate — a controller + a widget wrapper, not a framework

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Controller + Widget approach | Too bare as controller-only (error-prone), too opinionated as full widget. Sweet spot is controller with lightweight wrapper. | — Pending |
| Include reverse list behavior | Users expect reverse-chronological chat + the anchor behavior as one cohesive system | — Pending |
| No UI components | Keep scope tight — scroll behavior only. Devs bring their own chat UI. | — Pending |
| Mobile-first | The anchor behavior is a mobile UX pattern. Desktop/web can come later. | — Pending |

---
*Last updated: 2026-03-17 after v2.0 milestone start*
