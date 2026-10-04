/** Authored source starter and editor identity for the Svelte-backed mode. */

export const sverlinStarter = {
  path: 'Main.svelte',
  language: 'svelte',
  mediaType: 'text/x-svelte',
  source:
    '<script module>export const steps = ["Start"];</script>\n<script>let { step = 0, seed = 1 } = $props();</script>\n<main><h1>Start your visualization</h1><p>Step {step + 1} · seed {seed}</p></main>\n'
} as const;

/** A small self-contained algorithm example for administrator projects. */
export const linearSearchSource = `<script module>export const steps = ['Start', 'Compare', 'Result'];</script>
<script>
  let { step = 0, seed = 1 } = $props();
  const values = [3, 8, 5, 2, 7];
  const target = values[seed % values.length];
  const match = values.indexOf(target);
  const states = values.map((_, index) =>
    step === 0 || index > match ? 'idle' : index < match ? 'visited' : step === 1 ? 'active' : 'found'
  );
</script>
<Stage title="Linear search" subtitle="Find {target} by checking each cell in order.">
  <ArrayCells {values} {states} pointers={step === 0 ? {} : { i: match }} />
  <Note tone={step === 2 ? 'success' : 'info'}>
    {#if step === 0}Start at the first cell.{:else if step === 1}Compare cells left to right until one equals {target}.{:else}Found {target} at index {match}.{/if}
  </Note>
</Stage>`;
