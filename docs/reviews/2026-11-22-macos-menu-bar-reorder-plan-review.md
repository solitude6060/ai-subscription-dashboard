# Drag-to-reorder plan review

Target: `docs/plans/2026-11-22-macos-menu-bar-reorder.md` at `6387353`.
Reviewer: AGY `gemini-4-neon-high`, effort high, read-only, fresh context (owner-requested
UI/UX lane). Transcript in the sibling artifacts directory (`reviews/reorder-plan-neon-r1/`).
Verdict: REQUEST_CHANGES. Each finding was checked against the plan and the cited code.

| ID | Severity | Finding | Verified | Disposition |
| --- | --- | --- | --- | --- |
| 1 | HIGH | One "Reset to automatic" clearing visibility and order is a surprise; order is not shown in settings | Yes, `ProviderVisibilitySettings.swift:10-12` | Split: `Reset Order` button, `hasCustomOrder`, `resetAccountOrder()` |
| 2 | HIGH | Move actions on the card container would reach quota rows and pin buttons | Yes, the header is the combined element (`AccountCardView.swift:57`), the card `VStack` is not | Actions on the header element; first/last omission stated per action |
| 3 | MEDIUM | Saving `orderedAccounts` IDs on a move erases saved IDs absent from the dashboard; `by offset` inputs unspecified | Yes, contradiction within the plan | Merged working list; direction enum; hidden or unknown IDs rejected; tests added |
| 4 | MEDIUM | Handle size ambiguous, thin glyph hit-testing, handle shown for a single card | Yes | `.caption` glyph in a 22 x 22 pt frame with `contentShape`; handle and drop only with two or more cards |
| 5 | MEDIUM | Self highlight, external text accepted, `stroke` clipping | Partly | `strokeBorder`; drop accepts only visible IDs. Not adopted: payload nonce or custom UTType, and self-highlight suppression; a matching external string only reorders, which the user can undo |
| 6 | LOW | `K` was not tested inside the capped `ScrollView`; owner checks and `docs/macos-menu-bar.md` missing | Yes | Owner checks extended; doc update listed |

## Re-review of the revision

Target: `git diff 6387353..0b4dedb -- docs/plans/2026-11-22-macos-menu-bar-reorder.md`.
Reviewer: AGY `gemini-4-neon-high`, effort high, fresh context. Transcript in
`reviews/reorder-plan-neon-r2/`. Verdict: APPROVE. Findings 1-4 and 6 resolved; finding 5
partial by decision, accepted by the reviewer. No new findings.
