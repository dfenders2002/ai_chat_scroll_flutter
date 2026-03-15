---
phase: 05-v1x-enhancements
plan: 02
subsystem: ui
tags: [flutter, scroll, keyboard, viewport, filler, valuenotifier, dart]

# Dependency graph
requires:
  - phase: 05-v1x-enhancements plan 01
    provides: AiChatScrollView with ScrollMetricsNotification listener, filler ValueNotifier, _anchorActive flag
  - phase: 03-streaming-anchor-behavior
    provides: 3-phase anchor pipeline (_executeAnchorJump, _recomputeFiller, _lastMaxScrollExtent)
provides:
  - Keyboard-aware filler recomputation via viewportDimension change detection in ScrollMetricsNotification
  - _lastViewportDimension field tracking previous viewport height
  - _onViewportDimensionChanged() method adjusting filler by delta and re-anchoring
  - Filler clamped to 0.0 — never negative
  - AiChatScrollView dartdoc with "## Keyboard awareness" section
affects: [developers testing on mobile where soft keyboard affects viewport]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Viewport compensation: capture _lastViewportDimension at anchor jump end; compare on each ScrollMetricsNotification; call _onViewportDimensionChanged only when _anchorActive and delta is non-zero"
    - "Filler delta math: filler += viewportDimension delta (both grow together, both shrink together) — maxScrollExtent stays constant, pixels stay constant, item Y stays constant"

key-files:
  created:
    - test/keyboard_compensation_test.dart
  modified:
    - lib/src/widgets/ai_chat_scroll_view.dart

key-decisions:
  - "viewportDimension delta math: filler += delta keeps maxScrollExtent invariant — no jumpTo required for visual correctness (jumpTo is a no-op since pixels already equal maxScrollExtent). Added anyway for safety after large deltas."
  - "_lastViewportDimension updated in _recomputeFiller() to keep it current during streaming filler updates"
  - "Test assertions check visual position (item Y=0) not maxScrollExtent — maxScrollExtent is invariant under keyboard open/close, so it cannot distinguish compensated vs uncompensated behavior"
  - "TDD RED tests originally asserted maxScrollExtent changes — corrected to assert Y=0 after discovering the math invariant"

patterns-established:
  - "Viewport-dimension tracking: capture at anchor jump, update in _recomputeFiller, compare in ScrollMetricsNotification — single source of truth for compensation delta"

requirements-completed: [ENHN-02]

# Metrics
duration: 4min
completed: 2026-03-15
---

# Phase 5 Plan 02: Keyboard-Aware Anchor Compensation Summary

**ViewportDimension-delta keyboard compensation in AiChatScrollView: filler shrinks/grows with keyboard open/close during anchor, keeping sent message at Y=0 on mobile**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-03-15T18:36:43Z
- **Completed:** 2026-03-15T18:41:02Z
- **Tasks:** 2 (Task 1 TDD + Task 2 regression/docs)
- **Files modified:** 2

## Accomplishments

- Added `_lastViewportDimension` field to `_AiChatScrollViewState` to track previous viewport height
- Added `_onViewportDimensionChanged()` that adjusts filler by the exact viewport delta and re-anchors
- Hooked viewport dimension detection into the existing `ScrollMetricsNotification` handler — zero additional listeners required
- Captured `_lastViewportDimension` in `_executeAnchorJump()` (end of anchor pipeline) and updated it in `_recomputeFiller()` during streaming
- 4 new keyboard compensation tests; all 38 total tests pass with zero regressions
- `dart analyze lib/` reports zero issues
- Added `## Keyboard awareness` section to `AiChatScrollView` class dartdoc

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Add failing tests for keyboard-aware filler recomputation** - `17aba76` (test)
2. **Task 1 GREEN: Add keyboard-aware filler recomputation on viewportDimension change** - `bab6272` (feat)
3. **Task 2: Add keyboard awareness dartdoc and verify zero analyze warnings** - `bd04047` (feat)

## Files Created/Modified

- `lib/src/widgets/ai_chat_scroll_view.dart` - Added `_lastViewportDimension`, `_onViewportDimensionChanged()`, viewport detection in notification handler, `_recomputeFiller` update, "## Keyboard awareness" dartdoc
- `test/keyboard_compensation_test.dart` - 4 tests: keyboard open anchor stays Y=0, keyboard close anchor stays Y=0, outside-anchor no compensation, filler clamps to 0.0

## Decisions Made

- **Filler delta math invariant discovered:** When keyboard opens (viewport shrinks by N), filler shrinks by N, and total content height shrinks by N. Since viewport also shrinks by N, maxScrollExtent = total - viewport stays constant. Pixels stay at maxScrollExtent. Item Y stays at 0. The compensation works without needing to move the scroll position at all — the filler change alone preserves the invariant. The `jumpTo(maxScrollExtent)` in the postFrameCallback is redundant in normal operation but retained as a safety net for edge cases where large deltas could cause floating-point drift.

- **Test assertion correction:** Initial RED tests asserted `maxScrollExtent < maxScrollExtentBefore` after keyboard open. After discovering the invariant, tests were corrected to assert `item Y == 0.0` — the actual user-visible requirement. The maxScrollExtent assertion was mathematically wrong.

- **_lastViewportDimension updated in _recomputeFiller:** During streaming, filler changes (content grows, filler shrinks) do NOT change viewportDimension. However, keeping `_lastViewportDimension` updated there ensures that if `_executeAnchorJump` never fires a second time (streaming began, keyboard opened mid-stream), the baseline stays accurate.

## Deviations from Plan

### Test Assertion Corrections (not code deviations)

**1. [Rule 1 - Bug] TDD RED test assertions were mathematically incorrect**
- **Found during:** Task 1 GREEN phase
- **Issue:** Initial RED tests asserted `maxScrollExtent` changes after keyboard open/close. The filler delta math makes maxScrollExtent invariant under keyboard open/close — the assertion was wrong, not the code.
- **Fix:** Corrected test assertions to check visual position (item Y=0) and `pixels == maxScrollExtent` (still anchored) instead of maxScrollExtent magnitude
- **Files modified:** test/keyboard_compensation_test.dart
- **Committed in:** bab6272 (GREEN commit includes corrected tests)

---

**Total deviations:** 1 test assertion correction (math invariant discovery — not a code deviation)
**Impact on plan:** Implementation follows plan exactly. Test corrections improved test quality by asserting user-visible behavior (Y=0) rather than an internal metric that was invariant.

## Issues Encountered

None beyond the test assertion correction documented above. The math invariant (`filler + viewportDimension = constant → maxScrollExtent = constant`) was an elegant property discovered during implementation, not a problem.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Keyboard compensation is fully implemented and tested
- Phase 5 Plan 02 is the final plan in Phase 5 (v1x enhancements)
- The package is ready for v1.x release with both ENHN-01 (isAtBottom/scrollToBottom) and ENHN-02 (keyboard compensation) complete
- Real-device testing recommended on iOS with BouncingScrollPhysics to validate keyboard compensation under bouncing physics (test environment uses clamping physics)

## Self-Check: PASSED

- lib/src/widgets/ai_chat_scroll_view.dart: FOUND
- test/keyboard_compensation_test.dart: FOUND
- .planning/phases/05-v1x-enhancements/05-02-SUMMARY.md: FOUND
- Commit 17aba76: FOUND
- Commit bab6272: FOUND
- Commit bd04047: FOUND
