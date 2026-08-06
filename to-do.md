# Limitations and To-Do Register

- Backend: Validate multimodal agent requests end to end with Open WebUI
  attachments across supported vision and document models. The gateway accepts
  local base64 image and document blocks, while remote attachment URLs and
  unsupported content types are intentionally rejected until an authenticated
  attachment-transfer contract is defined.

- Validate lifecycle wizard progress streaming and cancellation across
  elevated and non-elevated operation paths.

- Architectural: Review for additional obsolete compatibility entry points
  after the first public release; this cleanup removed only root scripts with
  no active references and retained every documented lifecycle operation.

- Backend: Validate text-serialized JSON tool-call recovery across the supported
  small Ollama coding models; the compatibility path is intentionally limited
  to one exact `{name, arguments}` object and still requires normal approvals.

- Consolidate lifecycle operations into a shared single-window progress wizard
  with Next/Cancel navigation and captured stdout/stderr.

- Validate new-window/tab behavior across supported default browsers and
  Windows browser policies.

- Validate bounded native child-script startup under Python/PowerShell
  combinations; lifecycle launchers now fail with logs instead of waiting
  indefinitely.

- Validate bounded elevated Start-phase behavior across Docker Desktop update
  states; startup now records phase progress in `runtime/start.log`.

- Validate elevated installation ACLs when the interactive Windows account
  differs from the Administrator account; native Workbench and OAuth must be
  able to write runtime state as the signed-in user.

## Reliability and validation follow-up

- Validate structured-tool capability for every catalog and user-managed model
  before allowing Goal mode; models without tool calling remain Ask/Plan-only.
- Expand patch validation and model-specific protocol tests across representative
  Ollama releases, including malformed fenced file content and prose-only
  continuation loops.

- Installation, lifecycle recovery, and hardware-path coverage remain
  controlled-beta concerns. Public documentation should describe the installer
  as broadly validated only after representative preflight, post-install, and
  compatibility-matrix results are available.

- Add a task-based local landing page that explains when to use Open WebUI,
  Agent Studio, Workbench, and Health, with persistent badges for local model,
  local agent/tools, and external MCP enabled.

- Improve Health and lifecycle UI with one-screen component diagnosis,
  actionable safe fixes, GPU placement and RAM/VRAM/Docker allocation, and
  links to relevant redacted log sections.

## Current validation caveats

- The installer is deterministic and performs no AI inference during hardware
  detection or model recommendation, but deterministic output is not proof of
  universal hardware compatibility.
- The currently validated path is Windows 11 with a known NVIDIA CUDA GPU,
  dedicated VRAM, adequate RAM and disk, WSL2, Docker Desktop, and native
  Ollama. AMD, Intel, CPU-only, Vulkan, DirectML, unknown-VRAM, multi-GPU, and
  non-Windows paths still need representative validation.
- Free disk space is displayed in the model estimate but is not yet a hard
  eligibility gate. The installer can still fail later if Docker images,
  volumes, Ollama models, or temporary installers exceed available storage.
- CPU physical-core count and performance class are not yet part of model
  eligibility. CPU-only recommendations therefore require conservative manual
  review.
- Catalog RAM/VRAM, model-size, KV-cache, context, and backend values are
  planning estimates, not measured guarantees for every hardware combination.
- Official Ollama tag verification is currently a manual release check; an
  automated catalog-release gate is still required because library availability
  can change.
- Selecting one model can cause the same model to be used as a fallback for
  agent roles whose task coverage is absent. The installer does not yet block
  selection until General, Coding, and Reasoning role coverage is complete.
- Selecting up to three models downloads all checked models, but generated
  role configuration does not guarantee that every role has a task-specialized
  model. Only one conversational model is intended to be resident at a time;
  switching roles can cause model swaps, latency, and memory pressure.
- Docker/WSL resource sizing is now generated from detected RAM and logical
  processors plus the Comfortable/Aggressive choice; low-memory and mixed
  existing-`.wslconfig` validation remains outstanding.
- The full installer journey, restart/resume behavior, prerequisite fallback,
  GPU placement, model downloads, and lifecycle shortcuts have not yet been
  automated across representative hardware profiles. Treat this release as
  controlled beta software rather than a universal production installer.

- Backend: Measure catalog model memory, KV-cache use, GPU offload,
  throughput, and context behavior on representative CUDA, ROCm,
  Vulkan/DirectML, and CPU systems; current values are conservative estimates.
- Backend: Extend eligibility with free-disk gating, physical-core
  classification, unknown-VRAM handling, and tested-backend compatibility.
- Backend: Automate official Ollama tag verification as a catalog-release
  gate; this release was checked manually against official pages.
- UI/UX: Add editable hardware corrections and richer inline descriptions;
  hardware currently supports review and confirmation.
- UI/UX: Add installer UI automation for navigation, provenance transitions,
  Require validation, deterministic results, progress, cancel, and completion.
- UI/UX: Test the file-backed wizard output monitor on long model downloads,
  prerequisite fallbacks, restarts, failures, and cancellation; it now retains
  durable child stdout/stderr but has not yet had automated UI coverage.
- UI/UX: Regression-test empty and delayed child stdout/stderr files in the
  wizard progress monitor; the empty-log handling was fixed but needs automated
  coverage across PowerShell and PS2EXE versions.
- Testing/lifecycle: Exercise every packaged lifecycle EXE from its installed
  Start Menu and Desktop shortcut on clean and repaired installations,
  including UAC cancellation, child-process exit-code refresh, stale PID files,
  missing native processes, Docker failures, and readable stdout/stderr logs.
- Testing/lifecycle: Validate Docker CLI discovery from Explorer, Start Menu,
  PowerShell 5.1/7, OneDrive-redirection, and restricted `PATH` environments
  across supported Docker Desktop versions.
- Testing/lifecycle: Verify Start's three default-browser launches across Edge,
  Chrome, Firefox, and user-managed browser associations, including whether
  each browser opens a new window or reuses an existing window.
- Testing/lifecycle: Verify Uninstall removes Installed Apps registration and
  every shortcut location without removing user-owned project roots or data.
- Testing/lifecycle: Verify the five-entry Start Menu folder and four Desktop
  shortcuts on redirected Desktop paths and after rerunning Install/Repair.
- Testing/lifecycle: Exercise native child scripts directly under Windows
  PowerShell 5.1, PowerShell 7, and packaged PS2EXE hosts where automatic
  variables may differ across invocation scopes.
- Testing/lifecycle: Validate native Python launches from installation paths
  containing spaces, Unicode characters, and redirected user-profile folders.
- Testing/lifecycle: Verify packaged startup with child processes that return
  no observable exit code and with default browsers that delay shell activation.
- Build/release: Make release replacement fully transactional so a compiler,
  signing, or checksum failure after tool initialization cannot leave a
  partially updated `dist` directory. The build now preserves existing EXEs
  when PS2EXE itself is unavailable, but later failures still need staging and
  atomic promotion.
- Installation: Add automated merge tests for existing `.wslconfig` files with
  comments, unrelated sections, missing keys, resource conflicts, duplicate
  keys, malformed lines, and user abort/continue decisions. Confirm unrelated
  WSL settings are never replaced.
- Testing: Not every supported one-to-three model selection combination has
  been exercised through a complete healthy installation. Validate each
  catalog release's selected-model downloads, generated role assignments,
  Compose creation, and Start/Stop lifecycle before claiming broad support.
- Backend/lifecycle: Rerunning the installer with a different model selection
  downloads newly selected models and rewrites active role configuration, but
  intentionally retains previously downloaded Ollama models. Add a clear,
  ownership-aware review-and-cleanup workflow so users can reclaim disk space
  without deleting models they installed outside this project.
- UI/UX: Add richer per-byte Docker image and Ollama model progress parsing to
  the wizard; the current release shows live phase/status output and retains
  detailed native logs under `runtime`.

## Public-distribution roadmap

### Public-distribution blockers / P0

- Define and publish explicit support tiers: Validated, Compatible,
  Experimental, and Unsupported.
- Replace simple vendor gating with capability-based preflight covering OS and
  version, architecture/instruction support where practical, RAM, free disk,
  GPU model/vendor/VRAM, driver/backend readiness, virtualization, WSL2 and
  Docker readiness, and existing local runtime status.
- Add a dry-run report before machine changes showing compatible profiles,
  expected downloads, estimated disk/RAM/VRAM use, prerequisites, ports, and
  warnings.
- Add hard free-disk eligibility checks for selected models, embeddings,
  container images, WSL/Docker overhead, rollback headroom, and a safety margin.
- Generate hardware-aware Docker/WSL recommendations that preserve Windows
  headroom and never silently destabilize the host.
- Add post-install validation for runtime availability, model-load/inference,
  health, applicable tool calling and document indexing, and localhost-only
  exposure.
- Maintain a versioned compatibility matrix containing hardware/backend,
  driver, OS, RAM/VRAM, model profile, test result, known limitation, and
  tested release/version.

### Model freedom and runtime evolution / P1

- Add an explicit model-management workflow for adding models after
  installation and hot-swapping between installed models at runtime. The
  current setup can select models during installation and Ollama may unload or
  reload models as roles change, but there is no complete user-facing add,
  capability-check, safe unload/load, or resource-aware hot-swap workflow.
- Add safe bring-your-own Ollama model support and installed-model discovery,
  with safe handling for unknown models.
- Add explicit probes where technically feasible for chat, embeddings, tool
  calling, structured output, vision, context, and resource estimates.
- Evolve the registry toward a curated catalog plus user-managed custom entries
  without claiming capabilities that have not been probed.
- Evaluate optional runtime adapters only after defining contracts for model
  discovery, streaming chat, embeddings, health, lifecycle, capabilities,
  benchmarks, and security behavior.
- Add non-secret import/export for model choices, agents, MCP assignments,
  operating policy, and benchmark summaries. Explicitly exclude secrets,
  DPAPI data, OAuth tokens, prompts, documents, source code, and sensitive
  runtime state.

### Optional profiles / P1-P2

- Define opt-in profiles rather than expanding the always-on core: Core Chat
  and Documents; Agents and MCP; Developer Workbench; Visual Workflows; and
  Autonomous Coding Sandbox.
- Evaluate, without committing to inclusion, an OpenHands-based autonomous
  coding profile with disposable sandboxing, explicit repository mounts,
  least-privilege networking, no broad host filesystem access, no Docker socket
  by default, and preserved human review.
- Evaluate, without committing to inclusion, a Flowise or Dify visual-workflow
  profile disabled by default, including resources, data exposure, connectors,
  authentication, and attack surface.
- Decide whether native Open WebUI MCP support should replace, coexist with,
  or remain separate from Agent Gateway and the DPAPI-backed OAuth broker;
  require migration, compatibility, and threat-model decisions before any
  credential paths are duplicated.

### Platform validation / P2

- The supported distribution currently targets Windows installations with WSL2
  and Docker Desktop. Linux and macOS installation support is future work and
  requires separate lifecycle, secret-storage, filesystem-protection, and
  validation designs.
- Validate representative Windows NVIDIA profiles across VRAM tiers.
- Validate supported Windows AMD Radeon/Ollama paths as separate tested
  profiles, never as a blanket claim about all AMD GPUs.
- Maintain controlled tracks for CPU-only, Intel GPU, DirectML, Vulkan,
  unknown VRAM, and multi-GPU systems.
### Distribution quality / P2

- Define Stable, Preview, and Experimental release channels.
- Produce signed artifacts, checksums, SBOMs, pinned image digests,
  dependency/license inventory, and a supply-chain update policy.
- Add explicit opt-in diagnostics only. Never collect prompts, documents,
  source code, secrets, model content, or persistent device identifiers.
- Add reproducible issue templates for installation, hardware, model
  performance, MCP, Workbench, and security reports.

### Deliberate non-goals

- Universal installation or execution across every machine configuration is not
  a release claim. Unsupported operating systems, hardware, drivers,
  virtualization, WSL2, Docker, and storage conditions require detection and an
  actionable report; expanding support requires a separately validated
  compatibility profile.

- Public or LAN exposure without dedicated authentication, authorization, TLS,
  tenancy, and security design.
- Claiming Strict Offline is a machine-wide firewall or air gap.
- Unattended destructive execution, commit, push, or broad host access.
- Claiming universal model or hardware support merely because a model can be
  downloaded.

This is the canonical register for known limitations, unsupported behavior,
validation gaps, operational constraints, deliberate tradeoffs, and follow-up
work in DSAlgo Local AI Setup. Review and update it with every repository change.
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
- The Docker Compose project identity is `dsalgo-local-ai-setup`. Existing
  installations created under an older project identity require an explicit
  data-volume migration before their persisted volumes are reused.
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

- Refresh and validate `scripts/windows-time-zones.json` against Unicode CLDR
  during release maintenance so newly introduced Windows time-zone IDs remain
  installable without a network lookup.
- Validate the retired `Mid-Atlantic Standard Time` compatibility mapping on a
  machine that still actively uses that Windows zone. Unicode CLDR no longer
  maps it, so the installer uses its fixed UTC-02:00 standard offset without
  historical daylight-saving behavior.
- The current validated target is a single interactive Windows 11 user with a
  CUDA NVIDIA GPU, known dedicated VRAM, sufficient system RAM, free disk,
  WSL2, Docker Desktop, and native Ollama. Multi-user tenancy,
  shared-host isolation, Linux/macOS host installation, and production server
  deployment are not supported.
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
- This release is core-only; optional workflow, database, cache, and vector
  service integrations are not part of the supported installation path.
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
  centralized identity provider, RBAC, or multi-user review boundary.
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
- **Known**: If the Docker gateway container cannot reach Ollama at `host.docker.internal:11434`, the Built-in General Agent will return no response (empty spinner). Verify `ollama serve` is running natively before using gateway agents.
- **Known**: Kimi-VL `kimi-vl-a3b-thinking:latest` is listed in the catalog with `provenanceConfidence: medium`; verify tag availability on Ollama before pulling.
- model-catalog.json `organization` field for new entries (THUDM, NVIDIA, Moonshot) must match the `$vendor` dropdown strings in `InstallerWizard.ps1` exactly for provenance filtering to work; keep both lists synchronized on catalog updates.
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
- Workbench task selection uses enabled sample/custom Agent Studio agents by
  stable ID and their configured backing model. Validate stale, disabled, and
  missing-model configurations in packaged installs.
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
- Validate the enabled sample/custom agent picker against stale, disabled, and
  missing-model configurations in packaged installs.
- Add structured repository summary fields when supplied by the backend.
- Add per-file/per-hunk staging and richer patch review when backend support is
  implemented.
- Add commit history, conflict assistance, remote selection, and pull-request
  workflow only if they preserve the explicit local/remote impact boundary.
- Continue warning that generated changes and pre-existing working-tree changes
  must be reviewed before stage-all, commit, or push.
## Agent Studio model assignment follow-up

- [ ] Rebuild and package the Agent Studio frontend after the model-tag/role selector change; the source now distinguishes an installed Ollama backing model from the preferred-use role, but the generated static bundle still requires a successful frontend build on a writable Node/pnpm environment.

## Resolved in this session

- [x] Developer Workbench did not start when launched via `Invoke-ChildScript` in `Start.ps1` because `Start-DeveloperWorkbench.ps1` used raw `$PSScriptRoot` which can be empty in child PowerShell processes; fixed with the same three-source root-resolution pattern used in `Start.ps1` and `Uninstall.ps1`. Same fix applied to `Start-OAuthBroker.ps1` for consistency.
- [x] Browser open in `Start.ps1` used `rundll32 url.dll,FileProtocolHandler` which opens each URL in a separate browser window; replaced with `Start-Process -FilePath $url` (ShellExecute) so modern browsers open URLs as tabs in the existing window.
- [x] `Register-DSAlgoUninstall` in `scripts/Shortcuts.ps1` did not set `DisplayIcon` so no logo appeared in Settings > Apps or Control Panel. Added `DisplayIcon`, `QuietUninstallString`, `NoModify`, and `NoRepair` properties. Existing registry entry was patched in place.
# Latest validation follow-up

- Validate lifecycle startup from a clean, non-elevated installed copy after
  repairing runtime-directory permissions; stale Workbench PID files and
  elevated-owned state files can prevent port 3002 from binding.
### Developer Workbench agent assignment

- Validate the agent-picker workflow across sample and custom agents, including
  disabled agents, missing model tags, and stale installed configuration.
- Rebuild and package the Workbench static bundle after agent selection changes.
- [ ] Workbench task quality: validate model completion evidence and preserve an explicit incomplete state when a model stops after proposals or failed commands; validate multilingual/UTF-8 tool output across Windows encodings.
- [ ] Validate evidence accounting across representative models: semantic
  duplicate claim commands, claim-only completion repair, mutation/inspection
  progress resets, and compilation requests that require successful build/test
  evidence rather than a diff alone.
- [ ] Workbench protocol interoperability: validate the versioned JSON tool-call
  and tool-result envelopes across representative Ollama models, including
  malformed JSON, prose-only action requests, unsupported tool calling, and
  completion-quality evidence. Do not treat protocol compatibility as a claim
  that every model can reliably perform structured actions.
- [ ] Workbench modes: validate Ask (read/answer), Plan (read-only plan artifact), and Goal (approval-gated execution) across the packaged UI and installed payload.
### Workbench follow-up

- Validate that Goal-mode agents invoke approval-gated tools rather than asking
  for approval in ordinary response text; prose-only approval requests cannot
  create a UI approval card and must be treated as incomplete.

- Validate the uninstall purge-choice flow across running and stopped Docker
  Desktop states; the default preserves installer-owned images, volumes, and
  downloaded models, while the explicit purge option removes them.

- Validate Goal-mode continuation across multi-file tasks; a single approved
  action followed by a continuation message must remain incomplete and prompt
  the agent to continue.
- [ ] Validate the Goal continuation loop through multiple approval rounds and
  confirm it reaches a verified conclusion rather than stopping after a
  progress-only response or exhausting the configured safety limit.
- [ ] Validate repeated no-tool responses and missing-dependency blockers (for
  example Maven) so Goal tasks stop with an actionable incomplete result rather
  than looping until the tool-step limit.
- [ ] Validate that each agent's configured maximum tool-step count is honored
  end-to-end in the packaged Workbench, including large limits and safety-cap
  behavior.
- [ ] Validate that Ask and Plan never expose write/command tools and that Plan
  artifacts are uniquely named and saved only after the required approval.
- [ ] Validate that model prose containing an approval request never executes;
  only structured `tool_calls` may create an approval card.
- [ ] Validate scheduled permanent removal of an installed application folder
  from uninstall.exe, including locked executable/process cleanup and the
  safety behavior when no installer-state marker exists.
### Public distribution controls

- [ ] Keep the Help Center synchronized with every Studio and Workbench screen;
      add coverage for new controls, side effects, permissions, policy modes,
      approval behavior, and troubleshooting as the UI evolves.

- [ ] Configure GitHub branch protection, required CI checks, and owner-only
      release-environment approval before the first public release.
- [ ] Add a generated third-party license/dependency inventory to release
      artifacts; do not place private signing material in the repository.
- [ ] Validate the installer license acceptance gate on clean Windows machines.
- [ ] Validate no-op proposal handling and repeated identical tool-call guards
  across models and multi-file Goal tasks.
- [ ] Validate canonical argument schemas, compatibility aliases, three-turn
  protocol repair, focused-edit rejection, exploration-loop bounds, and
  post-mutation verification against representative Ollama model families.
  Record model-specific incompatibilities rather than treating downloadability
  as Goal-mode support.

