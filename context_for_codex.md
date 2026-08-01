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
