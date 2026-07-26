<script lang="ts">
  let { text, children }: { text: string; children: import("svelte").Snippet } = $props();
  const id = `tip-${Math.random().toString(36).slice(2)}`;
</script>

<span class="tooltip-wrap">
  <span aria-describedby={id}>{@render children()}</span>
  <span class="tooltip" role="tooltip" {id}>{text}</span>
</span>
