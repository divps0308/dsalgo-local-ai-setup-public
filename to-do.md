# Limitations and To-Do Register

This is the canonical register for known limitations, unsupported behavior,
validation gaps, operational constraints, deliberate tradeoffs, and follow-up
work in Alienware Local AI. Review and update it with every repository change.
Remove an item only after it has been demonstrably resolved and record the
resolution in `CHANGELOG.md` and any resulting decision in `decision-log.md`.

## Installation and lifecycle limitations

- Install ownership/resume state begins with this release. Older installations
  have no reliable ownership history, so Uninstall avoids removing software or
  Windows features it cannot prove this project installed.
- Desktop and Start Menu shortcuts are created only for the Windows user that
  runs Install or Repair.
- Start requires interactive UAC approval and rejects execution from an already
  elevated shell so Workbench and OAuth do not inherit Administrator rights.
- Repair requires Docker Desktop to be running even though rebuilt application
  services remain stopped afterward.
- Personal configuration overlays are untracked local snapshots; Git does not
  back them up.
- The Docker Compose project identity remains `alienware-local-ai` for
  compatibility with existing named volumes after the source directory was
  renamed to `dsalgo-local-ai-setup`. Changing that identity requires an
  explicit data-volume migration.
- Uninstall retains the source directory and all registered external project
  directories. Removing source remains a deliberate manual filesystem action.
- Repository Git hooks are specified by `agentic-dev-instructions.md` and
  `dev-guide.md`, but a Git repository must be initialized and
  `core.hooksPath` configured before hooks can enforce local commits.
- Mermaid architecture diagrams require a Markdown renderer with Mermaid
  support; plain text viewers still show the underlying diagram source.
- An OAuth broker already listening on port 3003 without its runtime PID file
  is treated as healthy but cannot be safely adopted or stopped by the current
  lifecycle scripts. Add verified process adoption or a single-instance lock;
  never terminate an unknown listener solely by port number.

## Architectural and platform limitations

### Deployment and lifecycle

- The supported target is a single Windows 11 user on the documented Alienware
  hardware profile. Multi-user tenancy, shared-host isolation, Linux/macOS host
  installation, and production server deployment are not supported.
- Ollama runs natively on Windows for direct NVIDIA access, while Open WebUI,
  Agent Gateway, Agent Studio, and optional services run in Docker/WSL2.
  Developer Workbench and the OAuth broker are separate native processes; the
  project is therefore not one self-contained deployment unit.
- Initial installation, WSL feature changes, and some repairs require elevated
  PowerShell. Developer Workbench and the OAuth broker should not run elevated.
- A `.wslconfig` change requires `wsl --shutdown` and a Docker Desktop restart.
  Automating that step can interrupt unrelated WSL workloads.
- Native Workbench and OAuth broker processes have separate start/stop
  lifecycles and do not start at Windows sign-in unless the user configures it.
- Temporal, PostgreSQL, Redis, and Qdrant remain optional Compose profiles and
  are unavailable until explicitly started.
- This setup directory may not be a Git repository, so history, rollback,
  branches, and pull-request workflows are not always available for the stack.

### Hardware and model constraints

- A 24 GB laptop GPU cannot reliably keep multiple 14B generation models
  resident. Orchestration can cause model swaps, latency, and memory pressure.
- Selected 14B Q4 models and bounded contexts trade model quality and context
  capacity for reliable local execution and VRAM headroom.
- Docker/WSL memory is capped to preserve Windows and native Ollama headroom.
  Large optional workloads can still compete for RAM.
- Local inference does not guarantee correctness, current knowledge, source
  accuracy, or deterministic tool use. Human review remains mandatory.
- Models and container images must be downloaded before offline use. Unloaded
  models add cold-start latency; unloading does not uninstall them.

### Security and trust boundaries

- The stack is localhost-oriented and has no internet-facing reverse proxy,
  centralized identity provider, RBAC, or multi-user audit boundary.
- Agent Studio and Developer Workbench intentionally remain separate
  applications. Studio is a containerized configuration surface; Workbench is
  a higher-trust native Windows execution surface. A combined application would
  blur authentication, filesystem, command-execution, and deployment
  boundaries.
- Agent Studio has no independent login. Workbench and OAuth broker use
  loopback runtime tokens rather than a general user identity system.
- URL-fetch protections and path containment reduce risk but cannot establish
  that remote content, MCP tools, model output, or approved commands are safe.
- Backups exclude plaintext/runtime secrets. Restores may require secrets and
  OAuth grants to be configured again.
- Restricted Online blocks direct AI/MCP connectivity but is not a network
  sandbox: approved build tools, plugins, project scripts, Docker, and Git may
  still contact arbitrary endpoints.
- Strict Offline prevents intentional outbound actions in project-controlled
  paths, but OS-wide certainty requires Windows Firewall controls because
  unrelated processes and separately configured Open WebUI integrations are
  outside this policy.
- There is no full observability suite, distributed tracing, durable metrics
  history, or integrated Grafana/Loki baseline.

### Deliberate version 5 non-goals

- No LangFlow/n8n-style visual workflow canvas.
- No baseline enterprise connector catalogue, workflow scheduler/versioning,
  independent MCP proxy product, or full observability platform.
- No complete hosted Codex/GitHub collaboration service with team comments,
  remote review management, and pull-request orchestration.

## Backend limitations and to-dos

### Open WebUI, models, and Agent Gateway

- Raw Ollama models do not gain agent tools merely by being selected.
- Open WebUI Workspace presets are separate from installed Ollama models and
  gateway agents; installed models do not automatically appear as editable
  Workspace presets.
- Switching models affects later messages and does not regenerate history.
- Gateway file and command tools are confined to this repository's
  `workspace/`; arbitrary Windows project access requires Workbench.
- Gateway commands are allow-listed and sandboxed. Arbitrary native Windows
  executables require Workbench and explicit approval.
- Agent configuration reload affects later requests only, not in-flight
  requests or previous messages.
- Multi-agent orchestration is slower and more resource-intensive than a single
  agent because it can invoke multiple stages and swap models.

### Agent Studio backend

- Studio configuration APIs have no separate authentication and must remain
  localhost-only.
- Studio does not expose DPAPI-protected secrets or OAuth tokens.
- There is no backend API/UI workflow for editing static `secretHeaders`;
  references require the secure PowerShell/config workflow.
- Agent and MCP configuration is saved as one operation, without server-side
  drafts, version history, undo, or configuration diff review.
- Status responses have no durable health history, recent-event timeline, or
  authoritative last-tested timestamps.
- MCP Test Connection proves current initialization/transport/authentication
  only, not every tool, scope, permission, or future invocation.
- Static-secret tests can differ from gateway execution because Studio cannot
  reveal protected gateway plaintext values.

### MCP and OAuth backend

- Configurable MCP supports trusted Streamable HTTP servers; local stdio MCP
  processes are not exposed in Studio.
- Remote MCP uptime, schemas, accuracy, behavior, and provider permissions are
  outside this project's control.
- OAuth requires compatible discovery, PKCE, and token behavior. Providers
  without compatible discovery or dynamic registration require documented
  client configuration.
- DPAPI grants are bound to the signed-in Windows user and cannot be decrypted
  after copying them to another user or machine.
- Providers that issue no refresh token require browser reauthorization after
  access-token expiry.
- Local disconnect may not revoke provider-side authorization unless a remote
  revocation flow is supported and invoked.
- Failed MCP initialization omits that server's tools for the request; a model
  may answer from general knowledge unless the prompt requires sourced tool use.

### Developer Workbench backend

- Workbench accepts only explicit project roots, rejects drive roots, binds to
  loopback, and approval-gates model-proposed writes, deletes, and commands.
- Approved projects cannot be edited in place; remove and re-register them.
- A project cannot be removed while a task is running or awaiting approval.
- Removing a project never deletes its files.
- Model-role selection uses `coder`, `general`, and `reasoning`; it does not
  dynamically list arbitrary Agent Studio agents.
- Tasks use a process-local background thread rather than a durable distributed
  queue. Process interruption can interrupt an active task.
- Native command support depends on executables already installed and visible
  to the non-elevated Workbench process. Workbench does not install Maven,
  Gradle, npm, .NET, Docker, Git, or project dependencies.
- Approval does not prove an action is correct or safe.
- Git APIs do not provide structured ahead/behind data, remote selection,
  credential management, merge/rebase/cherry-pick, conflict resolution, commit
  history, or pull-request creation.
- `Stage all and commit` includes all repository changes, including unrelated
  pre-existing work; there is no per-file or per-hunk staging backend.
- Push uses current-branch configured remote behavior and cannot select a remote
  or create a pull request.
- Repository detection, last-used time, and remote health are not dedicated
  backend fields.

## UI/UX limitations and to-dos

### Shared frontend

- Svelte/TypeScript development builds require Node.js and pnpm, although
  committed assets keep installation and runtime Node-free.
- Theme and sidebar preferences are browser-local and do not synchronize.
- Responsive web layouts target laptop, tablet, and narrow browser widths; no
  native mobile application exists.
- Add-project and new-task modal forms currently produce two non-blocking
  Svelte accessibility advisories for carrying `role="dialog"` directly.
  Replace them with a reusable, focus-trapping form-dialog primitive.
- Raw task, Git, and MCP output is text/JSON. Add syntax-aware diff navigation,
  per-line review, and richer structured diagnostics.
- Operating-mode synchronization uses polling rather than a push channel, so
  another UI may take approximately two seconds to reflect a change.
- Revision checks reduce conflicting mode updates, but Studio and Workbench do
  not share a cross-process lock. Truly simultaneous writes can still resolve
  last-writer-wins; atomic unique temporary files prevent partial JSON.

### Local Agent Studio UI

- Add a secure workflow for managing static secret-header references without
  displaying protected values.
- Add durable health history and last-tested information when backend support
  exists.
- Add configuration diff/undo/version history when backend support exists.
- Test Connection cannot visually guarantee that all server tools and scopes
  are usable; the UI must continue explaining this distinction.
- Confirm the versioned favicon response in the live rebuilt Studio container.
  Source/asset validation passed, but port 3001 was unreachable from the Codex
  execution environment during the cache-recovery fix.

### Developer Workbench UI

- Add in-place project editing when backend support exists.
- Dynamically list suitable configured agents/model roles when a safe backend
  contract is available.
- Add structured repository summary fields when supplied by the backend.
- Add per-file/per-hunk staging and richer patch review when backend support is
  implemented.
- Add commit history, conflict assistance, remote selection, and pull-request
  workflow only if they preserve the explicit local/remote impact boundary.
- Continue warning that generated changes and pre-existing working-tree changes
  must be reviewed before stage-all, commit, or push.
