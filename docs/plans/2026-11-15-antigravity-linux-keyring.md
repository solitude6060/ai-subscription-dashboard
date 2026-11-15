# Antigravity Default Home Reads The Linux Keyring (2026-11-15)

## Problem

`antigravity:local-cli` (home `/home/ma`) has failed every refresh since 2026-11-10 10:46Z with "Start Antigravity or run `agy` and try again."

- The account home is pinned, so the server injects `OPENUSAGE_ANTIGRAVITY_CLI_HOME=/home/ma`. A pinned home skips local language-server discovery, the IDE state databases and the `agy` keychain fallback.
- The only remaining source is `~/.gemini/antigravity-cli/antigravity-oauth-token`. That file no longer exists; the cause of its removal is not determined. `agy` 1.5.9 keeps its token in the Secret Service keyring (service `gemini`, username `antigravity`).
- The cached token in `~/.openusage-webui/plugins/antigravity:local-cli/auth.json` expired at 2026-11-10 10:46Z (`expiresAtMs` 1794307618420). With no token file there is no refresh token, so every probe since has failed.
- On Linux the WebUI host's `keychain` is a JSON file in the plugin data directory, so the plugin's `agy` keychain fallback cannot see the keyring even when the home is not pinned.

## Measurements (2026-11-15, scratch scripts, no tokens printed)

| Path | Result |
| --- | --- |
| Pinned to `/home/ma` (current) | Fails with the login message |
| Unpinned, Antigravity IDE 2.0.11 language server running | 1 line (Claude 5-hour); `RetrieveUserQuotaSummary` returns 404 |
| Unpinned, only the `agy` CLI process | Fails: discovery matches the first process whose argv contains `agy`, which has no listening port; the real `agy` server returns 401 "missing CSRF token" |
| Pinned to `/home/ma` + keyring read (spike) | 5 lines: Session, Weekly, Argon Weekly, Claude, Claude Weekly (matches the last good reading on 2026-11-10) |

Keyring entry shape: plain JSON (no `go-keyring-base64:` prefix) with `token.{access_token, token_type, refresh_token, expiry, expires_in}`, `auth_method`, `id_token_email`. A lookup from a transient `systemd-run --user` unit finds the item, so the service can reach D-Bus and the unlocked keyring.

## Decision

Owner decision 2026-11-15: let the WebUI read the system keyring (option "讓 WebUI 讀系統 keyring").

1. Host (`packages/providers/src/providers/openusage-plugin.ts`): for service `gemini`, after the local keychain store misses, read the Secret Service item with attributes `service`/`username` through a read-only `python3 -I` libsecret helper (5 s timeout). Only stderr is logged. Other services are unchanged.
2. Plugin (`plugins/antigravity/plugin.js`): a home pinned to `$HOME` may use the `agy` keychain fallback. The keyring belongs to the default home's `agy`; overlay profiles (`agy1`, `agy2`) run without D-Bus and use their own token files. Pinned homes still skip language-server discovery, so an open IDE cannot replace the five-line summary with its one-line reply.

`applyProviderHomeEnv` and `looksLikeAntigravityCliHome` are unchanged.

## Known Limits

- The keychain path uses the stored access token only (no refresh). It stays valid while `agy` runs and refreshes it hourly; when `agy` has not run for an hour the card shows the login message.
- After a reboot the keyring must be unlocked before the lookup succeeds.
- The account badge is not shown for the keyring path (no token file with an `id_token`).

## Tests

- Plugin (vitest): home pinned to `$HOME`, no token file, keychain returns the Linux shape, probe succeeds with that token and does not run discovery. Existing tests cover a home pinned elsewhere never reading the keychain.
- Host (bun): `gemini`/`antigravity` reads through the injected runner; exit 3 throws not-found; other services never call the runner.

## Docs To Update

- `docs/providers/antigravity.md` (auth summary, keychain fallback, multi-account homes, probe order).
- `docs/USER_GUIDE_WEBUI.zh-TW.md` where it describes the default Antigravity home.
- Fix log `docs/fix-logs/2026-11-15-antigravity-linux-keyring-fix-log.md`.
