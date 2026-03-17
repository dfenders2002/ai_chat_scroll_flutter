# Feature Research

**Domain:** Flutter scroll/viewport management package for AI chat — v2.0 milestone (dual-layout, auto-follow, 5-state machine)
**Researched:** 2026-03-17
**Confidence:** MEDIUM-HIGH (ecosystem surveyed via react-native-streaming-message-list, assistant-ui, stream_chat_flutter, flutter_chat_ui, TanStack Virtual discussion, and direct behavioral analysis of ChatGPT/Claude scroll UX)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features any developer picking up this package expects from a v2.0 AI-chat-optimized scroll package. Missing these makes the package feel incomplete or broken compared to what major AI chat apps deliver.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Auto-follow during streaming (when user is at bottom) | ChatGPT, Claude, Gemini all auto-follow streaming responses when the user has not scrolled away. Not following = user misses content being generated without realizing it. | MEDIUM | Only engage when user is in `idle_at_bottom` or `submitted_waiting_response` state. Must NOT engage when user has intentionally scrolled away. |
| Scroll-detach when user manually scrolls up during streaming | All major AI apps immediately stop auto-following if the user drags up. Failure to stop = the worst scroll UX bug in any chat app; user fights the scroll to read older content. | MEDIUM | Detected via `UserScrollNotification` in Flutter. Once detached, must remain detached until explicit re-attach trigger (user scrolls back to bottom OR taps scroll-to-bottom button). |
| Re-attach / resume auto-follow when user returns to bottom | After a user manually detaches and then scrolls back to the bottom, auto-follow resumes. ChatGPT confirms: "As long as you don't tap the bottom, autoscroll stays paused." Conversely, returning to bottom reactivates it. | MEDIUM | Re-attach threshold should be configurable but default to a small pixel offset (e.g., ≤20px from bottom). Must distinguish programmatic scroll (button tap) from user drag. |
| Scroll-to-bottom FAB / button visible when detached | Every major chat app (Claude, ChatGPT, stream_chat_flutter, flutter_chat_ui v2, iMessage, Telegram) shows a visible affordance when the user is not at the bottom. This is now expected table stakes, not a differentiator. | MEDIUM | Must expose `isAtBottom` / `isDetached` on the controller so the consuming app can show/hide a FAB. Optionally expose `unreadTokenCount` or simpler boolean. |
| Re-anchor from any scroll position on new send | If the user is browsing history and sends a new message, the viewport must snap to the active turn (top-anchor mode). Leaving the user looking at old history after sending = broken UX. | MEDIUM | This was a differentiator in v1.0 — it becomes table stakes in v2.0 because v1.0 ships it. |
| No scroll jank during streaming height changes | The AI response grows on every streamed token. Each height change must not cause the scroll view to visually jump or stutter. | MEDIUM | Critical for `streaming_following` state. The filler space mechanism must absorb growth without scroll position changes. |
| Keyboard-aware offset calculation in all states | Opening/closing the soft keyboard changes the visible viewport area. Anchor positions and filler heights must recalculate on every keyboard inset change. | MEDIUM | Already done in v1.0 for the top-anchor case. Must extend to the `rest` layout and `streaming_following` state. |

### Differentiators (Competitive Advantage)

Features that no current Flutter package provides. The v2.0 value proposition vs. v1.0 and all competitors lives here.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Two layout modes: rest vs. active-turn | Rest = conversation history, newest message at bottom, bottom-aligned (standard chat). Active-turn = user message anchored near top, AI response grows below. Transitioning between them on send/complete is the v2.0 core behavior. No Flutter package models this as two distinct visual modes. | HIGH | Rest mode: `ListView(reverse: true)` physics. Active-turn mode: top-anchor + filler. Transition on `onUserMessageSent()` and back on `onResponseComplete()`. |
| 5-state scroll machine with clean transitions | Formalizes the scroll lifecycle into: `idle_at_bottom` → `submitted_waiting_response` → `streaming_following` ↔ `streaming_detached` → `history_browsing`. Each state has clearly defined entry conditions, behavior, and exit triggers. No library (Flutter or React Native) exposes this model cleanly. | HIGH | State machine eliminates the class of bugs where scroll behavior depends on ad-hoc boolean flags. Each state is a named, testable entity. |
| Smart down-button: jumps to active turn composition, not absolute bottom | During `streaming_detached`, the down-button should scroll to the user message + AI response start — the "active turn" — not to the growing bottom of the AI response. This mirrors Claude's mobile behavior and keeps the user oriented. | MEDIUM | Requires storing the scroll offset of the active-turn anchor when the turn starts. Button target = that stored offset, not `maxScrollExtent`. |
| Content-bounded dynamic spacing | Filler space is computed from actual content heights so the viewport is never scrollable into empty space. In v1.0 the filler could leave empty scroll area below the AI response. In v2.0, filler = `max(0, viewport_height - content_above_filler)`, clamped so the list never overscrolls past content. | HIGH | Requires measuring total content height via `RenderBox` or `SliverConstraints`. Must recompute on every streaming token. |
| Response completion transition: active-turn → rest layout | When `onResponseComplete()` fires, the scroll system transitions back to rest mode (bottom-aligned). This needs to happen without a jarring jump: the final AI message should appear to settle at the bottom of the history. | HIGH | Transition involves removing the filler, allowing the list to reflow to rest position. May require a brief animation or deferred reflow. |
| `history_browsing` state: complete hands-off mode | When user has scrolled into history (past the active turn) and no streaming is happening, the package completely yields scroll control. No auto-jumps, no managed behavior. Package becomes a no-op until next `onUserMessageSent()`. | MEDIUM | Distinct from `streaming_detached` (which still has an active turn). This is full "user owns the scroll" mode. |
| Exposed scroll state as controller property | `controller.scrollState` returns the current `AiChatScrollState` enum value. Consuming apps can react to state changes: show/hide FAB, update send button style, trigger animations. No current Flutter package exposes this. | LOW | Requires a `ValueNotifier<AiChatScrollState>` on the controller so widgets can listen without polling. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Animated transitions between layout modes | "The snap from active-turn to rest feels abrupt" | Animation during reflow is extremely complex: the list must change anchor points while maintaining scroll continuity, and content height changes mid-animation cause visual artifacts. React Native's equivalent library deliberately skips this. | Ship instant transitions in v2.0. Mark as v2.1 candidate only after layout mode transitions are stable and real users report the abruptness as a pain point. |
| Auto-follow that chases the absolute bottom of the streaming response | "Just keep scrolling down as it generates, like a terminal" | This is the anti-pattern the entire package exists to solve. Users lose context of their own question. The anchor model (user message near top) is demonstrably better for comprehension. | The `streaming_following` state keeps the viewport at the active-turn composition. Users see their question + the beginning of the answer — not the end of a long response. |
| Unread message count badge on the down-button | "Show how many tokens/lines I've missed" | Token counts are not message counts. Streaming means the count changes every 50ms, causing badge flicker. Meaningful unread counts require message boundary awareness the package deliberately does not have. | Expose a boolean `isDetachedDuringStreaming` — consuming app decides its own badge UI. Do not attempt live counts. |
| Configurable scroll physics (friction, deceleration) | "Let me tune the feel" | Every exposed parameter multiplies the testing matrix by the number of valid values × 2 platforms. Premature surface area before any user requests specific values. | Ship zero physics configuration in v2.0. Open a GitHub issue template for physics requests with required justification. |
| Built-in support for "stop generation" button behavior | "When user taps stop, scroll should respond" | The package does not know about the AI generation lifecycle beyond the signals it receives. Trying to infer a "stop" from scroll behavior creates tight coupling to AI provider internals. | `onResponseComplete()` is the correct signal for stop — consuming app calls it when generation stops for any reason. Package responds identically whether stop was normal completion or user-initiated. |
| Sticky "today / yesterday" date separators that float above messages | Requested because major chat apps have these | Requires the package to understand message semantics (which items are date headers, which are messages). Out of scope — scroll logic only. | Document pattern: consuming app renders date headers as regular list items; `scrollview_observer` can track their position if needed. |
| Dual-axis scroll (horizontal message swipe + vertical chat scroll) | "Swipe to reply like iMessage" | Introduces gesture recognizer competition between the horizontal swipe and vertical chat scroll. Complex to arbitrate correctly, and the package has no knowledge of individual message items. | Out of scope. Gesture arbitration belongs in the message widget layer, not the scroll container. |

---

## Feature Dependencies

```
[rest layout mode]
    └──required by──> [response completion transition: active-turn → rest]
    └──required by──> [idle_at_bottom state]
    └──required by──> [history_browsing state]

[active-turn layout mode]
    └──required by──> [streaming_following state]
    └──required by──> [streaming_detached state]
    └──requires──> [top-anchor-on-send] (v1.0 feature, must remain)
    └──requires──> [dynamic filler space] (v1.0 feature, must remain)
    └──requires──> [content-bounded filler recomputation] (v2.0 improvement)

[5-state machine]
    └──requires──> [rest layout mode]
    └──requires──> [active-turn layout mode]
    └──requires──> [auto-follow during streaming]
    └──requires──> [scroll-detach on user drag]
    └──requires──> [re-attach on return to bottom]
    └──enables──> [exposed scroll state on controller]

[auto-follow during streaming]
    └──requires──> [streaming_following state] (from 5-state machine)
    └──conflicts──> [streaming_detached state]

[scroll-detach on user drag]
    └──transitions to──> [streaming_detached state]
    └──required by──> [scroll-to-bottom FAB visibility]

[re-attach on return to bottom]
    └──transitions to──> [streaming_following state]
    └──required by──> [scroll-to-bottom FAB tap behavior]

[smart down-button: jump to active-turn]
    └──requires──> [active-turn anchor offset stored at turn start]
    └──requires──> [streaming_detached state] (only relevant when detached)
    └──conflicts──> [naive scroll-to-bottom (maxScrollExtent)]

[content-bounded dynamic spacing]
    └──requires──> [dynamic filler space] (v1.0 base)
    └──requires──> [content height measurement]
    └──enhances──> [response completion transition]

[response completion transition: active-turn → rest]
    └──requires──> [content-bounded dynamic spacing]
    └──requires──> [rest layout mode]
    └──triggered by──> [onResponseComplete()]

[exposed scroll state on controller]
    └──requires──> [5-state machine]
    └──enables──> [scroll-to-bottom FAB visibility] (consuming app reads state)
```

### Dependency Notes

- **5-state machine requires both layout modes:** The machine transitions between rest (idle_at_bottom, history_browsing) and active-turn (submitted_waiting_response, streaming_following, streaming_detached) modes. Neither mode can be removed without collapsing the machine.
- **Auto-follow conflicts with streaming_detached:** These are mutually exclusive behaviors — the state machine enforces the conflict structurally. No boolean flag needed.
- **Smart down-button requires stored anchor offset:** On `onUserMessageSent()`, the package must record the scroll position of the active-turn anchor. Without this, the button can only target `maxScrollExtent` which moves as streaming grows.
- **Content-bounded spacing is a prerequisite for a clean completion transition:** Without clamping the filler, removing it at completion causes a scroll offset change that looks like a jump.
- **Scroll state on controller is low-cost but high-value:** A `ValueNotifier<AiChatScrollState>` enables consuming apps to drive their own UI (FABs, input bar state) without polling or custom callbacks.

---

## MVP Definition

### Launch With (v2.0)

The minimum for a coherent v2.0 release that justifies the version bump and delivers the milestone goal.

- [ ] Two layout modes (rest and active-turn) — the foundational redesign; everything else builds on this
- [ ] 5-state machine: `idle_at_bottom`, `submitted_waiting_response`, `streaming_following`, `streaming_detached`, `history_browsing` — formalizes behavior and eliminates flag-based bugs
- [ ] Auto-follow during streaming in `streaming_following` state — the core new behavior; without this the package is still v1.0
- [ ] Scroll-detach to `streaming_detached` on user drag during streaming — required; auto-follow without detach = the worst scroll bug
- [ ] Re-attach to `streaming_following` when user returns to bottom — required for detach to be usable
- [ ] Smart down-button target: scroll to active-turn composition, not absolute bottom — the differentiating detail that justifies "smart"
- [ ] Content-bounded dynamic spacing — eliminates the v1.0 overscroll-into-empty-space bug
- [ ] Response completion transition: active-turn → rest layout — closes the loop; without this the layout stays stuck in active-turn forever
- [ ] Exposed `scrollState` (`ValueNotifier`) on controller — enables consuming apps to drive FAB and other UI
- [ ] `isAtBottom` and `scrollToBottom()` on controller (already v1.0) — must continue working correctly in the new state machine

### Add After Validation (v2.x)

Features to add after v2.0 ships and real-world usage reveals actual gaps.

- [ ] Unread-content indicator (boolean only, no count) on controller — add if issues report users can't tell they missed content while detached
- [ ] Animated layout mode transitions — add only if v2.0 instant transitions generate complaints; animation correctness is hard
- [ ] RTL / bidirectional text layout support — add if international user issues filed
- [ ] Accessibility: `SemanticsService.announce` for new messages while detached — low effort add; high value for screen reader users

### Future Consideration (v3+)

Features to defer until the v2.0 architecture is proven stable.

- [ ] Pagination / infinite scroll for older message history — distinct technical problem from streaming anchor; out of scope until explicitly requested
- [ ] Desktop / web scroll support — mobile-first is correct; desktop requires separate physics strategy
- [ ] Per-turn scroll state callbacks for analytics / testing — useful but low adoption priority

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Two layout modes (rest + active-turn) | HIGH | HIGH | P1 |
| 5-state machine | HIGH | HIGH | P1 |
| Auto-follow during streaming | HIGH | MEDIUM | P1 |
| Scroll-detach on user drag | HIGH | MEDIUM | P1 |
| Re-attach on return to bottom | HIGH | MEDIUM | P1 |
| Content-bounded dynamic spacing | HIGH | HIGH | P1 |
| Response completion transition | HIGH | HIGH | P1 |
| Smart down-button (active-turn target) | MEDIUM | MEDIUM | P1 |
| Exposed `scrollState` ValueNotifier | HIGH | LOW | P1 |
| `isAtBottom` + `scrollToBottom()` (existing) | HIGH | LOW | P1 |
| Unread-content boolean indicator | MEDIUM | LOW | P2 |
| Animated layout transitions | MEDIUM | HIGH | P3 |
| RTL support | MEDIUM | LOW | P2 |
| Accessibility announcements | MEDIUM | LOW | P2 |
| Pagination / infinite scroll | LOW | HIGH | P3 |
| Desktop / web support | LOW | HIGH | P3 |

**Priority key:**
- P1: Required for v2.0 release — directly serves the milestone goal
- P2: Should add in v2.x — improves quality once core is stable
- P3: Defer to v3+ or until explicitly requested

---

## Competitor Feature Analysis

How major AI chat apps and libraries handle the v2.0 features.

| Feature | ChatGPT (web/iOS) | Claude (iOS) | react-native-streaming-message-list | stream_chat_flutter | Our v2.0 Approach |
|---------|-------------------|--------------|--------------------------------------|---------------------|--------------------|
| Auto-follow during streaming | Yes — follows by default when at bottom | Yes — follows when at bottom | Yes (isStreaming=true) | N/A (not AI streaming) | Yes — `streaming_following` state |
| Scroll-detach on user drag | Yes — pauses autoscroll on any upward drag | Yes | Yes — tracked via `isAtEnd` + threshold | Partial — dialog-aware only | Yes — `UserScrollNotification` triggers transition to `streaming_detached` |
| Re-attach on return to bottom | Yes — confirmed by multiple sources; returning to bottom resumes follow | Yes | Yes | N/A | Yes — pixel threshold triggers transition back to `streaming_following` |
| Scroll-to-bottom FAB when detached | No native FAB — users report this as a gap (third-party extensions add it) | Yes — visible down-arrow button | Yes (via `isAtEnd` + `contentFillsViewport` hook) | Yes — `ScrollToBottomButton` component with unread count | Yes — expose `scrollState` so consuming app renders FAB |
| Two distinct layout modes | No — single layout, bottom-grows | Yes — top-anchor active turn + rest history | Partial — streaming vs not-streaming | No | Yes — formal rest / active-turn mode distinction |
| Smart down-button (jump to active turn, not absolute bottom) | No — jumps to absolute bottom | Yes — jumps to the active turn composition | No — targets end of list | No | Yes — stores active-turn anchor offset on turn start |
| Formal state machine | No — implicit via boolean flags | Unknown (internal) | Implicit (isStreaming flag) | No | Yes — explicit 5-state enum |
| Content-bounded spacing | N/A (web) | Yes — no empty scroll area | Partial — placeholder managed but can overscroll | N/A | Yes — clamped filler height |
| Completion transition: active → rest | N/A | Yes — smooth settle to rest | Partial (isStreaming=false returns to standard list) | N/A | Yes — filler removal + layout reflow |
| Flutter native | No | No | No (React Native) | Yes | Yes |

**Key gap confirmed:** No Flutter-native package models dual layout modes + a formal scroll state machine + auto-follow with clean detach/re-attach semantics. The closest conceptual match is `react-native-streaming-message-list` (React Native), which solves the anchor problem but lacks the state machine formalism and dual-layout model. Claude's own iOS app appears to implement exactly the behavior described in v2.0, but no Flutter package currently provides it.

---

## Sources

- [react-native-streaming-message-list on GitHub](https://github.com/bacarybruno/react-native-streaming-message-list) — HIGH confidence for feature design and behavioral patterns; the closest cross-platform analog to this package
- [Building reliable AI chat on mobile — Doctolib, Medium, Feb 2026](https://medium.com/doctolib/building-reliable-ai-chat-on-mobile-01015d74422e) — MEDIUM confidence (403 on direct fetch, but search summary confirmed library primitives and patterns)
- [How to stop chat autoscroll when AI message streams — TanStack/virtual Discussion #730](https://github.com/TanStack/virtual/discussions/730) — HIGH confidence; direct discussion of the detach/re-attach problem with real implementation approaches
- [How to Stop ChatGPT Autoscroll — PromptLayer Blog](https://blog.promptlayer.com/how-to-stop-chatgpt-autoscroll/) — MEDIUM confidence; confirms ChatGPT's detach-on-upward-scroll and re-attach-on-return-to-bottom behavior
- [ScrollToBottomButton — Stream Chat React Native Docs](https://getstream.io/chat/docs/sdk/react-native/ui-components/scroll-to-bottom-button/) — HIGH confidence; confirms scroll-to-bottom button as table stakes with unread count pattern
- [Customizing MessageListView scroll behavior — Stream Chat Android Docs](https://getstream.io/chat/docs/sdk/android/ui/guides/customizing-message-list-scroll-behavior/) — MEDIUM confidence; documents dialog-aware scroll lock pattern
- [Handling scroll behavior for AI Chat Apps — jhakim.com](https://jhakim.com/blog/handling-scroll-behavior-for-ai-chat-apps) — MEDIUM confidence; confirms isAtBottom detection + debounced auto-follow pattern
- [Scroll to bottom widget discussion — flyerhq/flutter_chat_ui Discussion #163](https://github.com/flyerhq/flutter_chat_ui/discussions/163) — MEDIUM confidence; confirms scroll-to-bottom FAB was a feature request, now shipped in v2
- [Intuitive Scrolling for Chatbot Message Streaming — Hashnode](https://tuffstuff9.hashnode.dev/intuitive-scrolling-for-chatbot-message-streaming) — LOW confidence (403 on fetch, search summary only)
- [assistant-ui — TypeScript/React library for AI chat](https://www.assistant-ui.com/) — MEDIUM confidence; confirmed auto-scroll + streaming + viewport management features exist but docs don't expose internals
- [AI SDK UI Chatbot — Vercel AI SDK Docs](https://ai-sdk.dev/docs/ai-sdk-ui/chatbot) — MEDIUM confidence; no scroll behavior docs found but confirms streaming-first design philosophy

---

*Feature research for: Flutter AI chat scroll/viewport management package (ai_chat_scroll) — v2.0 dual-layout milestone*
*Researched: 2026-03-17*
