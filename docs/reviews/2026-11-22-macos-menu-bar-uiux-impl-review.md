# macOS panel layout implementation review

Target: `git diff feat/macos-menu-bar..06e4b20 -- apps/macos docs/macos-menu-bar.md`, implemented by
Codex `gpt-6.2-sol` (high) from `docs/plans/2026-11-22-macos-menu-bar-uiux.md`.

Orchestrator verification (Claude Opus, the implementer's sandbox blocked `~/.cache/clang`):
`swift test` 39 tests, 0 failures; each `test:` commit (`6c749e1`, `640c460`, `05a8df3`)
compiles and fails on assertions before its implementation commit; `build-app.sh` and
`codesign --verify --strict` pass; `TimelineView` and `DisclosureGroup` appear only in comments.

| Reviewer | Scope | Verdict |
| --- | --- | --- |
| Claude Opus, separate context (`feature-dev:code-reviewer`), read-only, no shell | Correctness against the plan, full files (no diff available to it) | APPROVE, no findings; noted `1 quotas` |
| AGY `gemini-4-neon-high`, effort high, owner-requested UI/UX lane | Plan conformance and UX | REQUEST_CHANGES |

Neon findings, each checked against the cited code:

| Severity | Finding | Verified |
| --- | --- | --- |
| HIGH | Settings switches do not align: the toggle label has no full-width frame (`ProviderVisibilitySettings.swift:45-56`) | Yes |
| MEDIUM | Provider state is in `accessibilityHint`, not the label (`:57-58`) | Yes |
| MEDIUM | `invalidOrigin` clears only when settings open (`MenuBarContentView.swift:323`), not on edit or source change | Yes |
| MEDIUM | `Stale (cached)` is orange text without an icon; status row spacer pushes a lone status to the right (`:150-164`) | Yes |
| MEDIUM | `LazyVStack` inside both capped `ScrollView`s may mis-measure in a `.window` panel | Code confirmed; effect not reproduced, preventive |
| LOW | Busy first load shows "No Usage Data" | Yes, `:237` |
| LOW | Singular counts (`1 quotas`, `All 1 providers hidden`) | Yes |
| LOW | Spoken countdown lacks "Resets" | Reported; not checked separately |

Transcripts are retained locally in the sibling artifacts directory
(`reviews/uiux-impl-neon-r1/`).
