<script lang="ts">
  import LayoutNode from '$lib/layout/components/LayoutNode.svelte';
  import { createLayout } from '$lib/layout/index.svelte';
  import { minimize } from '$lib/layout/constraints.svelte';

  const config = $state({
    width: 1200,
    height: 800,
    unitSize: 20
  });

  const layout = await createLayout(config);
  const { step, variable } = layout;

  const intsize = variable('intsize').constraint(minimize);

  const int = {
    width: intsize,
    height: intsize,
    backgroundColor: 'lightblue',
    border: '2px solid black',
    borderRadius: '10px',
    fontSize: 40,
    zIndex: 10
  };

  const op = {
    width: intsize,
    height: intsize,
    backgroundColor: 'lightcoral',
    border: '2px solid black',
    borderRadius: '10px',
    fontSize: 30,
    zIndex: 10
  };

  const [v1] = await step([], [[int, '1']]);

  const [v2] = await step([], [[int, '2']]);

  const [v3] = await step([], [[op, '+']]);

  await step([v1, v2, v3], [[int, '3']]);

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
    currStep = 0;
    await layout.solve();
  };

  await recomputeLayout();
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
    style:position="relative"
    style:width="{config.width}px"
    style:height="{config.height}px"
    style:background-size="{config.unitSize}px {config.unitSize}px"
  >
    {#each layout.views[currStep] as view (view.nodeId)}
      <LayoutNode id={view.nodeId} {view} />
    {/each}
  </div>
</div>

<style>
  .page {
    background-color: rgb(30, 30, 30);
  }

  .canvas {
    background-color: rgb(220, 220, 220);
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
