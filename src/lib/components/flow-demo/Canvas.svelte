<script lang="ts">
  //import Graph from './graph/Graph.svelte';

  import { onMount } from 'svelte';
  import {
    SvelteFlow,
    Position,
    useSvelteFlow,
    type Node,
    type Edge,
    ConnectionLineType,
    type Connection,
    addEdge
  } from '@xyflow/svelte';
  import '@xyflow/svelte/dist/style.css';

  import ELK from 'elkjs/lib/elk.bundled.js';
  const elk = new ELK();

  // import Array from './array/Array.svelte';
  import Value from './value/ValueNode.svelte';
  import Graph from './graph/Graph.svelte';

  const nodeTypes = { value: Value, graph: Graph };

  let nodes: Node[] = [
    {
      id: '1',
      type: 'value',
      data: { type: 'primitive', label: 'var1', value: 'Test' },
      position: { x: 100, y: 100 }
    },
    {
      id: '2',
      type: 'value',
      data: {
        type: 'array',
        value: [
          { type: 'primitive', value: 1 },
          { type: 'primitive', value: 2 },
          { type: 'primitive', value: 3 }
        ]
      },
      position: { x: 200, y: 300 }
    },
    {
      id: '3',
      type: 'value',
      data: { type: 'reference', label: 'ptr1', value: '2' },
      position: { x: 500, y: 300 }
    },
    // {
    //   id: '4',
    //   type: 'graph',
    //   data: {},
    //   position: { x: 400, y: 500 }
    // },
    {
      id: '5',
      type: 'value',
      data: {
        type: 'object',
        value: [
          ['key1', { type: 'primitive', value: 42 }],
          ['key2', { type: 'primitive', value: 'Hello' }],
          [
            'anotherKey',
            {
              type: 'object',
              value: [
                ['nestedKey', { type: 'primitive', value: 'Nested Value' }],
                ['anotherNestedKey', { type: 'primitive', value: 2 }]
              ]
            }
          ]
        ]
      },
      position: { x: 200, y: 500 }
    }
  ];

  let edges: Edge[] = [];

  const { fitView } = useSvelteFlow();

  // Elk has a *huge* amount of options to configure. To see everything you can
  // tweak check out:
  //
  // - https://www.eclipse.org/elk/reference/algorithms.html
  // - https://www.eclipse.org/elk/reference/options.html
  const elkOptions = {
    'elk.algorithm': 'mrtree',
    'elk.layered.spacing.nodeNodeBetweenLayers': '100',
    'elk.spacing.nodeNode': '80'
  };

  function getLayoutedElements(nodes: Node[], edges: Edge[], options: Record<string, any> = {}) {
    const isHorizontal = options?.['elk.direction'] === 'RIGHT';
    const graph = {
      id: 'root',
      layoutOptions: options,
      children: nodes.map((node) => ({
        ...node,
        // Adjust the target and source handle positions based on the layout
        // direction.
        targetPosition: isHorizontal ? Position.Left : Position.Top,
        sourcePosition: isHorizontal ? Position.Right : Position.Bottom,

        // Hardcode a width and height for elk to use when layouting.
        width: node.measured?.width,
        height: node.measured?.height
      })),
      edges: edges.map((edge) => ({
        ...edge
      }))
    } as any;

    return elk
      .layout(graph)
      .then((layoutedGraph) => {
        if (!layoutedGraph || !layoutedGraph.children) {
          throw new Error('Layout failed');
        }

        return {
          nodes: layoutedGraph.children.map((node) => ({
            ...node,
            // Svelte Flow expects a position property on the node instead of `x`
            // and `y` fields.
            position: { x: node.x, y: node.y }
          })),
          edges: layoutedGraph.edges
        };
      })
      .catch((err) => {
        console.error('Layout failed:', err);
        return { nodes, edges };
      });
  }

  function onLayout(direction: string) {
    const opts = { 'elk.direction': direction, ...elkOptions };
    const ns = nodes;
    const es = edges;

    getLayoutedElements(ns, es, opts).then(({ nodes: layoutedNodes, edges: layoutedEdges }) => {
      nodes = layoutedNodes;
      edges = layoutedEdges;

      fitView();
    });
  }

  onMount(() => {
    // wait a tick to ensure all nodes are measured
    setTimeout(() => {
      onLayout('DOWN');
    }, 0);
  });

  function onConnect(conn: Connection) {
    // Remove any existing edge with the same source and different target
    edges = edges.filter(
      (e) =>
        !(
          e.source === conn.source &&
          e.sourceHandle === conn.sourceHandle &&
          (e.target !== conn.target || e.targetHandle !== conn.targetHandle)
        )
    );
  }
</script>

<SvelteFlow
  bind:nodes
  bind:edges
  {nodeTypes}
  zIndexMode="manual"
  elevateEdgesOnSelect={false}
  elevateNodesOnSelect={false}
  connectionLineType={ConnectionLineType.SmoothStep}
  defaultEdgeOptions={{
    type: 'smoothstep',
    style: 'stroke-width: 2px; stroke: #FF4000;',
    markerEnd: { type: 'arrowclosed', width: 20, height: 20, color: '#FF4000' }
  }}
  onnodedragstop={() => {
    onLayout('DOWN');
  }}
  onconnect={(conn) => {
    onConnect(conn);
    onLayout('DOWN');
  }}
  onreconnect={() => {
    onLayout('DOWN');
  }}
  fitView
></SvelteFlow>

<style>
  :global(.svelte-flow__edges) {
    z-index: 10;
  }

  :global(.svelte-flow__nodes) {
    z-index: 1;
  }

  :global(.svelte-flow__node) {
    transition: transform 220ms ease;
    will-change: transform;
  }

  :global(.svelte-flow__node.dragging) {
    transition: none;
  }
</style>
