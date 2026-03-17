---
phase: 6
slug: state-machine-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter SDK, no version pin) |
| **Config file** | none — `flutter test` discovers tests in `test/` |
| **Quick run command** | `flutter test test/state_machine_test.dart --no-pub` |
| **Full suite command** | `flutter test --no-pub` |
| **Estimated runtime** | ~15 seconds |

**Baseline:** 23 pass, 15 pre-existing failures (from in-progress view refactor, not Phase 6). Phase 6 must not increase failures beyond 15.

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/ai_chat_scroll_controller_test.dart --no-pub`
- **After every plan wave:** Run `flutter test --no-pub`
- **Before `/gsd:verify-work`:** Full suite must be green (no new failures beyond pre-existing 15)
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | STATE-01 | unit | `flutter test test/state_machine_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 1 | STATE-02 | unit | `flutter test test/state_machine_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 06-01-03 | 01 | 1 | STATE-02 | widget | `flutter test test/state_machine_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 06-01-04 | 01 | 1 | STATE-03 | unit | `flutter test test/state_machine_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 06-01-05 | 01 | 1 | (compat) | regression | `flutter test --no-pub` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/state_machine_test.dart` — stubs for STATE-01, STATE-02, STATE-03 (enum values, transitions, ValueListenable exposure)

*Existing `test/ai_chat_scroll_controller_test.dart` covers backward compatibility (isStreaming getter).*

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
