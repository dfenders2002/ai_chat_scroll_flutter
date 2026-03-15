# Requirements: ai_chat_scroll

**Defined:** 2026-03-15
**Core Value:** When a user sends a message in an AI chat, that message snaps to the top of the viewport and the AI response grows below it — the user is never disoriented or auto-scrolled away.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Scroll Core

- [x] **SCRL-01**: Chat displays messages in reverse-chronological order (newest at bottom, older above)
- [x] **SCRL-02**: No visible scroll jank when new messages are inserted into the list
- [x] **SCRL-03**: Scroll position is preserved when user has scrolled up into message history
- [x] **SCRL-04**: Works correctly on both iOS (bouncing physics) and Android (clamping physics)

### Anchor Behavior

- [x] **ANCH-01**: When user sends a message, viewport snaps so the user's message is at the top of the viewport
- [x] **ANCH-02**: AI response streams below the user message, growing downward within the viewport
- [x] **ANCH-03**: Dynamic filler space is rendered below the AI response to keep the anchor stable during streaming
- [x] **ANCH-04**: No auto-scroll occurs during AI streaming — user stays positioned at their sent message
- [x] **ANCH-05**: If AI response exceeds the viewport, user must manually scroll down to see the rest
- [x] **ANCH-06**: When user scrolls up to history then sends a new message, viewport resets to top-anchor pattern with new message at top

### API Surface

- [x] **API-01**: Package exposes `AiChatScrollController` with `onUserMessageSent()` method to trigger anchor behavior
- [x] **API-02**: Package exposes `AiChatScrollController` with `onResponseComplete()` method to signal end of AI streaming
- [x] **API-03**: Package exposes `AiChatScrollView` wrapper widget that devs wrap around their own message list
- [x] **API-04**: User drag cancels any managed scroll behavior — no re-hijacking until next `onUserMessageSent()`

### Enhancements

- [ ] **ENHN-01**: Scroll-to-bottom FAB/indicator appears when user has scrolled away from the latest messages
- [ ] **ENHN-02**: Keyboard-aware scroll compensation — anchor position adjusts when soft keyboard opens/closes

### Package Quality

- [ ] **QUAL-01**: Package has proper pub.dev structure (pubspec.yaml, LICENSE, README, CHANGELOG)
- [ ] **QUAL-02**: Package includes a working example app demonstrating the scroll behavior
- [ ] **QUAL-03**: All public APIs have dartdoc documentation
- [x] **QUAL-04**: Package has zero runtime dependencies (Flutter SDK only)
- [ ] **QUAL-05**: Package passes `dart analyze` with no warnings and `pana` with a high score

## v2 Requirements

### Enhancements

- **ENHN-03**: Configurable animation curves for the anchor snap (instead of instant jump)
- **ENHN-04**: RTL / bidirectional layout support

### Platform

- **PLAT-01**: Desktop and web scroll support with appropriate physics

### Advanced

- **ADV-01**: Pagination / infinite scroll for loading older message history
- **ADV-02**: Accessibility: `SemanticsService.announce` for new messages
- **ADV-03**: Observability callbacks for scroll state (analytics / testing)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Chat UI components (message bubbles, input fields, avatars) | This is scroll logic only — devs bring their own UI |
| Streaming / AI integration | Consuming app handles streaming and signals the controller |
| Message state management | Devs manage their own message list with their own state solution |
| Auto-scroll-to-bottom during streaming | This is the anti-pattern this package exists to solve |
| Configurable scroll physics (v1) | Premature; add only if pub.dev issues request it |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| API-01 | Phase 1 | Complete |
| API-02 | Phase 1 | Complete |
| QUAL-04 | Phase 1 | Complete |
| API-03 | Phase 2 | Complete |
| SCRL-01 | Phase 2 | Complete |
| SCRL-02 | Phase 2 | Complete |
| SCRL-03 | Phase 2 | Complete |
| SCRL-04 | Phase 2 | Complete |
| ANCH-01 | Phase 3 | Complete |
| ANCH-02 | Phase 3 | Complete |
| ANCH-03 | Phase 3 | Complete |
| ANCH-04 | Phase 3 | Complete |
| ANCH-05 | Phase 3 | Complete |
| ANCH-06 | Phase 3 | Complete |
| API-04 | Phase 3 | Complete |
| QUAL-01 | Phase 4 | Pending |
| QUAL-02 | Phase 4 | Pending |
| QUAL-03 | Phase 4 | Pending |
| QUAL-05 | Phase 4 | Pending |
| ENHN-01 | Phase 5 | Pending |
| ENHN-02 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0

---
*Requirements defined: 2026-03-15*
*Last updated: 2026-03-15 after roadmap creation*
