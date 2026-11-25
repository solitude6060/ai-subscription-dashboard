# Google Colab provider fix log

Review record: `docs/reviews/2026-11-25-colab-compute-units-review.md` (round 1 at `6112248`).
Repairs by Codex `gpt-6.2-sol` (high); the orchestrator reran the checks at `fe0c62e`.

| Finding | Repair | Files | Commits |
| --- | --- | --- | --- |
| C1 Timing test depends on two process starts within 300 ms and leaves a child running | Longer deadline; the fixture child is reaped by its recorded pid; a test covers stopping a command that is still running at the deadline | `packages/providers/test/colab-provider.test.ts` | Test `f8e580b`, fix `4849f70` |
| C2 The command ran with the host environment | The runner accepts an environment and the provider passes the one it was given | `ccusage.ts`, `colab.ts` | Test `3783048`, fix `6f347f5` |
| C3 An invalid `COLAB_CLI_PATH` fell through to other locations | A non-empty trimmed override is the only location used; an invalid one fails with a message naming the variable | `colab.ts`, `docs/providers/colab.md`, plan | Test `2afe81f`, fix `b4dfeb3` |
| C4 Unbounded first stderr line; a leading blank line hid the message | First non-empty line, at most 200 characters | `colab.ts` | Test `6ad973b`, fix `2853979` |
| C5 Signed values, non-finite hours left, thousands separators | Rate and assignments take no sign; hours left only for a non-negative balance, a positive rate and a finite result; `,` separators accepted | `colab.ts` | Test `a9573d6`, fix `21d2714` |
| C6 Plan wording on usage summaries | Token and cost totals are unchanged; record counts and the provider breakdown include the snapshot | plan | `fe0c62e` |

The implementer reported an assertion failure before each repair of C1 to C5. At `fe0c62e`,
rerun by the orchestrator: Colab and ccusage tests 45 pass, 2 skip, 0 fail;
`bun run test:webui` 666 pass, 2 skip, 0 fail; `bun run build:webui` passes.

Deferred (C7 to C11): see the review record. Not verified: a refresh against the real CLI on
the owner's Linux host.

## Remediation re-review (2026-11-25)

Target `6112248..1c77abf`. Lane 1 (Grok Build `grok-4.7`, xhigh): APPROVE, no findings. Lane 2
(AGY `gemini-4-neon-high`, high): APPROVE, 1 LOW. Lane 3 (Codex `gpt-6.2-sol`, high):
REQUEST_CHANGES, 2 MEDIUM. Transcripts: `reviews/colab-triple-r2/` in the sibling artifacts
directory.

| Finding | Source | Verified | Repair |
| --- | --- | --- | --- |
| The test cleanup parses the pid file with `Number()`; an empty or partly written file gives 0, and `process.kill(0, "SIGKILL")` addresses the test runner's process group. `SIGKILL` to a process that has just exited throws `ESRCH` from `finally`. | Sol (MEDIUM), Neon (LOW) | Yes, `colab-provider.test.ts:39-42` | `readPid` returns a positive integer or null; the tests assert a pid was recorded; `ESRCH` on the kill is ignored. Test-only change, no red phase. |
| The lingering-output test polls with signal 0, which also succeeds for a zombie that its adoptive parent has not reaped. | Sol (MEDIUM) | By reading; not reproduced on macOS | Partly: the cleanup loop stops waiting at its deadline without failing. The assertion that the fixture is gone stays, so the test still depends on the system reaping orphans. Recorded as a limit. |

After the repair: Colab and ccusage tests 45 pass, 2 skip, 0 fail.
