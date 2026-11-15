# Antigravity Linux Keyring Fix Log (2026-11-15)

Plan: `docs/plans/2026-11-15-antigravity-linux-keyring.md`. Branch `fix/antigravity-linux-keyring`.

## Issue

`antigravity:local-cli` (home `/home/ma`) failed every refresh from 2026-11-10 10:46Z with "Start Antigravity or run `agy` and try again." The `probe_failures` table holds 60 rows for this provider, first at 2026-10-29T00:17Z and last at 2026-11-15T14:05Z. The last stored quota reading is 2026-11-10T09:47Z.

## Cause

- The account home is pinned (`OPENUSAGE_ANTIGRAVITY_CLI_HOME=/home/ma`). A pinned home reads only `~/.gemini/antigravity-cli/antigravity-oauth-token` and the plugin's `auth.json` cache.
- The token file is absent. `agy` 1.5.9 keeps its token in the Secret Service keyring. Cause of the file's removal not determined.
- `auth.json` expired at 2026-11-10 10:46:58Z; with no token file there was no refresh token.
- The WebUI host's `keychain` is a JSON file in the plugin data directory, so the plugin's `agy` keychain fallback could not reach the keyring even for unpinned homes.

## Repro

- `getProviders` with the live account row (`home_path=/home/ma`), no injected hooks: `ERR Error: Start Antigravity or run \`agy\` and try again.` (same on `origin/main` `17692e0f`).
- Plugin test "reads the agy keychain for a home pinned to $HOME without a token file" fails on `main` with the login message.
- Host test "reads the agy token from the Secret Service keyring when the local store misses" fails on `main` with `Keychain item not found: gemini`.

## Fix

| File | Change |
| --- | --- |
| `packages/providers/src/providers/openusage-plugin.ts` | Keychain service `gemini`: after the local store misses, read-only libsecret lookup through `python3 -I` (attributes `service`, `username`; 5 s timeout; exit 3 is not-found; only stderr is logged). New `secretServiceRunner` option for tests; it disables the worker runtime like the other injected hooks. |
| `plugins/antigravity/plugin.js` | `pinnedHomeIsDefault`: a CLI home pinned to `$HOME` (trailing slashes ignored) may use the `agy` keychain fallback. Language-server discovery stays skipped for pinned homes. |
| `packages/providers/test/openusage-plugin-bundled-fixtures.test.ts` | Bundled fixture injects a not-found runner so it never runs the host keyring helper. |

Alternatives measured and rejected (plan, Measurements table): unpinning the default home returns one line when the IDE server runs and fails otherwise; the `agy` CLI server requires a CSRF token that is not in its argv.

## Tests Added

- `plugins/antigravity/plugin.test.js`: home pinned to `$HOME`, Linux keyring JSON shape, no discovery, Bearer token from the keyring, refresh token absent from output.
- `packages/providers/test/openusage-plugin-isolation.test.ts`: runner read for `gemini`/`antigravity`; exit 3 reported as not found; other services never call the runner.
- Existing plugin tests keep covering homes pinned elsewhere never reading the keychain (`/tmp/agy-acct1`, `/tmp/.agy-homes/other`).

## Verification

- Live account through `getProviders`, branch code: plan Google AI Pro; lines Session, Weekly, Argon Weekly, Claude, Claude Weekly (same set as the 2026-11-10 reading).
- `systemd-run --user --wait --pipe` lookup: item found, so the service context reaches D-Bus and the unlocked keyring.
- `bun run test` (vitest): 70 files, 1374 tests passed.
- `bun run test:webui`: 631 passed, 1 failed (`CcusageProvider > default command runner cleans up child processes on timeout`). The same test passed and failed on two reruns of the same tree under load average 12; recorded as a known flake in `handover.md`.
- `bun run build:webui`: passed.
- Redaction audit (`src-tauri/src/plugin_engine/host_api.rs`): the plugin exposes no new request or response fields; the keyring value is used only as a Bearer header, as in the existing keychain path.

## Known Limits

- Keychain path uses the stored access token without refresh; it depends on a running `agy`.
- A locked keyring after reboot makes the lookup fail until login.
- No Account badge on the keyring path.
- `openusage-plugin.ts` is 589 lines, above the ~500 line guideline (560 before this change).
