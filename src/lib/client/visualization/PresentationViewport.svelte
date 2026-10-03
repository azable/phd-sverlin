<script lang="ts">
  import type { Component } from 'svelte';
  import { Skeleton } from '$lib/client/components/ui/skeleton';
  import { modeCatalog } from '$lib/visualization-modes/catalog';
  import {
    presentationMode,
    type RenderablePresentation,
    type VisualizationMode
  } from '$lib/shared/presentations';

  let {
    presentation,
    step,
    label
  }: { presentation?: RenderablePresentation; step: number; label: string } = $props();
  const viewports = import.meta.glob<{
    default: Component<{ presentation: RenderablePresentation; step: number; label: string }>;
  }>('../../visualization-modes/*/Viewport.svelte', { eager: true });
  const registered = Object.fromEntries(
    Object.entries(viewports).map(([file, module]) => [file.split('/').at(-2), module.default])
  ) as Partial<
    Record<
      VisualizationMode,
      Component<{ presentation: RenderablePresentation; step: number; label: string }>
    >
  >;
  for (const mode of Object.keys(modeCatalog) as VisualizationMode[]) {
    if (!registered[mode])
      throw new Error(`Visualization mode ${mode} needs a playback component.`);
  }
  const Viewport = $derived(presentation ? registered[presentationMode(presentation)] : undefined);
</script>

<section class="relative min-h-0 flex-1 overflow-hidden bg-white" aria-label={label}>
  {#if presentation && Viewport}
    <Viewport {presentation} {step} {label} />
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
