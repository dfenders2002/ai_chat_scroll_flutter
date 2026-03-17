---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: — Dual-Layout Scroll Redesign
status: in-progress
stopped_at: Completed 07-01-PLAN.md
last_updated: "2026-03-17T00:00:00Z"
last_activity: 2026-03-17 — Phase 7 Plan 1 complete: auto-follow/detach/re-attach wired
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 2
  completed_plans: 2
  percent: 10
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** When a user sends a message in an AI chat, that message snaps to the top of the viewport and the AI response grows below it — the user is never disoriented or auto-scrolled away.
**Current focus:** Phase 6 — State Machine Foundation (ready to plan)

## Current Position

Phase: 7 of 10 (Auto-Follow and Scroll Detach)
Plan: 1 of 1 in current phase (complete)
Status: Phase 7 complete — ready for Phase 8
Last activity: 2026-03-17 — auto-follow/detach/re-attach wired with state-enum guards

Progress: [██░░░░░░░░] 20% (v2.0 milestone)

## Performance Metrics

**Velocity (from v1.0):**
- Total plans completed: 8
- Average duration: ~8 min
- Total execution time: ~63 min

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1.0]: Use CustomScrollView (forward-growing) over ListView(reverse: true) — top-anchor math requires stable coordinate system
- [v1.0]: AiChatScrollController extends ChangeNotifier, delegates to private ScrollController owned by AiChatScrollView
- [v1.0]: Filler isolation via ValueNotifier<double> + ValueListenableBuilder — prevents full-list rebuilds on streaming tokens
- [v1.0]: All scroll commands through addPostFrameCallback with hasClients guard — avoids build-phase scroll crash
- [v1.0]: scheduleFrame() required after setting filler when jumpTo would be a no-op
- [v1.0]: isAtBottom is signal-only ValueListenable — no built-in FAB widget shipped
- [v1.0]: viewportDimension delta math: filler += delta keeps maxScrollExtent invariant under keyboard changes
- [v2.0 CRITICAL]: Define AiChatScrollState enum and migrate controller BEFORE any new behavioral code — boolean proliferation is the top risk
- [Phase 06]: isStreaming kept as derived getter (no deprecation) for backward compat; _transition() calls both _scrollState.value and notifyListeners() to notify both ValueListenable and ChangeNotifier audiences
- [Phase 07]: double.maxFinite sentinel for _lastMaxScrollExtent prevents spurious compensation before anchor baseline — no separate _anchorSetupComplete flag needed
- [Phase 07]: ScrollMetricsNotification doesn't fire in flutter_test on pumpWidget additions — tests call controller.onContentGrowthDetected() directly
- [Phase 07]: scrollDelta > 0 guard in drag detection prevents re-attach → immediate-detach race on scroll-back gestures
- [Phase 07]: scheduleFrame() must precede addPostFrameCallback in _onControllerChanged to fire in pump() when registered between frames in test environment

### Pending Todos

None.

### Blockers/Concerns

- iOS BouncingScrollPhysics interaction with anchor offset during streaming — needs real-device testing (Phase 8/9)
- onUserMessageSent() during streamingFollowing (rapid send): transition table must define explicit behavior in Phase 6 before Phase 7 auto-follow is built on top
- onResponseComplete() ordering contract: must be documented before v2.0 ships — consumer must call only after final streaming setState is committed

## Session Continuity

Last session: 2026-03-17T00:00:00Z
Stopped at: Completed 07-01-PLAN.md
Resume file: None
