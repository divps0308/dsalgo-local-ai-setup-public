# Functionality and Architecture Decision Log

## D-046: Enforce structured progress at the Workbench boundary

- **Status:** Accepted.
- **Decision:** Goal mode may execute only structured Workbench tool calls.
  Known models without tool-calling support are rejected for Goal mode. File
  writes reject Markdown-fenced or empty content before approval, and repeated
  prose-only progress is bounded before becoming an explicit incomplete state.
- **Rationale:** Prompting alone cannot make all local models reliably emit
  executable tool calls or clean patches.
- **Consequences:** Ask and Plan remain useful for text-oriented models; Goal
  requires a tool-capable model and still requires approval for mutations.

## D-063: Recover explicit text-form tool calls conservatively

- **Status:** Accepted.
- **Decision:** The gateway may recover an explicitly formatted, allow-listed
  tool call emitted as a `tool_code`/code-fenced expression or simple JSON when
  a model omits the native Ollama `tool_calls` field. Recovered calls go through
  the unchanged permission, operating-mode, URL-safety, and approval boundary;
  ordinary prose and ambiguous expressions are returned as text and never run.
- **Rationale:** Local models vary in native tool-calling support, but silently
  executing arbitrary prose would weaken the workstation's security model.
- **Consequences:** More models can use tools, while unsupported or malformed
  pseudo-calls still produce no side effect and remain diagnosable.

## D-045: Treat independent review findings as validation work

- **Status:** Accepted.
- **Decision:** Position the current distribution as controlled-beta outside
  its Windows/NVIDIA validated path. Track blocking preflight and post-install
  checks, a versioned compatibility matrix, role-coverage validation, and
  actionable health diagnostics as release work. Treat selected-agent
  Workbench behavior (sample/custom agent by stable ID and backing model) as
  authoritative over older role-only notes.
- **Rationale:** The independent review found strong local capability and
  security boundaries, but moderate installation/reliability confidence and
  documentation contradictions.
- **Consequences:** Preserve controlled-beta wording until representative
  validation is complete; documentation cleanup is part of release quality.

## D-043: Remove unreferenced legacy root wrappers

- **Status:** Accepted.
- **Decision:** Remove `context_for_codex.md` and the unreferenced root
  `Manage-AgentStudio.ps1`, `Manage-LocalAI.ps1`, `Start-AgentStudio.ps1`,
  `Start-LocalAI.ps1`, `Stop-AgentStudio.ps1`, `Stop-LocalAI.ps1`, and
  `Update.ps1` wrappers. Keep the documented top-level lifecycle, backup,
  restore, diagnostic, WSL, and secret-management commands.
- **Rationale:** The wrappers are not called by the active installer,
  lifecycle, build, documentation, or CI paths. Keeping parallel legacy entry
  points increases ambiguity and maintenance risk.
- **Consequences:** Users must use the documented `Install.ps1`, `Start.ps1`,
  `Stop.ps1`, `Repair.ps1`, `Remove.ps1`, `Uninstall.ps1`, and supporting
  commands. Existing scripts are not changed by this cleanup.

## D-042: Recover exact text-serialized Workbench tool requests

- **Status:** Accepted.
- **Decision:** When Ollama returns no native `tool_calls`, the Workbench may
  recover one exact JSON object with `name` and `arguments` from assistant text
  if the name is already present in the Workbench tool allow-list. The request
  then uses the normal structured execution and approval path.
- **Rationale:** Small local models sometimes understand the requested action
  but serialize the tool call in a fenced JSON block instead of the native
  Ollama field. Supporting this narrow representation improves reliability
  without granting text responses arbitrary execution authority.
- **Consequences:** Malformed, unknown, multi-action, or non-object JSON is
  ignored and remains ordinary assistant text. Approval gates, project-root
  containment, operating-mode restrictions, and command allow-lists remain
  unchanged.

## D-037: Use an Ollama-only deterministic catalog and generated sample agents

- **Decision:** The installer exposes five task-oriented use cases, treats
  Ollama as the only runtime, evaluates a versioned curated catalog with fixed
  hardware/provenance scoring, and generates the installed model-role registry
  plus three enabled sample agents from the confirmed result.
- **Rationale:** Users choose intended work rather than internal enums or
  runtimes. Curated dropdowns prevent spelling-dependent provenance behavior
  and keep downloaded models aligned with active agent roles.
- **Consequences:** Catalog releases validate tags against the official Ollama
  library. Require uses OR matching and never silently relaxes. Resource
  estimates require measured validation before being described as benchmarks.

## D-038: Make recommendation selection explicit

- **Decision:** The recommendation page displays task-fit columns and requires
  the user to select between one and three conversational models. Only checked
  models are downloaded and assigned to generated model roles.
- **Rationale:** A ranked candidate list is not an installation manifest.
  Explicit selection makes download/storage cost and installed behavior clear.
- **Consequences:** Ollama stores selected models but only one conversational
  model is intended to be resident at a time. The separate embedding support
  model is included in the displayed total estimate.

## D-039: Classify cross-hardware support as controlled beta

- **Status:** Accepted; release caveat.
- **Decision:** Recommendation output remains deterministic and inference-free,
  but the public release must describe the validated NVIDIA/CUDA Windows path
  separately from unvalidated AMD, Intel, CPU-only, Vulkan, DirectML,
  unknown-VRAM, multi-GPU, and non-Windows paths.
- **Rationale:** Fixed catalog thresholds and sorting make repeatable choices,
  but they cannot establish runtime compatibility, performance, disk capacity,
  driver behavior, or model availability on hardware that has not been tested.
- **Consequences:** The installer is controlled-beta software until hardware
  matrix tests, disk gating, CPU classification, backend checks, role-coverage
  validation, hardware-derived Docker/WSL limits, and automated Ollama tag
  verification are implemented. Documentation must not describe it as a
  universal production installer.

## D-040: Use file-backed installation output monitoring in the wizard

- **Status:** Accepted.
- **Decision:** The WinForms installer starts the deployed `Install.ps1` with
  redirected stdout and stderr files, then polls those files from its UI timer
  while polling the child exit code.
- **Rationale:** PowerShell process-event callbacks in the packaged EXE could
  end the wizard host or lose output while a child installation continued.
- **Consequences:** The wizard remains visible during installation and leaves
  `runtime/installer-child.stdout.log` and `runtime/installer-child.stderr.log`
  for post-failure diagnosis.

## D-041: Preserve and conservatively merge existing WSL configuration

- **Status:** Accepted.
- **Decision:** The installer must not replace an existing user `.wslconfig`.
  It preserves existing values, adds only missing core settings, and reports
  conflicting, duplicate, or unparseable entries before asking the user to
  continue with preserved values or abort for remediation.
- **Rationale:** `.wslconfig` is machine-wide user configuration that can
  govern unrelated WSL distributions and workloads; replacing it can cause
  unrelated data loss or behavior changes.
- **Consequences:** Existing limits can prevent DSAlgo's recommended Docker/WSL
  capacity from being applied. The user can continue knowingly, or correct the
  file and rerun setup. The original is still backed up in installer runtime.

## D-036: Use a single-window installer wizard

- **Decision:** The public installer uses one topmost WinForms wizard with
  Back, Next, and Cancel navigation. Hardware review, preference collection,
  recommendations, installation output, errors, and completion remain in that
  window.
- **Rationale:** One owned window provides predictable focus and makes
  long-running prerequisite, model, and Docker operations understandable.
- **Consequences:** Child PowerShell stdout/stderr streams into the progress
  page; detailed native subprocess logs remain under `runtime`.

This living log records accepted functionality, architecture, security,
deployment, model, and user-experience decisions for DSAlgo Local AI Setup. Review
and keep it current as the repository evolves. Add an entry whenever a change
introduces, revises, supersedes, or rejects a meaningful decision. Historical
entries remain visible and are marked superseded when replaced, with a link to
the replacement decision.

## Decision format

Each entry records its status, decision, rationale, and consequences. Dates
reflect when the decision was documented when the exact original decision date
is unavailable.

## Accepted decisions

### D-001 â€” Optimize for one documented Windows workstation

- **Status:** Accepted
- **Decision:** Target a single Windows 11 user on a capable NVIDIA CUDA system
  with dedicated VRAM and sufficient system memory.
- **Rationale:** Concrete hardware assumptions allow predictable model sizing,
  WSL limits, GPU use, and operational guidance.
- **Consequences:** Multi-user, server, Linux, and macOS deployment are outside
  the supported baseline.

### D-002 â€” Run Ollama natively on Windows

- **Status:** Accepted
- **Decision:** Keep Ollama outside Docker and use native NVIDIA access.
- **Rationale:** Native execution gives the laptop GPU the simplest and most
  reliable acceleration path and avoids GPU plumbing through Docker/WSL.
- **Consequences:** Containers reach Ollama through the host boundary, and the
  system has both native and container lifecycles.

### D-003 â€” Containerize the ordinary local application plane

- **Status:** Accepted
- **Decision:** Run Open WebUI, Agent Gateway, Agent Studio, and optional data
  services in Docker Compose.
- **Rationale:** Compose supplies repeatable service isolation, networking,
  resource limits, updates, and persistence.
- **Consequences:** Docker Desktop and WSL2 are required; host-access features
  remain separate.

### D-004 â€” Keep Local Agent Studio and Developer Workbench separate

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

### D-005 â€” Run Developer Workbench natively and non-elevated

- **Status:** Accepted
- **Decision:** Host Workbench on Windows loopback rather than in Docker.
- **Rationale:** It needs controlled access to arbitrary approved Windows paths
  and installed PowerShell, Maven, Gradle, npm, .NET, Docker, Git, and other
  executables. Broad container mounts or Docker-socket access would weaken
  isolation.
- **Consequences:** Workbench has separate lifecycle scripts, does not appear
  as a Docker container, and must preserve loopback/token/project containment.

### D-006 â€” Use explicit approved project roots and mandatory approvals

- **Status:** Accepted
- **Decision:** Workbench may access only roots in `config/projects.json`;
  model-proposed writes, deletes, and native commands require approval.
- **Rationale:** Arbitrary native project access is high trust and should be
  deliberate, bounded, and reviewable.
- **Consequences:** Drive roots are rejected, path traversal is contained, and
  some autonomous workflows pause for human decisions.

### D-007 â€” Keep container agent tools confined to `workspace/`

- **Status:** Accepted
- **Decision:** Gateway file and command tools operate only in the mounted
  repository `workspace/`.
- **Rationale:** A narrow writable mount limits the blast radius of tool use.
- **Consequences:** Arbitrary Windows projects require Workbench rather than
  container agents.

### D-008 â€” Centralize models in `config/models.json`

- **Status:** Accepted
- **Decision:** Model tags, contexts, keep-alive, and runtime settings have one
  source of truth.
- **Rationale:** Duplicated settings previously created drift and unsafe model
  choices.
- **Consequences:** Scripts and Python code must read the registry rather than
  hard-code model configuration.

### D-009 â€” Centralize agents and MCP assignments in `config/agents.json`

- **Status:** Accepted
- **Decision:** Configurable agent behavior, permissions, step limits, and MCP
  assignments live in one dynamically reloaded file.
- **Rationale:** This permits reusable agents and Studio configuration without
  rebuilding the gateway.
- **Consequences:** Changes affect subsequent requests; secrets are prohibited
  from this file.

### D-010 â€” Preserve an OpenAI-compatible gateway contract

- **Status:** Accepted
- **Decision:** Expose `/v1/models` and `/v1/chat/completions`.
- **Rationale:** Open WebUI can treat local agents as an external
  OpenAI-compatible connection without custom frontend integration.
- **Consequences:** Open WebUI may label gateway agents â€œExternalâ€ even though
  inference ultimately runs through local Ollama.

### D-011 â€” Prefer one resident generation model

- **Status:** Accepted
- **Decision:** Use pinned 14B Q4 models, bounded context sizes, and keep only one
  generation model resident when practical.
- **Rationale:** The 24 GB GPU needs headroom for reliable inference and other
  applications.
- **Consequences:** Orchestration can trigger model swaps and is reserved for
  complex tasks where independent review justifies latency.

### D-012 â€” Preserve at least 24 GB outside Docker/WSL

- **Status:** Accepted
- **Decision:** Default WSL/Docker profiles leave substantial RAM to Windows and
  native Ollama.
- **Rationale:** Unbounded WSL memory can starve the host and cause model
  fallback or instability.
- **Consequences:** Optional services may need alternate profiles and cannot be
  assumed always active.

### D-013 â€” Keep optional services behind Compose profiles

- **Status:** Accepted
- **Decision:** Optional workflow, database, cache, and vector services are
  outside the core installation profile.
- **Rationale:** Idle developer services should not consume scarce laptop RAM.
- **Consequences:** Their endpoints are unavailable until explicitly started.

### D-014 â€” Store static MCP secrets with Windows DPAPI references

- **Status:** Accepted
- **Decision:** Never store plaintext MCP secrets in agent configuration; use
  `secretHeaders` references and `Set-McpSecret.ps1`.
- **Rationale:** Configuration, logs, backups, and UI must not expose
  credentials.
- **Consequences:** Studio does not display secret values, and static-secret
  testing has intentional visibility constraints.

### D-015 â€” Use a native OAuth broker for MCP OAuth 2.1

- **Status:** Accepted
- **Decision:** Perform OAuth discovery, browser authorization, PKCE, callback,
  token exchange, refresh, and DPAPI storage in a loopback Windows broker at
  `localhost:3003`.
- **Rationale:** Browser callbacks and Windows-bound secret storage fit a native
  process better than a container; refresh tokens must not persist in the
  gateway.
- **Consequences:** Containers request short-lived access tokens through a
  runtime-authenticated broker. The broker has a separate lifecycle.

### D-016 â€” Treat MCP servers as privileged and disabled by default

- **Status:** Accepted
- **Decision:** Connect only trusted Streamable HTTP MCP servers, assign them
  per agent, and apply least-privilege credentials/scopes.
- **Rationale:** MCP tools can read external data or perform external actions.
- **Consequences:** Configuration saved, OAuth connected, and tools operational
  are separate states that the UI and documentation must distinguish.

### D-017 â€” Do not expose local services publicly

- **Status:** Accepted
- **Decision:** Preserve localhost/loopback assumptions for Studio, Workbench,
  OAuth broker, and other management surfaces.
- **Rationale:** The baseline lacks internet-facing authentication, RBAC, and
  hardened multi-user controls.
- **Consequences:** Public tunnels, router forwarding, or non-loopback binding
  require explicit security redesign.

### D-018 â€” Give Workbench remote-impact Git actions explicit confirmation

- **Status:** Accepted
- **Decision:** Separate read-only status/diff, local branch/commit actions, and
  remote push actions. Confirm push and other material actions.
- **Rationale:** Local inspection, repository mutation, and remote impact have
  different risk levels.
- **Consequences:** Push is not styled as destructive deletion, but it is
  visually distinct and confirmation-gated.

### D-019 â€” Build Studio and Workbench with one shared Svelte design system

- **Status:** Accepted
- **Decision:** Use Svelte 5, TypeScript, Vite, shared local components, CSS
  tokens, and Lucide icons while preserving separate product applications.
- **Rationale:** The former embedded HTML prototypes lacked hierarchy,
  responsiveness, accessibility, and maintainable component structure.
- **Consequences:** The products look and behave consistently without sharing
  their privileged backend. Frontend development requires Node/pnpm.

### D-020 â€” Commit compiled frontend assets

- **Status:** Accepted
- **Decision:** Store production assets in `agent-studio/static/` and
  `developer-workbench/static/`.
- **Rationale:** Normal install, repair, and runtime should not depend on a Node
  toolchain.
- **Consequences:** Source changes must run type checks and rebuild both asset
  directories before completion.

### D-021 â€” Support System, Light, and Dark themes

- **Status:** Accepted
- **Decision:** Default to OS appearance, allow explicit Light/Dark selection,
  persist it in browser storage, and apply it before first paint.
- **Rationale:** Both local tools need a professional, accessible experience
  across working environments.
- **Consequences:** Preferences are local to each browser profile.

### D-022 â€” Use contextual help and least-privilege explanations

- **Status:** Accepted
- **Decision:** Provide searchable page help, accessible tooltips, semantic
  action hierarchy, diagnostics, toasts, and confirmation dialogs.
- **Rationale:** Tool permissions, OAuth, native commands, and Git actions are
  consequential and should be understandable at the point of use.
- **Consequences:** Help content must remain synchronized with real behavior
  and must not become the only source of critical safety information.

### D-023 â€” Do not fabricate unsupported UI data

- **Status:** Accepted
- **Decision:** Show only fields and states returned by existing backends.
- **Rationale:** Fake repository status, timestamps, progress, health history,
  or remote information would mislead users.
- **Consequences:** Some requested summaries remain absent until backend
  contracts provide them and are tracked in `to-do.md`.

### D-024 â€” Favor a reliable local agent stack over a workflow platform

- **Status:** Accepted
- **Decision:** Version 5 does not treat workflow canvases, enterprise
  connectors, scheduling/versioning, an independent MCP proxy, or full
  observability as baseline requirements.
- **Rationale:** Reliability, bounded resources, privacy, and maintainability on
  one laptop take priority over platform breadth.
- **Consequences:** Add such capabilities only for a concrete workflow with a
  deliberate architecture and security decision.

### D-025 â€” Maintain explicit operational and architectural records

- **Status:** Accepted
- **Decision:** `to-do.md` is the canonical limitation/to-do register and
  `decision-log.md` is the canonical functionality/architecture decision log.
  Both are reviewed with every change.
- **Rationale:** Known gaps and the reasoning behind the system should survive
  individual chats and implementation iterations.
- **Consequences:** Resolved limitations require changelog evidence; changed
  decisions are superseded rather than silently erased.

### D-026 â€” Use clean, non-compatible agent naming

- **Status:** Accepted
- **Decision:** Built-ins retain `agent-*`; setup agents use immutable `my-*`
  keys and `My ...` names; Studio-created agents use immutable `my-custom-*`
  keys and `My Custom â€” ...` names. No legacy IDs or aliases are retained.
- **Rationale:** A clean-install baseline is preferred over compatibility, and
  the categories must be visibly distinct from raw Ollama model tags.
- **Consequences:** Existing callers using old configured IDs must select a
  renamed agent.

### D-027 â€” Centralize connectivity as a reversible policy overlay

- **Status:** Accepted
- **Decision:** `config/runtime-policy.json` is the source of truth for Online,
  Restricted Online, and Strict Offline. Both UIs share it and every relevant
  backend enforces it independently.
- **Rationale:** A policy overlay preserves configuration and prevents direct
  API calls from bypassing disabled frontend controls.
- **Consequences:** Returning Online restores effective capabilities without
  reconstructing settings. Writers use revisions and atomic replacement.

### D-028 â€” Separate AI-restricted connectivity from strict offline use

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

### D-029 â€” Separate distributable configuration from personal overlays

- **Status:** Accepted
- **Decision:** Tracked active JSON is a clean first-install baseline with no
  agents, MCP integrations, or local project paths. Optional machine-specific
  snapshots use ignored `config/personal-*` files and require an explicit
  installer switch.
- **Rationale:** Publishing the repository must not leak personal paths,
  integrations, or configuration history.
- **Consequences:** Generic installs require initial configuration. Personal
  overlays are local snapshots, not a versioned backup mechanism.

### D-030 â€” Give each lifecycle command one retention boundary

- **Status:** Accepted
- **Decision:** Install is resumable and creates stopped services; Start splits
  elevated container work from non-elevated native processes; Stop preserves
  containers; Repair recreates stopped containers; Remove deletes containers
  but preserves durable data; Uninstall is confirmed and ownership-aware.
- **Rationale:** Operators need predictable recovery and removal semantics.
- **Consequences:** Install and Repair no longer imply startup. Older setups
  without ownership state are uninstalled conservatively.

### D-031 â€” Use per-user shortcuts and common product branding

- **Status:** Accepted
- **Decision:** The supplied DS_ALGO PNG/ICO is used by both UIs and Windows
  shortcuts. Shortcuts are installed for the current user on the Desktop and in
  a dedicated Start Menu program folder.
- **Rationale:** The workstation is single-user and should not silently alter
  every Windows account.
- **Consequences:** Other user accounts must install their own shortcuts.

### D-032 â€” Separate documentation by audience and authority

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

### D-033 â€” Validate configuration structure, not only JSON syntax

- **Status:** Accepted
- **Decision:** Install and Repair verify required top-level properties as well
  as JSON syntax. `config/projects.json` is an object containing `projects`;
  `config/agents.json` contains `agents` and `mcpServers`; runtime mode must be
  one of the supported values.
- **Rationale:** Valid JSON with the wrong shape allowed Repair to complete but
  caused Workbench to crash during initialization.
- **Consequences:** Structural mistakes fail earlier with a configuration error
  instead of a downstream process exception.

### D-034 â€” Explicitly route root-level branded assets

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

### D-035 â€” Keep the Compose identity stable across source-directory renames

- **Status:** Accepted
- **Decision:** The source directory may be renamed without changing the Docker
  Compose project identity used by an existing installation.
- **Rationale:** Compose uses its project identity in named-volume names.
  Renaming it at the same time as the source directory would make existing
  Open WebUI and optional-service data appear missing unless every volume were
  migrated deliberately.
- **Consequences:** Scripts derive filesystem paths from their own location and
  run correctly from the renamed directory. Backup and restore continue using
  the existing Open WebUI data volume. A future product-name
  migration must include an explicit, validated volume migration and rollback
  procedure.

### D-037 - Use a hybrid Windows architecture as the primary distribution

- **Status:** Accepted
- **Decision:** Keep Ollama native on Windows for direct NVIDIA GPU access, and
  use WSL2/Docker Desktop for Open WebUI, the gateway, databases, and supporting
  services. Use PowerShell for installation and lifecycle management, with
  localhost-only service exposure.
- **Rationale:** On Windows, this balances GPU performance, service isolation,
  reproducibility, and maintainability better than either a fully containerized
  GPU path or a fully native multi-service deployment.
- **Consequences:** The validated distribution requires Windows with WSL2 and
  Docker Desktop. A fully native Windows profile may reduce overhead and startup
  time, but would require a separate design for dependency management,
  persistence, networking, health checks, upgrades, and uninstall behavior; it
  remains future work rather than an alternate install switch today.

### D-038 - Make packaged lifecycle commands self-contained Windows entry points

- **Status:** Accepted
- **Decision:** Packaged lifecycle EXEs resolve their installed root, request
  UAC elevation when their operation requires it, preserve forwarded options,
  invoke helper PowerShell processes directly for reliable native exit codes,
  and retain helper stdout/stderr under `runtime`. Shortcut creation must
  verify that Windows persisted a non-empty executable target.
- **Rationale:** Start Menu and Desktop entry points must behave predictably
  without requiring users to open PowerShell, and PS2EXE-hosted wrappers cannot
  safely treat an unrefreshed `Start-Process` result as an authoritative exit
  code.
- **Consequences:** Start remains non-elevated for native Workbench/OAuth
  processes and elevates only its container phase. Repair, Remove, and
  Uninstall display UAC themselves. Packaged lifecycle behavior still requires
  end-to-end validation on supported Windows versions.

### D-039 - Do not silently trust the self-signed release certificate

- **Status:** Accepted
- **Decision:** Sign local release artifacts with the configured self-signed
  code-signing certificate and verify the signer thumbprint, but do not import
  that certificate into Trusted Root or Trusted Publishers during a build.
- **Rationale:** Producing a signature and deciding to trust an issuer are
  separate security decisions. A build must not weaken the current user's
  Windows trust policy as a side effect.
- **Consequences:** Authenticode identifies the signer and protects artifact
  integrity, but Windows can correctly show an untrusted/self-signed publisher
  warning unless the user independently verifies and trusts the certificate.

### D-040 - Permit the public environment template in Git safety checks

- **Status:** Accepted
- **Decision:** Treat only the exact `.env` path as machine-local in
  `Test-GitSafety.ps1`; `.env.example` remains an allowed public template.
- **Rationale:** The repository must publish its documented environment
  contract without allowing local secrets or generated credentials into Git.
- **Consequences:** The safety check now matches `.gitignore`: `.env` is
  rejected while `.env.example` is intentionally trackable.

### D-041 - Keep runtime state writable by the signed-in operator

- **Status:** Accepted
- **Decision:** Elevated installation grants the signed-in Windows user Modify
  access to the installation's generated `runtime` directory. Start opens the
  three local web surfaces with the system default browser after startup.
- **Rationale:** Containers require elevation during installation/start, while
  native Workbench, OAuth, and lifecycle logging must remain usable from a
  normal user session.
- **Consequences:** Runtime logs and PID files are user-writable operational
  state; secrets remain protected by their existing DPAPI and file-boundary
  controls. Browser tab/window behavior remains subject to the user's default
  browser settings.

### D-042 - Resolve native child roots and spaced Python paths explicitly

- **Status:** Accepted
- **Decision:** Native OAuth and Workbench launchers assign the selected
  installation root after loading shared helpers and quote Python application
  paths when invoking `Start-Process`.
- **Rationale:** PowerShell invocation scopes can leave `$PSScriptRoot` empty
  inside `Invoke-Expression`, and the installed default path contains spaces.
  Either condition can prevent native services from starting while containers
  continue running.
- **Consequences:** Native services start independently of the current working
  directory and support installation paths containing spaces. Browser launch
  remains a post-start action and follows default-browser behavior.
### D-043 Agent model assignment semantics

Agent Studio custom agents expose two separate choices: an installed Ollama
model tag (`modelTag`) and a preferred-use role (General Conversation (Chat),
Reasoning, Coding, Deep Research, or All). The gateway uses the selected tag
when present. Tasks must select an enabled agent with a resolvable backing
model; role-only task execution is not supported.

### D-044 Workbench task agent selection

Workbench tasks now select an enabled sample or custom agent by stable ID. The
backend resolves its configured backing model tag deterministically and retains
without role fallback. This aligns task execution with Local Agent Studio
configuration without weakening approval gates.
### D-045 â€” Workbench completion evidence and UTF-8 tool output (2026-08-01)

Workbench task results require a recorded write action, successful command/test result, or explicit no-change conclusion before status `completed`; otherwise they are marked `incomplete`. Project file reads repair clear UTF-8-as-Latin-1 mojibake without altering correctly encoded content.

### D-046 â€” Explicit Workbench work modes (2026-08-01)

Ask and Plan modes expose only read/search tools; Goal retains the existing approval-gated write and command workflow. Plan artifacts are saved by the Workbench under `.workbench-plans` only after an explicit approval, with timestamped unique names.

### D-047 - Approval requests must be tool-mediated (2026-08-01)

Workbench agents must invoke an approval-gated tool for edits and commands;
asking for approval in response prose does not create an actionable UI card.
Goal-mode instructions direct agents to use the tool path and continue until
implementation or a concrete blocker is recorded.

### D-048 - Uninstall data-retention choice (2026-08-01)

Uninstall defaults to retaining installer-owned Docker images, volumes, and
downloaded Ollama models. A separate unchecked purge option is presented in the
uninstall wizard; only when explicitly selected are those resources removed.

### D-049 - Goal completion requires a conclusion (2026-08-01)

Goal-mode Workbench tasks do not become complete merely because one approved
action succeeded. The final response must contain completion/verification
evidence and must not indicate that work remains; otherwise the task remains
incomplete so the agent can continue.

### D-050 - Goal progress responses are resumable (2026-08-01)

When a Goal response fails the completion-quality check, the Workbench keeps
the conversation active and sends explicit continuation feedback instead of
finalizing the task as incomplete. The agent can therefore inspect more files,
request subsequent approvals, and verify the remaining scope. A bounded
tool-step limit remains as a safety stop and is reported as a failure requiring
user review rather than being presented as successful completion.

### D-051 - Uninstall removes the installer-owned application directory (2026-08-01)

Uninstall now schedules detached deletion of the installed application root
after cleanup, because uninstall.exe may still be running from that directory.
Deletion is guarded by the installer-state marker and rejects unsafe roots;
external registered project roots and source checkouts without that marker are
not removed.

### D-052 - Goal loops require a concrete blocker guard (2026-08-01)

Goal mode continues after incomplete progress, but repeated identical
no-tool responses and explicit missing-dependency installation requests are
treated as actionable blockers. The task is marked incomplete with remediation
instead of repeatedly consuming the tool-step budget or claiming success.

### D-053 - Agent-specific tool-step limits (2026-08-01)

Workbench execution uses the selected agent's configured `maxSteps` value,
bounded by a defensive maximum of 1000 steps. This replaces the previous
hard-coded 30-step execution limit while retaining explicit blocker and
repetition guards.

### D-056 - Structured Workbench protocol at the model boundary (2026-08-05)

Workbench tasks use protocol version 1 for model/tool exchange. Native
`tool_calls` and the narrowly scoped JSON compatibility envelope are normalized
to known Workbench functions; ordinary prose is never interpreted as a command.
Tool results are returned to the model in a JSON envelope. Goal mode requires
structured actions and completion evidence, retries actionable prose as
incomplete progress, and stops with an explicit incomplete state after its
existing safety guards are reached. This improves interoperability with local
models without claiming that every model reliably supports tool calling.
Goal requests also ask Ollama for JSON-formatted output when supported; a
single compatibility retry omits that option for older Ollama versions.
## D-054 â€” Canonical license and installer acceptance

`LICENSE` is the sole canonical legal license and is displayed by the
installer before machine changes. A required checkbox acknowledges the MIT
license and clarifies that third-party software and models retain their own
ownership and terms.

## D-055 â€” Owner-controlled public releases

Contributors use pull requests and CI; releases are created only through a
protected GitHub environment controlled by the repository owner. Signing
private keys remain in protected secrets and are never committed.
### D-057 - No-op and repeated proposal protection (2026-08-05)

Workbench write proposals are compared with the current file before an
approval card is created. Identical content produces a no-op tool result rather
than an approval request. Repeated identical tool requests are bounded and end
in an explicit incomplete state so Goal mode cannot trap the user in approval
loops.

### D-058 - Controller-owned cross-model Goal protocol (2026-08-05)

Goal mode treats every model as an untrusted protocol client. The Workbench
owns the canonical tool schemas, validates complete argument objects before
dispatch, normalizes only documented unambiguous aliases, and returns bounded
structured repair errors to malformed callers. It also requires verification
after the final mutation and bounds repeated or no-progress tool loops. These controls
provide consistent safety and failure semantics across models without claiming
that every model has equivalent reasoning or coding ability.

### D-059 - Evidence-based Goal progress and completion (2026-08-06)

The Workbench does not count a successful process exit as progress by itself.
Progress is reset only by a real file mutation, a recognized build/test/
verification command, or inspection after a mutation. Completion-only output
commands are rejected and semantically equivalent claim commands are treated as
duplicates. A completion claim without executable verification receives one
repair request; repetition ends the task as incomplete. Requests involving
compilation, builds, tests, or verification require successful matching evidence
and cannot be completed from a diff alone.

### D-061 - Explicit web-tool instruction (2026-08-06)

When an agent has the `http_get` permission, the gateway adds a system-level
instruction requiring that tool for current or external information and
requiring transparent reporting when it fails. Agents without the permission
are instructed not to claim live web access. Runtime policy remains authoritative
and removes the tool in Restricted Online and Strict Offline modes.

### D-062 - Contextual Help Center coverage (2026-08-06)

Local Agent Studio and Developer Workbench use screen-context help topics as
the definitive first-run guide. Topics describe visible controls, side
effects, permissions, policy boundaries, approval semantics, and remediation.
The shared drawer accepts nested section names so tool guidance remains visible
from its parent screen. New UI controls must add or update corresponding topics.

### D-060 - Bounded multimodal gateway input (2026-08-06)

The gateway normalizes OpenAI-compatible text/image/document content blocks into
Ollama-compatible messages. Only local base64 data URLs for common image types
and supported text-bearing documents are accepted, with 12 MB image and 20 MB
document limits; remote URLs and unsupported blocks are rejected with actionable
client errors. DOCX is extracted without executing embedded content, while PDF
text extraction uses the pinned `pypdf` dependency. This preserves attachment
permissions and SSRF boundaries while allowing configured models to inspect
local files. Vision and extraction quality remain model-dependent and require
validation.

### D-063 - Install-time Windows-to-IANA time-zone resolution (2026-08-06)

New environment files contain a time-zone placeholder that `Ensure-Env`
replaces with the current Windows system time zone expressed as an IANA ID.
Windows PowerShell 5.1 lacks a built-in converter, so the release carries the
Unicode CLDR global Windows-zone mapping plus explicit compatibility entries
for retired IDs still exposed by supported Windows versions, and performs the
conversion offline.
Existing non-placeholder `TZ` values are never rewritten. An unknown Windows
ID stops initialization with remediation guidance rather than silently using
the wrong local time; Compose uses UTC only when `TZ` is entirely absent.

### D-064 - Retire the separate project-context document (2026-08-06)

The removed `docs` directory and its former project-context document are not
part of the documentation set. `README.md` remains the mission and scope
authority, while `dev-guide.md` remains the architecture authority. Maintainer
instructions, documentation maps, checklists, and user-facing links no longer
reference the retired document.

### D-065 - Publish releases as complete extracted bundles (2026-08-06)

The release workflow publishes one ZIP containing all generated executables,
verification files, certificate, and the installer-required `payload` folder.
The installer is intentionally distributed beside its payload rather than
duplicating that payload inside each executable, so users must extract the
bundle before launching `install.exe`.

### D-066 - Resolve the license from the extracted payload (2026-08-06)

The installer accepts the canonical `LICENSE` from either the release root or
the adjacent `payload` directory. Complete release bundles keep repository
content under `payload`, so the installer must validate the license there
before displaying the acceptance page.

### D-067 - Derive WSL resources from detected hardware (2026-08-06)

**Superseded by D-070 for the allocation policy; hardware detection remains.**

The installer now writes the WSL/Docker core profile from detected logical
processors and system RAM. Comfortable reserves roughly 35% of RAM and half
the logical processors; Aggressive reserves roughly 15% and permits all
logical processors. Swap is derived from the selected memory limit and capped
at 16 GB. Existing `.wslconfig` values continue to win during conservative
merge.

# D-068: Conservative WSL merge and Docker readiness

- **Decision:** Preserve existing `.wslconfig` resource values when they are
  equal to or above the generated recommendation. If memory, processors, or
  swap are below it, offer an explicit overwrite (with the existing backup
  path shown) or exit without changes. Check Docker Desktop for updates and
  wait up to ten minutes for the engine before proceeding.
- **Rationale:** User-owned WSL settings should not trigger unnecessary
  warnings, while undersized settings need an informed, reversible choice.
  Docker startup and update time vary substantially across machines.
- **Consequence:** Users may retain larger-than-recommended WSL allocations;
  update checks depend on winget, and Docker readiness can delay installation.
# D-069: PowerShell-compatible configuration expressions

- **Decision:** Evaluate conditional resource and model configuration values
  in intermediate variables before using them in arithmetic or hashtables.
- **Rationale:** Windows PowerShell does not accept every inline `if` form as
  an expression; the packaged wizard must work on the supported shell.
- **Consequence:** The generated configuration is unchanged, but preparation
  avoids the misleading “if is not recognized” failure.
# D-070: Fixed 50% resource allocation

- **Decision:** The installer no longer asks users to choose Comfortable or
  Aggressive allocation. It generates WSL/Docker memory, processor, and swap
  from approximately half of detected RAM and logical processors. GPU model
  recommendations may use the full detected dedicated VRAM; Ollama manages
  actual GPU utilization at runtime.
- **Rationale:** A single conservative default is easier to understand and
  keeps comparable behavior across machines while preserving resources for
  Windows and native Ollama.
- **Consequence:** Users who need a different split must edit `.wslconfig`
  after installation; lower existing values still require explicit overwrite.

# D-071: Keep fixed-allocation guidance below preference controls

- **Decision:** Place the fixed resource-allocation explanation below the
  provenance controls in the installer wizard.
- **Rationale:** The previous position overlapped the model provenance row on
  compact Windows rendering and made the form difficult to read.
- **Consequence:** The page uses the existing vertical space more deliberately
  without changing any selection or recommendation behavior.

# D-072: Pin release builds to Node 24

- **Decision:** Release Actions use Node.js 24, and both Vite app roots provide
  explicit Svelte configuration. The known legacy form-dialog diagnostic is
  filtered while preserving other compiler warnings.
- **Rationale:** Keep release tooling current and eliminate non-actionable
  frontend build noise without changing application behavior.
- **Consequence:** Node 24 is now part of the release build requirement and
  frontend accessibility changes should still be reviewed when dialog markup
  is next refactored.

# D-073: Show complete model catalog classification

- **Decision:** Display all catalog models in recommended, supported-but-
  filtered, and unsupported categories. Only the first two are selectable,
  with a maximum of three models.
- **Rationale:** Users can see why a model was not recommended without losing
  hardware and preference safety filtering.
- **Consequence:** The review page contains more categorized rows; eligibility
  remains enforced by RAM and VRAM thresholds.

# D-074: Use explicit PowerShell constructor arguments in dynamic UI layout

- **Decision:** Construct dynamic WinForms points and sizes with
  `New-Object -ArgumentList`.
- **Rationale:** Windows PowerShell 5.1 can interpret parenthesized constructor
  syntax as multiple command arguments, causing the categorized review page to
  fail before it renders.
- **Consequence:** The layout is compatible with both source execution and
  PS2EXE-generated installers.

# D-075: Allocate 20% RAM to WSL/Docker

- **Decision:** Generate the WSL memory limit from approximately 20% of
  detected system RAM, retain 50% of logical processors for WSL, and use the
  remaining approximately 80% RAM for native Ollama model recommendations.
- **Rationale:** The container stack is lighter than model inference, so a
  smaller WSL memory cap leaves more host RAM for native Ollama.
- **Consequence:** Low-memory systems may still need a larger custom
  `.wslconfig`; the existing lower-value overwrite prompt remains in force.

# D-076: Foreground installer dialogs

- **Decision:** Installer message boxes are owned by the visible wizard or a
  temporary topmost owner window.
- **Rationale:** Child configuration processes can otherwise display warnings
  behind the main installer, making required decisions appear to be missing.
- **Consequence:** Dialogs remain modal and appear in front of other windows;
  no installation behavior or message content changes.

# D-077: Foreground all executable wizard dialogs

- **Decision:** Keep lifecycle wizard forms topmost and make the installer
  folder picker an owned dialog, alongside existing owned message boxes.
- **Rationale:** Every user decision or picker must remain visible when other
  windows have focus.
- **Consequence:** Dialog modality and normal cancellation behavior are
  preserved across lifecycle executables.

# D-078: Keep child WSL prompt foreground during choice

- **Decision:** Use a visible, borderless, activated topmost owner for the
  WSL confirmation message box and pump WinForms events before showing it.
- **Rationale:** A transparent 1x1 owner could lose foreground priority to the
  parent installer while the modal prompt was still open.
- **Consequence:** The prompt remains associated with the child configuration
  process until the user selects an option.
# D-079: Make categorized model selection state explicit

- **Decision:** Commit checkbox edits from each selectable category grid using
  its event sender, and label categories with more than two rows as scrollable.
- **Rationale:** A shared closure could commit the wrong grid, causing the
  summary count to lag behind visible selections; compact grids need a clear
  affordance for additional rows.
- **Consequence:** Selection counts update consistently across categories and
  users are told when scrolling is required.

# D-080: Use a dedicated topmost WSL decision form

- **Decision:** Show WSL overwrite/exit choices in a dedicated topmost modal
  form rather than a child-process message box.
- **Rationale:** The parent installer can reclaim foreground focus from a
  standard message box after startup.
- **Consequence:** The prompt has explicit Overwrite and Exit labels and stays
  modal until the user makes a choice.

# D-081: Fail visibly if the WSL prompt cannot initialize

- **Decision:** Make the WSL prompt taskbar-visible and provide a visible
  message-box fallback instead of reading hidden console input.
- **Rationale:** A failed child GUI prompt must never leave the installer
  blocked indefinitely.
- **Consequence:** Prompt initialization failures now surface as an explicit
  error or fallback dialog.

# D-083: Do not fallback after an intentional WSL exit

- **Decision:** Treat the primary dialog's Exit result as a terminal user
  decision and bypass fallback prompt handling.
- **Rationale:** Catch-all fallback logic previously interpreted the deliberate
  cancellation exception as a prompt failure, creating a duplicate dialog.
- **Consequence:** Exit produces one prompt and a clean setup stop; fallback is
  reserved for genuine dialog initialization failures.

# D-084: Persist WSL overwrites without duplicate keys

- **Decision:** Treat existing WSL keys as replacements, not missing entries,
  and persist changes even when the number of lines is unchanged.
- **Rationale:** The previous merge appended replacement values and skipped the
  write when only existing lines changed.
- **Consequence:** Overwrite produces one authoritative memory, processor, and
  swap entry per section.

# D-085: Handle winget no-update result

- **Decision:** Suppress Docker update warnings when winget explicitly reports
  that no newer package version is available.
- **Rationale:** winget returns a non-zero status for this informational result
  on some versions, even though the update check succeeded.
- **Consequence:** Genuine update-check failures remain warnings with log
  paths; an already-current Docker Desktop install is silent.

# D-086: Track current Qwen3 Ollama tag

- **Decision:** Use `qwen3:0.6b` in the catalog instead of the unavailable
  `qwen3:0.5b` tag.
- **Rationale:** Ollama returns `pull model manifest: file does not exist` for
  the old tag; the current Qwen3 catalog exposes the 0.6B model.
- **Consequence:** New installs download the valid small CPU-compatible Qwen3
model; existing installs must rerun model setup to change tags.

# D-087: Revalidate Ollama catalog tags

- **Decision:** Replace the unavailable `gpt-oss:8b` tag with `gpt-oss:20b`
  and qualify Kimi-VL with its published `richardyoung` namespace.
- **Rationale:** Official Ollama pages list GPT-OSS 20B/120B and the Kimi-VL
  model under the community namespace; the old entries were not pullable.
- **Consequence:** The catalog now points at currently published tags, with
  updated model sizes and hardware thresholds.

# D-088: Fetch the recommendation catalog at install time

- **Decision:** Remove the bundled `config/model-catalog.json`; installer
  recommendation screens fetch JSON from the DSAlgo catalog service over HTTPS.
- **Rationale:** Catalog entries and Ollama availability can change independently
  of installer releases.
- **Consequence:** Catalog updates no longer require rebuilding the installer;
  installs require access to the catalog endpoint and validate schema version 2
  and a non-empty model list before continuing.

# D-082: Release persistent installer foreground forcing

- **Decision:** Make the installer topmost only during its initial display,
  then clear `TopMost` and remove the foreground-reassertion timer.
- **Rationale:** Persistent foreground forcing displaced child dialogs and
  prevented users from moving the installer behind other windows.
- **Consequence:** The parent wizard behaves as a normal window after launch;
  its owned modal dialogs still remain in front while active.
