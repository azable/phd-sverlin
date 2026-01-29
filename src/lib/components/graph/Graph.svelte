<script lang="ts">
  import {
    ConnectionLineType,
    MarkerType,
    SvelteFlow,
    Background,
    type Node,
    type Edge
  } from '@xyflow/svelte';

  import CustomNode from './Node.svelte';

  import '@xyflow/svelte/dist/style.css';

  import FloatingEdge from './Edge.svelte';

  const initialNodes: Node[] = [
    {
      id: '1',
      type: 'circle',
      position: { x: 0, y: 0 },
      data: {
        label: 'Start Node'
      }
    },
    {
      id: '2',
      type: 'circle',
      position: { x: 250, y: 320 },
      data: {}
    },
    {
      id: '3',
      type: 'circle',
      position: { x: 40, y: 300 },
      data: {}
    }
  ];

  const initialEdges: Edge[] = [
    {
      id: 'e1-2',
      source: '1',
      target: '2'
    },
    {
      id: 'e1-3',
      source: '1',
      target: '3'
    }
  ];

  let nodes = $state.raw<Node[]>(initialNodes);
  let edges = $state.raw<Edge[]>(initialEdges);

  const nodeTypes = {
    circle: CustomNode
  };

  const edgeTypes = {
    floating: FloatingEdge
  };

  const defaultEdgeOptions = {
    type: 'floating',
    markerEnd: {
      type: MarkerType.ArrowClosed
    }
  };
</script>

<SvelteFlow
  bind:nodes
  {nodeTypes}
  bind:edges
  {edgeTypes}
  {defaultEdgeOptions}
  connectionLineType={ConnectionLineType.Straight}
  fitView
>
  <Background />
</SvelteFlow>
