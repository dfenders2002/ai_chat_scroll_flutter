---
phase: 2
slug: sliver-composition
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter SDK built-in) |
| **Config file** | none — existing test structure from Phase 1 |
| **Quick run command** | `flutter test` |
| **Full suite command** | `flutter test --coverage` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test`
- **After every plan wave:** Run `flutter test --coverage`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | API-03, SCRL-01 | widget | `flutter test test/ai_chat_scroll_view_test.dart` | ❌ W0 | ⬜ pending |
| 2-01-02 | 01 | 1 | SCRL-02, SCRL-03 | widget | `flutter test test/ai_chat_scroll_view_test.dart` | ❌ W0 | ⬜ pending |
| 2-01-03 | 01 | 1 | SCRL-04 | widget | `flutter test test/ai_chat_scroll_view_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/ai_chat_scroll_view_test.dart` — widget test stubs for API-03, SCRL-01 through SCRL-04

*Existing infrastructure from Phase 1 covers test runner setup.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No visible scroll jank on insertion | SCRL-02 | Visual smoothness not fully testable in widget tests | Run example app, add messages rapidly, observe for jank |
| iOS bounce / Android clamp correct | SCRL-04 | Platform physics require device testing | Test on iOS simulator + Android emulator |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
