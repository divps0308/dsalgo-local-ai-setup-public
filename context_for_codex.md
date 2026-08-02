# DSAlgo Local AI Setup - Issue Resolution Context

This document serves as a summary of the issues reported and the solutions applied during the recent troubleshooting session. This context is provided to ensure continuity for further development.

## 1. Installer UI Error
* **Issue:** When selecting the resource allocation dropdown ('Comfortable' or 'Aggressive') in the installer (`install.exe`), an unhandled exception was thrown, preventing the UI from updating the descriptive text.
* **Root Cause:** A WinForms event handler (`$updateAllocDesc`) was attempting to access the `$allocDesc` label variable which had fallen out of scope, causing a runtime null-reference error.
* **Solution:** Upgraded the variable scope to script-level (`$script:allocDesc`) in `src/InstallerWizard.ps1` so the dropdown correctly updates the text. Recompiled the installer to `dist/install.exe`.

## 2. Built-in and Custom Agents Producing No Output (Empty Responses)
* **Issue:** When prompting built-in agents (e.g., `registry/general`) or custom agents (e.g., `My Custom - Agent 1`) in Open WebUI, they produced no output at all.
* **Root Cause:** The `agent-gateway` and `agent-studio` Python backends were crashing or silently failing when attempting to load JSON files (specifically `config/models.json`) if the files contained a UTF-8 BOM (Byte Order Mark). PowerShell's `Set-Content` natively adds a BOM in Windows, causing Python's standard `utf-8` decoder to fail and preventing the Gateway from successfully registering models or handling OpenAI `/v1/chat/completions` traffic.
* **Solution:** Updated the file-reading logic in `agent-gateway/app.py` and `agent-studio/app.py` to use `encoding="utf-8-sig"`, which safely ignores the BOM if present. Restarted the Docker Compose stack to apply the backend changes.

## 3. Open WebUI Raw Ollama Model Tool Errors (e.g., gemma3:27b)
* **Issue:** Selecting raw Ollama models directly in Open WebUI (like `gemma3:27b`) and sending a prompt resulted in a "model does not support tools" error.
* **Root Cause:** Open WebUI connects directly to Ollama for raw models (bypassing the Gateway) and automatically sends tool definitions. If the selected Ollama model template does not support tools, Ollama rejects the request. A previous attempt to fix this stripped tool definitions in the Gateway, but because raw Ollama models bypass the Gateway, the fix only applied to Agents.
* **Solution (Workaround applied/communicated):** This is a native interaction between Open WebUI and Ollama. To chat with `gemma3:27b` without the tool error, it must be created as a Custom Agent in the Local Agent Studio (which routes it through the Gateway where the tool-stripping fix successfully intercepts it).

## 4. Missing Models in Agent Studio Dropdown
* **Issue:** In the Local Agent Studio, when creating a custom agent, the "backing LLM model" dropdown was completely empty.
* **Root Cause:** The dropdown is populated by reading `models.json` via the `/api/config` endpoint in `agent-studio/app.py`. The same UTF-8 BOM crash described in Issue #2 caused the JSON load to fail, resulting in an empty list being returned to the UI.
* **Solution:** Fixed by the same `utf-8-sig` encoding update in `agent-studio/app.py`.

## 5. Missing Models in Model Catalog
* **Issue:** `model-catalog.json` was missing `GLM`, `GPT-OSS`, `Kimi`, and `Nemotron` models.
* **Solution:** Added the missing models (`glm4:9b`, `nemotron-mini:4b`, `kimi-vl-a3b-thinking:latest`, and `gpt-oss:8b`) to `config/model-catalog.json` following the existing schema formatting.

## 6. Developer Workbench Not Accessible & Browser Tabs Not Launching Automatically
* **Issue:** After running `start.exe`, Developer Workbench was not accessible on `localhost:3002`, and the browser tabs did not automatically open.
* **Root Cause:** 
    1. The user was executing `start.exe` directly from the `dist/` release artifact directory rather than formally installing the application or running `Start.ps1` from the project root. This caused the script to fail to resolve the path to `scripts/Common.ps1`, resulting in an immediate silent crash.
    2. The previously compiled `start.exe` was out of date and did not contain two underlying fixes: a fix for `Start-Process` silently failing to open URLs inside PS2EXE, and a fix for `pythonw.exe` crashing on a `RedirectStandardInput NUL` parameter.
* **Solution:** Compiled all the latest fixes into a fresh `dist/start.exe` via `build/build.ps1`. The executable must be run from a proper installation directory (via `install.exe`) or via `Start.ps1` from the root, not directly from `dist/`.

## 7. Installer Overwrite Error
* **Issue:** Running `dist/install.exe` resulted in an error: `The process cannot access the file '.../start.exe' because it is being used by another process.`
* **Root Cause:** The `start.exe` executable from a previous successful launch was still running in the background, locking the file and preventing the installer from overwriting it.
* **Solution:** Forcefully terminated the running `start.exe` process so the installation could proceed.

## 8. Public release and licensing decisions

* `LICENSE` is the canonical MIT license and is displayed by the installer.
  `mit_license.md` was removed. The installer also displays a third-party
  notice explaining that upstream software, container images, and models keep
  their own ownership and licenses; no ownership or responsibility is claimed.
* The installer requires explicit license/third-party notice acceptance before
  proceeding. License text uses normalized line endings so paragraphs and
  headings render correctly in the WinForms text area.
* The public project must not contain `.env`, DPAPI/token files, runtime
  secrets, model caches, private certificates, PFX files, or personal email
  addresses. `PUBLIC_RELEASE_GUIDE.md` is intentionally gitignored and is not
  packaged.
* The root tracked `start.exe` was removed; generated executables belong under
  `dist/` only.
* Alienware identifiers were removed from public source/configuration while
  the legacy DPAPI entropy remains encoded for compatibility with existing
  stored secrets. Do not change that entropy without a migration plan.

## 9. Build and release workflow

* `build/build.ps1` automatically runs `pnpm --dir frontend build` before
  packaging. It generates and signs `install.exe`, `start.exe`, `stop.exe`,
  `repair.exe`, `remove.exe`, and `uninstall.exe`, then writes checksums,
  `VERIFY.md`, and the public `.cer` certificate.
* Local builds may generate/use the self-signed certificate in
  `Cert:\CurrentUser\My` with subject
  `CN=DSAlgo Local AI Setup Local Release Signing`. A self-signed certificate
  is not publicly trusted and is not a substitute for a CA certificate.
* `.github/workflows/ci.yml` validates frontend/build prerequisites, JSON,
  Python syntax, Compose configuration, PowerShell parsing, and Git safety.
* `.github/workflows/release.yml` is owner-only (`divps0308`), uses the
  protected GitHub `release` environment, checks out an existing semantic tag,
  imports `SIGNING_CERT_PFX_B64` and `SIGNING_CERT_PASSWORD` only on the
  ephemeral Windows runner, runs the normal build, publishes release assets,
  and removes the imported certificate/PFX in `finally` cleanup.
* The PFX private key must be stored only as GitHub environment secrets, never
  repository secrets/variables, source files, artifacts, logs, or release
  assets. Configure required reviewers and tag/branch restrictions on the
  environment. Rotate the PFX and secrets immediately if exposed.

## 10. Workbench and agent behavior

* Developer Workbench task creation uses a selected configured agent and its
  backing Ollama model; legacy model-role fallback is intentionally not used.
* Work modes are `Ask` (read/answer only), `Plan` (read and save a uniquely
  named dated Markdown plan in the project), and `Goal` (continue best-effort
  with approval gates until completion or a real blocker).
* Completion quality must not be inferred merely from the model ending its
  response. A task is incomplete unless it produces a patch, command, test
  result, or explicit “no changes needed” conclusion. Goal mode must continue
  while actionable work remains, subject to configured max steps and safety
  approvals.
* The Workbench supplies approval-gated tools, but a model may emit a proposed
  command as plain text instead of structured `tool_calls`; plain text is never
  executed. This explains repeated installation proposals that did not create
  approval cards.
* The selected agent’s configured maximum tool steps is used, with a defensive
  hard maximum of 1000. A high limit does not guarantee completion if the model
  repeats itself, fails to emit tool calls, or reaches a safety/timeout limit.
* Existing Chinese comments in sample projects can appear as UTF-8 mojibake in
  output when rendered with the wrong decoder; this is not necessarily model-
  generated content.

## 11. Operational limitations and current validation

* Primary validated target remains Windows 11 with WSL2, Docker Desktop,
  native Windows Ollama, NVIDIA CUDA GPU with dedicated VRAM, sufficient RAM,
  and disk. Linux/macOS, AMD, Intel GPU, CPU-only, Vulkan/DirectML, unknown
  VRAM, and multi-GPU paths remain future validation work.
* Re-running installation is intended to resume/repair and does not remove
  previously downloaded Ollama models unless the user explicitly chooses the
  destructive uninstall cleanup option.
* `Start`, `Stop`, `Repair`, `Remove`, and `Uninstall` are separate lifecycle
  operations; services, native Workbench/OAuth processes, Docker/WSL state,
  browser launching, and cleanup require validation on the target machine.
* The installer’s hardware/model recommendations and all model combinations
  are not exhaustively tested for healthy installation. Downloadable does not
  mean supported; compatible does not mean validated.
* Strict Offline is an application policy, not a host firewall or air gap.
  MCP/OAuth integrations can contact external providers and must remain
  trusted, least-privilege, and localhost-oriented.

## 12. Useful handoff commands

```powershell
# Build/package locally (requires Node.js and pnpm)
powershell -ExecutionPolicy Bypass -File .\build\build.ps1

# Validate the current build inputs without installing
Get-ChildItem .\dist\*.exe
Get-FileHash .\dist\install.exe -Algorithm SHA256
Get-AuthenticodeSignature .\dist\install.exe
```

For a public release, use the protected GitHub Actions workflow rather than
uploading a locally generated PFX or manually signing from a contributor
machine. Treat this file as a continuity handoff; consult `AGENTS.md`,
`agentic-dev-instructions.md`, `dev-guide.md`, `SECURITY.md`, and
`docs/PROJECT_CONTEXT.md` before changing architecture or security behavior.
