<script lang="ts">
  import { createLayout } from '$lib/layout/index.svelte';

  const config = $state({
    width: 1200,
    height: 800,
    unitSize: 20
  });

  const layout = createLayout(config);
  const { global } = layout;

  const int = (value: number) => {
    const intsize = global.uniform('intsize');
    layout.constraint.minimize(intsize);

    return layout
      .createNode({
        width: intsize,
        height: intsize,
        fontSize: 40,
        backgroundColor: 'lightblue',
        border: '2px solid black',
        borderRadius: '10px',
        zIndex: 10
      })
      .setContent(value.toString());
  };

  const intVar = (name: string) => {
    const intVarSize = global.uniform('intvarsize');
    const x = global.uniform();
    layout.constraint.minimize(intVarSize);

    const container = layout.createNode({
      width: intVarSize,
      height: intVarSize
    });

    const label = layout
      .createNode({
        width: intVarSize,
        left: x,
        fontSize: 30
      })
      .setContent(name);

    const slot = layout.createNode({
      width: global.uniform('intsize'),
      height: global.uniform('intsize'),
      left: x,
      backgroundColor: 'grey',
      border: '2px solid black',
      borderRadius: '10px'
    });

    layout.constraint.contains(container, label);
    layout.constraint.contains(container, slot);

    layout.constraint.above(label, slot, 0);

    return slot;
  };

  // const array = (size: number) => {
  //   const awidth = global.uniform('awidth');
  //   const aheight = global.uniform('aheight');

  //   layout.constraint.minimize(awidth);
  //   layout.constraint.minimize(aheight);

  //   const arrayNode = layout.createNode({
  //     width: awidth,
  //     height: aheight,
  //     backgroundColor: 'lightgray',
  //     borderRadius: '10px',
  //     outline: '20px solid lightgray',
  //     zIndex: 2
  //   });

  //   layout.constraint.centerX(layout.root, arrayNode);
  //   layout.constraint.contains(layout.root, arrayNode);

  //   const nodes = Array.from({ length: size }, () =>
  //     layout.createNode({
  //       top: global.uniform(),
  //       left: global.uniform()
  //     })
  //   );

  //   for (let i = 0; i < size; i++) {
  //     if (i !== size - 1) {
  //       layout.constraint.adjacentX(nodes[i], nodes[i + 1], 20);
  //     }
  //     layout.constraint.contains(arrayNode, nodes[i]);
  //   }
  //   return nodes;
  // };

  const value = int(1);
  const my_var = intVar('A');

  // const array1 = array(3);

  // layout.step();

  // layout.constraint.assign(my_var, value);

  // layout.constraint.assign(array1[0], value1);
  // layout.constraint.assign(array1[1], value2);
  // layout.constraint.assign(array1[2], value3);

  // layout.step();

  // layout.constraint.assign(array1[0], value1);
  // layout.constraint.assign(array1[1], value3);
  // layout.constraint.assign(array1[2], value2);

  // layout.step();

  // layout.constraint.assign(array1[0], value2);
  // layout.constraint.assign(array1[1], value3);
  // layout.constraint.assign(array1[2], value1);

  let currStep = $state(0);

  const nextStep = () => {
    console.log('Next step');
    currStep++;
  };

  const prevStep = () => {
    console.log('Previous step');
    currStep--;
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
  <button class="solve-button" onclick={() => prevStep()} disabled={currStep === 0}>Previous</button
  >
  <button class="solve-button" onclick={() => nextStep()} disabled={currStep === layout.timeSteps}
    >Next</button
  >
  <div
    class="canvas"
    style:opacity={layout.ready ? 1 : 0}
    style:position="relative"
    style:width="{config.width}px"
    style:height="{config.height}px"
    style:background-size="{config.unitSize}px {config.unitSize}px"
  >
    {#each layout.views[currStep] as view (view.nodeId)}
      <div class="node" id={view.nodeId} style={css(view.style)}>
        {#if view.content}
          <div
            class="node-content"
            bind:clientWidth={view.content.clientWidth}
            bind:clientHeight={view.content.clientHeight}
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

  .solve-button:disabled {
    background-color: gray;
  }
</style>
