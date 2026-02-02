<script module>
  export type PrimitiveValue = { type: 'primitive'; value: string | number };
  export type ReferenceValue = { type: 'reference'; value: string };
  export type ObjectValue = { type: 'object'; value: [string, Value][] };
  export type ArrayValue = { type: 'array'; value: Value[] };

  export type Value = PrimitiveValue | ReferenceValue | ObjectValue | ArrayValue;
</script>

<script lang="ts">
  import { Handle, Position, useNodeConnections } from '@xyflow/svelte';
  import Self from './Value.svelte';

  let { id, data }: { id: string; data: Value } = $props();

  const sourceConnections = useNodeConnections({ handleType: 'source', handleId: `${id}-handle` });

  const isConnected = $derived(sourceConnections.current.length > 0);

  const referenceBgColor = $derived(
    data.type === 'reference' && isConnected ? '#FF4000' : 'transparent'
  );
</script>

<div class="value-container">
  {#if data.type === 'primitive'}
    <div class="primitive">
      <div class="primitive-handle">
        <Handle type="target" position={Position.Right} id={`${id}-handle`} />
      </div>
      {data.value}
    </div>
  {:else if data.type === 'reference'}
    <div class="reference">
      <div class="reference-handle">
        <Handle
          style="width:16px; height:16px; background:{referenceBgColor}; border: 0"
          type="source"
          position={Position.Left}
          id={`${id}-handle`}
        />
      </div>
    </div>
  {:else if data.type === 'object'}
    <div class="object-entries">
      {#each data.value as [key, val]}
        <strong>{key}:</strong>
        <Self id={`${id}-${key}`} data={val} />
      {/each}
    </div>
  {:else if data.type === 'array'}
    <div class="array-entries">
      {#each data.value as val, index}
        <Self id={`${id}-${index}`} data={val} />
      {/each}
    </div>
  {/if}
</div>

<style>
  .value-container {
    position: relative;
  }

  .primitive {
    padding: 4px 8px;
    /* border: 1px solid #ccc; */
    border-radius: 4px;
    background-color: #fff;
    display: block;
  }

  .primitive-handle {
    position: absolute;
    top: 50%;
    right: 0px;
    transform: translateY(-50%);
  }

  .reference {
    position: relative;
    top: 50%;
    left: 50%;
    transform: translate(-50%);
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background-color: #999;
  }

  .reference-handle {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    z-index: 11;
  }

  .reference-handle-circle {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    background-color: blue;
    border: none;
    opacity: 0;
  }

  .object-entries {
    display: grid;
    grid-template-columns: 0fr 1fr;
    row-gap: 4px;
    column-gap: 8px;
    align-items: center;
  }

  .object-entries > :nth-child(2n + 1) {
    justify-self: end;
    text-align: right;
  }

  .array-entries {
    display: flex;
    gap: 8px;
  }
</style>
