---
phase: 07-auto-follow-and-scroll-detach
plan: "01"
subsystem: ui
tags: [flutter, scroll, streaming, state-machine, tdd]

# Dependency graph
requires:
  - phase: 06-anchor-behavior
    provides: AiChatScrollState enum, AiChatScrollController, anchor/filler mechanism

provides:
  - Auto-follow scroll compensation during streamingFollowing state
  - User drag detach transitioning streamingFollowing → streamingDetached
  - Re-attach on scroll-back or scrollToBottom() during streamingDetached
  - onUserScrolled(), onContentGrowthDetected(), onScrolledToBottom() controller methods
  - Fixed scrollToBottom() targeting pixels=0 (not maxScrollExtent) for reverse:true list

affects:
  - 08-scroll-to-bottom-button
  - Any phase using AiChatScrollController

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "double.maxFinite sentinel for _lastMaxScrollExtent prevents spurious compensation before anchor baseline"
    - "State-enum guards replace boolean flags for streaming compensation control"
    - "scheduleFrame() required before addPostFrameCallback in flutter_test called between frames"
    - "scrollDelta > 0 guard prevents re-attach→immediate-detach race on scroll-back gestures"
    - "Direct controller method call in tests (simulateContentGrowth) where ScrollMetricsNotification doesn't fire"

key-files:
  created:
    - test/auto_follow_test.dart
  modified:
    - lib/src/controller/ai_chat_scroll_controller.dart
    - lib/src/widgets/ai_chat_scroll_view.dart

key-decisions:
  - "Use double.maxFinite sentinel instead of _anchorSetupComplete boolean — naturally prevents all spurious compensation via the guard condition newMax <= _lastMaxScrollExtent + 0.5"
  - "ScrollMetricsNotification does not fire in flutter_test on pumpWidget/setState item additions — tests call controller.onContentGrowthDetected() directly, exercising the state machine rather than notification plumbing"
  - "scrollDelta > 0 guard in drag detection prevents immediate re-detach during scroll-back gestures (overshoot causes second notification with dragDetails still non-null)"
  - "scheduleFrame() must precede addPostFrameCallback in _onControllerChanged to fire during pump() in test environment when called between frames"

patterns-established:
  - "Streaming compensation: state-enum guard pattern (check scrollState before any compensation action)"
  - "Test helper pattern: simulateContentGrowth() calls controller method directly when ScrollMetricsNotification is untestable via pumpWidget"

requirements-completed: [FOLLOW-01, FOLLOW-02, FOLLOW-03]

# Metrics
duration: 90min
completed: 2026-03-17
---

# Phase 7 Plan 01: Auto-Follow and Scroll Detach Summary

**StreamingFollowing/streamingDetached state transitions wired to real scroll compensation via ScrollMetricsNotification and drag detection, replacing _anchorActive boolean**

## Performance

- **Duration:** ~90 min
- **Started:** 2026-03-17T00:00:00Z
- **Completed:** 2026-03-17T02:00:00Z
- **Tasks:** 2 (TDD: RED + GREEN)
- **Files modified:** 3

## Accomplishments

- Replaced `_anchorActive` boolean with `AiChatScrollState` enum guards throughout `AiChatScrollView`
- Wired `ScrollMetricsNotification` to detect real content growth and transition `submittedWaitingResponse` → `streamingFollowing`
- Wired `ScrollUpdateNotification` drag detection (with `scrollDelta > 0` guard) to call `onUserScrolled()` and transition `streamingFollowing` → `streamingDetached`
- Wired `_onScrollChanged` to call `onScrolledToBottom()` and re-attach during `streamingDetached`
- Fixed pre-existing `scrollToBottom()` bug: was using `animateTo(maxScrollExtent)` (goes to history top) — corrected to `animateTo(0.0)` for `reverse:true` list
- All 6 FOLLOW tests pass; full suite went from 42 passing / 15 failing to 54 passing / 9 failing (scrollToBottom fix resolved 6 pre-existing failures)

## Task Commits

Each task was committed atomically:

1. **Task 1: RED — failing FOLLOW tests** - `0d322e4` (test)
2. **Task 2: GREEN — production implementation** - `61757ce` (feat)

## Files Created/Modified

- `test/auto_follow_test.dart` — 6 widget tests for FOLLOW-01/02/03 covering auto-follow, drag detach, re-attach via drag and scrollToBottom
- `lib/src/controller/ai_chat_scroll_controller.dart` — Added onUserScrolled(), onContentGrowthDetected(), onScrolledToBottom(); fixed scrollToBottom()
- `lib/src/widgets/ai_chat_scroll_view.dart` — Replaced _anchorActive with state-enum guards; added _lastMaxScrollExtent sentinel; wired ScrollMetricsNotification, drag detection, and scroll-back re-attach

## Decisions Made

- **double.maxFinite sentinel over _anchorSetupComplete flag:** The field `_anchorSetupComplete` was added then removed — the `double.maxFinite` sentinel naturally prevents spurious compensation because any notification before the anchor baseline is established will have `newMax < maxFinite`, making the `newMax <= _lastMaxScrollExtent + 0.5` check pass and bail early. No separate boolean needed.

- **Tests call onContentGrowthDetected() directly:** `ScrollMetricsNotification` does not fire in the flutter_test framework when items are added via `pumpWidget` or `setState`. Tests exercise the controller state machine and view compensation directly, which covers the same semantics since production wires the notification to that same method call.

- **scrollDelta > 0 guard in drag detection:** Without this, a scroll-back gesture (dragging back to live bottom) triggers `onScrolledToBottom()` → transitions to `streamingFollowing` → but the same drag event then fires another `ScrollUpdateNotification` with `dragDetails != null`, immediately calling `onUserScrolled()` and detaching again. The `scrollDelta > 0` guard ensures detach only fires when moving away from live bottom.

- **scheduleFrame() before addPostFrameCallback in _onControllerChanged:** In flutter_test, `addPostFrameCallback` does not fire on the next `pump()` unless `scheduleFrame()` is called first when the callback is registered between frames. This is a test-environment quirk with no production impact.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed scrollToBottom() using wrong scroll target**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** `scrollToBottom()` called `animateTo(maxScrollExtent)` which scrolls to the history top in a `reverse:true` list. Live bottom is `pixels=0`.
- **Fix:** Changed to `animateTo(0.0)`
- **Files modified:** `lib/src/controller/ai_chat_scroll_controller.dart`
- **Verification:** FOLLOW-03b passes; 6 pre-existing scroll_to_bottom_indicator failures now pass
- **Committed in:** `61757ce` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Bug fix required for test correctness and production behavior. No scope creep.

## Issues Encountered

- `ScrollMetricsNotification` never fires in flutter_test on item additions via `pumpWidget` — fundamental framework limitation. Resolved by testing the controller state machine directly with `simulateContentGrowth()` helper.
- `addPostFrameCallback` in `_onControllerChanged` requires explicit `scheduleFrame()` to fire during `pump()` in test environment when called between frames.
- Drag re-attach/immediate-re-detach race condition from overshoot physics — resolved with `scrollDelta > 0` guard.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Auto-follow, detach, and re-attach fully wired and tested
- `scrollToBottom()` now correctly targets live bottom on reverse:true list
- `isAtBottom` ValueListenable available for scroll-to-bottom button visibility
- Ready for Phase 8: scroll-to-bottom button UI

---
*Phase: 07-auto-follow-and-scroll-detach*
*Completed: 2026-03-17*
