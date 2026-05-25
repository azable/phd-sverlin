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
      .createNode({
        width: '$isize',
        height: '$isize',
        fontSize: 40,
        backgroundColor: 'lightblue',
        border: '2px solid black',
        borderRadius: '10px',
        zIndex: 10
      })
      .setContent(value.toString());
  };

  const array = (nodes: Node[]): Node => {
    const arrayNode = layout.createNode({
      width: '?<',
      height: '?<',
      backgroundColor: 'lightgray',
      borderRadius: '10px',
      outline: '20px solid lightgray',
      zIndex: 2
    });

    for (let i = 0; i < nodes.length; i++) {
      if (i !== nodes.length - 1) {
        layout.constraint.adjacentX(nodes[i], nodes[i + 1], 20);
      }
      layout.constraint.contains(arrayNode, nodes[i]);
    }
    return arrayNode;
  };

  const value1 = int(1);
  const value2 = int(5);
  const value3 = int(10);

  const array1 = array([value1, value2, value3]);

  layout.constraint.centerX(layout.root, array1);
  layout.constraint.contains(layout.root, array1);

  const nextStep = () => {
    console.log('>>> Next step', array1);
    // array1.children[0].children = [];
    // array1.children[0].addChild(int(2));
  };

  const recomputeLayout = async () => {
    await layout.solve();
  };

  const css = (style: Record<string, string>): string => {
    return Object.entries(style)
      .filter(([, value]) => value !== null && value !== undefined)
      .map(([key, value]) => `${key}: ${value}`)
      .join('; ');
  };

  $effect(() => console.log(layout.views));
</script>

<div class="page" style:width="100vw" style:height="100vh">
  <button class="solve-button" onclick={() => recomputeLayout()}>Solve</button>
  <button class="solve-button" onclick={() => nextStep()}>Next Step</button>
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
            class="node-content"
            bind:clientWidth={view.content.clientWidth.value}
            bind:clientHeight={view.content.clientHeight.value}
          >
            {view.content.text.value}
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
    /* background-image:
      linear-gradient(to right, #999 1px, transparent 1px),
      linear-gradient(to bottom, #999 1px, transparent 1px); */
  }

  .node {
    position: absolute;
    display: flex;
    justify-content: center;
    align-items: center;
    /* border: 3px solid black; */
  }

  .node-content {
    user-select: none;
  }

  .solve-button {
    width: 100px;
    height: 30px;
    background-color: lightblue;
    margin-bottom: 10px;
  }
</style>
