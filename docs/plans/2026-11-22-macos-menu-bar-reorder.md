# macOS menu bar: drag to reorder providers

Branch `feat/macos-menu-bar-uiux` (same pull request as the panel layout; owner UI/UX
feedback). Extends `docs/plans/2026-11-22-macos-menu-bar-uiux.md`, whose "Out of scope"
listed a user-chosen account order. The owner asked for it on 2026-11-22 and chose
dragging cards in the main panel over reordering in settings.

## Evidence

- `MenuBarExtra(.window)` on macOS 27.2.1 broke `TimelineView` (label) and
  `DisclosureGroup` (panel), so drag and drop is checked in the same panel style first.
  Minimal app `K`: cards in a `VStack` with `.draggable(String)` and
  `.dropDestination(for: String.self)`. Minimal app `L`: `List` with `.onMove`.
  Result (owner, 2026-11-22): `K` reorders cards by dragging in the panel. `L` was not
  needed for the chosen design.

## Decisions

### Store (`AisubdashCore`)
- `DashboardPreferences.orderByOrigin: [String: [String]]` (UserDefaults key
  `aisubdash.orderByOrigin`), keyed by endpoint origin like `visibilityOverridesByOrigin`.
  Values are provider IDs (`UsageAccount.id`), matched exactly.
- `DashboardStore.orderedAccounts`: the dashboard accounts with saved IDs first in saved
  order, then every account not in the saved list in server order. Saved IDs missing from
  the dashboard are ignored (kept in storage so a provider that returns keeps its place).
- `visibleAccounts` filters `orderedAccounts`, so `hiddenAccountCount`, `nearLimitCount`
  and the panel follow the order. The settings provider list keeps its current grouping
  (with quotas first).
- `moveAccount(_ providerID: String, onto targetID: String) -> Bool`: operates on the full
  ordered ID list, hidden accounts included. If the dragged account was before the target
  it lands directly after the target, otherwise directly before it (the `K` behaviour).
  Hidden accounts keep their positions relative to each other. Returns false and changes
  nothing when either ID is not a current account or both are equal. Saves the full
  ordered list for the current origin.
- `moveAccount(_ providerID: String, by offset: Int) -> Bool` (offset -1 or +1): swaps
  with the nearest visible neighbour in that direction, skipping hidden accounts. Returns
  false at either end. Used by VoiceOver actions.
- `resetVisibilityOverrides()` becomes the single "Reset to automatic" action and also
  clears the saved order for the selected origin; `hasVisibilityOverrides` is true when
  either overrides or a saved order exist for the selected origin. Other origins keep
  theirs; changing the Tailscale origin keeps the previous origin's order (same rule as
  overrides).
- No source switch, reload or refresh changes the saved order. Pins are unaffected.

### Panel (`AisubdashMac`)
- Each card shows a drag handle (`line.3.horizontal`, secondary, 16 pt, leading edge of
  the card header) with `.help("Drag to reorder")`. The handle carries
  `.draggable(account.id) { preview }`; the preview is the provider name on a card
  background. Only the handle starts a drag, so clicks on the pin buttons and text are not
  captured.
- The whole card is a `.dropDestination(for: String.self)`; while targeted it shows an
  accent-colour 2 pt border. The drop calls `moveAccount(_:onto:)` and returns its result,
  so text dragged in from another app is rejected.
- Accessibility: the handle is hidden from VoiceOver; each card gets
  `.accessibilityAction(named: "Move Up")` and `"Move Down"`, omitted for the first and
  last visible card, calling `moveAccount(_:by:)`.
- No animation requirement; the list re-renders from the store.

## Tests (Red then Green, `AisubdashCore`)

- No saved order: `orderedAccounts` equals server order.
- Saved order applied; unknown saved IDs ignored and kept in storage; new accounts appended
  in server order.
- `moveAccount(_:onto:)` down (A onto C gives B, C, A) and up (C onto A gives C, A, B);
  with a hidden account between them its relative position is kept; unknown ID, equal IDs
  return false without saving.
- `moveAccount(_:by:)` skips hidden neighbours; false at the first and last visible card.
- Order is per origin, survives a new store with the same preferences, reset clears only
  the selected origin, changing the Tailscale origin keeps the previous origin's order,
  `hasVisibilityOverrides` is true with only a saved order.
- Pin and visibility unchanged by moves. Existing 43 tests stay green.

View behaviour (handle, drop border, VoiceOver actions) is checked by the owner on the Mac.

## Work split

| Step | Owner | Exit criteria |
| --- | --- | --- |
| Feasibility | Owner, minimal app `K` | Done: cards reorder by dragging in the panel |
| Plan review | AGY `gemini-4-neon-high` (UI/UX lane) | APPROVE or findings resolved |
| Implementation | Codex `gpt-6.2-sol` high, worktree `ai-subscription-dashboard-wt-uiux` | Red then Green commits, `swift test`, `build-app.sh`, `codesign --verify --strict` pass |
| Owner check | Owner on the Mac | Drag reorders, order survives restart, per source, reset restores server order |

## Out of scope

Reordering quotas inside a card, reordering in settings, syncing order between sources or
machines.
