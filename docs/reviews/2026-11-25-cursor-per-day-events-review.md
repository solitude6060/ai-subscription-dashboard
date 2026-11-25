# Cursor Per-Day Usage Events Review (2026-11-25)

PR #72, branch `fix/cursor-per-day-events`. Plan: `docs/plans/2026-11-25-cursor-per-day-events.md`.

## Target

- Base: `08f4203e` (`origin/main`).
- Exact head: `32e06c2b`.
- Also reviewed (not merged): `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/backfill.ts` and its dry-run output.
- Prompt: `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/review/round1/prompt.md` (SHA-256 `15dd6b1d…179598`).

## Round 1

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, 3 LOW | `round1/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` (bwrap read-only, SSH variables unset) | high | APPROVE, 2 LOW | `round1/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol`, home `~/.codex-family` (read-only sandbox) | high | REQUEST_CHANGES, 5 MEDIUM, 2 LOW | `round1/lane3-codex-family.jsonl`, `lane3-codex-family.final.md` |

The orchestrator is Claude Code (Anthropic); the lanes are xAI, Google and OpenAI. Lane 3 used `~/.codex-family` because `~/.codex` returned a usage limit earlier the same day (PR #70 round 2, resets 2026-11-29 03:47). Lane 2 `init` reports `gemini-4-neon-high`, result `SUCCESS`. Lane 3 thread `01a212dc-d3f6-7e91-9de7-954a8296cd8f`. The checkout stayed at `32e06c2b` with no tracked changes.

## Findings And Triage

| ID | Finding | Source | Severity | Verified evidence | Disposition |
|---|---|---|---|---|---|
| R1-1 | Per-day requests have no time limit; a 31-day cycle needs about 32 sequential requests (16 to 32 s at the measured 0.5 to 1.0 s) and the Tauri desktop host stops the whole probe at 30 s. | Lane 3 | MEDIUM | `src-tauri/src/plugin_engine/runtime.rs:8` `PROBE_TIMEOUT_SECS: u64 = 30`; the plugin is shared with the desktop app; `plugins/cursor/plugin.js` loop issues one request per day. | Fix: today alone, closed days in 7-day ranges that start at 00:00 UTC (stable paging, about 5 to 12 requests per refresh), plus a 15 s events deadline that marks the sample incomplete. Tests first. |
| R1-2 | Plugin and collector disagree on completeness: a 200 response with invalid JSON or no `usageEventsDisplay` counts as an empty page in the plugin; the plugin ignores a total that changes between pages; both accept more events than the total. | Lane 3 | MEDIUM | `fetchFilteredUsageEvents` sets `batch = []` for invalid bodies and breaks without a flag; no total comparison; `all.length >= total` and collector `events.length >= expectedCount`. | Fix: invalid body, a changed total and more events than the total mark the plugin sample incomplete; the collector requires `events.length === expectedCount` and fails a query with more. Tests first. The sub-claim that a failed newest day shows no Events Note is existing behavior covered by `keeps the main Cursor card when usage events are unavailable`; no change. |
| R1-3 | Backfill guard is read before the API fetch and written in a later transaction. | Lane 3 | MEDIUM | `backfill.ts` reads stored totals per day on a read-only handle, writes after all fetches. | Fix in the script: re-read stored totals immediately before the write and stop if any accepted day changed. The only other writer of these rows is the server refresh, whose window starts at 2026-11-16 00:00 UTC, disjoint from 2026-08-16..11-15. |
| R1-4 | Backfill replaces daily rows but only upserts hourly rows, so stale hours or models could remain. | Lane 3 | MEDIUM | `token_hourly` upsert without delete (`allowance-tokens.ts`). Copy rehearsal: 92 days, daily equals hourly for every accepted day (`backfill-copy/verify.txt`). | Fix in the script: after the write, check daily equals hourly for every accepted day and exit non-zero on a mismatch. |
| R1-5 | Backfill exits 0 when days fail (HTTP, page limit) and labels a rejected query as `no fetched tokens`. | Lane 3, lane 1 (LOW), lane 2 (LOW) | MEDIUM | `fetchDay` returns on a short page without comparing to the total; failures only become `skip (...)` rows. | Fix in the script: label incomplete queries, list failed days, stop on HTTP 401/403, exit non-zero when any day failed. |
| R1-6 | Backfill `fetch` and `JSON.parse` have no `try/catch`; one network error aborts the run. | Lane 2 | LOW | `backfill.ts` `fetchDay`. | Fix in the script: catch per day and record the day as failed. |
| R1-7 | Overlapping queries would double count events in the collector. | Lane 3 | LOW | No caller sends overlapping ranges (plugin ranges are disjoint; backfill uses one collector per day). | Deferred; recorded in the fix log. |
| R1-8 | Pagination tests do not assert that the fetch stops after the page cap, and no test covers `now` exactly at 00:00 UTC. | Lane 3 | LOW | `plugins/cursor/plugin.test.js` page-cap and mid-fetch tests. | Fix: assert the request count after the cap; add a midnight test. |
| R1-9 | No collector test pins a query start exactly at 00:00 UTC (`>=` against `>`). | Lane 1 | LOW | `cursor-usage-collector.test.ts` uses 07:30. | Fix: add the test. |
| R1-10 | `docs/providers/cursor.md` request example still shows a 7-day range and `pageSize` 100. | Lane 1 | LOW | Example at the `get-filtered-usage-events` request body. | Fix the example. |
