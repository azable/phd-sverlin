<script lang="ts">
  import { untrack } from 'svelte';
  import * as v from 'valibot';

  import { sandboxDocument, type CanvasView } from '../sandbox';
  import type { SelectedElement } from '$lib/client/visualization/visual-selection.svelte';
  import type { BrowserBundlePresentation } from '$lib/shared/presentations';
  import { elementIdSchema, elementLabelSchema } from '$lib/shared/projects/events/message-content';

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
  // Each step reloads the frame, so the canvas view (zoom and pan) it reports is kept here, outside
  // reactive state, and handed to the next document. A different presentation starts afresh.
  let view: CanvasView | undefined;
  let viewFor = '';
  const document = $derived.by(() => {
    if (viewFor !== presentation.presentationId) {
      viewFor = presentation.presentationId;
      view = undefined;
    }
    // A reload shows the selection current at that moment; later changes are sent as messages.
    const selected = untrack(() => selection);
    return sandboxDocument(
      '',
      presentation.javascript.text,
      step,
      presentation.seed,
      view,
      selected
    );
  });

  // The page runs authored code, so every selection it reports is checked.
  const selectionMessage = v.object({
    type: v.literal('sverlin:selection'),
    elements: v.pipe(
      v.array(v.strictObject({ id: elementIdSchema, label: elementLabelSchema })),
      v.maxLength(50)
    )
  });

  $effect(() => {
    const receive = (event: MessageEvent) => {
      if (!iframe || event.source !== iframe.contentWindow) return;
      const data = event.data as { type?: unknown } & Partial<Record<keyof CanvasView, unknown>>;
      if (data?.type === 'sverlin:selection') {
        const parsed = v.safeParse(selectionMessage, data);
        if (parsed.success) onSelectionChange(parsed.output.elements);
        return;
      }
      const numbers = [data?.zoom, data?.panX, data?.panY];
      if (data?.type !== 'sverlin:view' || !numbers.every(Number.isFinite)) return;
      view = { zoom: Number(data.zoom), panX: Number(data.panX), panY: Number(data.panY) };
      onViewChange(view);
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
