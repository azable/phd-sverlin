<script>
  import { SvelteFlowProvider } from '@xyflow/svelte';
  import '@xyflow/svelte/dist/style.css';

  import Canvas from '$lib/components/flow-demo/Canvas.svelte';
</script>

<div style:width="100vw" style:height="100vh">
  <SvelteFlowProvider>
    <Canvas />
  </SvelteFlowProvider>
</div>
