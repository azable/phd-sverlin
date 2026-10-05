<script lang="ts">
  import { untrack } from 'svelte';
  import * as v from 'valibot';

  import { sandboxDocument, type CanvasView } from '../sandbox';
  import type { SelectedElement } from '$lib/client/visualization/visual-selection.svelte';
  import type { BrowserBundlePresentation } from '$lib/shared/presentations';
  import { selectedElementSchema } from '$lib/shared/projects/events/message-content';

  let {
    presentation,
    step,
    label,
    selection = [],
    onSelectionChange = () => {},
    onViewChange = () => {}
  }: {
    presentation: BrowserBundlePresentation;
    step: number;
    label: string;
    /** Ids of the elements to show selected. */
    selection?: readonly string[];
    onSelectionChange?: (elements: SelectedElement[]) => void;
    /** The canvas zoom and pan the participant left the presentation at. */
    onViewChange?: (view: CanvasView) => void;
  } = $props();

  let iframe = $state<HTMLIFrameElement>();
  // The iframe fills its pane exactly, however short: the canvas inside fits itself to the iframe, so
  // an iframe taller than its pane would be clipped, cutting off the canvas.
  // The page loads once per presentation, with the step and selection current then;
  // later steps are sent to it as messages, so it never reloads while stepping.
  const document = $derived.by(() => {
    void presentation.presentationId;
    return sandboxDocument(
      '',
      presentation.javascript.text,
      untrack(() => step),
      presentation.seed,
      undefined,
      untrack(() => selection)
    );
  });
  // Whether the page has loaded and listens for steps; a new document starts unloaded.
  let loaded = $state(false);
  $effect(() => {
    void document;
    loaded = false;
  });

  $effect(() => {
    const shown = step;
    if (!loaded) return;
    // The step's selection is sent with it, so the new step shows it from the start.
    iframe?.contentWindow?.postMessage(
      { type: 'sverlin:step', step: shown, selection: untrack(() => [...selection]) },
      '*'
    );
  });

  // The page runs authored code, so every selection it reports is checked.
  const selectionMessage = v.object({
    type: v.literal('sverlin:selection'),
    elements: v.pipe(v.array(selectedElementSchema), v.maxLength(50))
  });

  $effect(() => {
    const receive = (event: MessageEvent) => {
      if (!iframe || event.source !== iframe.contentWindow) return;
      const data = event.data as { type?: unknown } & Partial<Record<keyof CanvasView, unknown>>;
      if (data?.type === 'sverlin:loaded') {
        loaded = true;
        return;
      }
      if (data?.type === 'sverlin:selection') {
        const parsed = v.safeParse(selectionMessage, data);
        if (parsed.success) onSelectionChange(parsed.output.elements);
        return;
      }
      const numbers = [data?.zoom, data?.panX, data?.panY];
      if (data?.type !== 'sverlin:view' || !numbers.every(Number.isFinite)) return;
      onViewChange({ zoom: Number(data.zoom), panX: Number(data.panX), panY: Number(data.panY) });
    };
    addEventListener('message', receive);
    return () => removeEventListener('message', receive);
  });

  // Show a selection the app sets, such as from a reference in the timeline, without reloading.
  $effect(() => {
    const ids = [...selection];
    iframe?.contentWindow?.postMessage({ type: 'sverlin:select', ids }, '*');
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
