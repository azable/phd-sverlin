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
    nodes.forEach((node) => arrayNode.addChild(node));
    for (let i = 0; i < nodes.length - 1; i++) {
      layout.constraint.adjacentX(nodes[i], nodes[i + 1], 20);
    }
    return arrayNode;
  };

  const array1 = array([int(1), int(5), int(2), int(1), int(33), int(10), int(2)]);
  const array2 = array([int(10), int(11), int(12), int(13)]);

  layout.constraint.centerX(array1);
  layout.constraint.centerX(array2);

  layout.constraint.disjoint(array1, array2);

  const nextStep = () => {
    // let tmp = value1.children[2].children[0];
    // console.log('>>> Swapping', tmp, 'with', value1.children[3].children[0]);
    // value1.children[2].children[0] = value1.children[3].children[0];
    // value1.children[3].children[0] = tmp;
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
