<script lang="ts">
  import { onMount } from 'svelte';
  import { createLayout } from '$lib/layout/index.svelte';

  const layout = createLayout({
    width: 1200,
    height: 800
  });

  const array = layout.addNode({ width: 300, height: 200 });

  const elem1 = array.addNode({ width: '$w', height: 100, y: '$y' });
  const elem2 = array.addNode({ width: '$w', height: 100, y: '$y' });
  const elem3 = array.addNode({ width: '$w', height: 100, y: '$y' });

  layout.constraint.disjoint(elem1, elem2);
  layout.constraint.disjoint(elem1, elem3);
  layout.constraint.disjoint(elem2, elem3);

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
  <button class="solve-button" on:click={() => layout.solve()}>Solve</button>
  <div class="canvas" style:position="relative">
    {#each layout.views as view (view.nodeId)}
      <div class="node" id={view.nodeId} style={css(view.style)}>{view.nodeId}</div>
    {/each}
  </div>
</div>

<style>
  .node {
    position: absolute;
    border: 3px solid black;
  }

  .solve-button {
    width: 100px;
    height: 30px;
    background-color: lightblue;
    margin-bottom: 10px;
  }
</style>
