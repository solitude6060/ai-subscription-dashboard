# Cursor Follow-Ups Fix Log (2026-11-25)

Plan: `docs/plans/2026-11-25-cursor-followups.md`. Review: `docs/reviews/2026-11-25-cursor-followups-review.md`. PR #75, branch `fix/cursor-followups`.

## Changes

| Item | Change |
|---|---|
| H4-1 | `status:refresh` hands the refresh to a WebUI server on `127.0.0.1:${OPENUSAGE_WEBUI_PORT:-6736}` whose `/api/health` reports the same database (absolute path, symlinks resolved), before the CLI opens the database. A health timeout or a failed server request ends the command with an error; without a matching server the CLI refreshes locally. `/api/health` reports the absolute path. `SqliteStorage.init` sets `busy_timeout` 5000. |
| R1-7 / R2-5 | A Cursor events query with a requested bound that returns an event outside it, an event without a readable time, or a non-object entry stores no rows. |
| R3-2 / R3-3 | Plugin notes: a self-contradicting answer reads `incomplete fetch`, the events deadline reads `time limit`, also with zero events; HTTP or network failures before the deadline with zero events show no event lines. |
| H4-2 / H4-3, PR #70 R2-1 / R1-3 | Comment, tests and docs. |

## Review

Round 1: Grok APPROVE, Gemini 2 MEDIUM + 4 LOW (fixed), Codex no verdict (usage limit). Round 2 (full diff): Grok and Gemini APPROVE, Codex 3 MEDIUM (fixed; every provider failing still exits 0 as the local branch does). Round 3: Grok and Gemini APPROVE, Codex 2 MEDIUM (fixed). Round 4: Grok and Gemini APPROVE `8035a8c1`; Codex MEDIUM F4-1 reclassified to LOW (no real trigger) under the owner's triage rule; wording LOWs fixed in comments and docs only.

Each repair has a `test:` commit before its `fix:` commit (`git log 7b8c3366..`). F1-4's helper test was added with the fix because the helper is new.

## Deferred

- F4-4 (LOW): the slow-health test stub leaves 1 s of margin over the CLI's 2 s timeout.
- Every provider failing in a server refresh exits 0 (same as the local branch).

## Verification

- Vitest 1403 passed; Bun 710 passed with the known load-dependent ccusage timeout test failing in the full run and passing 3 of 3 alone; `bun run build` and `build:webui` passed.
- Real account through the branch: 4 event requests, 7.5 s, no Events Note, closed days 2026-11-16..24 unchanged.
