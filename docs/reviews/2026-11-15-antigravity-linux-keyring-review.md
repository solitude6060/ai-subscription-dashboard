# Antigravity Linux Keyring Review (2026-11-15)

- PR: #67, branch `fix/antigravity-linux-keyring`
- Base: `17692e0faa227e472e2a10e5d367cc729443dfc4`
- Reviewed head: `23c31e2a48cea8c277c734b5cc17b3dbe2b8ac3d`
- Orchestrator: Claude Code, `claude-opus-5-5`
- Raw prompt, commands and outputs: `../openusage_webui-artifacts/2026-11-15-antigravity-keyring/review/round1/`

## Lanes

| Lane | Client / model | Result |
| --- | --- | --- |
| 1 | Grok Build `grok-4.7`, `--reasoning-effort xhigh` | APPROVE, no findings (`lane1-grok.final.md`) |
| 2 | AGY `gemini-4-hydrogen-high` under `bwrap` | Failed twice: "Authentication required … authentication timed out" (`lane2-agy.err`, `lane2-agy-retry1.err`). No review produced. |
| 2 (substitute) | Claude Code `claude-opus-5-5`, `--effort high`, `--advisor claude-opus-5-5`, `--safe-mode`, Read/Grep/Glob only | APPROVE, 5 LOW (`lane2-sub-claude.final.md`) |
| 3 | Codex `gpt-6.1-sol`, `model_reasoning_effort=high`, `--sandbox read-only` | APPROVE, 1 LOW (`lane3-codex.final.md`) |

Lane 2 substitution follows the unused-family rule (Google failed after one retry; Anthropic was the unused family). The substitute shares the orchestrator's family (Anthropic) and ran in a fresh, customization-free, read-only session. Families used: xAI, Anthropic, OpenAI.

AGY failure evidence: `~/.gemini/antigravity-cli/log/cli-20261115_223536.log` has no `keyringAuth` line and repeated "You are not logged into Antigravity." A libsecret lookup inside the same `bwrap` mount finds the `gemini`/`antigravity` item. An `agy` run at 22:31:58 started by another process logged `ChainedAuth: authenticated via keyring`. Cause not determined.

## Triage

| ID | Finding | Source | Severity | Verified evidence | Disposition |
| --- | --- | --- | --- | --- | --- |
| C1 | "Other services never read the keyring" test passes even if the runner is called, because the runner's exception is caught and the not-found result satisfies the assertion | Codex | LOW | `openusage-plugin-isolation.test.ts` runner throws; `readSecretServicePassword` catch returns `null` | Deferred: follow-up adds a call counter and asserts zero calls |
| O1 | Keyring branch checks only `service === "gemini"`, not plugin id or account | Claude | LOW | `openusage-plugin.ts:413`; no other bundled plugin uses service `gemini` (grep of `plugins/*/plugin.js`) | Deferred: follow-up restricts to plugin `antigravity` and account `antigravity` with a test |
| O2 | Existing pinned-elsewhere plugin tests return `null` for `HOME`, so they do not exercise the path comparison | Claude | LOW | Mocks in `plugin.test.js` return `null` for every name except `OPENUSAGE_ANTIGRAVITY_CLI_HOME` | Deferred: follow-up adds `HOME=/home/x` with an overlay pin and with `CONFIG_DIR` set |
| O3 | An overlay `agy` with a working session bus could overwrite the keyring item; the default card would then show that account without a badge | Claude | LOW | `~/.local/bin/agy-run-profile:74` sets `DBUS_SESSION_BUS_ADDRESS` to a missing socket for overlays on this machine | Deferred: follow-up shows the Account badge from `id_token_email` |
| O4 | Locked keyring may raise an unlock prompt instead of returning not-found | Claude | LOW | Not run; docs state the card shows the login message | Deferred: live check with a locked collection; docs statement marked unverified in the fix log |
| O5 | Hosts without `python3-gi` or a Secret Service log an error on every refresh | Claude | LOW | Non-0/3 exits reach `console.error` each call | Deferred: map module-missing and no-service to exit 3, or log once |

No CRITICAL, HIGH or MEDIUM findings. All three lanes approve the reviewed head.

## Integration Wiring

Checked by the orchestrator and lanes 1 and 2: the registry passes `process.env` and no `homeDir`, so the plugin's `HOME` is the server home (`openusage-plugin.ts:154-155`); the worker builds its own provider and runs the default lookup; the live account through `getProviders` returns five lines on the reviewed code.
