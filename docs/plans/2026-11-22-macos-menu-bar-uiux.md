# macOS Menu Bar Panel Layout and Provider Settings

## Scope and baseline

Follow-up to PR #69 (`feat/macos-menu-bar`), stacked on its head `b238496`. Branch
`feat/macos-menu-bar-uiux`. Only `apps/macos` and macOS documentation change. The
server, Web dashboard and the HTTP contract in `docs/local-http-api.md` do not change.

Owner requests from the 2026-11-22 Mac verification:

1. Important information is visible without expanding anything.
2. The panel is hard to read and visually poor.
3. A settings section chooses which providers each source shows.

## Evidence

- Real tailnet data on 2026-11-22: 12 provider snapshots, 0 to 5 progress quotas per
  account, every quota uses the `percent` format. A fully expanded list is about 30 quota rows.
- Current panel (`AisubdashMenuBarApp.swift`): accounts collapse when there are more than
  3, so the 8-account tailnet source shows no quota until a row is opened. Quota text uses
  `.caption` and `.caption2` with `.secondary` foreground on a `.quaternary.opacity(0.35)`
  background. Reset times are absolute dates.
- macOS 27.2.1 constraints verified on the owner's Mac: `TimelineView` in the
  `MenuBarExtra` label hides the status item; `DisclosureGroup` does not expand in a
  `.window` panel; a `Button` toggling `@State` or an `@Observable` property works. Time
  is rendered from `DashboardStore.clock`. The implementation must not reintroduce
  `TimelineView` or `DisclosureGroup`.

## Decisions

### Layout: flat, scannable list

- Remove account expansion. Every account shows a header line and all of its quotas.
- Account header: provider name (`.body`, semibold), then badges for Stale and Refresh
  failed, then the reading age right-aligned (`5m ago`, `.caption`, secondary).
- Quota row, one line each: label (`.callout`), a thin bar, the value right-aligned
  (`.callout`, semibold, monospaced digits), the time until reset (`in 3h 12m`, `.caption`,
  secondary), and the pin button. The absolute reset time moves to the row's help tooltip.
- Usage colour on the bar and value: below 70% the accent colour, 70% to below 90% orange,
  90% and above red. The thresholds are constants in `AisubdashCore`.
- Accounts without quotas show one secondary line, "No quota reported".
- Sorting: accounts keep the server order. A user-chosen order is out of scope.
- Panel width 400 pt fixed; the list scrolls above 520 pt height.

### Header and source

- Top row: app name, source segmented control (This Mac, Tailscale), a gear button that
  opens settings, and the busy indicator.
- The Tailscale origin field moves from the main panel into settings. When the Tailscale
  source has no valid origin, the list area shows "Set the Tailscale address in Settings"
  with a button that opens settings.
- The status line keeps the source summary, request status, refresh warning and the
  missing-pin note, in `.caption` with standard (not secondary) foreground for warnings.
- Footer: Reload, Fetch Provider Usage (This Mac only), Open Dashboard, Quit, unchanged in behavior.

### Settings section

- Opened from the gear button inside the same panel (the panel switches between the list
  and settings; a back button returns). No separate window.
- Contents: the Tailscale origin field with Apply (moved, behavior unchanged) and, for the
  selected source, one toggle per provider account in the loaded dashboard: "Show".
- Default visibility follows the data: an account is shown when its decoded `quotas` is
  non-empty, and hidden otherwise. On 2026-11-22 the This Mac source listed 20 enabled
  providers, of which 3 had quota lines (16 reported `lastError`, `manual` had no snapshot);
  the tailnet source listed 8, of which 7 had quota lines.
- Each settings toggle shows the effective state. Changing it stores an explicit override
  for that provider and source; an override wins over the data rule. A "Reset to automatic"
  button clears the overrides of the selected source.
- Overrides are stored per source endpoint, mirroring `pinsByOrigin`: a new
  `DashboardPreferences.visibilityOverridesByOrigin: [String: [String: Bool]]` keyed by the
  same origin string, inner keys are provider IDs (`providerId`, including account suffixes),
  `true` shows and `false` hides.
- Settings list every enabled provider of the loaded dashboard, including hidden ones, each
  with a short state: quota count, "No data", or "Refresh failed".
- Hidden accounts are removed from the list only; they are still loaded. Hiding the
  provider of the pinned quota keeps the pin and the menu bar value.
- An account shown by override without quotas displays "No quota reported" and its badges.
- A provider ID that no longer appears in the dashboard keeps its stored override.
- The status line shows "N hidden" when accounts are hidden, which opens settings.

## Tests (Red then Green, `AisubdashCore`)

- `QuotaFormatter` (moved to `AisubdashCore` so it is testable): time until reset
  (`in 45m`, `in 3h 12m`, `in 2d 4h`, `Reset due` when past), usage fraction clamped to 0...1,
  usage level from the thresholds (69.9 normal, 70 warning, 90 critical).
- `DashboardStore.visibleAccounts`: accounts with quotas shown and accounts without quotas
  hidden by default; an override `true` shows an account without quotas and `false` hides
  one with quotas; overrides match the exact provider ID; overrides are per source and
  survive a new store instance with the same preferences; reset clears only the selected
  source; hiding does not clear the pin; `hiddenAccountCount` matches the filter.
- Existing 25 tests stay green.

View code has no unit tests (XCTest has no `MenuBarExtra` panel). The owner checks the
panel on the Mac, recorded in the fix log with the build commit.

## Work split

| Step | Owner | Exit criteria |
| --- | --- | --- |
| Plan | Claude Opus (this document) | Owner accepts the decisions above |
| Implementation | Codex `gpt-6.2-sol`, workspace-write in sibling worktree `ai-subscription-dashboard-wt-uiux` | Red commit then Green commit per test group, `swift test --package-path apps/macos` passes, `build-app.sh` and `codesign --verify --strict` pass, no `TimelineView` or `DisclosureGroup` in `apps/macos/Sources` |
| Review | Separate context, model per `MODEL_ROUTING.md` | APPROVE, findings in a review document and fix log |
| Owner check | Owner on the Mac | List readable without expanding; settings hide and show a provider per source; pin survives hiding |

## Out of scope

User-chosen account order, notifications, colour themes, launch at login, the iOS widget.
