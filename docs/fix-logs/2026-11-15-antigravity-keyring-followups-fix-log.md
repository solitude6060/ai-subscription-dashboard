# Antigravity Keyring Follow-Ups Fix Log (2026-11-15)

Plan: `docs/plans/2026-11-15-antigravity-keyring-followups.md`. Branch `fix/antigravity-keyring-followups`. Findings from `docs/reviews/2026-11-15-antigravity-linux-keyring-review.md`.

## Investigations

| Question | Result |
| --- | --- |
| Why the AGY review lane failed authentication | `agy` 1.5.9 skips the keyring in print-mode silent auth when `SSH_CONNECTION` is set. Removing `SSH_CONNECTION`, `SSH_CLIENT` and `SSH_TTY` makes the same `bwrap` call authenticate via keyring. Evidence: `../openusage_webui-artifacts/2026-11-15-antigravity-keyring/agy-bwrap-diag/` runs `B`, `D`, `E`, `F` (fail, with `SSH_CONNECTION`), `G` (pass, without), `F-strace.txt` (no connection to `/run/user/1000/bus`). |
| Why `~/.gemini/antigravity-cli/antigravity-oauth-token` disappeared | Cause not determined. The file existed at 2026-11-10 09:46Z. No `agy` run, IDE log, system journal entry, trash entry or local script accounts for its removal. |

## Findings

| ID | Repro (red) | Fix | Files |
| --- | --- | --- | --- |
| C1 | Other-service test could pass with the runner called | Runner call counter, `expect(runnerCalls).toBe(0)` | `packages/providers/test/openusage-plugin-isolation.test.ts` |
| O1 | Plugin `gemini-cli` asking for `gemini`/`antigravity`, and plugin `antigravity` asking for `gemini`/`other-account`, each made 1 runner call | Keyring read requires plugin `antigravity`, service `gemini`, account `antigravity` | `packages/providers/src/providers/openusage-plugin.ts` |
| O2 | (guard) overlay pin, prefix-sharing pin and IDE config dir with `HOME` set; already passing | Tests only | `plugins/antigravity/plugin.test.js` |
| O3 | Keyring path returned no Account badge | Keychain entry's `id_token_email` is the badge fallback | `plugins/antigravity/plugin.js` |
| O4 | Not run live (would lock the owner's login keyring) | `Secret.Service.search_sync` with `LOAD_SECRETS`, no `UNLOCK`; locked item exits 4 with `keyring item is locked` | `packages/providers/src/providers/openusage-plugin.ts` |
| O5 | — | No change; `AGENTS.md` requires failures to be logged | — |

## Verification

- Live account through `getProviders`: Account badge, Session, Weekly, Argon Weekly, Claude, Claude Weekly.
- Helper extracted from the source: missing account exits 3; the real item exits 0 (563 bytes, not printed).
- `bun run test` (vitest): 70 files, 1377 tests passed.
- `bun run test:webui`: 633 passed, 1 failed (`CcusageProvider > default command runner cleans up child processes on timeout`, known flake). No `Secret Service lookup` line in the test log.
- `bun run build:webui`: passed.
- `openusage-plugin.ts` is 630 lines (618 before).
