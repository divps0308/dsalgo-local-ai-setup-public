# Codex guidance for Alienware Local AI

## Project purpose

This repository implements a single-user, self-hosted AI workstation for an
Alienware Area-51 laptop running Windows 11 with an RTX 5090 Laptop GPU
(24 GB VRAM) and 64 GB RAM. The system must coexist with Docker Desktop/WSL2
and an optional local Temporal development cluster.

Read `agentic-dev-instructions.md`, `dev-guide.md`,
`docs/PROJECT_CONTEXT.md`, and the relevant implementation files before making
architectural or operational changes. Treat `README.md` as the concise landing
page, `user-guide.md` as the user-facing operations authority, and
`dev-guide.md` as the contributor architecture authority.

## Architectural invariants

- Ollama runs natively on Windows for direct NVIDIA access.
- Open WebUI, Agent Gateway, Agent Studio, Temporal, and optional data services
  run in Docker Compose.
- Keep only one generation model resident when practical.
- Preserve at least 24 GB of system RAM outside Docker/WSL by default.
- `config/models.json` is the source of truth for model tags and runtime
  settings. Do not duplicate model configuration in scripts or Python code.
- `config/agents.json` is the source of truth for configurable agents and MCP
  assignments. The gateway reloads it dynamically.
- Tracked active configuration stays distributable and free of personal agents,
  MCP servers, project paths, and credentials. Machine-specific overlays use
  ignored `config/personal-*` files.
- `config/runtime-policy.json` is the source of truth for Online, Restricted
  Online, and Strict Offline behavior. Preserve it as a reversible overlay and
  enforce it in backends; disabled UI controls alone are insufficient.
- The OpenAI-compatible gateway contract is `/v1/models` and
  `/v1/chat/completions`; preserve Open WebUI compatibility.
- Container gateway file and command tools stay confined to `workspace/`.
- Native Developer Workbench access stays confined to explicit roots in
  `config/projects.json`; model-proposed writes, deletes, and commands must
  remain approval-gated.
- OAuth-protected MCP credentials stay in the native Windows broker's
  DPAPI-protected store; containers may request short-lived access tokens but
  must not persist refresh tokens.
- Optional services must remain behind Compose profiles (`temporal` and
  `extended`) unless a deliberate migration says otherwise.
- Version 5 intentionally prioritizes a reliable local agent stack over a
  LangFlow/n8n-style visual platform. Do not treat workflow canvases,
  enterprise connectors, versioning, scheduling, an independent MCP proxy, or
  a full observability suite as missing baseline requirements.

## Security constraints

- Never read, print, commit, or copy values from `.env`,
  `config/secrets.dpapi.json`, `config/oauth-tokens.dpapi.json`,
  `runtime/secrets.json`, or `runtime/oauth-broker/token`.
- Never add secrets to `config/agents.json`; use `secretHeaders` references and
  `Set-McpSecret.ps1`.
- Do not expose local service ports publicly or weaken localhost-oriented
  assumptions without explicit user direction and a security review.
- Preserve the gateway container's non-root execution, dropped capabilities,
  `no-new-privileges`, lack of Docker-socket access, and workspace-only mount.
- Preserve URL-fetch SSRF protections and command allow-list/sandbox behavior.
- Preserve the Workbench's loopback-only binding, API token check, project-root
  path containment, non-elevated execution guidance, and mandatory approvals.
- Preserve the OAuth broker's loopback-only binding, runtime authentication,
  PKCE/state checks, HTTPS discovery validation, DPAPI storage, token
  redaction, and non-elevated execution guidance.
- Treat MCP servers as privileged integrations and default them to disabled
  until configured with least-privilege credentials.
- Preserve lifecycle semantics: Repair rebuilds but leaves services stopped;
  Stop retains containers; Remove removes project containers but retains data;
  Uninstall is ownership-aware and never deletes registered project roots.

## Change workflow

1. Inspect the relevant PowerShell, Compose, Python, and JSON sources.
2. Make the smallest coherent change; avoid unrelated cleanup.
3. Review `to-do.md` for every change. Add every limitation, unsupported
   behavior, incomplete validation, operational constraint, known tradeoff, or
   follow-up identified while inspecting, implementing, or testing. Categorize
   entries under backend, UI/UX, or architectural work. Do not remove an entry
   unless it has been demonstrably resolved; record resolutions in
   `CHANGELOG.md`.
4. Review `decision-log.md` for every change. Record every new or revised
   functionality, architecture, security, deployment, model, or material UX
   decision together with its rationale and consequences. Do not silently
   rewrite history; mark replaced decisions as superseded and add the
   replacement.
5. Apply the documentation contract in `agentic-dev-instructions.md`. Update
   `README.md`, `user-guide.md`, `dev-guide.md`, `CHANGELOG.md`,
   `.env.example`, and this context when their public behavior, dependencies,
   ports, configuration, architecture, or audience-specific instructions
   change. Do not recreate the removed mixed-purpose `DevGuide.md`.
6. Validate proportionally:
   - Parse `config/models.json` and `config/agents.json`.
   - Compile the Gateway, Studio, Workbench, and OAuth broker Python
     applications.
   - Run tests when present or added.
   - Run `docker compose config` for Compose changes when Docker is available.
   - Use `Health.ps1`, `Test-LocalAI.ps1`, or `Benchmark.ps1 -Quick` only when
     live services/hardware are required and report if that validation was not
     possible.
7. Report exact files changed, validation results, and any Windows/Docker/GPU
   checks that remain for the user.

## Operational cautions

- Installation and WSL configuration may require elevated PowerShell.
- A `.wslconfig` change requires `wsl --shutdown` and Docker Desktop restart.
- Do not run uninstall, destructive restore, model removal, or data-removal
  paths unless the user explicitly requests them.
- Avoid pulling models or container images merely to validate a source change.
- This directory may not be a Git repository; do not assume Git history or
  rollback is available.
