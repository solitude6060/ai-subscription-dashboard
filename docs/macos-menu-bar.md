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
| **Tailscale** | Connect Tailscale on your Mac. Enter the origin of the existing Web backend and save it. For the direct port, use `http://100.x.y.z:6736` with your server's actual Tailscale IPv4 address. For Tailscale Serve, use your private `https://machine.tailnet.ts.net` origin, including its port if needed. | Reload reads the server's saved snapshots. Open Dashboard to run a provider refresh there. |
| **This Mac** | Install Bun and run the commands below on the Mac, in your own account. Keep the server process running while you use this source. | Fetch Provider Usage asks the loopback Bun server to update its enabled providers. Reload reads saved snapshots. |

A Tailscale URL contains only a scheme, address and optional port. Direct HTTP
supports Tailscale's IPv4 range. Connect through your trusted tailnet and use its
access rules to limit who can reach your Web server. The server's configured Host
allowlist must also accept the address used by the request. The app uses the system's
TLS verification for HTTPS. If macOS asks for Local Network access, enable it for
aisubdash in System Settings → Privacy & Security → Local Network.
[Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)

```sh
bun install --frozen-lockfile
bun run build:webui
OPENUSAGE_WEBUI_HOST=127.0.0.1 OPENUSAGE_WEBUI_PORT=6736 bun run start:webui
```

The Web build enables **Open Dashboard** for provider setup. The Mac's server stores
its own database and reads the existing CLI credentials available to its collectors.
Use Provider Accounts in the Web dashboard to configure additional supported CLI homes.
Some provider credentials stored exclusively in macOS Keychain may be unavailable.
The Bun plugin adapter's own credential store is
`~/.openusage-webui/plugins/<provider>/keychain.json`. Explicit provider refresh may
rotate credentials following the existing collector rules.
[Web dashboard and providers](../README_WEBUI.md)

## Read The Menu

Select one quota to pin it in the menu bar. The expanded panel shows the observation
time and the provider's reported reset time when available. Separate accounts
keep their own quota rows. A used quota of zero remains a reading. An unavailable
quota is labeled separately. The app shows the last successful reading in memory if
a connection fails, and marks old readings or readings past their reset time.
The selected source, endpoint and pin preference survive app restarts.

## Verify A Connection

With the backend running, inspect the read-only connection from the built app.
These commands print counts of enabled providers and quota rows.

```sh
"$HOME/Applications/aisubdash.app/Contents/MacOS/AisubdashMac" --probe-local
"$HOME/Applications/aisubdash.app/Contents/MacOS/AisubdashMac" --probe-tailscale "https://machine.tailnet.ts.net"
```

The Bun endpoints used by the client are `/api/providers` and
`/api/usage/latest-snapshots`. With This Mac selected, Fetch Provider Usage also uses
`POST /api/providers/refresh`.
[Native client plan and iOS roadmap](plans/2026-11-22-macos-menu-bar.md)
