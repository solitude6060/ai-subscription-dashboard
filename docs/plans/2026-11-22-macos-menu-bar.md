# Native macOS Menu Bar and iOS Widget Roadmap

## Scope and baseline

Build a personal aisubdash menu-bar application with two explicitly selected sources: the
existing Web backend through Tailscale and the same Bun backend on the Mac's loopback
interface. The application has its own name and bundle identity. No account in aisubdash or
OpenUsage is required. Local collectors still use their own existing provider credentials.
The iOS Home Screen widget is a follow-up design.

The integration base and the recorded live checkout both resolve to
`8b08db8ade55e7ddcd153a84aac6cb0d91542890`. The old Swift upstream reference is
`robinebers/openusage@bb7de176def23a99bbdcaabe1ac7269f18c738be`, MIT. No upstream
Swift or UI assets are imported. Keep the fork's existing MIT license. The current upstream
documents account enrollment through `ProviderLogin` and account-scoped refresh. The
fork's collectors remain the current source of the readings.
[Current upstream architecture](https://github.com/robinebers/openusage/blob/main/AGENTS.md)

## Decision and evidence

Use a SwiftUI `MenuBarExtra` with window style and a native status item label. Build an ad
hoc-signed personal `.app` from Swift Package Manager, keep shared decoding and HTTP
logic independent of SwiftUI, and run native tests plus bundle creation on a macOS
runner. The local build uses the Mac's own architecture. Publish the architecture of
any downloaded test artifact. Set `LSUIElement` and use an aisubdash-specific identifier. Target macOS 14
or later. Apple documents the menu-bar scene and Dock-free flag.
[Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra.md)

Keep the existing server, collectors, and storage. The product needs a glanceable reading
from a selected machine. Both machines can answer the existing two GET requests with
the same schema. A 2026-11-22 read-only probe of the existing direct Tailnet endpoint
returned health OK and 12 snapshots with both plugin and quota shapes. Reusing the
Web service avoids a second provider implementation and preserves multi-account IDs.
If the Mac collector lacks a compatible existing credential, show that account's data as
unavailable and document the collector limitation.

Use CodexBar's compact quota indicator and Usagebar's short-window/reset pairing as
interaction references. Use aisubdash's own layout: one optional pinned quota in the
system bar, then a panel with source controls, source/status text, and compact account
rows with expandable details. The current upstream's separate account enrollment is the
workflow this client removes.
[CodexBar UI documentation](https://github.com/steipete/CodexBar/blob/main/docs/ui.md)
[Usagebar product demo](https://usagebar.com/)

## Source and request contract

- **This Mac** is fixed to `http://127.0.0.1:6736`. Start the existing server from the
  repository with `OPENUSAGE_WEBUI_HOST=127.0.0.1 OPENUSAGE_WEBUI_PORT=6736 bun run start:webui`. The user can keep it running independently.
  The menu app neither owns nor starts the server process. Keep source-specific data
  and configuration on their own machines. The Bun adapter's Keychain implementation
  is a private JSON shim at `~/.openusage-webui/plugins/<provider>/keychain.json`
  with mode `0600`. Existing macOS Keychain-only credentials may remain unreadable.
  A manual provider refresh can rotate credentials under the existing collector rules. Verify
  an actual supported Codex CLI account on the Mac without copying credential material.
- **Tailscale** takes an explicit origin. Accept HTTPS to a full `.ts.net` hostname and
  direct HTTP to a numeric `100.64.0.0/10` address so the existing service keeps working.
  Keep system TLS verification. In the bundle, set `NSExceptionAllowsInsecureHTTPLoads`
  for exactly `127.0.0.1` and `100.64.0.0/10` via `NSExceptionDomains`. Apple
  documents IP and CIDR keys from macOS 14. In native CI test both addresses, including
  a synthetic Tailscale-range IPv4 alias on loopback. Route true Tailscale traffic through
  your connected device. IPv6 direct HTTP is outside this slice. Reject userinfo, query, fragment, non-root paths, other hosts, and
  redirects. Tailscale network grants and host firewall enforce access; the Bun Host
  allowlist is a separate validation step. Prefer a private HTTPS Serve origin if one
  already exists. A future Serve deployment must verify the forwarded Host and its port
  with the existing allowlist. Production mapping and firewall changes are separate.
  [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve)
  [Apple ATS exceptions](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptiondomains.md)
- Read `GET /api/providers` and `GET /api/usage/latest-snapshots`. Join by exact
  `providerId`, including account suffixes, and show enabled providers. Preserve zero
  as a valid reading. Use snapshot `startedAt` for data freshness. Status
  `lastRefreshAt` can advance after a failed provider refresh. Show unavailable providers
  without an invented zero. Decode typed progress rows and MiniMax's `raw.quota`
  shape. Preserve reset times and support percent, currency and count semantics.
  Ignore unsupported optional rows independently. Provider refresh failures update status
  without adding a usage record (server `runProviderRefresh`). Do not persist or show raw JSON,
  backend error strings, local paths, or provider secrets.
- On launch, source change, and periodically, GET the selected source. Reload also
  requests GET. For this Mac, provide an explicit provider refresh action through
  `POST /api/providers/refresh` and check the response's per-provider outcomes before
  fetching snapshots again. Give this explicit request a longer bounded timeout than a
  GET and never automatically retry it. The Bun server coalesces concurrent full refreshes
  in one process. The tailnet client only reads snapshots. Existing Web auto-refresh
  runs while the dashboard is open. Use Open Dashboard to refresh the remote collector if
  its stored reading is old. Local refresh uses the existing API on loopback. The app
  adds no listener and makes no changes to the existing Web API or browser policy. Keep the last good result for each
  origin in memory after connection failures, flag it as stale, and guard all results, loading state and POST-to-GET continuation
  on the main actor with the captured source and request generation. This covers overlapping requests
  and returning to an earlier origin before its older request completes. Persist only selected
  source, configured endpoint and pin preference. Display the absolute observation
  timestamp and reset status with a refresh indicator. Missing or stale pin values
  must be visibly distinguishable. Use a one-hour age threshold and the past reset
  timestamp to flag an outdated reading even when transport is healthy.
- Use an ephemeral URLSession without cookie, credential or response cache storage. Validate endpoints
  at the actual request boundary and use generic network error messages. Provide
  keyboard-accessible controls, labeled progress values and text status in addition to
  color. Include Reload, Open Dashboard, inline settings/source selection, and Quit. Build locally for personal installation.

## Work and exit criteria

| Work | Files and deliverables | Exit criteria |
| --- | --- | --- |
| Contract and review | This plan and local records | Sol draft, Astra advisory and independent Opus verdict tied to the plan hash. |
| Native client TDD | `apps/macos/Package.swift`, Swift sources, tests and synthetic fixtures | Record a failing behavior assertion before the production implementation. Prove endpoint validation, shape tolerance, per-account mapping, zero/missing, pin and date semantics, failure state, and isolation on source changes. |
| Personal build and setup | `apps/macos/Info.plist`, bundle script, macOS CI job, `docs/macos-menu-bar.md`, README links | A clean macOS runner builds and validates the signature, architecture and Info.plist, and exercises HTTP with synthetic data on loopback and an aliased Tailscale-range address through the signed app's `--probe-local` and `--probe-tailscale URL` modes. These read with the normal client, print only aggregate counts and exit with status. Document per-user startup, existing Tailnet access, Homebrew/Bun prerequisites, Mac provider limitations and UI actions. |
| Verification and delivery | Review and fix log, PR, local verification evidence | Verify the new native client against synthetic Bun responses and exercise local server start, GET and explicit provider refresh. Exercise the pre-existing Web build and test commands. Probe the existing Tailnet endpoint read-only. Validate the app on an accessible Mac for menu bar, source switch and real local credentials. Sonnet code review plus the configured three-family review bind the PR revision before merge. |

A hosted runner can compile and execute the tests using synthetic data. Record separately
the native bundle, response contract, live Tailnet and Mac GUI/live-collector checks.
Keep account names, hostnames, IP addresses and actual usage out of the public PR.
Passing hosted tests and read-only probes leaves the real-Mac GUI and provider checks open until an owner-authorized Mac environment is accessible. The 2026-11-22 known-host
SSH probe reached an owned online Mac, and its current key rejected the login.
Review and test logs stay in the persistent local artifact directory.

## iOS follow-up

Start with a SwiftUI host app pointing at the existing private HTTPS tailnet origin,
then a WidgetKit Home Screen widget with selected quota, reset and observation date.
Reuse the Foundation contract when implementation starts. An App Group lets the host
and widget read the same minimal last-good snapshot. Validate signing and provisioning
on the actual development team and device before choosing this arrangement. A free
Xcode Personal Team provisions device apps for seven days at a time. Treat WidgetKit
timeline updates as best effort and show reading age when the network or VPN is
unavailable. Test the transition from connected to disconnected on a physical iPhone.
iPhone loopback refers to the iPhone itself. Connecting it to Mac data would require a
separate, deliberately shared tailnet endpoint from that Mac.
[Apple widgets and timelines](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)
[Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups.md)
[Apple Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account)
