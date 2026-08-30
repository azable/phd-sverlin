<script lang="ts">
  import { fly } from 'svelte/transition';

  import { Spinner } from '$lib/client/components/ui/spinner';
  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import type { ProjectSession } from '$lib/client/projects/project-session.svelte';
  import {
    presentationDisplayId,
    timelinePresentations,
    type TimelinePresentation
  } from '$lib/client/visualization/presentation-history';
  import type { PresentationSelection } from '$lib/client/visualization/presentation-selection.svelte';
  import type { PresentationLayout } from '$lib/shared/presentations';
  import type { MessageContentSegment } from '$lib/shared/projects/events/message-content';

  import MessageContent from './MessageContent.svelte';
  import { participantTimeline } from './participant-timeline';

  type Props = {
    session: ProjectSession;
    selection: PresentationSelection;
    layout: PresentationLayout;
    onPresentationChange?: () => void;
    onReferenceRequest?: (presentation: TimelinePresentation) => void;
    onElementReferenceActivate?: (
      reference: Extract<MessageContentSegment, { type: 'element-ref' }>
    ) => void;
  };

  let {
    session,
    selection,
    layout,
    onPresentationChange = () => {},
    onReferenceRequest = () => {},
    onElementReferenceActivate = () => {}
  }: Props = $props();
  const items = $derived(participantTimeline(session.events));
  const selectedIds = $derived(
    selection
      .selected(session.events, layout)
      .map(({ presentation }) => presentation.presentationId)
  );

  function activatePresentation(
    item: Extract<(typeof items)[number], { kind: 'presentation' }>,
    event: MouseEvent
  ) {
    onPresentationChange();
    selection.activate(item.value, session.events, layout, event.shiftKey);
  }

  function activateReference(
    reference: Exclude<MessageContentSegment, { type: 'markdown' }>,
    extend: boolean
  ) {
    const presentation = timelinePresentations(session.events).find(
      ({ presentation: value }) => value.presentationId === reference.presentationId
    );
    if (!presentation) return;
    onPresentationChange();
    selection.activate(presentation, session.events, layout, extend);
    if (reference.type === 'element-ref') onElementReferenceActivate(reference);
  }

  function contextLabel(item: Extract<(typeof items)[number], { kind: 'message' }>) {
    if (!item.context) return '';
    const names = item.context.presentationIds.map(presentationDisplayId).join(' + ');
    return `${item.context.type === 'comparing' ? 'Comparing' : 'Viewing'} · ${names}`;
  }
</script>

{#each items as item (item.id)}
  <li
    class="flex"
    class:justify-end={item.kind === 'message' && item.actor === 'user'}
    in:fly={{ y: 12, duration: 180 }}
  >
    {#if item.kind === 'message'}
      <article
        class="max-w-[88%] rounded-2xl border px-4 py-3 shadow-sm"
        class:bg-primary={item.actor === 'user'}
        class:text-primary-foreground={item.actor === 'user'}
        class:bg-card={item.actor === 'assistant'}
      >
        <div class="mb-1 flex flex-wrap items-center gap-1.5">
          <p class="text-sm font-medium">
            {item.actor === 'user' ? session.userAuthorLabel : 'Sverlin Assistant'}
          </p>
          {#if item.context}
            <Badge variant={item.actor === 'user' ? 'secondary' : 'outline'}>
              {contextLabel(item)}
            </Badge>
          {/if}
        </div>
        <MessageContent content={item.content} onReferenceActivate={activateReference} />
      </article>
    {:else if item.kind === 'presentation'}
      {@const id = item.value.presentation.presentationId}
      {@const selected = selectedIds.includes(id)}
      <article
        class="w-full rounded-2xl border bg-card px-4 py-3 shadow-sm transition-[border-color,background-color]"
        class:border-primary={selected}
        class:bg-muted={selected}
      >
        <button
          type="button"
          class="block w-full text-left focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
          aria-pressed={selected}
          onclick={(event) => activatePresentation(item, event)}
        >
          <span class="flex items-baseline gap-2 text-base font-medium">
            <span>Visualization</span>
            <span class="font-mono text-sm text-muted-foreground">
              {presentationDisplayId(id)}
            </span>
          </span>
          <span class="mt-1 block text-sm text-muted-foreground">
            {item.value.presentation.format === 'sverlin-ir-v1'
              ? `Seed ${item.value.presentation.seed} · `
              : ''}Select to view{layout === 'comparison'
              ? ' · Shift-select a compatible visualization to compare'
              : ''}
          </span>
        </button>
        {#if !session.readOnly}
          <div class="mt-2 flex justify-end">
            <Button size="xs" variant="outline" onclick={() => onReferenceRequest(item.value)}>
              Reference
            </Button>
          </div>
        {/if}
      </article>
    {:else}
      <article class="w-full rounded-2xl border border-destructive/50 bg-destructive/10 px-4 py-3">
        <p class="text-sm font-medium text-destructive">The request could not be completed</p>
        <p class="mt-1 text-base">{item.text}</p>
      </article>
    {/if}
  </li>
{/each}

{#if session.pending}
  <li in:fly={{ y: 12, duration: 180 }}>
    <div
      class="flex max-w-[88%] items-center gap-2 rounded-2xl border bg-card px-4 py-3 text-base text-muted-foreground shadow-sm"
      role="status"
    >
      <Spinner />
      <span>Sverlin Assistant is working…</span>
    </div>
  </li>
{:else if session.refillPending}
  <li in:fly={{ y: 12, duration: 180 }}>
    <div
      class="flex max-w-[88%] items-center gap-2 rounded-2xl border bg-card px-4 py-3 text-base text-muted-foreground shadow-sm"
      role="status"
    >
      <Spinner />
      <span>Generating more visualizations…</span>
    </div>
  </li>
{:else if session.refillError}
  <li in:fly={{ y: 12, duration: 180 }}>
    <div class="flex max-w-[88%] items-center gap-3 rounded-2xl border bg-card px-4 py-3 shadow-sm">
      <p class="text-sm text-muted-foreground">More visualizations could not be generated.</p>
      <Button size="sm" variant="outline" onclick={() => session.retryPresentationRefill()}
        >Retry</Button
      >
    </div>
  </li>
{/if}
