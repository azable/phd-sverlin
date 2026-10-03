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
</script>
<main>
  <h1>Linear search</h1>
  <p>Find {target} in the array by checking each cell in order.</p>
  <div class="cells">
    {#each values as value, index (index)}
      <span class:active={step > 0 && index <= match} class:found={step === 2 && index === match}>{value}</span>
    {/each}
  </div>
  <p>{steps[step] ?? steps[0]}</p>
</main>
<style>
  main { padding: 2rem; font-family: system-ui, sans-serif; }
  .cells { display: flex; flex-wrap: wrap; gap: 1rem; }
  span { display: grid; place-items: center; width: 3rem; height: 3rem; border: 1px solid #334155; border-radius: .5rem; }
  .active { background: #dbeafe; }
  .found { background: #bbf7d0; }
</style>`;
