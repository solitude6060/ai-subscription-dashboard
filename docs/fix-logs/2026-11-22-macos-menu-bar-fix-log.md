# macOS menu bar review fixes

See the [initial review](../reviews/2026-11-22-macos-menu-bar-review.md) for the target
and triage.

| Verified finding | Test and repair |
| --- | --- |
| Cocoa arguments stopped startup | Added an executable-target test. Ordinary arguments return to the synchronous SwiftUI startup path. Two dedicated probe flags take the async CLI path. |
| Cancelled reads marked a healthy source stale | Added a controlled asynchronous cancellation test. Preserve the last successful reading and return to idle after cancellation. |
| Pin shown as missing before the source loads | Added a test for a persisted pin with no loaded source. Report unavailable until a successful read. |
| Shared session timeouts and proxy defaults | Added a configuration test. Reads and explicit refreshes use their own request and resource bounds. Session settings disable HTTP, HTTPS, SOCKS and automatic proxy routing for the configured private origins. |
| Signed GUI startup and bundle checks | The macOS job asserts the native architecture and both ATS exception entries, runs the actual signed executable against each alias, and starts the GUI with a Cocoa launch argument against the loopback fixture. |
| Incorrect Tailscale example and fractional progress scaling | Use a valid Tailscale hostname and the validated quota limit. |

The Linux regression suite reproduced six failed assertions in four behavior tests
before the repairs. The repaired suite passed 23 tests. A hosted process-start check
exercises the GUI entry point. Interaction with the system menu bar and already
authenticated provider accounts still requires the target Mac.

## Owner-Mac review, finding 1

See the [owner-Mac review](../reviews/2026-11-22-macos-menu-bar-owner-mac-review.md).

| Verified finding | Test and repair |
| --- | --- |
| MiniMax readings marked stale one hour into each quota window | `testObservedAtUsesSuccessfulRefreshTimeWhenSnapshotStartsAtWindowStart` failed with 05:00:00 observed against an expected 06:18:52 refresh. `UsageContractDecoder` now uses the later of snapshot `startedAt` and provider `lastRefreshAt` when `lastError` is absent. A failed refresh keeps the snapshot time because the server also writes `lastRefreshAt` on failure (`apps/server/src/index.ts`). The macOS suite passes 24 tests. Files: `UsageModels.swift`, `UsageContractTests.swift`. |

## Owner-Mac verification, missing menu bar icon

| Verified finding | Evidence and repair |
| --- | --- |
| The menu bar icon did not appear on macOS 27.2.1 although the GUI process ran | Minimal MenuBarExtra apps on the owner's Mac, one variable each: plain `Image`, `HStack` with `Text`, and `.menuBarExtraStyle(.window)` labels appeared; a `TimelineView` label did not. Removed the `TimelineView` from `MenuBarLabelView`; the label re-evaluates on observable store changes, at least once per 60-second poll. The owner confirmed the rebuilt icon. No unit test: XCTest has no system menu bar. The hosted GUI smoke check verifies process start only and cannot detect this. File: `AisubdashMenuBarApp.swift`. |

## Owner-Mac finding 11 re-review and finding 12

| Verified finding | Test and repair |
| --- | --- |
| An identical reload sends no Observation notification, so `(Stale)` could stay absent (Codex re-review of finding 11) | `testClockTickNotifiesObserversAndAgesAnUnchangedPinnedReading` failed on its assertion with a no-op `tick`. `DashboardStore.clock` and `tick(now:)` added; the app ticks every 30 s and the label and panel render against the clock; the panel `TimelineView` is removed. Commits `76de4b6`, `ef3515b`. |
| Account rows did not expand in either source | Minimal `.window` MenuBarExtra apps: `DisclosureGroup` did not expand with `@State`, a `@State` dictionary binding, or inside a `TimelineView`; a `Button` toggling `@State` or an `@Observable` property did. Replaced `DisclosureGroup` with a chevron button. Owner confirmed expansion in both sources. No unit test: XCTest has no MenuBarExtra panel. |

The macOS suite passes 25 tests.
