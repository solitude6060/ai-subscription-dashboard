# macOS panel text lines and review follow-ups

Date: 2026-11-25. Branch: `feat/panel-text-lines-and-followups` (from `main` at `50bca0c`).

## Goal

1. The macOS menu bar panel shows snapshot text lines, so an account whose snapshot has no
   progress line (Google Colab) shows its values.
2. Close the findings deferred by the reviews of pull requests 71 and 73.

## Part 1: text lines in the panel

`UsageContractDecoder` keeps `type: "progress"` lines only (`UsageModels.swift`). A Colab snapshot
has three `type: "text"` lines (`label`, `value`), so the card shows "No quota reported", and the
account is hidden by default because automatic visibility requires a quota.

Change:

- `UsageDetail` (`id`, `label`, `value`) and `UsageAccount.details`, decoded from `raw.lines`
  entries with `type: "text"`, a non-empty `label` and a non-empty string `value`. Order follows
  the snapshot. Other line types stay ignored. Details are kept only for an account without a
  quota, and at most the first three: on 2026-11-25 the owner's backend returned up to 12 text
  lines for accounts that also have quotas (Cursor, Codex), and the web card summary also shows
  three lines.
- `DashboardStore.isAccountVisible`: the automatic default is true when the account has a quota
  or a detail.
- `AccountCardView`: one row per detail (label left, value right). "No quota
  reported" shows only when both lists are empty.

Unchanged: details cannot be pinned, have no usage level and no reset time, so the menu bar
title, the near-limit count and staleness by reset time do not read them. `--probe-*` output keeps
counting quotas.

## Part 2: deferred findings

| ID | Finding | Decision |
| --- | --- | --- |
| C7 | Timeout cleanup signals process ids listed by `ps`; the system could have reused one (`ccusage.ts`, `killProcessTree`). | No change. The listing exists to stop descendants that left the process group (`29a7599`, tests in `ccusage-provider.test.ts`). A signal bound to process identity needs a pidfd, which Bun does not expose, or a cgroup: `Bun.spawn({ cgroup })` (Linux, Bun 1.4) joins an existing cgroup, and creating one needs host permissions the service does not have by default. The interval between listing and the last signal is about 50 ms. |
| C8 | After the command exits, a descendant that holds the pipes is not stopped at the deadline. | No change. The command's process id is released at that point, so a signal to it or to its group has the identity problem of C7. The refresh itself returns at the deadline. |
| C9 | The `ps` call during cleanup has no deadline. | Repair: 2 second deadline on the `ps` process. On expiry the listing is empty and the group and root signals still go out. |
| C10 | After a failed refresh the dashboard card shows the failure time as "Updated". | Repair: the card footer and the group's latest time use `lastSuccessAt`; without it, `lastRefreshAt` only when the status has no error. |
| C11 | `cli-status` reads the 100 newest records, so an older snapshot can be absent. | Repair: read `listLatestUsageSnapshots()`, the query behind `/api/usage/latest-snapshots`. |
| Round 4 LOW | A test comment credits `readPid` with rejecting a partly written pid file. | Repair the comment. |
| F8 | Panel list height cap and `NSScreen.main` (`MenuBarContentView.swift:21`, `:252`). | No change. No fault was observed; the owner checked this sizing on 2026-11-25, and a change needs a second-display check that is not available. |

## Tests (written first)

1. Swift: a snapshot with text lines decodes into `details`; lines without a label or value are
   dropped; progress lines still decode into `quotas`.
2. Swift: an account with details and no quota is visible by default.
3. Web: the "Updated" time is the last success after a failed refresh, and absent when the only
   refresh failed.
4. Server: `cli-status` prints a snapshot provider that is older than 100 newer records.
5. Providers: cleanup returns when the `ps` listing does not finish (Linux only; skipped elsewhere).

## Verification

`swift test --package-path apps/macos`, `bun run test:webui`, `bun run test`, `bun run build`,
and the built app against the owner's backend.

## Exit criteria

Tests and build pass, documents updated, triple review returns APPROVE.
