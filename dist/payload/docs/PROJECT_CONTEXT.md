# DSAlgo Local AI Setup project context

## Mission

Build and evolve a private, practical local agent platform on Windows 11.
Favor dependable operation, bounded resource use, local data control, and
maintainability over maximum benchmark scores. The current validated baseline
is a Windows/NVIDIA CUDA workstation path; broader hardware remains controlled
beta until tested.

The current implementation is version 5. It is designed for:

- a known NVIDIA CUDA GPU with dedicated VRAM
- 64 GB system RAM
- native Windows Ollama inference
- Docker Desktop with the WSL2 backend
- the core local-AI services only
- native Windows Developer Workbench for approval-gated local project changes
- shared Svelte 5/TypeScript frontend source for Studio and Workbench, compiled
  to committed static assets for Node-free runtime

## Origin and design history

Earlier planning documents referenced optional workflow/extended services
development cluster and a specific laptop. Those are historical assumptions,
not current public-release requirements. This release is core-only and its
validated compatibility baseline is Windows/NVIDIA CUDA; see `to-do.md` for
the remaining hardware matrix and resource-validation work.

Version 5 was commissioned after independent audits of versions 3 and 4. Those
audits identified a good core architecture but several concrete risks:

- unpinned 30B/32B model variants could exceed the laptop's 24 GB VRAM;
- large contexts further reduced KV-cache headroom;
- partial CPU offload could cause severe, easily missed performance loss;
- unconstrained Docker/WSL2 memory could compete with Ollama;
- model settings were duplicated across multiple files;
- plaintext secrets could be included in backups;
- a four-stage orchestrator incurred costly model swaps and should not be the
  default for ordinary work.

The explicit v5 request was to produce an end-to-end stack incorporating the
high-value fixes, a centralized model capability registry, and a benchmark and
calibration workflow, while leaving enough RAM for local inference and desktop
workloads.

This led to the following deliberate decisions:

- replace the earlier 30B/32B generation models with pinned 14B Q4 variants;
- keep native Windows Ollama rather than forcing a fully containerized design;
- assign a different context budget to each model role;
- detect GPU placement and suspected CPU offload;
- generate bounded WSL2 profiles;
- keep optional data services off unless needed;
- protect MCP secrets with Windows DPAPI and exclude secrets from backups;
- centralize model configuration in `config/models.json`;
- provide repeatable hardware-specific benchmarking;
- recommend single-agent operation by default and keep multi-model
  orchestration optional.

## System map

```text
Open WebUI (:3000)
    |
    | OpenAI-compatible API
    v
Agent Gateway (:8001 host -> :8000 container)
    |-- loads config/models.json
    |-- reloads config/agents.json
    |-- invokes built-in sandboxed tools
    |-- invokes assigned Streamable HTTP MCP tools
    |
    v
Native Windows Ollama (:11434)

Agent Studio (:3001)
    |-- edits config/agents.json
    |-- tests MCP initialization
    |-- starts and monitors remote MCP OAuth authorization
    `-- displays gateway model profiles

MCP OAuth Broker (:3003, native Windows, loopback only)
    |-- discovers protected resources and authorization servers
    |-- completes browser Authorization Code + PKCE
    |-- stores and refreshes DPAPI-protected tokens
    `-- supplies short-lived access tokens to Gateway and Studio

Developer Workbench (:3002, native Windows)
    |-- registers explicit local project roots
    |-- uses native Ollama coding/general/reasoning roles
    |-- previews patches and command requests
    |-- waits for per-action user approval
    |-- runs approved PowerShell and executables as the signed-in user
    `-- provides Git status, diff, branch, commit, and push controls

Optional Compose profiles:
    optional -> separately deployed integrations
```

## Core components and ownership

| Area | Source of truth | Notes |
|---|---|---|
| Model selection and tuning | `config/models.json` | Tags, context, temperature, keep-alive, hardware profile |
| Agent definitions | `config/agents.json` | Instructions, model roles, built-in tools, MCP assignments, step limits |
| Runtime API and tools | `agent-gateway/app.py` | OpenAI-compatible API, tool loop, MCP client, orchestration |
| Configuration UI | `agent-studio/app.py` | Local management UI and JSON persistence |
| Native coding UI | `developer-workbench/app.py` | Project registry, agent tasks, approvals, patches, native commands, Git |
| MCP OAuth client | `oauth-broker/app.py` | Discovery, browser authorization, DPAPI token storage, refresh |
| Service topology | `docker-compose.yml` | Base services, profiles, volumes, limits, ports |
| Windows lifecycle | root `*.ps1` and `scripts/*.ps1` | Resumable install, start, stop, remove, repair, health, backup, and ownership-aware uninstall |
| Project landing page | `README.md` | Concise overview, quick start, URLs, and guide routing |
| Operator documentation | `user-guide.md` | Beginner installation, usage, lifecycle, persistence, recovery, and troubleshooting |
| Contributor documentation | `dev-guide.md` | Architecture, source layout, APIs, security, development, testing, and commits |
| Agentic contributor contract | `agentic-dev-instructions.md` | Reusable coding-agent invariants, documentation/config updates, hooks, and validation |
| Security model | `SECURITY.md` | Local-only deployment and agent sandbox assumptions |
| Limitation and to-do register | `to-do.md` | Backend, UI/UX, and architectural constraints, gaps, and follow-up work |
| Decision log | `decision-log.md` | Accepted functionality and architecture decisions, rationale, and consequences |
| Runtime connectivity policy | `config/runtime-policy.json` | Shared Online, Restricted Online, and Strict Offline mode |

## Model strategy

The installer uses deterministic, inference-free scoring over the versioned
Ollama catalog. It is validated first for Windows/NVIDIA CUDA hardware with
known VRAM. AMD, Intel, CPU-only, Vulkan, DirectML, unknown-VRAM, multi-GPU,
and non-Windows compatibility remain validation work rather than guarantees.
Free-disk gating, CPU performance classification, backend checks, measured
model profiles, role-coverage validation, hardware-derived Docker/WSL limits,
and automated Ollama tag verification are tracked in `to-do.md`.

The registry currently assigns:

| Role | Model | Context | Intended use |
|---|---|---:|---|
| General | `qwen3:14b-q4_K_M` | 16K | planning and tool use |
| Coder | `qwen2.5-coder:14b-instruct-q4_K_M` | 24K | implementation and tool use |
| Reasoning | `deepseek-r1:14b-qwen-distill-q4_K_M` | 12K | independent read-only review |
| Embedding | `embeddinggemma:latest` | 2K | embeddings |

The 14B Q4 choices intentionally leave VRAM headroom. Changes to model size or
context must account for KV cache, desktop/browser GPU use, system-RAM offload,
and concurrent Docker memory.

## Agent and orchestration model

Configured agents select a model *role*, not an Ollama tag. This indirection
allows model replacement through the registry without rewriting each agent.

Built-in profiles include general, coding, reasoning, and orchestrator modes.
The orchestrator follows a planner -> executor -> reviewer -> conditional
revision sequence and swaps models between stages. Prefer a single agent for
routine tasks; reserve orchestration for work where independent review justifies
the latency and model swapping.

The gateway exposes configurable agents through an OpenAI-compatible model list,
allowing Open WebUI to treat agent profiles as selectable models.

## Resource policy

The default balanced WSL profile caps Docker/WSL2 at 20 GB with eight
processors and 8 GB swap, leaving approximately 44 GB outside WSL2. `AIOnly`
permits 28 GB and twelve processors.

Resource-related changes should preserve these principles:

- Native Ollama gets GPU priority.
- Avoid simultaneous residency of multiple generation models.
- Optional workflow services are outside the core setup.
- Extended services remain optional when their idle memory is not justified.
- Use measured benchmark and `ollama ps` evidence before increasing context.

## Persistence and trust boundaries

- Open WebUI data and optional databases live in named Docker volumes.
- Agent/model configuration and the agent workspace live on the host.
- Only `workspace/` is writable by agent tools inside the gateway.
- The separate native Workbench may access only explicitly registered project
  roots and requires approval for every model-proposed mutation or command.
- DPAPI-encrypted MCP secrets are tied to the current Windows user.
- OAuth access/refresh tokens and dynamic client credentials are held in a
  separate DPAPI-protected store owned by the native OAuth broker.
- Decrypted secrets are transient under `runtime/` and recreated at startup.
- Normal backups deliberately omit `.env` and both encrypted/decrypted secrets.

This is a local single-user system. It is not designed for public ingress,
multi-tenant isolation, or untrusted repositories.

## Current validation baseline

The package documentation says the following static validation was performed:

- Python compilation for Gateway and Studio
- JSON validation for model and agent configuration
- archive integrity and expected-file checks during packaging

Live Windows-specific paths still require target-machine validation:

- Ollama model availability and GPU placement
- NVIDIA VRAM usage and generation speed
- Docker Desktop and WSL2 limits
- base and optional Compose profiles
- Open WebUI-to-gateway integration
- MCP connectivity and optional workflow integrations
- backup/restore behavior
- native Workbench project registration, approvals, Windows toolchains, and Git

## Enhancement priorities

Unless a task specifies otherwise, assess enhancements in this order:

1. Correctness, recoverability, and observability
2. Security and containment
3. Stable Open WebUI/API compatibility
4. GPU/VRAM and host-memory efficiency
5. Agent quality and tool reliability
6. Operator experience and automation
7. Optional integrations and additional services

Potential future work should be grounded in an explicit use case and measured
against laptop resource constraints. Avoid adding infrastructure solely because
it is common in larger server deployments.

## Explicit v5 scope boundaries

The design discussion characterized v4 as a functional local AI and configurable
agent stack, not a LangFlow/n8n-class visual orchestration platform. Version 5
focused on hardware fit, reliability, security, and maintainability.
coexistence. It did not promise:

- a drag-and-drop workflow canvas or node editor;
- visual planner/executor/reviewer chain editing;
- REST/OpenAPI or generic database connector management UIs;
- built-in GitHub, Jira, Azure DevOps, Slack, or Teams connectors;
- agent version history, rollback, or export/import;
- agent scheduling or workflow execution history;
- an independent MCP proxy service;
- unattended scheduled upgrades;
- a centralized observability dashboard.

These are possible future enhancements, not defects in the delivered v5
baseline. Add them only when a concrete workflow warrants their security,
resource, and maintenance costs.

## Lower-priority operational opportunities

The design discussion also identified useful but non-urgent improvements:

- structured application logs;
- explicit log rotation and retention;
- a local log viewer or optional Grafana/Loki integration;
- richer benchmark recommendations in Agent Studio;
- scheduled updates with a safe rollback strategy.

For this single-user workstation, these remain below correctness, containment,
resource efficiency, agent reliability, and restore confidence.
