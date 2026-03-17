---
phase: 7
slug: auto-follow-and-scroll-detach
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter SDK) |
| **Config file** | none — `flutter test` discovers tests in `test/` |
| **Quick run command** | `flutter test test/auto_follow_test.dart --no-pub` |
| **Full suite command** | `flutter test --no-pub` |
| **Estimated runtime** | ~15 seconds |

**Baseline:** 42 pass, 15 pre-existing failures (from earlier view refactor). Phase 7 must not increase failures.

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/auto_follow_test.dart --no-pub`
- **After every plan wave:** Run `flutter test --no-pub`
- **Before `/gsd:verify-work`:** Full suite must be green (42 + new FOLLOW tests, no new failures)
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | FOLLOW-01 | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-01"` | ❌ W0 | ⬜ pending |
| 07-01-02 | 01 | 1 | FOLLOW-01 | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-01b"` | ❌ W0 | ⬜ pending |
| 07-01-03 | 01 | 1 | FOLLOW-02 | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-02"` | ❌ W0 | ⬜ pending |
| 07-01-04 | 01 | 1 | FOLLOW-02 | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-02b"` | ❌ W0 | ⬜ pending |
| 07-01-05 | 01 | 1 | FOLLOW-03 | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-03"` | ❌ W0 | ⬜ pending |
| 07-01-06 | 01 | 1 | FOLLOW-03 | widget | `flutter test test/auto_follow_test.dart --no-pub -n "FOLLOW-03b"` | ❌ W0 | ⬜ pending |
| 07-01-07 | 01 | 1 | (compat) | regression | `flutter test --no-pub` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/auto_follow_test.dart` — stubs for FOLLOW-01, FOLLOW-02, FOLLOW-03 and sub-cases
- No additional fixtures needed — existing `buildTestWidget()` pattern is the correct template

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
