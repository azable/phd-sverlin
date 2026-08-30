<script lang="ts">
  import { untrack } from 'svelte';
  import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
  import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';
  import { fly } from 'svelte/transition';

  import { Button } from '$lib/client/components/ui/button';
  import * as Empty from '$lib/client/components/ui/empty';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import type { ProjectSession } from '$lib/client/projects/project-session.svelte';
  import type { ProjectOperationKind } from '$lib/shared/projects/events';
  import type { VisualSelection } from '$lib/shared/projects/events/values';
  import type { PresentationLayout } from '$lib/shared/presentations';

  import type { PresentationSelection } from './presentation-selection.svelte';
  import {
    presentationPlaybackContext,
    type PresentationPlayback
  } from './presentation-playback.svelte';
  import PresentationViewport from './PresentationViewport.svelte';

  type Props = {
    session: ProjectSession;
    selection: PresentationSelection;
    playback: PresentationPlayback;
    layout: PresentationLayout;
    disabled?: boolean;
    visualSelection?: VisualSelection;
    onVisualSelectionChange?: (selection?: VisualSelection) => void;
    onReferenceSelection?: (selection: VisualSelection) => void;
  };

  let {
    session,
    selection,
    playback,
    layout,
    disabled = false,
    visualSelection,
    onVisualSelectionChange = (_selection?: VisualSelection) => {},
    onReferenceSelection = (_selection: VisualSelection) => {}
  }: Props = $props();

  const visualizationOperationKinds: readonly ProjectOperationKind[] = [
    'initial-render',
    'feedback',
    'render',
    'save',
    'save-html',
    'restore'
  ];
  const visible = $derived(selection.selected(session.events, layout));
  const preparing = $derived(
    session.refillPending ||
      (!!session.pending && visualizationOperationKinds.includes(session.pending.type))
  );
  const playbackContext = $derived(presentationPlaybackContext(visible));
  $effect.pre(() => {
    const context = playbackContext;
    untrack(() => playback.activate(context));
  });
  const step = $derived(playback.stepFor(playbackContext));
  const stepCount = $derived(playbackContext.stepCount);
  const selectedIds = $derived(visible.map(({ presentation }) => presentation.presentationId));
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
    playback.seek(playbackContext, next);
    onVisualSelectionChange(undefined);
  }

  async function prefer(preferred: string) {
    if (visible.length !== 2) return;
    const succeeded = await session.runCommand({
      type: 'prefer',
      presentations: [selectedIds[0], selectedIds[1]],
      preferred,
      step
    });
    if (succeeded) {
      onVisualSelectionChange(undefined);
      selection.returnToLatest();
    }
  }

  async function advancePresentations() {
    if (!visible.length) return;
    const succeeded = await session.runCommand({
      type: 'advance-presentations',
      presentations: selectedIds
    });
    if (succeeded) {
      onVisualSelectionChange(undefined);
      selection.returnToLatest();
    }
  }

  function returnToCurrent() {
    onVisualSelectionChange(undefined);
    selection.returnToLatest();
  }

  function selectedInstances(entry: (typeof visible)[number]) {
    if (!visualSelection || visualSelection.step !== step) return [];
    return visualSelection.presentationEvent === entry.eventId ? visualSelection.instances : [];
  }

  function selectInstances(entry: (typeof visible)[number], instances: number[]) {
    onVisualSelectionChange(
      instances.length ? { presentationEvent: entry.eventId, step, instances } : undefined
    );
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
      onclick={() => seek(step - 1)}
      disabled={disabled || step === 0}><ChevronLeftIcon /></Button
    >
    <span class="min-w-32 text-center text-sm text-muted-foreground">
      {stepCount ? `Step ${step + 1} of ${stepCount}` : 'No steps'}
    </span>
    <Button
      size="icon-sm"
      variant="ghost"
      aria-label="Next visualization step"
      onclick={() => seek(step + 1)}
      disabled={disabled || step >= stepCount - 1}><ChevronRightIcon /></Button
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
      <Button size="sm" variant="ghost" onclick={returnToCurrent}>Return to current</Button>
    {/if}
    {#if selection.buffered && selection.followingLatest && visible.length}
      <Button size="sm" variant="outline" onclick={advancePresentations} {disabled}>
        Next visualizations
      </Button>
    {/if}
    {#if visualSelection && visible.some(({ eventId }) => eventId === visualSelection?.presentationEvent)}
      <Button
        size="sm"
        variant="outline"
        onclick={() => onReferenceSelection(visualSelection)}
        {disabled}
      >
        Reference selection
      </Button>
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
            selectedIds={selectedInstances(entry)}
            onSelectionChange={(instances) => selectInstances(entry, instances)}
          />
        </div>
      </div>
      {#if index === 0}{@render controls()}{/if}
    {/each}
  {:else}
    <div class="flex min-h-0 flex-1 bg-muted/30 p-2">
      <Empty.Root class="border-0" aria-live="polite">
        <Empty.Header>
          {#if preparing}
            <Empty.Media><Spinner /></Empty.Media>
            <Empty.Title>Preparing a visualization…</Empty.Title>
          {:else}
            <Empty.Title>Your visualization will appear here.</Empty.Title>
          {/if}
        </Empty.Header>
      </Empty.Root>
    </div>
  {/if}
</section>
