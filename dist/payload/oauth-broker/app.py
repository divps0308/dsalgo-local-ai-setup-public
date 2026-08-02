"""Native Windows OAuth 2.1 broker for remote Streamable HTTP MCP servers."""

from __future__ import annotations

import argparse
import base64
import ctypes
import hashlib
import json
import os
import re
import secrets
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from ctypes import wintypes
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONFIG_FILE = ROOT / "config" / "agents.json"
POLICY_FILE = ROOT / "config" / "runtime-policy.json"
TOKEN_STORE = ROOT / "config" / "oauth-tokens.dpapi.json"
RUNTIME_DIR = ROOT / "runtime" / "oauth-broker"
BROKER_TOKEN_FILE = RUNTIME_DIR / "token"
LOG_FILE = ROOT / "logs" / "oauth-broker.log"
CALLBACK_PATH = "/oauth/callback"
CLIENT_NAME = "DSAlgo Local AI Setup"
HTTP_TIMEOUT = 30
REFRESH_SKEW_SECONDS = 90

PENDING: dict[str, dict[str, Any]] = {}
PENDING_LOCK = threading.RLock()
STORE_LOCK = threading.RLock()

def runtime_mode() -> str:
    try:
        mode = json.loads(POLICY_FILE.read_text(encoding="utf-8")).get("mode")
        return mode if mode in {"online","restricted-online","strict-offline"} else "online"
    except Exception:
        return "online"

def require_online(action: str) -> None:
    mode = runtime_mode()
    if mode != "online":
        raise RuntimeError(f"{action} is blocked by {mode} operating mode")


class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_ubyte))]


def log(message: str) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    line = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n"
    with LOG_FILE.open("a", encoding="utf-8") as stream:
        stream.write(line)


_DPAPI_ENTROPY = base64.b64decode("QWxpZW53YXJlTG9jYWxBSS9PQXV0aEJyb2tlci92MQ==")


def _blob(data: bytes) -> tuple[DATA_BLOB, Any]:
    buffer = ctypes.create_string_buffer(data)
    return DATA_BLOB(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte))), buffer


def dpapi_protect(data: bytes) -> str:
    if os.name != "nt":
        raise RuntimeError("OAuth token storage requires Windows DPAPI")
    source, source_buffer = _blob(data)
    entropy, entropy_buffer = _blob(_DPAPI_ENTROPY)
    output = DATA_BLOB()
    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    crypt32.CryptProtectData.argtypes = [
        ctypes.POINTER(DATA_BLOB),
        wintypes.LPCWSTR,
        ctypes.POINTER(DATA_BLOB),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(DATA_BLOB),
    ]
    crypt32.CryptProtectData.restype = wintypes.BOOL
    kernel32.LocalFree.argtypes = [ctypes.c_void_p]
    kernel32.LocalFree.restype = ctypes.c_void_p
    if not crypt32.CryptProtectData(
        ctypes.byref(source),
        "DSAlgo Local AI Setup OAuth tokens",
        ctypes.byref(entropy),
        None,
        None,
        0x01,
        ctypes.byref(output),
    ):
        raise ctypes.WinError()
    try:
        protected = ctypes.string_at(output.pbData, output.cbData)
        return base64.b64encode(protected).decode("ascii")
    finally:
        kernel32.LocalFree(output.pbData)
        del source_buffer, entropy_buffer


def dpapi_unprotect(value: str) -> bytes:
    if os.name != "nt":
        raise RuntimeError("OAuth token storage requires Windows DPAPI")
    source, source_buffer = _blob(base64.b64decode(value))
    entropy, entropy_buffer = _blob(_DPAPI_ENTROPY)
    output = DATA_BLOB()
    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    crypt32.CryptUnprotectData.argtypes = [
        ctypes.POINTER(DATA_BLOB),
        ctypes.POINTER(wintypes.LPWSTR),
        ctypes.POINTER(DATA_BLOB),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(DATA_BLOB),
    ]
    crypt32.CryptUnprotectData.restype = wintypes.BOOL
    kernel32.LocalFree.argtypes = [ctypes.c_void_p]
    kernel32.LocalFree.restype = ctypes.c_void_p
    if not crypt32.CryptUnprotectData(
        ctypes.byref(source),
        None,
        ctypes.byref(entropy),
        None,
        None,
        0x01,
        ctypes.byref(output),
    ):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(output.pbData, output.cbData)
    finally:
        kernel32.LocalFree(output.pbData)
        del source_buffer, entropy_buffer


def load_store() -> dict[str, dict[str, Any]]:
    with STORE_LOCK:
        if not TOKEN_STORE.exists():
            return {}
        envelope = json.loads(TOKEN_STORE.read_text(encoding="utf-8-sig"))
        if envelope.get("version") != 1 or not isinstance(envelope.get("protected"), str):
            raise RuntimeError("Unsupported OAuth token store format")
        value = json.loads(dpapi_unprotect(envelope["protected"]).decode("utf-8"))
        return value if isinstance(value, dict) else {}


def save_store(data: dict[str, dict[str, Any]]) -> None:
    with STORE_LOCK:
        TOKEN_STORE.parent.mkdir(parents=True, exist_ok=True)
        envelope = {
            "version": 1,
            "protected": dpapi_protect(json.dumps(data, separators=(",", ":")).encode("utf-8")),
        }
        temporary = TOKEN_STORE.with_suffix(".tmp")
        temporary.write_text(json.dumps(envelope, indent=2), encoding="utf-8")
        temporary.replace(TOKEN_STORE)


def load_config() -> dict[str, Any]:
    try:
        return json.loads(CONFIG_FILE.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise RuntimeError(f"Unable to load {CONFIG_FILE}: {exc}") from exc


def server_config(server_id: str) -> dict[str, Any]:
    for server in load_config().get("mcpServers", []):
        if isinstance(server, dict) and server.get("id") == server_id:
            return server
    raise KeyError(f"MCP server not found: {server_id}")


def oauth_enabled(server: dict[str, Any]) -> bool:
    auth = server.get("authentication") or {}
    return isinstance(auth, dict) and auth.get("type") == "oauth"


def request(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    json_body: dict[str, Any] | None = None,
    form_body: dict[str, Any] | None = None,
    allow_http: bool = False,
) -> tuple[int, dict[str, str], bytes]:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ({"https", "http"} if allow_http else {"https"}):
        raise RuntimeError("OAuth metadata and token endpoints must use HTTPS")
    data = None
    final_headers = {"User-Agent": "DSAlgo-Local-AI-OAuth-Broker/1.0", **(headers or {})}
    if json_body is not None:
        data = json.dumps(json_body).encode("utf-8")
        final_headers["Content-Type"] = "application/json"
    elif form_body is not None:
        data = urllib.parse.urlencode(form_body).encode("ascii")
        final_headers["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=data, headers=final_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as response:
            final_scheme = urllib.parse.urlparse(response.geturl()).scheme
            if final_scheme not in ({"https", "http"} if allow_http else {"https"}):
                raise RuntimeError("OAuth request redirected to a non-HTTPS endpoint")
            return response.status, {k.lower(): v for k, v in response.headers.items()}, response.read()
    except urllib.error.HTTPError as exc:
        final_scheme = urllib.parse.urlparse(exc.geturl()).scheme
        if final_scheme not in ({"https", "http"} if allow_http else {"https"}):
            raise RuntimeError("OAuth request redirected to a non-HTTPS endpoint") from exc
        return exc.code, {k.lower(): v for k, v in exc.headers.items()}, exc.read()


def json_request(url: str, **kwargs: Any) -> tuple[int, dict[str, str], dict[str, Any]]:
    status, headers, body = request(url, **kwargs)
    try:
        value = json.loads(body.decode("utf-8")) if body else {}
    except Exception as exc:
        raise RuntimeError(f"Expected JSON from {url}, received HTTP {status}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected a JSON object from {url}")
    return status, headers, value


def metadata_url(resource_url: str) -> str:
    parsed = urllib.parse.urlparse(resource_url)
    suffix = parsed.path if parsed.path and parsed.path != "/" else ""
    return urllib.parse.urlunparse(
        (parsed.scheme, parsed.netloc, f"/.well-known/oauth-protected-resource{suffix}", "", "", "")
    )


def parse_resource_metadata_header(value: str | None) -> str | None:
    if not value:
        return None
    match = re.search(r'resource_metadata\s*=\s*"([^"]+)"', value, re.IGNORECASE)
    return match.group(1) if match else None


def authorization_metadata_url(issuer: str) -> str:
    parsed = urllib.parse.urlparse(issuer.rstrip("/"))
    if parsed.path:
        path = f"/.well-known/oauth-authorization-server{parsed.path}"
    else:
        path = "/.well-known/oauth-authorization-server"
    return urllib.parse.urlunparse((parsed.scheme, parsed.netloc, path, "", "", ""))


def discover(server: dict[str, Any]) -> dict[str, Any]:
    resource = str(server["url"]).rstrip("/")
    resource_metadata_url = metadata_url(resource)
    probe_body = {
        "jsonrpc": "2.0",
        "id": uuid.uuid4().hex,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": CLIENT_NAME, "version": "1.0"},
        },
    }
    status, headers, _ = request(
        resource,
        method="POST",
        headers={"Accept": "application/json, text/event-stream"},
        json_body=probe_body,
    )
    resource_metadata_url = parse_resource_metadata_header(headers.get("www-authenticate")) or resource_metadata_url
    rm_status, _, resource_metadata = json_request(resource_metadata_url)
    if rm_status != 200:
        raise RuntimeError(f"Protected-resource discovery failed with HTTP {rm_status}")
    advertised_resource = str(resource_metadata.get("resource", "")).rstrip("/")
    if advertised_resource and advertised_resource != resource:
        raise RuntimeError("Protected-resource metadata returned a mismatched resource identifier")
    authorization_servers = resource_metadata.get("authorization_servers") or []
    if not authorization_servers:
        raise RuntimeError("Protected-resource metadata did not advertise an authorization server")
    issuer = str(authorization_servers[0]).rstrip("/")
    am_status, _, authorization_metadata = json_request(authorization_metadata_url(issuer))
    if am_status != 200:
        raise RuntimeError(f"Authorization-server discovery failed with HTTP {am_status}")
    if str(authorization_metadata.get("issuer", "")).rstrip("/") != issuer:
        raise RuntimeError("Authorization-server metadata returned a mismatched issuer")
    if not authorization_metadata.get("authorization_endpoint") or not authorization_metadata.get("token_endpoint"):
        raise RuntimeError("Authorization-server metadata is missing required endpoints")
    return {
        "resource": resource,
        "resourceMetadataUrl": resource_metadata_url,
        "resourceMetadata": resource_metadata,
        "issuer": issuer,
        "authorizationMetadata": authorization_metadata,
        "initialStatus": status,
    }


def register_client(discovery: dict[str, Any], redirect_uri: str, server: dict[str, Any]) -> dict[str, Any]:
    configured = (server.get("authentication") or {}).get("client") or {}
    if configured.get("clientId"):
        return {
            "client_id": configured["clientId"],
            "client_secret": configured.get("clientSecret"),
            "redirect_uris": [redirect_uri],
        }
    endpoint = discovery["authorizationMetadata"].get("registration_endpoint")
    if not endpoint:
        raise RuntimeError(
            "The authorization server does not support dynamic client registration; configure a clientId"
        )
    payload = {
        "client_name": CLIENT_NAME,
        "redirect_uris": [redirect_uri],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "token_endpoint_auth_method": "none",
    }
    status, _, registration = json_request(endpoint, method="POST", json_body=payload)
    if status not in {200, 201} or not registration.get("client_id"):
        raise RuntimeError(
            f"Dynamic client registration failed with HTTP {status}: "
            f"{registration.get('error_description') or registration.get('error') or 'unknown error'}"
        )
    return registration


def begin_authorization(server_id: str, port: int) -> str:
    require_online("OAuth authorization")
    server = server_config(server_id)
    if not oauth_enabled(server):
        raise RuntimeError("This MCP server is not configured for OAuth")
    discovery = discover(server)
    redirect_uri = f"http://127.0.0.1:{port}{CALLBACK_PATH}"
    client = register_client(discovery, redirect_uri, server)
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(48)).decode("ascii").rstrip("=")
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii")).digest()).decode("ascii").rstrip("=")
    state = secrets.token_urlsafe(32)
    auth = server.get("authentication") or {}
    requested_scopes = auth.get("scopes") or discovery["resourceMetadata"].get("scopes_supported") or []
    query: dict[str, str] = {
        "response_type": "code",
        "client_id": str(client["client_id"]),
        "redirect_uri": redirect_uri,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
        "state": state,
        "resource": discovery["resource"],
    }
    if requested_scopes:
        query["scope"] = " ".join(str(scope) for scope in requested_scopes)
    with PENDING_LOCK:
        PENDING[state] = {
            "createdAt": time.time(),
            "serverId": server_id,
            "verifier": verifier,
            "redirectUri": redirect_uri,
            "client": client,
            "discovery": discovery,
        }
        for key, value in list(PENDING.items()):
            if time.time() - float(value.get("createdAt", 0)) > 600:
                PENDING.pop(key, None)
    return f"{discovery['authorizationMetadata']['authorization_endpoint']}?{urllib.parse.urlencode(query)}"


def token_error(status: int, value: dict[str, Any]) -> RuntimeError:
    detail = value.get("error_description") or value.get("error") or "unknown error"
    return RuntimeError(f"OAuth token endpoint returned HTTP {status}: {detail}")


def exchange_code(state: str, code: str) -> str:
    require_online("OAuth token exchange")
    with PENDING_LOCK:
        pending = PENDING.pop(state, None)
    if not pending or time.time() - float(pending["createdAt"]) > 600:
        raise RuntimeError("Authorization state is invalid or expired; start Connect again")
    client = pending["client"]
    discovery = pending["discovery"]
    form = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": pending["redirectUri"],
        "client_id": client["client_id"],
        "code_verifier": pending["verifier"],
        "resource": discovery["resource"],
    }
    if client.get("client_secret"):
        form["client_secret"] = client["client_secret"]
    status, _, token = json_request(
        discovery["authorizationMetadata"]["token_endpoint"], method="POST", form_body=form
    )
    if status != 200 or not token.get("access_token"):
        raise token_error(status, token)
    now = time.time()
    token["obtained_at"] = now
    token["expires_at"] = now + float(token.get("expires_in", 3600))
    store = load_store()
    store[pending["serverId"]] = {
        "token": token,
        "client": client,
        "discovery": discovery,
    }
    save_store(store)
    log(f"OAuth connection established for MCP server {pending['serverId']}")
    return pending["serverId"]


def refresh(server_id: str, record: dict[str, Any]) -> dict[str, Any]:
    require_online("OAuth token refresh")
    token = record.get("token") or {}
    refresh_token = token.get("refresh_token")
    if not refresh_token:
        raise RuntimeError("Access token expired and no refresh token was issued; reconnect the MCP server")
    client = record.get("client") or {}
    discovery = record.get("discovery") or {}
    form = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": client.get("client_id", ""),
        "resource": discovery.get("resource", ""),
    }
    if client.get("client_secret"):
        form["client_secret"] = client["client_secret"]
    status, _, replacement = json_request(
        discovery["authorizationMetadata"]["token_endpoint"], method="POST", form_body=form
    )
    if status != 200 or not replacement.get("access_token"):
        raise token_error(status, replacement)
    if not replacement.get("refresh_token"):
        replacement["refresh_token"] = refresh_token
    now = time.time()
    replacement["obtained_at"] = now
    replacement["expires_at"] = now + float(replacement.get("expires_in", 3600))
    record["token"] = replacement
    store = load_store()
    store[server_id] = record
    save_store(store)
    log(f"OAuth access token refreshed for MCP server {server_id}")
    return record


def access_token(server_id: str) -> dict[str, Any]:
    require_online("OAuth token access")
    server = server_config(server_id)
    if not oauth_enabled(server):
        raise RuntimeError("This MCP server is not configured for OAuth")
    store = load_store()
    record = store.get(server_id)
    if not record:
        raise RuntimeError("OAuth connection is not established")
    token = record.get("token") or {}
    if time.time() >= float(token.get("expires_at", 0)) - REFRESH_SKEW_SECONDS:
        record = refresh(server_id, record)
        token = record["token"]
    return {
        "accessToken": token["access_token"],
        "tokenType": token.get("token_type", "Bearer"),
        "expiresAt": token.get("expires_at"),
    }


def status(server_id: str) -> dict[str, Any]:
    server = server_config(server_id)
    if not oauth_enabled(server):
        return {"serverId": server_id, "authentication": "none", "connected": False}
    record = load_store().get(server_id)
    if not record:
        return {"serverId": server_id, "authentication": "oauth", "connected": False}
    token = record.get("token") or {}
    return {
        "serverId": server_id,
        "authentication": "oauth",
        "connected": bool(token.get("access_token")),
        "expiresAt": token.get("expires_at"),
        "scope": token.get("scope"),
        "refreshable": bool(token.get("refresh_token")),
        "issuer": (record.get("discovery") or {}).get("issuer"),
    }


def disconnect(server_id: str) -> None:
    store = load_store()
    if store.pop(server_id, None) is not None:
        save_store(store)
        log(f"OAuth connection removed for MCP server {server_id}")


def html_page(title: str, message: str, success: bool) -> bytes:
    color = "#1d7a4d" if success else "#8b2635"
    safe_title = title.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    safe_message = message.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return (
        "<!doctype html><meta charset=utf-8><title>"
        + safe_title
        + "</title><body style='font:16px Segoe UI;background:#10131a;color:#edf2f7;padding:40px'>"
        + f"<main style='max-width:720px;margin:auto;border:1px solid {color};border-radius:12px;padding:24px'>"
        + f"<h1>{safe_title}</h1><p>{safe_message}</p><p>You may close this tab and return to Local Agent Studio.</p>"
        + "</main></body>"
    ).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    server_version = "DSAlgoOAuthBroker/1.0"

    @property
    def broker(self) -> "BrokerServer":
        return self.server  # type: ignore[return-value]

    def log_message(self, fmt: str, *args: Any) -> None:
        log(f"{self.client_address[0]} {fmt % args}")

    def send_json(self, value: Any, status_code: int = 200) -> None:
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self) -> bool:
        supplied = self.headers.get("X-OAuth-Broker-Token", "")
        return secrets.compare_digest(supplied, self.broker.broker_token)

    def require_auth(self) -> bool:
        if self.authorized():
            return True
        self.send_json({"error": "Unauthorized"}, HTTPStatus.UNAUTHORIZED)
        return False

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)
        try:
            if path == "/health":
                self.send_json({"status": "ok", "bind": "127.0.0.1", "version": 1, "mode": runtime_mode()})
                return
            if path == "/connect":
                nonce = (query.get("nonce") or [""])[0]
                with PENDING_LOCK:
                    start = self.broker.start_nonces.pop(nonce, None)
                if not start or time.time() - start["createdAt"] > 120:
                    raise RuntimeError("Connect link is invalid or expired")
                location = begin_authorization(start["serverId"], self.broker.server_port)
                self.send_response(HTTPStatus.FOUND)
                self.send_header("Location", location)
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                return
            if path == CALLBACK_PATH:
                error = (query.get("error_description") or query.get("error") or [None])[0]
                if error:
                    raise RuntimeError(f"Authorization was denied: {error}")
                state = (query.get("state") or [""])[0]
                code = (query.get("code") or [""])[0]
                if not state or not code:
                    raise RuntimeError("Authorization callback is missing code or state")
                server_id = exchange_code(state, code)
                body = html_page("MCP OAuth connected", f"{server_id} is now connected.", True)
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            match = re.fullmatch(r"/api/status/([a-z0-9][a-z0-9_-]{1,62})", path)
            if match and self.require_auth():
                self.send_json(status(match.group(1)))
                return
            match = re.fullmatch(r"/api/token/([a-z0-9][a-z0-9_-]{1,62})", path)
            if match and self.require_auth():
                self.send_json(access_token(match.group(1)))
                return
            self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
        except KeyError as exc:
            self.send_json({"error": str(exc)}, HTTPStatus.NOT_FOUND)
        except Exception as exc:
            log(f"GET {path} failed: {exc}")
            if path == CALLBACK_PATH or path == "/connect":
                body = html_page("MCP OAuth failed", str(exc), False)
                self.send_response(HTTPStatus.BAD_REQUEST)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if not self.require_auth():
            return
        try:
            match = re.fullmatch(r"/api/authorize/([a-z0-9][a-z0-9_-]{1,62})", path)
            if match:
                require_online("OAuth authorization")
                server_id = match.group(1)
                server = server_config(server_id)
                if not oauth_enabled(server):
                    raise RuntimeError("This MCP server is not configured for OAuth")
                nonce = secrets.token_urlsafe(32)
                with PENDING_LOCK:
                    self.broker.start_nonces[nonce] = {"serverId": server_id, "createdAt": time.time()}
                self.send_json(
                    {"authorizeUrl": f"http://127.0.0.1:{self.broker.server_port}/connect?nonce={urllib.parse.quote(nonce)}"}
                )
                return
            match = re.fullmatch(r"/api/disconnect/([a-z0-9][a-z0-9_-]{1,62})", path)
            if match:
                disconnect(match.group(1))
                self.send_json({"ok": True})
                return
            self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
        except KeyError as exc:
            self.send_json({"error": str(exc)}, HTTPStatus.NOT_FOUND)
        except Exception as exc:
            log(f"POST {path} failed: {exc}")
            self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)


class BrokerServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], handler: type[BaseHTTPRequestHandler], broker_token: str):
        super().__init__(address, handler)
        self.broker_token = broker_token
        self.start_nonces: dict[str, dict[str, Any]] = {}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=3003)
    args = parser.parse_args()
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    if BROKER_TOKEN_FILE.exists():
        broker_token = BROKER_TOKEN_FILE.read_text(encoding="utf-8").strip()
    else:
        broker_token = secrets.token_urlsafe(48)
        BROKER_TOKEN_FILE.write_text(broker_token, encoding="utf-8")
    server = BrokerServer(("127.0.0.1", args.port), Handler, broker_token)
    log(f"OAuth broker started on http://127.0.0.1:{args.port}")
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        server.server_close()
        log("OAuth broker stopped")


if __name__ == "__main__":
    main()
