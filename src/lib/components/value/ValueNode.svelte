<script module>
  export type ValueNodeType = Node<Value & { label?: string }, 'value'>;
</script>

<script lang="ts">
  import ValueComponent from './Value.svelte';
  import { type Value } from './Value.svelte';
  import { type NodeProps, type Node } from '@xyflow/svelte';

  let { id, data }: NodeProps<ValueNodeType> = $props();
</script>

<div class="value-node">
  {#if data.label}
    <div class="value-node-label">{data.label}</div>
  {/if}

  <ValueComponent {id} {data} />
</div>

<style>
  .value-node {
    padding: 10px;
    border: 2px solid #222138;
    border-radius: 8px;
    background-color: #f9f9f9;
    box-shadow:
      0 1px 3px rgba(0, 0, 0, 0.2),
      0 1px 2px rgba(0, 0, 0, 0.14),
      0 2px 1px -1px rgba(0, 0, 0, 0.12);
    font-family: Arial, sans-serif;
    font-size: 14px;
    text-align: center;
    min-width: 80px;
    position: relative;
  }

  .value-node-label {
    position: absolute;
    font-size: 12px;
    top: -20px;
  }
</style>
