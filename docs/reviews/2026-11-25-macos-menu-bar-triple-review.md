# Triple review of pull requests 69 and 71

Date: 2026-11-25. Orchestrator: Claude Code (Fable 5.2). The reviewers ran in separate
read-only sessions on a checkout at `ef82ff1`.

| Target | Diff | Head |
| --- | --- | --- |
| A, pull request 69 (fixes after the approved revision) | `c90464c..45eb3f6` | `45eb3f6ff15e97bd4d8e33e31e5ef94d16f503c3` |
| B, pull request 71 | `45eb3f6..ef82ff1` | `ef82ff1b6fcbeff22a647276bdbe1efda4546e68` |

## Verdicts

| Lane | Client and model | Effort | Target A | Target B |
| --- | --- | --- | --- | --- |
| 1 | Grok Build `grok-4.7` (stream reports `grok-4.7-build`) | xhigh | APPROVE, no findings | APPROVE, no findings |
| 2 | AGY `gemini-4-neon-high` | high | APPROVE, 1 LOW | REQUEST_CHANGES |
| 3 | Codex `gpt-6.2-sol` | high | REQUEST_CHANGES | REQUEST_CHANGES |

Lane 1, first attempt: the run ended with `stopReason: cancelled` and no verdict after the
reviewer requested a shell command (`xcrun`) that a headless run cannot approve. One retry
with the same model and effort, and a prompt that limits tools to file reads and
`git diff`, `git show`, `git log`, returned the verdict above.

Lane 2 limit: the routing registry runs AGY inside a `bwrap` read-only mount. `bwrap` is not
available on macOS, so the lane ran without it. After the run `git status` was clean and
`HEAD` was `ef82ff1`.

Prompt, commands, raw output and extracted verdicts are retained locally in the sibling
artifacts directory (`reviews/pr69-pr71-triple-r1/`).

## Findings and triage

Each finding was checked against the cited code.

| ID | Target | Source | Severity | Finding | Verified | Disposition |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | A | Sol | MEDIUM | After a failed refresh the decoder drops `lastRefreshAt` and dates a MiniMax reading by the quota window start (`UsageModels.swift`, `UsageContractDecoder.decode`); the server overwrites `lastRefreshAt` on failure (`apps/server/src/index.ts`). | Yes | Repair: the backend records `lastSuccessAt`; the client uses it when present. |
| F2 | B | Sol | MEDIUM | `DashboardStore.updateTailscaleOrigin` removes the previous origin's pin. Present since pull request 69 and deferred as finding 4 of the owner-Mac review. | Yes | Repair (owner decision, 2026-11-25): keep the pin entry. |
| F3 | B | Sol | MEDIUM | The quota card uses `compactValue`, which prints only the amount used for dollar quotas; the limit is absent from the card and its VoiceOver label (`AccountCardView.swift:150`). | Yes | Repair: card value with used and limit. |
| F4 | B | Sol, Neon | MEDIUM | `build-app.sh:51`: `awk` exits on the first match; under `set -euo pipefail` `otool` can end with SIGPIPE and abort the script. `found` is not reset per load command. | Yes (by reading; not reproduced) | Repair: read to end of input, reset per load command. |
| F5 | B | Sol, Neon | LOW | `build-app.sh:29,52`: SDK versions are compared as strings; `15.0` and `15.0.0` differ. | Yes | Repair: normalise both sides. |
| F6 | B | Sol | LOW | `docs/macos-menu-bar.md` names the Command Line Tools as sufficient; the macOS 27.2 SDK build needs full Xcode (owner-Mac review). | Yes | Repair: documentation. |
| F7 | B | Neon | LOW | `QuotaFormatter.compactValue` has no unit test. | Yes | Repair: tests, with F3. |
| F8 | B | Neon | LOW | The list height cap (`screenHeight - 200`) leaves about 38 pt for status rows inside the panel cap, and `screenHeight` reads `NSScreen.main`. | Arithmetic not re-derived; `NSScreen.main` use confirmed | Deferred: the owner checked this sizing on 2026-11-25; a change needs a new owner check. Follow-up. |
| F9 | A | Neon | LOW | The expand chevron in `AccountRowView` is not hidden from VoiceOver. | Yes at `45eb3f6` | No action: target B removes `AccountRowView`, and both targets merge together. |

Not verified by any lane: the `-platform_version` linker flag on the CI runner (`macos-15`).
Pull request 71 now targets `main`, so the macOS workflow runs on its next push.

The repairs land on the branch of pull request 71, which contains pull request 69. The
remediation diff is re-reviewed by the same three lanes.
