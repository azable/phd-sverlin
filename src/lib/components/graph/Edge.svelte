<script lang="ts">
  import { BaseEdge, getStraightPath, useInternalNode, type EdgeProps } from '@xyflow/svelte';

  import { getEdgeParams } from './utils';

  let { id, source, target, markerEnd }: EdgeProps = $props();

  const sourceNode = useInternalNode(source);
  const targetNode = useInternalNode(target);

  let path: string = $derived.by(() => {
    if (sourceNode.current && targetNode.current) {
      const edgeParams = getEdgeParams(sourceNode.current, targetNode.current);
      return getStraightPath({
        sourceX: edgeParams.sx,
        sourceY: edgeParams.sy,
        targetX: edgeParams.tx,
        targetY: edgeParams.ty
      })[0];
    }
    return '';
  });
</script>

<svg width="0" height="0" style="position:absolute">
  <defs>
    <marker
      id="floating-arrow"
      viewBox="0 0 10 10"
      refX="10"
      refY="5"
      markerWidth="6"
      markerHeight="6"
      orient="auto-start-reverse"
    >
      <path class="floatingEdgeMarker" d="M 0 0 L 10 5 L 0 10 z" />
    </marker>
  </defs>
</svg>

<BaseEdge class={'floatingEdge'} {id} {path} markerEnd="url(#floating-arrow)" />

<style>
  :global(.floatingEdge) {
    stroke: #222138;
    stroke-width: 2;
  }

  :global(.floatingEdgeMarker) {
    fill: #222138;
    stroke: #222138;
  }
</style>
