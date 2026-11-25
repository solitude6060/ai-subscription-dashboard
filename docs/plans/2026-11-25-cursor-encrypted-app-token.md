# Cursor Encrypted App Token

Date: 2026-11-25

## Problem

Since 2026-11-21T09:38:44Z every Cursor refresh on the live service fails with
`Session expired. Sign in via Cursor app or run \`agent login\`.` (292 rows in
`probe_failures` through 2026-11-24T17:57Z). The last stored Cursor usage record is
from 2026-11-21.

## Cause

- Cursor IDE 3.31.15 was installed at 2026-11-21 17:34:20 +0800 (09:34:20Z,
  `/var/log/apt/history.log`), four minutes before the first failure.
- `~/.config/Cursor/User/globalStorage/state.vscdb` now stores
  `cursorAuth/accessToken` and `cursorAuth/refreshToken` as
  `cursor-safe-storage:v1:<772 base64 chars>`. The key
  `encryption.migratedToGnomeLibsecret` is `true`. The value is ciphertext, not a JWT.
- The plugin takes the first database that has any token value. It treats the
  ciphertext as a token, finds no expiry, posts it to `/oauth/token`, gets
  `shouldLogout`, and throws `Session expired`. The keychain fallback is never reached.

## Evidence For The Fix

- The Cursor CLI (`agent` 2026.11.22, `agent about`: Subscription Tier Ultra) keeps a
  plain JWT pair in `~/.config/cursor/auth.json` (`accessToken`, `refreshToken`;
  claims `type: session`, `signInSurface: agent_cli`, expiry 2027-01-23T17:54:06Z).
- The CLI token user id matches the IDE account (`cursorAuth/cachedScopedProfile`).
- With the CLI token, all six endpoints the plugin calls returned HTTP 200 on
  2026-11-24: `GetCurrentPeriodUsage`, `GetPlanInfo`, `GetCreditGrantsBalance`,
  `cursor.com/api/usage`, `cursor.com/api/auth/stripe`,
  `cursor.com/api/dashboard/get-filtered-usage-events`.
- Upstream (Swift `main` at `53f70b39`, `tauri-legacy` at `0a08306d`) has no handling
  for this format. The Swift app signs in itself and does not read `state.vscdb`.

## Change

1. A `state.vscdb` token value that starts with `cursor-safe-storage:` counts as no
   token for that database. The plugin moves on to the next source and never sends
   it to any endpoint.
2. New last fallback: `~/.config/cursor/auth.json` (Cursor CLI on Linux), after the
   keychain. Skipped for pinned homes (`OPENUSAGE_CURSOR_CONFIG_DIR` /
   `OPENUSAGE_CURSOR_STATE_DB`), same rule as the keychain.
3. The CLI file is read-only for the plugin: no `/oauth/token` refresh with its
   refresh token and no write-back. The CLI owns rotation of that session. An expired
   or rejected CLI token ends in the existing `Token expired` message.
4. When the only token found is encrypted, the error says the Cursor app sign-in is
   encrypted and points to `agent login`.

Not changed: decrypting `cursor-safe-storage` values, account detection, pinned
homes that only have an encrypted database (they now get the encrypted message).

## Tests

`plugins/cursor/plugin.test.js`:

- encrypted `state.vscdb` plus CLI file: usage request uses the CLI token; no
  `/oauth/token` request; no SQLite write.
- expired CLI token: no `/oauth/token` request, no file or keychain write; usage 401
  ends in `Token expired`.
- encrypted `state.vscdb` and no CLI file: encrypted-sign-in error, no HTTP request.
- pinned home with encrypted database: CLI file is not read.

## Docs

- `docs/providers/cursor.md` (token sources, refresh).

## Exit Criteria

- New tests fail on `origin/main` (`8b08db8a`) for the stated reason, then pass.
- Full Vitest and `bun run build:webui` pass.
- A refresh through the branch code with an isolated data directory returns Cursor
  usage lines from the real account.
- Triple-review APPROVE. Deploy needs owner approval for the service restart.
