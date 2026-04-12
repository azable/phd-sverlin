<script module>
  export type ArrayNodeType = Node<{ labels: string[] }, 'array'>;
</script>

<script lang="ts">
  import type { NodeProps, Node } from '@xyflow/svelte';
  import { useUpdateNodeInternals } from '@xyflow/svelte';

  let { id, data }: NodeProps<ArrayNodeType> = $props();

  const updateNodeInternals = useUpdateNodeInternals();

  let cellW = $state(0);
  let ready = $state(false);

  function measureRow(node: HTMLDivElement) {
    const measure = () => {
      const items = Array.from(node.querySelectorAll<HTMLElement>('.array-element'));
      if (!items.length) return;

      const max = Math.max(...items.map((el) => el.scrollWidth));

      cellW = Math.ceil(max);
      ready = true;

      updateNodeInternals(id);
    };

    measure();

    const ro = new ResizeObserver(measure);
    ro.observe(node);

    return {
      destroy() {
        ro.disconnect();
      }
    };
  }
</script>

<div class="array-node" style={`--cell-w:${cellW}px`}>
  <div class="array-elements" class:fixed={ready} class:ready use:measureRow>
    {#each data.labels as label}
      <div class="array-element">{label}</div>
    {/each}
  </div>
</div>

<style>
  .array-node {
    text-align: center;
  }

  .array-elements {
    border: 2px solid #222138;
    border-radius: 8px;
    background-color: #f0f0f0;
    display: inline-flex;
    width: max-content;
    flex-direction: row;

    visibility: hidden;
  }

  .array-elements.ready {
    visibility: visible;
  }

  .array-element {
    flex: 0 0 auto;
    padding: 10px 16px;
    border-left: 2px solid #222138;
    box-sizing: border-box;
    white-space: nowrap;
  }

  .array-elements.fixed .array-element {
    width: var(--cell-w);
  }

  .array-element:first-child {
    border-left: none;
  }
</style>
