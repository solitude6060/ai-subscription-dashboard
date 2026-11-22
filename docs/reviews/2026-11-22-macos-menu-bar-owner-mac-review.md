# macOS menu bar review on the owner Mac

PR #69, head `c90464c`. The reviewed `apps/macos` and workflow source is identical to
the approved implementation `a10b2d7`. Reviewer: Claude Code `claude-opus-5-5`,
`/code-review high 69`, one context, no separate verification pass. The orchestrator
verified finding 1 against the cited code and the live tailnet backend. Findings 2 to 10
are unverified candidates.

## Finding 1, verified: MiniMax quotas are reported stale after one hour of each window

`UsageModels.swift:111` sets `observedAt` from the snapshot's `startedAt`.
`readTimes` in `packages/providers/src/providers/minimax.ts:297` sets `startedAt` to the
quota window start (`start_time`, `end_time` minus the coding plan window, or the UTC day
start). `DashboardStore.staleAgeThresholdSeconds` is 3600, so a fresh MiniMax reading
becomes stale one hour after its window starts.

Observation on the tailnet backend at 2026-11-22T06:20:58Z:

| Provider | Snapshot `startedAt` | Snapshot `createdAt` | Provider `lastRefreshAt` |
| --- | --- | --- | --- |
| MiniMax | 2026-11-22T05:00:00.000Z | 2026-11-22 05:18:52 | 2026-11-22T06:18:52.623Z |
| Other current providers | within 3 s of their refresh | equal to `startedAt` | not compared |

The MiniMax reading was refreshed two minutes earlier and is 80 minutes past `startedAt`.
`createdAt` keeps the first insert time within a window, so it is not a valid observation
time. `lastRefreshAt` from `/api/providers` reflects the refresh.

## Triage

| ID | Finding | Severity | Verified | This PR | Reason |
| --- | --- | --- | --- | --- | --- |
| 1 | MiniMax observation time uses the window start | Medium | Yes | Fixed | The owner enables MiniMax; a pinned MiniMax quota shows stale on fresh data. |
| 2 | Cancelled panel-open read delays the first poll by up to 60 s | Low | No | Defer | Recovers on the next poll. |
| 3 | `100.64.0.0/10` ATS exception key is a CIDR, not a domain | Low | No | Defer | Tailnet probe over HTTP to an IP literal passed on this Mac. |
| 4 | Changing the Tailscale origin deletes the previous origin's pin | Low | No | Defer | Documentation or behavior decision. |
| 5 | Refresh warning persists after later successful reads | Low | No | Defer | Display only. |
| 6 | Probe and store discard the underlying error | Low | No | Defer | Diagnosability; AGENTS.md error-handling rule. |
| 7 | Unknown progress format kinds drop the line | Low | No | Defer | No current provider emits another kind; not checked. |
| 8 | Reopening the panel discards an unapplied origin draft | Low | No | Defer | Display only. |
| 9 | Setup guide says "save" where the control is Apply | Low | No | Defer | Wording. |
| 10 | Legacy Tauri API on port 6736 conflicts with This Mac | Low | No | Defer | Documentation. |

## Environment findings outside the PR source

- Command Line Tools without Xcode cannot compile the app with the macOS 27.2 SDK:
  `@State` requires `libSwiftUIMacros.dylib`, which ships with Xcode. The macOS CI job
  uses `macos-15`. Xcode resolved the build without a source change.
- `bun run test:webui` fails three tests on macOS (`pi-session-io.test.ts` twice,
  `codex-event-rescan-failure.test.ts` once). The fixtures build paths from `tmpdir()`
  (`/var/folders`) while the scanner resolves them with `realpathSync`
  (`/private/var/folders`), so exact-path fault injection does not match. With
  `TMPDIR="$(realpath "$TMPDIR")"` the suite reports 632 pass, 2 skip, 0 fail. PR #69 does
  not change these files.

## Re-review of the finding 1 remediation

Target: `git diff 6f70442 5ac751f` (`c01d6d4` test, `23cb872` fix, `5ac751f` fix log).
Reviewer: Codex `gpt-6.1-sol`, `model_reasoning_effort=high`, `--sandbox read-only`, fresh
context, a different model family from the implementing context (Claude `claude-opus-5-5`).
Transcript retained locally in the sibling artifacts directory (`reviews/pr69-owner-mac-r1/`).

| Verdict | Findings |
| --- | --- |
| APPROVE | None |

The reviewer reproduced the new test failing against `6f70442` (observed `05:00:00`,
expected `06:18:52.623`) and passing against `5ac751f`, and ran the macOS suite: 24 tests,
0 failures. Recorded residual risk: a collector that reports success without writing a new
snapshot would have its previous snapshot dated by the refresh. The current snapshot-producing
collectors return a snapshot on success (`minimax.ts:83`, `openusage-plugin.ts:298`).
Not checked by the reviewer: live provider refreshes and menu interaction.
