<script lang="ts">
  import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
  import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';
  import { fly } from 'svelte/transition';

  import { Button } from '$lib/client/components/ui/button';
  import type { ProjectSession } from '$lib/client/projects/project-session.svelte';
  import { presentationStepLabels, type PresentationLayout } from '$lib/shared/presentations';

  import type { PresentationSelection } from './presentation-selection.svelte';
  import PresentationViewport from './PresentationViewport.svelte';

  type Props = {
    session: ProjectSession;
    selection: PresentationSelection;
    layout: PresentationLayout;
    disabled?: boolean;
  };

  let { session, selection, layout, disabled = false }: Props = $props();
  let playback = $state<{ selectionKey: string; step: number }>({ selectionKey: '', step: 0 });

  const visible = $derived(selection.selected(session.events, layout));
  const selectionKey = $derived(
    visible.map(({ presentation }) => presentation.presentationId).join(':')
  );
  const step = $derived(playback.selectionKey === selectionKey ? playback.step : 0);
  const labels = $derived(visible[0] ? presentationStepLabels(visible[0].presentation) : []);
  const selectedIds = $derived(
    visible.map(({ presentation }) => presentation.presentationId) as [string, string]
  );
  const preferred = $derived.by(() => {
    if (visible.length !== 2) return undefined;
    const preference = session.events.findLast(
      (event) =>
        event.type === 'visualization.preference-recorded' &&
        event.payload.step === step &&
        event.payload.presentations.every((id) => selectedIds.includes(id))
    );
    return preference?.type === 'visualization.preference-recorded'
      ? preference.payload.preferred
      : undefined;
  });

  function seek(next: number) {
    playback = { selectionKey, step: next };
  }

  async function prefer(preferred: string) {
    if (visible.length !== 2) return;
    const succeeded = await session.runCommand({
      type: 'prefer',
      presentations: selectedIds,
      preferred,
      step
    });
    if (succeeded) selection.returnToLatest();
  }
</script>

{#snippet controls()}
  <div
    class="flex min-h-14 shrink-0 items-center justify-center gap-2 border-y bg-background px-3 py-2"
  >
    {#if layout === 'comparison' && visible.length === 2}
      <Button
        size="sm"
        variant={preferred === selectedIds[0] ? 'default' : 'outline'}
        onclick={() => prefer(selectedIds[0])}
        {disabled}
      >
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
    <span class="min-w-32 text-center text-sm text-muted-foreground">
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
      <Button
        size="sm"
        variant={preferred === selectedIds[1] ? 'default' : 'outline'}
        onclick={() => prefer(selectedIds[1])}
        {disabled}
      >
        Prefer bottom
      </Button>
    {/if}
    {#if !selection.followingLatest}
      <Button size="sm" variant="ghost" onclick={() => selection.returnToLatest()}
        >Return to latest</Button
      >
    {/if}
  </div>
  {#if selection.notice}
    <p class="border-b bg-muted px-3 py-2 text-center text-sm text-muted-foreground" role="status">
      {selection.notice}
    </p>
  {/if}
{/snippet}

<section class="flex min-h-0 flex-1 flex-col" aria-label="Visualization presentations">
  {#if visible.length}
    {#each visible as entry, index (entry.presentation.presentationId)}
      <div
        class="flex min-h-0 flex-1 overflow-hidden bg-muted/30 p-2"
        in:fly={{ x: 24, duration: 180 }}
      >
        <div
          class="flex min-h-0 min-w-0 flex-1 overflow-hidden rounded-lg border bg-white shadow-sm"
        >
          <PresentationViewport
            presentation={entry.presentation}
            {step}
            projectId={session.projectId}
            label={`Visualization ${index + 1}`}
          />
        </div>
      </div>
      {#if index === 0}{@render controls()}{/if}
    {/each}
  {:else}
    <div class="grid min-h-0 flex-1 place-items-center text-base text-muted-foreground">
      Preparing a visualization…
    </div>
    {@render controls()}
  {/if}
</section>
