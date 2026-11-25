# Cursor Per-Day Usage Events Fix Log (2026-11-25)

Plan: `docs/plans/2026-11-25-cursor-per-day-events.md`. Review: `docs/reviews/2026-11-25-cursor-per-day-events-review.md`. PR #72, branch `fix/cursor-per-day-events`. Artifacts: `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/`.

## Issue

- The event window started inside a UTC day, and the daily scope replace overwrote that day with the events after the window start. The first refresh after PR #70 reduced 2026-11-16 from 171.0M tokens / $119.94 to 37.35M / $40.05.
- Above 2000 events (10 pages of 200) the collector stored no token rows. No Cursor token rows exist for 2026-10-27..11-08.

## Fix

| Commit | Change |
|---|---|
| `9fb0117a` | Plan. |
| `8c3b1563` | Tests: per-day requests, per-query completeness, leading partial day, host passes the request body. Red on `9fb0117a`. |
| `5f1ab4f5` | Per-UTC-day fetch with `pageSize` 1000; collector tracks each request range; host passes the request body. |
| `32e06c2b` | Provider docs. |

## Review Round 1 Repairs

| ID | Severity | Repro | Fix | Tests | Files |
|---|---|---|---|---|---|
| R1-1 | MEDIUM | A 31-day cycle needs about 32 sequential day requests; the desktop host stops the probe at 30 s. | `cfbc391a`: today, then closed days in 7-day ranges from 00:00 UTC, newest first; 15 s events deadline; request timeout capped to the time left. | `e0ae3a03`: range requests, `now` at 00:00 UTC, deadline with capped timeouts. | `plugins/cursor/plugin.js`, `plugins/cursor/plugin.test.js` |
| R1-2 | MEDIUM | Invalid body counted as an empty page; changed total and more events than the total not flagged. | `cfbc391a`: these mark the sample incomplete; the collector fails a query with more events than its total. `c977d331`: a body with neither a list nor a positive total is an empty range (see below). | `e0ae3a03`, `51fcee8a`. | `plugins/cursor/plugin.js`, `packages/providers/src/providers/structured-usage.ts`, tests |
| R1-3 | MEDIUM | Backfill guard read before the API fetch. | Script: stored totals are read again just before the write; any change stops with exit 3 and writes nothing. | Copy rehearsal. | `backfill.ts` (not merged) |
| R1-4 | MEDIUM | Stale hourly rows could remain after a daily replace. | Script: after the write, daily and hourly totals must equal the fetch on every written day, otherwise exit 4. | Copy rehearsal: check passed on 90 days. | `backfill.ts` |
| R1-5 | MEDIUM | Failed days exit 0 and a rejected query reads as no tokens. | Script: failed and rejected days are listed, exit 2; HTTP 401/403 stops with exit 5 and writes nothing. | Dry run reported a transient HTTP 503 on 2026-10-01 as failed (exit 2). | `backfill.ts` |
| R1-6 | LOW | One network error aborts the run. | Script: request and JSON errors are caught per day. | — | `backfill.ts` |
| R1-8 | LOW | Page-cap test does not assert the fetch stops. | Test asserts 10 requests. | `e0ae3a03` (passes on base). | `plugins/cursor/plugin.test.js` |
| R1-9 | LOW | No test for a query start at 00:00 UTC. | Test added. | `e0ae3a03` (passes on base). | `packages/providers/test/cursor-usage-collector.test.ts` |
| R1-10 | LOW | Docs request example showed a 7-day range and `pageSize` 100. | `e58ece87`. | — | `docs/providers/cursor.md` |

### Found during the repair

The API answers a range without events with HTTP 200 and `{}` (2026-07-20, 2026-08-17, a future day, a zero-length range; `empty-range-check.txt`). The R1-2 change in `cfbc391a` treated that body as invalid, so a today range without events would stop all older ranges. `51fcee8a` (test, red on `e58ece87`) and `c977d331` (fix) read it as an empty range. The backfill script reads it the same way; 2026-08-17 is now `skip (no token events)`.

## Deferred

- R1-7 (LOW): the collector would double count events if two queries overlapped. No caller sends overlapping ranges.
- Desktop limit: with 600+ events per day (2026-10 levels) the 15 s deadline can end the fetch before the oldest ranges; those ranges are then missing from the lines, and their stored rows keep the last complete values.

## Verification

- Vitest 1392 passed; Bun 646 passed, 0 failed; `bun run build` and `build:webui` passed (`*-r1fix2.log`).
- Real account through the branch (`e2e-ranges-r1fix2.txt`): 4 event requests (0.6 to 1.6 s each), refresh 6.9 s; daily equals hourly for 2026-11-16..25; 2026-11-16 = 171.00M tokens / $119.94.
- Paging: one closed 7-day range (2026-11-16..22) returned 1000 + 277 = 1277 events, the same total on both pages, no repeated event, per-day sums equal to the per-day fetch (`range-paging-check.txt`). Per-day totals for 2026-11-16..23 sum to the single-range total (1553; `day-split-check.txt`).
- Redaction audit (`AGENTS.md`): the plugin sends the same request fields (`startDate`, `endDate`, `page`, `pageSize`) and reads the same response fields (`usageEventsDisplay`, `totalUsageEventsCount`); no `host_api.rs` change.
- Backfill rehearsal on a copy of the live database (`backfill-copy2/`): 90 days written, 0 failed; 92 days checked against the plan with 0 mismatches; rows outside the range and other providers unchanged; 2026-08-16..11-15 token rows 1456.90M to 3137.77M tokens, cost $569.86 to $2872.54. Skipped: 2026-08-17 (API `{}`, stored 516.0M from an earlier import), 2026-10-19 (API 33,071 tokens below stored).
