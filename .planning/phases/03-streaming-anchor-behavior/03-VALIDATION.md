---
phase: 3
slug: streaming-anchor-behavior
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter SDK built-in) |
| **Config file** | none — existing test structure from Phase 1/2 |
| **Quick run command** | `/Users/bommel/flutter/flutter/bin/flutter test` |
| **Full suite command** | `/Users/bommel/flutter/flutter/bin/flutter test --coverage` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test`
- **After every plan wave:** Run `flutter test --coverage`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | ANCH-01, ANCH-06 | widget | `flutter test test/anchor_behavior_test.dart` | No W0 | pending |
| 3-01-02 | 01 | 1 | ANCH-02, ANCH-03, ANCH-04, ANCH-05 | widget | `flutter test test/streaming_filler_test.dart` | No W0 | pending |
| 3-02-01 | 02 | 2 | API-04 | widget | `flutter test test/manual_scroll_test.dart` | No W0 | pending |
| 3-02-02 | 02 | 2 | API-04 | widget | `flutter test test/manual_scroll_test.dart` | No W0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `test/anchor_behavior_test.dart` — stubs for ANCH-01, ANCH-06
- [ ] `test/streaming_filler_test.dart` — stubs for ANCH-02, ANCH-03, ANCH-04, ANCH-05
- [ ] `test/manual_scroll_test.dart` — stubs for API-04

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Smooth anchor snap (no visual glitch) | ANCH-01 | Visual smoothness not testable in widget tests | Send message in example app, observe snap |
| iOS bouncing physics during anchor | ANCH-01 | flutter_test uses clamping physics | Test on iOS simulator |
| Filler shrinks visually during streaming | ANCH-03 | Visual confirmation | Watch filler space shrink as AI response grows |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
