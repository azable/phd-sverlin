<script lang="ts">
  import { onMount } from 'svelte';
  import { createLayout } from '$lib/layout/index.svelte';

  const layout = createLayout([
    { id: 'elem1', style: { width: 100, height: 100 } },
    { id: 'elem2', style: { width: 100, height: 100 } }
  ]);

  // layout.constraint.nonOverlapping(['elem1', 'elem2']);

  onMount(async () => {
    await layout.solve();
  });

  const css = (style: Record<string, string>): string => {
    console.log(style);
    return Object.entries(style)
      .filter(([, value]) => value !== null && value !== undefined)
      .map(([key, value]) => `${key}: ${value}`)
      .join('; ');
  };
</script>

<div style:width="100vw" style:height="100vh">
  {#each layout.views as view (view.nodeId)}
    <div class="node" id={view.nodeId} style={css(view.style)}></div>
  {/each}
</div>

<style>
  .node {
    position: absolute;
    border: 3px solid black;
  }
</style>
