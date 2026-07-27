<script lang="ts">
  import { AlertTriangle, X } from "lucide-svelte";
  import { tick } from "svelte";
  let { open = $bindable(), title, message, confirmLabel = "Confirm", tone = "danger", onconfirm }: {
    open: boolean; title: string; message: string; confirmLabel?: string; tone?: "danger"|"primary"; onconfirm: () => void|Promise<void>;
  } = $props();
  let cancel = $state<HTMLButtonElement>();
  $effect(() => { if(open) tick().then(() => cancel?.focus()); });
  async function confirm(){ await onconfirm(); open=false; }
</script>
{#if open}
  <div class="overlay" role="presentation" onclick={(e)=>e.target===e.currentTarget&&(open=false)} onkeydown={(e)=>e.key==="Escape"&&(open=false)}>
    <div class="dialog" role="alertdialog" aria-modal="true" aria-labelledby="confirm-title" aria-describedby="confirm-message">
      <div class="dialog-header"><div><h2 id="confirm-title"><AlertTriangle size={19} style="vertical-align:-4px;margin-right:7px;color:var(--warning)"/>{title}</h2></div><button class="btn icon ghost" aria-label="Close" onclick={()=>open=false}><X size={18}/></button></div>
      <div class="dialog-body"><p id="confirm-message" class="muted" style="margin:0">{message}</p></div>
      <div class="dialog-footer"><button bind:this={cancel} class="btn" onclick={()=>open=false}>Cancel</button><button class:danger={tone==="danger"} class:primary={tone==="primary"} class="btn" onclick={confirm}>{confirmLabel}</button></div>
    </div>
  </div>
{/if}
