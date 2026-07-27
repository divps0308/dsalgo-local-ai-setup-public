<script lang="ts">
  import { ChevronLeft, ChevronRight, Globe2, HelpCircle, Menu, X } from "lucide-svelte";
  import ThemeSelector from "./ThemeSelector.svelte";
  import Tooltip from "./Tooltip.svelte";
  import type { NavItem, OperatingMode } from "./types";
  let { title, subtitle, nav, active = $bindable(), status = "Local · Ready", mode = "online", collapsed = $bindable(false), help, onmodechange, children }: {
    title:string; subtitle:string; nav:NavItem[]; active:string; status?:string; mode?:OperatingMode; collapsed:boolean; help:()=>void; onmodechange?:(mode:OperatingMode)=>void; children:import("svelte").Snippet;
  } = $props();
  let mobileOpen = $state(false);
  function choose(id:string){active=id;mobileOpen=false;}
</script>
<div class:collapsed class="app-shell">
  <header class="app-header">
    <div class="brand">
      <button class="btn icon ghost mobile-only" aria-label="Open navigation" onclick={()=>mobileOpen=true}><Menu size={19}/></button>
      <div class="brand-mark"><img src="/logo.png" alt="" /></div>
      <div><div class="brand-title">{title}</div><div class="brand-subtitle">{subtitle}</div></div>
    </div>
    <div class="header-actions">
      <Tooltip text="Central connectivity policy shared by Agent Studio and Developer Workbench">
        <label class="mode-control"><Globe2 size={16}/><span class="desktop-only">Mode</span><select aria-label="Operating mode" value={mode} onchange={(e)=>onmodechange?.((e.currentTarget as HTMLSelectElement).value as OperatingMode)}><option value="online">Online</option><option value="restricted-online">Restricted Online</option><option value="strict-offline">Strict Offline</option></select></label>
      </Tooltip>
      <span class="badge success"><span class="dot"></span>{status}</span>
      <Tooltip text="Open contextual help and frequently asked questions"><button class="btn icon ghost" aria-label="Open help" onclick={help}><HelpCircle size={18}/></button></Tooltip>
      <Tooltip text="Choose System, Light, or Dark appearance"><ThemeSelector/></Tooltip>
    </div>
  </header>
  {#if mobileOpen}<button class="overlay mobile-only" style="display:block;border:0" aria-label="Close navigation" onclick={()=>mobileOpen=false}></button>{/if}
  <aside class:mobile-open={mobileOpen} class="sidebar" aria-label="Primary navigation">
    <div class="mobile-only" style="position:absolute;top:14px;right:12px"><button class="btn icon ghost" aria-label="Close navigation" onclick={()=>mobileOpen=false}><X size={18}/></button></div>
    <nav class="nav-list">
      {#each nav as item}
        <Tooltip text={item.description}>
          <button class:active={active===item.id} class="nav-button" aria-current={active===item.id?"page":undefined} onclick={()=>choose(item.id)}>
            <item.icon size={18}/><span class="nav-label">{item.label}</span>{#if item.badge!==undefined&&!collapsed}<span class="badge" style="margin-left:auto">{item.badge}</span>{/if}
          </button>
        </Tooltip>
      {/each}
    </nav>
    <div class="sidebar-footer desktop-only">
      <Tooltip text={collapsed?"Expand navigation":"Collapse navigation"}>
        <button class="nav-button" aria-label={collapsed?"Expand navigation":"Collapse navigation"} onclick={()=>collapsed=!collapsed}>
          {#if collapsed}<ChevronRight size={18}/>{:else}<ChevronLeft size={18}/>{/if}<span class="sidebar-footer-label">Collapse</span>
        </button>
      </Tooltip>
    </div>
  </aside>
  <main class="main">{@render children()}</main>
</div>
