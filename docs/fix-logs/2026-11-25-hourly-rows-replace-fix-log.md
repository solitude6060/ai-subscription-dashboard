# Hourly Rows Replace With Their Day Fix Log (2026-11-25)

Plan: `docs/plans/2026-11-25-hourly-rows-replace-with-day.md`. Review: `docs/reviews/2026-11-25-hourly-rows-replace-review.md`. PR #74, branch `fix/cursor-hourly-replace`.

## Issue

`token_hourly` rows were only upserted while the daily rows of the same scope were replaced. Cursor renamed `helios-alpha` events to `Other`; on the live database hourly totals exceeded daily by 1.35M tokens on 2026-11-16 and 0.54M on 2026-11-18.

## Fix

| Commit | Change |
|---|---|
| `4019a788` | Plan. |
| `02e216e3` / `1ace986a` | Test, then fix: replacing a UTC-day tool's daily scope also replaces that day's hourly rows. |
| `7aa277a3` / `3b7673fe` | Round 1: Cursor only, closed days only, UTC-midnight check, boundary tests. |
| `a2ded7b7` / `9083d114` | Round 2: 10-minute grace after midnight (pinned-clock tests). |
| `9b39c298` / `69cebc2e` | Round 3: `CursorUsageCollector` marks `completeDay` when every contributing query covered the whole UTC day; storage replaces hourly rows only for those rows; clock rule and allowlist removed. |

## Review

Round 1: Grok APPROVE, Gemini APPROVE (3 LOW), Codex 2 MEDIUM + 1 LOW (Grok partial scans, cross-refresh race) — fixed. Round 2: all three raised the midnight race (Codex MEDIUM) — grace rule. Round 3: Codex MEDIUM (writer paused past the grace) — coverage rule. Round 4: Grok and Gemini APPROVE `f76d8744`; Codex MEDIUM H4-1 deferred as existing behavior (below).

## Deferred

- H4-1 (MEDIUM): two writers (WebUI queue, `status:refresh`) can commit in either order; an older batch replaces the day's daily rows and overwrites same-key hourly rows. Existing behavior on `origin/main`; the next refresh restores. Follow-up: serialize the writers or record per-day completeness.
- H4-2 (LOW): storage comment and plan wording for closed days fetched before midnight.
- H4-3 (LOW): collector tests for mixed coverage and one-bound ranges.

## Verification

- Vitest 1397 passed; Bun 656 passed with the known load-dependent ccusage timeout test (failed in the full run, passed 3 of 3 alone at load average about 7; at load average 32 on 2026-11-25 23:10 it failed 3 of 3 alone, so commit `c8699263`'s "passed 3 of 3 alone" does not hold for that run).
- Real refresh through the default worker into a fresh copy of the live database: 3 `helios-alpha` hours on 2026-11-16..24 before, 0 after; hourly equals daily for 2026-11-16..25 (`../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/hourly-pr/copy3-check.txt`).

## Deploy

- Merged `7b8c3366` through the REST API after two GitHub GraphQL errors on `gh pr merge` (owner: 「持續做完」). Backup `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/deploy-pr74/live-before-pr74.sqlite` (integrity ok). wt-live `daabd5ed` to `7b8c3366` (also PR #73, no storage change); restarted 2026-11-25 23:54:19 +0800.
- Cursor refresh: ok, 285 records, 7 s; hourly equals daily for 2026-11-14..25; `helios-alpha` hours on 2026-11-16..24 from 3 to 0; IDE and CLI token fingerprints unchanged; journal without errors.
