# Cursor Per-Day Usage Events

Date: 2026-11-25

## Problem

Two defects in Cursor token rows (`usage_records` tool `Cursor Usage Event`, and `token_hourly`):

1. **Partial first day.** `appendUsageEventBreakdown` (`plugins/cursor/plugin.js`) fetches events from
   `min(now - 7 days, billingCycleStart)`, a time inside a UTC day. `CursorUsageCollector.records()`
   (`packages/providers/src/providers/structured-usage.ts`) groups the events by UTC day, and the server
   stores them with `replaceScopes: true`, which deletes each stored day in the batch before inserting it.
   The first day of the window is overwritten with the events after the window start.
   `token_hourly` overwrites the boundary hour in the same way.
2. **Page cap.** The plugin fetches at most 10 pages of 200 events per refresh. When the window holds
   more events, the collector sees `events < totalUsageEventsCount` and `records()` returns no rows.

Evidence (deploy of PR #70, `../openusage_webui-artifacts/2026-11-25-cursor-encrypted-token/deploy/DEPLOY_NOTES.md`):

- The first refresh after the deploy reduced the 2026-11-16 rows from 171.0M tokens / $119.94 to
  37.35M / $40.05.
- 2026-11-10..14 rows hold 0.29M to 24.26M tokens. Each was last written about 7 days after its date.
- No Cursor token rows exist for 2026-10-27..11-08; the 2026-10-16..26 rows were last written
  2026-10-26 10:22Z.
- Per-day probe (`../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/probe-days.txt`):
  days hold 100 to 632 events. A request takes 0.5 to 1.0 s. `pageSize` 1000 returns 632 events in one
  page, and `pageSize` 2000 returns HTTP 400. Events are returned from 2026-08-16. 2026-07-20 returns 0.

## Upstream

Upstream `93e5897` (Swift, #1373) fetches each day separately with `pageSize` 1000, checks that
`totalCount` is the same on every page, and caches finished days. The cache is not ported: the WebUI
refreshes every 20 minutes (`AUTO_REFRESH_INTERVAL_MS`), and a 31-day window takes about 31 requests,
within the 120 s plugin worker limit (`PLUGIN_REFRESH_WORKER_TIMEOUT_MS`).

## Change

1. Plugin: fetch events one UTC day at a time, from 00:00 UTC of the window start day to now, newest
   day first. Each request is `[dayStart, min(dayStart + 1 day - 1 ms, now)]` with `pageSize` 1000
   (10 pages per day). A failed request marks the sample incomplete and stops the remaining days.
   Line values are unchanged; they still filter events by `sevenStart` and `cycleStart`.
2. Collector: track each query (request `startDate` and `endDate`) separately: its own events, total,
   completeness and failure. A query whose total changes between pages is incomplete. Without a total, a
   page shorter than the request `pageSize` (default 200) ends the query. `records()` uses only complete
   queries, and from each query only days and hours that start at or after the query start.
3. Host: pass the request body to `CursorUsageCollector.capture`.

Not changed: storage, the scope delete, line labels, other endpoints.

Docs: `docs/providers/cursor.md` (events request description).

## Tests

- Plugin: event requests are aligned UTC days with `pageSize` 1000, newest first; a failed day ends in
  `Partial sample (incomplete fetch)` and no further day requests. Existing event tests get a mock that
  returns only the fixture events inside each request range; their expected line values stay unchanged.
- Collector: a query that starts inside a day emits no record for that day or for the hours before the
  start; completeness is tracked per query; a failed query does not drop another complete query; a query
  whose total changes between pages emits nothing; without a total, a 500-event page of a
  `pageSize` 1000 query is complete.
- Host wiring: the provider passes the request body, so a refresh through `OpenUsagePluginProvider`
  emits no record for a partial leading day.

## Data Repair

After deploy and owner approval (2026-11-25, "都幫我完成"):

- The next refresh rewrites 2026-11-16 from 00:00 UTC.
- A one-off script (`../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/backfill.ts`) fetches
  2026-08-16..2026-11-15 one day at a time through `CursorUsageCollector` and stores the rows with
  `replaceScopes: true`. A day is written only when its fetched token total is at least the stored total.
- Order: dry run on a read-only handle (per day: stored and fetched tokens and cost); apply on a copy of
  the database and diff it; after the deploy, back up and apply on the live database from the deployed
  revision. Token rows before 2026-09-17 have no cost; the backfill fills it in. A failed transaction
  (no `busy_timeout`) is rerun.

## Exit Criteria

- New tests fail on `origin/main` for the stated reason, then pass. Full Vitest, Bun tests and
  `bun run build:webui` pass.
- A real-account run through the branch code with an isolated data dir completes within the worker limit
  and returns token rows for every day of the window.
- For a closed range (2026-11-16..23), the sum of per-day `totalUsageEventsCount` equals the total of one
  request over the range.
- Triple-review APPROVE; merge; deploy; 2026-11-16 restored to the full day; backfill applied and
  verified against the dry run.
