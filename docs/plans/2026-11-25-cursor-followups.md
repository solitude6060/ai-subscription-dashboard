# Cursor Follow-Ups

Date: 2026-11-25

Deferred items from PR #70, PR #72 and PR #74 (owner: 「持續做完」).

## Items

| ID | Source | Issue | Change |
|---|---|---|---|
| H4-1 | PR #74 review round 4 (MEDIUM, deferred) | Two writers refresh the same database: the WebUI queue and `bun run status:refresh` (`apps/server/src/cli-status.ts`). An older batch can commit after a newer one, replace a day's daily rows and overwrite same-key hourly rows until the next refresh. | When a WebUI server answers `GET /api/health` on `127.0.0.1:${OPENUSAGE_WEBUI_PORT ?? 6736}` with the same `databasePath`, the CLI asks it to refresh (`POST /api/providers/refresh`) and prints its results instead of writing itself. Otherwise the CLI refreshes locally as before. |
| H4-2 | PR #74 round 4 (LOW) | The storage comment and the plan say a batch fetched before midnight keeps hourly rows upsert-only; only its in-progress day does. | Reword the comment and the plan. |
| H4-3 | PR #74 round 4 (LOW) | No collector test for a day fed by a covering and a partial query, or a range with one bound. | Tests. |
| R1-7 / R2-5 | PR #72 rounds 1 and 2 (LOW / MEDIUM collector part, deferred) | The collector filters events by query start only; an event after the query end, or before its start, is counted. | A query with an explicit range that returns an event outside it fails (no records), as the backfill script does. |
| R3-2 | PR #72 round 3 (LOW) | A short page below a known total is labeled `Partial sample (page cap)`. | Mark it incomplete (`Partial sample (incomplete fetch)`); `page cap` only for the page limit. |
| R3-3 | PR #72 round 3 (LOW) | When the events deadline passes before any event request, no Events Note is shown. | Show `Partial sample (time limit)` when the deadline stopped the fetch, also with zero events. HTTP failures with zero events keep showing no event lines (accounts without event access). |
| PR70 R2-1 | PR #70 round 2 (LOW) | The encrypted-access-token test case sets both fields to ciphertext. | Keep the access token encrypted and set a plain refresh token. |
| PR70 R1-3 | PR #70 round 1 (LOW remainder) | `docs/providers/cursor.md` does not say that Settings-managed Cursor accounts drop an ambient `OPENUSAGE_CURSOR_STATE_DB` (`packages/providers/src/account-detect.ts`). | One sentence. |

## Tests

- CLI: with a stub server reporting the same `databasePath`, `status:refresh` posts `/api/providers/refresh` and prints the server results; with a different `databasePath` or no server it refreshes locally.
- Collector: an event outside an explicit query range fails the query; a day fed by a covering and a partial query is not `completeDay`, in both orders; a range with only one bound is not `completeDay`.
- Plugin: a short page below a known total ends in `Partial sample (incomplete fetch)`; a deadline that passes before the first event request shows `Partial sample (time limit)`; a deadline after some events shows `Partial sample (time limit)`.
- PR #70 test case update.

## Exit Criteria

- New tests fail on `origin/main` (`7b8c3366`) for the stated reason, then pass; full Vitest, Bun tests and builds pass.
- Triple-review APPROVE; merge; deploy; a Cursor refresh and `bun run status:refresh` on the live host both succeed, the latter through the server.
