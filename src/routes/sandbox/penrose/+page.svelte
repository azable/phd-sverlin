<script lang="ts">
  import { createLayout, type Node } from '$lib/layout/index.svelte';

  const config = $state({
    width: 1200,
    height: 800,
    unitSize: 20
  });

  const layout = createLayout(config);

  const int = (value: number): Node => {
    return layout
      .addNode({
        width: '$isize',
        height: '$isize',
        fontSize: 30,
        backgroundColor: 'lightblue'
      })
      .setContent(value.toString());
  };

  // const array = layout.addNode();

  // const elem1 = array.addNode({ width: 100, height: 100, y: '$y' });
  // const elem2 = array.addNode({ width: 100, height: 100, y: '$y' });
  // const elem3 = array.addNode({ width: 100, height: 100, y: '$y' });

  const value1 = int(2);
  const value2 = int(3);

  layout.constraint.adjacentX(value1, value2, 20);

  // layout.constraint.adjacentX(elem1, elem2, 20);
  // layout.constraint.adjacentX(elem2, elem3, 20);

  const recomputeLayout = async () => {
    await layout.solve();
  };

  const css = (style: Record<string, string>): string => {
    return Object.entries(style)
      .filter(([, value]) => value !== null && value !== undefined)
      .map(([key, value]) => `${key}: ${value}`)
      .join('; ');
  };
</script>

<div class="page" style:width="100vw" style:height="100vh">
  <button class="solve-button" onclick={() => recomputeLayout()}>Solve</button>
  <div
    class="canvas"
    style:opacity={layout.ready ? 1 : 0}
    style:position="relative"
    style:width="{config.width}px"
    style:height="{config.height}px"
    style:background-size="{config.unitSize}px {config.unitSize}px"
  >
    {#each layout.views as view (view.nodeId)}
      <div class="node" id={view.nodeId} style={css(view.style)}>
        {#if view.content}
          <div
            bind:clientWidth={view.content.clientWidth.value}
            bind:clientHeight={view.content.clientHeight.value}
          >
            {view.content.text}
          </div>
        {/if}
      </div>
    {/each}
  </div>
</div>

<style>
  .page {
    background-color: rgb(30, 30, 30);
  }

  .canvas {
    background-color: rgb(220, 220, 220);
    background-image:
      linear-gradient(to right, #999 1px, transparent 1px),
      linear-gradient(to bottom, #999 1px, transparent 1px);
  }

  .node {
    position: absolute;
    display: flex;
    justify-content: center;
    align-items: center;
    /* border: 3px solid black; */
  }

  .solve-button {
    width: 100px;
    height: 30px;
    background-color: lightblue;
    margin-bottom: 10px;
  }
</style>
