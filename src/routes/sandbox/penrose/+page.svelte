<script lang="ts">
  import { onMount } from 'svelte';
  import { createLayout } from '$lib/layout/index.svelte';

  const layout = createLayout({
    rootWidth: 800,
    rootHeight: 600
  });

  layout.addNode('elem1', { width: 100, height: 100 });
  layout.addNode('elem2', { width: 100, height: 100 });
  // layout.addNode('elem3', { width: 100, height: 100 });

  layout.constraint.disjoint('elem1', 'elem2');
  // layout.constraint.disjointBounds('elem1', 'elem3');
  // layout.constraint.disjointBounds('elem2', 'elem3');

  onMount(async () => {
    await layout.solve();
    console.log(layout.views);
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
    <div class="node" id={view.nodeId} style={css(view.style)}>{view.nodeId}</div>
  {/each}
</div>

<style>
  .node {
    position: absolute;
    border: 3px solid black;
  }
</style>
