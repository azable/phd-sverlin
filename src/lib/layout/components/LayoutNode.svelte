<script lang="ts">
  import type { NodeView } from '$lib/layout/node.svelte';

  export type NodeProps = {
    id: string;
    view: NodeView;
  };

  let { id, view }: NodeProps = $props();
</script>

<div class="node" {id} style={view.css}>
  {#if view.content}
    <div class="node-content">
      {view.content.text}
    </div>
  {/if}
</div>

<style>
  .node {
    position: absolute;
    display: flex;
    justify-content: center;
    align-items: center;
    /* border: 3px solid black; */
  }

  .node-content {
    user-select: none;
  }
</style>
