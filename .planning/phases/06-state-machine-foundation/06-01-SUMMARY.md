---
phase: 06-state-machine-foundation
plan: "01"
subsystem: controller/state-machine
tags: [state-machine, enum, ValueNotifier, refactoring, backward-compat]
dependency_graph:
  requires: []
  provides: [AiChatScrollState enum, scrollState ValueListenable, _transition method]
  affects: [ai_chat_scroll_controller.dart, ai_chat_scroll.dart]
tech_stack:
  added: []
  patterns: [ValueNotifier state machine, TDD RED/GREEN, derived getter backward compat]
key_files:
  created:
    - lib/src/model/ai_chat_scroll_state.dart
    - test/state_machine_test.dart
  modified:
    - lib/src/controller/ai_chat_scroll_controller.dart
    - lib/ai_chat_scroll.dart
    - test/ai_chat_scroll_controller_test.dart
decisions:
  - "Keep isStreaming as derived getter (not deprecated) — minimal API surface, backward compat for existing consumers with zero view changes"
  - "TestWidgetsFlutterBinding.ensureInitialized() in unit test main() — onUserMessageSent calls SchedulerBinding internally"
  - "Update ai_chat_scroll_controller_test no-notify test — reflects correct new no-op contract (not a regression)"
metrics:
  duration: "~16 min"
  completed_date: "2026-03-17"
  tasks_completed: 2
  files_changed: 5
---

# Phase 6 Plan 1: State Machine Foundation Summary

**One-liner:** 5-value AiChatScrollState enum replaces boolean _streaming flag, exposed as ValueNotifier<AiChatScrollState> scrollState on the controller with derived isStreaming getter for backward compatibility.

## What Was Built

- `lib/src/model/ai_chat_scroll_state.dart` — Plain Dart enum with 5 values (`idleAtBottom`, `submittedWaitingResponse`, `streamingFollowing`, `streamingDetached`, `historyBrowsing`), each with dartdoc comments explaining semantics
- `lib/ai_chat_scroll.dart` — Barrel export updated to include `ai_chat_scroll_state.dart`
- `lib/src/controller/ai_chat_scroll_controller.dart` — Migrated from `bool _streaming` to `ValueNotifier<AiChatScrollState> _scrollState`; added `scrollState` getter, `_transition()` helper, and derived `isStreaming` getter; `onUserMessageSent()` and `onResponseComplete()` now use `_transition()`
- `test/state_machine_test.dart` — 19 unit tests covering STATE-01 (enum values), STATE-02 (transition rules), STATE-03 (ValueListenable exposure), and COMPAT (isStreaming derived logic)

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 (RED) | Enum, barrel export, failing test scaffold | cf85d35 |
| 2 (GREEN) | Controller migration + all tests GREEN | 7195731 |

## Test Results

- State machine tests: 19/19 passing
- Full suite: 42 passing, 15 failing (all 15 are pre-existing failures; zero regressions)
- `dart analyze lib/ test/`: No issues found
- `grep -r '_streaming' lib/`: NOT FOUND (boolean fully removed)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Flutter binding not initialized for unit tests calling onUserMessageSent()**
- **Found during:** Task 2 (GREEN phase)
- **Issue:** `onUserMessageSent()` calls `SchedulerBinding.instance` internally via `addPostFrameCallback`. Pure unit tests (non-`testWidgets`) don't initialize the Flutter binding automatically, causing "Binding has not yet been initialized" errors.
- **Fix:** Added `TestWidgetsFlutterBinding.ensureInitialized()` at the top of `state_machine_test.dart` main(). This is the standard Flutter testing pattern for unit tests that touch scheduler APIs.
- **Files modified:** `test/state_machine_test.dart`
- **Commit:** 7195731

**2. [Rule 1 - Bug] Existing controller test assumed always-notify behavior for onResponseComplete()**
- **Found during:** Task 2 (GREEN phase)
- **Issue:** `ai_chat_scroll_controller_test.dart` line 52-59 called `onResponseComplete()` on a fresh controller (idleAtBottom) and expected 1 notification. Under the new state machine, this is a no-op (idleAtBottom → idleAtBottom), which is correct per STATE-02i spec.
- **Fix:** Updated test to call `onResponseComplete()` after `onUserMessageSent()` to test a genuine state transition (submittedWaitingResponse → idleAtBottom), which does fire a notification.
- **Files modified:** `test/ai_chat_scroll_controller_test.dart`
- **Commit:** 7195731

## Key Decisions Made

1. **isStreaming kept as derived getter** — No deprecation annotation added. This is a public package; the getter stays as-is for maximum backward compat. Future phases can deprecate it if the v2.0 API surface review recommends it.

2. **_transition() uses both _scrollState.value = next AND notifyListeners()** — `_scrollState.value = next` notifies ValueListenable consumers (app-level state, ValueListenableBuilder). `notifyListeners()` notifies the ChangeNotifier channel (the internal `AiChatScrollView` via `addListener`). Both audiences need notification; both calls are required.

3. **No view changes** — `ai_chat_scroll_view.dart` was NOT modified. The view uses `widget.controller.isStreaming` which is now a derived getter returning the same semantics. This was the plan's intent and was confirmed correct.
