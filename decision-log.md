# Functionality and Architecture Decision Log

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
- **Decision:** Target a single Windows 11 user on a capable NVIDIA CUDA system
  with dedicated VRAM and sufficient system memory.
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
- **Decision:** Optional workflow, database, cache, and vector services are
  outside the core installation profile.
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
### D-045 — Workbench completion evidence and UTF-8 tool output (2026-08-01)

Workbench task results require a recorded write action, successful command/test result, or explicit no-change conclusion before status `completed`; otherwise they are marked `incomplete`. Project file reads repair clear UTF-8-as-Latin-1 mojibake without altering correctly encoded content.

### D-046 — Explicit Workbench work modes (2026-08-01)

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
## D-054 — Canonical license and installer acceptance

`LICENSE` is the sole canonical legal license and is displayed by the
installer before machine changes. A required checkbox acknowledges the MIT
license and clarifies that third-party software and models retain their own
ownership and terms.

## D-055 — Owner-controlled public releases

Contributors use pull requests and CI; releases are created only through a
protected GitHub environment controlled by the repository owner. Signing
private keys remain in protected secrets and are never committed.
