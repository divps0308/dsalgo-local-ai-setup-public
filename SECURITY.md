# Security notes

The agent gateway, native Developer Workbench, and native MCP OAuth broker are
intended for a single-user local workstation.

The security design is appropriate for that local developer-machine scope, not
an internet-facing or multi-user deployment. Installation and reliability are
still controlled-beta outside the validated Windows/NVIDIA path. Restricted
Online and Strict Offline are application policies, not machine-wide firewall
or air-gap guarantees; unrelated Windows processes and integrations can still
use the network.

- Open WebUI requires a local login.
- The agent API uses a package-local static key and binds to localhost port 8001 through Docker Desktop. Do not expose ports 3000, 3001, 3002, 3003, 8001, or 11434 through router forwarding, public tunnels, or permissive firewall rules.
- Only the `workspace` directory is mounted into the agent container.
- The gateway runs as a non-root user, drops Linux capabilities, enables `no-new-privileges`, and does not mount the Docker socket.
- The built-in URL-fetch tool rejects resolved private and reserved IP ranges and does not follow redirects. Command execution and test code run inside the gateway container, which still needs network access to reach Ollama; do not run untrusted repositories.
- Local models can make incorrect tool choices. Review generated changes and outputs before using them in production.
- Do not place credentials, private keys, browser profiles, password files, or production data in the workspace.

## MCP OAuth boundary

- The native broker binds to `127.0.0.1:3003`, refuses to run elevated through
  the supported start script, and uses a runtime bearer token for Studio and
  Gateway API calls.
- OAuth Authorization Code flows use PKCE and a short-lived cryptographic
  `state`; browser start links are single-use and expire.
- Discovery validates HTTPS metadata endpoints, resource identifiers, and
  authorization-server issuers. Redirect callbacks return only to the
  broker's loopback address.
- Access and refresh tokens, dynamic client credentials, issuer metadata, and
  expiry state are stored as one DPAPI-protected bundle in
  `config/oauth-tokens.dpapi.json`, bound to the current Windows user.
- Tokens are never written to `config/agents.json`, `.env`, logs, Studio API
  responses, or supported backups. Gateway receives only the current access
  token over an authenticated local broker call.
- Remote MCP authorization and tool calls leave the local machine. Review the
  provider, scopes, data policy, and tools before connecting or assigning a
  server to an agent.
- Disconnect removes the local token bundle for that server. It does not
  necessarily revoke authorization at the provider; use the provider's account
  security page when explicit revocation is required.

## Native Developer Workbench boundary

- Developer Workbench binds to `127.0.0.1` only and rejects non-local Host
  headers. Its browser API requires a random token stored under
  `runtime/developer-workbench/`.
- A user must explicitly register each Windows project root. File tools resolve
  paths beneath that root and reject traversal; registering an entire drive
  root is prohibited.
- Read and Git-inspection tools can run automatically. Every model-proposed
  write, deletion, or native PowerShell command creates an approval card and
  waits for an explicit user decision.
- Approval cards are created only from structured Workbench tool calls. Model
  prose that contains a command or asks the user to approve it is not parsed or
  executed.
- Approval cards are created only from structured Workbench tool calls. Model
  prose that contains a command or asks the user to approve it is not parsed or
  executed.
- Commands execute with the privileges of the account that started the
  Workbench. Do not start it from an elevated Administrator session.
- Approved commands are intentionally capable of invoking arbitrary installed
  executables, Docker, package managers, build tools, and network clients.
  Approval is a security decision, not merely a workflow acknowledgment.
- Patch previews are textual and may not represent binary files, generated
  files, side effects produced by commands, or changes made by child processes.
  Inspect Git status and diff after execution.
- Git commit stages all changes in the selected project. Git push is available
  only through an explicit UI confirmation. Verify branch, remote, diff, and
  credentials before approving it.
- Project paths and task history may disclose private filenames, prompts,
  patches, and command output. They are stored locally in
  `config/projects.json` and `runtime/developer-workbench/tasks.json`;
  Workbench runtime history is excluded from normal backups.
## Public release and signing controls

The repository does not contain and must not contain a signing private key, PFX, password, or
personal certificate-store export. The checked-in certificate (if present) is
public verification material only and cannot sign executables without its
private key. If a private key was ever exposed, rotate it and treat previous
artifacts as untrusted.

Configure `main` branch protection, required CI checks, and a protected
`release` environment in GitHub. Limit that environment and release workflow
approval to the project owner (`divps0308`). Store signing inputs only as
environment secrets. Contributors may propose changes through pull requests,
but releases must be created from the protected workflow by the owner.

The repository's release workflow intentionally refuses to run without the
protected signing secrets; it does not generate or accept a contributor's
local self-signed key. It imports the owner-controlled PFX only on an
ephemeral Windows runner, publishes the public certificate and checksums, and
deletes the imported key material before the job ends.
## Public release and signing controls

The repository must never contain a signing private key, PFX, password, or
personal certificate-store export. The checked-in certificate (if present) is
public verification material only and cannot sign executables without its
private key. If a private key was ever exposed, rotate it and treat previous
artifacts as untrusted.

Configure `main` branch protection, required CI checks, and a protected
`release` environment in GitHub. Limit that environment and release workflow
approval to the project owner (`divps0308`). Store signing inputs only as
environment secrets. Contributors may propose changes through pull requests,
but releases must be created from the protected workflow by the owner.

The repository's release workflow intentionally refuses to run without the
protected signing secrets; it does not generate or accept a contributor's
local self-signed key.
