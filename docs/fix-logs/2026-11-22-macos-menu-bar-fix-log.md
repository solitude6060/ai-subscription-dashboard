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
