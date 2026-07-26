<script lang="ts">
  import { ChevronDown, HelpCircle, Search, X } from "lucide-svelte";
  import { tick } from "svelte";
  import type { HelpTopic } from "./types";
  let { open = $bindable(), topics, context = "" }: { open: boolean; topics: HelpTopic[]; context?: string } = $props();
  let query = $state("");
  let closeButton = $state<HTMLButtonElement>();
  let filtered = $derived(topics.filter((topic) => {
    const search = `${topic.title} ${topic.section} ${topic.body}`.toLowerCase();
    return (!context || topic.section === context || topic.section === "General") && search.includes(query.toLowerCase());
  }));
  $effect(() => {
    if (open) tick().then(() => closeButton?.focus());
  });
  function keydown(event: KeyboardEvent) {
    if (event.key === "Escape") open = false;
    if (event.key === "Tab") {
      const drawer = document.querySelector(".help-drawer");
      const controls = Array.from(drawer?.querySelectorAll<HTMLElement>('button,input,[href],summary,[tabindex]:not([tabindex="-1"])') ?? []);
      if (!controls.length) return;
      const first = controls[0], last = controls[controls.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  }
</script>

{#if open}
  <div class="overlay" role="presentation" onclick={(e) => e.target === e.currentTarget && (open = false)} onkeydown={keydown}>
    <div class="help-drawer" role="dialog" aria-modal="true" aria-label="Help and frequently asked questions">
      <div class="help-header">
        <div><h2><HelpCircle size={19} style="vertical-align:-4px;margin-right:7px"/>Help center</h2><p class="muted" style="margin:0">Guidance for this local tool</p></div>
        <button bind:this={closeButton} class="btn icon ghost" aria-label="Close help" onclick={() => open=false}><X size={18}/></button>
      </div>
      <div class="help-content">
        <div class="field" style="margin-bottom:14px">
          <label for="help-search">Search help</label>
          <div style="position:relative"><Search size={16} style="position:absolute;left:12px;top:14px;color:var(--text-muted)"/><input id="help-search" style="padding-left:36px" bind:value={query} placeholder="Search topics"/></div>
        </div>
        {#each filtered as topic}
          <details class="faq" open={topic.section === context && !query}>
            <summary>{topic.title}<ChevronDown size={16}/></summary>
            <p>{topic.body}</p>
          </details>
        {:else}
          <div class="empty">No help topics match your search.</div>
        {/each}
      </div>
    </div>
  </div>
{/if}
