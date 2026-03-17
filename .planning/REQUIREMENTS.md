# Requirements: ai_chat_scroll v2.0

**Defined:** 2026-03-17
**Core Value:** When a user sends a message in an AI chat, that message snaps to the top of the viewport and the AI response grows below it — the user is never disoriented or auto-scrolled away.

## v2.0 Requirements

Requirements for the dual-layout scroll redesign. Each maps to roadmap phases.

### State Machine

- [ ] **STATE-01**: Scroll system uses a 5-state enum (`idleAtBottom`, `submittedWaitingResponse`, `streamingFollowing`, `streamingDetached`, `historyBrowsing`) replacing boolean flags
- [ ] **STATE-02**: State transitions are event-driven: `onUserMessageSent()` → submittedWaitingResponse, first AI token → streamingFollowing, user drag during streaming → streamingDetached, down-button tap → streamingFollowing, `onResponseComplete()` at bottom → idleAtBottom, `onResponseComplete()` away from bottom → historyBrowsing
- [ ] **STATE-03**: Scroll state is exposed as `ValueNotifier<AiChatScrollState>` so consuming apps can build conditional UI (e.g., different FAB behavior per state)

### Auto-Follow

- [ ] **FOLLOW-01**: During `streamingFollowing` state, viewport automatically tracks the growing AI response so newest tokens remain visible
- [ ] **FOLLOW-02**: When user drags upward during streaming, auto-follow stops immediately and state transitions to `streamingDetached`
- [ ] **FOLLOW-03**: Auto-follow resumes when user taps down-button or manually scrolls back to live bottom, transitioning state to `streamingFollowing`

### Layout Modes

- [ ] **LAYOUT-01**: In rest mode (`idleAtBottom`, `historyBrowsing`), the chat displays with last content above the inputbar — normal bottom-aligned chat layout
- [ ] **LAYOUT-02**: In active-turn mode (`submittedWaitingResponse`, `streamingFollowing`), the user's sent message appears near the top of the viewport with the AI response streaming in a reading area below
- [ ] **LAYOUT-03**: When `onResponseComplete()` is called and user is at the bottom, layout transitions from active-turn to rest mode — filler is zeroed and last content settles above inputbar
- [ ] **LAYOUT-04**: Dynamic spacing is content-bounded — user cannot scroll past actual content into empty filler area

### Smart Down-Button

- [ ] **DBUTTON-01**: Down-button visibility signal is exposed when user is not at live bottom and new streaming or appended content exists below current viewport
- [ ] **DBUTTON-02**: Down-button action jumps to the active turn composition (user message visible near top + AI response start/current position visible), not to absolute scroll bottom

### Inputbar Awareness

- [ ] **INPUT-01**: All anchor offset calculations account for inputbar height, safe area bottom inset, keyboard height, and composer expansion so the active-turn anchor position is always visually correct

## Future Requirements

### Animation

- **ANIM-01**: Configurable animation curves for anchor snap (instead of instant jump)
- **ANIM-02**: Smooth transition animation from active-turn to rest mode on response completion

### Platform

- **PLAT-01**: Desktop and web scroll support with appropriate physics

### Advanced

- **ADV-01**: Pagination / infinite scroll for loading older message history
- **ADV-02**: Accessibility: SemanticsService.announce for new messages and state changes

## Out of Scope

| Feature | Reason |
|---------|--------|
| Chat UI components (bubbles, input, avatars) | Scroll logic only — devs bring their own UI |
| Streaming / AI integration | Consuming app handles streaming and signals controller |
| Message state management | Devs manage their own message list |
| Built-in down-button widget | Expose signal only — devs build their own FAB (same as v1.0) |
| Animated transitions (v2.0) | Instant jump first; animation is a v2.1 candidate |
| Desktop/web scroll behavior | Mobile-first; defer to future milestone |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| STATE-01 | — | Pending |
| STATE-02 | — | Pending |
| STATE-03 | — | Pending |
| FOLLOW-01 | — | Pending |
| FOLLOW-02 | — | Pending |
| FOLLOW-03 | — | Pending |
| LAYOUT-01 | — | Pending |
| LAYOUT-02 | — | Pending |
| LAYOUT-03 | — | Pending |
| LAYOUT-04 | — | Pending |
| DBUTTON-01 | — | Pending |
| DBUTTON-02 | — | Pending |
| INPUT-01 | — | Pending |

**Coverage:**
- v2.0 requirements: 13 total
- Mapped to phases: 0
- Unmapped: 13 ⚠️

---
*Requirements defined: 2026-03-17*
*Last updated: 2026-03-17 after initial definition*
