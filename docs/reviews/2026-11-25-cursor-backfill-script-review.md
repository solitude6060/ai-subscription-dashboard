# Cursor Backfill Script Review (2026-11-25)

Target: `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/backfill.ts`, a one-off script that refetches Cursor events for 2026-08-16..2026-11-15 and rewrites those days in the live database. It is not merged. It was split from the PR #72 gate after round 2 (`docs/reviews/2026-11-25-cursor-per-day-events-review.md`, findings R1-3..R1-6 and R2-4..R2-7 for earlier versions).

## Round 1

- Script SHA-256 `caea9cd4…e41c4f`. Prompt `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/review/script-round1/prompt.md` (SHA-256 `4d4e801e…976078`).

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, no findings | `script-round1/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` (bwrap read-only, SSH variables unset) | high | APPROVE, 2 LOW | `script-round1/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol`, home `~/.codex-family` (read-only sandbox) | high | REQUEST_CHANGES, 3 MEDIUM, 1 LOW | `script-round1/lane3-codex-family.jsonl`, `lane3-codex-family.final.md` |

Lane 3 thread `01a2130d-f6f4-7b33-9a54-6931a25b7f9a`.

| ID | Finding | Source | Severity | Disposition |
|---|---|---|---|---|
| S1-1 | Pages that overlap can pass the count check. | Lane 3 | MEDIUM | Fixed: an event repeated across pages fails the day. |
| S1-2 | A malformed `totalUsageEventsCount` is treated as absent. | Lane 3 | MEDIUM | Fixed: a present total must be a nonnegative safe integer. |
| S1-3 | A body-read failure on HTTP 401/403 bypasses the stop. | Lane 3 | MEDIUM | Fixed: the status is checked before the body is read. |
| S1-4 | `COMMIT` is outside the protected block. | Lane 3 | LOW | Fixed: `COMMIT` inside `try`; `finally` rolls back if open and closes the handle. |
| S1-5 | The read handle has no busy timeout. | Lane 2 | LOW | Fixed: `PRAGMA busy_timeout = 10000`. |
| S1-6 | `--from` and `--to` are not validated. | Lane 2 | LOW | Fixed: `YYYY-MM-DD`, finite, `from <= to`. |

Rehearsal after the repairs: a fresh copy of the live database (`backfill-copy5/`) wrote 90 days; `usage_records` (316 rows) and `token_hourly` (1234 rows) in range equal the earlier transaction path (`backfill-copy3/`) and the `SqliteStorage` path (`backfill-copy2/`). A stored total changed after its read (`backfill-copy6/`) gave exit 3 with only the injected row changed.

## Round 2

- Script SHA-256 `753ae08a…0364c204`. Prompt `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/review/script-round2/prompt.md` (SHA-256 `a246d18d…a0543014`).

| Lane | Client and model | Effort | Verdict |
|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, no findings |
| 2 | AGY `gemini-4-neon-high` | high | APPROVE, 2 LOW |
| 3 | Codex `gpt-6.2-sol`, `~/.codex-family` | high | REQUEST_CHANGES, 2 MEDIUM, 2 LOW |

Lane 3 thread `01a2131e-4789-7bf3-ad45-ef3467bc8257`.

| ID | Finding | Source | Severity | Disposition |
|---|---|---|---|---|
| S2-1 | Reordered event fields bypass the repeated-event check. | Lane 3 | MEDIUM | Fixed: key-order independent serialization. |
| S2-2 | A complete fetch without cost fields could erase stored costs. | Lane 3 | MEDIUM | Fixed: a day is skipped when its fetched cost is below the stored daily or hourly cost; the in-transaction re-read compares costs. On the current data only 2026-10-19 has a lower fetched cost and it is already skipped. |
| S2-3 | A rollback error can mask the original error and skip close. | Lanes 2, 3 | LOW | Fixed: rollback only when `db.inTransaction`; close in a nested `finally`. |
| S2-4 | A database read error can preempt the 401/403 exit. | Lane 3 | LOW | Fixed: the auth stop comes right after the fetch. |
| S2-5 | Impossible calendar dates (`2026-02-30`). | Lane 2 | LOW | Fixed: the parsed date must format back to the input. |

Rehearsal: `backfill-copy7/` (fresh copy) wrote 90 days; in-range rows identical to `backfill-copy5/`; `backfill-copy8/` (cost changed after its read) gave exit 3.

## Round 3

- Script SHA-256 `e62cf696…773ace3e`. Prompt `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/review/script-round3/prompt.md` (SHA-256 `5505641f…bf6c47`).

| Lane | Client and model | Effort | Verdict |
|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, no findings |
| 2 | AGY `gemini-4-neon-high` | high | APPROVE, no findings |
| 3 | Codex `gpt-6.2-sol`, `~/.codex-family` | high | REQUEST_CHANGES, 1 MEDIUM, 1 LOW |

Lane 3 thread `01a2132f-31d1-7013-897a-1a74ede91007`.

| ID | Finding | Source | Severity | Disposition |
|---|---|---|---|---|
| S3-1 | One hourly bucket is lowered although its day rises: 2026-10-26 09:00 `grok-bot-default` 1,453,514 to 1,347,455 tokens ($1.1177 to $1.0602). | Lane 3 | MEDIUM | Closed with evidence: the API returns 18 events for that hour summing to 1,347,455, one of them exactly 106,059 tokens; the stored 1,453,514 equals 1,347,455 + 106,059, so the stored value counted that event twice (`bucket-1026-probe.txt`). In the whole rehearsal this is the only lowered bucket of 323 hourly buckets, and no daily row is lowered (`bucket-decreases.txt`). Rule applied: a day may not drop; buckets inside a complete day follow the fetch. |
| S3-2 | A `ROLLBACK` exception could replace an error already propagating. | Lane 3 | LOW | Deferred: the rollback runs only while `db.inTransaction` is true, so the SQLite auto-rollback case is excluded; changing the script would unbind the three approvals and the rehearsals. |

## Live Run

- 2026-11-25 23:07 +0800, after a refresh round (23:02), script SHA-256 `e62cf696…`, `REPO` = `openusage_webui-wt-live` at `daabd5ed`.
- Backup `backfill-live/live-before-backfill.sqlite` (integrity ok).
- Exit 0: 90 days written, 2 skipped (2026-08-17 the API returns `{}` while 516.0M tokens without cost are stored, last written 2026-08-17 17:33 UTC; 2026-10-19 fetched 33,071 tokens below stored), 0 failed.
- Verification (`backfill-live/verify.txt`): integrity ok; in-range `usage_records` (316 rows) and `token_hourly` (1234 rows) identical to the rehearsal `backfill-copy7/copy.sqlite`; Cursor token rows before 2026-08-16 unchanged; 2026-08-16..11-15 daily tokens 1456.90M to 3137.77M, cost $569.86 to $2872.54 (the cost rise includes days before 2026-09-17 that had no stored cost); service journal without errors after the run.
