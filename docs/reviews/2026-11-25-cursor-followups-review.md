# Cursor Follow-Ups Review (2026-11-25)

PR #75, branch `fix/cursor-followups`. Plan: `docs/plans/2026-11-25-cursor-followups.md`. Artifacts: `../openusage_webui-artifacts/2026-11-25-cursor-per-day-events/review/pr75-*`.

## Round 1

- Base `7b8c3366` (`origin/main`), exact head `09553e86`. Prompt `pr75-round1/prompt.md` (SHA-256 `7f8b70f3…3576d8d`).

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, 2 LOW | `pr75-round1/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` | high | REQUEST_CHANGES, 2 MEDIUM, 4 LOW | `pr75-round1/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol`, `~/.codex-family` | high | No verdict: usage limit ("try again at 12:38 AM"); `~/.codex` is limited until 2026-11-29 | `pr75-round1/lane3-codex-family.jsonl` |

Lane 3 thread `01a21371-b6ba-7a50-9e15-e1543eb6f08e`. Lane 3 is not counted as a verdict. Round 2 reviews the full PR diff with all three lanes, lane 3 on `~/.codex-family` after its reset.

| ID | Finding | Source | Severity | Disposition |
|---|---|---|---|---|
| F1-1 | `databasePath` is compared as a raw string; a relative `OPENUSAGE_WEBUI_DIR` or a symlink gives a false match (refresh of the wrong database) or a false mismatch (second writer). | Lane 2 | MEDIUM | Fix: `/api/health` reports the absolute path; the CLI requires an absolute path and compares real paths. Tests first. |
| F1-2 | The subprocess tests' local branch runs every provider (`bunx`/`npx ccusage`, Colab, a `/proc` scan) and ignores the exit code and stderr. | Lane 2 (MEDIUM), lane 1 (LOW) | MEDIUM | Fix: the test database disables every provider; stdout and stderr are read; the exit code is asserted; a server HTTP 500 test is added. The two local-branch tests are regression locks (they pass on base). |
| F1-3 | The range check needs both bounds; an unparseable timestamp in a bounded query does not fail it. | Lanes 1, 2 | LOW | Fix: any finite bound is enforced, and an event without a parseable time fails a bounded query. |
| F1-4 | An empty `OPENUSAGE_WEBUI_PORT` gives port 0. | Lane 2 | LOW | Fix: empty means 6736; only integers 1..65535 are used. |
| F1-5 | A request that times out after the events deadline does not set the deadline flag. | Lane 2 | LOW | Fix: a failed request at or after the deadline sets it. |
| F1-6 | `storage.init()` runs before the server handoff and can hit `SQLITE_BUSY` during a server commit. | Lane 2 | LOW | Fix: the handoff runs first; storage is opened for the local branch and for printing. |

Repairs after round 1: test `11aee269` (red on `d1b6c29e`), fix `7c963877`, docs `aad76156`. F1-4's helper test was added with its fix because the helper is new.
