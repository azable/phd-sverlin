<script lang="ts">
  import { untrack } from 'svelte';
  import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
  import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';
  import ShuffleIcon from '@lucide/svelte/icons/shuffle';
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
    localPresentationStep,
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
    visualSelections?: readonly VisualSelection[];
    onVisualSelectionsChange?: (selections: VisualSelection[]) => void;
    onReferenceSelections?: (selections: VisualSelection[]) => void;
    onViewportChange?: (
      presentationId: string,
      viewport: { zoom: number; panX: number; panY: number }
    ) => void;
  };

  let {
    session,
    selection,
    playback,
    layout,
    disabled = false,
    visualSelections = [],
    onVisualSelectionsChange = (_selections: VisualSelection[]) => {},
    onReferenceSelections = (_selections: VisualSelection[]) => {},
    onViewportChange = (
      _presentationId: string,
      _viewport: { zoom: number; panX: number; panY: number }
    ) => {}
  }: Props = $props();
  let preferencePending = $state<string>();

  const visualizationOperationKinds: readonly ProjectOperationKind[] = [
    'initial-render',
    'feedback',
    'prefer',
    'render',
    'resample',
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
  const visibleSelections = $derived(
    visible.flatMap((entry) =>
      visualSelections.filter(
        (selection) =>
          selection.presentationEvent === entry.eventId && selection.step === localStep(entry)
      )
    )
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
    playback.seek(playbackContext, next);
    onVisualSelectionsChange([]);
  }

  async function prefer(preferred: string) {
    if (visible.length !== 2) return;
    preferencePending = preferred;
    selection.pin(visible);
    try {
      const succeeded = await session.runCommand({
        type: 'prefer',
        presentations: [selectedIds[0], selectedIds[1]],
        preferred,
        step,
        visualSelections: visibleSelections
      });
      if (succeeded) {
        onVisualSelectionsChange([]);
        selection.returnToLatest();
      }
    } finally {
      preferencePending = undefined;
    }
  }

  async function advancePresentations() {
    if (!visible.length) return;
    const succeeded = await session.runCommand({
      type: 'advance-presentations',
      presentations: selectedIds
    });
    if (succeeded) {
      onVisualSelectionsChange([]);
      selection.returnToLatest();
    }
  }

  async function generateVariants() {
    const succeeded = await session.runCommand({
      type: 'resample',
      presentationCount: layout === 'comparison' ? 2 : 1
    });
    if (succeeded) {
      onVisualSelectionsChange([]);
      selection.returnToLatest();
    }
  }

  function returnToCurrent() {
    onVisualSelectionsChange([]);
    selection.returnToLatest();
  }

  function selectedInstances(entry: (typeof visible)[number]) {
    return (
      visualSelections.find(
        (selection) =>
          selection.presentationEvent === entry.eventId && selection.step === localStep(entry)
      )?.instances ?? []
    );
  }

  function selectInstances(entry: (typeof visible)[number], instances: number[]) {
    const entryStep = localStep(entry);
    if (entryStep < 0) return;
    const retained = visualSelections.filter(
      (selection) =>
        visible.some(({ eventId }) => eventId === selection.presentationEvent) &&
        selection.presentationEvent !== entry.eventId
    );
    onVisualSelectionsChange(
      instances.length
        ? [...retained, { presentationEvent: entry.eventId, step: entryStep, instances }]
        : retained
    );
  }

  function localStep(entry: (typeof visible)[number]) {
    return localPresentationStep(playbackContext, entry.presentation.presentationId, step);
  }
</script>

{#snippet controls()}
  <div
    class="flex min-h-14 shrink-0 items-center justify-center gap-2 border-y bg-background px-3 py-2"
    data-replay-region="presentation-controls"
  >
    {#if layout === 'comparison' && visible.length === 2}
      <Button
        size="lg"
        variant={preferred === selectedIds[0] ? 'default' : 'outline'}
        aria-label="Prefer top candidate"
        onclick={() => prefer(selectedIds[0])}
        disabled={disabled || preferencePending !== undefined}
      >
        {#if preferencePending === selectedIds[0]}
          <Spinner data-icon="inline-start" /> Recording…
        {:else}
          Prefer top candidate
        {/if}
      </Button>
    {/if}
    <Button
      size="lg"
      variant="outline"
      aria-label="Previous visualization step"
      onclick={() => seek(step - 1)}
      disabled={disabled || step === 0}
    >
      <ChevronLeftIcon data-icon="inline-start" />
      Previous
    </Button>
    <span class="min-w-32 text-center text-sm text-muted-foreground">
      {stepCount ? `Step ${step + 1} of ${stepCount}` : 'No steps'}
    </span>
    <Button
      size="lg"
      variant="outline"
      aria-label="Next visualization step"
      onclick={() => seek(step + 1)}
      disabled={disabled || step >= stepCount - 1}
    >
      Next
      <ChevronRightIcon data-icon="inline-end" />
    </Button>
    {#if layout === 'comparison' && visible.length === 2}
      <Button
        size="lg"
        variant={preferred === selectedIds[1] ? 'default' : 'outline'}
        aria-label="Prefer bottom candidate"
        onclick={() => prefer(selectedIds[1])}
        disabled={disabled || preferencePending !== undefined}
      >
        {#if preferencePending === selectedIds[1]}
          <Spinner data-icon="inline-start" /> Recording…
        {:else}
          Prefer bottom candidate
        {/if}
      </Button>
    {/if}
    {#if !selection.followingLatest}
      <Button
        size="sm"
        variant="ghost"
        aria-label="Return to current visualizations"
        onclick={returnToCurrent}
        {disabled}>Return to current</Button
      >
    {/if}
    {#if selection.buffered && selection.followingLatest && visible.length}
      <Button
        size="sm"
        variant="outline"
        aria-label="Show next visualization pair"
        onclick={advancePresentations}
        {disabled}
      >
        Next pair
      </Button>
    {/if}
    {#if !selection.buffered && session.snapshot.renderer === 'sverlin'}
      <Button
        size="sm"
        variant="outline"
        aria-label={layout === 'comparison'
          ? 'Generate another visualization pair'
          : 'Generate another visualization variant'}
        onclick={generateVariants}
        disabled={disabled || !session.atHead}
      >
        {#if session.pending?.type === 'resample'}
          <Spinner data-icon="inline-start" /> Generating…
        {:else}
          <ShuffleIcon data-icon="inline-start" />
          {layout === 'comparison' ? 'New pair' : 'Another variant'}
        {/if}
      </Button>
    {/if}
    {#if visibleSelections.length}
      <Button
        size="sm"
        variant="outline"
        aria-label="Reference selected visualization elements"
        onclick={() => onReferenceSelections(visibleSelections)}
        {disabled}
      >
        Reference {visibleSelections.length === 1 ? 'selection' : 'selections'}
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
        data-replay-region={`candidate-${index + 1}`}
        data-replay-presentation-id={entry.presentation.presentationId}
        in:fly={{ x: 24, duration: 180 }}
      >
        <div
          class="flex min-h-0 min-w-0 flex-1 overflow-hidden rounded-lg border bg-white shadow-sm"
        >
          <PresentationViewport
            presentation={entry.presentation}
            step={localStep(entry)}
            projectId={session.projectId}
            label={`Visualization ${index + 1}`}
            selectedIds={selectedInstances(entry)}
            onSelectionChange={(instances) => selectInstances(entry, instances)}
            onViewportChange={(viewport) =>
              onViewportChange(entry.presentation.presentationId, viewport)}
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
