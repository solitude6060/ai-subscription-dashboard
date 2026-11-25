# Triple review of the Google Colab provider

Date: 2026-11-25. Target: `git diff 5e54e99..6112248` on `feat/colab-compute-units`
(head `611224867acdbf6ce9605f4c3830182f80fe181b`). Implemented by Codex `gpt-6.2-sol` (high)
from `docs/plans/2026-11-25-colab-compute-units.md`; commits `7f58085` and `6112248` by the
orchestrator (Claude Code, Fable 5.2). The reviewers ran in separate read-only sessions.

The implementer also ran its own review round before returning (Grok Build, Claude Opus 5.5,
a second Codex session) and repaired one finding (`89de2d8`..`005bd9b`). That round is not
part of this gate.

| Lane | Client and model | Effort | Verdict |
| --- | --- | --- | --- |
| 1 | Grok Build `grok-4.7` | xhigh | REQUEST_CHANGES |
| 2 | AGY `gemini-4-neon-high` (without `bwrap`, which macOS lacks; `git status` clean afterwards) | high | REQUEST_CHANGES |
| 3 | Codex `gpt-6.2-sol`, fresh session; same model as the implementer | high | REQUEST_CHANGES |

Transcripts are retained locally in the sibling artifacts directory (`reviews/colab-triple-r1/`).

## Findings and triage

| ID | Source | Severity | Finding | Disposition |
| --- | --- | --- | --- | --- |
| C1 | Grok, Neon, Sol | MEDIUM | The lingering-output test (`colab-provider.test.ts:105-130`) needs two Bun processes to start within a 300 ms deadline, mocks `process.kill` for the whole call and leaves a sleeping child behind. | Repair: longer deadline, child reaped by recorded pid, no process-wide mock. Add a test that a still-running command is stopped at the deadline. |
| C2 | Neon | MEDIUM | `ColabProvider` resolves the executable with its injected `env` but `runCommand` spawns with the host environment (`colab.ts:39`, `ccusage.ts:141-145`). | Repair: the runner accepts an environment and the provider passes its own. |
| C3 | Neon | MEDIUM | An invalid `COLAB_CLI_PATH` falls through to `PATH` and `$HOME/.local/bin/colab` (`colab.ts:73-79`). | Repair: a non-empty (trimmed) override is authoritative; `detect()` is false and `refresh()` names the variable when it is not an executable. Plan and provider document updated. |
| C4 | Neon, Sol | LOW / MEDIUM | The first stderr line is used unbounded and a leading blank line hides the message (`colab.ts:40-43`). Sol asks for sanitised diagnostics because the message is stored, logged and shown. | Repair: first non-empty line, capped at 200 characters. Not repaired: content filtering. Every provider's error text follows the same path (`apps/server/src/index.ts`, failure path), and the dashboard is a local single-user service. |
| C5 | Neon | LOW | Signs are accepted on rate and assignments; hours left can be negative or infinite; thousands separators are rejected (`colab.ts:46-58`). | Repair: no sign on rate and assignments; hours left only when balance is non-negative, rate is positive and the result is finite; `,` thousands separators accepted. |
| C6 | Sol | LOW | The plan says usage summaries are unchanged; the snapshot adds one record to the counts and a `byProvider` entry (`sqlite-storage.ts:495`). | Repair the plan wording: token and cost totals are unchanged, record counts include the snapshot, as for plugin snapshots. No code change. |
| C7 | Sol | MEDIUM | Timeout cleanup signals numeric process ids that the system could have reused (`ccusage.ts:189`, `232-244`). | Deferred: behaviour of the existing ccusage runner, unchanged by this diff. Follow-up. |
| C8 | Sol | MEDIUM | After the command exits, a descendant that keeps the pipes open is not stopped at the deadline (`ccusage.ts:170`). | Deferred: stopping it needs the identity-safe signalling of C7. `colab usage` was observed to exit without leaving a process. Follow-up with C7. |
| C9 | Sol | MEDIUM | Cleanup after the deadline is unbounded (`ps` on Linux) (`ccusage.ts:173`). | Deferred: existing cleanup code. Follow-up with C7. |
| C10 | Sol | MEDIUM | After a failed refresh the dashboard shows the failure time as "Updated" next to the older snapshot (`dashboard-page.tsx:322`). | Deferred: applies to every provider. The pending macOS pull request adds `lastSuccessAt` to the provider status, which the dashboard can use. Follow-up. |
| C11 | Sol | LOW | `cli-status.ts:117` reads the 100 newest records, so an older snapshot can be absent from the terminal status. | Deferred: existing behaviour for every snapshot provider. Follow-up. |

The repairs are re-reviewed by the three lanes.

## Remediation re-reviews

Findings and repairs of each round are in `docs/fix-logs/2026-11-25-colab-compute-units-fix-log.md`.
The lanes, models and efforts are those of round 1; AGY ran without `bwrap` each time and
`git status` was clean afterwards.

| Round | Target | Lane 1 Grok | Lane 2 Neon | Lane 3 Sol |
| --- | --- | --- | --- | --- |
| 2 | `6112248..1c77abf` | APPROVE | APPROVE, 1 LOW | REQUEST_CHANGES, 2 MEDIUM |
| 3 | `1c77abf..e814486` | APPROVE | APPROVE | REQUEST_CHANGES, 1 MEDIUM |
| 4 | `1c77abf..4cb5c4a` | APPROVE | APPROVE | APPROVE, 1 LOW |

Round 4 LOW (lane 3): the comment above `readPid` credits it with rejecting a partly written pid
file; the rename in `publishPidSource` provides that. Not changed, so that the reviewed content
of `4cb5c4a` stays as approved; follow-up. Transcripts: `reviews/colab-triple-r2/` to `-r4/`.

Result: three APPROVE verdicts on `4cb5c4a`; no unresolved CRITICAL, HIGH or MEDIUM finding.
Later commits that change only review records and fix logs keep this approval.
