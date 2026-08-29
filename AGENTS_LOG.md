# External-service warning handling

This snapshot adds a general instruction requiring agents to account for every
warning or error before advancing a guided external-service setup.

| File                     | Change                                                                                                            |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| [`AGENTS.md`](AGENTS.md) | Require explicit classification, remediation, and read-only verification of external-service warnings and errors. |

## Resume

Implementation is complete. The next safe action is to commit `AGENTS.md` and
this snapshot, then restart Codex so its configured Railway MCP server registers.
No application lock is held, and no application or Railway project state was
changed by this task. Railway CLI 5.45.7 is installed globally at
`/usr/local/bin/railway`; `/root/.codex/config.toml` launches `railway mcp`.

## Architecture and behavior

During guided setup for Railway or another external service, an agent must now
account for every warning or error before presenting the next step. It must say
whether the output is blocking, actionable, or harmless, follow remediation
required by an applicable skill, and use a read-only check to verify the result
when possible.

## Representative instruction

```text
Classify it as blocking, actionable, or harmless; follow any applicable skill
remediation; and verify the resulting external state with a read-only check
where possible.
```

## Verification

- Documentation-only change; no application tests were required.
- `git diff --check` passed.
- The global `railway` command reports version 5.45.7, exposes the MCP proxy,
  and successfully authenticated as the existing Railway user.

## Limitations and excluded changes

- No application source, deployment configuration, or external Railway resource
  changed.
- The global Railway CLI and Codex MCP configuration live outside the repository
  and therefore do not appear in the working-tree file table.
