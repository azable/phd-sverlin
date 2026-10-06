<script lang="ts">
  import { untrack } from 'svelte';
  import { fade } from 'svelte/transition';
  import { Spinner } from '$lib/client/components/ui/spinner';
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
    onViewChange = () => {},
    onRuntimeError = () => {}
  }: {
    presentation: BrowserBundlePresentation;
    step: number;
    label: string;
    /** Ids of the elements to show selected. */
    selection?: readonly string[];
    onSelectionChange?: (elements: SelectedElement[]) => void;
    /** The canvas zoom and pan the participant left the presentation at. */
    onViewChange?: (view: CanvasView) => void;
    /** The view's own code failed as it drew a step (or, without a step, at some other moment). */
    onRuntimeError?: (failure: { step?: number; message: string }) => void;
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
  // Whether the page shows its first step: it lays every step out before showing any.
  let ready = $state(false);
  $effect(() => {
    void document;
    loaded = false;
    ready = false;
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

  // The view's own code can fail as it draws a step; the page reports it, and it is shown here.
  const errorMessage = v.object({
    type: v.literal('sverlin:error'),
    message: v.pipe(v.string(), v.maxLength(500)),
    step: v.optional(v.pipe(v.number(), v.integer(), v.minValue(0)))
  });
  let failure = $state<v.InferOutput<typeof errorMessage>>();
  $effect(() => {
    void document;
    failure = undefined;
  });

  $effect(() => {
    const receive = (event: MessageEvent) => {
      if (!iframe || event.source !== iframe.contentWindow) return;
      const data = event.data as { type?: unknown } & Partial<Record<keyof CanvasView, unknown>>;
      if (data?.type === 'sverlin:loaded') {
        loaded = true;
        // Presentations built before pages reported readiness never say so; stop waiting for them.
        const waiting = document;
        setTimeout(() => {
          if (document === waiting) ready = true;
        }, 4000);
        return;
      }
      if (data?.type === 'sverlin:ready') {
        ready = true;
        return;
      }
      if (data?.type === 'sverlin:error') {
        const parsed = v.safeParse(errorMessage, data);
        if (parsed.success) {
          failure = parsed.output;
          ready = true;
          onRuntimeError({
            message: parsed.output.message,
            ...(parsed.output.step === undefined ? {} : { step: parsed.output.step })
          });
        }
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

<div class="relative h-full w-full">
  <iframe
    bind:this={iframe}
    title={label}
    srcdoc={document}
    sandbox="allow-scripts"
    referrerpolicy="no-referrer"
    class="block h-full w-full border-0 bg-white"
  ></iframe>
  {#if !ready}
    <div
      class="absolute inset-0 flex items-center justify-center gap-2 bg-white text-sm text-muted-foreground"
      role="status"
      aria-live="polite"
      out:fade={{ duration: 150 }}
    >
      <Spinner />
      <span>Loading…</span>
    </div>
  {/if}
  {#if failure}
    <p
      role="alert"
      class="absolute inset-x-2 bottom-2 rounded border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800"
    >
      {failure.step === undefined
        ? 'The view failed while drawing'
        : `The view failed while drawing step ${failure.step + 1}`}: {failure.message}
    </p>
  {/if}
</div>
