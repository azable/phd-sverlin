<!-- One row of array cells with per-cell states and named index pointers. -->
<script lang="ts">
  import type { CellState } from './types';

  let {
    values,
    states = [],
    pointers = {},
    indices = true,
    label
  }: {
    values: readonly (string | number)[];
    states?: readonly CellState[];
    pointers?: Readonly<Record<string, number>>;
    indices?: boolean;
    label?: string;
  } = $props();

  const pointerLabels = $derived(
    values.map((_, index) =>
      Object.entries(pointers)
        .filter(([, at]) => at === index)
        .map(([name]) => name)
    )
  );
</script>

<figure class="sv-array">
  {#if label}<figcaption>{label}</figcaption>{/if}
  <div class="cells">
    {#each values as value, index (index)}
      <div class="cell {states[index] ?? 'idle'}">
        {#if indices}<span class="index">{index}</span>{/if}
        <span class="value">{value}</span>
        {#if pointerLabels[index].length > 0}
          <span class="pointer">{pointerLabels[index].join(', ')}</span>
        {/if}
      </div>
    {/each}
  </div>
</figure>

<style>
  .sv-array {
    margin: 0;
  }
  figcaption {
    margin-bottom: 0.75rem;
    color: var(--sv-muted);
    font-size: 0.875rem;
  }
  .cells {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    padding-bottom: 1.5rem;
  }
  .cell {
    position: relative;
    display: grid;
    place-items: center;
    width: 3.5rem;
    height: 3.5rem;
    border: 2px solid var(--sv-line);
    border-radius: var(--sv-radius);
    background: var(--sv-surface);
  }
  .active {
    border-color: var(--sv-active-line);
    background: var(--sv-active);
  }
  .visited {
    border-color: var(--sv-visited-line);
    background: var(--sv-visited);
  }
  .found {
    border-color: var(--sv-found-line);
    background: var(--sv-found);
  }
  .muted {
    opacity: 0.4;
  }
  .index {
    position: absolute;
    top: 0.2rem;
    left: 0.35rem;
    color: var(--sv-muted);
    font-size: 0.65rem;
  }
  .value {
    font-size: 1.25rem;
    font-weight: 700;
  }
  .pointer {
    position: absolute;
    top: calc(100% + 0.3rem);
    color: var(--sv-muted);
    font-size: 0.7rem;
    font-weight: 700;
    white-space: nowrap;
  }
</style>
