---
phase: 03-streaming-anchor-behavior
verified: 2026-03-15T00:00:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 03: Streaming Anchor Behavior Verification Report

**Phase Goal:** Sending a message snaps the user's message to the top of the viewport, AI response grows below it without auto-scroll, and user drag correctly cancels managed scroll behavior
**Verified:** 2026-03-15
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                               | Status     | Evidence                                                                                                                 |
|----|-----------------------------------------------------------------------------------------------------|------------|--------------------------------------------------------------------------------------------------------------------------|
| 1  | After onUserMessageSent(), the sent message's top edge is at the viewport top                      | VERIFIED  | ANCH-01 test passes: `lastItemTopY` verified at `closeTo(0.0, 1.0)`; `_executeAnchorJump` calls `jumpTo(maxScrollExtent)` |
| 2  | As AI response grows (itemCount increases), filler shrinks and sent message stays at viewport top   | VERIFIED  | ANCH-02 + ANCH-03 tests pass; `_recomputeFiller` subtracts `growth` from `_fillerHeight.value`                           |
| 3  | During streaming, user's scroll position remains stable — no jumps or auto-scrolls occur           | VERIFIED  | ANCH-04 test passes: `pixelsAfter` verified `closeTo(pixelsBefore, 1.0)` after adding streaming items                   |
| 4  | Filler clamps to 0 when AI response exceeds viewport height                                        | VERIFIED  | ANCH-05 test passes: `math.max(0.0, _fillerHeight.value - growth)` clamping confirmed; filler reaches `closeTo(0.0, 1.0)` |
| 5  | Calling onUserMessageSent() after scrolling up to history re-anchors the new message at top        | VERIFIED  | ANCH-06 test passes: `Msg 10` at Y=0 after scrolling to 0.0 and re-sending                                              |
| 6  | onResponseComplete() stops filler recomputation and clears anchor state                            | VERIFIED  | `onResponseComplete()` sets `_streaming = false`, `notifyListeners()`, widget sets `_anchorActive = false` in setState   |
| 7  | A user drag gesture during anchor-active streaming immediately cancels the anchor                  | VERIFIED  | API-04 test 1 passes: after `tester.drag`, adding items does NOT reset position back to anchor target                    |
| 8  | After drag cancellation, subsequent content growth does not re-hijack scroll position              | VERIFIED  | `_anchorActive = false` in `NotificationListener<ScrollUpdateNotification>` gates `_onScrollChanged` no-op               |
| 9  | Anchor behavior resumes only on the next onUserMessageSent() call                                  | VERIFIED  | API-04 test 2 passes: `Msg 10` at Y=0 after drag + new `onUserMessageSent()`                                            |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact                                                          | Expected                                                                   | Status    | Details                                                                                                      |
|-------------------------------------------------------------------|----------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------------------------------------|
| `lib/src/controller/ai_chat_scroll_controller.dart`              | Streaming state (`_streaming`, `isStreaming`) and notifyListeners          | VERIFIED  | `bool _streaming = false`, `bool get isStreaming => _streaming`, set in `onUserMessageSent`/`onResponseComplete` |
| `lib/src/widgets/ai_chat_scroll_view.dart`                        | Anchor pipeline, GlobalKey measurement, filler recomputation, drag cancel  | VERIFIED  | Contains `_anchorActive`, 3-phase pipeline, `NotificationListener<ScrollUpdateNotification>` drag detection  |
| `test/anchor_behavior_test.dart`                                  | Widget tests for ANCH-01 and ANCH-06                                      | VERIFIED  | 2 test groups, both exercising `onUserMessageSent()` + `pumpAnchor()` helper, substantive assertions          |
| `test/streaming_filler_test.dart`                                 | Widget tests for ANCH-02, ANCH-03, ANCH-04, ANCH-05                      | VERIFIED  | 4 test groups, `readFillerHeight` helper, all substantive assertions on pixels and filler height             |
| `test/manual_scroll_test.dart`                                    | Widget tests for API-04 and ANCH-05 manual scroll                         | VERIFIED  | 3 tests across 2 groups, drag simulation via `tester.drag`, substantive position assertions                  |

---

### Key Link Verification

| From                                        | To                              | Via                                                     | Status    | Details                                                                                 |
|---------------------------------------------|---------------------------------|---------------------------------------------------------|-----------|-----------------------------------------------------------------------------------------|
| `ai_chat_scroll_controller.dart`            | `ai_chat_scroll_view.dart`      | `controller.addListener(_onControllerChanged)` in initState | WIRED  | Line 88: `widget.controller.addListener(_onControllerChanged)` confirmed                |
| `ai_chat_scroll_view.dart`                  | `ScrollController`              | `_scrollController.addListener(_onScrollChanged)`      | WIRED     | Line 86: `_scrollController.addListener(_onScrollChanged)` confirmed                   |
| `ai_chat_scroll_view.dart`                  | `FillerSliver`                  | `_fillerHeight.value` assignment drives filler rendering | WIRED  | Lines 197, 251: two assignment sites; `FillerSliver(fillerHeight: _fillerHeight)` wired |
| `ai_chat_scroll_view.dart`                  | `ScrollUpdateNotification`      | `NotificationListener` checking `dragDetails != null`  | WIRED     | Line 260: `NotificationListener<ScrollUpdateNotification>`, line 262: guard confirmed   |
| `ai_chat_scroll_view.dart`                  | `_anchorActive`                 | Set to false on drag, re-enabled by next send           | WIRED     | Line 263: `_anchorActive = false` on drag; line 113: `isStreaming` check re-enables     |

---

### Requirements Coverage

| Requirement | Source Plan | Description                                                                       | Status    | Evidence                                                                                        |
|-------------|-------------|-----------------------------------------------------------------------------------|-----------|-------------------------------------------------------------------------------------------------|
| ANCH-01     | 03-01       | Viewport snaps so user's message is at the top after send                        | SATISFIED | `anchor_behavior_test.dart` ANCH-01 group passes; `_executeAnchorJump` → `jumpTo(maxScrollExtent)` |
| ANCH-02     | 03-01       | AI response streams below user message, growing downward                         | SATISFIED | `streaming_filler_test.dart` ANCH-02 group passes; filler shrinks to allow content growth below  |
| ANCH-03     | 03-01       | Dynamic filler rendered below AI response to keep anchor stable                  | SATISFIED | `streaming_filler_test.dart` ANCH-03: `fillerAfter < fillerBefore` confirmed; `math.max(0, filler - growth)` |
| ANCH-04     | 03-01       | No auto-scroll during AI streaming — user stays at sent message                  | SATISFIED | `streaming_filler_test.dart` ANCH-04: `pixelsAfter closeTo(pixelsBefore, 1.0)` passes          |
| ANCH-05     | 03-01       | If AI response exceeds viewport, user must manually scroll to see rest           | SATISFIED | `streaming_filler_test.dart` ANCH-05: filler clamps to 0; `manual_scroll_test.dart` drag test passes |
| ANCH-06     | 03-01       | When scrolled to history then new message sent, viewport resets to top-anchor    | SATISFIED | `anchor_behavior_test.dart` ANCH-06 group: Msg 10 at Y=0 after history scroll + re-send        |
| API-04      | 03-02       | User drag cancels managed scroll — no re-hijacking until next onUserMessageSent  | SATISFIED | `manual_scroll_test.dart` API-04 group (2 tests); drag sets `_anchorActive = false`             |

**Orphaned requirements check:** REQUIREMENTS.md traceability table maps ANCH-01 through ANCH-06 and API-04 all to Phase 3. All 7 are claimed by plans 03-01 and 03-02. No orphaned requirements.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | None found | — | `grep` for TODO/FIXME/XXX/HACK/PLACEHOLDER across `lib/` returned no matches |

No stubs, no placeholder returns, no empty handlers. The `onUserMessageSent` controller method contains an empty `addPostFrameCallback` body (lines 76–81) but this is intentional and documented: the callback is a safety guard retained from Phase 1; the actual anchor logic lives in the widget state listener. It is not a stub — it guards against pre-mount calls and documents why.

---

### Human Verification Required

#### 1. iOS Bouncing Scroll Physics Interaction

**Test:** On an iOS device or simulator, anchor a message, then allow the AI response to stream in. Observe whether the bouncing physics at the top or bottom of the scroll view disturb the anchor position.
**Expected:** The anchor remains stable during iOS overscroll bounce; filler still shrinks correctly; no visible jump or jitter.
**Why human:** `flutter_test` emulates clamping physics (Android-style). iOS `BouncingScrollPhysics` behavior with negative scroll extents cannot be reliably validated in widget tests. This was flagged as a known limitation in both SUMMARYs.

#### 2. Real-time Streaming Visual Stability

**Test:** In the example app (once built in Phase 4), send a message and watch a simulated streaming response populate character-by-character.
**Expected:** The sent message stays pinned at the top visually; the AI response text grows downward smoothly; no flicker or jump is visible.
**Why human:** Widget tests pump discrete frames; they cannot verify perceived visual smoothness or the absence of flicker under real timing conditions.

---

### Test Suite Results

```
25 tests, 0 failures, 0 skipped
flutter analyze: No issues found!
```

All 25 tests pass:
- 2 tests from `anchor_behavior_test.dart` (ANCH-01, ANCH-06)
- 4 tests from `streaming_filler_test.dart` (ANCH-02, ANCH-03, ANCH-04, ANCH-05)
- 3 tests from `manual_scroll_test.dart` (API-04 x2, ANCH-05 manual)
- 16 regression tests from Phase 1+2 (all still pass)

---

### Gaps Summary

No gaps. All 9 observable truths are verified, all 5 artifacts exist and are substantively implemented and wired, all 7 key links are confirmed present in the code, all 7 requirement IDs (ANCH-01 through ANCH-06, API-04) are satisfied with test evidence.

The two human verification items above (iOS physics, visual smoothness) are informational — they do not block phase completion as they are known flutter_test limitations, not implementation gaps.

---

_Verified: 2026-03-15_
_Verifier: Claude (gsd-verifier)_
