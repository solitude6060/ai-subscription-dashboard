# macOS Menu Bar Handover

## Starting Point

Use branch `feat/macos-menu-bar` for [draft PR #69](https://github.com/solitude6060/ai-subscription-dashboard/pull/69).
The approved implementation is `a10b2d7117a6a1a141bbcf69f2cdc9b88a09259c`.
Sonnet approved it, and Opus, Neon, and Sol approved it in independent reviews.
Sol filled the Grok review lane after two timeouts. The prior
[macOS CI run](https://github.com/solitude6060/ai-subscription-dashboard/actions/runs/44940969500)
passed 23 Swift tests, checked the signed Apple Silicon bundle, started the GUI
process, and read synthetic data through both source modes. The existing Linux Web
build and its 634 Bun tests also passed.

The remaining milestone is physical verification of the menu bar, the actual
Tailscale URL, and an existing provider login on the Mac. Use your normal macOS
user in a graphical session. The output of the signed probes is an additional
connection check. Use the menu itself to verify the interaction.

## Clone And Build On The Mac

Prerequisites are macOS 14 or later, Swift through Xcode or the Command Line Tools,
and Tailscale for the remote source. Install Bun for the local source. Prefer the
CI-tested Bun version `1.4.5` when reproducing a difference.

From a persistent directory such as `~/Projects` with a free
`ai-subscription-dashboard` checkout name, run:

```sh
git clone --branch feat/macos-menu-bar https://github.com/solitude6060/ai-subscription-dashboard.git
cd ai-subscription-dashboard
git rev-parse --short HEAD
git diff --exit-code a10b2d71 HEAD -- apps/macos .github/workflows/macos.yml
sw_vers -productVersion
uname -m
swift --version
swift test --package-path apps/macos
bash apps/macos/build-app.sh "$HOME/Applications/aisubdash-pr69"
app="$HOME/Applications/aisubdash-pr69/aisubdash.app"
codesign --verify --strict "$app"
open "$app"
```

If the checkout already exists, fetch and switch to the feature branch. Keep
existing uncommitted changes. Pick a new output directory for a repeat build when
the app bundle path is already occupied.

## Verify On The Mac

1. **Menu bar and pin.** Confirm the aisubdash icon appears in the macOS menu bar.
   Click it and confirm the panel opens and responds to source selection. Once a
   quota loads, pin it and compare its menu-bar value to the panel. Reopen the app
   and confirm it restores the source and the pin once that source loads.
2. **Actual Tailscale backend.** Connect Tailscale, select **Tailscale**, and apply
   your existing dashboard origin, including its port when applicable. Use your
   current `http://100.x.y.z:6736` or private `https://machine.tailnet.ts.net`
   origin. Click **Reload** and compare a known account's quota, observation time,
   and reset time to **Open Dashboard**. If macOS prompts, grant aisubdash Local
   Network access. To check the signed app's connection separately, run the command
   below with your existing origin substituted.
3. **Actual Mac-local provider.** In another terminal at the checkout root, use
   the same macOS account that already uses the provider CLI. Start the local Bun
   backend with the command below. In the menu, select **This Mac** and click
   **Fetch Provider Usage**. Verify one account with a supported credential source,
   such as Codex with file-based CLI credentials. Confirm its quota and observation
   time appear and match the local dashboard. Switch between **Tailscale** and
   **This Mac** and confirm each source shows its own rows and pin. Some accounts
   whose credentials reside exclusively in the system Keychain may need separate
   support in the existing Bun collector.

```sh
# Existing Tailscale origin, in the first terminal.
"$app/Contents/MacOS/AisubdashMac" --probe-tailscale "https://machine.tailnet.ts.net"
```

```sh
# Mac-local backend, in the second terminal.
bun --version
bun install --frozen-lockfile
bun run build:webui
OPENUSAGE_WEBUI_HOST=127.0.0.1 OPENUSAGE_WEBUI_PORT=6736 bun run start:webui
```

```sh
# Mac-local check, while the backend is running.
curl -fsS http://127.0.0.1:6736/api/health >/dev/null
"$app/Contents/MacOS/AisubdashMac" --probe-local
```

Both signed probes report `providers=N quotas=M`. A positive provider count alone
does not verify a collector. Check the selected account's quota and observation
time in the panel after refreshing it. If the Mac's port is occupied, identify
its listener with `lsof -nP -iTCP:6736 -sTCP:LISTEN`. An existing compatible local
aisubdash server can be reused. For Tailscale HTTP 403, check that the dashboard's
existing Host allowlist accepts the same origin used by the Mac app.

## Record The Result

Record the commit, macOS version, architecture, date, and each result below.
Keep account identifiers, credentials, actual origins, and raw logs in a private
local record. A fresh clone can use the repository's ignored `handover.md`.
Summarize only the redacted result in PR #69 when updating its verification status.

| Check | Result to record |
| --- | --- |
| Menu bar | Icon, popover, quota pin, app restart, and source switch |
| Tailscale | Connection probe exit status and whether a known quota matches the Web dashboard |
| This Mac | Connection probe exit status, provider family, and a verified local refresh |
| Failure | First failing step, error summary, and reproduction steps |

Once all three checks pass, update PR #69 with the evidence and confirm the latest
PR checks. Any new source fix needs tests and the applicable re-review before merge.

References: [installation and source behavior](../macos-menu-bar.md),
[plan and iOS widget roadmap](../plans/2026-11-22-macos-menu-bar.md),
[initial review](../reviews/2026-11-22-macos-menu-bar-review.md) and
[fix log](../fix-logs/2026-11-22-macos-menu-bar-fix-log.md).
