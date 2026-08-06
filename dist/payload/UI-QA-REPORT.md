# DSAlgo Local AI Setup — Manual UI QA Report

Date: 2026-08-06  
Test surface: installed Windows workstation at `C:\Users\divya\DSAlgo Local AI Setup`  
Method: browser-based manual QA against the local interfaces on ports 3000–3002.

## Executive summary

The three URLs served application pages during the test. An initial
non-elevated listener check incorrectly reported no listeners because the
process could not inspect the relevant sockets/Docker resources. A subsequent
privileged check confirmed all three listeners and the Docker containers are
running. The distribution is therefore **currently running**, although the
non-elevated diagnostic path is misleading and should be improved.

Agent Studio and Developer Workbench rendered their primary screens and exposed
the expected navigation and controls. Open WebUI reached its sign-in page, but
authenticated chat behavior could not be tested without user credentials.

## Endpoint and process checks

| Check | Result | Evidence |
|---|---|---|
| `http://localhost:3000/` | Pass | Redirected to Open WebUI sign-in (`/auth?redirect=%2F`). |
| `http://localhost:3001/` | Pass | Local Agent Studio rendered with `Local · Ready`. |
| `http://localhost:3002/` | Pass | Developer Workbench rendered with `Local · Ready`. |
| Direct HTTP recheck | Pass | `Invoke-WebRequest` returned HTTP 200 for all three ports during the final check. |
| Listener persistence | Pass (privileged check) | Ports 3000, 3001, and 3002 were listening; 3002 was owned by the Workbench Python process. |
| Docker container state | Pass (privileged check) | Gateway healthy; Open WebUI healthy; Agent Studio running; published ports included 3000 and 3001. |
| Gateway health endpoint | Pass | `http://localhost:8001/health` returned HTTP 200 with status `ok`, version `5.2.0`, Ollama host, workspace, writes enabled, and Online runtime policy. |
| Non-elevated diagnostics | **Warning** | The non-elevated shell could not inspect Docker/sockets and produced misleading “not listening”/access-denied output. |
| Workbench/OAuth process lifecycle | **Warning** | Runtime PID files and Python processes remained after the listener check; lifecycle cleanup needs verification. |

## Open WebUI (port 3000)

| Feature | Result | Notes |
|---|---|---|
| Page load | Pass, transient | Open WebUI title and sign-in page rendered. |
| Sign-in form | Pass | Email, password, visibility control, and Sign in button were present. |
| Authenticated chat/model selection | Not tested | Requires a valid local account; no credentials were entered. |
| Empty sign-in submission | Inconclusive | Clicking Sign in with blank fields did not visibly navigate or expose an inline message in the captured DOM; authentication behavior remains pending. |
| Chat, attachments, documents, RAG, settings | Not tested | Sign-in gate prevented access. |

## Local Agent Studio (port 3001)

| Feature | Result | Notes |
|---|---|---|
| Page load and readiness badge | Pass, transient | `Local · Ready` displayed. |
| Operating mode selector | Pass | Online, Restricted Online, and Strict Offline options were present. |
| Mode switching | Pass | Studio and Workbench accepted Restricted Online/Strict Offline selections and were restored to Online; the UI displayed the active mode notification. |
| Primary navigation | Pass | Agents, MCP Servers, and Status navigation rendered and switched views. |
| Agent list | Pass | Four configured agents were displayed, including the three samples and one custom agent. |
| Agent backing-model selector | Pass | Installed model options were populated. |
| Agent role selector | Pass | General Conversation, Reasoning, Coding, Deep Research, and All were present. |
| Agent permissions controls | Pass | Utility, web, workspace read/write, delete, and command controls rendered. |
| New agent flow | Partially tested | New-agent controls were available; no persistent change was submitted during QA. |
| New-agent form | Pass | Backing LLM model, Role, Maximum tool steps, instructions, permissions, and Save controls were present. An invalid name was rejected with a clear `My Custom` prefix requirement; a valid temporary agent saved successfully, then was deleted and remained absent after reload. |
| MCP server form | Pass | Server ID, display name, URL, timeout, offline toggle, auth type, scopes, headers, diagnostics, and connection-action controls rendered. A temporary server saved successfully, the offline toggle could be checked/unchecked, and the temporary server was deleted and absent after reload. |
| MCP authentication/connection | Not tested | Would contact an external provider or require credentials. |
| Status view | Pass | Gateway showed Healthy; four configured/enabled agents were reported; MCP summary rendered. |
| Save/delete persistence | Not tested | Avoided destructive or persistent configuration changes in this pass. |

## Developer Workbench (port 3002)

| Feature | Result | Notes |
|---|---|---|
| Page load and readiness badge | Pass, transient | Projects view rendered with `Local · Ready`. |
| Operating mode selector | Pass | Online, Restricted Online, and Strict Offline options were present. |
| Mode switching | Pass | The Workbench accepted Strict Offline and Online selections; the task form reflected the active work-mode choices. |
| Projects view | Pass | One approved project was listed and selected. New task and Remove controls rendered. |
| Add-project form | Pass (surface) | Project name, Windows directory, Add project, and Cancel controls rendered; the form was opened and canceled without modifying the registry. |
| Tasks view | Pass | Existing completed and incomplete tasks rendered with activity/event history. |
| Agent assignment | Pass | Task history identified the selected agent and backing model. |
| Goal/protocol diagnostics | Pass | The incomplete task displayed recovered JSON-tool events, file-not-found errors, completion-quality status, and repetition-stop diagnostics. |
| Git view | Pass | Status, Working diff, Staged diff, branch, commit, and push controls rendered. |
| Git safety gating | Pass (surface only) | Commit/branch actions were disabled until required inputs were supplied; push was presented as confirmation-gated. |
| New change-task dialog | Partially tested | The task entry control was present, but the active task selection prevented a clean fresh-dialog submission in this run. |
| New change-task form | Pass (surface) | Project, Agent, Work mode (Ask/Plan/Goal), request textbox, guidance, Cancel, and Start task controls were present. Start was disabled with an empty request and enabled after entering a request; no task was submitted. |
| Project file mutation and verification | Not retested | Existing task history proves one earlier successful task and one invalid/incomplete task; a new mutation was not submitted during this QA pass. |
| Workbench task execution | **Fail/unstable** | Existing task history shows malformed assistant tool JSON, wrong/duplicate paths, no meaningful target-module patch, and repetition termination. |

## Defects and follow-up items

1. **Service persistence is not verified.** All three ports became unavailable
   after initially serving pages. Investigate Docker engine permissions, compose
   lifecycle, and the stale Python/PID cleanup path.
2. **Docker diagnostics are not actionable enough for a normal-user launch.**
   The current session received Docker engine/config access-denied errors; the
   UI should surface this state instead of leaving stale-looking readiness pages.
3. **Workbench path/build-module validation remains insufficient.** A prior
   task wrote only a placeholder comment into a duplicate root-level source
   tree rather than the Maven module used by the project. Approval of a path did
   not prove that the path was build-relevant.
4. **Open WebUI functional coverage remains pending authentication.** Chat,
   model loading, documents, and attachment workflows require a signed-in local
   account and should be tested separately.
5. **Persistent configuration and destructive lifecycle actions were not run**
   in this report to avoid changing the user’s installed agents, MCP servers,
   projects, models, or containers.

## Connectivity-mode verification

The Online, Restricted Online, and Strict Offline selectors were exercised in
both Agent Studio and Developer Workbench. Each selection updated the shared
policy and the active-mode banner in both applications. The gateway health
response reflected the selected policy (`online`, `restricted-online`, or
`strict-offline`) while the mode was active.

| Mode | Agent Studio | Developer Workbench | Observed enforcement |
|---|---|---|---|
| Online | Pass | Pass | Ready state remained visible; local and external capabilities were available according to the Online policy. |
| Restricted Online | Pass | Pass | Both UIs displayed the Restricted Online banner; local AI remained available while external LLM/agent/MCP/OAuth access was described as blocked. |
| Strict Offline | Pass | Pass | Both UIs displayed the Strict Offline banner; local models/files/local Git remained available, while external MCP, OAuth, HTTP, remote Git, dependency downloads, and arbitrary commands were described as blocked. Workbench Push was disabled. |
| Restore Online | Pass | Pass | Restoring Online updated the gateway health policy to `online` (revision 11) and the Studio selector showed Online selected. |

This verifies mode propagation and the UI policy gates. It does not prove every
individual network or command path under every mode; those require targeted
authenticated/side-effect tests.

## Overall result

**Partially verified based on this run.** The UI surfaces are present, the
three ports are listening under a privileged check, and the core navigation and
configuration surfaces worked. Full end-to-end coverage remains incomplete
because Open WebUI authentication, MCP authentication, persistent configuration
changes, and controlled Workbench mutations were not submitted. The diagnostic
commands should also be made privilege-aware so users do not receive a false
failure signal.
