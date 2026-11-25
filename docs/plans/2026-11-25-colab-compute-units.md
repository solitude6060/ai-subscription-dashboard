# Google Colab compute units provider

Date: 2026-11-25. Branch: `feat/colab-compute-units` (from `main` at `5e54e99`).

## Goal

Show the Google Colab compute-unit balance in the WebUI dashboard. The backend reads it from
the Colab CLI on the machine where the backend runs.

## Source

`google-colab-cli` (installed with `uv tool`, executable `colab`). On the owner's Linux host
the executable is `~/.local/bin/colab`; that directory is not on the `PATH` of a
non-interactive shell. `colab usage` is read-only. Observed on 2026-11-25 (exit code 0,
plain text on stdout, empty stderr, no JSON option in `colab usage --help`):

```
Current balance: 341.98 compute units
Usage rate: 0.00/hr
Active assignments: 0
```

The balance has no limit and no reset time.

## Scope

In scope: a native backend provider, its WebUI listing, tests and documentation.

Out of scope:

- The macOS menu bar panel. Its decoder keeps progress lines only, so a Colab account shows
  "No quota reported" there. Text-line support is a follow-up after the panel pull request
  merges.
- Kaggle, AI Studio and Jev. No documented quota or balance interface was found for them.
- Deployment to the always-on service, which needs owner approval (`README_WEBUI.md`).

## Design

Provider id `colab`, name `Google Colab`, class `ColabProvider` in
`packages/providers/src/providers/colab.ts`. It follows the two existing native providers:
dependency injection as in `MiniMaxProvider`, command execution as in `CcusageProvider`.

Executable lookup uses the trimmed `COLAB_CLI_PATH` value when it is non-empty. If that value
does not resolve to an executable, `detect()` returns false and `refresh()` reports an error
naming `COLAB_CLI_PATH`. When the variable is unset or blank, lookup checks for `colab` on
`PATH`, then at `$HOME/.local/bin/colab`. Detection runs no command.

`refresh()` runs `<executable> usage` with the provider's environment, stdin ignored and a
20 second timeout. The command runner is injected through the constructor. It shares the spawn,
timeout and kill logic in `ccusage.ts`. Timeout messages name the command that ran.

Parsing, line by line, case-sensitive labels as observed:

| Line | Rule |
| --- | --- |
| `Current balance: <number> compute units` | Required. Accepts an optional sign. A missing or non-numeric value is an error. |
| `Usage rate: <number>/hr` | Optional. Digits with an optional fractional part and no sign. |
| `Active assignments: <integer>` | Optional. Integer digits without a sign. |

All three fields accept comma thousands separators in groups of three digits.

Errors are thrown from `refresh()` with a message the Providers page can show: executable not
found (names `COLAB_CLI_PATH`), command failed (includes up to 200 characters from the first
nonblank stderr line), timeout, and unrecognised output. No zero or cached value is substituted.

`refresh()` returns one `UsageRecord`:

- `id`: a fixed value derived from `"colab|usage"`, so each refresh updates one row.
- `providerId: "colab"`, `tool: "OpenUsage Plugin Snapshot"` (the latest-snapshot query in
  `sqlite-storage.ts` selects `raw.lines` records by this tool name), `source: "cli"`,
  `startedAt`: the refresh time.
- `raw.lines`: text lines, which the WebUI already renders (`usage-line.tsx`), as OpenRouter's
  `Balance` line does.

| Label | Value | Condition |
| --- | --- | --- |
| `Balance` | `341.98 compute units` | Always |
| `Usage Rate` | `0.00 units/hr`. The finite estimate `balance / rate` is appended to one decimal place when the balance is non-negative and the rate is positive. Example: `3.00 units/hr, 12.3 h left` | When the rate line is present |
| `Active Sessions` | `0` | When the assignments line is present |

The snapshot leaves token and cost totals unchanged. Usage summary record counts include it,
and `byProvider` includes a Colab entry, as with other provider snapshots.

## Files

| File | Change |
| --- | --- |
| `packages/core/src/types.ts` | Add `"colab"` to `PROVIDER_IDS` |
| `packages/providers/src/providers/colab.ts` | New provider |
| `packages/providers/src/providers/ccusage.ts` | Share the command runner |
| `packages/providers/src/index.ts`, `registry.ts` | Export and register |
| `apps/web/src/provider-ui.ts` | Add to `providerCards` and `refreshableProviders` |
| `apps/server/src/cli-status.ts` | Provider name |
| `packages/providers/test/colab-provider.test.ts` | New tests |
| `docs/providers/colab.md` | New provider document |
| `README.md`, `README_WEBUI.md`, `README_WEBUI.zh-TW.md`, `docs/USER_GUIDE_WEBUI.zh-TW.md` | Supported-provider lists and a Colab note |

## Tests

Written before the implementation, each failing on an assertion first:

1. The observed output yields the `Balance`, `Usage Rate` and `Active Sessions` lines without
   hours left.
2. A rate greater than 0 appends the hours left to `Usage Rate`.
3. Output without the balance line throws; so does a non-numeric balance.
4. A failed command and a timeout throw messages that name the cause.
5. Executable lookup order, and `detect()` true and false.
6. The record uses the fixed id, the snapshot tool name and `source: "cli"`.
7. The registry returns a `ColabProvider`; the WebUI lists it as refreshable.
8. A refresh through the server stores the record and `/api/usage/latest-snapshots` returns it.

## Verification

- `bun test packages/providers/test/colab-provider.test.ts`
- `bun run test:webui` (on macOS run with `TMPDIR="$(realpath "$TMPDIR")"`; three unrelated
  tests fail with the default value)
- `bun run build:webui`
- On the owner's Linux host after deployment: refresh Google Colab and compare the dashboard
  with `colab usage`.

## Exit criteria

The tests above pass, the build passes, the documents listed are updated, and the review
required by the project gate returns APPROVE.
