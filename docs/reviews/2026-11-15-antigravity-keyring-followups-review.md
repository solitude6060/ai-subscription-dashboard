# Antigravity Keyring Follow-Ups Review (2026-11-15)

- PR: #68, branch `fix/antigravity-keyring-followups`
- Base: `f7f2f7f3fd4958e3d69d3de656504b848728fb9f`
- Reviewed head: `2ffff42d6170c3b38c34b3f10b01972d4670f0cf`
- Orchestrator: Claude Code, `claude-opus-5-5`
- Raw prompt, commands and outputs: `../openusage_webui-artifacts/2026-11-15-antigravity-keyring/review-pr68/round1/`

## Lanes

| Lane | Client / model | Result |
| --- | --- | --- |
| 1 | Grok Build `grok-4.7`, `--reasoning-effort xhigh` | APPROVE, no findings; 46 tool calls covering every changed file (`lane1-grok.final.md`) |
| 2 | AGY `gemini-4-hydrogen-high` under `bwrap`, launched with `env -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY` | APPROVE, no findings (`lane2-agy.final.md`); `cli.log` shows `ChainedAuth: authenticated via keyring` |
| 3 | Codex `gpt-6.1-sol`, `model_reasoning_effort=high`, `--sandbox read-only` | APPROVE, no findings (`lane3-codex.final.md`) |

Families: xAI, Google, OpenAI; no overlap with the orchestrator (Anthropic). The lane 2 environment change removes only the SSH variables that make `agy` 1.5.9 skip the keyring (`docs/plans/2026-11-15-antigravity-keyring-followups.md`); model, effort and the read-only mount are the registry call shape.

## Triage

No findings. Codex notes that the locked-keyring and timeout behavior were not exercised live; the fix log records the locked path as not run.
