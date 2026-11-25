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

## Round 2 (full PR diff)

- Reviewed `7b8c3366..6ef49f4c` (review records excluded). Prompt `pr75-round2/prompt.md` (SHA-256 `62989b37…ff5408a1`). Lane 3 started after the `~/.codex-family` reset (00:39).

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, 1 LOW | `pr75-round2/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` | high | APPROVE, 2 LOW | `pr75-round2/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol`, `~/.codex-family` | high | REQUEST_CHANGES, 3 MEDIUM, 4 LOW | `pr75-round2/lane3-codex-family.jsonl`, `lane3-codex-family.final.md` |

Lane 3 thread `01a21393-2bb1-7352-bba3-a59967a4d908`.

| ID | Finding | Source | Severity | Disposition |
|---|---|---|---|---|
| F2-1 | After the handoff the CLI's `storage.init()` takes a write lock (`BEGIN IMMEDIATE` in the `last_success_at` migration check runs on every init) and can hit `SQLITE_BUSY` against a queued server write. | Lane 3 | MEDIUM | Fix: `SqliteStorage.init()` sets `PRAGMA busy_timeout = 5000`, so the server and the CLI wait for a write lock instead of failing. Test first (a child process holds the lock). |
| F2-2 | The CLI exits 0 when every provider fails, and a response without `results` reads as success. | Lane 3 | MEDIUM | Fix the malformed response: no `results` list is an error. Not changed: every provider failing exits 0, as the local branch does on `origin/main`; per-provider errors are printed. README wording clarified. |
| F2-3 | A bounded response without a total whose list contains a non-object entry counts as a short, complete page after the filter and can mark a day `completeDay`. | Lane 3 | MEDIUM | Fix: a non-object entry fails a bounded query (legacy unbounded queries keep the filter). Test first. |
| F2-4 | An empty page below a known positive total shows no Events Note. | Lane 3 | LOW | Fix: inconsistent responses (invalid body, changed total, short page, more events than the total) show `Partial sample (incomplete fetch)` also with zero events; HTTP and network failures with zero events keep showing no event lines. |
| F2-5 | An HTTP error returned after the deadline is not labeled as the time limit. | Lane 3 | LOW | Fix: the non-2xx branch checks the deadline too. |
| F2-6 | The subprocess test uses `tmpdir()`. | Lane 3 | LOW | Not changed: per-test directories created with `mkdtempSync(tmpdir())` and removed in `afterEach` are disposable scratch, the convention of the existing storage and provider tests (for example `packages/storage/test/token-hourly.test.ts`). |
| F2-7 | The plan lists the HTTP 500 test as a base lock. | Lanes 1, 2, 3 | LOW | Fix: three locks (relative reported path, another database, no server); the two `completeDay` collector tests are locks too. |
| F2-8 | No test that `/api/health` reports an absolute path for a relative `OPENUSAGE_WEBUI_DIR`. | Lane 2 | LOW | Fix: test added (fails on `7b8c3366`, passes since `7c963877`). |
