/** Authored source starter and editor identity for the Svelte-backed mode. */

export const sverlinStarter = {
  path: 'Main.svelte',
  language: 'svelte',
  mediaType: 'text/x-svelte',
  source:
    '<script lang="sverlin">\n  yield "Start";\n</script>\n<main><h1>Start your visualization</h1><p>Step {step + 1} · seed {seed}</p></main>\n'
} as const;

/** A small self-contained algorithm example for administrator projects. */
export const linearSearchSource = `<script lang="sverlin" input>
  const values = [3, 8, 5, 2, 7];
  const target = 2;
</script>
<script lang="sverlin">
  let i = -1;
  let found = false;
  yield 'Start';
  for (i = 0; i < values.length; i++) {
    if (values[i] === target) {
      found = true;
      yield \`Found \${target} at index \${i}\`;
      break;
    }
    yield \`Compare index \${i}\`;
  }
  if (!found) yield 'Not found';
</script>
<script lang="sverlin" design>
  const showIndices = chance(0.5);
  const pointerName = pick(['i', 'index']);
</script>
<Stage title="Linear search" subtitle="Find {target} by checking each cell in order.">
  {@const states = values.map((_, index) =>
    index < i ? 'visited' : index === i ? (found ? 'found' : 'active') : 'idle'
  )}
  <ArrayCells {values} {states} indices={showIndices} pointers={i < 0 ? {} : { [pointerName]: i }} />
  <Note tone={found ? 'success' : 'info'}>
    {#if i < 0}Start at the first cell.{:else if found}Found {target} at index {i}.{:else if i < values.length}{values[i]} is not {target}; move right.{:else}{target} is not in the array.{/if}
  </Note>
</Stage>`;
