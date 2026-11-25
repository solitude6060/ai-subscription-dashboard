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

When a batch with `replaceScopes` replaces the daily rows of a UTC day for a provider and a tool whose
hourly rows use UTC days (`Cursor Usage Event`, `Grok Session`, `Pi Session`), it also deletes that
provider and tool's `token_hourly` rows for the same UTC day before the batch's hourly rows are
written. Both deletes and the inserts stay in the existing transaction.

Not changed: `ccusage` (its hourly rows pair with local days), hourly rows of days the batch does not
replace, batches without `replaceScopes`.

Both Cursor and Grok build their daily and hourly rows from the same events (`CursorUsageCollector`,
`aggregateGrokEntries`), so a replaced day's hourly rows come from the same complete data. Pi emits no
hourly rows.

## Tests

`packages/storage/test/token-hourly.test.ts`:

- a replaced Cursor day loses an hourly model the batch no longer has; Grok the same;
- hourly rows of a day the batch does not replace stay;
- hourly rows stay when the batch carries hourly rows but no daily row for that day;
- `ccusage` hourly rows stay when its daily scope is replaced.

## Docs

`docs/providers/cursor.md` (storage paragraph).

## Exit Criteria

- New tests fail on `origin/main` for the stated reason, then pass; full Vitest, Bun tests and builds pass.
- Triple-review APPROVE; merge; deploy; after one Cursor refresh, hourly equals daily for 2026-11-16..25.
