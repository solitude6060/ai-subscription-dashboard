# Cursor Encrypted App Token Review (2026-11-25)

PR #70, branch `fix/cursor-encrypted-app-token`. Plan: `docs/plans/2026-11-25-cursor-encrypted-app-token.md`.

## Target

- Base: `8b08db8a` (`origin/main`).
- Exact head: `a4bd697b`.
- Prompt: `../openusage_webui-artifacts/2026-11-25-cursor-encrypted-token/review/round1/prompt.md` (SHA-256 `470486a1…bddb3`).

## Round 1

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, no findings | `round1/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` (bwrap read-only, SSH variables unset) | high | APPROVE, 1 LOW | `round1/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol` (read-only sandbox) | high | REQUEST_CHANGES, 1 MEDIUM, 2 LOW | `round1/lane3-codex.jsonl`, `lane3-codex.final.md` |

The orchestrator is Claude Code (Anthropic). The three lanes are xAI, Google and OpenAI, so no lane shares the orchestrator's family.

The first lane 1 launch did not start: the shell did not split a command stored in a variable (exit 127, `lane1-grok.launch-error-zsh-wordsplit.err`). The lane was launched again with explicit arguments; this is not counted as a lane retry.

Lane 2 stream `init` event reports model `gemini-4-neon-high`; result status `SUCCESS`, 193.6 s. Lane 3 thread `01a20ec1-5c1f-7523-bde1-4a62b2640a11`. The checkout stayed at `a4bd697b` with no tracked changes during the round.

## Findings And Triage

| ID | Finding | Source | Severity | Verified evidence | Disposition |
|---|---|---|---|---|---|
| R1-1 | `readCliAuth` accepts a file without a usable access token: a refresh-only file selects source `cli` (which never refreshes) and hides the encrypted-sign-in message; an encrypted access value would be sent as the bearer token. | Lane 3 (MEDIUM), lane 2 (LOW) | MEDIUM | `plugins/cursor/plugin.js:133-139` returns a source when either field is non-empty and does not check `cursor-safe-storage:`; `refreshToken()` returns null for `cli` at line 289. | Fix in this PR: require a non-empty, non-encrypted access token; the CLI source carries no refresh token. Regression tests first. |
| R1-2 | Pinned-home test does not observe file access and covers one pinning variable. | Lane 3 | LOW | `plugins/cursor/plugin.test.js` pinned test asserts only the error and no HTTP. | Fix in this PR (test only): assert the CLI file is never checked or read, for both `OPENUSAGE_CURSOR_CONFIG_DIR` and `OPENUSAGE_CURSOR_STATE_DB`. |
| R1-3 | Docs say Detect looks for a signed-in `state.vscdb`; it checks file presence. Docs also leave open that Settings accounts drop an ambient `OPENUSAGE_CURSOR_STATE_DB`. | Lane 3 | LOW | `packages/providers/src/account-detect.ts:160-166` (`existsSync`), `:319-323` (`delete providerEnv.OPENUSAGE_CURSOR_STATE_DB`). Both sentences predate this PR. | Fix the presence wording in this PR (one phrase, relevant now that a present database can be encrypted). Record the `STATE_DB` wording as a follow-up. |
