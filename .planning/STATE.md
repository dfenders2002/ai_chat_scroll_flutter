# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-15)

**Core value:** When a user sends a message in an AI chat, that message snaps to the top of the viewport and the AI response grows below it — the user is never disoriented or auto-scrolled away.
**Current focus:** Phase 1 — Controller Foundation

## Current Position

Phase: 1 of 5 (Controller Foundation)
Plan: 0 of ? in current phase
Status: Ready to plan
Last activity: 2026-03-15 — Roadmap created

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: -
- Total execution time: -

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-phase]: Use CustomScrollView (forward-growing) over ListView(reverse: true) — top-anchor math requires stable coordinate system
- [Pre-phase]: AiChatScrollController extends ChangeNotifier, delegates to private ScrollController owned by AiChatScrollView
- [Pre-phase]: Filler isolation via ValueNotifier<double> + ValueListenableBuilder — prevents full-list rebuilds on streaming tokens
- [Pre-phase]: All scroll commands through addPostFrameCallback with hasClients guard — avoids build-phase scroll crash

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 3: Variable-height item measurement strategy not yet pinned down (GlobalKey at scale is expensive; SizeChangedLayoutNotifier or height cache map are candidates — validate during Phase 3 planning)
- Phase 3: Throttling filler recomputation to one update per frame — pattern known but exact debounce strategy needs implementation validation
- Phase 3: iOS BouncingScrollPhysics interaction with anchor offset during streaming — needs real-device testing

## Session Continuity

Last session: 2026-03-15
Stopped at: Roadmap created, STATE.md initialized — ready to plan Phase 1
Resume file: None
