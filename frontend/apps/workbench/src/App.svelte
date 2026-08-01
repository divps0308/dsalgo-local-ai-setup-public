<script lang="ts">
  import { Check, ClipboardCheck, Code2, Copy, FolderGit2, GitBranch, GitCommit, GitCompare, GitPullRequestArrow, ListTodo, Plus, RefreshCw, Rocket, Square, Trash2, Unplug, X } from "lucide-svelte";
  import AppShell from "../../../shared/AppShell.svelte";
  import ConfirmDialog from "../../../shared/ConfirmDialog.svelte";
  import HelpDrawer from "../../../shared/HelpDrawer.svelte";
  import ToastStack from "../../../shared/ToastStack.svelte";
  import Tooltip from "../../../shared/Tooltip.svelte";
  import type { OperatingMode, ToastMessage } from "../../../shared/types";
  import { workbenchHelp } from "./help";

  type Project={id:string;name:string;path:string};
  type Approval={id:string;status:string;risk:string;summary:string;details:Record<string,any>};
  type Event={kind:string;content:any};
  type Agent={id:string;name:string;modelTag?:string;modelRole?:string};
  type Task={id:string;projectId:string;prompt:string;modelRole:string;workMode?:"ask"|"plan"|"goal";agentId?:string;agentName?:string;status:string;createdAt:number;approvals?:Approval[];events?:Event[];planPath?:string};
  const token=document.querySelector<HTMLMetaElement>('meta[name="workbench-token"]')?.content??"";
  let active=$state("projects"), collapsed=$state(localStorage.getItem("workbench-sidebar-collapsed")==="true"), helpOpen=$state(false);
  let projects=$state<Project[]>([]), tasks=$state<Task[]>([]), agents=$state<Agent[]>([]), selected=$state(""), selectedTask=$state("");
  let healthy=$state<boolean|null>(null), loading=$state(true), busy=$state(false), toasts=$state<ToastMessage[]>([]);
  let projectDialog=$state(false), projectName=$state(""), projectPath=$state(""), projectError=$state("");
  let taskDialog=$state(false), prompt=$state(""), agentId=$state(""), workMode=$state<"ask"|"plan"|"goal">("goal"), guidance=$state(false);
  let gitView=$state<"status"|"diff"|"diff-staged">("status"), gitOutput=$state("Select an approved project, then inspect repository status or a diff.");
  let branchName=$state(""), commitMessage=$state(""), confirmOpen=$state(false), confirmAction=$state<"remove"|"push"|"commit"|null>(null);
  let policy=$state<{mode:OperatingMode;revision:number}>({mode:"online",revision:1});
  const nav=[
    {id:"projects",label:"Projects",description:"Register and select explicitly approved Windows project roots.",icon:FolderGit2},
    {id:"tasks",label:"Tasks",description:"Create and review AI-driven code change tasks.",icon:ListTodo},
    {id:"git",label:"Git",description:"Inspect diffs and perform explicit branch, commit, and push actions.",icon:GitBranch}
  ];
  const gitViews:[{id:"status";label:string},{id:"diff";label:string},{id:"diff-staged";label:string}]=[
    {id:"status",label:"Status"},{id:"diff",label:"Working diff"},{id:"diff-staged",label:"Staged diff"}
  ];
  let project=$derived(projects.find(p=>p.id===selected));
  let projectTasks=$derived(tasks.filter(t=>!selected||t.projectId===selected).sort((a,b)=>b.createdAt-a.createdAt));
  let task=$derived(projectTasks.find(t=>t.id===selectedTask)??projectTasks[0]);
  $effect(()=>localStorage.setItem("workbench-sidebar-collapsed",String(collapsed)));
  $effect(()=>{void refresh();const timer=setInterval(refresh,2000);return()=>clearInterval(timer)});
  function toast(title:string,message="",tone:ToastMessage["tone"]="info"){const id=Date.now()+Math.random();toasts=[...toasts,{id,title,message,tone}];setTimeout(()=>toasts=toasts.filter(t=>t.id!==id),4500)}
  async function api(path:string,options:RequestInit={}){
    const response=await fetch(path,{...options,headers:{"X-Workbench-Token":token,...(options.body?{"Content-Type":"application/json"}:{}),...(options.headers||{})}});
    const data=await response.json().catch(()=>({}));
    if(response.status===401 && !sessionStorage.getItem("workbench-token-reloaded")){
      sessionStorage.setItem("workbench-token-reloaded","true");
      location.reload();
      throw new Error("Refreshing Workbench authorization…");
    }
    if(!response.ok) throw new Error(data.error||`Request failed (${response.status})`);
    return data;
  }
  async function refresh(){
    try{const data=await api("/api/state");projects=data.projects??[];tasks=data.tasks??[];agents=data.agents??[];agentId ||= agents[0]?.id??"";if(agentId&&!agents.some(a=>a.id===agentId))agentId=agents[0]?.id??"";policy=data.runtimePolicy??policy;selected ||= projects[0]?.id??"";if(selected&&!projects.some(p=>p.id===selected))selected=projects[0]?.id??"";healthy=true}
    catch(e){healthy=false;if(loading)toast("Workbench unavailable",(e as Error).message,"danger")}finally{loading=false}
  }
  async function addProject(){
    projectError="";
    if(!projectName.trim()){projectError="Project name is required.";return}
    if(!/^[A-Za-z]:\\/.test(projectPath.trim())){projectError="Enter an absolute Windows directory such as C:\\dev\\my-project.";return}
    busy=true;try{const added=await api("/api/projects",{method:"POST",body:JSON.stringify({name:projectName.trim(),path:projectPath.trim()})});projectDialog=false;projectName="";projectPath="";await refresh();selected=added.id??selected;toast("Project approved","The Workbench can now operate within this directory.","success")}
    catch(e){projectError=(e as Error).message}finally{busy=false}
  }
  async function removeProject(){if(!selected)return;busy=true;try{await api(`/api/projects/${encodeURIComponent(selected)}`,{method:"DELETE"});selected="";await refresh();toast("Project removed","The directory was not deleted.","success")}catch(e){toast("Remove failed",(e as Error).message,"danger")}finally{busy=false}}
  async function createTask(){
    if(!selected||!prompt.trim()){toast("Complete the task request","Select a project and describe the requested change.","warning");return}
    if(!agentId){toast("Select an agent","Choose a sample or custom agent before starting the task.","warning");return}
    busy=true;try{const created=await api("/api/tasks",{method:"POST",body:JSON.stringify({projectId:selected,prompt:prompt.trim(),agentId,workMode})});prompt="";taskDialog=false;await refresh();selectedTask=created.id??"";active="tasks";toast(`${workMode[0].toUpperCase()+workMode.slice(1)} started`,"The request is running in the selected Workbench mode.","success")}catch(e){toast("Task could not start",(e as Error).message,"danger")}finally{busy=false}
  }
  async function decide(taskId:string,approvalId:string,decision:"approve"|"reject"){try{await api(`/api/tasks/${taskId}/approvals/${approvalId}`,{method:"POST",body:JSON.stringify({decision})});await refresh();toast(`Action ${decision==="approve"?"approved":"rejected"}`,"The task has been updated.","success")}catch(e){toast("Approval failed",(e as Error).message,"danger")}}
  async function cancelTask(id:string){try{await api(`/api/tasks/${id}/cancel`,{method:"POST"});await refresh();toast("Task cancelled","","warning")}catch(e){toast("Cancel failed",(e as Error).message,"danger")}}
  async function gitRead(kind=gitView){if(!selected)return;busy=true;gitView=kind as typeof gitView;try{gitOutput=JSON.stringify(await api(`/api/projects/${selected}/git/${kind}`),null,2)}catch(e){gitOutput=(e as Error).message;toast("Git read failed",gitOutput,"danger")}finally{busy=false}}
  async function gitAction(action:"branch"|"commit"|"push"){
    if(!selected)return;
    const value=action==="branch"?branchName:action==="commit"?commitMessage:"";
    if(action==="branch"&&!/^[A-Za-z0-9._/-]+$/.test(value)){toast("Invalid branch name","Use letters, numbers, dots, slashes, underscores, or hyphens.","warning");return}
    if(action==="commit"&&!value.trim()){toast("Commit message required","Describe the outcome of the change.","warning");return}
    busy=true;try{gitOutput=JSON.stringify(await api(`/api/projects/${selected}/git/${action}`,{method:"POST",body:JSON.stringify({value})}),null,2);await refresh();toast(`Git ${action} complete`,action==="push"?"The current branch was sent to its configured remote.":"Review the Git output for details.","success")}catch(e){gitOutput=(e as Error).message;toast(`Git ${action} failed`,gitOutput,"danger")}finally{busy=false}
  }
  function requestConfirm(action:"remove"|"push"|"commit"){confirmAction=action;confirmOpen=true}
  function runConfirmed(){if(confirmAction==="remove")return removeProject();if(confirmAction==="push")return gitAction("push");return gitAction("commit")}
  function statusTone(status:string){return status==="completed"?"success":status==="failed"||status==="cancelled"?"danger":status==="waiting_approval"?"warning":"info"}
  function eventText(value:any){return typeof value==="string"?value:JSON.stringify(value,null,2)}
  async function changeMode(mode:OperatingMode){
    if(mode===policy.mode)return;
    try{policy=await api("/api/runtime-policy",{method:"PUT",body:JSON.stringify({mode,revision:policy.revision})});toast("Operating mode changed",mode==="online"?"All configured connectivity is available.":mode==="restricted-online"?"AI web, external MCP, and OAuth access are blocked; builds and Git may connect.":"Remote Git and command execution are blocked; local models, files, and Git remain available.","success")}
    catch(e){toast("Mode change failed",(e as Error).message,"danger");await refresh()}
  }
</script>

<AppShell title="Developer Workbench" subtitle="Local code change and Git console" {nav} bind:active bind:collapsed help={()=>helpOpen=true} mode={policy.mode} onmodechange={changeMode} status={policy.mode==="online"?(healthy===false?"Local · Degraded":"Local · Ready"):policy.mode==="restricted-online"?"Restricted Online":"Strict Offline"}>
  {#snippet children()}
    <div class="page">
      {#if policy.mode!=="online"}<div class:warning={policy.mode==="strict-offline"} class="mode-banner"><Unplug size={19}/><div><strong>{policy.mode==="restricted-online"?"Restricted Online":"Strict Offline"} mode is active.</strong><div>{policy.mode==="restricted-online"?"Local AI remains available. External AI/MCP access is blocked; approved developer builds and Git may still use the internet.":"External connectivity, remote Git, dependency downloads, and arbitrary commands are blocked. Local models, file changes, and local Git remain available."}</div></div></div>{/if}
      {#if active==="projects"}
        <div class="page-header"><div><h1>Approved projects</h1><p class="page-description">Register local repositories that the Workbench is allowed to inspect and modify.</p></div><Tooltip text="Register an existing absolute Windows directory"><button class="btn primary" onclick={()=>projectDialog=true}><Plus size={17}/>Add project</button></Tooltip></div>
        {#if loading}<div class="section empty">Loading approved projects…</div>
        {:else if !projects.length}<div class="section empty"><div class="empty-icon"><FolderGit2/></div><h2>No approved projects</h2><p>Explicitly register a project root before asking an agent to inspect or change local files.</p><button class="btn primary" onclick={()=>projectDialog=true}><Plus size={17}/>Add your first project</button></div>
        {:else}<section class="section"><div class="section-header"><div><h2>Project registry</h2><p class="muted" style="margin:2px 0 0">{projects.length} approved {projects.length===1?"directory":"directories"}</p></div></div>{#each projects as item}<button class:active={selected===item.id} class="list-row" onclick={()=>selected=item.id}><FolderGit2 size={19}/><div class="list-content"><div class="list-title">{item.name}</div><div class="list-meta">{item.path}</div></div>{#if selected===item.id}<span class="badge success"><Check size={12}/>Selected</span>{/if}</button>{/each}</section>
        {#if project}<section class="section" style="margin-top:20px"><div class="section-header"><div><h2>{project.name}</h2><p class="muted" style="margin:2px 0 0;font-family:var(--font-mono)">{project.path}</p></div><div class="toolbar"><Tooltip text="Use this project when creating a new change task"><button class="btn primary" onclick={()=>{active="tasks";taskDialog=true}}><ListTodo size={16}/>New task</button></Tooltip><Tooltip text="Remove approval without deleting files from disk"><button class="btn danger" onclick={()=>requestConfirm("remove")}><Trash2 size={16}/>Remove</button></Tooltip></div></div><div class="section-body"><div class="notice"><ClipboardCheck size={18}/><span>Filesystem and command actions remain subject to the Workbench’s approval and safety controls. Generated changes should be reviewed before commit.</span></div></div></section>{/if}{/if}
      {:else if active==="tasks"}
        <div class="page-header"><div><h1>Change tasks</h1><p class="page-description">Ask a selected local coding agent to inspect an approved project, implement a scoped change, and report results.</p></div><Tooltip text="Compose a scoped code-change request for the selected project"><button class="btn primary" disabled={!selected} onclick={()=>taskDialog=true}><Plus size={17}/>New change task</button></Tooltip></div>
        <div class="section" style="margin-bottom:20px"><div class="section-body"><div class="field"><Tooltip text="Choose the approved project that bounds file and command access"><label for="task-context">Project context</label></Tooltip><select id="task-context" bind:value={selected}>{#each projects as item}<option value={item.id}>{item.name} — {item.path}</option>{/each}</select>{#if !projects.length}<span class="field-help">Add an approved project before creating a task.</span>{/if}</div></div></div>
        {#if !selected}<div class="section empty"><div class="empty-icon"><FolderGit2/></div><h2>Select or add a project</h2><p>Tasks can run only within an explicitly approved Windows directory.</p><button class="btn" onclick={()=>active="projects"}>Go to Projects</button></div>
        {:else if !projectTasks.length}<div class="section empty"><div class="empty-icon"><ListTodo/></div><h2>No change tasks for this project</h2><p>Start with a focused objective, constraints, acceptance criteria, and tests.</p><button class="btn primary" onclick={()=>taskDialog=true}><Plus size={17}/>New change task</button></div>
        {:else}<div class="master-detail">
          <section class="section master-list">{#each projectTasks as item}<button class:active={task?.id===item.id} class="list-row" onclick={()=>selectedTask=item.id}><div class="list-content"><div class="list-title">{item.prompt}</div><div class="list-meta">{item.agentName||item.agentId||item.modelRole} · {new Date(item.createdAt*1000).toLocaleString()}</div></div><span class="badge {statusTone(item.status)}">{item.status.replaceAll("_"," ")}</span></button>{/each}</section>
          {#if task}<section class="section"><div class="section-header"><div><h2>{task.prompt}</h2><p class="muted" style="margin:4px 0 0">Agent: {task.agentName||task.agentId||task.modelRole}</p></div><span class="badge {statusTone(task.status)}">{task.status.replaceAll("_"," ")}</span></div>
            {#each (task.approvals??[]).filter(a=>a.status==="pending") as approval}<div class="form-section"><div class="notice {approval.risk==="high"?"danger":""}"><div style="flex:1"><h3>{approval.summary} <span class="badge warning">{approval.risk} risk</span></h3><p>{approval.details?.reason??"Review the requested action before deciding."}</p>{#if approval.details?.command||approval.details?.patch}<div class="code-panel"><pre>{approval.details.command??approval.details.patch}</pre></div>{/if}<div class="button-row" style="margin-top:12px"><Tooltip text="Allow this pending task action to continue"><button class="btn primary" onclick={()=>decide(task!.id,approval.id,"approve")}><Check size={16}/>Approve</button></Tooltip><Tooltip text="Deny this pending task action"><button class="btn danger" onclick={()=>decide(task!.id,approval.id,"reject")}><X size={16}/>Reject</button></Tooltip></div></div></div></div>{/each}
            <div class="form-section"><div class="split-header"><div><h3>Activity and results</h3><span class="muted">Commands, patches, test output, and agent progress.</span></div>{#if ["running","waiting_approval"].includes(task.status)}<Tooltip text="Request cancellation of this running task"><button class="btn danger" onclick={()=>cancelTask(task!.id)}><Square size={15}/>Cancel task</button></Tooltip>{/if}</div>
              {#if task.events?.length}{#each task.events as event}<details class="faq" open><summary><span><span class="badge">{event.kind}</span></span></summary><div class="code-panel" style="margin-bottom:14px"><pre>{eventText(event.content)}</pre></div></details>{/each}{:else}<p class="muted">Waiting for task activity…</p>{/if}
            </div>
          </section>{/if}
        </div>{/if}
      {:else}
        <div class="page-header"><div><h1>Git workflow</h1><p class="page-description">Inspect repository changes and perform explicit local Git actions for the selected approved project.</p></div><Tooltip text="Refresh the current Git view"><button class="btn" disabled={!selected||busy} onclick={()=>gitRead()}><RefreshCw size={17}/>Refresh</button></Tooltip></div>
        <section class="section" style="margin-bottom:20px"><div class="section-body"><div class="form-grid"><div class="field"><Tooltip text="Select the approved repository for all Git actions on this page"><label for="git-project">Project</label></Tooltip><select id="git-project" bind:value={selected}>{#each projects as item}<option value={item.id}>{item.name} — {item.path}</option>{/each}</select></div><div class="field"><span class="field-label">Repository context</span><div style="min-height:44px;display:flex;align-items:center"><span class="badge info"><GitBranch size={13}/>{project?.name??"No project selected"}</span></div></div></div></div></section>
        {#if !selected}<div class="section empty"><div class="empty-icon"><GitBranch/></div><h2>No project selected</h2><p>Approve and select a Git repository root to use this workflow.</p></div>
        {:else}<section class="section">
          <div class="section-header"><div class="segmented" aria-label="Git output view">{#each gitViews as view}<Tooltip text={view.id==="status"?"Show branch and working-tree status":view.id==="diff"?"Show unstaged working-tree changes":"Show changes already staged for commit"}><button class:active={gitView===view.id} onclick={()=>gitRead(view.id)}>{view.label}</button></Tooltip>{/each}</div></div>
          <div class="form-section"><div class="code-panel"><div class="code-toolbar"><span>{gitView}</span><Tooltip text="Copy current Git output"><button class="btn icon ghost" style="color:#cbd5e1;width:32px;min-height:32px" aria-label="Copy Git output" onclick={()=>navigator.clipboard.writeText(gitOutput)}><Copy size={15}/></button></Tooltip></div><pre>{gitOutput}</pre></div></div>
          <div class="form-section"><div class="form-section-heading"><div><h3>Branch</h3><span class="muted">Create or switch to a focused local branch.</span></div></div><div class="form-grid"><div class="field"><Tooltip text="Valid branch name to create or switch to, such as feature/my-change"><label for="branch-name">Create or switch branch</label></Tooltip><input id="branch-name" bind:value={branchName} placeholder="feature/my-change"/></div><div style="display:flex;align-items:end"><Tooltip text="Run the existing backend branch action for this repository"><button class="btn" disabled={!branchName.trim()||busy} onclick={()=>gitAction("branch")}><GitBranch size={16}/>Create / switch</button></Tooltip></div></div></div>
          <div class="form-section"><div class="form-section-heading"><div><h3>Commit</h3><span class="muted">Stages all current project changes and creates a local commit.</span></div></div><div class="form-grid"><div class="field"><Tooltip text="Describe the outcome clearly in imperative form"><label for="commit-message">Commit message</label></Tooltip><input id="commit-message" bind:value={commitMessage} placeholder="Improve OAuth connection diagnostics"/></div><div style="display:flex;align-items:end"><Tooltip text="Stages all current changes and creates a local commit"><button class="btn success" disabled={!commitMessage.trim()||busy} onclick={()=>requestConfirm("commit")}><GitCommit size={16}/>Stage all and commit</button></Tooltip></div></div></div>
            <div class="form-section"><div class="form-section-heading"><div><h3>Remote</h3><span class="muted">{policy.mode==="strict-offline"?"Remote Git actions are disabled by Strict Offline mode.":"Push is an external-impact action and always requires confirmation."}</span></div><Tooltip text={policy.mode==="strict-offline"?"Git push is blocked by Strict Offline mode":"Pushes the current local branch to its configured remote"}><button class="btn" disabled={busy||policy.mode==="strict-offline"} onclick={()=>requestConfirm("push")}><Rocket size={16}/>Push current branch</button></Tooltip></div></div>
        </section>{/if}
      {/if}
    </div>
  {/snippet}
</AppShell>

{#if projectDialog}<div class="overlay" role="presentation" onclick={(e)=>e.target===e.currentTarget&&(projectDialog=false)} onkeydown={(e)=>e.key==="Escape"&&(projectDialog=false)}><form class="dialog" role="dialog" aria-modal="true" aria-labelledby="project-title" onsubmit={(e)=>{e.preventDefault();addProject()}}><div class="dialog-header"><div><h2 id="project-title">Add approved project</h2><p class="muted" style="margin:3px 0 0">Register an existing Windows directory.</p></div><button type="button" class="btn icon ghost" aria-label="Close" onclick={()=>projectDialog=false}><X size={18}/></button></div><div class="dialog-body"><div class="field"><Tooltip text="Human-friendly label for this repository or project root"><label for="project-name">Project name</label></Tooltip><input id="project-name" bind:value={projectName} placeholder="My project"/></div><div class="field" style="margin-top:16px"><Tooltip text="Existing absolute Windows directory the Workbench may inspect and modify"><label for="project-path">Windows directory</label></Tooltip><input id="project-path" bind:value={projectPath} placeholder="C:\dev\my-project"/><span class="field-help">Use the narrowest practical root, preferably a Git repository root.</span></div>{#if projectError}<p style="color:var(--danger);margin:12px 0 0" role="alert">{projectError}</p>{/if}</div><div class="dialog-footer"><button type="button" class="btn" onclick={()=>projectDialog=false}>Cancel</button><button class="btn primary" disabled={busy}>{busy?"Adding…":"Add project"}</button></div></form></div>{/if}

{#if taskDialog}<div class="overlay" role="presentation" onclick={(e)=>e.target===e.currentTarget&&(taskDialog=false)} onkeydown={(e)=>e.key==="Escape"&&(taskDialog=false)}><form class="dialog" role="dialog" style="width:min(720px,100%)" aria-modal="true" aria-labelledby="task-title" onsubmit={(e)=>{e.preventDefault();createTask()}}><div class="dialog-header"><div><h2 id="task-title">New change task</h2><p class="muted" style="margin:3px 0 0">Scope an agent request within an approved project.</p></div><button type="button" class="btn icon ghost" aria-label="Close" onclick={()=>taskDialog=false}><X size={18}/></button></div><div class="dialog-body"><div class="form-grid"><div class="field"><Tooltip text="Approved project that bounds file and command access"><label for="new-task-project">Project</label></Tooltip><select id="new-task-project" bind:value={selected}>{#each projects as item}<option value={item.id}>{item.name}</option>{/each}</select></div><div class="field"><Tooltip text="Sample or custom agent configured in Local Agent Studio"><label for="new-task-agent">Agent</label></Tooltip><select id="new-task-agent" bind:value={agentId}><option value="" disabled>Select an agent</option>{#each agents as item}<option value={item.id}>{item.name}{item.modelTag?` — ${item.modelTag}`:""}</option>{/each}</select>{#if !agents.length}<span class="field-help">No enabled agents are configured. Create one in Local Agent Studio first.</span>{/if}</div><div class="field full"><Tooltip text="Describe the objective, constraints, acceptance criteria, tests, and relevant modules"><label for="new-task-prompt">Change request</label></Tooltip><textarea id="new-task-prompt" rows="8" bind:value={prompt} placeholder="Objective:&#10;Constraints:&#10;Acceptance criteria:&#10;Tests to run:&#10;Likely files/modules:"></textarea><span class="field-help">The selected agent may inspect or change files and request command approvals according to configured permissions.</span></div></div><button type="button" class="btn ghost" onclick={()=>guidance=!guidance}>{guidance?"Hide":"Show"} request guidance</button>{#if guidance}<div class="notice" style="margin-top:10px"><Code2 size={18}/><span><strong>Recommended structure:</strong> objective, constraints, acceptance criteria, exact tests, and likely files. Keep one task focused on one coherent outcome.</span></div>{/if}</div><div class="dialog-footer"><button type="button" class="btn" onclick={()=>taskDialog=false}>Cancel</button><button class="btn primary" disabled={busy||!prompt.trim()||!agentId}><GitPullRequestArrow size={16}/>{busy?"Starting…":"Start task"}</button></div></form></div>{/if}

{#if taskDialog}<div class="field" style="position:fixed;inset:auto 24px 92px auto;z-index:20;background:var(--panel);padding:10px;border:1px solid var(--line);border-radius:8px"><label for="work-mode-floating">Work mode</label><select id="work-mode-floating" bind:value={workMode}><option value="ask">Ask — read and answer</option><option value="plan">Plan — read and save a Markdown plan</option><option value="goal">Goal — pursue with approvals</option></select></div>{/if}
<HelpDrawer bind:open={helpOpen} topics={workbenchHelp} context={active==="projects"?"Projects":active==="tasks"?"Tasks":"Git"}/>
<ConfirmDialog bind:open={confirmOpen} title={confirmAction==="remove"?"Remove approved project?":confirmAction==="push"?"Push current branch?":"Stage all changes and commit?"} message={confirmAction==="remove"?"This revokes Workbench approval but does not delete files from disk.":confirmAction==="push"?`This pushes the current branch for ${project?.name??"the selected project"} to its configured remote.`:"All current project changes will be staged and committed with the entered message."} confirmLabel={confirmAction==="remove"?"Remove project":confirmAction==="push"?"Push branch":"Stage and commit"} tone={confirmAction==="remove"?"danger":"primary"} onconfirm={runConfirmed}/>
<ToastStack bind:messages={toasts}/>
