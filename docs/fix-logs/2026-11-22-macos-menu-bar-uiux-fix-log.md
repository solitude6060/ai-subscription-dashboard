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

## Review remediation

[Implementation review](../reviews/2026-11-22-macos-menu-bar-uiux-impl-review.md)

| Finding | Change | Test | Files in `apps/macos` |
| --- | --- | --- | --- |
| 1. High — Switch alignment | Give the toggle label a full-width leading frame to align the switches at the trailing edge. | SwiftUI layout only. No unit test. Check switches with short and long provider names in the macOS panel. | `Sources/AisubdashMac/ProviderVisibilitySettings.swift` |
| 2. Medium — Provider state in VoiceOver | Include the provider name and state in the toggle's accessibility label and remove the state hint. | SwiftUI accessibility wiring. Check the toggle with VoiceOver hints disabled. | `Sources/AisubdashMac/ProviderVisibilitySettings.swift` |
| 3. Medium — Stale Tailscale validation error | Clear the panel's validation error when the draft or the selected source changes. | SwiftUI state wiring. Submit an invalid address, then verify that editing the draft clears the error. Repeat and switch sources to check that the error clears on return. | `Sources/AisubdashMac/MenuBarContentView.swift` |
| 4. Medium — Cached status appearance and alignment | Use an orange clock warning icon and primary text for `Stale (cached)`. Align status text to the leading edge when it stands alone and to the trailing edge when the near-limit count is present. | SwiftUI layout only. No unit test. Check lone status messages and wrapped status with a near-limit count. | `Sources/AisubdashMac/MenuBarContentView.swift` |
| 5. Medium — Capped list measurement | Use `VStack` inside both capped scroll views so the content size includes all rows. | SwiftUI layout only. No unit test. Open each list with a short provider list and with enough rows to scroll. | `Sources/AisubdashMac/MenuBarContentView.swift`, `Sources/AisubdashMac/ProviderVisibilitySettings.swift` |
| 6. Low — Initial loading state | Show `Loading usage…` in the list area while a request is active and the dashboard is absent. | SwiftUI presentation only. No unit test. Check the panel during the first load of a configured source. | `Sources/AisubdashMac/MenuBarContentView.swift` |
| 7. Low — Singular count wording | Format quota subtitles, the all-hidden message, and the hidden settings button's VoiceOver label using singular wording for a count of one. | `ProviderCountFormatterTests` covers counts of one and two for all three strings. | `Sources/AisubdashCore/ProviderCountFormatter.swift`, `Sources/AisubdashMac/ProviderVisibilitySettings.swift`, `Sources/AisubdashMac/MenuBarContentView.swift`, `Tests/AisubdashCoreTests/ProviderCountFormatterTests.swift` |
| 8. Low — Spoken reset countdown | Prefix the future countdown with `Resets` in the quota row's VoiceOver label. | `QuotaFormatterTests.testSpokenResetCountdownDescribesFutureReset` covers future, sub-minute, due, past, and missing reset times. The existing visual countdown assertions remain in place. | `Sources/AisubdashCore/QuotaFormatter.swift`, `Sources/AisubdashMac/AccountCardView.swift`, `Tests/AisubdashCoreTests/QuotaFormatterTests.swift` |

The four new test methods were committed before the fixes in `1e7fdad`. The focused
test command at that step and the full `swift test --package-path apps/macos` after
implementation both exited 1 during manifest compilation. XCTest ran no assertions
in either attempt. The suite has 43 declared test methods, including the existing 39.

`build-app.sh` exited 1 with the same manifest diagnostics. `codesign --verify --strict`
exited 1 with `No such file or directory` for `apps/macos/.build/app/aisubdash.app`.

```text
<unknown>:0: error: error opening '/Users/cyma/.cache/clang/ModuleCache/Swift-18Y2CYADWFGX0.swiftmodule' for output: /Users/cyma/.cache/clang/ModuleCache: Operation not permitted
<unknown>:0: error: unable to load standard library for target 'arm64-apple-macosx14.0'
```

Swift syntax parsing and `git diff --check` exited 0. The source scan for
`TimelineView`, `DisclosureGroup`, and `LazyVStack` found only the existing comment
at `Sources/AisubdashMac/AisubdashMenuBarApp.swift:59`. The panel and VoiceOver
checks are pending a successful macOS build.

## Owner feedback: account list height

Owner report on build `aisubdash-uiux-r2`: the account list needed constant scrolling.
The list was capped at 470 pt and the panel at 580 pt, about half of the owner's visible
screen height. Both caps now follow `NSScreen.main.visibleFrame.height` (list: minus 200 pt,
panel: minus 40 pt; 800 pt when no screen is reported). The settings list keeps 340 pt.
Layout only, no unit test: the value depends on the attached display. Checked by build and
on the owner Mac. Files: `Sources/AisubdashMac/MenuBarContentView.swift`, the plan.

Follow-up (build `aisubdash-uiux-r4`): the screen-relative cap alone did not grow the list,
because the `ScrollView` reports almost no ideal height in the panel. The card stack's
height is now measured with `onGeometryChange` and the scroll area is sized to
`min(measured, visible screen height - 200 pt)`, so cards that fit show without
scrolling. 43 tests pass; build and codesign pass. Owner panel check pending.

## Drag to reorder

Plan: `docs/plans/2026-11-22-macos-menu-bar-reorder.md` (review record with APPROVE:
`docs/reviews/2026-11-22-macos-menu-bar-reorder-plan-review.md`). Routing: the planned
implementer Codex `gpt-6.2-sol` (high) had exhausted its quota and no second Codex home
exists on this Mac, so the registry's Codex quota fallback applied: Claude Opus 5.5
(medium). Each test commit failed on XCTest assertions before its implementation commit.

| Group | Change | Tests (`Tests/AisubdashCoreTests/DashboardOrderTests.swift`) | Files in `apps/macos` | Commits |
| --- | --- | --- | --- | --- |
| Saved order | `orderByOrigin` preference (key `aisubdash.orderByOrigin`), loaded per origin with pins and overrides. `orderedAccounts`: saved IDs in saved order, then the rest in server order. `visibleAccounts` filters it. | Server order without a saved order; saved order applied, unknown IDs ignored and kept in storage, new accounts appended. | `Sources/AisubdashCore/DashboardStore.swift` | Test `5501aeb`, implementation `b0f815f` |
| Moves | `moveAccount(_:onto:)` on the merged working list (stored IDs, deduplicated, then current IDs not stored); `AccountMoveDirection` and `moveAccount(_:_:)` past the nearest visible neighbour. | Down and up drops; hidden account between keeps its place; absent saved ID survives; unknown, hidden, equal and quota IDs rejected without saving; direction skips hidden neighbours, false at the ends and for hidden or unknown IDs; no endpoint; pin and visibility unchanged. | `Sources/AisubdashCore/DashboardStore.swift` | Test `4d0b06b`, implementation `5293f7e` |
| Per-source order and reset | `hasCustomOrder`, `resetAccountOrder()` for the selected origin only. | Order per origin and across a new store; reset clears only the selected origin and leaves overrides; visibility reset leaves the order; Tailscale origin change keeps the previous order; `hasCustomOrder` per origin. | `Sources/AisubdashCore/DashboardStore.swift` | Test `f702c63`, implementation `65a0b04` |
| Panel and settings | Drag handle (two or more visible cards), `.draggable` with a name preview, card `.dropDestination(for: String.self)` with an accent `strokeBorder` while targeted, VoiceOver Move Up/Move Down on the header element, `Reset Order` in settings, user guide section. | No unit test: XCTest cannot host the panel. Owner check on the Mac. | `Sources/AisubdashMac/AccountCardView.swift`, `Sources/AisubdashMac/MenuBarContentView.swift`, `Sources/AisubdashMac/ProviderVisibilitySettings.swift`, `docs/macos-menu-bar.md` | `a54efd0` |

`swift test --package-path apps/macos`: 56 tests, 0 failures (43 existing plus 13 new).
`build-app.sh "$HOME/Applications/aisubdash-reorder-r1"` built and signed the arm64 app;
`codesign --verify --strict` exited 0. The source scan for `TimelineView`,
`DisclosureGroup` and `LazyVStack` found only the comment at
`Sources/AisubdashMac/AisubdashMenuBarApp.swift:59`. The account list height logic in
`MenuBarContentView.swift` is unchanged. Owner panel checks are pending.

Owner check of drag to reorder on build `aisubdash-reorder-r3` (HEAD `b89e8af`),
2026-11-23: dragging works.

## Panel window does not shrink after a source switch

Owner report (2026-11-22): with Tailscale selected, choosing This Mac leaves the panel
content in the middle of the screen.

Observation, from window-frame logging in a temporary build (not committed): the panel
window grew from 535 pt to 977 pt when the list went from 4 to 8 cards and stayed at
977 pt after the list returned to 4 cards. No resize notification followed a decrease
in content height. The content is centred in the taller window.

| Check (temporary builds, owner opened the panel, heights logged) | Result |
| --- | --- |
| Minimal apps `M` (list sized to content), `N` (fixed 600 pt), `O` (list and `ContentUnavailableView`), owner visual check | No displacement reported |
| `.fixedSize(horizontal: false, vertical: true)` on the account section, then on the panel in place of `.frame(maxHeight:)` | Window still does not shrink |
| Minimal app `Q`, seven variants (root `fixedSize`, `NSViewRepresentable` background, segmented picker and shortcut button, dividers and `layoutPriority`, asynchronous status row, all combined) | Window shrinks in all seven (for example 650 pt to 178 pt) |
| App with the panel content reduced in nine steps, from a list of plain boxes to the full panel | Window shrinks in none |
| App with a static menu bar label and a list of plain boxes driven by a local flag | Window does not shrink |
| `otool -l`: `Q` built with `swiftc` records `minos 27.2`, `sdk 27.2`; the app built with SwiftPM records `minos 14.0`, `sdk 14.0` (debug and release) | Difference found |
| The same app executable with only the recorded SDK changed to 27.2 (`vtool -set-build-version macos 14.0 27.2`), re-signed | Window shrinks in all five logged cases (844 pt to 444 pt) |

Cause: the executable records SDK 14.0. On macOS 27.2.1 the `MenuBarExtra(.window)`
panel of such an executable keeps its largest height. Why SwiftPM (Swift 6.4.2,
`swiftbuild` engine) records the deployment target as the SDK version is not determined;
`swiftc` with the same `-target arm64-apple-macos14.0` and `-sdk` flags records 27.2.

| Change | Check | File | Commits |
| --- | --- | --- | --- |
| `build-app.sh` passes `-Xlinker -platform_version -Xlinker macos -Xlinker <LSMinimumSystemVersion> -Xlinker <xcrun SDK version>` and exits 1 when the recorded SDK differs from the build SDK. | The check alone fails with `executable records SDK '14.0', expected the build SDK 27.2`; with the linker flags the script passes and `otool` shows `sdk 27.2`. | `apps/macos/build-app.sh` | Test `713bc3a`, fix `866fba3` |

No Swift source changed. `swift test`: 56 tests, 0 failures; `codesign --verify --strict`
passes on `~/Applications/aisubdash-sdkfix-r1`. Not verified: the linker flag on the CI
runner (`macos-15`), which uses a different toolchain; the script's SDK check runs there.
Owner check of `aisubdash-sdkfix-r1` (2026-11-25): the owner was asked to switch between
Tailscale and This Mac, open the settings page and drag to reorder, and reported the build
as working. Not reported on: order persistence across a restart, Reset Order, VoiceOver
Move Up/Down.
