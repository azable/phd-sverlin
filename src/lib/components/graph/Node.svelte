<script lang="ts">
  import { Handle, Position, useConnection, type NodeProps } from '@xyflow/svelte';

  let { id, data }: NodeProps = $props();

  const connection = useConnection();

  let isTarget = $derived(
    connection.current.inProgress && connection.current.fromHandle?.nodeId !== id
  );

  let label = $derived(isTarget ? 'Drop here' : (data.label ?? `Node ${id}`));
</script>

<div class="customNode">
  <div class="customNodeBody">
    <!-- If handles are conditionally rendered and not present initially, you need to update the node internals https://svelteflow.dev/docs/api/hooks/use-update-node-internals/
    In this case we don't need to use useUpdateNodeInternals, since !isConnecting is true at the beginning and all handles are rendered initially. -->
    {#if !connection.current.inProgress}
      <Handle class="customHandle" position={Position.Right} type="source" style="z-index: 1;" />
    {/if}
    <Handle
      class="customHandle"
      position={Position.Left}
      type="target"
      isConnectableStart={false}
    />
    {label}
  </div>
</div>

<style>
  .customNodeBody {
    border: 2px solid #222138;
    border-radius: 50%;
    background: #eee;
    box-shadow:
      0 1px 3px rgba(0, 0, 0, 0.2),
      0 1px 2px rgba(0, 0, 0, 0.14),
      0 2px 1px -1px rgba(0, 0, 0, 0.12);
    width: 150px;
    height: 150px;
    position: relative;
    display: flex;
    justify-content: center;
    align-items: center;
    font-weight: bold;
  }

  :global(.customHandle) {
    width: 100%;
    height: 100%;
    background: blue;
    position: absolute;
    top: 0;
    left: 0;
    border-radius: 50%;
    transform: none;
    border: none;
    opacity: 0;
  }
</style>
