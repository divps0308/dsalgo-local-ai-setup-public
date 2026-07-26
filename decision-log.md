# Functionality and Architecture Decision Log

This living log records accepted functionality, architecture, security,
deployment, model, and user-experience decisions for Alienware Local AI. Review
and update it with every repository change. Add a new entry whenever a change
introduces, revises, supersedes, or rejects a meaningful decision. Do not
silently rewrite historical decisions; mark superseded decisions and link the
replacement.

## Decision format

Each entry records its status, decision, rationale, and consequences. Dates
reflect when the decision was documented when the exact original decision date
is unavailable.

## Accepted decisions

### D-001 — Optimize for one documented Windows workstation

- **Status:** Accepted
- **Decision:** Target a single Windows 11 user on an Alienware Area-51 laptop
  with an RTX 5090 Laptop GPU, 24 GB VRAM, and 64 GB RAM.
- **Rationale:** Concrete hardware assumptions allow predictable model sizing,
  WSL limits, GPU use, and operational guidance.
- **Consequences:** Multi-user, server, Linux, and macOS deployment are outside
  the supported baseline.

### D-002 — Run Ollama natively on Windows

- **Status:** Accepted
- **Decision:** Keep Ollama outside Docker and use native NVIDIA access.
- **Rationale:** Native execution gives the laptop GPU the simplest and most
  reliable acceleration path and avoids GPU plumbing through Docker/WSL.
- **Consequences:** Containers reach Ollama through the host boundary, and the
  system has both native and container lifecycles.

### D-003 — Containerize the ordinary local application plane

- **Status:** Accepted
- **Decision:** Run Open WebUI, Agent Gateway, Agent Studio, and optional data
  services in Docker Compose.
- **Rationale:** Compose supplies repeatable service isolation, networking,
  resource limits, updates, and persistence.
- **Consequences:** Docker Desktop and WSL2 are required; host-access features
  remain separate.

### D-004 — Keep Local Agent Studio and Developer Workbench separate

- **Status:** Accepted
- **Decision:** Local Agent Studio at `localhost:3001` and Developer Workbench at
  `localhost:3002` are intentionally separate UIs and are not merged
  functionally or architecturally.
- **Rationale:** They represent different trust planes:
  - Agent Studio is a containerized configuration plane for agents, model
    roles, bounded gateway tools, MCP assignments, and OAuth initiation.
  - Developer Workbench is a native Windows execution plane that can reach
    explicitly approved arbitrary project roots, run native executables, apply
    changes, and perform Git operations under mandatory approvals.
  Merging them would require the configuration UI to inherit native filesystem
  and command privileges or require the native Workbench to expose its
  higher-trust APIs through the container application. Either option would blur
  security, authentication, deployment, and failure boundaries.
- **Consequences:** Users switch between two coordinated products. Studio
  remains visible in Docker Desktop; Workbench appears as a native Windows
  process. The products share a design system but not a privileged runtime or
  backend.

### D-005 — Run Developer Workbench natively and non-elevated

- **Status:** Accepted
- **Decision:** Host Workbench on Windows loopback rather than in Docker.
- **Rationale:** It needs controlled access to arbitrary approved Windows paths
  and installed PowerShell, Maven, Gradle, npm, .NET, Docker, Git, and other
  executables. Broad container mounts or Docker-socket access would weaken
  isolation.
- **Consequences:** Workbench has separate lifecycle scripts, does not appear
  as a Docker container, and must preserve loopback/token/project containment.

### D-006 — Use explicit approved project roots and mandatory approvals

- **Status:** Accepted
- **Decision:** Workbench may access only roots in `config/projects.json`;
  model-proposed writes, deletes, and native commands require approval.
- **Rationale:** Arbitrary native project access is high trust and should be
  deliberate, bounded, and reviewable.
- **Consequences:** Drive roots are rejected, path traversal is contained, and
  some autonomous workflows pause for human decisions.

### D-007 — Keep container agent tools confined to `workspace/`

- **Status:** Accepted
- **Decision:** Gateway file and command tools operate only in the mounted
  repository `workspace/`.
- **Rationale:** A narrow writable mount limits the blast radius of tool use.
- **Consequences:** Arbitrary Windows projects require Workbench rather than
  container agents.

### D-008 — Centralize models in `config/models.json`

- **Status:** Accepted
- **Decision:** Model tags, contexts, keep-alive, and runtime settings have one
  source of truth.
- **Rationale:** Duplicated settings previously created drift and unsafe model
  choices.
- **Consequences:** Scripts and Python code must read the registry rather than
  hard-code model configuration.

### D-009 — Centralize agents and MCP assignments in `config/agents.json`

- **Status:** Accepted
- **Decision:** Configurable agent behavior, permissions, step limits, and MCP
  assignments live in one dynamically reloaded file.
- **Rationale:** This permits reusable agents and Studio configuration without
  rebuilding the gateway.
- **Consequences:** Changes affect subsequent requests; secrets are prohibited
  from this file.

### D-010 — Preserve an OpenAI-compatible gateway contract

- **Status:** Accepted
- **Decision:** Expose `/v1/models` and `/v1/chat/completions`.
- **Rationale:** Open WebUI can treat local agents as an external
  OpenAI-compatible connection without custom frontend integration.
- **Consequences:** Open WebUI may label gateway agents “External” even though
  inference ultimately runs through local Ollama.

### D-011 — Prefer one resident generation model

- **Status:** Accepted
- **Decision:** Use pinned 14B Q4 models, bounded context sizes, and keep only one
  generation model resident when practical.
- **Rationale:** The 24 GB GPU needs headroom for reliable inference and other
  applications.
- **Consequences:** Orchestration can trigger model swaps and is reserved for
  complex tasks where independent review justifies latency.

### D-012 — Preserve at least 24 GB outside Docker/WSL

- **Status:** Accepted
- **Decision:** Default WSL/Docker profiles leave substantial RAM to Windows and
  native Ollama.
- **Rationale:** Unbounded WSL memory can starve the host and cause model
  fallback or instability.
- **Consequences:** Optional services may need alternate profiles and cannot be
  assumed always active.

### D-013 — Keep optional services behind Compose profiles

- **Status:** Accepted
- **Decision:** Temporal uses the `temporal` profile; PostgreSQL, Redis, and
  Qdrant use `extended`.
- **Rationale:** Idle developer services should not consume scarce laptop RAM.
- **Consequences:** Their endpoints are unavailable until explicitly started.

### D-014 — Store static MCP secrets with Windows DPAPI references

- **Status:** Accepted
- **Decision:** Never store plaintext MCP secrets in agent configuration; use
  `secretHeaders` references and `Set-McpSecret.ps1`.
- **Rationale:** Configuration, logs, backups, and UI must not expose
  credentials.
- **Consequences:** Studio does not display secret values, and static-secret
  testing has intentional visibility constraints.

### D-015 — Use a native OAuth broker for MCP OAuth 2.1

- **Status:** Accepted
- **Decision:** Perform OAuth discovery, browser authorization, PKCE, callback,
  token exchange, refresh, and DPAPI storage in a loopback Windows broker at
  `localhost:3003`.
- **Rationale:** Browser callbacks and Windows-bound secret storage fit a native
  process better than a container; refresh tokens must not persist in the
  gateway.
- **Consequences:** Containers request short-lived access tokens through a
  runtime-authenticated broker. The broker has a separate lifecycle.

### D-016 — Treat MCP servers as privileged and disabled by default

- **Status:** Accepted
- **Decision:** Connect only trusted Streamable HTTP MCP servers, assign them
  per agent, and apply least-privilege credentials/scopes.
- **Rationale:** MCP tools can read external data or perform external actions.
- **Consequences:** Configuration saved, OAuth connected, and tools operational
  are separate states that the UI and documentation must distinguish.

### D-017 — Do not expose local services publicly

- **Status:** Accepted
- **Decision:** Preserve localhost/loopback assumptions for Studio, Workbench,
  OAuth broker, and other management surfaces.
- **Rationale:** The baseline lacks internet-facing authentication, RBAC, and
  hardened multi-user controls.
- **Consequences:** Public tunnels, router forwarding, or non-loopback binding
  require explicit security redesign.

### D-018 — Give Workbench remote-impact Git actions explicit confirmation

- **Status:** Accepted
- **Decision:** Separate read-only status/diff, local branch/commit actions, and
  remote push actions. Confirm push and other material actions.
- **Rationale:** Local inspection, repository mutation, and remote impact have
  different risk levels.
- **Consequences:** Push is not styled as destructive deletion, but it is
  visually distinct and confirmation-gated.

### D-019 — Build Studio and Workbench with one shared Svelte design system

- **Status:** Accepted
- **Decision:** Use Svelte 5, TypeScript, Vite, shared local components, CSS
  tokens, and Lucide icons while preserving separate product applications.
- **Rationale:** The former embedded HTML prototypes lacked hierarchy,
  responsiveness, accessibility, and maintainable component structure.
- **Consequences:** The products look and behave consistently without sharing
  their privileged backend. Frontend development requires Node/pnpm.

### D-020 — Commit compiled frontend assets

- **Status:** Accepted
- **Decision:** Store production assets in `agent-studio/static/` and
  `developer-workbench/static/`.
- **Rationale:** Normal install, repair, and runtime should not depend on a Node
  toolchain.
- **Consequences:** Source changes must run type checks and rebuild both asset
  directories before completion.

### D-021 — Support System, Light, and Dark themes

- **Status:** Accepted
- **Decision:** Default to OS appearance, allow explicit Light/Dark selection,
  persist it in browser storage, and apply it before first paint.
- **Rationale:** Both local tools need a professional, accessible experience
  across working environments.
- **Consequences:** Preferences are local to each browser profile.

### D-022 — Use contextual help and least-privilege explanations

- **Status:** Accepted
- **Decision:** Provide searchable page help, accessible tooltips, semantic
  action hierarchy, diagnostics, toasts, and confirmation dialogs.
- **Rationale:** Tool permissions, OAuth, native commands, and Git actions are
  consequential and should be understandable at the point of use.
- **Consequences:** Help content must remain synchronized with real behavior
  and must not become the only source of critical safety information.

### D-023 — Do not fabricate unsupported UI data

- **Status:** Accepted
- **Decision:** Show only fields and states returned by existing backends.
- **Rationale:** Fake repository status, timestamps, progress, health history,
  or remote information would mislead users.
- **Consequences:** Some requested summaries remain absent until backend
  contracts provide them and are tracked in `to-do.md`.

### D-024 — Favor a reliable local agent stack over a workflow platform

- **Status:** Accepted
- **Decision:** Version 5 does not treat workflow canvases, enterprise
  connectors, scheduling/versioning, an independent MCP proxy, or full
  observability as baseline requirements.
- **Rationale:** Reliability, bounded resources, privacy, and maintainability on
  one laptop take priority over platform breadth.
- **Consequences:** Add such capabilities only for a concrete workflow with a
  deliberate architecture and security decision.

### D-025 — Maintain explicit operational and architectural records

- **Status:** Accepted
- **Decision:** `to-do.md` is the canonical limitation/to-do register and
  `decision-log.md` is the canonical functionality/architecture decision log.
  Both are reviewed with every change.
- **Rationale:** Known gaps and the reasoning behind the system should survive
  individual chats and implementation iterations.
- **Consequences:** Resolved limitations require changelog evidence; changed
  decisions are superseded rather than silently erased.

### D-026 — Use clean, non-compatible agent naming

- **Status:** Accepted
- **Decision:** Built-ins retain `agent-*`; setup agents use immutable `my-*`
  keys and `My ...` names; Studio-created agents use immutable `my-custom-*`
  keys and `My Custom — ...` names. No legacy IDs or aliases are retained.
- **Rationale:** A clean-install baseline is preferred over compatibility, and
  the categories must be visibly distinct from raw Ollama model tags.
- **Consequences:** Existing callers using old configured IDs must select a
  renamed agent.

### D-027 — Centralize connectivity as a reversible policy overlay

- **Status:** Accepted
- **Decision:** `config/runtime-policy.json` is the source of truth for Online,
  Restricted Online, and Strict Offline. Both UIs share it and every relevant
  backend enforces it independently.
- **Rationale:** A policy overlay preserves configuration and prevents direct
  API calls from bypassing disabled frontend controls.
- **Consequences:** Returning Online restores effective capabilities without
  reconstructing settings. Writers use revisions and atomic replacement.

### D-028 — Separate AI-restricted connectivity from strict offline use

- **Status:** Accepted
- **Decision:** Restricted Online permits approved build/dependency/Docker/Git
  network activity while blocking direct agent HTTP, external MCP, OAuth
  network operations, and external LLM use. Strict Offline additionally blocks
  remote Git and arbitrary command execution.
- **Rationale:** Developers need an intermediate mode that keeps local AI
  private while permitting normal engineering workflows.
- **Consequences:** Restricted Online is not a network sandbox. Strict
  application policy is not an OS-wide firewall and cannot govern unrelated
  Windows or independently configured Open WebUI processes.

### D-029 — Separate distributable configuration from personal overlays

- **Status:** Accepted
- **Decision:** Tracked active JSON is a clean first-install baseline with no
  agents, MCP integrations, or local project paths. Optional machine-specific
  snapshots use ignored `config/personal-*` files and require an explicit
  installer switch.
- **Rationale:** Publishing the repository must not leak personal paths,
  integrations, or configuration history.
- **Consequences:** Generic installs require initial configuration. Personal
  overlays are local snapshots, not a versioned backup mechanism.

### D-030 — Give each lifecycle command one retention boundary

- **Status:** Accepted
- **Decision:** Install is resumable and creates stopped services; Start splits
  elevated container work from non-elevated native processes; Stop preserves
  containers; Repair recreates stopped containers; Remove deletes containers
  but preserves durable data; Uninstall is confirmed and ownership-aware.
- **Rationale:** Operators need predictable recovery and removal semantics.
- **Consequences:** Install and Repair no longer imply startup. Older setups
  without ownership state are uninstalled conservatively.

### D-031 — Use per-user shortcuts and common product branding

- **Status:** Accepted
- **Decision:** The supplied DS_ALGO PNG/ICO is used by both UIs and Windows
  shortcuts. Shortcuts are installed for the current user on the Desktop and in
  a dedicated Start Menu program folder.
- **Rationale:** The workstation is single-user and should not silently alter
  every Windows account.
- **Consequences:** Other user accounts must install their own shortcuts.

### D-032 — Separate documentation by audience and authority

- **Status:** Accepted
- **Decision:** Keep `README.md` as a concise landing page,
  `user-guide.md` as the beginner/operator authority, `dev-guide.md` as the
  contributor architecture authority, and `agentic-dev-instructions.md` as the
  reusable coding-agent contract. The former mixed `DevGuide.md` is removed.
- **Rationale:** Installation instructions, user workflows, APIs, architecture,
  and agent constraints have different readers and change at different rates.
  A 1,400-line mixed guide made important information hard to find and easy to
  duplicate inconsistently.
- **Consequences:** Changes must update the authoritative audience-specific
  document and link rather than copying complete sections between guides.

### D-033 — Validate configuration structure, not only JSON syntax

- **Status:** Accepted
- **Decision:** Install and Repair verify required top-level properties as well
  as JSON syntax. `config/projects.json` is an object containing `projects`;
  `config/agents.json` contains `agents` and `mcpServers`; runtime mode must be
  one of the supported values.
- **Rationale:** Valid JSON with the wrong shape allowed Repair to complete but
  caused Workbench to crash during initialization.
- **Consequences:** Structural mistakes fail earlier with a configuration error
  instead of a downstream process exception.

### D-034 — Explicitly route root-level branded assets

- **Status:** Accepted
- **Decision:** Studio and Workbench explicitly serve `/logo.png` and
  `/favicon.ico`; hashed application bundles remain under `/assets`.
- **Rationale:** Vite copies public files to the static root, while both
  backends previously routed only `/assets`, so valid branding files returned
  404.
- **Consequences:** New root-level public files require narrow explicit routes
  rather than a broad mount that could shadow API paths. Favicon links use a
  release cache-buster and favicon responses are not cached so a formerly
  missing icon can recover without retaining a cached 404.

### D-035 — Keep the Compose identity stable across source-directory renames

- **Status:** Accepted
- **Decision:** The source directory may be named `dsalgo-local-ai-setup`, while
  the Docker Compose project identity remains `alienware-local-ai`.
- **Rationale:** Compose uses its project identity in named-volume names.
  Renaming it at the same time as the source directory would make existing
  Open WebUI and optional-service data appear missing unless every volume were
  migrated deliberately.
- **Consequences:** Scripts derive filesystem paths from their own location and
  run correctly from the renamed directory. Backup and restore continue using
  the stable `alienware-local-ai_open-webui-data` volume. A future product-name
  migration must include an explicit, validated volume migration and rollback
  procedure.
