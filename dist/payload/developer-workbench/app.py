"""Native Windows developer workbench for approved local project roots."""

from __future__ import annotations

import argparse
import difflib
import json
import mimetypes
import os
import re
import secrets
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent
CONFIG_DIR = ROOT / "config"
RUNTIME_DIR = ROOT / "runtime" / "developer-workbench"
PROJECTS_FILE = CONFIG_DIR / "projects.json"
TASKS_FILE = RUNTIME_DIR / "tasks.json"
TOKEN_FILE = RUNTIME_DIR / "token"
LOG_FILE = ROOT / "logs" / "developer-workbench.log"
MODELS_FILE = CONFIG_DIR / "models.json"
AGENTS_FILE = CONFIG_DIR / "agents.json"
POLICY_FILE = CONFIG_DIR / "runtime-policy.json"
MAX_READ_BYTES = 5_000_000
MAX_OUTPUT = 100_000
MAX_AGENT_STEPS = 30
STATIC_DIR = Path(__file__).resolve().parent / "static"
VALID_MODES = {"online", "restricted-online", "strict-offline"}
WORK_MODES = {"ask", "plan", "goal"}
READ_ONLY_TOOL_NAMES = {"list_files", "read_file", "search_files", "git_status", "git_diff"}

def load_policy() -> dict[str, Any]:
    default = {"schemaVersion": 1, "mode": "online", "revision": 1, "updatedAt": None}
    try:
        value = json.loads(POLICY_FILE.read_text(encoding="utf-8"))
        return {**default, **value} if value.get("mode") in VALID_MODES else default
    except Exception:
        return default

def save_policy(mode: str, revision: int | None = None) -> dict[str, Any]:
    current = load_policy()
    if mode not in VALID_MODES:
        raise ValueError("Unsupported operating mode")
    if revision is not None and int(revision) != int(current["revision"]):
        raise ValueError("Operating mode changed; refresh and retry")
    value = {"schemaVersion": 1, "mode": mode, "revision": int(current["revision"]) + 1, "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    temporary = POLICY_FILE.with_name(f"{POLICY_FILE.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    temporary.replace(POLICY_FILE)
    return value


def log(message: str) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write(f"{stamp} {message}\n")


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default


def save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding="utf-8")
    temp.replace(path)


def public_task(task: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in task.items() if not k.startswith("_")}


@dataclass
class State:
    token: str
    projects: list[dict[str, Any]] = field(default_factory=list)
    tasks: dict[str, dict[str, Any]] = field(default_factory=dict)
    lock: threading.RLock = field(default_factory=threading.RLock)
    approval_events: dict[str, threading.Event] = field(default_factory=dict)
    cancel_events: dict[str, threading.Event] = field(default_factory=dict)

    def persist_projects(self) -> None:
        save_json(PROJECTS_FILE, {"projects": self.projects})

    def persist_tasks(self) -> None:
        save_json(TASKS_FILE, {"tasks": [public_task(t) for t in self.tasks.values()]})

    def project(self, project_id: str) -> dict[str, Any]:
        item = next((p for p in self.projects if p["id"] == project_id), None)
        if not item:
            raise ValueError("Unknown project")
        return item

    def update_task(self, task_id: str, **values: Any) -> None:
        with self.lock:
            task = self.tasks[task_id]
            task.update(values)
            task["updatedAt"] = time.time()
            self.persist_tasks()


def initialize_state() -> State:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    if TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text(encoding="ascii").strip()
    else:
        token = secrets.token_urlsafe(32)
        TOKEN_FILE.write_text(token, encoding="ascii")
    projects = load_json(PROJECTS_FILE, {"projects": []}).get("projects", [])
    previous = load_json(TASKS_FILE, {"tasks": []}).get("tasks", [])
    tasks: dict[str, dict[str, Any]] = {}
    for task in previous:
        if task.get("status") in {"running", "waiting_approval"}:
            task["status"] = "interrupted"
            task["error"] = "Workbench restarted before the task completed."
        tasks[task["id"]] = task
    state = State(token=token, projects=projects, tasks=tasks)
    state.persist_tasks()
    return state


STATE = initialize_state()


def safe_project_path(project: dict[str, Any], relative: str = ".") -> Path:
    root = Path(project["path"]).resolve()
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError("Path escapes the approved project root") from exc
    return candidate


def run_process(args: list[str], cwd: Path, timeout: int = 300) -> dict[str, Any]:
    timeout = max(1, min(int(timeout), 3600))
    try:
        result = subprocess.run(
            args,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        return {
            "exitCode": result.returncode,
            "stdout": result.stdout[-MAX_OUTPUT:],
            "stderr": result.stderr[-MAX_OUTPUT:],
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "exitCode": -1,
            "stdout": (exc.stdout or "")[-MAX_OUTPUT:] if isinstance(exc.stdout, str) else "",
            "stderr": f"Command timed out after {timeout} seconds.",
        }
    except OSError as exc:
        return {"exitCode": -1, "stdout": "", "stderr": str(exc)}


def git(project: dict[str, Any], arguments: list[str], timeout: int = 120) -> dict[str, Any]:
    return run_process(["git", *arguments], Path(project["path"]), timeout)


def risk_for_command(command: str) -> str:
    high = re.compile(
        r"(?i)\b(remove-item|del|erase|rmdir|rd|format|diskpart|shutdown|restart-computer|"
        r"stop-computer|git\s+(push|reset|clean)|docker\s+(system\s+prune|volume\s+rm)|"
        r"winget\s+(install|uninstall)|choco\s+(install|uninstall)|npm\s+publish|dotnet\s+nuget\s+push)\b"
    )
    return "high" if high.search(command) else "normal"

def restricted_developer_command(command: str) -> bool:
    match = re.match(r"^\s*(?:&\s*)?(?:['\"])?(?:\.?[\\/])?(?:[^\\/\s'\"]+[\\/])*([^\\/\s'\"]+)", command)
    executable = (match.group(1) if match else "").lower().removesuffix(".exe").removesuffix(".cmd").removesuffix(".bat")
    return executable in {
        "mvn","mvnw","gradle","gradlew","npm","npx","pnpm","yarn","dotnet","msbuild",
        "docker","git","cargo","rustc","go","javac","java","pytest","ctest","cmake","make",
    }


def read_text(path: Path) -> str:
    if not path.is_file():
        raise ValueError("File not found")
    if path.stat().st_size > MAX_READ_BYTES:
        raise ValueError("File exceeds the 5 MB read limit")
    text = path.read_text(encoding="utf-8", errors="replace")
    markers = ("Ã", "Â", "â", "ä", "å", "ç")
    if any(marker in text for marker in markers):
        try:
            repaired = text.encode("latin-1").decode("utf-8")
            if sum(text.count(marker) for marker in markers) > sum(repaired.count(marker) for marker in markers):
                return repaired
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
    return text


def unified_patch(relative: str, before: str, after: str) -> str:
    return "".join(
        difflib.unified_diff(
            before.splitlines(keepends=True),
            after.splitlines(keepends=True),
            fromfile=f"a/{relative}",
            tofile=f"b/{relative}",
        )
    ) or "(No textual change)"


def broad_rewrite_allowed(prompt: str) -> bool:
    return bool(re.search(r"(?i)\b(rewrite|replace|re-create|regenerate|migrate|refactor the entire|rewrite the entire|replace the whole)\b", prompt or ""))


def focused_edit_violation(before: str, after: str, prompt: str) -> bool:
    """Reject likely whole-file replacement unless the user requested it."""
    if not before.strip() or broad_rewrite_allowed(prompt):
        return False
    before_lines = before.splitlines()
    after_lines = after.splitlines()
    if len(before_lines) < 20:
        return False
    similarity = difflib.SequenceMatcher(None, before_lines, after_lines).ratio()
    return similarity < 0.35


COMPLETION_CLAIM_WORDS = re.compile(
    r"(?i)\b(?:task|change|changes|code|console message|compilation|build|tests?)\b.*\b(?:complete|completed|finished|successfully|verified|no further)\b"
)
VERIFICATION_REQUEST_WORDS = re.compile(
    r"(?i)\b(?:compile|compilation|build|test|tests|testing|verify|verification|lint|format|check)\b"
)


def command_fingerprint(command: str) -> str:
    if is_claim_only_command(command):
        return "completion-claim"
    """Normalize command wording for semantic duplicate detection."""
    value = re.sub(r"(?i)^\s*(?:powershell(?:\.exe)?\s+)?(?:-command\s+)?", "", command or "")
    value = re.sub(r"(?i)\b(?:the task|this task|the change|the code|the console message)\b", "task", value)
    value = re.sub(r"(?i)\b(?:has been|was|is|will be)\b", "", value)
    value = re.sub(r"(?i)\b(?:successfully|fully|now|just|already)\b", "", value)
    value = re.sub(r"(?i)\b(?:added|applied|completed|complete|finished|verified|done)\b", "complete", value)
    value = re.sub(r"[\"'`.;:!?(),]+", " ", value)
    return re.sub(r"\s+", " ", value).strip().lower()


def is_claim_only_command(command: str) -> bool:
    """Return true for shell commands that only print an unverified claim."""
    normalized = re.sub(r"\s+", " ", (command or "").strip().lower())
    return bool(
        re.match(r"(?i)^(?:echo|write-host|write-output|printf|print)\b", command or "")
        and COMPLETION_CLAIM_WORDS.search(normalized)
    )


def verification_kind(command: str) -> str | None:
    """Classify commands that can provide deterministic verification evidence."""
    normalized = re.sub(r"\s+", " ", (command or "").strip().lower())
    if is_claim_only_command(command):
        return None
    if re.search(r"\bgit\s+(?:diff|status)\b", normalized):
        return "inspection"
    if re.search(r"(?:^|\s)(?:mvnw(?:\.cmd)?|mvn)\s+.*\b(?:compile|test|verify|package|install)\b", normalized):
        return "build"
    if re.search(r"(?:^|\s)(?:gradlew(?:\.bat)?|gradle)\s+.*\b(?:build|test|check)\b", normalized):
        return "build"
    if re.search(r"(?:^|\s)(?:npm|pnpm|yarn)\s+.*\b(?:build|test|check|lint)\b", normalized):
        return "build"
    if re.search(r"(?:^|\s)(?:dotnet)\s+.*\b(?:build|test)\b", normalized):
        return "build"
    if re.search(r"(?:^|\s)(?:pytest|cargo\s+(?:test|build|check)|go\s+(?:test|build))\b", normalized):
        return "build"
    return None


def prompt_requires_verification(prompt: str) -> bool:
    return bool(VERIFICATION_REQUEST_WORDS.search(prompt or ""))


def has_successful_required_verification(task: dict[str, Any], prompt: str) -> bool:
    required = prompt_requires_verification(prompt)
    for event in task.get("events", []):
        if event.get("kind") != "command" or not isinstance(event.get("content"), dict):
            continue
        if int(event["content"].get("exitCode", -1)) != 0:
            continue
        kind = verification_kind(str(event["content"].get("command", "")))
        if kind == "build" or (kind == "inspection" and not required):
            return True
    return False


TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "list_files",
            "description": "List files in the approved project.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "recursive": {"type": "boolean"},
                    "max_entries": {"type": "integer"},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read a UTF-8 text file in the approved project.",
            "parameters": {
                "type": "object",
                "properties": {"path": {"type": "string"}},
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "search_files",
            "description": "Search project text files for a literal string.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "path": {"type": "string"},
                    "max_results": {"type": "integer"},
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "propose_write_file",
            "description": "Propose creating or replacing a file. The user reviews a unified patch before execution.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "content": {"type": "string"},
                    "reason": {"type": "string"},
                },
                "required": ["path", "content", "reason"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "propose_delete_file",
            "description": "Propose deleting one file. User approval is always required.",
            "parameters": {
                "type": "object",
                "properties": {"path": {"type": "string"}, "reason": {"type": "string"}},
                "required": ["path", "reason"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "propose_command",
            "description": "Propose a native Windows PowerShell command in the project directory. Approval is always required.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string"},
                    "reason": {"type": "string"},
                    "timeout_seconds": {"type": "integer"},
                },
                "required": ["command", "reason"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "git_status",
            "description": "Read git status for the approved project.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "git_diff",
            "description": "Read the current git diff for the approved project.",
            "parameters": {
                "type": "object",
                "properties": {"staged": {"type": "boolean"}},
            },
        },
    },
]

for tool_definition in TOOLS:
    # Make the schema sent to Ollama match the controller's strict validation.
    # Models then receive an explicit signal that invented arguments are invalid.
    tool_definition["function"]["parameters"]["additionalProperties"] = False

TOOL_NAMES = {tool["function"]["name"] for tool in TOOLS}
PROTOCOL_VERSION = 1
MAX_PROTOCOL_REPAIRS = 3

# Models from different providers sometimes use familiar argument names from
# other coding tools. Translate only aliases whose meaning is unambiguous; the
# canonical schema below remains the sole execution contract.
TOOL_ARGUMENT_ALIASES: dict[str, dict[str, str]] = {
    "list_files": {"base_dir": "path", "directory": "path", "max_results": "max_entries"},
    "read_file": {"file_path": "path", "filename": "path"},
    "search_files": {
        "content_pattern": "query",
        "search_term": "query",
        "base_dir": "path",
        "directory": "path",
        "limit": "max_results",
    },
    "propose_write_file": {"file_path": "path", "description": "reason"},
    "propose_delete_file": {"file_path": "path", "description": "reason"},
    "propose_command": {"cmd": "command", "description": "reason", "timeout": "timeout_seconds"},
}


def tool_schema(name: str) -> dict[str, Any]:
    item = next((tool for tool in TOOLS if tool["function"]["name"] == name), None)
    return item["function"]["parameters"] if item else {}


def normalize_and_validate_tool_call(call: Any) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    """Normalize one untrusted model action and validate its complete schema."""
    if not isinstance(call, dict):
        return None, {"code": "invalid_tool_call", "message": "Tool call must be a JSON object."}
    function = call.get("function") if isinstance(call.get("function"), dict) else call
    name = function.get("name") or function.get("type")
    if name not in TOOL_NAMES:
        return None, {"code": "unknown_tool", "message": f"Unknown Workbench tool: {name!r}."}
    arguments = function.get("arguments", {})
    if isinstance(arguments, str):
        try:
            arguments = json.loads(arguments)
        except json.JSONDecodeError as exc:
            return None, {"code": "invalid_json", "tool": name, "message": str(exc)}
    if not isinstance(arguments, dict):
        return None, {"code": "invalid_arguments", "tool": name, "message": "Tool arguments must be a JSON object."}

    aliases = TOOL_ARGUMENT_ALIASES.get(name, {})
    translated: dict[str, Any] = {}
    used_aliases: dict[str, str] = {}
    for key, value in arguments.items():
        canonical = aliases.get(key, key)
        if canonical in translated and canonical != key:
            continue
        translated[canonical] = value
        if canonical != key:
            used_aliases[key] = canonical

    if name == "search_files" and "content_pattern" in used_aliases and isinstance(translated.get("query"), str):
        # search_files is deliberately literal. Remove only regex escaping of
        # punctuation when a model used the content_pattern compatibility
        # alias; do not otherwise reinterpret or execute a regular expression.
        translated["query"] = re.sub(r"\\([()[\]{}.+*?^$|])", r"\1", translated["query"])

    # A common search shape includes a file glob plus content_pattern. The
    # current search tool searches text recursively, so the glob is redundant
    # and safe to omit. Other unknown fields remain validation failures.
    ignored: list[str] = []
    if name == "search_files" and "pattern" in translated and "query" in translated:
        translated.pop("pattern")
        ignored.append("pattern")

    schema = tool_schema(name)
    properties = schema.get("properties", {})
    required = schema.get("required", [])
    missing = [key for key in required if key not in translated or translated[key] in (None, "")]
    unsupported = sorted(set(translated) - set(properties))
    type_errors: list[str] = []
    python_types = {"string": str, "integer": int, "boolean": bool, "object": dict}
    for key, value in translated.items():
        expected = properties.get(key, {}).get("type")
        if expected == "integer" and isinstance(value, str) and re.fullmatch(r"[+-]?\d+", value.strip()):
            translated[key] = int(value)
            value = translated[key]
        elif expected == "boolean" and isinstance(value, str) and value.strip().lower() in {"true", "false"}:
            translated[key] = value.strip().lower() == "true"
            value = translated[key]
        expected_type = python_types.get(expected)
        if expected_type and (not isinstance(value, expected_type) or expected == "integer" and isinstance(value, bool)):
            type_errors.append(f"{key} must be {expected}")
    if missing or unsupported or type_errors:
        return None, {
            "code": "invalid_arguments",
            "tool": name,
            "message": "Tool arguments do not match the Workbench schema.",
            "missing": missing,
            "unsupported": unsupported,
            "typeErrors": type_errors,
            "expected": {"required": required, "properties": sorted(properties)},
        }
    return {
        "type": "function",
        "function": {"name": name, "arguments": translated},
        "normalization": {"aliases": used_aliases, "ignored": ignored},
    }, None


def protocol_error_message(error: dict[str, Any]) -> str:
    return json.dumps(
        {"version": PROTOCOL_VERSION, "type": "protocol_error", **error},
        ensure_ascii=False,
        sort_keys=True,
    )


def protocol_contract_summary() -> str:
    contract: dict[str, Any] = {}
    for name in sorted(TOOL_NAMES):
        schema = tool_schema(name)
        contract[name] = {
            "required": schema.get("required", []),
            "allowed": sorted(schema.get("properties", {})),
        }
    return json.dumps(contract, ensure_ascii=False, separators=(",", ":"))


def extract_text_tool_call(content: Any) -> dict[str, Any] | None:
    """Recover a single JSON tool request emitted as assistant text.

    Some small Ollama models understand the tool schema but serialize the
    request in a fenced JSON block instead of populating ``message.tool_calls``.
    Only the exact {name, arguments} shape is accepted, and the name must be a
    Workbench tool so this compatibility path cannot bypass the tool boundary.
    """
    if not isinstance(content, str) or not content.strip():
        return None
    candidates = re.findall(r"```(?:json)?\s*(\{.*?\})\s*```", content, flags=re.IGNORECASE | re.DOTALL)
    candidates.append(content.strip())
    for candidate in candidates:
        try:
            value = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if not isinstance(value, dict):
            continue
        # Some Ollama models emit the tool request as {type, ...} (often
        # inside a fenced block) instead of the OpenAI/Ollama {name,
        # arguments} envelope. Normalize only the documented Workbench
        # tools and their exact argument aliases; never execute arbitrary
        # JSON emitted as assistant text.
        if value.get("version") == PROTOCOL_VERSION and value.get("type") == "tool_call" and "name" in value:
            name = value.get("name")
            arguments = value.get("arguments", {})
        elif "name" in value and not (set(value) - {"name", "arguments"}):
            name = value.get("name")
            arguments = value.get("arguments", {})
        elif "type" in value and value.get("type") in TOOL_NAMES:
            name = value.get("type")
            arguments = {k: v for k, v in value.items() if k != "type"}
            aliases = {"file_path": "path", "description": "reason"}
            arguments = {aliases.get(k, k): v for k, v in arguments.items()}
            raw_content = arguments.get("content")
            if isinstance(raw_content, str):
                fenced = re.fullmatch(r"\s*```[^\n]*\n(.*?)\n```\s*", raw_content, flags=re.DOTALL)
                if fenced:
                    arguments["content"] = fenced.group(1)
        else:
            continue
        if name not in TOOL_NAMES or not isinstance(arguments, dict):
            continue
        return {"type": "function", "function": {"name": name, "arguments": arguments}}
    return None


def normalize_tool_call(call: Any) -> dict[str, Any] | None:
    """Normalize native or compatibility tool calls at the trust boundary.

    Model output is untrusted data. Only known Workbench tools with object
    arguments are admitted; everything else remains ordinary assistant text
    and can never be executed implicitly.
    """
    normalized, _ = normalize_and_validate_tool_call(call)
    return normalized


def protocol_tool_result(name: str, output: str) -> str:
    """Return a stable JSON envelope for the next model turn."""
    try:
        result: Any = json.loads(output)
    except (TypeError, json.JSONDecodeError):
        result = output
    ok = not (isinstance(result, dict) and result.get("type") == "protocol_error")
    return json.dumps(
        {"version": PROTOCOL_VERSION, "type": "tool_result", "tool": name, "ok": ok, "result": result},
        ensure_ascii=False,
    )


def parse_protocol_response(content: Any) -> dict[str, Any] | None:
    """Parse the explicit v1 assistant envelope without interpreting prose."""
    if not isinstance(content, str) or not content.strip():
        return None
    candidate = content.strip()
    fenced = re.fullmatch(r"```(?:json)?\s*(\{.*\})\s*```", candidate, flags=re.I | re.S)
    if fenced:
        candidate = fenced.group(1)
    try:
        value = json.loads(candidate)
    except json.JSONDecodeError:
        return None
    if not isinstance(value, dict) or value.get("version") != PROTOCOL_VERSION:
        return None
    kind = value.get("type")
    if kind == "tool_call":
        return normalize_tool_call(value)
    if kind in {"progress", "complete", "blocked"}:
        message = value.get("message", value.get("summary", ""))
        return {"type": kind, "message": str(message)}
    return None


def model_for_role(role: str) -> tuple[str, dict[str, Any]]:
    registry = load_json(MODELS_FILE, {}).get("models", {})
    if role not in {"general", "coder", "reasoning"}:
        role = "coder"
    cfg = registry.get(role)
    if not cfg:
        raise ValueError(f"Model role is not configured: {role}")
    return cfg["ollamaTag"], cfg


def available_agents() -> list[dict[str, Any]]:
    """Return enabled configured agents without exposing instructions or secrets."""
    configured = load_json(AGENTS_FILE, {"agents": []}).get("agents", [])
    result: list[dict[str, Any]] = []
    for item in configured if isinstance(configured, list) else []:
        if not isinstance(item, dict) or not item.get("enabled", True):
            continue
        agent_id = str(item.get("id", "")).strip()
        if not agent_id:
            continue
        result.append({
            "id": agent_id,
            "name": str(item.get("name") or item.get("displayName") or agent_id),
            "modelTag": str(item.get("modelTag", "")).strip(),
            "modelRole": str(item.get("modelRole") or item.get("role") or "general"),
            "maxSteps": max(1, min(int(item.get("maxSteps", MAX_AGENT_STEPS)), 1000)),
            "toolCalling": bool(item.get("toolCalling", True)),
        })
    return result


def model_for_agent(agent_id: str) -> tuple[str, dict[str, Any], dict[str, Any]]:
    """Resolve an agent to a model registry entry deterministically."""
    agent = next((a for a in available_agents() if a["id"] == agent_id), None)
    if not agent:
        raise ValueError("Selected agent is not configured or is disabled")
    registry = load_json(MODELS_FILE, {}).get("models", {})
    tag = agent.get("modelTag", "")
    cfg = next((value for value in registry.values() if isinstance(value, dict) and value.get("ollamaTag") == tag), None)
    if cfg is None:
        if not tag:
            raise ValueError(f"Backing model is not configured for agent: {agent_id}")
        # Custom agents may select an installed Ollama model that is not part
        # of the curated catalog. Validate its presence, then use conservative
        # deterministic runtime defaults rather than inferring capabilities.
        try:
            request = urllib.request.Request("http://127.0.0.1:11434/api/tags", method="GET")
            with urllib.request.urlopen(request, timeout=10) as response:
                installed = json.loads(response.read().decode("utf-8")).get("models", [])
            names = {str(item.get("name", "")) for item in installed if isinstance(item, dict)}
        except Exception as exc:
            raise ValueError(f"Could not verify installed backing model '{tag}': {exc}") from exc
        if tag not in names:
            raise ValueError(f"Backing model is not installed in Ollama: {tag}")
        cfg = {
            "ollamaTag": tag,
            "displayName": tag,
            "numCtx": 8192,
            "temperature": 0.2,
            "keepAlive": "10m",
            "toolCalling": True,
        }
    return str(cfg["ollamaTag"]), cfg, agent


def ollama_chat(model: str, cfg: dict[str, Any], messages: list[dict[str, Any]], work_mode: str = "goal") -> dict[str, Any]:
    payload = {
        "model": model,
        "messages": messages,
        "tools": [tool for tool in TOOLS if work_mode == "goal" or tool["function"]["name"] in READ_ONLY_TOOL_NAMES],
        "stream": False,
        "keep_alive": cfg.get("keepAlive", "10m"),
        "options": {
            "num_ctx": cfg.get("numCtx", 16384),
            "temperature": cfg.get("temperature", 0.2),
        },
    }
    if work_mode == "goal" and cfg.get("structuredOutput", True):
        payload["format"] = "json"
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/chat",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=900) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        # Older Ollama releases may reject the format field. Retry once
        # without it; tool execution remains protected by validation below.
        if "format" not in payload:
            raise
        payload.pop("format", None)
        fallback = urllib.request.Request(
            "http://127.0.0.1:11434/api/chat",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(fallback, timeout=900) as response:
            return json.loads(response.read().decode("utf-8"))


def add_event(task_id: str, kind: str, content: Any) -> None:
    with STATE.lock:
        task = STATE.tasks[task_id]
        task.setdefault("events", []).append(
            {"id": uuid.uuid4().hex, "time": time.time(), "kind": kind, "content": content}
        )
        task["updatedAt"] = time.time()
        STATE.persist_tasks()


def completion_quality(task: dict[str, Any], content: str, prompt: str = "") -> tuple[bool, str]:
    """Require evidence that a task actually finished or explicitly needed no change."""
    events = task.get("events", [])
    normalized = content.lower()
    actions = [event for event in events if event.get("kind") == "action"]
    if actions:
        # A Goal task may perform many approved actions. One action followed by
        # "next"/"we will proceed" is progress, not completion.
        has_conclusion = re.search(r"\b(completed|complete|finished|implemented|verified|all requested|no further changes)\b", normalized)
        is_continuing = re.search(r"\b(next|proceed|continue|let's start|will now|remaining)\b", normalized)
        last_action = max(float(event.get("time", 0)) for event in actions)
        verified_after_change = False
        for event in events:
            if float(event.get("time", 0)) <= last_action:
                continue
            if event.get("kind") == "command" and isinstance(event.get("content"), dict):
                verified_after_change = (
                    int(event["content"].get("exitCode", -1)) == 0
                    and verification_kind(str(event["content"].get("command", ""))) is not None
                    and (not prompt_requires_verification(prompt) or verification_kind(str(event["content"].get("command", ""))) == "build")
                )
            if event.get("kind") == "tool" and isinstance(event.get("content"), dict):
                verified_after_change = (
                    not prompt_requires_verification(prompt)
                    and event["content"].get("name") in {"read_file", "search_files", "git_diff", "git_status"}
                )
            if verified_after_change:
                break
        if has_conclusion and not is_continuing and verified_after_change:
            return True, ""
        if not verified_after_change:
            return False, "The requested files changed, but the agent has not inspected the resulting state or run a successful verification command after the last change."
        return False, "The Goal agent stopped after partial progress; it must continue until the requested goal is implemented and verified."
    if has_successful_required_verification(task, prompt):
        return True, ""
    no_change = re.search(r"\b(no changes? (are )?needed|no changes? (were )?made|nothing (to|needed to) change)\b", normalized)
    inspected = any(
        event.get("kind") == "tool"
        and isinstance(event.get("content"), dict)
        and event["content"].get("name") in READ_ONLY_TOOL_NAMES
        for event in events
    )
    if no_change and inspected:
        return True, ""
    if no_change:
        return False, "The model claimed no change was needed without first inspecting the approved project."
    return False, "The model stopped without a patch, successful command/test result, or explicit no-change conclusion."


def save_plan(project: dict[str, Any], prompt: str, content: str) -> str:
    """Save a user-requested plan artifact under the approved project root."""
    root = Path(project["path"]).resolve()
    plans = root / ".workbench-plans"
    plans.mkdir(exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "-", prompt.lower()).strip("-")[:60] or "implementation-plan"
    stamp = time.strftime("%Y%m%d-%H%M%S")
    candidate = plans / f"{stamp}-{slug}.md"
    suffix = 2
    while candidate.exists():
        candidate = plans / f"{stamp}-{slug}-{suffix}.md"
        suffix += 1
    body = f"# Implementation plan\n\n- Generated: {time.strftime('%Y-%m-%d %H:%M:%S %z')}\n- Request: {prompt}\n\n{content.strip()}\n"
    candidate.write_text(body, encoding="utf-8")
    return str(candidate.relative_to(root))


def request_approval(
    task_id: str, action_type: str, summary: str, details: dict[str, Any], risk: str = "normal"
) -> tuple[bool, dict[str, Any]]:
    approval_id = uuid.uuid4().hex
    event = threading.Event()
    with STATE.lock:
        approval = {
            "id": approval_id,
            "type": action_type,
            "summary": summary,
            "details": details,
            "risk": risk,
            "status": "pending",
            "createdAt": time.time(),
        }
        task = STATE.tasks[task_id]
        task.setdefault("approvals", []).append(approval)
        task["status"] = "waiting_approval"
        STATE.approval_events[approval_id] = event
        STATE.persist_tasks()
    event.wait()
    with STATE.lock:
        task = STATE.tasks[task_id]
        approval = next(a for a in task["approvals"] if a["id"] == approval_id)
        approved = approval["status"] == "approved"
        task["status"] = "running"
        STATE.approval_events.pop(approval_id, None)
        STATE.persist_tasks()
        return approved, approval


def execute_tool(task_id: str, project: dict[str, Any], name: str, args: dict[str, Any]) -> str:
    root = Path(project["path"])
    if name == "list_files":
        target = safe_project_path(project, args.get("path", "."))
        recursive = bool(args.get("recursive", False))
        limit = max(1, min(int(args.get("max_entries", 300)), 2000))
        if not target.exists():
            return "Path not found"
        items = target.rglob("*") if recursive else target.iterdir()
        rows = []
        for item in items:
            rows.append(("DIR " if item.is_dir() else "FILE ") + str(item.relative_to(root)))
            if len(rows) >= limit:
                rows.append("... truncated")
                break
        return "\n".join(rows)
    if name == "read_file":
        return read_text(safe_project_path(project, args["path"]))[:MAX_OUTPUT]
    if name == "search_files":
        query = str(args["query"])
        if not query or len(query) > 500:
            return "Search query is empty or too long"
        target = safe_project_path(project, args.get("path", "."))
        limit = max(1, min(int(args.get("max_results", 100)), 500))
        files = [target] if target.is_file() else target.rglob("*")
        rows: list[str] = []
        for file in files:
            try:
                if not file.is_file() or file.stat().st_size > 2_000_000:
                    continue
                for number, line in enumerate(read_text(file).splitlines(), 1):
                    if query.lower() in line.lower():
                        rows.append(f"{file.relative_to(root)}:{number}: {line[:500]}")
                        if len(rows) >= limit:
                            return "\n".join(rows)
            except OSError:
                continue
        return "\n".join(rows) or "No matches"
    if name == "git_status":
        return json.dumps(git(project, ["status", "--short", "--branch"]), ensure_ascii=False)
    if name == "git_diff":
        arguments = ["diff"]
        if args.get("staged"):
            arguments.append("--cached")
        return json.dumps(git(project, arguments), ensure_ascii=False)
    if name == "propose_write_file":
        relative = args["path"]
        target = safe_project_path(project, relative)
        before = read_text(target) if target.exists() else ""
        after = str(args["content"])
        # Models frequently wrap complete-file output in Markdown fences. That
        # is a proposal format, not valid file content, and must be rejected
        # before approval so fenced text cannot be written into source files.
        stripped = after.strip()
        if re.match(r"^```(?:[A-Za-z0-9_+-]+)?\s*\r?\n", stripped) and stripped.endswith("```"):
            return "Rejected proposed file content: remove Markdown code fences and return only the file contents."
        if not stripped:
            return "Rejected proposed file content: the file content cannot be empty."
        with STATE.lock:
            task_prompt = str(STATE.tasks.get(task_id, {}).get("prompt", ""))
        if focused_edit_violation(before, after, task_prompt):
            return (
                "Rejected broad file replacement: preserve unrelated code and make a focused edit. "
                "Read the current file, change only the relevant section, and resubmit the complete "
                "updated file. A full rewrite requires an explicit user request."
            )
        patch = unified_patch(relative, before, after)
        if patch == "(No textual change)":
            return f"No change needed: {relative} already contains the proposed content."
        approved, _ = request_approval(
            task_id,
            "write_file",
            f"Write {relative}",
            {"path": relative, "reason": args["reason"], "patch": patch},
        )
        if not approved:
            return "User rejected the file change."
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(after, encoding="utf-8")
        add_event(task_id, "action", f"Wrote {relative}")
        return f"Wrote {relative}"
    if name == "propose_delete_file":
        relative = args["path"]
        target = safe_project_path(project, relative)
        if not target.is_file():
            return "File does not exist or is not a regular file."
        before = read_text(target)
        approved, _ = request_approval(
            task_id,
            "delete_file",
            f"Delete {relative}",
            {"path": relative, "reason": args["reason"], "patch": unified_patch(relative, before, "")},
            "high",
        )
        if not approved:
            return "User rejected the file deletion."
        target.unlink()
        add_event(task_id, "action", f"Deleted {relative}")
        return f"Deleted {relative}"
    if name == "propose_command":
        command = str(args["command"])
        if is_claim_only_command(command):
            return (
                "Rejected completion-only command: this command only prints an "
                "unverified claim. Use a real build, test, or inspection command "
                "and report its structured result."
            )
        mode = load_policy()["mode"]
        if mode == "strict-offline":
            return "Command blocked by Strict Offline operating mode."
        if mode == "restricted-online" and not restricted_developer_command(command):
            return "Command blocked by Restricted Online mode. Only approved build, test, Docker, and Git executables are available."
        timeout = max(1, min(int(args.get("timeout_seconds", 300)), 3600))
        risk = risk_for_command(command)
        approved, _ = request_approval(
            task_id,
            "command",
            "Run native Windows PowerShell command",
            {"command": command, "reason": args["reason"], "cwd": str(root), "timeoutSeconds": timeout},
            risk,
        )
        if not approved:
            return "User rejected the command."
        result = run_process(
            ["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
            root,
            timeout,
        )
        add_event(task_id, "command", {"command": command, **result})
        return json.dumps(result, ensure_ascii=False)
    return f"Unknown tool: {name}"


def run_agent_task(task_id: str) -> None:
    try:
        with STATE.lock:
            task = STATE.tasks[task_id]
            project = STATE.project(task["projectId"])
            prompt = task["prompt"]
            agent_id = task.get("agentId", "")
            work_mode = task.get("workMode", "goal")
        if not agent_id:
            raise ValueError("Task agent is required; select an enabled agent in Local Agent Studio")
        model, cfg, agent = model_for_agent(agent_id)
        if work_mode == "goal" and cfg.get("toolCalling") is False:
            raise ValueError(
                f"Selected backing model '{model}' is not configured for structured tool calling. "
                "Use a tool-capable model for Goal mode, or use Ask/Plan mode."
            )
        max_steps = max(1, min(int(agent.get("maxSteps", MAX_AGENT_STEPS)), 1000))
        system = (
            "You are a local Windows coding agent operating on one user-approved project root: "
            f"{project['path']}. Inspect evidence before changing anything. Read tools run immediately. "
            "Every write, delete, or native Windows PowerShell command requires the user to approve an "
            "action card. Use propose_write_file with complete file content for edits. Use "
            "propose_command for Maven, Gradle, npm, .NET, Docker, Git, PowerShell, tests, formatters, "
            "or any executable. Never claim an action succeeded without its tool result. Keep changes "
            "minimal and finish with exact files changed and verification results. Do not ask for "
            "approval in ordinary assistant prose and then stop: when an edit or command is needed, "
            "invoke the corresponding approval-gated tool so the Workbench can display an actionable "
            "Approve/Reject card. In Goal mode, continue pursuing the requested change until it is "
            "implemented or a concrete blocking reason is recorded."
        )
        if work_mode == "goal":
            system += (
                " For every existing file, make the smallest focused change possible. Preserve all "
                "unrelated code, imports, comments, formatting, and configuration. Never replace or "
                "regenerate an entire file merely to change one method or section. A full rewrite is "
                "allowed only when the user's request explicitly asks for a rewrite, replacement, "
                "migration, or regeneration. Before propose_write_file, read the current file and "
                "return its complete content with only the requested section changed."
            )
        system += (
            " Workbench protocol v1 is active. Tool calls must be structured tool_calls "
            "with exactly one known function and JSON object arguments. If your client cannot "
            "populate tool_calls, return exactly one JSON object of the form "
            "{\"version\":1,\"type\":\"tool_call\",\"name\":\"<known tool>\",\"arguments\":{...}}. "
            "Never describe an actionable tool call as prose. Tool results arrive as "
            "{version:1,type:tool_result,tool,result}; interpret them as authoritative. "
            "The exact tool argument contract is: " + protocol_contract_summary()
        )
        if work_mode == "ask":
            system += " This is ASK mode: only inspect/read/search; answer the question and do not propose edits or commands."
        elif work_mode == "plan":
            system += " This is PLAN mode: only inspect/read/search; produce a concrete implementation plan with steps, files, risks, and verification. Do not edit files or run commands."
        messages: list[dict[str, Any]] = [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ]
        last_no_tool_result = ""
        no_tool_repeats = 0
        last_tool_signature = ""
        repeated_tool_calls = 0
        protocol_repairs = 0
        steps_without_progress = 0
        completion_claim_repairs = 0
        add_event(task_id, "status", f"Started with {agent.get('name', agent_id)} ({model})")
        for _ in range(max_steps):
            if STATE.cancel_events[task_id].is_set():
                STATE.update_task(task_id, status="cancelled")
                add_event(task_id, "status", "Task cancelled")
                return
            response = ollama_chat(model, cfg, messages, work_mode)
            assistant = response.get("message", {})
            messages.append(assistant)
            calls: list[dict[str, Any]] = []
            validation_errors: list[dict[str, Any]] = []
            native_calls = assistant.get("tool_calls") or []
            if len(native_calls) > 1:
                validation_errors.append({
                    "code": "multiple_tool_calls",
                    "message": "Goal mode accepts exactly one tool call per model turn.",
                })
                native_calls = []
            for item in native_calls:
                normalized, validation_error = normalize_and_validate_tool_call(item)
                if normalized:
                    calls.append(normalized)
                elif validation_error:
                    validation_errors.append(validation_error)
            if not calls:
                envelope = parse_protocol_response(assistant.get("content", ""))
                if envelope and envelope.get("type") == "function":
                    calls = [envelope]
                    messages[-1] = {**assistant, "tool_calls": calls}
                    add_event(task_id, "status", "Accepted a validated protocol-v1 tool call.")
                elif envelope and envelope.get("type") in {"progress", "complete", "blocked"}:
                    assistant["content"] = envelope.get("message", "")
                    messages[-1] = assistant
                    if envelope.get("type") == "blocked":
                        add_event(task_id, "error", assistant["content"])
                        STATE.update_task(task_id, status="incomplete", error=assistant["content"], result=assistant["content"])
                        return
                text_call = extract_text_tool_call(assistant.get("content", ""))
                if not calls and text_call:
                    normalized, validation_error = normalize_and_validate_tool_call(text_call)
                    if normalized:
                        calls = [normalized]
                        messages[-1] = {**assistant, "tool_calls": calls}
                        detail = normalized.get("normalization", {})
                        suffix = " Known cross-model argument aliases were normalized." if detail.get("aliases") or detail.get("ignored") else ""
                        add_event(task_id, "status", "Recovered a JSON tool request emitted as assistant text." + suffix)
                    elif validation_error:
                        validation_errors.append(validation_error)
            if validation_errors and not calls:
                protocol_repairs += 1
                error = validation_errors[0]
                repair = protocol_error_message(error)
                add_event(task_id, "status", f"Repairing invalid model tool request ({protocol_repairs}/{MAX_PROTOCOL_REPAIRS}): {error.get('message', 'invalid protocol')}")
                if protocol_repairs >= MAX_PROTOCOL_REPAIRS:
                    blocker = (
                        "The selected model could not produce a valid Workbench tool request after "
                        f"{MAX_PROTOCOL_REPAIRS} repair attempts. Last protocol error: {repair}"
                    )
                    add_event(task_id, "error", blocker)
                    STATE.update_task(task_id, status="incomplete", error=blocker)
                    return
                messages.append({
                    "role": "user",
                    "content": repair + " Return exactly one corrected protocol-v1 tool_call JSON object using only the required and allowed argument names; do not add prose.",
                })
                continue
            if not calls:
                result = assistant.get("content", "")
                add_event(task_id, "assistant", result)
                if work_mode == "plan":
                    approved, _ = request_approval(task_id, "plan", "Save generated implementation plan", {"reason": "The plan will be saved as a Markdown artifact inside the approved project."})
                    if not approved:
                        STATE.update_task(task_id, status="cancelled", error="Plan artifact save was rejected.", result=result)
                        return
                    relative = save_plan(project, prompt, result)
                    add_event(task_id, "action", f"Saved plan {relative}")
                    STATE.update_task(task_id, status="completed", result=result, planPath=relative)
                    return
                if work_mode == "ask":
                    STATE.update_task(task_id, status="completed", result=result)
                    return
                with STATE.lock:
                    current = STATE.tasks[task_id]
                valid, reason = completion_quality(current, result, prompt)
                if valid:
                    STATE.update_task(task_id, status="completed", result=result)
                    return
                if work_mode == "goal":
                    normalized_result = re.sub(r"\s+", " ", result.strip().lower())
                    completion_claim = bool(COMPLETION_CLAIM_WORDS.search(result or "")) and not re.search(
                        r"(?i)\b(?:blocked|cannot|could not|unable)\b", result or ""
                    )
                    if completion_claim and not has_successful_required_verification(current, prompt):
                        completion_claim_repairs += 1
                        if completion_claim_repairs >= 2:
                            blocker = "The model produced completion prose without executable verification."
                            add_event(task_id, "error", blocker)
                            STATE.update_task(task_id, status="incomplete", error=blocker, result=result)
                            return
                        add_event(task_id, "status", "Completion claim requires executable verification; requesting one repair.")
                        messages.append({
                            "role": "user",
                            "content": (
                                "The model produced completion prose without executable verification. "
                                "Return exactly one structured Workbench tool call for the required "
                                "build/test/inspection, or return a concrete BLOCKED response. Do not "
                                "use echo, Write-Host, or other claim-only commands."
                            ),
                        })
                        continue
                    if normalized_result and normalized_result == last_no_tool_result:
                        no_tool_repeats += 1
                    else:
                        last_no_tool_result = normalized_result
                        no_tool_repeats = 1
                    dependency_blocker = re.search(
                        r"(?:mvn|maven)\s+(?:is not recognized|not installed)|install(?:ing)?\s+(?:apache\s+)?maven",
                        normalized_result,
                    )
                    if dependency_blocker or no_tool_repeats >= 3:
                        blocker = (
                            "The agent could not continue because the required Maven dependency is "
                            "not available and it repeatedly requested installation without invoking "
                            "an approval-gated command. Install Maven (or provide a project wrapper) "
                            "and rerun the Goal task."
                            if dependency_blocker
                            else "The agent repeated the same progress response without invoking a tool; review the blocker and rerun the Goal task."
                        )
                        add_event(task_id, "error", blocker)
                        STATE.update_task(task_id, status="incomplete", error=blocker, result=result)
                        return
                    # A natural-language progress update is not a terminal Goal
                    # result. Feed the quality failure back into the same
                    # conversation so the model must inspect further, request
                    # the next approval, and verify the remaining work.
                    add_event(task_id, "status", "Goal continuation required: " + reason)
                    messages.append({
                        "role": "user",
                        "content": (
                            "This is Goal mode and the task is not complete yet. "
                            f"Completion check: {reason} Continue now: inspect the remaining "
                            "scope. Do not explain or propose the next action in prose. "
                            "Invoke exactly one required structured tool now (read_file, "
                            "search_files, propose_write_file, propose_command, or another "
                            "allowed Workbench tool). For edits, send raw file content "
                            "without Markdown fences; for commands, use propose_command so "
                            "an approval card is created. Verify each change before moving "
                            "on. Only finish after the full request is implemented and "
                            "verified, or report a concrete blocker."
                        ),
                    })
                    continue
                add_event(task_id, "error", reason)
                STATE.update_task(task_id, status="incomplete", error=reason, result=result)
                return
            if assistant.get("content"):
                add_event(task_id, "assistant", assistant["content"])
            protocol_repairs = 0
            for call in calls:
                normalized, validation_error = normalize_and_validate_tool_call(call)
                if not normalized:
                    add_event(task_id, "error", protocol_error_message(validation_error or {"code": "invalid_tool_call"}))
                    continue
                function = normalized["function"]
                name = function["name"]
                arguments = normalized["function"]["arguments"]
                signature_arguments = arguments
                if name == "propose_command":
                    signature_arguments = {**arguments, "command": command_fingerprint(str(arguments.get("command", "")))}
                signature = json.dumps(
                    {"name": name, "arguments": signature_arguments},
                    sort_keys=True,
                    ensure_ascii=False,
                )
                if signature == last_tool_signature:
                    repeated_tool_calls += 1
                else:
                    last_tool_signature = signature
                    repeated_tool_calls = 1
                if repeated_tool_calls >= 3:
                    blocker = "The agent repeated the same tool request three times without advancing the task. Review the proposed change and rerun with a narrower request."
                    add_event(task_id, "error", blocker)
                    STATE.update_task(task_id, status="incomplete", error=blocker)
                    return
                try:
                    output = execute_tool(task_id, project, name, arguments)
                except (OSError, ValueError, TypeError) as exc:
                    output = protocol_error_message({"code": "tool_execution_error", "tool": name, "message": str(exc)})
                    add_event(task_id, "error", f"{name} was not executed: {exc}")
                add_event(task_id, "tool", {"name": name, "result": output[:10_000]})
                messages.append({"role": "tool", "tool_name": name, "content": protocol_tool_result(name, output)})
                made_progress = output.startswith(("Wrote ", "Deleted "))
                if name == "propose_command":
                    try:
                        command_result = json.loads(output)
                        command_text = str(arguments.get("command", ""))
                        made_progress = (
                            isinstance(command_result, dict)
                            and int(command_result.get("exitCode", -1)) == 0
                            and verification_kind(command_text) is not None
                        )
                    except (json.JSONDecodeError, TypeError, ValueError):
                        made_progress = False
                if name in READ_ONLY_TOOL_NAMES:
                    with STATE.lock:
                        has_action = any(event.get("kind") == "action" for event in STATE.tasks[task_id].get("events", []))
                    made_progress = made_progress or has_action
                if made_progress:
                    steps_without_progress = 0
                else:
                    steps_without_progress += 1
                if steps_without_progress >= 50:
                    blocker = (
                        "The agent used 50 consecutive tool calls without a successful change or command. "
                        "The task was stopped to prevent an exploration, rejection, or execution-failure loop."
                    )
                    add_event(task_id, "error", blocker)
                    STATE.update_task(task_id, status="incomplete", error=blocker)
                    return
        result = f"Agent reached the configured {max_steps}-step limit before completing and verifying the request."
        add_event(task_id, "error", result)
        STATE.update_task(task_id, status="failed", error=result)
    except (Exception, urllib.error.URLError) as exc:
        log(f"Task {task_id} failed: {exc}")
        add_event(task_id, "error", str(exc))
        STATE.update_task(task_id, status="failed", error=str(exc))


def start_task(project_id: str, prompt: str, agent_id: str, work_mode: str = "goal") -> dict[str, Any]:
    STATE.project(project_id)
    if not prompt.strip():
        raise ValueError("Task prompt is required")
    if work_mode not in WORK_MODES:
        raise ValueError("Work mode must be Ask, Plan, or Goal")
    task_id = uuid.uuid4().hex
    now = time.time()
    selected_agent = next((a for a in available_agents() if a["id"] == agent_id), None)
    if not selected_agent:
        raise ValueError("Selected agent is not configured or is disabled")
    task = {
        "id": task_id,
        "projectId": project_id,
        "prompt": prompt.strip(),
        "modelRole": selected_agent.get("modelRole", ""),
        "agentId": agent_id,
        "agentName": (selected_agent or {}).get("name", ""),
        "workMode": work_mode,
        "status": "running",
        "events": [],
        "approvals": [],
        "createdAt": now,
        "updatedAt": now,
    }
    with STATE.lock:
        STATE.tasks[task_id] = task
        STATE.cancel_events[task_id] = threading.Event()
        STATE.persist_tasks()
    threading.Thread(target=run_agent_task, args=(task_id,), daemon=True).start()
    return public_task(task)


INDEX_HTML = r"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Developer Workbench</title>
<style>
:root{color-scheme:dark;--bg:#0b0e14;--panel:#131925;--line:#2b3547;--text:#edf3ff;--muted:#99a7bb;--blue:#5b7cff;--green:#1f9d68;--red:#c84d64;--amber:#cf8b36}
*{box-sizing:border-box}body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:var(--bg);color:var(--text)}
header{padding:18px 24px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;align-items:center}
h1,h2,h3{margin:.2em 0}.muted{color:var(--muted)}main{display:grid;grid-template-columns:310px 1fr;min-height:calc(100vh - 76px)}
aside{border-right:1px solid var(--line);padding:18px}.content{padding:22px;max-width:1400px}.panel,.card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:15px;margin-bottom:15px}
input,select,textarea,button{font:inherit;border-radius:7px;border:1px solid #3b4860;background:#0d121c;color:var(--text);padding:9px}
input,select,textarea{width:100%}textarea{min-height:110px}button{cursor:pointer;background:#25314a}button.primary{background:var(--blue)}button.good{background:var(--green)}button.danger{background:var(--red)}button.warn{background:var(--amber)}
.row{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
.project{padding:10px;border:1px solid var(--line);border-radius:8px;margin:8px 0;cursor:pointer}.project.active{border-color:var(--blue);background:#192345}
pre{white-space:pre-wrap;word-break:break-word;background:#090d14;border:1px solid #253047;border-radius:8px;padding:12px;max-height:420px;overflow:auto}
.approval{border-left:4px solid var(--amber)}.approval.high{border-color:var(--red)}.badge{display:inline-block;padding:3px 7px;border-radius:20px;background:#29354b;font-size:12px}
.event{border-top:1px solid var(--line);padding:10px 0}.hidden{display:none}.tabs{display:flex;gap:8px;margin-bottom:15px}.tabs button.active{background:var(--blue)}
@media(max-width:850px){main{grid-template-columns:1fr}aside{border-right:0;border-bottom:1px solid var(--line)}.row{grid-template-columns:1fr}}
</style></head>
<body><header><div><h1>Developer Workbench</h1><div class="muted">Native Windows projects, approvals, patches, commands, and Git</div></div><span id="health" class="badge">Connecting</span></header>
<main><aside><h3>Approved projects</h3><div id="projects"></div>
<div class="panel"><label>Name</label><input id="projectName" placeholder="My project"><label>Windows directory</label><input id="projectPath" placeholder="C:\dev\my-project"><button class="primary" onclick="addProject()">Add project</button></div></aside>
<div class="content"><div class="tabs"><button class="active" onclick="tab('tasks',this)">Tasks</button><button onclick="tab('git',this)">Git</button></div>
<section id="tasks"><div class="panel"><h2>New change task</h2><div class="row"><div><label>Project</label><select id="taskProject"></select></div><div><label>Model role</label><select id="modelRole"><option>coder</option><option>general</option><option>reasoning</option></select></div></div><label>Request</label><textarea id="prompt" placeholder="Inspect the project, implement the requested change, run tests, and report results."></textarea><button class="primary" onclick="createTask()">Start task</button></div>
<div id="tasksList"></div></section>
<section id="git" class="hidden"><div class="panel"><h2>Git workflow</h2><div class="actions"><button onclick="gitRead('status')">Status</button><button onclick="gitRead('diff')">Working diff</button><button onclick="gitRead('diff-staged')">Staged diff</button></div><pre id="gitOutput">Select a project, then inspect status or diff.</pre>
<div class="row"><div><label>New/switch branch</label><input id="branchName" placeholder="feature/my-change"><button onclick="gitAction('branch')">Create/switch</button></div><div><label>Commit message</label><input id="commitMessage" placeholder="Describe the change"><button class="good" onclick="gitAction('commit')">Stage all and commit</button></div></div>
<div class="actions"><button class="danger" onclick="gitAction('push')">Push current branch</button></div></div></section></div></main>
<script>
const TOKEN="__TOKEN__";let data={projects:[],tasks:[]},selected=null;
async function api(path,opt={}){opt.headers={...(opt.headers||{}),'X-Workbench-Token':TOKEN};if(opt.body)opt.headers['Content-Type']='application/json';let r=await fetch(path,opt);let x=await r.json();if(!r.ok)throw Error(x.error||JSON.stringify(x));return x}
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function tab(id,b){document.querySelectorAll('.content section').forEach(x=>x.classList.add('hidden'));document.getElementById(id).classList.remove('hidden');document.querySelectorAll('.tabs button').forEach(x=>x.classList.remove('active'));b.classList.add('active')}
async function refresh(){try{data=await api('/api/state');document.getElementById('health').textContent='Ready';render()}catch(e){document.getElementById('health').textContent=e.message}}
function selectProject(id){selected=id;render()}
function render(){if(!selected&&data.projects.length)selected=data.projects[0].id;document.getElementById('projects').innerHTML=data.projects.map(p=>`<div class="project ${p.id==selected?'active':''}" onclick="selectProject('${p.id}')"><b>${esc(p.name)}</b><div class="muted">${esc(p.path)}</div><button class="danger" onclick="event.stopPropagation();removeProject('${p.id}')">Remove</button></div>`).join('')||'<div class="muted">No projects registered.</div>';document.getElementById('taskProject').innerHTML=data.projects.map(p=>`<option value="${p.id}" ${p.id==selected?'selected':''}>${esc(p.name)}</option>`).join('');let tasks=data.tasks.filter(t=>!selected||t.projectId==selected).sort((a,b)=>b.createdAt-a.createdAt);document.getElementById('tasksList').innerHTML=tasks.map(taskCard).join('')||'<div class="panel muted">No tasks for this project.</div>'}
function taskCard(t){let approvals=(t.approvals||[]).filter(a=>a.status=='pending').map(a=>`<div class="card approval ${a.risk=='high'?'high':''}"><h3>${esc(a.summary)} <span class="badge">${esc(a.risk)} risk</span></h3><div>${esc(a.details.reason||'')}</div>${a.details.command?`<pre>${esc(a.details.command)}</pre>`:''}${a.details.patch?`<pre>${esc(a.details.patch)}</pre>`:''}<div class="actions"><button class="good" onclick="decide('${t.id}','${a.id}','approve')">Approve</button><button class="danger" onclick="decide('${t.id}','${a.id}','reject')">Reject</button></div></div>`).join('');let events=(t.events||[]).map(e=>`<div class="event"><span class="badge">${esc(e.kind)}</span><pre>${esc(typeof e.content=='string'?e.content:JSON.stringify(e.content,null,2))}</pre></div>`).join('');return `<div class="panel"><h2>${esc(t.prompt)}</h2><div><span class="badge">${esc(t.status)}</span> <span class="muted">${esc(t.modelRole)}</span></div>${approvals}<details open><summary>Activity</summary>${events}</details>${['running','waiting_approval'].includes(t.status)?`<button class="danger" onclick="cancelTask('${t.id}')">Cancel</button>`:''}</div>`}
async function addProject(){try{await api('/api/projects',{method:'POST',body:JSON.stringify({name:projectName.value,path:projectPath.value})});projectName.value='';projectPath.value='';await refresh()}catch(e){alert(e.message)}}
async function removeProject(id){if(!confirm('Remove this project from the approved registry? Files will not be deleted.'))return;try{await api('/api/projects/'+id,{method:'DELETE'});if(selected==id)selected=null;await refresh()}catch(e){alert(e.message)}}
async function createTask(){try{let p=document.getElementById('taskProject').value;selected=p;await api('/api/tasks',{method:'POST',body:JSON.stringify({projectId:p,prompt:prompt.value,modelRole:modelRole.value})});prompt.value='';await refresh()}catch(e){alert(e.message)}}
async function decide(t,a,d){try{await api(`/api/tasks/${t}/approvals/${a}`,{method:'POST',body:JSON.stringify({decision:d})});await refresh()}catch(e){alert(e.message)}}
async function cancelTask(id){try{await api('/api/tasks/'+id+'/cancel',{method:'POST'});await refresh()}catch(e){alert(e.message)}}
async function gitRead(kind){if(!selected)return alert('Select a project.');try{gitOutput.textContent=JSON.stringify(await api(`/api/projects/${selected}/git/${kind}`),null,2)}catch(e){gitOutput.textContent=e.message}}
async function gitAction(action){if(!selected)return alert('Select a project.');let value=action=='branch'?branchName.value:action=='commit'?commitMessage.value:'';let warning=action=='push'?'Push the current branch to its configured remote?':`Run Git ${action}?`;if(!confirm(warning))return;try{gitOutput.textContent=JSON.stringify(await api(`/api/projects/${selected}/git/${action}`,{method:'POST',body:JSON.stringify({value})}),null,2);await refresh()}catch(e){gitOutput.textContent=e.message}}
refresh();setInterval(refresh,2000);
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "DSAlgoLocalAIWorkbench/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        log(f"{self.client_address[0]} {fmt % args}")

    def send_json(self, value: Any, status: int = 200) -> None:
        payload = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length > 10_000_000:
            raise ValueError("Request body is too large")
        return json.loads(self.rfile.read(length).decode("utf-8")) if length else {}

    def authorized(self) -> bool:
        host = self.headers.get("Host", "").split(":")[0].lower()
        return host in {"localhost", "127.0.0.1"} and secrets.compare_digest(
            self.headers.get("X-Workbench-Token", ""), STATE.token
        )

    def require_auth(self) -> bool:
        if self.authorized():
            return True
        self.send_json({"error": "Unauthorized local request"}, HTTPStatus.UNAUTHORIZED)
        return False

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path in {"/logo.png", "/favicon.ico"}:
            requested = STATIC_DIR / path.lstrip("/")
            if not requested.is_file():
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            payload = requested.read_bytes()
            content_type = "image/png" if path.endswith(".png") else "image/x-icon"
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store, max-age=0" if path == "/favicon.ico" else "public, max-age=3600")
            self.end_headers()
            self.wfile.write(payload)
            return
        if path.startswith("/assets/"):
            requested = (STATIC_DIR / path.lstrip("/")).resolve()
            if STATIC_DIR.resolve() not in requested.parents or not requested.is_file():
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            payload = requested.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mimetypes.guess_type(requested.name)[0] or "application/octet-stream")
            self.send_header("Content-Length", str(len(payload)))
            # Static bundles are replaced by installer/repair. Avoid serving
            # an older task UI from the browser cache after an upgrade.
            self.send_header("Cache-Control", "no-store, max-age=0")
            self.end_headers()
            self.wfile.write(payload)
            return
        if path == "/":
            host = self.headers.get("Host", "").split(":")[0].lower()
            if host not in {"localhost", "127.0.0.1"}:
                self.send_error(HTTPStatus.FORBIDDEN)
                return
            payload = (STATIC_DIR / "index.html").read_text(encoding="utf-8").replace("__TOKEN__", STATE.token).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
            return
        if path == "/health":
            self.send_json({"status": "ok", "bind": "127.0.0.1", "projects": len(STATE.projects), "runtimePolicy": load_policy()})
            return
        if not self.require_auth():
            return
        try:
            if path == "/api/state":
                with STATE.lock:
                    self.send_json(
                        {
                            "projects": STATE.projects,
                            "tasks": [public_task(t) for t in STATE.tasks.values()],
                            "runtimePolicy": load_policy(),
                            "agents": available_agents(),
                        }
                    )
                return
            match = re.fullmatch(r"/api/projects/([^/]+)/git/(status|diff|diff-staged)", path)
            if match:
                project = STATE.project(unquote(match.group(1)))
                action = match.group(2)
                args = ["status", "--short", "--branch"] if action == "status" else ["diff"]
                if action == "diff-staged":
                    args.append("--cached")
                self.send_json(git(project, args))
                return
            self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
        except Exception as exc:
            self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)

    def do_POST(self) -> None:
        if not self.require_auth():
            return
        path = urlparse(self.path).path
        try:
            data = self.body()
            if path == "/api/projects":
                raw_path = str(data.get("path", "")).strip()
                if not raw_path:
                    raise ValueError("Project path is required")
                requested = Path(raw_path).expanduser()
                if not requested.is_absolute():
                    raise ValueError("Project path must be absolute")
                candidate = requested.resolve()
                if not candidate.is_dir():
                    raise ValueError("Project path must be an existing directory")
                if candidate.parent == candidate:
                    raise ValueError("A filesystem root cannot be registered; choose a specific project directory")
                name = str(data.get("name", "")).strip() or candidate.name
                with STATE.lock:
                    if any(Path(p["path"]).resolve() == candidate for p in STATE.projects):
                        raise ValueError("That project path is already registered")
                    project = {"id": uuid.uuid4().hex, "name": name, "path": str(candidate)}
                    STATE.projects.append(project)
                    STATE.persist_projects()
                self.send_json(project, HTTPStatus.CREATED)
                return
            if path == "/api/tasks":
                self.send_json(
                    start_task(str(data.get("projectId", "")), str(data.get("prompt", "")), str(data.get("agentId", "")).strip(), str(data.get("workMode", "goal")).lower()),
                    HTTPStatus.CREATED,
                )
                return
            match = re.fullmatch(r"/api/tasks/([^/]+)/approvals/([^/]+)", path)
            if match:
                task_id, approval_id = match.groups()
                decision = data.get("decision")
                if decision not in {"approve", "reject"}:
                    raise ValueError("Decision must be approve or reject")
                with STATE.lock:
                    task = STATE.tasks[task_id]
                    approval = next(a for a in task.get("approvals", []) if a["id"] == approval_id)
                    if approval["status"] != "pending":
                        raise ValueError("Approval has already been decided")
                    approval["status"] = "approved" if decision == "approve" else "rejected"
                    approval["decidedAt"] = time.time()
                    STATE.persist_tasks()
                    event = STATE.approval_events.get(approval_id)
                    if event:
                        event.set()
                self.send_json({"ok": True})
                return
            match = re.fullmatch(r"/api/tasks/([^/]+)/cancel", path)
            if match:
                task_id = match.group(1)
                event = STATE.cancel_events.get(task_id)
                if event: event.set()
                with STATE.lock:
                    task = STATE.tasks.get(task_id)
                    if task:
                        for approval in task.get("approvals", []):
                            if approval["status"] == "pending":
                                approval["status"] = "rejected"
                                approval["decidedAt"] = time.time()
                                approval_event = STATE.approval_events.get(approval["id"])
                                if approval_event: approval_event.set()
                        STATE.persist_tasks()
                self.send_json({"ok": True})
                return
            match = re.fullmatch(r"/api/projects/([^/]+)/git/(branch|commit|push)", path)
            if match:
                project = STATE.project(unquote(match.group(1)))
                action = match.group(2)
                value = str(data.get("value", "")).strip()
                if action == "branch":
                    if not re.fullmatch(r"[A-Za-z0-9._/-]+", value):
                        raise ValueError("Invalid branch name")
                    result = git(project, ["switch", "-c", value])
                elif action == "commit":
                    if not value or len(value) > 500:
                        raise ValueError("Commit message is required and must be at most 500 characters")
                    staged = git(project, ["add", "-A"])
                    result = staged if staged["exitCode"] else git(project, ["commit", "-m", value])
                else:
                    if load_policy()["mode"] == "strict-offline":
                        raise ValueError("Git push is blocked by Strict Offline operating mode")
                    result = git(project, ["push"], 600)
                self.send_json(result)
                return
            self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
        except Exception as exc:
            self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)

    def do_PUT(self) -> None:
        if not self.require_auth():
            return
        try:
            if urlparse(self.path).path != "/api/runtime-policy":
                self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
                return
            data = self.body()
            self.send_json(save_policy(str(data.get("mode", "")), data.get("revision")))
        except Exception as exc:
            self.send_json({"error": str(exc)}, HTTPStatus.CONFLICT if "changed" in str(exc) else HTTPStatus.BAD_REQUEST)

    def do_DELETE(self) -> None:
        if not self.require_auth():
            return
        path = urlparse(self.path).path
        match = re.fullmatch(r"/api/projects/([^/]+)", path)
        if not match:
            self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
            return
        project_id = unquote(match.group(1))
        with STATE.lock:
            if any(
                t["projectId"] == project_id and t["status"] in {"running", "waiting_approval"}
                for t in STATE.tasks.values()
            ):
                self.send_json({"error": "Cancel active project tasks before removing it"}, HTTPStatus.CONFLICT)
                return
            before = len(STATE.projects)
            STATE.projects = [p for p in STATE.projects if p["id"] != project_id]
            if len(STATE.projects) == before:
                self.send_json({"error": "Project not found"}, HTTPStatus.NOT_FOUND)
                return
            STATE.persist_projects()
        self.send_json({"ok": True})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=3002)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    log(f"Developer Workbench started on http://127.0.0.1:{args.port}")
    try:
        server.serve_forever()
    finally:
        server.server_close()
        log("Developer Workbench stopped")


if __name__ == "__main__":
    main()
