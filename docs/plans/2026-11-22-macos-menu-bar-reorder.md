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
- Working list for a move: the stored IDs for the current origin (deduplicated, including
  IDs absent from the current dashboard), then current dashboard IDs not yet stored, in
  server order. The move is applied to this list and the whole list is saved, so a
  temporarily absent provider keeps its place.
- `moveAccount(_ providerID: String, onto targetID: String) -> Bool`: both IDs must be
  visible accounts and differ. If the dragged account was before the target it lands
  directly after the target, otherwise directly before it (the `K` behaviour). Other
  entries, hidden or absent, keep their relative order. Returns false without saving
  otherwise, or when `currentEndpoint` is nil.
- `enum AccountMoveDirection { case up, down }` and
  `moveAccount(_ providerID: String, _ direction: AccountMoveDirection) -> Bool`: the ID must
  be visible; it moves past the nearest visible neighbour in that direction, skipping
  hidden and absent entries. Returns false without saving at either end, for a hidden or
  unknown ID, or when `currentEndpoint` is nil. Used by VoiceOver actions.
- Reset is split (review finding 1): `hasCustomOrder` and `resetAccountOrder()` clear only
  the selected origin's saved order; `resetVisibilityOverrides()` and
  `hasVisibilityOverrides` stay unchanged. Other origins keep theirs; changing the
  Tailscale origin keeps the previous origin's order (same rule as overrides).
- No source switch, reload or refresh changes the saved order. Pins are unaffected.

### Panel (`AisubdashMac`)
- Drag handle, shown only when at least two cards are visible: `line.3.horizontal` at
  `.caption` size, secondary colour, in a 22 x 22 pt frame with `.contentShape(Rectangle())`,
  at the leading edge of the card header, `.help("Drag to reorder")`. The handle carries
  `.draggable(account.id) { preview }`; the preview is the provider name on a card
  background. Only the handle starts a drag, so clicks on the pin buttons and text are not
  captured.
- The whole card is a `.dropDestination(for: String.self)` (only when the handle is shown);
  while targeted it shows `RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor,
  lineWidth: 2)`. The drop calls `moveAccount(_:onto:)` and returns its result, so a string
  that is not a visible provider ID (text from another app) is rejected. The dragged card
  may highlight over itself; a self drop is a no-op. No payload nonce or custom UTType:
  the only effect of a matching external string is a reorder the user can undo by dragging.
- Settings: next to `Reset to automatic` (visibility), a `Reset Order` button, same
  `.controlSize(.small)`, disabled when `!store.hasCustomOrder`.
- Accessibility: the handle is hidden from VoiceOver. `Move Up` (omitted on the first
  visible card) and `Move Down` (omitted on the last visible card) are
  `.accessibilityAction(named:)` on the card header element, which is already
  `.accessibilityElement(children: .combine)` (`AccountCardView.swift:57`), so quota rows and
  pin buttons do not get them.
- No animation requirement; the list re-renders from the store.
- Update `docs/macos-menu-bar.md` (drag, Move Up/Down, Reset Order).

## Tests (Red then Green, `AisubdashCore`)

- No saved order: `orderedAccounts` equals server order.
- Saved order applied; unknown saved IDs ignored and kept in storage; new accounts appended
  in server order.
- `moveAccount(_:onto:)` down (A onto C gives B, C, A) and up (C onto A gives C, A, B);
  with a hidden account between them its relative position is kept; a saved ID absent from
  the dashboard survives a move; unknown, hidden or equal IDs return false without saving.
- `moveAccount(_:_:)` skips hidden neighbours; false at the first and last visible card and
  for a hidden or unknown ID.
- Order is per origin, survives a new store with the same preferences, `resetAccountOrder`
  clears only the selected origin and leaves visibility overrides, `resetVisibilityOverrides`
  leaves the order, changing the Tailscale origin keeps the previous origin's order,
  `hasCustomOrder` reflects the selected origin.
- Pin and visibility unchanged by moves. Existing 43 tests stay green.

View behaviour (handle, drop border, VoiceOver actions) is checked by the owner on the Mac.

## Work split

| Step | Owner | Exit criteria |
| --- | --- | --- |
| Feasibility | Owner, minimal app `K` | Done: cards reorder by dragging in the panel |
| Plan review | AGY `gemini-4-neon-high` (UI/UX lane) | APPROVE or findings resolved |
| Implementation | Codex `gpt-6.2-sol` high, worktree `ai-subscription-dashboard-wt-uiux` | Red then Green commits, `swift test`, `build-app.sh`, `codesign --verify --strict` pass |
| Owner check | Owner on the Mac | Drag reorders, including onto a card scrolled into view (record whether the list auto-scrolls while dragging); pin buttons still click; VoiceOver Move Up/Down; order survives restart, per source; Reset Order restores server order |

## Review

Neon plan review r1 (REQUEST_CHANGES, six findings) is recorded in
`docs/reviews/2026-11-22-macos-menu-bar-reorder-plan-review.md`; this revision addresses it.

## Out of scope

Reordering quotas inside a card, reordering in settings, syncing order between sources or
machines.
