<script lang="ts">
  import { fly } from 'svelte/transition';

  import SparklesIcon from '@lucide/svelte/icons/sparkles';
  import UserRoundIcon from '@lucide/svelte/icons/user-round';

  import * as Avatar from '$lib/client/components/ui/avatar';
  import { Button } from '$lib/client/components/ui/button';
  import { Spinner } from '$lib/client/components/ui/spinner';
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
      reference: Extract<MessageContentSegment, { type: 'element-ref' }>,
      extend: boolean
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
    if (reference.type === 'presentation-ref') {
      onPresentationChange();
      selection.activate(presentation, session.events, layout, extend);
      return;
    }
    selection.activate(presentation, session.events, layout);
    onElementReferenceActivate(reference, extend);
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
        class="max-w-[88%] rounded-2xl border px-4 py-3 shadow-md"
        class:bg-primary={item.actor === 'user'}
        class:text-primary-foreground={item.actor === 'user'}
        class:bg-card={item.actor === 'assistant'}
      >
        <div class="mb-2 flex flex-wrap items-center gap-2.5">
          <Avatar.Root size="lg" class="shadow-sm" aria-hidden="true">
            <Avatar.Fallback class="[&>svg]:size-5">
              {#if item.actor === 'user'}
                <UserRoundIcon />
              {:else}
                <SparklesIcon />
              {/if}
            </Avatar.Fallback>
          </Avatar.Root>
          <p class="text-base font-medium">
            {item.actor === 'user' ? session.userAuthorLabel : 'Assistant'}
          </p>
        </div>
        <MessageContent
          content={item.content}
          inverted={item.actor === 'user'}
          onReferenceActivate={activateReference}
        />
      </article>
    {:else if item.kind === 'presentation'}
      {@const id = item.value.presentation.presentationId}
      {@const selected = selectedIds.includes(id)}
      <article
        class="relative w-full rounded-2xl border bg-card px-4 py-3 shadow-md transition-[border-color,background-color,box-shadow,transform] hover:-translate-y-0.5 hover:border-primary/60 hover:shadow-lg"
        class:border-primary={selected}
        class:bg-muted={selected}
      >
        <button
          type="button"
          class="absolute inset-0 rounded-2xl focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
          aria-label={`Candidate ${presentationDisplayId(id)}`}
          aria-pressed={selected}
          onclick={(event) => activatePresentation(item, event)}
        ></button>
        <div class="pointer-events-none relative">
          <span class="flex items-baseline gap-2 text-base font-medium">
            <span>Candidate</span>
            {#if !session.readOnly}
              <Button
                size="xs"
                variant="outline"
                class="pointer-events-auto relative z-10 font-mono"
                aria-label={`Add ${presentationDisplayId(id)} to feedback`}
                onclick={(event) => {
                  event.stopPropagation();
                  onReferenceRequest(item.value);
                }}
              >
                {presentationDisplayId(id)}
              </Button>
            {:else}
              <span class="font-mono text-sm text-muted-foreground">
                {presentationDisplayId(id)}
              </span>
            {/if}
          </span>
          <span class="mt-1 block text-sm text-muted-foreground">
            {item.value.presentation.format === 'sverlin-ir-v1'
              ? `Seed ${item.value.presentation.seed} · `
              : ''}Click to view{layout === 'comparison'
              ? ' · Shift-click another compatible candidate to compare'
              : ''}
          </span>
        </div>
      </article>
    {:else}
      <article
        class="w-full rounded-2xl border border-destructive/50 bg-destructive/10 px-4 py-3 shadow-md"
      >
        <p class="text-sm font-medium text-destructive">The request could not be completed</p>
        <p class="mt-1 text-base">{item.text}</p>
      </article>
    {/if}
  </li>
{/each}

{#if session.pending}
  <li in:fly={{ y: 12, duration: 180 }}>
    <div
      class="flex max-w-[88%] items-center gap-2 rounded-2xl border bg-card px-4 py-3 text-base text-muted-foreground shadow-md"
      role="status"
    >
      <Spinner />
      <span>Assistant is working…</span>
    </div>
  </li>
{:else if session.refillPending}
  <li in:fly={{ y: 12, duration: 180 }}>
    <div
      class="flex max-w-[88%] items-center gap-2 rounded-2xl border bg-card px-4 py-3 text-base text-muted-foreground shadow-md"
      role="status"
    >
      <Spinner />
      <span>Generating more visualizations…</span>
    </div>
  </li>
{:else if session.refillError}
  <li in:fly={{ y: 12, duration: 180 }}>
    <div class="flex max-w-[88%] items-center gap-3 rounded-2xl border bg-card px-4 py-3 shadow-md">
      <p class="text-sm text-muted-foreground">More visualizations could not be generated.</p>
      <Button size="sm" variant="outline" onclick={() => session.retryPresentationRefill()}
        >Retry</Button
      >
    </div>
  </li>
{/if}
