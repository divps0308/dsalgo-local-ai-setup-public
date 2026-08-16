<script lang="ts">
  import { Monitor, Moon, Sun, Sparkles, Layers3, Factory } from "lucide-svelte";
  import { applyTheme, initialTheme } from "./theme";
  import type { ThemeMode } from "./types";
  let mode: ThemeMode = $state("system");
  let open = $state(false);
  const options = [
    { value: "system" as const, label: "System", icon: Monitor },
    { value: "light" as const, label: "Light", icon: Sun },
    { value: "dark" as const, label: "Dark", icon: Moon },
    { value: "art" as const, label: "Art", icon: Sparkles },
    { value: "material" as const, label: "Material", icon: Layers3 },
    { value: "industrial" as const, label: "Industrial", icon: Factory }
  ];
  $effect(() => {
    mode = initialTheme();
    applyTheme(mode);
    const media = matchMedia("(prefers-color-scheme: dark)");
    const listener = () => mode === "system" && applyTheme("system");
    media.addEventListener("change", listener);
    return () => media.removeEventListener("change", listener);
  });
  function choose(value: ThemeMode) { mode = value; applyTheme(value); open = false; }
</script>

<div style="position:relative">
  <button class="btn icon ghost" aria-label="Choose color theme" aria-expanded={open} onclick={() => open = !open}>
    {#if mode === "light"}<Sun size={18}/>{:else if mode === "dark"}<Moon size={18}/>{:else if mode === "art"}<Sparkles size={18}/>{:else if mode === "material"}<Layers3 size={18}/>{:else if mode === "industrial"}<Factory size={18}/>{:else}<Monitor size={18}/>{/if}
  </button>
  {#if open}
    <div class="theme-menu" role="menu">
      {#each options as option}
        <button role="menuitemradio" aria-checked={mode === option.value} class:active={mode === option.value} onclick={() => choose(option.value)}>
          <option.icon size={16}/><span>{option.label}</span>
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .theme-menu{position:absolute;right:0;top:48px;z-index:70;width:170px;padding:5px;background:var(--surface-elevated);border:1px solid var(--border);border-radius:10px;box-shadow:var(--shadow-md)}
  .theme-menu button{width:100%;height:38px;border:0;border-radius:7px;background:transparent;color:var(--text-secondary);display:flex;align-items:center;gap:9px;padding:0 10px;cursor:pointer}
  .theme-menu button:hover,.theme-menu button.active{background:var(--accent-soft);color:var(--accent)}
</style>
