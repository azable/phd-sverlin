<script lang="ts">
  //import Graph from './graph/Graph.svelte';

  import { SvelteFlow } from '@xyflow/svelte';
  import '@xyflow/svelte/dist/style.css';

  // import Array from './array/Array.svelte';
  import Value from './value/ValueNode.svelte';
  import Graph from './graph/Graph.svelte';

  const nodeTypes = { value: Value, graph: Graph };

  let nodes = [
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
    {
      id: '4',
      type: 'graph',
      data: {},
      position: { x: 400, y: 500 }
    },
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
                ['anotherNestedKey', { type: 'primitive', value: 2 }],
                [
                  'deeplyNested',
                  {
                    type: 'array',
                    value: [
                      { type: 'primitive', value: 'Item 1' },
                      { type: 'primitive', value: 'Item 2' },
                      { type: 'primitive', value: 'Item 3' }
                    ]
                  }
                ]
              ]
            }
          ]
        ]
      },
      position: { x: 200, y: 500 }
    }
  ];

  let edges = [
    //{ id: '3-5-key1', source: '3', target: '5', targetHandle: '5-key1-handle' }
  ];
</script>

<SvelteFlow
  bind:nodes
  bind:edges
  {nodeTypes}
  zIndexMode="manual"
  elevateEdgesOnSelect={false}
  elevateNodesOnSelect={false}
  defaultEdgeOptions={{
    type: 'smoothstep',
    style: 'stroke-width: 2px; stroke: #FF4000;',
    markerEnd: { type: 'arrowclosed', width: 20, height: 20, color: '#FF4000' }
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
</style>
