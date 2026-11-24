# Cursor Encrypted App Token Fix Log (2026-11-25)

Plan: `docs/plans/2026-11-25-cursor-encrypted-app-token.md`. Review: `docs/reviews/2026-11-25-cursor-encrypted-app-token-review.md`. PR #70, branch `fix/cursor-encrypted-app-token`.

## Issue

Every Cursor refresh on the live service failed with `Session expired. Sign in via Cursor app or run \`agent login\`.` from 2026-11-21T09:38:44Z. `probe_failures` holds 292 such rows through 2026-11-24T17:57:14Z. The last Cursor usage record is from 2026-11-21.

## Cause

Cursor IDE 3.31.15 (installed 2026-11-21 09:34:20Z) stores `cursorAuth/accessToken` and `cursorAuth/refreshToken` in `state.vscdb` as `cursor-safe-storage:v1:<ciphertext>`. The plugin used the first database with any token value, found no JWT expiry, posted the ciphertext to `/oauth/token`, received `shouldLogout`, and threw `Session expired`.

## Fix

| Commit | Change |
|---|---|
| `aa623e06` | Plan. |
| `d33af39e` | Tests: encrypted database plus CLI file, expired CLI token, encrypted only, pinned home. All four fail on `8b08db8a` (usage request carries the ciphertext, or the error is not the encrypted-sign-in message). |
| `31c286f4` | Skip `cursor-safe-storage:` values; add `~/.config/cursor/auth.json` as the last fallback for unpinned homes; no refresh or write-back for that source; encrypted-sign-in message. |
| `a4bd697b` | Provider docs. |

## Review Round 1 Repairs

| ID | Severity | Repro | Fix | Tests | Files |
|---|---|---|---|---|---|
| R1-1 | MEDIUM | `auth.json` with only `refreshToken`, or with an encrypted `accessToken`, next to an encrypted database: the first ends in `Not logged in`, the second sends the ciphertext as the bearer token. | `968f980f`: require a non-empty, non-encrypted access token; the CLI source has no refresh token; remove the unreachable `source === "cli"` refresh guard. | `fe8f7b4d`: two cases fail on `a4bd697b`, pass after the fix. | `plugins/cursor/plugin.js`, `plugins/cursor/plugin.test.js` |
| R1-2 | LOW | Pinned-home test did not observe file access and covered one variable. | Test only. | `fe8f7b4d`: both `OPENUSAGE_CURSOR_CONFIG_DIR` and `OPENUSAGE_CURSOR_STATE_DB`; CLI file never checked or read. | `plugins/cursor/plugin.test.js` |
| R1-3 | LOW | Docs said Detect finds a signed-in database; it checks file presence. | `e69f2fe9`: presence wording; CLI file read is access token only. | None (docs). | `docs/providers/cursor.md` |

## Review Round 2

Grok xhigh, Gemini 4 Neon high and Codex Sol high (second Codex home after a `~/.codex` usage limit) APPROVE `e69f2fe9`. One LOW (R2-1) is deferred.

## Deferred

- R2-1 (LOW): in the `encrypted access token` test case, keep `accessToken` encrypted and set `refreshToken` to a plain value.
- R1-3 remainder (LOW): `docs/providers/cursor.md` does not state that Settings-managed accounts drop an ambient `OPENUSAGE_CURSOR_STATE_DB` (`packages/providers/src/account-detect.ts:319-323`). Pre-existing wording.

## Verification

- After the round 1 repairs: Vitest 1384 passed; Bun 634 passed, 0 failed; `bun run build:webui` passed. Logs: `../openusage_webui-artifacts/2026-11-25-cursor-encrypted-token/{vitest,bun-tests,build-webui}-r1fix.log`.
- Real account through the branch code with an isolated plugin data dir: 213 records (212 token rows, 2026-11-16 to 2026-11-24), lines Total usage, Included Spend, Auto usage, API usage, Last 7 Days and Billing Cycle. The SHA-256 fingerprints of the IDE access value and of `auth.json` were the same before and after. Output: `e2e-summary-r1fix.txt`.
- Before the fix the first full Bun run failed only the known flaky test `CcusageProvider > default command runner cleans up child processes on timeout`; it passed alone 3 of 3 (`ccusage-flake-rerun.log`).

## Known Limits

- Only the default CLI config dir (`~/.config/cursor`) is read; a second CLI account under another `XDG_CONFIG_HOME` is not.
- A pinned Cursor home with an encrypted database cannot be read; it shows the encrypted-sign-in message.
- When the CLI token expires (current token: 2027-01-23), the card shows `Token expired` until `agent` renews its session.
