---
phase: 1
slug: controller-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter SDK built-in) |
| **Config file** | none — Wave 0 creates test structure |
| **Quick run command** | `flutter test` |
| **Full suite command** | `flutter test --coverage` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test`
- **After every plan wave:** Run `flutter test --coverage`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | API-01 | unit | `flutter test test/ai_chat_scroll_controller_test.dart` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | API-02 | unit | `flutter test test/ai_chat_scroll_controller_test.dart` | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | QUAL-04 | static | `dart pub deps --style=list` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/ai_chat_scroll_controller_test.dart` — stubs for API-01, API-02
- [ ] `pubspec.yaml` — Flutter package scaffold with zero runtime deps

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Barrel export surface | QUAL-04 | Verify only expected symbols exported | Check `lib/ai_chat_scroll.dart` exports only `AiChatScrollController` and `AiChatScrollView` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
