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
- Account grouping: each account is a card, `.primary.opacity(0.05)` fill with a hairline
  border, 8 pt inner padding, 10 pt between accounts, 6 pt between quota rows.
- Account header: provider name (`.body`, semibold, `.lineLimit(1)`, lowest layout
  priority), badges, and the reading age right-aligned (`.caption`, secondary). Badges use
  `.caption` `.primary` text after a tinted icon on a subtle capsule fill: Stale
  (`clock.badge.exclamationmark`, orange icon), Refresh failed (`exclamationmark.triangle`,
  red icon). Both may appear together.
- Quota row, two lines. Line 1: label (`.callout`, `.lineLimit(1)`), reset countdown
  (`.subheadline`, secondary), `compactValue` (`82%`, `.callout`, semibold, monospaced
  digits, minimum width so values align), pin button. The label has the lowest layout
  priority, so the countdown and value are never truncated. Line 2: a full-width 5 pt bar.
- Usage level from the fraction `used / limit` clamped to 0...1 (a limit of 0 or less gives
  fraction 0, normal): normal below 0.70,
  warning from 0.70, critical from 0.90. The bar is tinted (accent, orange, red). The value
  text stays `.primary`; warning and critical add `exclamationmark.triangle.fill` or
  `exclamationmark.octagon.fill` before the value. Colour is never the only cue.
- Reset countdown: `in <1m`, `in 45m`, `in 3h 12m`, `in 3h` (zero minutes omitted),
  `in 2d 4h`, `in 2d` (zero hours omitted). When the reset time has passed: `Reset due`
  in `.primary` text after an orange `clock.badge.exclamationmark` icon. No reset time: the
  slot is empty. Reading age: `<1m ago`, `5m ago`, `3h 12m ago`, `2d 4h ago`, `2d ago`; no
  observation time: `No reading time`.
- Tooltips: the absolute reset time on the countdown only; `Pin to menu bar` or `Unpin`
  on the pin button.
- Pin button: 22 x 22 pt hit target; unpinned icon at `.tertiary`, pinned icon in the accent colour.
- Accounts without quotas but shown by override: one secondary line, `No quota reported`.
- Near-limit summary: when any visible quota is critical, the status line shows
  `N near limit`.
- Sorting: accounts keep the server order. A user-chosen order is out of scope.
- Panel width 400 pt fixed. The account list is a `ScrollView` with `maxHeight: 470`; the
  whole panel stays within about 580 pt.
- No fixed row heights, so text can grow without clipping.

### Header and source

- Top row: app name, source segmented control (This Mac, Tailscale), a fixed 16 pt slot
  for the busy indicator so controls do not move during background reloads, and a gear
  button (`⌘,`) that opens settings.
- The Tailscale origin field moves from the main panel into settings. When the Tailscale
  source has no valid origin, the list area shows `Set the Tailscale address in Settings`
  with an Open Settings button. `DashboardStore.performGet` leaves `status` at `.idle`
  instead of `.failed("Enter a valid Tailscale origin.")` when `currentEndpoint` is nil, so
  neither the list nor settings shows a red error for a missing origin.
- Status section, rows within the 376 pt inner width:
  - Row 1: the source summary with the Tailscale host middle-truncated (lowest layout
    priority) on the left; `N hidden ›` on the right as a separate borderless button, not
    part of a combined accessibility element.
  - Row 2, only when it has content: `N near limit` and the request status. The status is
    omitted only for the normal idle `Ready`; `Stale (cached)` (`isUsingCachedFallback`),
    loading, refreshing and failures are shown.
  - Then the refresh warning and the missing-pin note, each on its own row in standard
    foreground with an icon. The missing-pin note has an Unpin button.
- When providers are loaded but every account is hidden: `All N providers hidden` with
  Open Settings, plus Fetch Usage on This Mac.
- Footer, one row within the 376 pt inner width: an icon-only Reload button with help
  text, `Fetch Usage` (This Mac only), `Dashboard`, `Quit`. Accessibility labels keep the
  full action names. Behavior is unchanged.

### Settings section

- Opened from the gear button inside the same panel; the panel switches between the list
  and settings. Closing and reopening the panel returns to the list.
- Settings header, row 1: Back, `Settings`, the source control and the fixed 16 pt busy
  slot. Row 2, only when present: the error status (needed after Apply).
- Contents, top to bottom: the Tailscale origin field with Apply (moved, behavior
  unchanged), `Reset to automatic` above the provider list (outside the scroll area), and
  the provider list in a `ScrollView` with `maxHeight: 340`. Without a loaded dashboard the
  list area shows `Connect a source to manage providers`.
- The main footer is hidden in settings. The panel stays within about 580 pt in both modes.
- One switch-style toggle per enabled provider account; the provider name is the toggle
  label and a `.caption` subtitle shows its state: `N quotas`, `No data`, `Refresh failed`,
  or `N quotas · Refresh failed`. Providers with quotas are listed before those without.
- The provider that owns the pinned quota shows a `Pinned` badge and an Unpin button. The
  owner is found from `pinnedQuotaID` itself, so it is found even when the pinned quota is
  missing from the current data. Quota IDs are length-prefixed
  (`<UTF-8 byte count>:<providerId><UTF-8 byte count>:<label>:<occurrence>`,
  `UsageModels.makeQuota`); a new `UsageQuota.providerID(fromID:)` parses the provider ID by
  its byte count. A string prefix match is not used, because `codex` would also match
  `codex:work`.
- Default visibility follows the data: an account is shown when its decoded `quotas` is
  non-empty, and hidden otherwise. On 2026-11-22 the This Mac source listed 20 enabled
  providers, of which 3 had quota lines (16 reported `lastError`, `manual` had no snapshot);
  the tailnet source listed 8, of which 7 had quota lines.
- Each toggle shows the effective state. Changing it stores an explicit override for that
  provider and source; an override wins over the data rule. `Reset to automatic` clears the
  overrides of the selected source and is disabled when there are none.
- Overrides are stored per source endpoint, mirroring `pinsByOrigin`: a new
  `DashboardPreferences.visibilityOverridesByOrigin: [String: [String: Bool]]` keyed by the
  same origin string, inner keys are provider IDs (`providerId`, including account suffixes),
  `true` shows and `false` hides. Changing the Tailscale origin keeps the overrides of the
  previous origin (unlike the current pin behavior, which is review finding 4 of the
  owner-Mac review and stays out of scope here).
- Hidden accounts are removed from the list only; they are still loaded. Hiding the
  provider of the pinned quota keeps the pin and the menu bar value.
- A provider ID that no longer appears in the dashboard keeps its stored override.

### Accessibility

- Each quota row is one combined element (label, value, level, reset countdown); the pin
  button is a separate control with its action as the label.
- The custom bar is hidden from VoiceOver because the combined row carries the value.
- Gear, Back, `N hidden`, Unpin and the icon-only Reload button have explicit labels.
- Account headers keep the combined label with badges and reading age (PR #69 fix `8d9bab7`).

## Tests (Red then Green, `AisubdashCore`)

- `QuotaFormatter` (moved to `AisubdashCore` so it is testable): reset countdown and
  reading age for every case in the layout section, including `in 2d` and `2d ago`; usage
  fraction clamped to 0...1, 0 for a limit of 0 or less; usage
  level from the fraction (0.699 normal, 0.70 warning, 0.90 critical), including `count`
  and `usd` quotas and a zero limit.
- `DashboardStore.visibleAccounts`: accounts with quotas shown and accounts without quotas
  hidden by default; an override `true` shows an account without quotas and `false` hides
  one with quotas; overrides match the exact provider ID; overrides are per source and
  survive a new store instance with the same preferences; reset clears only the selected
  source; changing the Tailscale origin keeps the previous origin's overrides; hiding does
  not clear the pin; `hiddenAccountCount` and `nearLimitCount` match the visible list;
  the pinned owner is found by provider ID when the pinned quota is missing;
  `UsageQuota.providerID(fromID:)` returns `codex` and `codex:work` for their own quota IDs,
  handles multi-byte provider IDs, and returns nil for a malformed ID.
- `DashboardStore.reload` with the Tailscale source and no valid origin leaves `status` at `.idle`.
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
