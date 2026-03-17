---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Dual-Layout Scroll Redesign
status: active
stopped_at: null
last_updated: "2026-03-17"
last_activity: 2026-03-17 — Milestone v2.0 started
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** When a user sends a message in an AI chat, that message snaps to the top of the viewport and the AI response grows below it — the user is never disoriented or auto-scrolled away.
**Current focus:** Defining requirements for v2.0

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-03-17 — Milestone v2.0 started

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
- [v1.0]: AiChatScrollView uses itemBuilder/itemCount API — owns CustomScrollView for sliver composition
- [v1.0]: scheduleFrame() required after setting filler when jumpTo would be a no-op
- [v1.0]: isAtBottom is signal-only ValueListenable — no built-in FAB widget shipped
- [v1.0]: viewportDimension delta math: filler += delta keeps maxScrollExtent invariant under keyboard changes

### Pending Todos

None.

### Blockers/Concerns

- iOS BouncingScrollPhysics interaction with anchor offset during streaming — needs real-device testing

## Session Continuity

Last session: 2026-03-17
Stopped at: null
Resume file: None
