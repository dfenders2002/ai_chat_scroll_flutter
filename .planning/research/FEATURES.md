# Feature Research

**Domain:** Flutter scroll/viewport management package for AI chat
**Researched:** 2026-03-15
**Confidence:** MEDIUM-HIGH (ecosystem well-surveyed; Claude/ChatGPT internal implementation inferred from behavior observation and analogous React Native library)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that any developer picking up a chat scroll package expects to work. Missing these means the package is not usable as a drop-in solution.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Reverse-list ordering (newest at bottom, older above) | Universal convention in chat apps — WhatsApp, iMessage, Telegram, every AI chat app | LOW | Flutter `ListView(reverse: true)` partially handles this but has known physics bugs; package must paper over them |
| Scroll-to-bottom on new message (when already at bottom) | Standard chat behavior: if user is reading the current bottom, new message should stay in view | LOW | Requires detecting "is user at bottom?" threshold + programmatic jump/animate |
| Preserve scroll position when user has scrolled up | Standard pattern: do not hijack user scroll when they are reading history | MEDIUM | Needs scroll position tracking + threshold logic (see `lorien_chat_list` `bottomEdgeThreshold`) |
| "Scroll to bottom" FAB / indicator when behind in history | All major chat apps show a badge/button when messages arrive below view | MEDIUM | Must detect unread messages below current position; `stream_chat_flutter` and `flutter_chat_ui` both implement this |
| Keyboard-aware scroll compensation | When soft keyboard opens, scroll must adjust so latest content stays visible | MEDIUM | Flutter `MediaQuery.viewInsets` provides inset data; must integrate with scroll physics |
| No scroll jank during message insertion | Abrupt jumps when items are added are immediately visible and frustrating | MEDIUM | `scrollview_observer` addresses specifically: "prevents visual jitter during dynamic updates" |
| Simple, obvious API surface | Devs expect a controller + widget pattern, not a full framework | LOW | PROJECT.md already mandates `AiChatScrollController` + `AiChatScrollView` — this aligns with ecosystem expectations |
| Working on iOS and Android | These are the primary targets for Flutter chat apps | LOW | Must validate against both platform scroll physics (Cupertino bouncing vs. Android clamping) |

### Differentiators (Competitive Advantage)

Features no current Flutter package provides cleanly. The core value proposition of this package lives here.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Top-anchor-on-send: user message snaps to top of viewport when sent | The defining behavior of Claude mobile. No Flutter package does this. `scrollview_observer` partially covers streaming preservation but not the snap-to-top-on-send trigger. | HIGH | Requires calculating target scroll offset such that the sent message sits flush at the top of the viewport, then jumping there atomically before AI response begins |
| Dynamic filler space below streaming response | Keeps the anchor in place during streaming without scroll chasing. React Native equivalent (`react-native-streaming-message-list`) injects a dynamic blank spacer at the bottom. Flutter requires a `SliverFillRemaining` or equivalent to do this. | HIGH | Filler height = max(0, viewport_height - (user_message_height + ai_response_height_so_far)). Must recompute on every streaming token. |
| No auto-scroll during AI streaming | User stays pinned at the user message; AI grows below. Current packages (e.g., `lorien_chat_list`) auto-scroll to the bottom on new content — the opposite of desired behavior. | MEDIUM | Streaming must be modeled as a content height change, not a new message insertion, to suppress auto-scroll logic |
| Manual scroll resume to see long responses | If AI response exceeds viewport, user manually scrolls down without any interference from the package | LOW | Package must stop all scroll-management behavior the moment user drags; detect via `ScrollNotification` / `UserScrollNotification` |
| New-message-while-scrolling-history: jump back to anchor | If user was reading old messages and sends a new one, the viewport resets to the top-anchor pattern | MEDIUM | Requires detecting send event while `scrollOffset > nearBottomThreshold` and executing the top-anchor positioning sequence |
| Streamed response height tracking | Controller knows AI response height in real time, enabling filler space calculation and correct anchor positioning | MEDIUM | Requires a `GlobalKey` or `RenderBox` measurement callback on the AI message widget |
| Controller lifecycle hooks: `onUserMessageSent()`, `onResponseComplete()` | Clean API for consuming apps to signal transitions; far better DX than requiring devs to manipulate scroll offsets directly | LOW | These are the seams between the consuming app's streaming logic and the scroll package |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Built-in message bubble UI | "Make it a full drop-in chat widget" — reduces integration code | Violates the single-responsibility principle; forces opinionated visual design on consumers; competitors (flutter_chat_ui, dash_chat_2) already own this space. This package's value is scroll logic, not UI. | Keep scope to scroll behavior; provide a clear example app showing how to combine with any message bubble widget |
| Built-in streaming/AI integration | "Handle the API calls too" | Couples a pure UI concern (scroll) to networking and AI provider choice; would require depending on http/dio/openai SDK and tracking every API change | Expose controller hooks (`onUserMessageSent`, `onResponseComplete`) so consuming apps push events in; they own the streaming |
| Infinite scroll / pagination of older messages | "Load more history at top" | Technically distinct problem from bottom-anchor streaming; adds significant complexity (prepend vs. append scroll math, loading indicators, cache management); `scrollview_observer` and Stream's lazy-load pattern cover this separately | Explicit v1 exclusion; document that consumers can layer pagination on top via standard `ScrollController` callbacks |
| Desktop/web scroll support | "Support all platforms" | Scroll physics differ fundamentally: no momentum, mouse-wheel events, trackpad precision. The top-anchor pattern is a mobile UX pattern. Attempting desktop support without a real desktop design leads to poor UX on all platforms. | Explicitly document mobile-only in v1; revisit for v2 with platform-specific physics |
| Auto-scroll-to-bottom during AI streaming | "Follow the response as it generates" | This is the anti-pattern this package exists to solve. Auto-following causes disorientation when the response is longer than the viewport. | The top-anchor model: user message stays visible, response grows below, user manually scrolls to read more |
| Full message state management | "Also manage the message list" | Devs already have message state in their existing architecture (Provider, Riverpod, Bloc, etc.); forcing a new state layer causes integration friction | Receive only scroll-relevant signals (`onUserMessageSent`, `onResponseComplete`); let the consuming app own message data |
| Configurable scroll physics | "Let users tune physics values" | Surface area explosion; each exposed parameter requires documentation, testing, and migration consideration. Premature optimization before real-world usage data. | Expose zero physics config in v1; add only if pub.dev issues request specific values |

---

## Feature Dependencies

```
[Reverse-list ordering]
    └──required by──> [Scroll-to-bottom on new message]
    └──required by──> [Top-anchor-on-send]
    └──required by──> [Preserve scroll position on history scroll]

[Top-anchor-on-send]
    └──requires──> [Streamed response height tracking]
    └──requires──> [Dynamic filler space management]
                       └──requires──> [Streamed response height tracking]

[Preserve scroll position on history scroll]
    └──required by──> [New-message-while-scrolling-history reset]

[Manual scroll resume]
    └──enhances──> [No auto-scroll during streaming]

[Keyboard-aware scroll compensation]
    └──enhances──> [Scroll-to-bottom on new message]
    └──enhances──> [Top-anchor-on-send]

[Controller lifecycle hooks]
    └──triggers──> [Top-anchor-on-send]
    └──triggers──> [Dynamic filler space management]
    └──triggers──> [New-message-while-scrolling-history reset]

[Scroll-to-bottom FAB]
    └──requires──> [Preserve scroll position on history scroll]  (needs "am I behind?" state)

[Top-anchor-on-send] ──conflicts──> [Auto-scroll-to-bottom during streaming]
[No auto-scroll during streaming] ──conflicts──> [Auto-scroll-to-bottom during streaming]
```

### Dependency Notes

- **Top-anchor-on-send requires streamed response height tracking:** The filler spacer height is `viewport_height - anchor_message_height - response_height_so_far`. Without measuring the response height in real time, the spacer cannot be computed and the anchor will drift.
- **Dynamic filler space requires streamed response height tracking:** The two features are inseparable — filler is the mechanism that keeps the anchor stable as content grows.
- **Controller lifecycle hooks trigger the anchor sequence:** `onUserMessageSent()` is the entry point for the entire top-anchor sequence. Without a clean hook, consuming apps must manipulate scroll offsets themselves, which is error-prone.
- **Keyboard-aware compensation enhances anchor positioning:** When the keyboard opens after the user taps a text field to send, the viewport shrinks. The anchor target position must be recalculated against the reduced viewport height.
- **Top-anchor-on-send conflicts with auto-scroll-to-bottom during streaming:** These are mutually exclusive scroll strategies. The package must implement only one; auto-scroll-to-bottom is the anti-feature.
- **Preserve scroll position on history scroll is a prerequisite for new-message reset:** You cannot detect "user was in history" without the preservation logic already tracking scroll offset vs. bottom threshold.

---

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed to validate the core behavior and be useful to Flutter developers building AI chat.

- [ ] Reverse-list ordering support — foundational; without it the package cannot be used in a conventional chat layout
- [ ] `AiChatScrollController` with `onUserMessageSent()` and `onResponseComplete()` — the primary API surface that consuming apps integrate against
- [ ] `AiChatScrollView` wrapper widget — the lightweight integration point over any `ListView` / `CustomScrollView`
- [ ] Top-anchor-on-send: viewport snaps so user message is at the top — the core differentiating behavior
- [ ] Dynamic filler space management during streaming — required to keep the anchor stable while the AI response grows
- [ ] No auto-scroll during streaming — preserves the anchor; the package must not undo the snap with scroll-to-bottom logic
- [ ] Manual scroll resume: user drag cancels any managed scroll, no re-hijacking until next `onUserMessageSent()` — critical for usability when AI response exceeds viewport
- [ ] New-message-while-in-history: reset to top-anchor pattern — ensures the behavior is consistent even if user scrolled up before sending
- [ ] No scroll jank on message insertion — baseline quality bar; without this the package is unusable in practice
- [ ] pub.dev-ready package structure with example app — required for distribution; this is a package, not an internal library

### Add After Validation (v1.x)

Features to add once the core is working and adopted.

- [ ] "Scroll to bottom" FAB/indicator — add if pub.dev issues or community feedback indicates users want this; simple to add but not needed for the anchor UX
- [ ] Keyboard-aware scroll compensation — add if reported as issue; Flutter's default `Scaffold` `resizeToAvoidBottomInset` may already handle enough for most apps
- [ ] Animation curves for anchor snap — add if the default `jumpTo` feels abrupt on device; `animateTo` with a short curve is an easy enhancement
- [ ] RTL / bidirectional layout support — add if international users or apps request it; directional flag in `AiChatScrollView`

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] Pagination / infinite scroll for older message history — distinct technical problem; significant added complexity; not needed for the streaming anchor use case
- [ ] Desktop and web scroll support — mobile-first is correct for v1; desktop requires separate physics strategy
- [ ] Accessibility: `SemanticsService.announce` for new messages — valuable but not blocking for initial launch; can be added without API changes
- [ ] Observability: scroll state callbacks for analytics / testing — useful for integration testing and analytics, low priority for initial adoption

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Reverse-list ordering | HIGH | LOW | P1 |
| Top-anchor-on-send | HIGH | HIGH | P1 |
| Dynamic filler space during streaming | HIGH | HIGH | P1 |
| No auto-scroll during streaming | HIGH | MEDIUM | P1 |
| `AiChatScrollController` lifecycle hooks | HIGH | LOW | P1 |
| `AiChatScrollView` wrapper widget | HIGH | LOW | P1 |
| Manual scroll resume (user drag) | HIGH | MEDIUM | P1 |
| New-message-while-in-history reset | HIGH | MEDIUM | P1 |
| No scroll jank on insertion | HIGH | MEDIUM | P1 |
| pub.dev package structure + example | HIGH | LOW | P1 |
| Scroll-to-bottom FAB | MEDIUM | MEDIUM | P2 |
| Keyboard-aware scroll compensation | MEDIUM | MEDIUM | P2 |
| Anchor snap animation curve | LOW | LOW | P2 |
| RTL support | MEDIUM | LOW | P2 |
| Pagination / infinite scroll | MEDIUM | HIGH | P3 |
| Desktop/web support | LOW | HIGH | P3 |
| Accessibility announcements | MEDIUM | LOW | P3 |
| Observability/analytics callbacks | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for launch — defines the package's value proposition
- P2: Should have, add when possible — improves quality but not blocking
- P3: Nice to have, future consideration

---

## Competitor Feature Analysis

| Feature | scrollview_observer | lorien_chat_list | react-native-streaming-message-list | flutter_chat_ui | Our Approach |
|---------|---------------------|------------------|--------------------------------------|-----------------|--------------|
| Reverse-list ordering | Yes (wraps existing) | Yes | Yes | Yes | Yes (required foundation) |
| Auto-scroll on new message | Yes | Yes (configurable threshold) | Yes | Yes | Only when user is already at bottom; NOT during streaming |
| Preserve position in history | Yes | Yes | Yes | Yes | Yes |
| Top-anchor-on-send (snap) | No | No | Yes (AnchorItem wrapper) | No | Yes — the core differentiator |
| Dynamic filler/spacer for streaming | No | No | Yes (dynamic placeholder) | No | Yes — required for anchor stability |
| No auto-scroll during streaming | Generative mode exists but is complex to configure | No | Yes | No | Yes — default behavior, not opt-in |
| Streaming height tracking | Partial (observer) | No | Yes (StreamingItem) | No | Yes |
| Controller lifecycle hooks | No (observer callbacks) | No (widget-level) | Hook-based | No | Yes — `onUserMessageSent()`, `onResponseComplete()` |
| Scroll-to-bottom indicator | No | No | Yes (via hook) | Yes | P2 — post-launch |
| Pagination (older messages) | No | Yes (`onLoadMoreCallback`) | No | Yes | Explicit non-goal for v1 |
| Chat UI components | No | No | No | Yes (full UI) | Deliberate non-goal |
| Flutter native | Yes | Yes | No (React Native) | Yes | Yes |
| pub.dev | Yes | Yes | No (npm) | Yes | Yes |

**Gap identified:** No Flutter-native package implements the top-anchor-on-send + dynamic filler pattern. `scrollview_observer` is the closest in the streaming preservation space but does not expose a clean "snap user message to top on send" API and requires complex configuration for generative mode. The React Native `react-native-streaming-message-list` is the only library that solves the exact same problem, but for a different platform.

---

## Sources

- [scrollview_observer on pub.dev](https://pub.dev/packages/scrollview_observer) — MEDIUM confidence, official package page
- [scrollview_observer Chat Observer wiki](https://github.com/fluttercandies/flutter_scrollview_observer/wiki/3%E3%80%81Chat-Observer) — MEDIUM confidence, official wiki
- [lorien_chat_list on pub.dev](https://pub.dev/packages/lorien_chat_list) — MEDIUM confidence, official package page
- [anchor_scroll_controller on pub.dev via Flutter Gems](https://fluttergems.dev/packages/anchor_scroll_controller/) — LOW confidence, aggregator
- [react-native-streaming-message-list on GitHub](https://github.com/bacarybruno/react-native-streaming-message-list) — HIGH confidence for feature design; LOW confidence for direct Flutter applicability (different runtime)
- [flutter_chat_ui on pub.dev](https://pub.dev/packages/flutter_chat_ui) — MEDIUM confidence, official package page
- [stream_chat_flutter unread indicator](https://github.com/GetStream/stream-chat-flutter/issues/2184) — MEDIUM confidence, issue thread
- [Conversational AI UI comparison 2025 — IntuitionLabs](https://intuitionlabs.ai/articles/conversational-ai-ui-comparison-2025) — LOW confidence, third-party analysis
- [Flutter ListView reverse scroll behavior — GitHub Issue #17303](https://github.com/flutter/flutter/issues/17303) — HIGH confidence, official Flutter repo
- [Flutter scroll position preservation — GitHub Issue #96398](https://github.com/flutter/flutter/issues/96398) — HIGH confidence, official Flutter repo
- [SemanticsService.announce — Flutter accessibility docs](https://docs.flutter.dev/ui/accessibility) — HIGH confidence, official docs

---

*Feature research for: Flutter AI chat scroll/viewport management package (ai_chat_scroll)*
*Researched: 2026-03-15*
