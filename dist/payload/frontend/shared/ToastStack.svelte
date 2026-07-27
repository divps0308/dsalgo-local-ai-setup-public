<script lang="ts">
  import { CircleAlert, CircleCheck, Info, TriangleAlert, X } from "lucide-svelte";
  import type { ToastMessage } from "./types";
  let { messages = $bindable() }: { messages: ToastMessage[] } = $props();
  const icon = { success: CircleCheck, danger: CircleAlert, warning: TriangleAlert, info: Info, neutral: Info };
</script>
<div class="toast-stack" aria-live="polite" aria-atomic="false">
  {#each messages as toast (toast.id)}
    {@const Icon = icon[toast.tone]}
    <div class="toast {toast.tone}" role="status">
      <div style="display:flex;align-items:flex-start;gap:10px">
        <Icon size={18} style="margin-top:2px"/>
        <div style="flex:1"><strong>{toast.title}</strong>{#if toast.message}<div class="muted" style="font-size:12px;margin-top:2px">{toast.message}</div>{/if}</div>
        <button class="btn icon ghost" style="width:28px;min-height:28px" aria-label="Dismiss notification" onclick={()=>messages=messages.filter(m=>m.id!==toast.id)}><X size={14}/></button>
      </div>
    </div>
  {/each}
</div>
