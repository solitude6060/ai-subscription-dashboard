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

Repairs after round 2:

```text
21ce113d docs: status:refresh exit rules and test baselines (review F2-2, F2-7)
867278da fix: PR #75 review round 2 (F2-1..F2-5)
f2fa3f4c test: PR #75 review round 2 (F2-1..F2-5, F2-8)
bbd9571d docs: record PR #75 review round 2 and triage
```

## Round 3 (remediation re-review)

- Reviewed `6ef49f4c..ee0ff789` (review records excluded). Prompt `pr75-round3/prompt.md` (SHA-256 `680fd983…a426f03f77`).

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, no findings | `pr75-round3/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` | high | APPROVE, 2 LOW | `pr75-round3/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol`, `~/.codex-family` | high | REQUEST_CHANGES, 2 MEDIUM, 2 LOW | `pr75-round3/lane3-codex-family.jsonl`, `lane3-codex-family.final.md` |

Lane 3 thread `01a2139c-edca-7a61-80c9-227eaeb1acd5`.

| ID | Finding | Source | Severity | Disposition |
|---|---|---|---|---|
| F3-1 | With `busy_timeout`, a server write waiting on an external lock blocks the server's event loop; the CLI's 2 s health probe then times out and the CLI refreshes locally, a second writer again. | Lane 3 | MEDIUM | Fix: a health probe that times out is an unknown server state; the CLI exits with an error and does not write. Without a matching WebUI server (refused connection, non-OK or unreadable health, another database) the CLI refreshes locally. `busy_timeout` stays for the server's own writes. Test first. |
| F3-2 | The plugin accepts a page with a non-object entry that the collector rejects, so the card shows an unqualified total. | Lane 3 | MEDIUM | Fix: a non-object entry is a self-contradicting answer in the plugin too. Test first. |
| F3-3 | The write-lock test does not assert that the child took the lock or exited cleanly. | Lanes 2, 3 | LOW | Fix: assert the `locked` message and exit 0; kill the child in `finally`. |
| F3-4 | The Events Note row and the plan omit the zero-event `incomplete fetch` note and the deadline exception for HTTP failures. | Lanes 2, 3 | LOW | Fix the docs and the plan. |

## Round 4 (second remediation re-review)

- Reviewed `ee0ff789..8035a8c1` (review records excluded). Prompt `pr75-round4/prompt.md` (SHA-256 `d398c22d…c47938f806`).

| Lane | Client and model | Effort | Verdict | Raw output |
|---|---|---|---|---|
| 1 | Grok Build `grok-4.7` | xhigh | APPROVE, no findings | `pr75-round4/lane1-grok.jsonl`, `lane1-grok.final.md` |
| 2 | AGY `gemini-4-neon-high` | high | APPROVE, 2 LOW | `pr75-round4/lane2-agy.jsonl`, `lane2-agy.final.md` |
| 3 | Codex `gpt-6.2-sol`, `~/.codex-family` | high | REQUEST_CHANGES, 1 MEDIUM, 2 LOW | `pr75-round4/lane3-codex-family.jsonl`, `lane3-codex-family.final.md` |

Lane 3 thread `01a213a9-4943-7d41-8f0f-1c6428df5bb8`. Triage rule from the owner (2026-11-26, 「不要太無限上綱…不是一直雞蛋挑骨頭」): a finding blocks only with a trigger reachable in real use and a real impact; otherwise it is LOW at most.

| ID | Finding | Source | Severity | Disposition |
|---|---|---|---|---|
| F4-1 | A health response whose body stalls after the headers falls back to a local refresh. | Lane 3 (MEDIUM) | LOW | Not changed: the WebUI server answers `/api/health` with `Response.json(...)` built before the response (`apps/server/src/index.ts` health handler), so headers and body are sent together; a server blocked on a write sends no headers and takes the timeout path. No real trigger. |
| F4-2 | The CLI comment, README and round 3 record state a narrower local-fallback rule than the code. | Lanes 2, 3 | LOW | Fixed after the round: comment and docs only (no code token changed). |
| F4-3 | The endpoint paragraph and the Events Note row describe zero-event notes differently. | Lane 3 | LOW | Fixed after the round (docs). |
| F4-4 | The 3 s health stub leaves 1 s of margin over the 2 s probe timeout. | Lane 2 | LOW | Deferred: the CLI exits at about 2.1 s; a flake needs a scheduler pause over 1 s in the child. |

Gate: lanes 1 and 2 APPROVE `8035a8c1`; F4-1 reclassified with the evidence above. The commit after `8035a8c1` changes a code comment and docs only.
