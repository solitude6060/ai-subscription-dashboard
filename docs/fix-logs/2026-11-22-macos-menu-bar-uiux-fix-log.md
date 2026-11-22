# macOS Menu Bar Panel Implementation Log

[Implementation plan](../plans/2026-11-22-macos-menu-bar-uiux.md) · [Plan review](../reviews/2026-11-22-macos-menu-bar-uiux-plan-review.md) · [User guide](../macos-menu-bar.md)

## Test Groups

| Group | Scenarios | Implementation | Commits |
| --- | --- | --- | --- |
| Quota formatting | Countdown and reading age for missing dates, sub-minute intervals, minutes, hours, and days. Reset at or before the store clock. Fractions outside the allowed range and nonpositive limits. Warning and critical thresholds across percent, count, and USD quotas. | Moved formatting into `AisubdashCore/QuotaFormatter.swift`. The panel uses the same fraction and thresholds as the near-limit count. | Test `6c749e1`, implementation `9259719` |
| Visibility and pin ownership | Default visibility, forced show and hide, exact account IDs, server order, source and origin isolation, persistence, selected-source reset, absent providers, visible-list counts, and pinned readings for hidden accounts. Missing quota ownership and UTF-8 byte-length parsing from decoded quota IDs, including malformed IDs. | Added visibility overrides to `DashboardStore.swift` and both preferences implementations. Filtered the panel list while retaining the loaded dashboard for pins. Added the decoder-compatible ID parser to `UsageModels.swift`. | Test `640c460`, implementation `107abe1` |
| Tailscale without a valid origin | Reload with an empty or invalid saved origin stays idle, leaves the dashboard empty, and issues no request. | Changed the missing-endpoint branch of `DashboardStore.performGet` to set `.idle`. | Test `05a8df3`, implementation `5ad0522` |
| Existing suite | The 25 baseline test methods and assertions remain in place. The suite now contains 39 declared test methods. | Added 14 test methods across the three groups. | See the test commits above. |

Each focused test command was attempted before and after its implementation. SwiftPM
failed while compiling the package manifest in all six runs. Neither the expected
assertion failures nor a passing run could be observed.

## Acceptance Checks

The app build was attempted at `dbe5c50`, which contains the panel, settings, and
accessibility changes.

| Check | Result |
| --- | --- |
| `swift test --package-path apps/macos` | Exit 1 during manifest compilation. XCTest did not start. |
| `bash apps/macos/build-app.sh "$PWD/apps/macos/.build/app"` | Exit 1 during manifest compilation. |
| `codesign --verify --strict "$PWD/apps/macos/.build/app/aisubdash.app"` | Exit 1 with `No such file or directory` for the bundle. |
| `grep -rn "TimelineView\|DisclosureGroup" apps/macos/Sources` | One match, a historical comment at `AisubdashMenuBarApp.swift:59`. |
| Swift syntax parsing and `git diff --check` | Both exited 0. |

The test and bundle commands produced the same blocking diagnostics.

```text
<unknown>:0: error: error opening '/Users/cyma/.cache/clang/ModuleCache/Swift-18Y2CYADWFGX0.swiftmodule' for output: /Users/cyma/.cache/clang/ModuleCache: Operation not permitted
<unknown>:0: error: unable to load standard library for target 'arm64-apple-macosx14.0'
```

## Owner Mac Check

Pending a successful build of `dbe5c50` or a descendant. Open the panel with
both sources and confirm that quotas are visible on their account cards, the reset
tooltip shows the absolute time, and the panel scrolls while the status and footer
stay visible. Open Settings with the gear, Command–Comma, and the hidden provider
count. Check visibility overrides and automatic reset separately for each source,
including a hidden pinned provider and a missing pinned quota. Close and reopen
the panel from Settings and confirm that it returns to the quota list. With
VoiceOver, check that each quota is read as one element with a separate pin control
and that the account name, badges, and reading age are announced together.

The panel also observes its hosting window's visibility to reset Settings when the
window is hidden. [AppKit window occlusion notification](https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification)

## Open Plan Questions

None.
