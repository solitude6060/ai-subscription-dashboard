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
