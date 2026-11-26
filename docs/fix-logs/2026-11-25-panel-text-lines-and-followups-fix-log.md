# Fix log: macOS panel text lines and review follow-ups

Review: `docs/reviews/2026-11-25-panel-text-lines-and-followups-review.md`.

## Deferred findings from earlier reviews

| ID | Reproduction | Repair | Test | Files |
| --- | --- | --- | --- | --- |
| C9 | A listing command that does not finish kept cleanup waiting (3 s in the test, against a 100 ms deadline). | `timeout` and `killSignal` on the `ps` process, 2 s by default. | `ccusage-provider.test.ts`, "descendant listing gives up ..." | `ccusage.ts` |
| C10 | A status with `lastError` and a later `lastRefreshAt` gave the failure time as "Updated". | `lastUpdatedAt`: `lastSuccessAt`, otherwise `lastRefreshAt` only without an error. Same rule in `cli-status`. | `dashboard-page.test.ts` "lastUpdatedAt"; `cli-status-snapshots.test.ts` | `dashboard-page.tsx`, `cli-status.ts` |
| C11 | With 101 newer records, `cli-status` printed "No usage data". | Read `listLatestUsageSnapshots()`. | `cli-status-snapshots.test.ts`, "prints a snapshot that is older ..." | `cli-status.ts` |
| Round 4 LOW | Comment wording. | Comment corrected. | None (comment only). | `colab-provider.test.ts` |

C7, C8 and F8: no change; reasons in the plan.

## Round 1

| ID | Reproduction | Repair | Test | Files |
| --- | --- | --- | --- | --- |
| P1 | A listing command that printed `4242 1` and was then stopped, or exited with code 1, returned `[4242]`. | The listing is parsed only when the process exits with code 0. The exit is awaited before the read, so a process that holds the pipe does not extend the deadline. A spawn error gives an empty listing. | `ccusage-provider.test.ts`, "descendant listing discards ..." | `ccusage.ts` |
| P2 | `status(quotas: 0, details: 1, ...)` returned "No data". | `ProviderCountFormatter.status` returns "1 value" or "N values"; Settings sorts accounts with details with the non-empty accounts. | `ProviderCountFormatterTests` | `ProviderCountFormatter.swift`, `ProviderVisibilitySettings.swift` |
| P3 | Not reproduced; read from the assertion. | Optional leading zero, the failure time asserted absent, a case for a status whose only refresh failed. | `cli-status-snapshots.test.ts` | Test only |

## Round 2

| ID | Reproduction | Repair | Test | Files |
| --- | --- | --- | --- | --- |
| P4 | A listing command that printed a record, started a background `sleep 3` and exited with code 0 returned after 3 s with that record, against a 100 ms deadline. | One timer races the exit and the read; on expiry the listing is empty. | `ccusage-provider.test.ts`, "descendant listing discards ..." (held-pipe case) | `ccusage.ts` |
| P5 | Not applicable. | No code change; reason in the review record. | None. | None. |
| P6 | Not reproduced; read from the assertion. | The expected time text comes from a process with the same environment. | `cli-status-snapshots.test.ts` | Test only |
| P7 | Plan wording. | Plan corrected. | None. | Plan |

## Round 3

| ID | Reproduction | Repair | Test | Files |
| --- | --- | --- | --- | --- |
| P8 | Read from the code; the return value does not show a read that stays active. | The read goes through an abortable stream and is aborted when the listing is discarded. | No new test: the existing listing cases pass through the abort path (timeout, non-zero exit, held pipe). | `ccusage.ts` |

## Verification

On macOS 27.2, 2026-11-27: `swift test` 63 tests, 0 failures; `bun run test:webui` 686 pass,
2 skip, 0 fail; `bun run build` passes. `bun run test` (vitest): 1395 pass, 2 fail in
`allowance-page.vitest.tsx`; the same two fail on `main` at `50bca0c` on this machine and passed
in CI for pull request 73. Cause not determined.

Not verified: a Colab card on screen. The owner's backend does not run the Colab provider yet.
