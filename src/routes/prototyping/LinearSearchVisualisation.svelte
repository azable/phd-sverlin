<script lang="ts">
  import { Badge } from '$lib/client/components/ui/badge';

  import StepControls from './StepControls.svelte';

  /** Sequence scanned from index 0 upwards. */
  let values = $state([14, 3, 27, 8, 41, 19, 6, 33, 22, 11]);
  /** Value the search is looking for. */
  let target = $state(19);

  /** Index the scan is comparing; -1 before it starts, values.length once it runs out. */
  let cursor = $state(-1);
  /** Whether the value at the cursor is the target. */
  let matched = $state(false);

  /** Step selected by the controls; -1 before the scan starts. */
  let stepIndex = $state(-1);

  const matchAt = $derived(values.indexOf(target));
  /** One step per comparison, plus a closing step when the target is absent. */
  const stepCount = $derived(matchAt >= 0 ? matchAt + 1 : values.length + 1);

  /** The scan itself: every yield hands control back with the comparison state written. */
  function* scanForTarget(): Generator<void> {
    for (const [index, value] of values.entries()) {
      cursor = index;
      matched = value === target;
      yield;
      if (matched) return;
    }
    cursor = values.length;
    matched = false;
    yield;
  }

  let scan = scanForTarget();
  let yielded = 0;

  function rewind() {
    scan = scanForTarget();
    yielded = 0;
    cursor = -1;
    matched = false;
  }

  /** Run the scan forward to the selected step, restarting it when the selection moves back. */
  $effect(() => {
    const wanted = stepIndex + 1;
    if (wanted < yielded) rewind();
    while (yielded < wanted && !scan.next().done) yielded += 1;
  });

  const started = $derived(cursor >= 0);
  const exhausted = $derived(cursor >= values.length);
  const comparisons = $derived(Math.min(cursor + 1, values.length));

  /** The view reads the comparison state and says what it means. */
  const status = $derived.by(() => {
    if (!started) return `Ready to scan ${values.length} values for ${target}.`;
    if (matched) return `Found ${target} at index ${cursor}.`;
    if (exhausted) return `${target} is not in the sequence.`;
    return `Index ${cursor}: ${values[cursor]} is not ${target}, continue.`;
  });

  /** Cell appearance follows the comparison: untouched, settled, inspected, or matched. */
  function cellClass(index: number) {
    if (matched && index === cursor) {
      return 'border-status-success bg-status-success text-status-success-foreground';
    }
    if (index === cursor) return 'border-primary bg-primary text-primary-foreground';
    if (index < cursor) return 'border-border bg-muted text-muted-foreground';
    return 'border-border bg-card text-card-foreground';
  }
</script>

<section class="flex flex-col gap-4">
  <header class="flex flex-wrap items-center gap-3">
    <h2 class="mr-auto text-lg font-medium">Linear search</h2>
    <Badge variant="outline">target {target}</Badge>
    <Badge variant="outline">{comparisons} comparison{comparisons === 1 ? '' : 's'}</Badge>
  </header>

  <ol class="flex flex-wrap gap-2">
    {#each values as value, index (index)}
      <li class="flex flex-col items-center gap-1">
        <span
          class="flex h-12 w-12 items-center justify-center rounded-md border font-mono text-sm transition-colors {cellClass(
            index
          )}"
        >
          {value}
        </span>
        <span class="text-xs text-muted-foreground">{index}</span>
      </li>
    {/each}
  </ol>

  <p class="text-sm text-muted-foreground" aria-live="polite">{status}</p>

  <StepControls {stepCount} bind:index={stepIndex} />
</section>
