import json, os, re, uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

CONFIG = Path(os.getenv("AGENT_CONFIG_FILE", "/config/agents.json"))
POLICY = Path(os.getenv("RUNTIME_POLICY_FILE", "/config/runtime-policy.json"))
REGISTRY = Path(os.getenv("MODEL_REGISTRY_FILE", "/config/models.json"))
GATEWAY = os.getenv("GATEWAY_URL", "http://local-agent-gateway:8000")
API_KEY = os.getenv("AGENT_API_KEY", "local-agent-key")
OAUTH_BROKER = os.getenv("OAUTH_BROKER_URL", "http://host.docker.internal:3003").rstrip("/")
OAUTH_BROKER_TOKEN_FILE = Path(os.getenv("OAUTH_BROKER_TOKEN_FILE", "/runtime/oauth-broker/token"))
app = FastAPI(title="Local Agent Studio", version="5.2.0")
STATIC_DIR = Path(__file__).resolve().parent / "static"
app.mount("/assets", StaticFiles(directory=STATIC_DIR / "assets"), name="assets")

DEFAULT = {"mcpServers": [], "agents": []}
BUILTIN_TOOLS = ["calculate","get_datetime","http_get","workspace_list","workspace_read","workspace_search","workspace_write","workspace_delete","run_command"]
MODEL_ROLES = ["general","coder","reasoning"]
VALID_MODES = {"online","restricted-online","strict-offline"}

def load_policy():
    default={"schemaVersion":1,"mode":"online","revision":1,"updatedAt":None}
    try:
        value=json.loads(POLICY.read_text(encoding="utf-8"))
        return {**default,**value} if value.get("mode") in VALID_MODES else default
    except Exception: return default

def save_policy(mode, revision=None):
    current=load_policy()
    if mode not in VALID_MODES: raise HTTPException(400,"Unsupported operating mode")
    if revision is not None and revision != current["revision"]: raise HTTPException(409,"Operating mode changed; refresh and retry")
    value={"schemaVersion":1,"mode":mode,"revision":current["revision"]+1,"updatedAt":datetime.now(timezone.utc).isoformat()}
    tmp=POLICY.with_name(f"{POLICY.name}.{uuid.uuid4().hex}.tmp");tmp.write_text(json.dumps(value,indent=2),encoding="utf-8");tmp.replace(POLICY);return value

def load():
    try: return json.loads(CONFIG.read_text(encoding="utf-8"))
    except Exception: return DEFAULT.copy()

def save(data):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    tmp=CONFIG.with_suffix('.tmp'); tmp.write_text(json.dumps(data, indent=2), encoding='utf-8'); tmp.replace(CONFIG)

def valid_id(value):
    return bool(re.fullmatch(r"[a-z0-9][a-z0-9_-]{1,62}", value or ""))

def broker_request(method: str, path: str):
    if not OAUTH_BROKER_TOKEN_FILE.is_file():
        raise HTTPException(503, "The native MCP OAuth broker is not running")
    token=OAUTH_BROKER_TOKEN_FILE.read_text(encoding="utf-8").strip()
    try:
        r=httpx.request(method,f"{OAUTH_BROKER}{path}",headers={"X-OAuth-Broker-Token":token},timeout=40)
        value=r.json()
    except Exception as exc:
        raise HTTPException(502,f"OAuth broker unavailable: {exc}") from exc
    if not r.is_success:
        raise HTTPException(r.status_code,value.get("error","OAuth broker request failed"))
    return value

class Payload(BaseModel):
    data: dict[str, Any]
class PolicyPayload(BaseModel):
    mode: str
    revision: int | None = None

@app.get("/", response_class=FileResponse)
def home(): return FileResponse(STATIC_DIR / "index.html", headers={"Cache-Control": "no-store"})
@app.get("/logo.png", response_class=FileResponse)
def logo(): return FileResponse(STATIC_DIR / "logo.png", media_type="image/png", headers={"Cache-Control":"public, max-age=3600"})
@app.get("/favicon.ico", response_class=FileResponse)
def favicon(): return FileResponse(STATIC_DIR / "favicon.ico", media_type="image/x-icon", headers={"Cache-Control":"no-store, max-age=0"})
@app.get("/api/config")
def get_config(): return {**load(), "builtinTools": BUILTIN_TOOLS, "models": MODEL_ROLES}
@app.put("/api/config")
def put_config(payload: Payload):
    data=payload.data; ids=set()
    for s in data.get('mcpServers',[]):
        if not valid_id(s.get('id')): raise HTTPException(400, f"Invalid MCP id: {s.get('id')}")
        if s['id'] in ids: raise HTTPException(400, f"Duplicate id: {s['id']}")
        ids.add(s['id'])
        if not str(s.get('url','')).startswith(('http://','https://')): raise HTTPException(400, f"Invalid MCP URL for {s['id']}")
        authentication=s.get('authentication') or {"type":"none"}
        if authentication.get('type') not in {"none","oauth"}: raise HTTPException(400,f"Unsupported authentication type for {s['id']}")
        if authentication.get('client',{}).get('clientSecret'): raise HTTPException(400,f"Do not store an OAuth client secret in agent configuration for {s['id']}")
    aids=set()
    for a in data.get('agents',[]):
        if not valid_id(a.get('id')): raise HTTPException(400, f"Invalid agent id: {a.get('id')}")
        if a['id'] in aids: raise HTTPException(400, f"Duplicate agent id: {a['id']}")
        aids.add(a['id'])
        if a.get('modelRole') not in MODEL_ROLES: raise HTTPException(400, f"Unsupported model role for {a['id']}")
        source=a.get("source","user"); prefix="my-custom-" if source=="user" else "my-"
        if source not in {"setup","user"} or not a["id"].startswith(prefix): raise HTTPException(400,f"Agent id must start with {prefix}")
        name_prefix="My Custom — " if source=="user" else "My "
        if not str(a.get("name","")).startswith(name_prefix): raise HTTPException(400,f"Agent name must start with {name_prefix}")
    save({"mcpServers":data.get('mcpServers',[]),"agents":data.get('agents',[])})
    return {"ok":True}
@app.post("/api/mcp/test/{server_id}")
def test_mcp(server_id: str):
    server=next((x for x in load().get('mcpServers',[]) if x.get('id')==server_id),None)
    if not server: raise HTTPException(404,'Server not found')
    if load_policy()["mode"]!="online" and server.get("offlineCapable") is not True: raise HTTPException(409,"External MCP testing is blocked by the operating mode")
    headers={"Accept":"application/json, text/event-stream","Content-Type":"application/json",**(server.get('headers') or {})}
    if (server.get("authentication") or {}).get("type")=="oauth":
        token=broker_request("GET",f"/api/token/{server_id}")
        headers["Authorization"]=f"{token.get('tokenType','Bearer')} {token['accessToken']}"
    body={"jsonrpc":"2.0","id":uuid.uuid4().hex,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"local-agent-studio","version":"1.0"}}}
    try:
        r=httpx.post(server['url'],headers=headers,json=body,timeout=float(server.get('timeoutSeconds',60)),follow_redirects=True)
        return {"ok":r.is_success,"status":r.status_code,"contentType":r.headers.get('content-type'),"preview":r.text[:1500]}
    except Exception as e: return {"ok":False,"error":str(e)}
@app.get("/api/mcp/oauth/{server_id}/status")
def oauth_status(server_id: str): return broker_request("GET",f"/api/status/{server_id}")
@app.post("/api/mcp/oauth/{server_id}/authorize")
def oauth_authorize(server_id: str):
    if load_policy()["mode"]!="online": raise HTTPException(409,"OAuth authorization is available only in Online mode")
    return broker_request("POST",f"/api/authorize/{server_id}")
@app.post("/api/mcp/oauth/{server_id}/disconnect")
def oauth_disconnect(server_id: str): return broker_request("POST",f"/api/disconnect/{server_id}")
@app.get("/api/gateway/models")
def gateway_models():
    try:
        r=httpx.get(f"{GATEWAY}/v1/models",headers={"Authorization":f"Bearer {API_KEY}"},timeout=10); r.raise_for_status(); return r.json()
    except Exception as e: return {"error":str(e)}
@app.get("/health")
def health(): return {"status":"ok","config":str(CONFIG),"runtimePolicy":load_policy()}
@app.get("/api/runtime-policy")
def get_runtime_policy(): return load_policy()
@app.put("/api/runtime-policy")
def put_runtime_policy(payload: PolicyPayload): return save_policy(payload.mode,payload.revision)

HTML=r'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Local Agent Studio</title><style>
body{font-family:Segoe UI,Arial;background:#10131a;color:#edf2f7;margin:0}.wrap{max-width:1200px;margin:auto;padding:24px}h1{margin:0 0 6px}.muted{color:#9aa7b4}.tabs{display:flex;gap:8px;margin:22px 0}.tab,button{background:#273142;color:white;border:1px solid #445066;border-radius:8px;padding:9px 13px;cursor:pointer}.tab.active{background:#4865ff}.panel{background:#171c25;border:1px solid #30394a;border-radius:12px;padding:18px;margin-bottom:16px}.row{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.full{grid-column:1/-1}label{display:block;font-size:13px;color:#aab5c4;margin-bottom:5px}input,select,textarea{width:100%;box-sizing:border-box;background:#0e1218;color:white;border:1px solid #3b4658;border-radius:7px;padding:9px}textarea{min-height:120px}.card{border:1px solid #354054;border-radius:10px;padding:14px;margin:12px 0}.actions{display:flex;gap:8px;flex-wrap:wrap}.danger{background:#8b2635}.good{background:#1d7a4d}.status{white-space:pre-wrap;background:#0b0e13;padding:10px;border-radius:7px;max-height:220px;overflow:auto}.checks{display:flex;flex-wrap:wrap;gap:10px}.checks label{background:#202838;padding:8px;border-radius:7px;color:white}.hidden{display:none}@media(max-width:700px){.row{grid-template-columns:1fr}}
</style></head><body><div class="wrap"><h1>Local Agent Studio</h1><div class="muted">Manage custom agents and Streamable HTTP MCP servers used by the local gateway.</div><div class="tabs"><button class="tab active" onclick="show('agents',this)">Agents</button><button class="tab" onclick="show('mcp',this)">MCP Servers</button><button class="tab" onclick="show('status',this)">Status</button></div>
<section id="agents"><div class="actions"><button onclick="addAgent()">Add Agent</button><button class="good" onclick="saveAll()">Save All</button></div><div id="agentList"></div></section>
<section id="mcp" class="hidden"><div class="actions"><button onclick="addMcp()">Add MCP Server</button><button class="good" onclick="saveAll()">Save All</button></div><div id="mcpList"></div></section>
<section id="status" class="hidden"><div class="panel"><button onclick="loadStatus()">Refresh Gateway Models</button><pre id="statusBox" class="status"></pre></div></section></div>
<script>
let cfg={mcpServers:[],agents:[],builtinTools:[],models:[]};
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function show(id,b){document.querySelectorAll('section').forEach(x=>x.classList.add('hidden'));document.getElementById(id).classList.remove('hidden');document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));b.classList.add('active')}
async function load(){cfg=await (await fetch('/api/config')).json();render()}
function render(){document.getElementById('agentList').innerHTML=cfg.agents.map((a,i)=>agentCard(a,i)).join('')||'<div class="panel muted">No custom agents yet. Built-in agents remain available.</div>';document.getElementById('mcpList').innerHTML=cfg.mcpServers.map((s,i)=>mcpCard(s,i)).join('')||'<div class="panel muted">No MCP servers configured.</div>'}
function agentCard(a,i){return `<div class="card"><div class="row"><div><label>Agent ID</label><input value="${esc(a.id)}" onchange="cfg.agents[${i}].id=this.value"></div><div><label>Display name</label><input value="${esc(a.name)}" onchange="cfg.agents[${i}].name=this.value"></div><div><label>Model</label><select onchange="cfg.agents[${i}].modelRole=this.value">${cfg.models.map(m=>`<option ${m==a.modelRole?'selected':''}>${esc(m)}</option>`).join('')}</select></div><div><label>Maximum tool steps</label><input type="number" min="1" max="20" value="${a.maxSteps||8}" onchange="cfg.agents[${i}].maxSteps=+this.value"></div><div class="full"><label>Agent instructions</label><textarea onchange="cfg.agents[${i}].instructions=this.value">${esc(a.instructions)}</textarea></div><div class="full"><label>Built-in tools</label><div class="checks">${cfg.builtinTools.map(t=>`<label><input type="checkbox" ${(a.builtinTools||[]).includes(t)?'checked':''} onchange="toggleArr(cfg.agents[${i}],'builtinTools','${t}',this.checked)"> ${t}</label>`).join('')}</div></div><div class="full"><label>MCP servers</label><div class="checks">${cfg.mcpServers.map(s=>`<label><input type="checkbox" ${(a.mcpServers||[]).includes(s.id)?'checked':''} onchange="toggleArr(cfg.agents[${i}],'mcpServers','${s.id}',this.checked)"> ${esc(s.name||s.id)}</label>`).join('')||'<span class="muted">Add an MCP server first.</span>'}</div></div><div><label><input type="checkbox" ${a.enabled!==false?'checked':''} onchange="cfg.agents[${i}].enabled=this.checked"> Enabled</label></div><div class="actions"><button class="danger" onclick="cfg.agents.splice(${i},1);render()">Delete</button></div></div></div>`}
function mcpCard(s,i){let auth=(s.authentication||{}).type||'none';return `<div class="card"><div class="row"><div><label>Server ID</label><input value="${esc(s.id)}" onchange="cfg.mcpServers[${i}].id=this.value"></div><div><label>Name</label><input value="${esc(s.name)}" onchange="cfg.mcpServers[${i}].name=this.value"></div><div class="full"><label>Streamable HTTP URL</label><input value="${esc(s.url)}" onchange="cfg.mcpServers[${i}].url=this.value"></div><div><label>Timeout seconds</label><input type="number" value="${s.timeoutSeconds||60}" onchange="cfg.mcpServers[${i}].timeoutSeconds=+this.value"></div><div><label><input type="checkbox" ${s.enabled!==false?'checked':''} onchange="cfg.mcpServers[${i}].enabled=this.checked"> Enabled</label></div><div><label>Authentication</label><select onchange="setAuth(${i},this.value)"><option value="none" ${auth=='none'?'selected':''}>None / static headers</option><option value="oauth" ${auth=='oauth'?'selected':''}>OAuth 2.1</option></select></div><div><label>OAuth scopes (space separated; normally blank for discovery)</label><input value="${esc(((s.authentication||{}).scopes||[]).join(' '))}" ${auth!='oauth'?'disabled':''} onchange="setScopes(${i},this.value)"></div><div class="full"><label>HTTP headers (non-secret JSON)</label><textarea onchange="setHeaders(${i},this.value)">${esc(JSON.stringify(s.headers||{},null,2))}</textarea></div><div class="actions"><button onclick="testMcp(${i})">Test Connection</button>${auth=='oauth'?`<button class="good" onclick="connectOAuth(${i})">Connect OAuth</button><button onclick="oauthStatus(${i})">OAuth Status</button><button class="danger" onclick="disconnectOAuth(${i})">Disconnect OAuth</button>`:''}<button class="danger" onclick="cfg.mcpServers.splice(${i},1);render()">Delete</button></div><pre id="mcpStatus${i}" class="status full"></pre></div></div>`}
function toggleArr(o,k,v,on){o[k]=o[k]||[];if(on&&!o[k].includes(v))o[k].push(v);if(!on)o[k]=o[k].filter(x=>x!==v)}
function setHeaders(i,v){try{cfg.mcpServers[i].headers=JSON.parse(v)}catch(e){}}
function setAuth(i,v){cfg.mcpServers[i].authentication={...(cfg.mcpServers[i].authentication||{}),type:v,scopes:(cfg.mcpServers[i].authentication||{}).scopes||[]};render()}
function setScopes(i,v){cfg.mcpServers[i].authentication=cfg.mcpServers[i].authentication||{type:'oauth'};cfg.mcpServers[i].authentication.scopes=v.split(/\s+/).filter(Boolean)}
function addAgent(){cfg.agents.push({id:'custom-agent-'+(cfg.agents.length+1),name:'Custom Agent',modelRole:'coder',instructions:'You are a careful local agent. Use tools only when needed and report verified results.',builtinTools:['calculate','workspace_list','workspace_read','workspace_search'],mcpServers:[],maxSteps:8,enabled:true});render()}
function addMcp(){cfg.mcpServers.push({id:'mcp-'+(cfg.mcpServers.length+1),name:'New MCP Server',url:'https://',headers:{},authentication:{type:'none',scopes:[]},timeoutSeconds:60,enabled:true});render()}
async function saveAll(){let r=await fetch('/api/config',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{mcpServers:cfg.mcpServers,agents:cfg.agents}})});let x=await r.json();alert(r.ok?'Saved. The gateway reloads this configuration automatically.':JSON.stringify(x))}
async function testMcp(i){await saveAll();let b=document.getElementById('mcpStatus'+i);b.textContent='Testing...';let x=await (await fetch('/api/mcp/test/'+encodeURIComponent(cfg.mcpServers[i].id),{method:'POST'})).json();b.textContent=JSON.stringify(x,null,2)}
async function connectOAuth(i){await saveAll();let b=document.getElementById('mcpStatus'+i);b.textContent='Preparing OAuth discovery...';let r=await fetch('/api/mcp/oauth/'+encodeURIComponent(cfg.mcpServers[i].id)+'/authorize',{method:'POST'});let x=await r.json();if(!r.ok){b.textContent=JSON.stringify(x,null,2);return}window.open(x.authorizeUrl,'_blank','noopener');b.textContent='Complete authorization in the new browser tab, then select OAuth Status.'}
async function oauthStatus(i){let b=document.getElementById('mcpStatus'+i);let r=await fetch('/api/mcp/oauth/'+encodeURIComponent(cfg.mcpServers[i].id)+'/status');b.textContent=JSON.stringify(await r.json(),null,2)}
async function disconnectOAuth(i){if(!confirm('Remove locally stored OAuth tokens for this MCP server?'))return;let b=document.getElementById('mcpStatus'+i);let r=await fetch('/api/mcp/oauth/'+encodeURIComponent(cfg.mcpServers[i].id)+'/disconnect',{method:'POST'});b.textContent=JSON.stringify(await r.json(),null,2)}
async function loadStatus(){let x=await (await fetch('/api/gateway/models')).json();document.getElementById('statusBox').textContent=JSON.stringify(x,null,2)}
load();
</script></body></html>'''
