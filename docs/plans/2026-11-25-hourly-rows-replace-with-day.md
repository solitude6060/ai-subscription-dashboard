# Hourly Token Rows Replace With Their Day

Date: 2026-11-25

## Problem

`SqliteStorage.upsertUsageRecords(records, { replaceScopes: true })` deletes and rewrites every daily
`usage_records` row of each `(provider, tool, day, source)` scope in the batch, but `token_hourly` rows
are only upserted by `(provider, tool, hour, model)` (`packages/storage/src/allowance-tokens.ts`
`prepareHourlyUpsert`). An hour or model that a refresh no longer returns keeps its old value, and the
Allowance page reads the hourly rows.

Evidence (live database after PR #72, `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/hourly-keys.txt`):
Cursor now reports the events once named `helios-alpha` as `Other`, with the same token counts
(2026-11-16 00:00 1,353,903; 2026-11-18 00:00 373,804; 04:00 169,016). The daily rows show `Other`
only. `token_hourly` holds both names, so hourly totals exceed daily totals by 1.35M tokens on
2026-11-16 and 0.54M on 2026-11-18.

## Change

When a batch with `replaceScopes` replaces the daily rows of a closed UTC day (the day ended at least 10
minutes before the write, and the daily row starts at 00:00 UTC; a refresh that fetched the day before
midnight writes within the 120 s worker limit) for `Cursor Usage Event`, it also deletes that provider's
Cursor `token_hourly` rows of the same UTC day before the batch's hourly rows are written, in the
existing transaction.

Not changed: today's hourly rows (an earlier refresh can commit after a later one), Grok (a scan can skip
an unreadable transcript, so a day's batch can be partial), `ccusage` and Pi (local-day labels; Pi emits
no hourly rows), hourly rows of days the batch does not replace, batches without `replaceScopes`.
(PR #74 review round 1.)

`CursorUsageCollector` emits daily and hourly rows only from complete queries that start at 00:00 UTC, so
a replaced closed day's hourly rows come from the same complete data.

## Tests

`packages/storage/test/token-hourly.test.ts`:

- a replaced closed Cursor day loses the hours and models the batch no longer has;
- Grok hourly rows, a Cursor day's hourly rows 9 minutes after it ends (replaced at 10 minutes, pinned clock)
  and the hours around a daily row that does not start at 00:00 UTC stay;
- hourly rows of the neighbouring days (including the next day's 00:00) stay;
- hourly rows stay when the batch carries hourly rows but no daily row for that day;
- `ccusage` hourly rows stay when its daily scope is replaced.

## Docs

`docs/providers/cursor.md` (storage paragraph).

## Exit Criteria

- The stale-model test fails on `origin/main`; the round 1 tests (Grok, today, non-midnight) fail on `71fb80cf`; the 9-minute test fails on `dd82ec60`; neighbour-day, no-daily-row and ccusage tests are boundary locks that pass on every base. Full Vitest, Bun tests and builds pass.
- Triple-review APPROVE; merge; deploy; after one Cursor refresh, hourly equals daily for the closed days 2026-11-16..24.
