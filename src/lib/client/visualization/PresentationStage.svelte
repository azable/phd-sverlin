<script lang="ts">
  import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
  import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';

  import { Button } from '$lib/client/components/ui/button';
  import type { ProjectSession } from '$lib/client/projects/project-session.svelte';
  import {
    presentationStepLabels,
    type PresentationLayout,
    type RenderablePresentation
  } from '$lib/shared/presentations';

  import PresentationViewport from './PresentationViewport.svelte';

  type Props = {
    session: ProjectSession;
    layout: PresentationLayout;
    disabled?: boolean;
  };

  let { session, layout, disabled = false }: Props = $props();
  let playback = $state<{ displaySetId?: string; step: number }>({ step: 0 });

  const active = $derived(session.snapshot.activePresentationSet);
  const step = $derived(playback.displaySetId === active?.displaySetId ? playback.step : 0);
  const presentations = $derived.by(
    (): Array<{ id: string; value: RenderablePresentation }> =>
      (active?.presentations ?? []).flatMap((event) => {
        if (event.type === 'visualization.presented') {
          return [
            {
              id: event.payload.presentation.presentationId,
              value: event.payload.presentation
            }
          ];
        }
        return [
          {
            id: `00000000-0000-4000-8000-${String(event.id).padStart(12, '0')}`,
            value: {
              presentationId: `00000000-0000-4000-8000-${String(event.id).padStart(12, '0')}`,
              format: 'sverlin-ir-v1',
              stepSignature: `legacy-${event.id}`,
              seed: event.payload.seed,
              source: event.payload.source,
              render: event.payload.render,
              resources: event.payload.resources,
              provenance: event.payload.provenance,
              targetDiagnostics: event.payload.targetDiagnostics
            }
          }
        ];
      })
  );
  const visible = $derived(
    layout === 'comparison' ? presentations.slice(0, 2) : presentations.slice(0, 1)
  );
  const labels = $derived(visible[0] ? presentationStepLabels(visible[0].value) : []);

  function seek(next: number) {
    playback = { displaySetId: active?.displaySetId, step: next };
  }

  async function prefer(preferred: string) {
    if (!active || visible.length !== 2) return;
    await session.runCommand({
      type: 'prefer',
      displaySetId: active.displaySetId,
      presentations: [visible[0].id, visible[1].id],
      preferred,
      step
    });
  }
</script>

{#snippet controls()}
  <div
    class="flex min-h-14 shrink-0 items-center justify-center gap-2 border-y bg-background px-3 py-2"
  >
    {#if layout === 'comparison' && visible.length === 2}
      <Button size="sm" variant="outline" onclick={() => prefer(visible[0].id)} {disabled}>
        Prefer top
      </Button>
    {/if}
    <Button
      size="icon-sm"
      variant="ghost"
      aria-label="Previous visualization step"
      onclick={() => seek(Math.max(0, step - 1))}
      disabled={disabled || step === 0}><ChevronLeftIcon /></Button
    >
    <span class="min-w-32 text-center text-xs text-muted-foreground">
      {labels[step] ?? 'No steps'}{labels.length ? ` · ${step + 1}/${labels.length}` : ''}
    </span>
    <Button
      size="icon-sm"
      variant="ghost"
      aria-label="Next visualization step"
      onclick={() => seek(Math.min(labels.length - 1, step + 1))}
      disabled={disabled || step >= labels.length - 1}><ChevronRightIcon /></Button
    >
    {#if layout === 'comparison' && visible.length === 2}
      <Button size="sm" variant="outline" onclick={() => prefer(visible[1].id)} {disabled}>
        Prefer bottom
      </Button>
    {/if}
  </div>
{/snippet}

<section class="flex min-h-0 flex-1 flex-col" aria-label="Visualization presentations">
  {#if visible.length}
    {#each visible as presentation, index (presentation.id)}
      <div class="flex min-h-0 flex-1 overflow-hidden bg-muted/30 p-2">
        <div
          class="flex min-h-0 min-w-0 flex-1 overflow-hidden rounded-lg border bg-white shadow-sm"
        >
          <PresentationViewport
            presentation={presentation.value}
            {step}
            projectId={session.projectId}
            label={`Visualization ${index + 1}`}
          />
        </div>
      </div>
      {#if index === 0}{@render controls()}{/if}
    {/each}
  {:else}
    <div class="grid min-h-0 flex-1 place-items-center text-sm text-muted-foreground">
      Preparing a visualization…
    </div>
    {@render controls()}
  {/if}
</section>
