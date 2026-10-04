/** Authored source starter and editor identity for the Svelte-backed mode. */

export const sverlinStarter = {
  path: 'Main.svelte',
  language: 'svelte',
  mediaType: 'text/x-svelte',
  source:
    '<script module>export const steps = ["Start"];</script>\n<script>let { step = 0, seed = 1 } = $props();</script>\n<main><h1>Start your visualization</h1><p>Step {step + 1} · seed {seed}</p></main>\n'
} as const;

/** A small self-contained algorithm example for administrator projects. */
export const linearSearchSource = `<script lang="sverlin">
  const values = [3, 8, 5, 2, 7];
  const target = 2;
  let i = -1;
  let found = false;
  yield 'Start';
  for (i = 0; i < values.length; i++) {
    yield \`Compare \${values[i]}\`;
    if (values[i] === target) {
      found = true;
      yield \`Found \${target}\`;
      break;
    }
  }
</script>
<script>
  let { values, target, i, found } = $props();
  const states = values.map((_, index) =>
    index < i ? 'visited' : index === i ? (found ? 'found' : 'active') : 'idle'
  );
</script>
<Stage title="Linear search" subtitle="Find {target} by checking each cell in order.">
  <ArrayCells {values} {states} pointers={i < 0 ? {} : { i }} />
  <Note tone={found ? 'success' : 'info'}>
    {#if i < 0}Start at the first cell.{:else if found}Found {target} at index {i}.{:else}Compare {values[i]} with {target}.{/if}
  </Note>
</Stage>`;
