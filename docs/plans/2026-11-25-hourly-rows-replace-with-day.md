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

`CursorUsageCollector` marks a daily row `completeDay` when every query that contributes to it covered the
whole UTC day (`startDate` and `endDate` given, `endDate >= day start + 24 h - 1 ms`). When a batch with
`replaceScopes` replaces such a daily row and the row starts at 00:00 UTC, storage also deletes that
provider and tool's `token_hourly` rows of the same UTC day before the batch's hourly rows are written,
in the existing transaction. `completeDay` is not stored.

Not changed: rows without `completeDay`, which include today's Cursor range (its query ends at the request
time), a batch fetched before midnight and written later, Grok (a scan can skip an unreadable transcript),
`ccusage` and Pi (local-day labels; Pi emits no hourly rows); hourly rows of days the batch does not
replace; batches without `replaceScopes`. (PR #74 review rounds 1 to 3: round 1 limited the rule to closed
Cursor days, round 2 added a 10-minute grace after midnight, round 3 replaced both clock rules by the
query coverage.)

## Tests

`packages/providers/test/cursor-usage-collector.test.ts`: a query covering whole UTC days marks them
`completeDay`; today's range and a query without an explicit range do not.

`packages/storage/test/token-hourly.test.ts`:

- a replaced complete Cursor day loses the hours and models the batch no longer has;
- a Cursor daily row without `completeDay` keeps the day's hourly rows even when written two days later;
  with `completeDay` it replaces them (pinned clock);
- Grok hourly rows and the hours around a daily row that does not start at 00:00 UTC stay;
- hourly rows of the neighbouring days (including the next day's 00:00) stay;
- hourly rows stay when the batch carries hourly rows but no daily row for that day;
- `ccusage` hourly rows stay when its daily scope is replaced.

## Docs

`docs/providers/cursor.md` (storage paragraph).

## Exit Criteria

- Baselines: the stale-model test fails on `origin/main`; the Grok and non-midnight tests fail on `71fb80cf`;
  the no-`completeDay` test and the collector `completeDay` test fail on `c8699263`; the neighbour-day,
  no-daily-row and `ccusage` tests are boundary locks that pass on every base. Full Vitest, Bun tests and
  builds pass.
- Triple-review APPROVE; merge; deploy; after one Cursor refresh, hourly equals daily for the closed days
  2026-11-16..24.
