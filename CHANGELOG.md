# Changelog

## Unreleased

- Removed the Comfortable/Aggressive installer choice. WSL/Docker resource
  recommendations now consistently target approximately 50% of detected RAM
  and logical processors. GPU model recommendations use the full detected
  dedicated VRAM; Ollama controls actual GPU utilization at runtime.

- Fixed installer configuration preparation failing when conditional values
  were evaluated inline as commands in PowerShell.
- Fixed model-preference wizard layout so the fixed-allocation explanation no
  longer overlaps provenance controls.
- Pinned the protected release workflow to Node.js 24, added explicit Svelte
  configs for both frontend apps, and filtered the known legacy form-dialog
  accessibility diagnostic.
- Expanded the installer model review into recommended, supported-but-filtered,
  and unsupported catalog categories. Only the first two categories are
  selectable, with a three-model maximum.
- Fixed Windows PowerShell point/size construction in the categorized model
  review page.
- Reduced the default WSL/Docker RAM allocation to approximately 20%, leaving
  approximately 80% for Windows and native Ollama model recommendations.
- Made installer confirmation and warning dialogs owned by topmost windows so
  they appear in front of the main installer.
- Audited lifecycle executables and made the installation folder picker owned
  by its topmost wizard as well.
- Strengthened the WSL confirmation owner window so the warning remains in
  the foreground while the user makes a choice.
- Replaced the child-process WSL message box with a dedicated topmost
  Overwrite/Exit dialog to prevent focus being reclaimed by the parent wizard.
- Hardened the WSL prompt initialization and fallback so setup cannot wait on
  an invisible decision dialog.
- Prevented the fallback prompt from appearing after the user intentionally
  chooses Exit in the primary WSL dialog.
- Fixed WSL overwrite persistence so existing keys are replaced once without
  duplicate entries and are written even when the file length is unchanged.
- Treats winget's explicit "No available upgrade" Docker result as expected
  instead of displaying a warning.
- Changed installer windows to be topmost only during initial launch; users
  can now move the parent wizard behind child prompts and other applications.
- Fixed categorized model selection counts across multiple grids and added
  explicit scroll cues when a category contains more rows than visible.

- WSL setup now silently preserves existing memory/processor/swap values that
  meet or exceed the generated hardware-safe recommendation; lower values can
  be explicitly overwritten after the existing file is backed up, or setup
  can exit without changes.
- Release installation checks for Docker Desktop updates and waits longer for
  Docker Engine readiness before using Compose.

## Unreleased

- Fixed the installer license lookup for extracted release bundles by locating
  the canonical `LICENSE` file inside the adjacent `payload` directory.

- Replaced the fixed 20 GB WSL memory profile with hardware- and allocation-
  aware Comfortable/Aggressive recommendations for WSL memory, processors,
  and swap. Existing `.wslconfig` values remain preserved.

- Fixed release packaging to publish the complete `dist` directory, including
  the installer-required `payload` folder, as one extractable ZIP.

- Removed obsolete references to the retired project-context document; the
  README and development guide now carry the project mission, scope, and
  architecture documentation contract.

- Replaced the Chicago-specific container time-zone default with automatic
  Windows-to-IANA detection during environment initialization. New installs
  receive their system time zone in machine-local `.env`; existing explicit
  `TZ` choices remain unchanged, and Compose falls back to UTC when no value is
  supplied.

- Added a conservative cross-model tool-call compatibility parser. Explicit
  allow-listed calls emitted in `tool_code`/code fences or simple JSON are
  recovered into the existing permission, runtime-policy, and execution path;
  arbitrary prose is never executed.

- Tightened Goal completion accounting: claim-only commands are rejected and
  semantic duplicates are detected; progress resets only on meaningful mutation,
  recognized verification, or post-change inspection. Compilation requests now
  require successful build/test evidence, with one repair for unsupported
  completion prose before an explicit incomplete result.

- Documented the independent review disposition: Windows/NVIDIA is the current
  validated baseline, while preflight resource gates, post-install checks,
  broader hardware validation, lifecycle recovery, and documentation
  reconciliation remain release-bar work.
- Clarified that Workbench tasks use enabled sample/custom agents and their
  configured backing models; obsolete role-only notes are superseded.
- Hardened Goal-mode execution: known non-tool-calling models are rejected,
  fenced or empty proposed file content is refused, and continuation prompts
  require the next structured tool call instead of another prose proposal.
- Added controller-owned tool argument validation, deterministic cross-model
  aliases, bounded protocol-repair turns, structured tool-result status, a
  no-progress tool-loop guard, and post-change verification requirements.
  Malformed model requests now end with actionable protocol diagnostics instead
  of raw argument errors or accidental execution.

- Removed the obsolete `context_for_codex.md` file and unreferenced legacy
  component-management wrappers (`Manage-*`, `Start-*`, `Stop-*`, and
  `Update.ps1`). The documented lifecycle commands remain unchanged.
- Workbench now recovers narrowly formatted `{ "name": ..., "arguments": ... }`
  JSON tool requests emitted as assistant text by small Ollama models, then
  routes them through the existing tool allow-list and approval gates.
- Fixed the installer wizard to report the expected Windows restart after enabling WSL and Virtual Machine Platform instead of showing an unavailable exit-code failure.
- Updated restart guidance to direct users to rerun `Install.exe` after signing in.
- Added automatic WSL kernel/client update before WSL shutdown during installation.

- Workbench tasks now select enabled sample/custom agents by stable ID and use
  their configured backing model and `maxSteps` budget (defensively capped at
  1000). Added enforced Ask, Plan, and Goal modes, completion-quality checks,
  structured-tool-call approval requirements, and Goal repetition/dependency
  guards.
- Uninstall now offers an unchecked opt-in purge of installer-owned Docker
  images, volumes, and downloaded Ollama models, and schedules safe removal of
  the installer-owned application directory after cleanup.

- Added a shared single-window lifecycle wizard for Start, Stop, Repair,
  Remove, and Uninstall with Next/Cancel controls and captured child output.

- Added a shared single-window lifecycle wizard for Start, Stop, Repair,
  Remove, and Uninstall with Next/Cancel controls and captured child output.

- Uninstall now starts Docker Desktop when needed and waits for Docker
  readiness before attempting container/image cleanup.

- Uninstall now starts Docker Desktop when needed and waits for Docker
  readiness before attempting container/image cleanup.

- Improved Start browser launch by detecting an installed browser executable
  and requesting a new window containing the three local interfaces.

- Improved Start browser launch by detecting an installed browser executable
  and requesting a new window containing the three local interfaces.

- Replaced the unbounded native child-script invocation in Start with a
  bounded process runner and actionable stdout/stderr diagnostics.

- Added bounded elevated startup waiting and `runtime/start.log` phase
  diagnostics so `start.exe` cannot remain indefinitely blocked before native
  services and browser launch.

- Fixed elevated installation runtime permissions to target the interactive
  desktop user rather than the temporary Administrator account.

- Fixed `start.exe` crashing with `RedirectStandardInput` error: removed `-RedirectStandardInput NUL` from `Start-DeveloperWorkbench.ps1` and `Start-OAuthBroker.ps1`. In PS2EXE-compiled mode `NUL` is resolved as a relative path rather than the Windows null device. `pythonw.exe` is already detached from the console so the redirect is unnecessary.
- Fixed browser tabs not opening after `start.exe`: replaced `Start-Process -FilePath $url` with `System.Diagnostics.ProcessStartInfo` + `Process.Start()` which calls `ShellExecute` directly and works reliably inside PS2EXE-hosted processes. Added a 600 ms inter-tab delay so each URL opens in a new tab rather than a new window.
- Fixed `gemma3:27b does not support tools` error in Open WebUI: gateway's `ollama_chat()` now respects `toolCalling: false` from `models.json` and skips sending tool definitions to Ollama for non-tool-capable models. Added a graceful 400-error retry without tools as a belt-and-suspenders fallback.
- Fixed Local Agent Studio "Backing LLM model" dropdown showing no models: `agent-studio/app.py /api/config` now fetches the Ollama `/api/tags` list and merges all installed models with the registry entries, ensuring every locally available model appears in the dropdown.
- Added inline resource allocation description in the installer wizard: a dynamic label below the Resource Allocation ComboBox updates in real time to explain the RAM/VRAM impact of each choice.
- Expanded `model-catalog.json` with 9 new entries across 4 new families: **GLM4** (THUDM/ZhipuAI, China — `glm4:9b`), **Nemotron Mini** (NVIDIA, US — `nemotron-mini:4b`), **Qwen3** (Alibaba, China — 0.5B through 32B), and **Kimi-VL** (Moonshot AI, China — `kimi-vl-a3b-thinking`). Bumped `catalogVersion` to `2026.07.31.1`. Added Moonshot, NVIDIA, and THUDM to the installer's Preferred Organization dropdown.

- Fixed `Start.ps1` browser launch opening separate browser windows instead of tabs: replaced `rundll32 url.dll,FileProtocolHandler` with `Start-Process -FilePath $url` (ShellExecute) so modern browsers open all three URLs as tabs in the existing window. Added a 2-second settle wait after native services start before opening the browser.
- Fixed missing icon in Settings > Apps / Control Panel uninstall entry: `Register-DSAlgoUninstall` in `scripts/Shortcuts.ps1` now writes `DisplayIcon` pointing to `assets/branding/logo.ico`, plus `QuietUninstallString`, `NoModify`, and `NoRepair` for full Windows uninstaller conformance. Existing registry entry was patched in place.


- Fixed packaged Start/Stop helpers falsely reporting exit code `-196608` by
  invoking helper PowerShell processes directly and using the native command
  exit code instead of PS2EXE's unreliable `Start-Process.ExitCode`.
- Added durable stdout/stderr logs for native lifecycle helpers so packaged EXE
  failures report the underlying PowerShell or Python error.
- Made Docker CLI discovery independent of a shortcut process's `PATH` by also
  checking Docker Desktop's standard installation directory; Stop now fails
  explicitly instead of silently leaving containers running.
- Granted the signed-in user modify access to installer-generated runtime state
  so non-elevated lifecycle shortcuts can write logs and PID files.
- Start now opens Open WebUI, Agent Studio, and Developer Workbench through the
  Windows default browser after services are ready.
- Uninstall now removes the per-user Installed Apps registration and all known
  Desktop and Start Menu shortcuts.
- Corrected child-script root resolution so native Workbench/OAuth startup and
  runtime logging stay inside the selected installation directory.
- Made each native child script explicitly assign its installation root after
  loading shared helpers, covering PowerShell hosts where `$PSScriptRoot` is
  empty inside `Invoke-Expression`.
- Fixed native Python launcher arguments so installed paths containing spaces
  are quoted correctly for OAuth and Developer Workbench.
- Made packaged child invocation treat an unavailable PS2EXE exit code as
  successful when no child error was emitted, and routed browser launches
  through Windows' URL handler so startup cannot be blocked by browser process
  activation.
- Install now creates Desktop shortcuts for Install, Repair, Start, and Stop;
  the Start Menu program folder exposes Install, Repair, Start, Stop, and
  Uninstall.
- Granted the signed-in user modify access to installer-generated runtime state
  so non-elevated lifecycle shortcuts can write logs and PID files.
- Start now opens Open WebUI, Agent Studio, and Developer Workbench through the
  Windows default browser after services are ready.
- Uninstall now removes the per-user Installed Apps registration and all known
  Desktop and Start Menu shortcuts.
- Changed Repair, Remove, and Uninstall to request UAC elevation themselves
  while preserving their selected options.
- Added shortcut target validation so installation and repair fail clearly
  instead of leaving an unusable Windows shortcut with an empty target.
- Changed the release build to verify PS2EXE is loaded before replacing the
  previous release executables.
- Added discovery of PowerShell modules under a OneDrive-redirected Documents
  folder so PS2EXE builds do not depend on a hardcoded user profile path.
- Removed automatic insertion of the self-signed release certificate into
  Trusted Root and Trusted Publishers; builds verify the actual signer
  thumbprint without silently changing Windows trust policy.
- Fixed `Test-GitSafety.ps1` to allow the distributable `.env.example` template
  while continuing to reject the machine-local `.env` file.
- Replaced ambiguous installer use cases with General Conversation, Reasoning,
  Coding, Deep Research, and All; Ollama is now displayed as the fixed runtime.
- Replaced provenance free text with curated organization/country dropdowns,
  including None reset/disable behavior and Require validation.
- Expanded the release catalog from three placeholders to 30 curated Ollama
  variants and generate installed model roles plus enabled sample agents from
  the confirmed recommendation.
- Replaced the recommendation text list with an install-selection table that
  tags task fit, enforces one-to-three models, and totals estimated HDD usage.
- Replaced the wizard's event-based child-process output bridge with a
  file-backed UI monitor so installation stdout/stderr remains visible and
  durable under `runtime` while the single installer window stays open.
- Fixed empty redirected child-log files causing repeated `Length` property
  exceptions in the wizard progress monitor after a healthy installation.
- Changed WSL configuration from replacement to conservative merge behavior:
  existing `.wslconfig` values are preserved, missing DSAlgo keys are added,
  and conflicts/unparseable entries require an explicit continue-or-abort choice.
- Treat a child installer that emitted `Phase: complete` as successful when
  PS2EXE exposes an unavailable child exit code.
- Replaced chained installer dialogs with one topmost Back/Next/Cancel wizard
  covering destination, hardware confirmation, preferences, deterministic
  recommendations, live progress, errors, and completion.
- Excluded the repository-local pnpm store and Python bytecode caches from Git
  so first-time publication does not include machine-generated dependencies.
- Updated operator commands for the renamed source directory; commands now use
  the directory selected by the operator rather than a fixed machine path.
- Verified lifecycle code derives its root from script location and documented
  the intentional stable Compose identity, which preserves
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
- Converted the disabled documentation MCP example from a static
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
- Added `Configure-WSL.ps1` with balanced and AI-only profiles.
- Added optional workflow and data-service Compose profiles.
- Added container memory limits.
- Added `Benchmark.ps1` with tokens/sec, VRAM, placement, and offload detection.
- Expanded `Health.ps1` with RAM, GPU, and Ollama placement telemetry.
- Added DPAPI-backed MCP secret workflow through `Set-McpSecret.ps1`.
- Excluded secrets and `.env` from standard backups.
- Added General, Coding, Reasoning, QA, Python, Java, and Architecture agents.
- Preserved Open WebUI, Agent Studio, dynamic MCP management, orchestration, persistence, backup/restore, and optional data services.
# Unreleased

- Hardened Developer Workbench startup against elevated-owned runtime files
  and stale PID metadata so normal-user startup can bind port 3002 reliably.
### Changed

- Added a required installer license/third-party notice screen.
- Removed the tracked root `start.exe` and legacy `mit_license.md`; `LICENSE`
  is canonical.
- Added Windows GitHub Actions CI and owner-gated release workflow scaffolding.
