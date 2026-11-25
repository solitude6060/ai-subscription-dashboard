# aisubdash for macOS

aisubdash displays subscription quotas in the macOS menu bar. It reads the same data
as the Web dashboard and uses the tool credentials already available to the selected
backend. The menu app has its own bundle identity and needs no aisubdash account.

## Build And Open

On macOS 14 or later, install the Xcode Command Line Tools if `swift --version` is
unavailable. Run these commands from the repository root.

```sh
bash apps/macos/build-app.sh "$HOME/Applications"
open "$HOME/Applications/aisubdash.app"
```

The script builds for the architecture of that Mac and signs the bundle for local use.
Use a clean output directory when building an update. The app stays in the menu bar. To start it at login, add
it in System Settings under General → Login Items.

## Choose A Source

| Source | Setup | Updates |
| --- | --- | --- |
| **Tailscale** | Connect Tailscale on your Mac. Open **Settings** in the panel, enter the address of the existing Web backend, and select **Apply**. For the direct port, use `http://100.x.y.z:6736` with your server's actual Tailscale IPv4 address. For Tailscale Serve, use your private `https://machine.tailnet.ts.net` origin, including its port if needed. | Reload reads the server's saved snapshots. Select **Dashboard** to run a provider refresh there. |
| **This Mac** | Install Bun and run the commands below on the Mac, in your own account. Keep the server process running while you use this source. | **Fetch Usage** asks the local Bun server to update its enabled providers. Reload reads saved snapshots. |

A Tailscale URL contains only a scheme, address and optional port. Direct HTTP
supports Tailscale's IPv4 range. Connect through your trusted tailnet and use its
access rules to limit who can reach your Web server. The server's configured Host
allowlist must also accept the address used by the request. The app uses the system's
TLS verification for HTTPS and connects to the configured usage origin directly. If
macOS asks for Local Network access, enable it for
aisubdash in System Settings → Privacy & Security → Local Network.
[Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)

```sh
bun install --frozen-lockfile
bun run build:webui
OPENUSAGE_WEBUI_HOST=127.0.0.1 OPENUSAGE_WEBUI_PORT=6736 bun run start:webui
```

The Web build enables **Dashboard** for provider setup. The Mac's server stores
its own database and reads the existing CLI credentials available to its collectors.
Use Provider Accounts in the Web dashboard to configure additional supported CLI homes.
Some provider credentials stored exclusively in macOS Keychain may be unavailable.
The Bun plugin adapter's own credential store is
`~/.openusage-webui/plugins/<provider>/keychain.json`. Explicit provider refresh may
rotate credentials following the existing collector rules.
[Web dashboard and providers](../README_WEBUI.md)

## Read The Menu

The panel shows each visible provider account and all its quotas. Each quota shows
usage and a reset countdown when available. Dollar quotas show both the amount used
and the limit. Hover over the countdown for the exact reset time. The account
header shows how long ago the reading was taken and marks
stale readings or refresh failures. Reading age uses the later of the snapshot start
and the last successful refresh when the backend reports it. On older backends, a
failed refresh leaves the age based on the snapshot start. If a connection fails,
the panel can still show the last successful reading from this app session.

Select the pin next to a quota to show its value in the menu bar. Hiding that
provider keeps the pin active. To remove it, select **Unpin** next to the quota or
in **Settings**. If the pinned quota is missing, the usage panel also offers
**Unpin** next to the warning. Your selected source, Tailscale address, and pin
preference are saved across app restarts. Each Tailscale address keeps its own
pin, which returns when you switch back or re-enter the address after clearing it.

## Reorder Providers

When two or more providers are visible, drag a card by the handle at the left of
its header and drop it on another card. A card dragged down lands after the card
you drop it on, and a card dragged up lands before it. With VoiceOver, use the
**Move Up** and **Move Down** actions on the provider header. The app remembers
the order separately for This Mac and for each Tailscale address, including after
an app restart. A provider that disappears keeps its place if it returns, and a
new provider appears after the ordered ones. **Reset Order** in **Settings**
restores the server order for the selected source and keeps your visibility
choices.

## Choose Which Providers Appear

Select the gear, press **Command–Comma**, or select the hidden provider count to
open **Settings**. Choose **This Mac** or **Tailscale** to manage that source.
Providers with reported quotas appear automatically, including quotas with zero
usage. Use the switches to show a provider with no reported quota or hide a
provider you do not want in the usage list.

**Reset to automatic** restores the default for the selected source. The app
remembers visibility choices separately for This Mac and for each Tailscale
address, including after an app restart. Select **Back** to return to the usage
list. Closing the panel also returns it to the usage list when you reopen it.

## Verify A Connection

With the backend running, inspect the read-only connection from the built app.
These commands print counts of enabled providers and quota rows.

```sh
"$HOME/Applications/aisubdash.app/Contents/MacOS/AisubdashMac" --probe-local
"$HOME/Applications/aisubdash.app/Contents/MacOS/AisubdashMac" --probe-tailscale "https://machine.tailnet.ts.net"
```

The Bun endpoints used by the client are `/api/providers` and
`/api/usage/latest-snapshots`. With This Mac selected, **Fetch Usage** also uses
`POST /api/providers/refresh`.
[Native client plan and iOS roadmap](plans/2026-11-22-macos-menu-bar.md)

For the first physical Mac acceptance pass, follow the
[Mac verification handover](handovers/2026-11-22-macos-owner-verification.md).
