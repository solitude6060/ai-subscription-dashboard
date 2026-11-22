# macOS panel layout plan review

Target: `docs/plans/2026-11-22-macos-menu-bar-uiux.md` at `fbdfbc0` (before rebase `2369f76`),
read against `apps/macos/Sources`. Reviewer: AGY `gemini-4-neon-high`, effort high, fresh
context, requested by the owner. Transcript retained locally in the sibling artifacts
directory (`reviews/uiux-plan-neon-r1/`).

Isolation note: the routing registry's call shape wraps AGY in `bwrap`, which macOS does not
provide. The run used `--mode plan --sandbox`; AGY reported that `--mode plan` has no
effect while slash commands are disabled. `git status` was clean after the run.

| Verdict | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| REQUEST_CHANGES | HIGH | Five elements on one quota line at 400 pt truncate and misalign | Two-line quota row, `compactValue`, aligned value width |
| | HIGH | No account grouping specified | Cards with fill, hairline border and fixed spacing |
| | HIGH | Colour is the only severity cue; orange text and `.caption2` badges have low contrast | Value stays `.primary`, severity icons, `.caption` badges with icons |
| | HIGH | Four `.titleAndIcon` footer buttons exceed the fixed inner width | Icon-only Reload, shorter labels, full accessibility labels |
| | HIGH | Empty states and settings scrolling, header and dismissal unspecified | All-hidden, no-dashboard and no-origin states; settings header and scroll; reset on reopen |
| | MEDIUM | Hiding the pinned provider removes the way to unpin | `Pinned` badge and Unpin in settings |
| | MEDIUM | Busy indicator shifts controls; status row collisions; red status for a missing origin (`DashboardStore.swift:316`, verified) | Fixed indicator slot, truncation, idle status omitted, red status suppressed |
| | MEDIUM | Thresholds, countdown and age formats, tooltip placement, height cap ambiguous | Fraction thresholds, every format case, tooltip placement, `maxHeight: 470` |
| | MEDIUM | No accessibility or keyboard behavior for the redesign | Accessibility section, `⌘,`, 22 pt pin target, `.subheadline` countdown |
| | LOW | Repeated "Show", state precedence, reset disabled state, origin-change behavior | Name as toggle label, combined state, disabled reset, overrides kept per origin |

Optional suggestions adopted: near-limit count, muted unpinned pins, providers with quotas
listed first in settings, header truncation priority.

## Remediation re-review

Target: `git diff fbdfbc0 733ab31` of the plan. Reviewer: AGY `gemini-4-neon-high`, effort high,
fresh context. Transcript in `reviews/uiux-plan-neon-r2/`. `git status` was clean after the run.
Earlier findings: 7 resolved, 3 partly resolved.

| Verdict | Severity | New finding | Verified | Disposition |
| --- | --- | --- | --- | --- |
| REQUEST_CHANGES | HIGH | One status line cannot hold summary, status, `N hidden` and `N near limit`; idle omission drops `Stale (cached)`; a button inside the combined status element breaks VoiceOver | Yes, `AisubdashMenuBarApp.swift:180-189` combines the status row; `Stale (cached)` at line 305 | Two status rows, `N hidden` outside the combined element, only normal `Ready` omitted |
| | MEDIUM | `Reset due` and badges keep orange text | Yes, badges at lines 397-406 | `.primary` text after a tinted named icon |
| | MEDIUM | Settings height, header rows, reset placement and footer unspecified | Plan text | Two header rows, reset outside the scroll area, `maxHeight: 340`, footer hidden |
| | MEDIUM | Missing-origin red status suppressed only in the list | Yes, `DashboardStore.swift:315-317` | Store leaves `status` idle; test added to the plan |
| | LOW | Label truncation priority, zero-limit and zero-hour formats, Unpin when the pinned quota is missing | Plan text | Specified; pinned owner parsed from the length-prefixed quota ID (`UsageModels.makeQuota`), verified by reading the decoder |

Review budget for this target (one round and one remediation re-review) is used. The
remaining changes were applied without a further review round; the owner decides whether
another round runs before implementation.
