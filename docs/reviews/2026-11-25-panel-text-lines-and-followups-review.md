# Triple review: macOS panel text lines and review follow-ups

Target: branch `feat/panel-text-lines-and-followups`. Plan:
`docs/plans/2026-11-25-panel-text-lines-and-followups.md`. Fix log:
`docs/fix-logs/2026-11-25-panel-text-lines-and-followups-fix-log.md`.

Lanes (orchestrator: Claude Code): 1 Grok Build `grok-4.7` xhigh; 2 AGY `gemini-4-neon-high` high
(no `bwrap` on macOS; `git status` checked after the run); 3 Codex `gpt-6.2-sol` high, read-only
sandbox.

## Round 1 — `main..cb03c76`

| Lane | Verdict |
| --- | --- |
| 1 Grok | APPROVE, 2 LOW |
| 2 Neon | REQUEST_CHANGES, 1 HIGH, 1 MEDIUM, 1 LOW |
| 3 Sol | No review: the process waited on standard input and produced no output. Rerun in round 2. |

| ID | Lanes | Severity | Finding | Verified | Decision |
| --- | --- | --- | --- | --- | --- |
| P1 | Neon | HIGH | `listDescendantPids` parses the output of a `ps` process that was stopped at the deadline or failed (`ccusage.ts`). A record cut at the end can name another process id, which cleanup then signals. | Confirmed: the exit status is not read. | Repair: an empty listing unless `ps` exits with code 0. |
| P2 | Grok, Neon | LOW / MEDIUM | Settings describes an account that has text values and no quota as "No data" and sorts it with the empty accounts (`ProviderVisibilitySettings.swift:35`, `:76-83`). | Confirmed. | Repair: sort by quota or detail; subtitle states the number of values. |
| P3 | Grok, Neon | LOW | The `cli-status` time assertion fails under a locale that prints `02:00:00`; no case for a status whose only refresh failed. | Confirmed by reading; not reproduced. | Repair: accept an optional leading zero, assert the failure time is absent, add the only-failed case. |

Transcripts: `openusage_webui-artifacts/reviews/followups-triple-r1/`.

## Round 2 — `main..1017bf2`

| Lane | Verdict |
| --- | --- |
| 1 Grok | APPROVE, no findings |
| 2 Neon | APPROVE, no findings |
| 3 Sol | REQUEST_CHANGES, 2 MEDIUM, 2 LOW |

| ID | Lanes | Severity | Finding | Verified | Decision |
| --- | --- | --- | --- | --- | --- |
| P4 | Sol | MEDIUM | After the listing process exits with code 0, the read of its output has no deadline; a process that inherited the pipe keeps cleanup waiting (`ccusage.ts:228`). | Confirmed by reading. `ps` starts no such process; a wrapper could. | Repair: one deadline over exit and read. |
| P5 | Sol | MEDIUM | `listLatestUsageSnapshots()` excludes `raw.lines` rows whose tool is not `OpenUsage Plugin Snapshot`, and can pick a newer quota-only row for a provider; `cli-status` printed such rows before (`cli-status.ts:117`). | The query conditions are as described. No writer in `packages/providers/src` emits `raw.lines` under another tool name (lanes 1 and 2 report the same), and the one quota-only writer (MiniMax) emits no `raw.lines` rows. | No code change. `/api/usage/latest-snapshots` uses this query, so `cli-status` now selects the rows the dashboard and the macOS app show. A second selection rule for the CLI would let the two differ. |
| P6 | Sol | LOW | The time assertion still assumes ASCII digits and colons. | Confirmed by reading. | Repair: the expected text is produced by a process with the same environment. |
| P7 | Sol | LOW | The plan says Bun exposes no cgroup interface; Bun 1.4 has `Bun.spawn({ cgroup })` on Linux, which joins an existing cgroup. | Not checked against the Bun source; taken from the cited release notes. | Repair the plan wording. C7 stays unchanged: creating the cgroup needs host permissions that the service does not have by default. |

Transcripts: `openusage_webui-artifacts/reviews/followups-triple-r2/`.

## Round 3 — remediation re-review, `1017bf2..846c27d`

| Lane | Verdict |
| --- | --- |
| 1 Grok | APPROVE, no findings |
| 2 Neon | APPROVE, 1 LOW |
| 3 Sol | REQUEST_CHANGES, 1 MEDIUM |

| ID | Lanes | Severity | Finding | Verified | Decision |
| --- | --- | --- | --- | --- | --- |
| P8 | Sol, Neon | MEDIUM / LOW | When the listing is discarded, the read of its output stays active until the pipe closes (`ccusage.ts:230`). | Confirmed by reading. | Repair: abort the read, as `runCommand` does. |

P5: lanes 1 and 2 confirmed the stated reason; lane 3 did not reopen it.
Transcripts: `openusage_webui-artifacts/reviews/followups-triple-r3/`.

## Round 4 — remediation re-review, `846c27d..36f3e5d`

| Lane | Verdict |
| --- | --- |
| 1 Grok | APPROVE, no findings |
| 2 Neon | APPROVE, no findings |
| 3 Sol | APPROVE, no findings |

Lane 3's first attempt stopped at the Codex usage limit without a verdict; the rerun after the
limit reset returned the verdict above. Reviewed code: `36f3e5d`. Later commits change records only.
Transcripts: `openusage_webui-artifacts/reviews/followups-triple-r4/`.
