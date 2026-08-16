import ast
import base64
import json
import io
import math
import mimetypes
import operator
import os
import re
import shlex
import socket
import subprocess
import time
import uuid
import zipfile
from html import unescape
from xml.etree import ElementTree
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field

APP_VERSION = "5.2.0"
API_KEY = os.getenv("AGENT_API_KEY", "local-agent-key")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://host.docker.internal:11434").rstrip("/")
WORKSPACE = Path(os.getenv("AGENT_WORKSPACE", "/workspace")).resolve()
MAX_STEPS = int(os.getenv("AGENT_MAX_STEPS", "8"))
MODEL_REGISTRY_FILE = Path(os.getenv("MODEL_REGISTRY_FILE", "/config/models.json"))
SECRET_FILE = Path(os.getenv("AGENT_SECRET_FILE", "/runtime/secrets.json"))
OAUTH_BROKER_URL = os.getenv("OAUTH_BROKER_URL", "http://host.docker.internal:3003").rstrip("/")
OAUTH_BROKER_TOKEN_FILE = Path(os.getenv("OAUTH_BROKER_TOKEN_FILE", "/runtime/oauth-broker/token"))
ALLOW_WRITES = os.getenv("AGENT_ALLOW_WRITES", "true").lower() == "true"
COMMAND_TIMEOUT = int(os.getenv("AGENT_COMMAND_TIMEOUT", "120"))
MAX_TOOL_OUTPUT = int(os.getenv("AGENT_MAX_TOOL_OUTPUT", "30000"))
CONFIG_FILE = Path(os.getenv("AGENT_CONFIG_FILE", "/config/agents.json"))
POLICY_FILE = Path(os.getenv("RUNTIME_POLICY_FILE", "/config/runtime-policy.json"))
VALID_MODES = {"online", "restricted-online", "strict-offline"}

def runtime_policy() -> dict[str, Any]:
    default = {"schemaVersion": 1, "mode": "online", "revision": 1, "updatedAt": None}
    try:
        value = json.loads(POLICY_FILE.read_text(encoding="utf-8-sig"))
        if value.get("mode") in VALID_MODES:
            return {**default, **value}
    except Exception:
        pass
    return default

def load_model_registry() -> dict[str, Any]:
    try:
        return json.loads(MODEL_REGISTRY_FILE.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise RuntimeError(f"Unable to load model registry {MODEL_REGISTRY_FILE}: {exc}")


def load_secrets() -> dict[str, str]:
    try:
        if SECRET_FILE.exists():
            value = json.loads(SECRET_FILE.read_text(encoding="utf-8-sig"))
            return {str(k): str(v) for k, v in value.items()}
    except Exception:
        pass
    return {}


def model_for_role(role: str) -> tuple[str, dict[str, Any]]:
    models = load_model_registry().get("models", {})
    if role not in models:
        raise ValueError(f"Unknown model role: {role}")
    cfg = models[role]
    return cfg["ollamaTag"], cfg

def model_for_agent(agent: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    tag = str(agent.get("modelTag", "")).strip()
    if tag:
        registry = load_model_registry().get("models", {})
        for cfg in registry.values():
            if cfg.get("ollamaTag") == tag:
                return tag, cfg
        return tag, {}
    role = agent.get("modelRole", "general")
    return model_for_role(role if role in {"general", "coder", "reasoning"} else "general")


MODEL_NAMES = {
    "agent-general": "Built-in General Agent — registry/general",
    "agent-coder": "Built-in Coding Agent — registry/coder",
    "agent-reasoning": "Built-in Reasoning Agent — registry/reasoning",
    "agent-orchestrator": "Built-in Multi-Agent Orchestrator — planner/executor/reviewer",
}

app = FastAPI(title="DSAlgo Local AI Setup Agent Gateway", version=APP_VERSION)

class ChatRequest(BaseModel):
    model: str
    messages: list[dict[str, Any]]
    stream: bool = False
    temperature: float | None = None
    max_tokens: int | None = None
    user: str | None = None


_IMAGE_MIME_TYPES = {"image/png", "image/jpeg", "image/jpg", "image/webp", "image/gif"}
_MAX_IMAGE_BYTES = 12 * 1024 * 1024
_DOCUMENT_MIME_TYPES = {
    "text/plain": "txt", "text/markdown": "md", "text/csv": "csv",
    "application/pdf": "pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
}
_MAX_DOCUMENT_BYTES = 20 * 1024 * 1024
_MAX_EXTRACTED_DOCUMENT_CHARS = 2_000_000


def _image_data_url(value: str) -> str:
    """Convert a supported data URL into Ollama's base64 image value.

    Remote URLs are intentionally rejected: the gateway must not fetch arbitrary
    user-supplied URLs or bypass Open WebUI's attachment permissions.
    """
    if not isinstance(value, str) or not value.startswith("data:"):
        raise HTTPException(status_code=400, detail="Image attachments must be local data URLs; remote image URLs are not supported.")
    header, separator, encoded = value.partition(",")
    if not separator or ";base64" not in header.lower():
        raise HTTPException(status_code=400, detail="Image attachment is not a valid base64 data URL.")
    mime = header[5:].split(";", 1)[0].lower()
    if mime not in _IMAGE_MIME_TYPES:
        raise HTTPException(status_code=400, detail=f"Unsupported image type {mime}. Use PNG, JPEG, WEBP, or GIF.")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise HTTPException(status_code=400, detail="Image attachment contains invalid base64 data.") from exc
    if not raw:
        raise HTTPException(status_code=400, detail="Image attachment is empty.")
    if len(raw) > _MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image attachment exceeds the 12 MB limit.")
    return base64.b64encode(raw).decode("ascii")


def _data_url_bytes(value: str, kind: str) -> tuple[str, bytes]:
    if not isinstance(value, str) or not value.startswith("data:"):
        raise HTTPException(status_code=400, detail=f"{kind} attachments must be local data URLs; remote URLs are not supported.")
    header, separator, encoded = value.partition(",")
    if not separator or ";base64" not in header.lower():
        raise HTTPException(status_code=400, detail=f"{kind} attachment is not a valid base64 data URL.")
    mime = header[5:].split(";", 1)[0].lower()
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise HTTPException(status_code=400, detail=f"{kind} attachment contains invalid base64 data.") from exc
    if not raw:
        raise HTTPException(status_code=400, detail=f"{kind} attachment is empty.")
    limit = _MAX_IMAGE_BYTES if kind == "Image" else _MAX_DOCUMENT_BYTES
    if len(raw) > limit:
        raise HTTPException(status_code=413, detail=f"{kind} attachment exceeds the {limit // (1024 * 1024)} MB limit.")
    return mime, raw


def _extract_document(mime: str, raw: bytes) -> str:
    kind = _DOCUMENT_MIME_TYPES.get(mime)
    if not kind:
        raise HTTPException(status_code=400, detail=f"Unsupported document type {mime}. Supported types are TXT, Markdown, CSV, PDF, and DOCX.")
    if kind in {"txt", "md", "csv"}:
        text = raw.decode("utf-8", errors="replace")
    elif kind == "docx":
        try:
            with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                xml = archive.read("word/document.xml")
            root = ElementTree.fromstring(xml)
            text = "\n".join(unescape(node.text or "") for node in root.iter() if node.tag.endswith("}t"))
        except (KeyError, OSError, ElementTree.ParseError) as exc:
            raise HTTPException(status_code=400, detail="DOCX attachment is corrupt or missing document content.") from exc
    else:
        try:
            from pypdf import PdfReader
            reader = PdfReader(io.BytesIO(raw))
            text = "\n".join(page.extract_text() or "" for page in reader.pages)
        except ImportError as exc:
            raise HTTPException(status_code=503, detail="PDF extraction is unavailable because the gateway PDF parser is not installed.") from exc
        except Exception as exc:
            raise HTTPException(status_code=400, detail="PDF attachment could not be read.") from exc
    text = text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="Document contains no extractable text.")
    if len(text) > _MAX_EXTRACTED_DOCUMENT_CHARS:
        text = text[:_MAX_EXTRACTED_DOCUMENT_CHARS] + "\n[Document text truncated]"
    return text


def normalize_messages_for_ollama(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Normalize OpenAI text/image blocks to Ollama chat messages.

    Text-only messages are returned with their existing shape. OpenAI image
    blocks become Ollama's ``images`` array while text blocks are joined into a
    normal string. Tool-call fields are preserved unchanged.
    """
    normalized: list[dict[str, Any]] = []
    for message in messages:
        item = dict(message)
        content = item.get("content")
        if not isinstance(content, list):
            normalized.append(item)
            continue
        text_parts: list[str] = []
        images: list[str] = []
        for block in content:
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            if kind == "text":
                text_parts.append(str(block.get("text", "")))
            elif kind == "image_url":
                image_url = block.get("image_url")
                image_url = image_url.get("url") if isinstance(image_url, dict) else image_url
                images.append(_image_data_url(image_url))
            elif kind in {"image", "input_image"}:
                source = block.get("source") or block.get("image") or block.get("data")
                if isinstance(source, dict):
                    source = source.get("data") or source.get("url")
                images.append(_image_data_url(source))
            elif kind in {"file", "input_file", "document"}:
                source = block.get("file_data") or block.get("file_url") or block.get("data") or block.get("source")
                if isinstance(source, dict):
                    source = source.get("url") or source.get("data")
                if isinstance(source, str) and not source.startswith("data:") and not source.startswith("http"):
                    filename = block.get("filename") or block.get("file_name") or "attachment"
                    guessed = mimetypes.guess_type(str(filename))[0] or "application/octet-stream"
                    source = f"data:{guessed};base64,{source}"
                mime, raw = _data_url_bytes(source, "Document")
                text_parts.append("[Attached document]\n" + _extract_document(mime, raw) + "\n[End attached document]")
            else:
                raise HTTPException(status_code=400, detail=f"Unsupported multimodal content block: {kind or 'unknown'}.")
        item["content"] = "\n".join(part for part in text_parts if part).strip()
        if images:
            item["images"] = images
        normalized.append(item)
    return normalized


def check_auth(authorization: str | None) -> None:
    if API_KEY and authorization != f"Bearer {API_KEY}":
        raise HTTPException(status_code=401, detail="Invalid API key")


def safe_path(relative: str = ".") -> Path:
    candidate = (WORKSPACE / relative).resolve()
    if candidate != WORKSPACE and WORKSPACE not in candidate.parents:
        raise ValueError("Path escapes the agent workspace")
    return candidate


def trim(value: Any) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, indent=2)
    return text[:MAX_TOOL_OUTPUT]


def workspace_list(path: str = ".", recursive: bool = False, max_entries: int = 200) -> str:
    target = safe_path(path)
    if not target.exists():
        return f"Not found: {path}"
    if target.is_file():
        return str(target.relative_to(WORKSPACE))
    iterator = target.rglob("*") if recursive else target.iterdir()
    rows = []
    for item in iterator:
        rel = item.relative_to(WORKSPACE)
        rows.append(f"{'DIR ' if item.is_dir() else 'FILE'} {rel}")
        if len(rows) >= max(1, min(max_entries, 1000)):
            rows.append("... output truncated")
            break
    return "\n".join(rows) or "Workspace directory is empty."


def workspace_read(path: str, start_line: int = 1, max_lines: int = 400) -> str:
    target = safe_path(path)
    if not target.is_file():
        return f"Not a file: {path}"
    if target.stat().st_size > 5_000_000:
        return "File is larger than the 5 MB read limit."
    text = target.read_text(encoding="utf-8", errors="replace").splitlines()
    start = max(1, start_line) - 1
    end = start + max(1, min(max_lines, 2000))
    return "\n".join(f"{i+1}: {line}" for i, line in enumerate(text[start:end], start=start))


def workspace_search(query: str, path: str = ".", max_results: int = 100) -> str:
    if not query or len(query) > 500:
        return "Search query is empty or too long."
    base = safe_path(path)
    results = []
    files = [base] if base.is_file() else base.rglob("*")
    pattern = re.compile(re.escape(query), re.IGNORECASE)
    for file in files:
        if not file.is_file() or file.stat().st_size > 2_000_000:
            continue
        try:
            for number, line in enumerate(file.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
                if pattern.search(line):
                    results.append(f"{file.relative_to(WORKSPACE)}:{number}: {line[:500]}")
                    if len(results) >= max(1, min(max_results, 500)):
                        return "\n".join(results)
        except OSError:
            continue
    return "\n".join(results) or "No matches."


def workspace_write(path: str, content: str, overwrite: bool = False) -> str:
    if not ALLOW_WRITES:
        return "Workspace writes are disabled by configuration."
    target = safe_path(path)
    if target.exists() and not overwrite:
        return "File already exists. Set overwrite=true to replace it."
    if len(content.encode("utf-8")) > 2_000_000:
        return "Content exceeds the 2 MB write limit."
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return f"Wrote {len(content)} characters to {target.relative_to(WORKSPACE)}"


def workspace_delete(path: str) -> str:
    if not ALLOW_WRITES:
        return "Workspace writes are disabled by configuration."
    target = safe_path(path)
    if target == WORKSPACE:
        return "Refusing to delete the workspace root."
    if not target.exists():
        return "Path does not exist."
    if target.is_dir():
        return "Directory deletion is intentionally disabled."
    target.unlink()
    return f"Deleted {path}"


_ALLOWED_COMMANDS = {"python", "python3", "pytest", "git", "ls", "find", "grep", "head", "tail", "cat", "wc", "sed"}
_BLOCKED_GIT = {"push", "send-email", "credential", "remote"}

def run_command(command: str, timeout_seconds: int = COMMAND_TIMEOUT) -> str:
    if not ALLOW_WRITES:
        return "Command execution is disabled with workspace writes."
    if any(token in command for token in [";", "&&", "||", "|", ">", "<", "`", "$(`", "\n", "\r"]):
        return "Shell operators and redirection are not allowed. Run one command at a time."
    try:
        args = shlex.split(command, posix=True)
    except ValueError as exc:
        return f"Invalid command: {exc}"
    if not args or args[0] not in _ALLOWED_COMMANDS:
        return f"Executable not allowed. Allowed: {', '.join(sorted(_ALLOWED_COMMANDS))}"
    if args[0] == "git" and len(args) > 1 and args[1] in _BLOCKED_GIT:
        return f"git {args[1]} is blocked."
    timeout_seconds = max(1, min(int(timeout_seconds), 300))
    try:
        result = subprocess.run(
            args,
            cwd=WORKSPACE,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            env={"PATH": os.environ.get("PATH", ""), "HOME": "/tmp", "PYTHONDONTWRITEBYTECODE": "1"},
        )
        return trim({"exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    except subprocess.TimeoutExpired:
        return f"Command timed out after {timeout_seconds} seconds."
    except OSError as exc:
        return f"Command failed: {exc}"


_BINOPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv,
           ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod, ast.Pow: operator.pow}
_UNARY = {ast.UAdd: operator.pos, ast.USub: operator.neg}

def _eval_math(node: ast.AST) -> float:
    if isinstance(node, ast.Expression): return _eval_math(node.body)
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)): return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in _BINOPS: return _BINOPS[type(node.op)](_eval_math(node.left), _eval_math(node.right))
    if isinstance(node, ast.UnaryOp) and type(node.op) in _UNARY: return _UNARY[type(node.op)](_eval_math(node.operand))
    raise ValueError("Unsupported expression")

def calculate(expression: str) -> str:
    if len(expression) > 200: return "Expression is too long."
    try:
        value = _eval_math(ast.parse(expression, mode="eval"))
        if isinstance(value, (int, float)) and (not math.isfinite(value) or abs(value) > 1e100):
            return "Result is outside the allowed range."
        return str(value)
    except Exception as exc:
        return f"Calculation error: {exc}"


def get_datetime() -> str:
    return datetime.now(timezone.utc).isoformat()


def http_get(url: str, max_chars: int = 12000) -> str:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return "Only fully qualified http/https URLs are allowed."
    try:
        infos = socket.getaddrinfo(parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80))
        import ipaddress
        for info in infos:
            ip = ipaddress.ip_address(info[4][0])
            if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
                return "Requests to private, loopback, link-local, or reserved addresses are blocked."
        with httpx.Client(timeout=20, follow_redirects=False) as client:
            response = client.get(url, headers={"User-Agent": "DSAlgo-Local-Agent/2.0"})
            if 300 <= response.status_code < 400:
                return "HTTP redirects are not followed for security. Fetch the final public URL directly."
            response.raise_for_status()
            ctype = response.headers.get("content-type", "")
            if not any(t in ctype for t in ["text/", "application/json", "application/xml", "application/xhtml"]):
                return f"Unsupported content type: {ctype}"
            return response.text[:max(1000, min(int(max_chars), 30000))]
    except Exception as exc:
        return f"HTTP request failed: {exc}"


TOOL_DEFS = {
    "calculate": {"description": "Safely calculate a numeric expression.", "parameters": {"type": "object", "properties": {"expression": {"type": "string"}}, "required": ["expression"]}},
    "get_datetime": {"description": "Get the current UTC date and time.", "parameters": {"type": "object", "properties": {}}},
    "http_get": {"description": "Fetch a public HTTP or HTTPS text/JSON URL. Private network addresses are blocked.", "parameters": {"type": "object", "properties": {"url": {"type": "string"}, "max_chars": {"type": "integer"}}, "required": ["url"]}},
    "workspace_list": {"description": "List files inside the dedicated agent workspace.", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "recursive": {"type": "boolean"}, "max_entries": {"type": "integer"}}}},
    "workspace_read": {"description": "Read a UTF-8 text file from the dedicated workspace.", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "start_line": {"type": "integer"}, "max_lines": {"type": "integer"}}, "required": ["path"]}},
    "workspace_search": {"description": "Search text files in the dedicated workspace.", "parameters": {"type": "object", "properties": {"query": {"type": "string"}, "path": {"type": "string"}, "max_results": {"type": "integer"}}, "required": ["query"]}},
    "workspace_write": {"description": "Create or replace a UTF-8 text file inside the dedicated workspace.", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}, "overwrite": {"type": "boolean"}}, "required": ["path", "content"]}},
    "workspace_delete": {"description": "Delete one file inside the dedicated workspace. Directory deletion is disabled.", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
    "run_command": {"description": "Run one allow-listed command inside the isolated agent container with the workspace as its working directory.", "parameters": {"type": "object", "properties": {"command": {"type": "string"}, "timeout_seconds": {"type": "integer"}}, "required": ["command"]}},
}

TOOL_FUNCS = {
    "calculate": calculate, "get_datetime": get_datetime, "http_get": http_get,
    "workspace_list": workspace_list, "workspace_read": workspace_read, "workspace_search": workspace_search,
    "workspace_write": workspace_write, "workspace_delete": workspace_delete, "run_command": run_command,
}

PROFILE_TOOLS = {
    "agent-general": ["calculate", "get_datetime", "http_get", "workspace_list", "workspace_read", "workspace_search"],
    "agent-coder": ["calculate", "get_datetime", "http_get", "workspace_list", "workspace_read", "workspace_search", "workspace_write", "workspace_delete", "run_command"],
    "agent-reasoning": ["calculate", "get_datetime", "http_get", "workspace_list", "workspace_read", "workspace_search"],
}

SYSTEM_PROMPTS = {
    "agent-general": "You are a local general-purpose agent. Use tools when they improve correctness. Never claim an action succeeded unless a tool result confirms it. Ask before proposing destructive external actions. Your file access is limited to /workspace.",
    "agent-coder": "You are a careful autonomous coding agent. Inspect relevant files before editing, make minimal changes, run available checks, and report exact files changed and test results. Work only inside /workspace. Do not attempt network credentials, host administration, git push, or destructive directory operations.",
    "agent-reasoning": "You are a rigorous reasoning and review agent. Use tools for calculation, evidence, and workspace inspection. Separate assumptions from verified facts. You are read-only with respect to workspace files.",
}


def load_dynamic_config() -> dict[str, Any]:
    default = {"mcpServers": [], "agents": []}
    try:
        if CONFIG_FILE.is_file():
            data = json.loads(CONFIG_FILE.read_text(encoding="utf-8-sig"))
            if isinstance(data, dict):
                return {"mcpServers": data.get("mcpServers", []), "agents": data.get("agents", [])}
    except Exception:
        pass
    return default


def effective_agents() -> dict[str, dict[str, Any]]:
    agents: dict[str, dict[str, Any]] = {}
    for item in load_dynamic_config().get('agents', []):
        if isinstance(item, dict) and item.get('id') and item.get('enabled', True):
            agents[str(item['id'])] = item
    return agents

def mcp_servers() -> dict[str, dict[str, Any]]:
    mode = runtime_policy()["mode"]
    return {
        s.get("id"): s for s in load_dynamic_config().get("mcpServers", [])
        if isinstance(s, dict) and s.get("id") and s.get("enabled", True)
        and (mode == "online" or s.get("offlineCapable") is True)
    }


def _mcp_headers(server: dict[str, Any], session_id: str | None = None) -> dict[str, str]:
    headers = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}
    for k, v in (server.get("headers") or {}).items():
        if isinstance(k, str) and isinstance(v, str): headers[k] = v
    secrets = load_secrets()
    for k, ref in (server.get("secretHeaders") or {}).items():
        if isinstance(k, str) and isinstance(ref, str) and ref in secrets:
            headers[k] = secrets[ref]
    authentication = server.get("authentication") or {}
    if isinstance(authentication, dict) and authentication.get("type") == "oauth":
        if not OAUTH_BROKER_TOKEN_FILE.is_file():
            raise RuntimeError("The native MCP OAuth broker is not running")
        broker_token = OAUTH_BROKER_TOKEN_FILE.read_text(encoding="utf-8-sig").strip()
        server_id = str(server.get("id", ""))
        if not server_id:
            raise RuntimeError("OAuth MCP server is missing its id")
        with httpx.Client(timeout=20) as client:
            response = client.get(
                f"{OAUTH_BROKER_URL}/api/token/{server_id}",
                headers={"X-OAuth-Broker-Token": broker_token},
            )
        if not response.is_success:
            try:
                detail = response.json().get("error", response.text)
            except Exception:
                detail = response.text
            raise RuntimeError(f"OAuth token unavailable for {server_id}: {detail}")
        token = response.json()
        headers["Authorization"] = f"{token.get('tokenType', 'Bearer')} {token['accessToken']}"
    if session_id: headers["Mcp-Session-Id"] = session_id
    return headers


def _decode_mcp_response(response: httpx.Response) -> dict[str, Any]:
    response.raise_for_status()
    ctype = response.headers.get("content-type", "")
    if "text/event-stream" in ctype:
        for line in response.text.splitlines():
            if line.startswith("data:"):
                raw = line[5:].strip()
                if raw and raw != "[DONE]":
                    return json.loads(raw)
        return {}
    return response.json() if response.content else {}


def mcp_request(server: dict[str, Any], method: str, params: dict[str, Any] | None = None, session_id: str | None = None) -> tuple[dict[str, Any], str | None]:
    body = {"jsonrpc": "2.0", "id": uuid.uuid4().hex, "method": method}
    if params is not None: body["params"] = params
    with httpx.Client(timeout=float(server.get("timeoutSeconds", 60)), follow_redirects=True) as client:
        response = client.post(server["url"], headers=_mcp_headers(server, session_id), json=body)
        result = _decode_mcp_response(response)
        return result, response.headers.get("mcp-session-id") or session_id


def mcp_list_tools(server: dict[str, Any]) -> list[dict[str, Any]]:
    session = None
    init, session = mcp_request(server, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "dsalgo-local-agent", "version": APP_VERSION}})
    if init.get("error"): raise RuntimeError(init["error"])
    try:
        with httpx.Client(timeout=15) as client:
            client.post(server["url"], headers=_mcp_headers(server, session), json={"jsonrpc":"2.0","method":"notifications/initialized"})
    except Exception:
        pass
    listed, _ = mcp_request(server, "tools/list", {}, session)
    if listed.get("error"): raise RuntimeError(listed["error"])
    return listed.get("result", {}).get("tools", [])


def mcp_tool_catalog(agent: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, tuple[dict[str, Any], str]]]:
    defs, mapping = [], {}
    servers = mcp_servers()
    for sid in agent.get("mcpServers", []) or []:
        server = servers.get(sid)
        if not server: continue
        try:
            for tool in mcp_list_tools(server):
                original = tool.get("name", "tool")
                safe = re.sub(r"[^a-zA-Z0-9_-]", "_", f"mcp_{sid}_{original}")[:64]
                defs.append({"type":"function","function":{"name":safe,"description":f"[{server.get('name',sid)}] {tool.get('description','')}","parameters":tool.get("inputSchema") or {"type":"object","properties":{}}}})
                mapping[safe] = (server, original)
        except Exception as exc:
            continue
    return defs, mapping


def tools_for_agent(agent: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, tuple[dict[str, Any], str]]]:
    mode = runtime_policy()["mode"]
    blocked = {"http_get", "run_command"} if mode in {"restricted-online", "strict-offline"} else set()
    builtin = [n for n in (agent.get("builtinTools") or []) if n in TOOL_DEFS and n not in blocked]
    defs = [{"type": "function", "function": {"name": name, **TOOL_DEFS[name]}} for name in builtin]
    mcp_defs, mapping = mcp_tool_catalog(agent)
    return defs + mcp_defs, mapping


def invoke_tool(name: str, arguments: Any, allowed: set[str], mcp_mapping: dict[str, tuple[dict[str, Any], str]] | None = None) -> str:
    mode = runtime_policy()["mode"]
    if name == "http_get" and mode != "online":
        return f"Tool blocked by operating mode {mode}: {name}"
    if name == "run_command" and mode in {"restricted-online", "strict-offline"}:
        return f"Tool blocked by operating mode {mode}: {name}"
    if isinstance(arguments, str):
        try: arguments = json.loads(arguments)
        except json.JSONDecodeError: return "Tool arguments were not valid JSON."
    if not isinstance(arguments, dict): arguments = {}
    if mcp_mapping and name in mcp_mapping:
        server, original = mcp_mapping[name]
        try:
            init, session = mcp_request(server, "initialize", {"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"dsalgo-local-agent","version":APP_VERSION}})
            result, _ = mcp_request(server, "tools/call", {"name": original, "arguments": arguments}, session)
            if result.get("error"): return trim(result["error"])
            return trim(result.get("result", {}))
        except Exception as exc: return f"MCP tool execution failed: {exc}"
    if name not in allowed or name not in TOOL_FUNCS:
        return f"Tool not allowed: {name}"
    try:
        return trim(TOOL_FUNCS[name](**arguments))
    except TypeError as exc:
        return f"Invalid tool arguments: {exc}"
    except Exception as exc:
        return f"Tool execution failed: {exc}"

def ollama_chat(model: str, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None, temperature: float | None = None) -> dict[str, Any]:
    model_cfg = next((v for v in load_model_registry().get("models", {}).values() if v.get("ollamaTag") == model), {})
    messages = normalize_messages_for_ollama(messages)
    has_images = any(bool(message.get("images")) for message in messages)
    if has_images and model_cfg.get("vision") is False:
        raise HTTPException(status_code=400, detail=f"Configured model {model} is not marked as vision-capable. Select a vision-capable Ollama model.")
    # Only send tools if the model is explicitly configured to support tool-calling
    tool_capable = bool(model_cfg.get("toolCalling", True))
    effective_tools = tools if (tools and tool_capable) else None
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": False,
        "keep_alive": model_cfg.get("keepAlive", "5m"),
        "options": {"num_ctx": int(model_cfg.get("numCtx", 16384))},
    }
    if temperature is not None: payload["options"]["temperature"] = temperature
    if effective_tools: payload["tools"] = effective_tools
    with httpx.Client(timeout=900) as client:
        try:
            response = client.post(f"{OLLAMA_URL}/api/chat", json=payload)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as exc:
            # Retry without tools if model rejected tool-calling (e.g. "does not support tools")
            if effective_tools and exc.response.status_code in (400, 422):
                payload.pop("tools", None)
                retry = client.post(f"{OLLAMA_URL}/api/chat", json=payload)
                retry.raise_for_status()
                return retry.json()
            raise


def parse_compatibility_tool_calls(content: Any, allowed: set[str]) -> list[dict[str, Any]]:
    """Recover narrowly formatted tool requests emitted as ordinary model text.

    Some Ollama models describe a call in a ``tool_code`` block instead of
    returning Ollama's structured ``tool_calls`` field.  Only an explicit,
    allow-listed function invocation is recovered; arbitrary prose is never
    executed.  This keeps the existing permission and policy checks in
    ``invoke_tool`` as the final security boundary.
    """
    if not isinstance(content, str) or not content.strip():
        return []
    candidates: list[str] = []
    fenced = re.findall(r"```(?:tool_code|tool|python|json)?\s*\n?(.*?)```", content, flags=re.IGNORECASE | re.DOTALL)
    candidates.extend(fenced)
    # Also support models that omit the fence but put the call on its own line.
    candidates.extend(line.strip() for line in content.splitlines() if "(" in line or line.lstrip().startswith("{"))
    recovered: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    for candidate in candidates:
        text = candidate.strip()
        if not text:
            continue
        # JSON tool-call objects are accepted only when they name a known tool.
        values: list[Any] = []
        if text.startswith("{") and text.endswith("}"):
            try:
                values.append(json.loads(text))
            except (TypeError, ValueError):
                try:
                    values.append(ast.literal_eval(text))
                except (SyntaxError, ValueError):
                    pass
        match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)", text, flags=re.DOTALL)
        if match:
            name, raw_args = match.group(1), match.group(2).strip()
            if name not in allowed:
                continue
            try:
                parsed = json.loads(raw_args) if raw_args else {}
            except (TypeError, ValueError):
                try:
                    parsed = ast.literal_eval(raw_args) if raw_args else {}
                except (SyntaxError, ValueError):
                    continue
            if isinstance(parsed, dict):
                values.append({"name": name, "arguments": parsed})
            elif isinstance(parsed, str) and name == "http_get":
                values.append({"name": name, "arguments": {"url": parsed}})
        # Accept keyword arguments and simple Python literals without ever
        # evaluating the expression (AST parsing is deliberately non-executing).
        if not match:
            try:
                expression = ast.parse(text, mode="eval").body
                if isinstance(expression, ast.Call) and isinstance(expression.func, ast.Name):
                    name = expression.func.id
                    if name in allowed and not expression.args:
                        parsed = {item.arg: ast.literal_eval(item.value) for item in expression.keywords if item.arg}
                        values.append({"name": name, "arguments": parsed})
            except (SyntaxError, ValueError, TypeError):
                pass
        for value in values:
            if not isinstance(value, dict):
                continue
            function = value.get("function") if isinstance(value.get("function"), dict) else value
            name = function.get("name") or value.get("name") or value.get("tool")
            args = function.get("arguments", function.get("args", value.get("arguments", {})))
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except (TypeError, ValueError):
                    try:
                        args = ast.literal_eval(args)
                    except (SyntaxError, ValueError):
                        continue
            if name not in allowed or name not in TOOL_DEFS or not isinstance(args, dict):
                continue
            marker = (name, json.dumps(args, sort_keys=True, ensure_ascii=False))
            if marker not in seen:
                seen.add(marker)
                recovered.append({"function": {"name": name, "arguments": args}})
    return recovered


def run_agent(profile: str, incoming: list[dict[str, Any]], extra_system: str = "", temperature: float | None = None) -> tuple[str, list[dict[str, Any]]]:
    agent = effective_agents().get(profile)
    if not agent: raise HTTPException(status_code=404, detail=f"Unknown agent model: {profile}")
    model, model_cfg = model_for_agent(agent)
    defs, mcp_mapping = tools_for_agent(agent)
    allowed = {item["function"]["name"] for item in defs if item.get("function", {}).get("name") in TOOL_DEFS}
    system = agent.get("instructions", "") + ("\n\n" + extra_system if extra_system else "")
    if "http_get" in allowed:
        system += ("\n\nLIVE WEB ACCESS: You have an http_get tool. When the user asks about "
                   "current, external, or internet information, you MUST call http_get "
                   "before answering. Do not claim that you lack internet access unless "
                   "the tool call fails; report the tool error clearly instead.")
    else:
        system += ("\n\nWEB ACCESS: You do not have an internet-fetch tool in this request. "
                   "Do not imply that you performed live web access.")
    messages = [{"role": "system", "content": system}]
    messages.extend({k: v for k, v in m.items() if k in {"role", "content", "name", "tool_calls"}} for m in incoming)
    trace: list[dict[str, Any]] = []
    for step in range(int(agent.get("maxSteps", MAX_STEPS))):
        result = ollama_chat(model, messages, defs, temperature)
        assistant = result.get("message", {})
        messages.append(assistant)
        calls = assistant.get("tool_calls") or []
        if not calls:
            calls = parse_compatibility_tool_calls(assistant.get("content"), allowed)
            if calls:
                # Normalize the recovered request to Ollama's native shape
                # before sending the subsequent role=tool result back.
                messages[-1] = {"role": "assistant", "content": "", "tool_calls": calls}
                trace.append({"step": step + 1, "event": "recovered_text_tool_call", "result": "Recovered an explicit allow-listed tool request emitted as model text."})
        if not calls: return assistant.get("content", ""), trace
        for call in calls:
            fn = call.get("function", {}); name = fn.get("name", ""); args = fn.get("arguments", {})
            output = invoke_tool(name, args, allowed, mcp_mapping)
            trace.append({"step": step + 1, "tool": name, "arguments": args, "result": output[:2000]})
            messages.append({"role": "tool", "tool_name": name, "content": output})
    messages.append({"role": "system", "content": "Tool-step limit reached. Provide the best final response now without calling more tools."})
    final = ollama_chat(model, messages, None, temperature)
    return final.get("message", {}).get("content", ""), trace

def plain_completion(model: str, messages: list[dict[str, Any]], system: str, temperature: float = 0.2) -> str:
    payload = [{"role": "system", "content": system}] + messages
    return ollama_chat(model, payload, None, temperature).get("message", {}).get("content", "")


def run_orchestrator(incoming: list[dict[str, Any]]) -> tuple[str, list[dict[str, Any]]]:
    transcript = json.dumps(incoming, ensure_ascii=False)
    planner_prompt = [{"role": "user", "content": "Create a concise execution plan for this request. Identify required evidence, files, tools, risks, and completion checks. Do not perform the work yet.\n\nREQUEST:\n" + transcript}]
    plan = plain_completion(model_for_role("general")[0], planner_prompt, "You are the planning stage in a planner-executor-reviewer system.")
    execution, trace1 = run_agent("agent-coder", incoming, "A planning agent produced this plan. Follow it when useful, but correct it if evidence contradicts it:\n" + plan)
    review_prompt = [{"role": "user", "content": f"Review the proposed result against the original request. Find correctness gaps, unsupported claims, unsafe actions, missing tests, and incomplete requirements. End with APPROVED only when no material change is needed.\n\nREQUEST:\n{transcript}\n\nPLAN:\n{plan}\n\nRESULT:\n{execution}"}]
    review = plain_completion(model_for_role("reasoning")[0], review_prompt, "You are the independent reviewer stage. Be strict and concise.")
    if re.search(r"\bAPPROVED\b\s*$", review.strip(), re.IGNORECASE):
        final = execution
        trace2: list[dict[str, Any]] = []
    else:
        final, trace2 = run_agent("agent-coder", incoming, "Revise the answer or workspace changes using this plan and independent review. Verify fixes with tools where possible.\n\nPLAN:\n" + plan + "\n\nFIRST RESULT:\n" + execution + "\n\nREVIEW:\n" + review)
    trace = [{"stage": "plan", "content": plan[:4000]}, *trace1, {"stage": "review", "content": review[:4000]}, *trace2]
    return final, trace


def openai_response(model: str, content: str) -> dict[str, Any]:
    return {
        "id": "chatcmpl-" + uuid.uuid4().hex,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }


def sse_response(model: str, content: str):
    completion_id = "chatcmpl-" + uuid.uuid4().hex
    created = int(time.time())
    def generate():
        first = {"id": completion_id, "object": "chat.completion.chunk", "created": created, "model": model, "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]}
        yield "data: " + json.dumps(first) + "\n\n"
        for i in range(0, len(content), 500):
            chunk = {"id": completion_id, "object": "chat.completion.chunk", "created": created, "model": model, "choices": [{"index": 0, "delta": {"content": content[i:i+500]}, "finish_reason": None}]}
            yield "data: " + json.dumps(chunk) + "\n\n"
        last = {"id": completion_id, "object": "chat.completion.chunk", "created": created, "model": model, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
        yield "data: " + json.dumps(last) + "\n\n"
        yield "data: [DONE]\n\n"
    return StreamingResponse(generate(), media_type="text/event-stream")


@app.get("/health")
def health():
    return {"status": "ok", "version": APP_VERSION, "ollama": OLLAMA_URL, "workspace": str(WORKSPACE), "writes": ALLOW_WRITES, "runtimePolicy": runtime_policy()}

@app.get("/v1/models")
def models(authorization: str | None = Header(default=None)):
    check_auth(authorization)
    now = int(time.time())
    return {"object": "list", "data": [{"id": aid, "object": "model", "created": now, "owned_by": "local-agent-gateway", "name": a.get("name", aid)} for aid, a in effective_agents().items()]}

@app.post("/v1/chat/completions")
def chat(request: ChatRequest, authorization: str | None = Header(default=None)):
    check_auth(authorization)
    if request.model == "agent-orchestrator":
        content, _trace = run_orchestrator(request.messages)
    elif request.model in effective_agents():
        content, _trace = run_agent(request.model, request.messages, temperature=request.temperature)
    else:
        raise HTTPException(status_code=404, detail=f"Unknown agent model: {request.model}")
    return sse_response(request.model, content) if request.stream else JSONResponse(openai_response(request.model, content))
