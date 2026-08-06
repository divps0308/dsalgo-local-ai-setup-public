# Maintainer and Contributor Standards

This document defines the engineering, security, and documentation standards
for maintaining DSAlgo Local AI Setup. It is a reference for human contributors
and may also be supplied to repository-aware development tools. Repository
integrations should reference this document rather than maintaining a second set
of rules.

## Mission

Maintain DSAlgo Local AI Setup as a secure, single-user, self-hosted Windows AI
workstation. Preserve local-first operation, explicit trust boundaries, native
NVIDIA acceleration through Windows Ollama, and predictable lifecycle scripts.

Before making a change, review:

1. `README.md`
2. `dev-guide.md`
3. `docs/PROJECT_CONTEXT.md`
4. `decision-log.md`
5. `to-do.md`
6. The implementation and configuration files relevant to the request

Use `user-guide.md` to confirm that user-visible behavior remains clear and
accurately documented.

## Non-negotiable architecture

- Ollama runs natively on Windows for direct NVIDIA GPU access.
- Open WebUI, Agent Gateway, and Agent Studio run through Docker Compose.
- Developer Workbench and the OAuth broker run natively as the signed-in,
  non-Administrator Windows user.
- Local Agent Studio and Developer Workbench remain separate products and
  processes. Studio configures reusable agents and MCP integrations; Workbench
  performs higher-trust project changes, approvals, commands, and Git actions.
- `config/models.json` is the only model registry.
- `config/agents.json` is the only active agent/MCP registry.
- `config/projects.json` is the only approved Workbench project registry.
- `config/runtime-policy.json` is the shared operating-mode source of truth.
- Container agent file and command tools remain confined to `workspace/`.
- Workbench access remains confined to explicitly approved project roots.
- Only core services are supported in the public release.
- Preserve the OpenAI-compatible `/v1/models` and `/v1/chat/completions`
  gateway contract.
- Workbench tasks select enabled agents by stable ID. Preserve Ask (read-only),
  Plan (saved Markdown plan), and Goal (approval-gated continuation) semantics;
  never execute edits or commands described only in assistant prose.
- Treat Goal models as untrusted protocol clients: validate complete tool
  arguments against controller-owned schemas, keep compatibility aliases
  narrow and deterministic, bound repair/loop behavior, and require
  post-mutation verification before completion.

## Security rules

- Never read, print, copy, summarize, or commit values from `.env`,
  `config/secrets.dpapi.json`, `config/oauth-tokens.dpapi.json`,
  `runtime/secrets.json`, or `runtime/oauth-broker/token`.
- Never place credentials directly in `config/agents.json`. Use
  `secretHeaders` references and `Set-McpSecret.ps1`.
- Never commit `config/personal-*`, runtime state, logs, backups, benchmark
  output, local paths, access tokens, or generated credentials.
- Keep services localhost-oriented. Do not publish ports or weaken authentication
  without an explicit security decision.
- Preserve gateway non-root execution, dropped Linux capabilities,
  `no-new-privileges`, no Docker socket, SSRF filtering, path containment, and
  command allow-list behavior.
- Preserve Workbench approval gates for writes, deletions, commands, commits,
  branch changes, and remote-impact actions.
- Preserve OAuth PKCE, state validation, HTTPS discovery, DPAPI storage,
  loopback binding, token redaction, and non-elevated execution.
- Treat MCP servers as privileged integrations and grant least privilege.

## Required change workflow

1. Inspect before editing. Use the source files rather than assumptions.
2. Check whether the working tree contains unrelated user changes and preserve
   them.
3. Define the smallest coherent change and its affected trust boundaries.
4. Update implementation, configuration, tests, generated frontend assets, and
   documentation together.
5. Run proportional validation.
6. Run repository safety checks before committing.
7. Review the complete diff, then commit one coherent change.

Destructive operations such as uninstall, model or volume deletion, destructive
restore, and external-project deletion are not appropriate for routine tests.

## Documentation contract

Every functional change must review and update the applicable files:

| File | Required purpose |
|---|---|
| `README.md` | Short project overview, entry points, quick start, and links |
| `user-guide.md` | Beginner installation, daily use, recovery, and troubleshooting |
| `dev-guide.md` | Architecture, source layout, APIs, security, development, testing, and release process |
| `agentic-dev-instructions.md` | Persistent coding-agent constraints and workflow |
| `docs/PROJECT_CONTEXT.md` | Mission, historical context, system map, scope, and current architecture |
| `decision-log.md` | New or revised functional, architectural, security, deployment, or material UX decisions |
| `to-do.md` | Every discovered limitation, unsupported behavior, validation gap, operational constraint, or follow-up |
| `CHANGELOG.md` | User-visible additions, fixes, migrations, and demonstrably resolved limitations |
| `SECURITY.md` | Supported security posture and disclosure guidance when the threat model changes |
| `.env.example` | Public environment contract when variables change |

Each topic has one authoritative guide; other documents should link to it rather
than duplicating the full text. Replaced decisions remain in the history and are
marked superseded. A roadmap item is removed only after its resolution is
verified and recorded.

## Configuration contract

- Parse every modified JSON file.
- Keep active tracked configuration generic and free of personal integrations.
- Use ignored `config/personal-*` only for machine-local non-secret snapshots.
- Never duplicate model tags or runtime settings in scripts or Python.
- Update schema documentation and examples when a config shape changes.
- Operating-mode restrictions must be enforced by backends; graying out a UI
  control is not sufficient.

## Frontend contract

- Keep Svelte 5 and TypeScript; do not introduce React.
- Reuse `frontend/shared` components and CSS design tokens.
- Preserve System, Light, and Dark modes and the centralized operating mode.
- Keep keyboard operation, visible focus, semantic labels, tooltips, dialogs,
  reduced motion, and WCAG AA contrast.
- Do not edit compiled JavaScript manually. Build from `frontend/` and commit
  the generated `agent-studio/static` and `developer-workbench/static` assets.
- Do not add mock backend data or silently change API contracts.

## Lifecycle contract

- `Install.ps1`: resumable prerequisite installation; build and create stopped
  containers; record ownership; install shortcuts.
- `Start.ps1`: elevate only the Docker/container phase; start Workbench and
  OAuth as the normal user.
- `Stop.ps1`: stop processes and containers without removing them.
- `Repair.ps1`: rebuild and recreate the complete selected setup, then leave it
  stopped.
- `Remove.ps1`: remove project containers/services while retaining persistent
  volumes, models, configuration, source, and external projects.
- `Uninstall.ps1`: confirmed, ownership-aware removal; never delete registered
  external project directories; optionally purge installer-owned data and safely
  remove the installer-owned application directory after cleanup.

## Validation gates

Run what applies:

```powershell
# PowerShell syntax
$errors = @()
Get-ChildItem -Filter '*.ps1' -Recurse | ForEach-Object {
  $tokens = $null
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    $_.FullName, [ref]$tokens, [ref]$parseErrors
  ) | Out-Null
  $errors += $parseErrors
}
if ($errors) { $errors; throw 'PowerShell parsing failed.' }

# Configuration
Get-Content config\models.json -Raw | ConvertFrom-Json | Out-Null
Get-Content config\agents.json -Raw | ConvertFrom-Json | Out-Null
Get-Content config\projects.json -Raw | ConvertFrom-Json | Out-Null
Get-Content config\runtime-policy.json -Raw | ConvertFrom-Json | Out-Null
. .\scripts\Common.ps1
. .\scripts\Configuration.ps1
Assert-GenericConfiguration

# Python
python -m py_compile agent-gateway\app.py agent-studio\app.py `
  developer-workbench\app.py oauth-broker\app.py

# Frontend
pnpm --dir frontend install --frozen-lockfile
pnpm --dir frontend check
pnpm --dir frontend build

# Compose and repository safety
docker compose config --quiet
.\Test-GitSafety.ps1
```

Run relevant automated tests. Use `Health.ps1`, `Test-LocalAI.ps1`, or
`Benchmark.ps1 -Quick` only when live services or hardware are required.
Never pull models or images solely for a source validation.

## Git hooks and commit enforcement

If Git is initialized, install or maintain repository-local hooks that enforce:

- no tracked secrets, personal overlays, runtime files, backups, logs, or
  benchmark output;
- JSON parsing;
- PowerShell parsing;
- documentation review when behavior/configuration changes;
- generated frontend assets accompanying frontend source changes.

Hooks are a safety net, not permission to skip manual review. Do not bypass
hooks with `--no-verify` unless the user explicitly authorizes it and the reason
is recorded.

Recommended commit pattern:

```text
<type>(<scope>): <imperative summary>

Why:
- concise rationale

Validation:
- exact checks and results

Docs:
- files updated, or an explicit explanation of why none applied
```

Use conventional types such as `feat`, `fix`, `docs`, `refactor`, `test`,
`build`, `chore`, and `security`. Keep one architectural decision or coherent
feature per commit where practical.

## Completion report

Every agent handoff must state:

- outcome;
- exact files changed;
- configuration or migration effects;
- validation performed and results;
- limitations added or resolved;
- decisions added or superseded;
- live Windows, Docker, GPU, OAuth, or external MCP checks still required.
