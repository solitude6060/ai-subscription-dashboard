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

## Round 2 (remediation re-review)

- Reviewed `71fb80cf..dd82ec60` (review records excluded). Prompt `pr74-round2/prompt.md` (SHA-256 `7aa98c3e…cf6d7b85e`).

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, 1 LOW | `pr74-round2/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` | high | APPROVE, 2 LOW | `pr74-round2/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol`, `~/.codex-family` | high | REQUEST_CHANGES, 1 MEDIUM, 2 LOW | `pr74-round2/lane3-codex-family.jsonl`, `lane3-codex-family.final.md` |

Lane 3 thread `01a21337-f6a9-7e33-8fcc-9021e237d64b`.

| ID | Finding | Source | Severity | Disposition |
|---|---|---|---|---|
| H2-1 | A refresh that fetched today before UTC midnight and writes after it counts the day as closed and replaces its hourly rows with a partial batch. | Lanes 1, 2 (LOW), lane 3 (MEDIUM) | MEDIUM | Fixed: a day counts as closed 10 minutes after it ends; the plugin worker stops a refresh at 120 s. Test first (9 and 10 minutes, pinned clock). The daily row in the same race (an earlier batch replacing a later daily total) is the existing daily behavior and is restored by the next refresh; not changed here. |
| H2-2 | The today test read the wall clock. | Lanes 2, 3 | LOW | Fixed: replaced by pinned-clock tests. |
| H2-3 | The plan's exit criterion named the wrong baseline for the remediation tests. | Lane 3 | LOW | Fixed: each test names its baseline. |

## Round 3 (second remediation re-review)

- Reviewed `dd82ec60..c8699263` (review records excluded). Prompt `pr74-round3/prompt.md` (SHA-256 `94d7b4fe…b7c4b66`).

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, no findings | `pr74-round3/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` | high | APPROVE, 2 LOW | `pr74-round3/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol`, `~/.codex-family` | high | REQUEST_CHANGES, 1 MEDIUM, 1 LOW | `pr74-round3/lane3-codex-family.jsonl`, `lane3-codex-family.final.md` |

Lane 3 thread `01a21343-075f-7173-a2c6-00628283849b`.

| ID | Finding | Source | Severity | Disposition |
|---|---|---|---|---|
| H3-1 | A writer that pauses more than 10 minutes between a pre-midnight fetch and its write can still replace a full day's hourly rows. | Lane 3 | MEDIUM | Fixed at the root, as lane 3 proposed in round 2: the collector marks daily rows whose query covered the whole UTC day (`completeDay`), and storage replaces hourly rows only for those. The clock rule and the Cursor allowlist are removed. Tests first. |
| H3-2 | Docs omit the previous day's grace period. | Lanes 2, 3 | LOW | Superseded: the docs now describe the coverage rule. |
| H3-3 | The plan's baselines named a removed today test. | Lane 2 | LOW | Fixed: baselines rewritten for the current tests. |
