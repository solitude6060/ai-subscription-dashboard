# Antigravity Keyring Follow-Ups (2026-11-15)

Follow-up to PR #67 (`docs/reviews/2026-11-15-antigravity-linux-keyring-review.md`). Owner request 2026-11-15: investigate the open causes and fix the LOW findings where needed.

## Investigation Results

### AGY review lane authentication failure

- Cause: `agy` 1.5.9 skips the keyring during print-mode silent auth when `SSH_CONNECTION` is set. The orchestrating Claude Code session was started over SSH (`SSH_CONNECTION` present in its environment; other local sessions do not have it).
- Evidence (logs under `../openusage_webui-artifacts/2026-11-15-antigravity-keyring/agy-bwrap-diag/`): with `SSH_CONNECTION` set, the same tiny prompt fails inside `bwrap` (`B`, `D`, `E`) and outside it (`F`); `strace` of `F` shows no connection to `/run/user/1000/bus`. With `env -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY` inside `bwrap` (`G`), `cli.log` reads `keyringAuth: loaded token` and `ChainedAuth: authenticated via keyring`, and the reply is `OK`.
- Out of scope for this repository: the AGY call shapes in the global routing registry. Recommendation recorded for the owner.

### Token file removal

- `~/.gemini/antigravity-cli/antigravity-oauth-token` existed at 2026-11-10 09:46Z (the plugin refreshed from its refresh token and wrote `auth.json`). No `agy` log exists between 2026-11-09 16:22Z and 2026-11-10 16:59Z; no Antigravity IDE log for 2026-11-10; the system journal starts 2026-11-12 18:57 +0800; no trash entry; no local script deletes the file. Cause not determined. `agy` itself authenticated from the keyring in every logged run since 2026-11-10, so the file was not its active credential.

## LOW Findings Disposition

| ID | Finding | Decision |
| --- | --- | --- |
| C1 | Other-service test passes even if the runner is called | Fix: count runner calls, assert zero |
| O1 | Keyring read keyed only on service `gemini` | Fix: require plugin `antigravity` and account `antigravity` |
| O2 | Plugin isolation tests leave `HOME` null | Fix: tests with `HOME=/home/x` for an overlay pin and for `CONFIG_DIR` plus `CLI_HOME=$HOME` |
| O3 | Keyring path has no Account badge | Fix: badge from the keychain entry's `id_token_email` when the token file gives no email |
| O4 | `password_lookup_sync` may unlock a locked item (prompt) | Fix: `Secret.Service.search_sync` with `LOAD_SECRETS` and without `UNLOCK`; locked item exits 4 with a stderr message |
| O5 | Repeated error log when libsecret is absent | No change: `AGENTS.md` requires failures to be logged, not hidden |

## Tests

- Host (bun): runner call counter for another service; another plugin id and another account never call the runner; existing keyring tests pass `pluginId: "antigravity"`.
- Plugin (vitest): overlay pin with non-null `HOME` never reads the keychain; `CONFIG_DIR` with `CLI_HOME=$HOME` never reads the keychain; keyring path shows an Account badge from `id_token_email`.
- Live: unlocked lookup with the new helper finds the item; the locked path is covered by the API contract only (not run).

## Docs To Update

- `docs/providers/antigravity.md` (scope, locked keyring, badge).
- `docs/USER_GUIDE_WEBUI.zh-TW.md` (badge sentence if needed).
- Fix log `docs/fix-logs/2026-11-15-antigravity-keyring-followups-fix-log.md`.
