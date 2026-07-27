<script lang="ts">
  import { Activity, Bot, Check, Copy, KeyRound, Link2, Plus, RefreshCw, Save, Server, ShieldAlert, Trash2, Unplug } from "lucide-svelte";
  import AppShell from "../../../shared/AppShell.svelte";
  import ConfirmDialog from "../../../shared/ConfirmDialog.svelte";
  import HelpDrawer from "../../../shared/HelpDrawer.svelte";
  import ToastStack from "../../../shared/ToastStack.svelte";
  import Tooltip from "../../../shared/Tooltip.svelte";
  import type { OperatingMode, ToastMessage } from "../../../shared/types";
  import { studioHelp } from "./help";

  type Agent = { id:string; name:string; source:"setup"|"user"; role:string; modelTag:string; modelRole?:string; maxSteps:number; instructions:string; enabled:boolean; builtinTools:string[]; mcpServers:string[] };
  type Mcp = { id:string; name:string; url:string; timeoutSeconds:number; enabled:boolean; offlineCapable?:boolean; headers:Record<string,string>; authentication?:{type:string;scopes?:string[]} };
  const toolInfo:Record<string,{group:string;description:string;risky?:boolean}> = {
    calculate:{group:"Utilities",description:"Evaluate supported arithmetic."},
    get_datetime:{group:"Utilities",description:"Read the current date and time."},
    http_get:{group:"Web",description:"Fetch content from an allowed HTTP URL."},
    workspace_list:{group:"Workspace read",description:"List files in the approved workspace."},
    workspace_read:{group:"Workspace read",description:"Read files in the approved workspace."},
    workspace_search:{group:"Workspace read",description:"Search content in approved workspace files."},
    workspace_write:{group:"Workspace write",description:"Create or modify approved workspace files.",risky:true},
    workspace_delete:{group:"Workspace write",description:"Delete approved workspace files. Enable only when required.",risky:true},
    run_command:{group:"Execution",description:"Run allow-listed local commands in the approved context.",risky:true}
  };
  let active = $state("agents"), collapsed = $state(localStorage.getItem("studio-sidebar-collapsed")==="true");
  let helpOpen = $state(false), loading = $state(true), saving = $state(false), dirty = $state(false);
  let agents = $state<Agent[]>([]), mcps = $state<Mcp[]>([]), tools = $state<string[]>([]), models = $state<{tag:string;role:string}[]>([]), modelRoles = $state<string[]>(["General Conversation (Chat)","Reasoning","Coding","Deep Research","All"]);
  let selectedAgent = $state(""), selectedMcp = $state(""), diagnostics = $state<Record<string,string>>({});
  let oauth = $state<Record<string,any>>({}), gatewayHealthy = $state<boolean|null>(null);
  let toasts = $state<ToastMessage[]>([]), confirmOpen = $state(false), confirmKind = $state<"agent"|"mcp"|null>(null);
  let policy=$state<{mode:OperatingMode;revision:number}>({mode:"online",revision:1});
  const nav = [
    {id:"agents",label:"Agents",description:"Configure agents, model roles, instructions, and permissions.",icon:Bot},
    {id:"mcp",label:"MCP Servers",description:"Connect trusted external tool and data servers.",icon:Server},
    {id:"status",label:"Status",description:"Inspect gateway, agent, and MCP health.",icon:Activity}
  ];
  let agent = $derived(agents.find(a=>a.id===selectedAgent));
  let mcp = $derived(mcps.find(s=>s.id===selectedMcp));
  let risky = $derived(agent?.builtinTools.some(t=>toolInfo[t]?.risky) ?? false);
  let groups = $derived([...new Set(tools.map(t=>toolInfo[t]?.group ?? "Other"))]);

  $effect(()=>localStorage.setItem("studio-sidebar-collapsed",String(collapsed)));
  $effect(()=>{ void load();const timer=setInterval(async()=>{try{policy=await json("/api/runtime-policy")}catch{}},2000);return()=>clearInterval(timer); });
  function toast(title:string,message="",tone:ToastMessage["tone"]="info"){const id=Date.now()+Math.random();toasts=[...toasts,{id,title,message,tone}];setTimeout(()=>toasts=toasts.filter(t=>t.id!==id),4500)}
  function changed(){dirty=true;agents=[...agents];mcps=[...mcps];}
  async function json(url:string, init?:RequestInit){
    const response=await fetch(url,{...init,headers:{"Content-Type":"application/json",...(init?.headers||{})}});
    const data=await response.json().catch(()=>({}));
    if(!response.ok) throw new Error(data.detail||data.error||`Request failed (${response.status})`);
    return data;
  }
  async function load(){
    try{
      const [data,currentPolicy]=await Promise.all([json("/api/config"),json("/api/runtime-policy")]);policy=currentPolicy;
      agents=(data.config?.agents??data.agents??[]).map((a:any)=>({...a,role:a.role??(a.modelRole==="coder"?"Coding":a.modelRole==="reasoning"?"Reasoning":"General Conversation (Chat)"),modelTag:a.modelTag??""})); mcps=data.config?.mcpServers??data.mcpServers??[]; tools=data.builtinTools??Object.keys(toolInfo);
      models=(data.models??[]).filter((m:any)=>m?.tag);
      modelRoles=data.modelRoles??modelRoles;
      selectedAgent ||= agents[0]?.id??""; selectedMcp ||= mcps[0]?.id??"";
      try{await json("/health");gatewayHealthy=true}catch{gatewayHealthy=false}
      await Promise.all(mcps.map(async s=>{try{oauth[s.id]=await json(`/api/mcp/oauth/${encodeURIComponent(s.id)}/status`)}catch{oauth[s.id]={connected:false}}}));
      oauth={...oauth};
    }catch(e){toast("Unable to load configuration",(e as Error).message,"danger")}
    finally{loading=false}
  }
  async function save(){
    saving=true;
    try{await json("/api/config",{method:"PUT",body:JSON.stringify({data:{agents,mcpServers:mcps}})});dirty=false;toast("Configuration saved","The gateway will reload the updated agents and MCP assignments.","success")}
    catch(e){toast("Save failed",(e as Error).message,"danger")}finally{saving=false}
  }
  function newAgent(){
    let number=agents.filter(a=>a.source==="user").length+1;let id=`my-custom-agent-${number}`;while(agents.some(a=>a.id===id)){number++;id=`my-custom-agent-${number}`}
    agents=[...agents,{id,name:`My Custom — Agent ${number}`,source:"user",role:modelRoles[0],modelTag:models[0]?.tag??"",maxSteps:6,instructions:"",enabled:false,builtinTools:["calculate","get_datetime"],mcpServers:[]}];
    selectedAgent=id;active="agents";dirty=true;
  }
  function newMcp(){
    const id=`mcp-${mcps.length+1}`;
    mcps=[...mcps,{id,name:"New MCP server",url:"",timeoutSeconds:60,enabled:false,offlineCapable:false,headers:{},authentication:{type:"none",scopes:[]}}];
    selectedMcp=id;active="mcp";dirty=true;
  }
  function askDelete(kind:"agent"|"mcp"){confirmKind=kind;confirmOpen=true}
  function removeSelected(){
    if(confirmKind==="agent"){agents=agents.filter(a=>a.id!==selectedAgent);selectedAgent=agents[0]?.id??""}
    if(confirmKind==="mcp"){mcps=mcps.filter(s=>s.id!==selectedMcp);selectedMcp=mcps[0]?.id??""}
    dirty=true;
  }
  function toggleTool(tool:string){if(!agent)return;agent.builtinTools=agent.builtinTools.includes(tool)?agent.builtinTools.filter(t=>t!==tool):[...agent.builtinTools,tool];changed()}
  function toggleMcp(id:string){if(!agent)return;agent.mcpServers=agent.mcpServers.includes(id)?agent.mcpServers.filter(x=>x!==id):[...agent.mcpServers,id];changed()}
  function toolBlocked(tool:string){return (tool==="http_get"||tool==="run_command")&&policy.mode!=="online"}
  async function mcpAction(action:"test"|"status"|"authorize"|"disconnect"){
    if(!mcp)return;
    const method=action==="status"?"GET":"POST";
    try{
      const result=await json(`/api/mcp/${action==="test"?"test":`oauth/${encodeURIComponent(mcp.id)}/${action}`}${action==="test"?`/${encodeURIComponent(mcp.id)}`:""}`,{method});
      diagnostics[mcp.id]=JSON.stringify(result,null,2); diagnostics={...diagnostics};
      if(action==="authorize"&&result.authorizeUrl) window.open(result.authorizeUrl,"_blank","noopener,noreferrer");
      if(action==="status"||action==="disconnect") oauth[mcp.id]=result;
      oauth={...oauth}; toast(action==="test"?"Connection test complete":`OAuth ${action} complete`,"Review the diagnostics for details.","success");
    }catch(e){diagnostics[mcp.id]=JSON.stringify({error:(e as Error).message},null,2);diagnostics={...diagnostics};toast("Connection action failed",(e as Error).message,"danger")}
  }
  async function changeMode(mode:OperatingMode){
    if(mode===policy.mode)return;
    try{policy=await json("/api/runtime-policy",{method:"PUT",body:JSON.stringify({mode,revision:policy.revision})});toast("Operating mode changed",mode==="online"?"All configured connectivity is available.":mode==="restricted-online"?"AI web, external MCP, and OAuth network access are blocked; developer tools and Git may connect.":"External connectivity, remote Git, and command execution are blocked.","success")}
    catch(e){toast("Mode change failed",(e as Error).message,"danger");await load()}
  }
</script>

<AppShell title="Local Agent Studio" subtitle="Agent and MCP control plane" {nav} bind:active bind:collapsed help={()=>helpOpen=true} mode={policy.mode} onmodechange={changeMode} status={policy.mode==="online"?(gatewayHealthy===false?"Local · Degraded":"Local · Ready"):policy.mode==="restricted-online"?"Restricted Online":"Strict Offline"}>
  {#snippet children()}
    <div class="page">
      {#if policy.mode!=="online"}<div class:warning={policy.mode==="strict-offline"} class="mode-banner"><Unplug size={19}/><div><strong>{policy.mode==="restricted-online"?"Restricted Online":"Strict Offline"} mode is active.</strong><div>{policy.mode==="restricted-online"?"External LLM, agent HTTP, external MCP, and OAuth network access are blocked. Approved developer builds and Git may still connect.":"External MCP, OAuth, HTTP, remote Git, dependency downloads, and arbitrary command execution are blocked. Local models, files, and local Git remain available."}</div></div></div>{/if}
      {#if active==="agents"}
        <div class="page-header"><div><h1>Agents</h1><p class="page-description">Configure local agents, their model roles, execution limits, and authorized capabilities.</p></div><div class="toolbar"><Tooltip text="Create a disabled agent with safe starter permissions"><button class="btn" onclick={newAgent}><Plus size={17}/>New agent</button></Tooltip><Tooltip text="Save all agent and MCP configuration changes"><button class="btn primary" disabled={!dirty||saving} onclick={save}><Save size={17}/>{saving?"Saving…":"Save changes"}</button></Tooltip></div></div>
        {#if loading}<div class="section empty">Loading agent configuration…</div>
        {:else if !agents.length}<div class="section empty"><div class="empty-icon"><Bot/></div><h2>No agents configured</h2><p>Create an agent and grant only the capabilities it needs.</p><button class="btn primary" onclick={newAgent}><Plus size={17}/>New agent</button></div>
        {:else}<div class="master-detail">
          <section class="section master-list" aria-label="Agent list">{#each agents as item}<button class:active={selectedAgent===item.id} class="list-row" onclick={()=>selectedAgent=item.id}><div class="list-content"><div class="list-title">{item.name||item.id}</div><div class="list-meta">{item.modelRole} · {item.builtinTools.length} tools</div></div><span class:success={item.enabled} class="badge">{item.enabled?"Enabled":"Disabled"}</span></button>{/each}</section>
          {#if agent}<section class="section">
            <div class="section-header"><div><h2>{agent.name||"Untitled agent"}</h2><p class="muted" style="margin:2px 0 0">Changes are staged locally until you save.</p></div><label class="switch"><input type="checkbox" bind:checked={agent.enabled} onchange={changed}/><span class="switch-track"></span><span>{agent.enabled?"Enabled":"Disabled"}</span></label></div>
            <div class="form-section"><div class="form-section-heading"><div><h3>Identity</h3><span class="muted">Stable API identity and client-facing label.</span></div></div><div class="form-grid">
              <div class="field"><Tooltip text="Immutable generated key that distinguishes setup and custom agents from raw Ollama models."><label for="agent-id">Agent key</label></Tooltip><input id="agent-id" value={agent.id} disabled/><span class="field-help">{agent.source==="user"?"Custom agent":"Setup agent"}</span></div>
              <div class="field"><Tooltip text="Human-friendly name shown in model and agent selectors. Keep the required My or My Custom prefix."><label for="agent-name">Agent display name</label></Tooltip><input id="agent-name" bind:value={agent.name} oninput={changed}/></div>
            </div></div>
            <div class="form-section"><div class="form-section-heading"><div><h3>Runtime behavior</h3><span class="muted">Choose the model role and bound autonomous execution.</span></div></div><div class="form-grid">
              <div class="field"><Tooltip text="Installed Ollama model used by this agent."><label for="agent-model">Backing LLM model</label></Tooltip><select id="agent-model" bind:value={agent.modelTag} onchange={changed}>{#each models as model}<option value={model.tag}>{model.tag}</option>{/each}</select></div>
              <div class="field"><Tooltip text="Primary use case for this agent."><label for="agent-role">Role</label></Tooltip><select id="agent-role" bind:value={agent.role} onchange={changed}>{#each modelRoles as role}<option value={role}>{role}</option>{/each}</select></div>
              <div class="field"><Tooltip text="Maximum autonomous tool calls allowed during one request."><label for="max-steps">Maximum tool steps</label></Tooltip><input id="max-steps" type="number" min="1" max="50" bind:value={agent.maxSteps} oninput={changed}/></div>
            </div></div>
            <div class="form-section"><div class="form-section-heading"><div><h3>Instructions</h3><span class="muted">Define responsibilities, boundaries, and expected behavior.</span></div></div><div class="field"><Tooltip text="Durable system guidance applied whenever this agent runs."><label for="instructions">Agent instructions</label></Tooltip><textarea id="instructions" rows="8" bind:value={agent.instructions} oninput={changed}></textarea></div></div>
            <div class="form-section"><div class="form-section-heading"><div><h3>Permissions</h3><span class="muted">Apply least privilege. Read, write, deletion, and execution are intentionally distinct.</span></div></div>
              <div class="permission-groups">{#each groups as group}<div><h3>{group}</h3><div class="permission-grid">{#each tools.filter(t=>(toolInfo[t]?.group??"Other")===group) as tool}<Tooltip text={toolBlocked(tool)?`${tool} is configured but temporarily blocked by ${policy.mode} mode.`:toolInfo[tool]?.description??tool}><label class:risky={toolInfo[tool]?.risky} class="permission-card"><input type="checkbox" disabled={toolBlocked(tool)} checked={agent.builtinTools.includes(tool)} onchange={()=>toggleTool(tool)}/><span><span class="permission-name">{tool}</span><span class="permission-description">{toolBlocked(tool)?"Temporarily blocked by operating mode":toolInfo[tool]?.description}</span></span></label></Tooltip>{/each}</div></div>{/each}</div>
              {#if risky}<div class="notice" style="margin-top:16px"><ShieldAlert size={18}/><span>This agent can modify/delete files or execute commands. Review its instructions and project scope before use.</span></div>{/if}
            </div>
            <div class="form-section"><div class="form-section-heading"><div><h3>Connected MCP servers</h3><span class="muted">Assigned servers expand the tools available to this agent.</span></div></div>
              {#if mcps.length}<div class="permission-grid">{#each mcps as server}{@const blocked=policy.mode!=="online"&&!server.offlineCapable}<Tooltip text={blocked?`External MCP is configured but blocked by ${policy.mode} mode.`:"Allow this agent to discover and call tools exposed by this MCP server"}><label class="permission-card"><input type="checkbox" disabled={blocked} checked={agent.mcpServers.includes(server.id)} onchange={()=>toggleMcp(server.id)}/><span><span class="permission-name">{server.name}</span><span class="permission-description">{blocked?"Temporarily blocked by operating mode":`${server.id} · ${oauth[server.id]?.connected?"OAuth connected":"authorization not confirmed"}`}</span></span></label></Tooltip>{/each}</div>{:else}<p class="muted">No MCP servers are configured.</p>{/if}
            </div>
            <div class="form-section"><div class="form-section-heading"><div><h3 style="color:var(--danger)">Danger zone</h3><span class="muted">Deletion takes effect after Save changes.</span></div><Tooltip text="Remove this agent from configuration after confirmation"><button class="btn danger" onclick={()=>askDelete("agent")}><Trash2 size={16}/>Delete agent</button></Tooltip></div></div>
          </section>{/if}
        </div>{/if}
      {:else if active==="mcp"}
        <div class="page-header"><div><h1>MCP Servers</h1><p class="page-description">Connect trusted Model Context Protocol servers to extend local agents with external tools and data.</p></div><div class="toolbar"><Tooltip text="Add a disabled Streamable HTTP MCP configuration"><button class="btn" onclick={newMcp}><Plus size={17}/>Add MCP server</button></Tooltip><Tooltip text="Save all server and agent configuration changes"><button class="btn primary" disabled={!dirty||saving} onclick={save}><Save size={17}/>{saving?"Saving…":"Save changes"}</button></Tooltip></div></div>
        {#if !mcps.length}<div class="section empty"><div class="empty-icon"><Server/></div><h2>No MCP servers</h2><p>Add a trusted server when an agent needs external tools or data.</p><button class="btn primary" onclick={newMcp}><Plus size={17}/>Add MCP server</button></div>
        {:else}<div class="master-detail">
          <section class="section master-list">{#each mcps as item}<button class:active={selectedMcp===item.id} class="list-row" onclick={()=>selectedMcp=item.id}><div class="list-content"><div class="list-title">{item.name||item.id}</div><div class="list-meta">{item.authentication?.type??"none"} · Streamable HTTP</div></div><span class:success={item.enabled} class="badge">{item.enabled?"Enabled":"Disabled"}</span></button>{/each}</section>
          {#if mcp}<section class="section">
            <div class="section-header"><div><h2>{mcp.name||"Untitled server"}</h2><p class="muted" style="margin:2px 0 0">Streamable HTTP · {oauth[mcp.id]?.connected?"Authenticated":"Authentication not confirmed"}</p></div><label class="switch"><input type="checkbox" bind:checked={mcp.enabled} onchange={changed}/><span class="switch-track"></span><span>{mcp.enabled?"Enabled":"Disabled"}</span></label></div>
            <div class="form-section"><h3>Server identity</h3><div class="form-grid" style="margin-top:16px"><div class="field"><Tooltip text="Stable key used by agent assignments and secret references."><label for="mcp-id">Server ID</label></Tooltip><input id="mcp-id" bind:value={mcp.id} oninput={changed}/></div><div class="field"><Tooltip text="Human-friendly server name shown throughout Studio."><label for="mcp-name">Display name</label></Tooltip><input id="mcp-name" bind:value={mcp.name} oninput={changed}/></div></div></div>
            <div class="form-section"><h3>Connection</h3><div class="form-grid" style="margin-top:16px"><div class="field full"><Tooltip text="Provider's trusted HTTPS Streamable HTTP MCP endpoint."><label for="mcp-url">Streamable HTTP URL</label></Tooltip><input id="mcp-url" type="url" bind:value={mcp.url} oninput={changed} placeholder="https://example.com/mcp"/></div><div class="field"><Tooltip text="Maximum seconds to wait for the remote server."><label for="timeout">Timeout seconds</label></Tooltip><input id="timeout" type="number" min="1" max="600" bind:value={mcp.timeoutSeconds} oninput={changed}/></div><div class="field"><span class="field-label">Offline capability</span><label class="switch"><input type="checkbox" bind:checked={mcp.offlineCapable} onchange={changed}/><span class="switch-track"></span><span>Trusted local/offline server</span></label><span class="field-help">Off by default. Enable only when this server never requires internet access.</span></div></div></div>
            <div class="form-section"><h3>Authentication</h3><div class="form-grid" style="margin-top:16px"><div class="field"><Tooltip text="Authentication mechanism expected by this MCP server."><label for="auth-type">Authentication type</label></Tooltip><select id="auth-type" bind:value={mcp.authentication!.type} onchange={changed}><option value="none">None</option><option value="oauth">OAuth 2.1</option></select></div><div class="field"><Tooltip text="Space-separated OAuth scopes. Leave blank when provider discovery supplies defaults."><label for="scopes">OAuth scopes</label></Tooltip><input id="scopes" value={(mcp.authentication?.scopes??[]).join(" ")} oninput={(e)=>{mcp!.authentication!.scopes=(e.currentTarget as HTMLInputElement).value.split(/\s+/).filter(Boolean);changed()}}/></div><div class="field full"><Tooltip text="Non-secret request headers as JSON. Store credentials through Set-McpSecret.ps1."><label for="headers">Non-secret HTTP headers (JSON)</label></Tooltip><textarea id="headers" rows="4" value={JSON.stringify(mcp.headers??{},null,2)} onblur={(e)=>{try{mcp!.headers=JSON.parse((e.currentTarget as HTMLTextAreaElement).value);changed()}catch{toast("Invalid headers JSON","Correct the JSON before saving.","danger")}}}></textarea><span class="field-help">Do not paste tokens or credentials here. Use secure secret-header references.</span></div></div></div>
            <div class="form-section"><div class="form-section-heading"><div><h3>Connection actions</h3><span class="muted">Saving, authentication, and testing are separate operations.</span></div></div><div class="button-row"><Tooltip text={policy.mode!=="online"&&!mcp.offlineCapable?"External MCP testing is blocked by the operating mode":"Initialize a session and verify transport plus current authentication"}><button class="btn primary" disabled={policy.mode!=="online"&&!mcp.offlineCapable} onclick={()=>mcpAction("test")}><RefreshCw size={16}/>Test connection</button></Tooltip><Tooltip text={policy.mode!=="online"?"OAuth network authorization is available only in Online mode":"Open the provider's browser authorization flow"}><button class="btn" disabled={policy.mode!=="online"} onclick={()=>mcpAction("authorize")}><Link2 size={16}/>Connect OAuth</button></Tooltip><Tooltip text="Check locally stored OAuth authorization state"><button class="btn" onclick={()=>mcpAction("status")}><KeyRound size={16}/>OAuth status</button></Tooltip><Tooltip text="Remove this server's locally stored OAuth grant"><button class="btn" onclick={()=>mcpAction("disconnect")}><Unplug size={16}/>Disconnect OAuth</button></Tooltip></div></div>
            <div class="form-section"><div class="split-header"><div><h3>Diagnostics</h3><span class="muted">Latest action response for this browser session.</span></div>{#if diagnostics[mcp.id]}<Tooltip text="Copy diagnostic JSON to the clipboard"><button class="btn icon ghost" aria-label="Copy diagnostics" onclick={()=>navigator.clipboard.writeText(diagnostics[mcp!.id])}><Copy size={16}/></button></Tooltip>{/if}</div><div class="code-panel"><div class="code-toolbar"><span>JSON response</span></div><pre>{diagnostics[mcp.id]??"Run a connection action to view diagnostics."}</pre></div></div>
            <div class="form-section"><div class="form-section-heading"><div><h3 style="color:var(--danger)">Danger zone</h3><span class="muted">Remove configuration only after detaching it from agents.</span></div><Tooltip text="Remove this MCP server after confirmation"><button class="btn danger" onclick={()=>askDelete("mcp")}><Trash2 size={16}/>Delete server</button></Tooltip></div></div>
          </section>{/if}
        </div>{/if}
      {:else}
        <div class="page-header"><div><h1>Status</h1><p class="page-description">Operational health for the local gateway, configured agents, and MCP integrations.</p></div><Tooltip text="Refresh configuration and connection status"><button class="btn" onclick={load}><RefreshCw size={17}/>Refresh</button></Tooltip></div>
        <div class="metric-grid"><div class="metric"><span class="muted">Local gateway</span><div class="metric-value">{gatewayHealthy===null?"Checking":gatewayHealthy?"Healthy":"Degraded"}</div></div><div class="metric"><span class="muted">Configured agents</span><div class="metric-value">{agents.length}</div></div><div class="metric"><span class="muted">Enabled agents</span><div class="metric-value">{agents.filter(a=>a.enabled).length}</div></div><div class="metric"><span class="muted">MCP connected</span><div class="metric-value">{mcps.filter(s=>oauth[s.id]?.connected).length} / {mcps.length}</div></div></div>
        <section class="section"><div class="section-header"><div><h2>MCP server health</h2><p class="muted" style="margin:2px 0 0">Configuration and current authorization state.</p></div></div>{#if mcps.length}{#each mcps as server}<button class="list-row" onclick={()=>{selectedMcp=server.id;active="mcp"}}><Server size={18}/><div class="list-content"><div class="list-title">{server.name}</div><div class="list-meta">{server.url}</div></div><span class="badge">{server.enabled?"Enabled":"Disabled"}</span><span class:success={oauth[server.id]?.connected} class:warning={!oauth[server.id]?.connected} class="badge">{oauth[server.id]?.connected?"Authenticated":"Not authenticated"}</span></button>{/each}{:else}<div class="empty"><div class="empty-icon"><Check/></div><h2>No MCP servers configured</h2><p>Add a server only when an agent needs an external capability.</p></div>{/if}</section>
      {/if}
    </div>
  {/snippet}
</AppShell>
<HelpDrawer bind:open={helpOpen} topics={studioHelp} context={active==="mcp"?"MCP Servers":active==="status"?"Status":"Agents"}/>
<ConfirmDialog bind:open={confirmOpen} title={confirmKind==="agent"?"Delete agent?":"Delete MCP server?"} message="This removes the item from the editable configuration. The change becomes active when you save." confirmLabel="Delete" onconfirm={removeSelected}/>
<ToastStack bind:messages={toasts}/>
