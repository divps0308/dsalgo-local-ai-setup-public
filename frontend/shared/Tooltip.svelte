<script lang="ts">
  let { text, children }: { text: string; children: import("svelte").Snippet } = $props();
  const id = `tip-${Math.random().toString(36).slice(2)}`;
  let visible = $state(false);
  let position = $state({ left: 8, top: 8 });
  function show(event: PointerEvent) { const rect = (event.currentTarget as HTMLElement).getBoundingClientRect(); position = { left: Math.max(8, Math.min(rect.left + rect.width / 2, window.innerWidth - 140)), top: Math.max(8, rect.top - 10) }; visible = true; }
</script>

<span class="tooltip-wrap" role="group" onpointerenter={show} onpointerleave={() => visible = false} onfocusin={() => visible = true} onfocusout={() => visible = false}>
  <span aria-describedby={visible ? id : undefined}>{@render children()}</span>
  {#if visible}<span class="tooltip" role="tooltip" style={`left:${position.left}px;top:${position.top}px`} {id}>{text}</span>{/if}
</span>