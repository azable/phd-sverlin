/** Authored source starter and editor identity for the Svelte-backed mode. */

export const sverlinStarter = {
  path: 'Main.svelte',
  language: 'svelte',
  mediaType: 'text/x-svelte',
  source:
    '<script lang="sverlin">\n  yield "Start";\n</script>\n<main><h1>Start your visualization</h1><p>Step {step + 1} · seed {seed}</p></main>\n'
} as const;

/** A small self-contained algorithm example for administrator projects. */
export const linearSearchSource = `<script lang="sverlin" domain>
  const Int = type('integer');
</script>
<script lang="sverlin" input>
  const values = [Int(3), Int(8), Int(5), Int(2), Int(7)];
  const target = Int(2);
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
  const intShape = pick(['box', 'circle']);
  const flow = pick(['row', 'column']);
  const showIndices = chance(0.5);
  const pointerName = pick(['i', 'index']);
  const font = pick(['sans', 'serif']);
  const textSize = pick(['medium', 'large']);
  const current = pick(['amber', 'red']);
</script>
{#snippet Int(value, node)}
  <Node shape={intShape} {value} {...node} />
{/snippet}
<Stage title="Linear search" subtitle="Find {target} by checking each cell in order.">
  <Node items={values} layout={flow}>
    {#snippet item(value, index, type)}
      <Node layout="column">
        {@const colour = index === i ? (found ? 'green' : current) : index < i ? 'blue' : undefined}
        {#if showIndices}<Node size="small">{index}</Node>{/if}
        <Node {value} {type} fill={colour} stroke={colour} />
        {#if index === i}<Node size="small">{pointerName}</Node>{/if}
      </Node>
    {/snippet}
  </Node>
  <Node
    shape="card"
    fill={found ? 'green' : undefined}
    stroke={found ? 'green' : undefined}
    {font}
    size={textSize}
  >
    {#if i < 0}Start at the first cell.{:else if found}Found {target} at index {i}.{:else if i < values.length}{values[i]} is not {target}; move right.{:else}{target} is not in the array.{/if}
  </Node>
</Stage>`;
