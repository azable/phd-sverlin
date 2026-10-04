<script lang="ts">
  import { sandboxDocument, type CanvasView } from '../sandbox';
  import type { BrowserBundlePresentation } from '$lib/shared/presentations';

  let {
    presentation,
    step,
    label
  }: { presentation: BrowserBundlePresentation; step: number; label: string } = $props();

  let iframe = $state<HTMLIFrameElement>();
  // The iframe fills its pane exactly, however short: the canvas inside fits itself to the iframe, so
  // an iframe taller than its pane would be clipped, cutting off the canvas.
  // Each step reloads the frame, so the canvas view (zoom and pan) it reports is kept here, outside
  // reactive state, and handed to the next document. A different presentation starts afresh.
  let view: CanvasView | undefined;
  let viewFor = '';
  const document = $derived.by(() => {
    if (viewFor !== presentation.presentationId) {
      viewFor = presentation.presentationId;
      view = undefined;
    }
    return sandboxDocument('', presentation.javascript.text, step, presentation.seed, view);
  });

  $effect(() => {
    const receive = (event: MessageEvent) => {
      if (!iframe || event.source !== iframe.contentWindow) return;
      const data = event.data as { type?: unknown } & Partial<Record<keyof CanvasView, unknown>>;
      const numbers = [data?.zoom, data?.panX, data?.panY];
      if (data?.type !== 'sverlin:view' || !numbers.every(Number.isFinite)) return;
      view = { zoom: Number(data.zoom), panX: Number(data.panX), panY: Number(data.panY) };
    };
    addEventListener('message', receive);
    return () => removeEventListener('message', receive);
  });
</script>

<iframe
  bind:this={iframe}
  title={label}
  srcdoc={document}
  sandbox="allow-scripts"
  referrerpolicy="no-referrer"
  class="block h-full w-full border-0 bg-white"
></iframe>
