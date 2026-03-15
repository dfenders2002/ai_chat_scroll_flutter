# ai_chat_scroll

## What This Is

A Flutter package for pub.dev that provides AI-chat-optimized scroll behavior for mobile apps. When a user sends a message, their message anchors to the top of the viewport and the AI response streams downward below it — no auto-scroll chasing the response. This solves a UX problem that has no clean solution in Flutter today: the "top-anchor-on-send" pattern used by apps like Claude's mobile client.

## Core Value

When a user sends a message in an AI chat, that message snaps to the top of the viewport and the AI response grows below it — the user is never disoriented or auto-scrolled away from their own message.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Reverse list support (newest messages at bottom, older messages load on scroll up)
- [ ] Top-anchor-on-send: when user sends a message, viewport snaps so their message is at the top
- [ ] AI response streams below the user message, growing downward
- [ ] No auto-scroll during AI streaming — user stays positioned at their message
- [ ] If AI response exceeds viewport, user manually scrolls to see the rest
- [ ] When user scrolls up to history then sends a new message, viewport jumps back to anchor new message at top
- [ ] Exposes `AiChatScrollController` with methods like `onUserMessageSent()` and `onResponseComplete()`
- [ ] Exposes `AiChatScrollView` wrapper widget that devs wrap around their own ListView/CustomScrollView
- [ ] Dynamic filler space management below AI response during streaming
- [ ] Package is publishable on pub.dev with proper structure, documentation, and example

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
*Last updated: 2026-03-15 after initialization*
