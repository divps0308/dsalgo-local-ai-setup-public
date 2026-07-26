# Changelog

## Unreleased

- Excluded the repository-local pnpm store and Python bytecode caches from Git
  so first-time publication does not include machine-generated dependencies.
- Updated operator commands for the renamed
  `C:\self-hosted-setup\dsalgo-local-ai-setup` source directory.
- Verified lifecycle code derives its root from script location and documented
  the intentional stable `alienware-local-ai` Compose identity, which preserves
  existing named-volume data across the directory rename.
- Regenerated path-bound frontend dependency links for the new source location.
- Clarified the process-scoped execution-policy command for manual starts on
  systems where downloaded helper scripts retain Mark of the Web metadata.
- Refreshed per-user Desktop and Start Menu shortcuts to target the renamed
  source directory.

## 5.2.0

- Fixed broken product logos and missing browser favicons by explicitly serving
  `/logo.png` and `/favicon.ico` from both Studio and Workbench with correct
  media types.
- Added a versioned explicit favicon URL, legacy `shortcut icon` declaration,
  and no-store favicon response policy to invalidate Chrome's cached 404 from
  the previously missing Studio route.

- Fixed fresh/generic Developer Workbench startup by restoring the required
  `{ "projects": [] }` registry shape instead of a bare JSON array.
- Added structural configuration checks to Install/Repair and redirected
  Workbench stdout/stderr so startup failures expose the real exception.
- Normalized duplicate case-variant `Path`/`PATH` variables before launching
  Workbench to avoid a Windows `Start-Process` dictionary failure.

- Reorganized documentation by audience: streamlined `README.md`, replaced the
  mixed `DevGuide.md` with beginner-focused `user-guide.md`, and added a
  comprehensive diagram-rich `dev-guide.md`.
- Added `agentic-dev-instructions.md` as a reusable Claude/Codex/agent harness
  contract covering architecture, security, Git hooks, documentation/config
  synchronization, validation gates, and commit patterns.

- Added generic first-install configuration with ignored `personal-*` snapshots
  for machine-specific agents, models, project roots, and operating mode.
- Added defensive Git ignore rules and `Test-GitSafety.ps1`.
- Applied the supplied DS_ALGO logo/favicon to both UIs and Windows shortcuts.
- Made installation resumable and ownership-aware, with Desktop and Start Menu
  shortcuts plus an explicit `-UsePersonalConfig` overlay.
- Split Stop, Remove, Repair, and Uninstall into predictable retention levels.

- Added a centralized three-mode policy shared by Agent Studio and Developer
  Workbench: Online, Restricted Online, and Strict Offline.
- Enforced mode restrictions in Gateway tools/MCP discovery, OAuth network
  actions, Workbench commands, and remote Git push.
- Renamed setup agents to immutable `my-*` keys and `My ...` names; new Studio
  agents use immutable `my-custom-*` keys and `My Custom — ...` names, with no
  legacy aliases.
- Added synchronized mode selectors, impact banners, policy-aware disabled
  controls, health metadata, and backup/restore coverage.
- Renamed the limitation register to `to-do.md`, organized it by backend,
  UI/UX, and architectural work, and retained mandatory review for every change.
- Added `decision-log.md` as the required living functionality and architecture
  decision record, including the security and lifecycle rationale for keeping
  Agent Studio and Developer Workbench separate.

- Replaced the embedded prototype interfaces for Local Agent Studio and
  Developer Workbench with compiled Svelte 5 and TypeScript applications.
- Added a shared accessible design system, persistent System/Light/Dark themes,
  responsive navigation, contextual help, confirmations, and toasts.
- Preserved existing Studio and Workbench API routes and data contracts;
  generated assets are committed for Node-free installation and runtime.

- Replaced the embedded prototype interfaces for Local Agent Studio and
  Developer Workbench with compiled Svelte 5 and TypeScript applications.
- Added a shared accessible design system, persistent System/Light/Dark themes,
  responsive navigation, contextual help, confirmations, and toasts.
- Preserved existing Studio and Workbench API routes and data contracts;
  generated assets are committed for Node-free installation and runtime.

- Replaced the embedded prototype interfaces for Local Agent Studio and
  Developer Workbench with compiled Svelte 5 and TypeScript applications.
- Added a shared accessible design system, persistent System/Light/Dark themes,
  responsive navigation, contextual help, confirmations, and toasts.
- Preserved existing Studio and Workbench API routes and data contracts;
  generated assets are committed for Node-free installation and runtime.
- Added a native loopback MCP OAuth broker at `http://localhost:3003`.
- Added RFC 9728 protected-resource discovery, authorization-server metadata
  discovery, dynamic client registration, Authorization Code with PKCE,
  browser callback validation, token exchange, and automatic refresh.
- Added DPAPI-protected OAuth token storage bound to the signed-in Windows user.
- Added Local Agent Studio OAuth authentication selection, Connect, Status,
  Disconnect, and authenticated connection testing.
- Added Gateway retrieval of short-lived OAuth access tokens without exposing
  refresh tokens to containers or agent configuration.
- Integrated broker start, stop, repair/update guidance, health checks,
  configuration, Compose connectivity, Git exclusions, and documentation.
- Converted the disabled Temporal documentation MCP example from a static
  secret-header reference to OAuth.

## 5.1.0

- Added a native Windows Developer Workbench at `http://localhost:3002`.
- Added explicit local project registration for code located outside the
  container gateway workspace.
- Added Ollama-driven change tasks with automatic read/inspection tools and
  approval-gated file writes, deletions, and native PowerShell commands.
- Added unified patch previews, action history, command output, task
  cancellation, and high-risk command labeling.
- Added Git status, working/staged diff, branch creation, commit, and explicit
  push controls.
- Integrated Workbench installation, start, stop, repair, update, health,
  backup registry, restore registry, and uninstall lifecycle behavior.
- Added loopback-only hosting, a runtime API token, project-root containment,
  and non-elevated execution guidance.

## 5.0.3

- Added WSL2 prerequisite detection and installation to `Install.ps1`.
- Added an explicit reboot boundary with opt-in `-RestartIfRequired` support.
- Automated the `.wslconfig`, WSL shutdown, Docker Desktop restart, and Docker
  readiness sequence during installation.
- Made `Configure-WSL.ps1` avoid rewriting and backing up an unchanged profile.

## 5.0.2

- Corrected the Agent Studio Compose mapping to use container port 8080.
- Fixed benchmark VRAM and processor-placement sampling so measurements are
  taken while the tested model is resident.
- Explicitly unload each generation model before its baseline and after its
  benchmark run.

## 5.0.1

- Fixed the shared PowerShell `Compose` helper dropping all Docker Compose
  arguments because its parameter shadowed PowerShell's automatic `$Args`
  variable.
- Added a fail-fast guard so an empty Compose invocation cannot falsely report
  a successful installation.

## 5.0.0

- Replaced VRAM-tight 30B/32B models with pinned 14B Q4 models.
- Added centralized `config/models.json` capability registry.
- Added per-role context, temperature, and keep-alive settings.
- Added `Configure-WSL.ps1` with Temporal-friendly and AI-only profiles.
- Added Temporal Server, Temporal UI, and dedicated PostgreSQL Compose profile.
- Added container memory limits.
- Added `Benchmark.ps1` with tokens/sec, VRAM, placement, and offload detection.
- Expanded `Health.ps1` with RAM, GPU, and Ollama placement telemetry.
- Added DPAPI-backed MCP secret workflow through `Set-McpSecret.ps1`.
- Excluded secrets and `.env` from standard backups.
- Added General, Coding, Reasoning, Temporal, QA, Python, Java, and Architecture agents.
- Preserved Open WebUI, Agent Studio, dynamic MCP management, orchestration, persistence, backup/restore, and optional data services.
