<script lang="ts">
  import { onDestroy, untrack } from 'svelte';

  import { Skeleton } from '$lib/client/components/ui/skeleton';
  import {
    htmlFramesManifestSchema,
    staticHtmlFrameDocument,
    type RenderablePresentation
  } from '$lib/shared/presentations';
  import { decodeVisualization } from '$lib/shared/visualization';
  import type { RenderInstanceId } from '$lib/shared/visualization';
  import * as v from 'valibot';

  import VisualizationViewport from './VisualizationViewport.svelte';
  import { VisualizationPlayer } from './visualization-player.svelte';

  type Props = {
    presentation?: RenderablePresentation;
    step: number;
    projectId: string;
    label: string;
    selectedIds?: RenderInstanceId[];
    onSelectionChange?: (ids: RenderInstanceId[]) => void;
  };

  let {
    presentation,
    step,
    projectId,
    label,
    selectedIds = [],
    onSelectionChange = (_ids: RenderInstanceId[]) => {}
  }: Props = $props();
  const player = new VisualizationPlayer();
  let loadedPresentationId: string | undefined;

  const htmlDocument = $derived.by(() => {
    if (presentation?.format !== 'html-frames-v1') return undefined;
    const manifest = v.parse(htmlFramesManifestSchema, JSON.parse(presentation.rendered.text));
    const frame = manifest.frames[Math.min(step, manifest.frames.length - 1)];
    return frame ? staticHtmlFrameDocument(frame.html) : undefined;
  });

  $effect(() => {
    const nextPresentation = presentation;
    if (nextPresentation?.presentationId === loadedPresentationId) return;
    loadedPresentationId = nextPresentation?.presentationId;
    untrack(() => {
      if (nextPresentation?.format === 'sverlin-ir-v1') {
        player.setVisualization(decodeVisualization(nextPresentation.render.text), {
          initialStep: step
        });
      } else {
        player.clear();
      }
    });
  });

  $effect(() => {
    if (presentation?.format === 'sverlin-ir-v1') player.seek(step);
  });

  onDestroy(() => player.dispose());
</script>

<section class="relative min-h-0 flex-1 overflow-hidden bg-white" aria-label={label}>
  {#if presentation?.format === 'sverlin-ir-v1' && player.hasVisualization}
    <VisualizationViewport
      elements={player.elements}
      height={player.canvasHeight}
      root={player.canvasRoot!}
      resourceBaseUrl={`/api/projects/${encodeURIComponent(projectId)}/resources`}
      width={player.canvasWidth}
      {selectedIds}
      {onSelectionChange}
    />
  {:else if presentation?.format === 'html-frames-v1' && htmlDocument}
    <iframe
      title={label}
      srcdoc={htmlDocument}
      sandbox=""
      referrerpolicy="no-referrer"
      class="h-full min-h-64 w-full border-0 bg-white"
    ></iframe>
  {:else}
    <div class="flex min-h-full items-center justify-center p-6">
      <div class="flex w-full max-w-md flex-col gap-3">
        <Skeleton class="h-8 w-48" />
        <Skeleton class="h-4 w-2/3" />
        <Skeleton class="h-4 w-5/6" />
      </div>
    </div>
  {/if}
</section>
