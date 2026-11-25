# Hourly Rows Replace With Their Day Review (2026-11-25)

PR #74, branch `fix/cursor-hourly-replace`. Plan: `docs/plans/2026-11-25-hourly-rows-replace-with-day.md`. Artifacts: `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/review/pr74-*`.

## Round 1

- Base `daabd5ed` (`origin/main`), exact head `71fb80cf`. Prompt `pr74-round1/prompt.md` (SHA-256 `ec892f5b…87f00b2`).

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, no findings | `pr74-round1/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` (bwrap read-only, SSH variables unset) | high | APPROVE, 3 LOW | `pr74-round1/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol`, home `~/.codex-family` (read-only sandbox) | high | REQUEST_CHANGES, 2 MEDIUM, 1 LOW | `pr74-round1/lane3-codex-family.jsonl`, `lane3-codex-family.final.md` |

The orchestrator is Claude Code (Anthropic); the lanes are xAI, Google and OpenAI. Lane 3 used `~/.codex-family` (`~/.codex` usage limit until 2026-11-29 03:47). Lane 3 thread `01a2132c-be44-7742-9fae-c973b2415126`.

| ID | Finding | Source | Severity | Verified evidence | Disposition |
|---|---|---|---|---|---|
| H1-1 | A partial Grok scan (an unreadable transcript is skipped) would delete valid hours of that day. | Lane 3 | MEDIUM | `grok-session-usage.ts` skips unreadable files; daily and hourly come from the remaining entries. | Fixed: only `Cursor Usage Event` replaces hourly rows. |
| H1-2 | An earlier Cursor refresh that commits after a later one would delete hours the later refresh saved. | Lane 3 | MEDIUM | Today's range ends at the request time; `status:refresh` writes outside the WebUI queue. | Fixed: only closed days replace hourly rows; today's rows stay upsert-only. A closed day returns the same events to both refreshes. |
| H1-3 | A daily row that does not start at 00:00 UTC shifts the delete into the next day. | Lane 3, lane 2 | LOW | Delete range was `[startedAt, startedAt + 24 h)`. | Fixed: the parsed start must be a UTC midnight. |
| H1-4 | Pi labels local days but was in the replaced set. | Lane 2 | LOW | `allowance-tokens.ts` groups Pi with ccusage as a local-day tool. | Fixed by the Cursor-only allowlist. |
| H1-5 | Tests did not cover a stale non-00:00 hour or the next day's 00:00 hour. | Lane 2 | LOW | `token-hourly.test.ts`. | Fixed: both added. |
