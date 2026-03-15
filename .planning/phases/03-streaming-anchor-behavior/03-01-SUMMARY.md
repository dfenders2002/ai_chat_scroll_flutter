---
phase: 03-streaming-anchor-behavior
plan: 01
subsystem: ui
tags: [flutter, scroll, anchor, streaming, filler, ValueNotifier, GlobalKey, postFrameCallback]

# Dependency graph
requires:
  - phase: 02-sliver-composition
    provides: CustomScrollView with SliverList.builder + SliverToBoxAdapter FillerSliver; _fillerHeight ValueNotifier infrastructure

provides:
  - Anchor-on-send: onUserMessageSent() snaps last item to viewport top via jumpTo
  - Streaming filler: filler shrinks as AI response grows to hold anchor stable
  - Drag cancellation: user drag sets _anchorActive = false, restoring free scroll
  - Controller state: isStreaming getter + _streaming bool lifecycle
  - Tests for ANCH-01 through ANCH-06

affects:
  - 04-user-scroll-detection
  - 05-integration-polish

# Tech tracking
tech-stack:
  added: []
  patterns:
    - 3-phase postFrameCallback anchor pipeline (scroll-to-bottom → measure → jump)
    - scheduleFrame() to force layout frame when jumpTo is a no-op
    - _fillerUpdateScheduled bool for frame-throttled filler recomputation
    - ScrollMetricsNotification + ScrollController.addListener dual listener strategy
    - NotificationListener<ScrollUpdateNotification> with dragDetails != null for drag detection

key-files:
  created:
    - test/anchor_behavior_test.dart
    - test/streaming_filler_test.dart
  modified:
    - lib/src/controller/ai_chat_scroll_controller.dart
    - lib/src/widgets/ai_chat_scroll_view.dart

key-decisions:
  - "Anchor jump target = new maxScrollExtent (after filler set), NOT maxScrollExtent - viewportDimension + sentMsgHeight — the RESEARCH.md formula was incorrect for this filler-inclusive setup"
  - "3-phase postFrameCallback chain needed because jumpTo(0) is a no-op and does not schedule a frame; scheduleFrame() forces the layout pass so Phase 3 fires"
  - "setState() called in _onControllerChanged to apply GlobalKey to anchor item — control flags like _anchorActive do not need setState, but _anchorIndex does to drive the key in the build method"
  - "SliverToBoxAdapter with SizedBox(height: 0) is NOT found by find.byType(SizedBox) in flutter_test due to lazy sliver rendering optimization — tests must handle this case"

patterns-established:
  - "Pattern: anchor pipeline — Phase1: scrollToBottom; Phase2: measureAndSetFiller + scheduleFrame(); Phase3: executeAnchorJump to maxScrollExtent"
  - "Pattern: filler delta tracking — _lastMaxScrollExtent captures jump baseline; listener computes growth = maxScrollExtent - _lastMaxScrollExtent; filler = max(0, filler - growth)"
  - "Pattern: test pump helper — pumpAnchor() does 4 pumps + pumpAndSettle to fire all 3 postFrameCallback phases"

requirements-completed: [ANCH-01, ANCH-02, ANCH-03, ANCH-04, ANCH-05, ANCH-06]

# Metrics
duration: 45min
completed: 2026-03-15
---

# Phase 03 Plan 01: Streaming Anchor Behavior Summary

**Anchor-on-send with streaming filler: jumpTo(maxScrollExtent) after setting filler = viewportDimension - sentMsgHeight, driven by a 3-phase postFrameCallback pipeline with scheduleFrame() to guarantee frame dispatch**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-03-15T00:00:00Z
- **Completed:** 2026-03-15T00:45:00Z
- **Tasks:** 2 (TDD RED + TDD GREEN)
- **Files modified:** 4

## Accomplishments

- ANCH-01: After `onUserMessageSent()`, the sent message snaps to viewport top (Y=0)
- ANCH-02/03/04: During streaming, only filler shrinks — scroll position stays locked, anchor stays visible
- ANCH-05: Filler clamps to 0 when AI response exceeds viewport height
- ANCH-06: Re-anchor after scrolling to history works correctly
- All 22 tests pass (6 new ANCH tests + 16 Phase 1+2 regression)
- `flutter analyze` reports no issues

## Task Commits

Each task was committed atomically:

1. **Task 1: Wave 0 — Write failing tests for anchor behavior and streaming filler** - `47104ab` (test)
2. **Task 2: Implement anchor jump, streaming filler, and controller state** - `67c93e4` (feat)

_Both tasks used TDD: Task 1 = RED phase, Task 2 = GREEN phase_

## Files Created/Modified

- `test/anchor_behavior_test.dart` - Tests for ANCH-01 and ANCH-06 with pumpAnchor() helper
- `test/streaming_filler_test.dart` - Tests for ANCH-02, ANCH-03, ANCH-04, ANCH-05 with readFillerHeight() helper
- `lib/src/controller/ai_chat_scroll_controller.dart` - Added `_streaming` bool, `isStreaming` getter; `onUserMessageSent()` sets `_streaming = true`; `onResponseComplete()` sets `_streaming = false`
- `lib/src/widgets/ai_chat_scroll_view.dart` - Full anchor pipeline: `_onControllerChanged`, `_scrollToBottomForMeasurement`, `_measureAndSetFiller`, `_executeAnchorJump`; filler recomputation via `_onScrollChanged` + `_recomputeFiller`; drag detection via `NotificationListener<ScrollUpdateNotification>`

## Decisions Made

**1. Anchor jump formula correction: `target = new_maxScrollExtent`**

The RESEARCH.md formula `target = maxScrollExtent - viewportDimension + sentMsgHeight` was incorrect. Derivation: when `filler = viewportDimension - sentMsgHeight` is set, `new_maxScrollExtent = original_maxScrollExtent + filler`. The desired jump target (offset that places anchor top at Y=0) is `original_maxScrollExtent + viewportDimension - sentMsgHeight = new_maxScrollExtent`. So `target = new_maxScrollExtent` after filler is set.

**2. `scheduleFrame()` required to unstick the pipeline**

When `jumpTo(currentMaxScrollExtent)` is a no-op (e.g., already at maxScrollExtent, or maxScrollExtent = 0), Flutter does not schedule a new frame. Subsequent `addPostFrameCallback` calls would never fire. Fix: call `SchedulerBinding.instance.scheduleFrame()` after setting filler in Phase 2 to force a frame that fires Phase 3's callback.

**3. `setState` needed for `_anchorIndex` (but not `_anchorActive`)**

`_anchorIndex` drives the item builder's GlobalKey assignment, so it needs `setState` to trigger a rebuild. `_anchorActive` is a control flag that gates scroll listeners — it doesn't affect the render tree, so no `setState` needed.

**4. SizedBox(height:0) not findable in sliver context**

`find.byType(SizedBox)` does not find `SizedBox(height: 0)` inside `SliverToBoxAdapter` when the sliverextent is zero. The `readFillerHeight` test helper handles this: absence in `find.byType` results = 0.0 filler, which is correct for the ANCH-05 post-condition.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] RESEARCH.md anchor formula was incorrect**
- **Found during:** Task 2 (anchor jump implementation)
- **Issue:** RESEARCH.md Pattern 1 formula `target = maxScrollExtent - viewportDimension + sentMsgHeight` placed the anchor item at Y=500 (not Y=0). The formula assumed the new maxScrollExtent was used but the formula actually resolves to the original maxScrollExtent adjusted incorrectly.
- **Fix:** Derived correct formula: `target = new_maxScrollExtent` (after filler = viewportDimension - sentMsgHeight is set). Proof: `new_max = original_max + filler = original_max + viewport - sentH = sum_of_items_above_anchor`. Jumping to `new_max` places anchor top at Y=0.
- **Files modified:** lib/src/widgets/ai_chat_scroll_view.dart
- **Verification:** ANCH-01 test passes with Y=0 for anchor item
- **Committed in:** 67c93e4 (Task 2 commit)

**2. [Rule 3 - Blocking] `scheduleFrame()` needed for zero-scroll-extent anchor**
- **Found during:** Task 2 (ANCH-05 pre-condition failure)
- **Issue:** For a 1-item list where `maxScrollExtent = 0`, `jumpTo(0)` is a no-op and doesn't schedule a frame. Phase 2's postFrameCallback registered inside Phase 1 never fired.
- **Fix:** Added `SchedulerBinding.instance.scheduleFrame()` in both the "no jump needed" branch and after `_fillerHeight.value = X` in Phase 2 to ensure a frame is always scheduled.
- **Files modified:** lib/src/widgets/ai_chat_scroll_view.dart
- **Verification:** ANCH-05 pre-condition (filler=500 after anchor) now passes
- **Committed in:** 67c93e4 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 bug in RESEARCH.md formula, 1 blocking frame scheduling issue)
**Impact on plan:** Both fixes essential for correctness. No scope creep.

## Issues Encountered

- `readFillerHeight` helper needed special handling for SizedBox(height=0) in sliver context (returns 0 by default when not found, which is semantically correct)
- 3-pump test helper (`pumpAnchor`) required 4 pumps + pumpAndSettle to cover the 3-phase pipeline

## Next Phase Readiness

- Core anchor behavior complete (ANCH-01 through ANCH-06)
- Phase 4 can build user-scroll detection (drag cancels anchor — partial implementation in Phase 3 via `ScrollUpdateNotification.dragDetails != null`)
- Remaining concern: iOS bouncing scroll physics interaction with anchor offset — needs real-device testing (not coverable by flutter_test which emulates clamping physics)

---
*Phase: 03-streaming-anchor-behavior*
*Completed: 2026-03-15*
