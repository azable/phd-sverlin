<script lang="ts">
  import { createLayout, type Node } from '$lib/layout/index.svelte';

  const config = $state({
    width: 1200,
    height: 800,
    unitSize: 20
  });

  const layout = createLayout(config);

  const int = (value: number, parent: Node = layout.root): Node => {
    return parent
      .addNode({
        width: '$isize',
        height: '$isize',
        fontSize: 40,
        backgroundColor: 'lightblue',
        border: '2px solid black',
        borderRadius: '10px'
      })
      .setContent(value.toString());
  };

  const arrayOfInts = (values: number[], parent: Node = layout.root): Node => {
    const array = parent.addNode({
      width: '?<',
      height: '?<',
      backgroundColor: 'lightgray',
      borderRadius: '10px',
      outline: '20px solid lightgray'
    });
    let slots = values.map(() => array.addNode());
    slots.forEach((slot, i) => {
      int(values[i], slot);
    });
    for (let i = 0; i < slots.length - 1; i++) {
      layout.constraint.adjacentX(slots[i], slots[i + 1], 20);
    }
    return array;
  };

  const array1 = arrayOfInts([1, 5, 2, 1, 33, 10, 2]);
  const array2 = arrayOfInts([10, 11, 12, 13]);

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
