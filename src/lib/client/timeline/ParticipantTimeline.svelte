<script lang="ts">
  import { fly } from 'svelte/transition';

  import { Spinner } from '$lib/client/components/ui/spinner';
  import type { ProjectSession } from '$lib/client/projects/project-session.svelte';
  import { presentationDisplayId } from '$lib/client/visualization/presentation-history';
  import type { PresentationSelection } from '$lib/client/visualization/presentation-selection.svelte';
  import type { PresentationLayout } from '$lib/shared/presentations';

  import { participantTimeline } from './participant-timeline';

  type Props = {
    session: ProjectSession;
    selection: PresentationSelection;
    layout: PresentationLayout;
  };

  let { session, selection, layout }: Props = $props();
  const items = $derived(participantTimeline(session.events));
  const selectedIds = $derived(
    selection
      .selected(session.events, layout)
      .map(({ presentation }) => presentation.presentationId)
  );
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
        <p class="mb-1 text-sm font-medium">
          {item.actor === 'user' ? 'You' : 'Sverlin Assistant'}
        </p>
        <p class="text-base whitespace-pre-wrap">{item.text}</p>
      </article>
    {:else if item.kind === 'presentation'}
      {@const id = item.value.presentation.presentationId}
      {@const selected = selectedIds.includes(id)}
      <button
        type="button"
        class="w-full rounded-2xl border bg-card px-4 py-3 text-left shadow-sm transition-[border-color,background-color,transform] hover:-translate-y-0.5 hover:border-primary/60 focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
        class:border-primary={selected}
        class:bg-muted={selected}
        aria-pressed={selected}
        onclick={(event) => selection.activate(item.value, session.events, layout, event.shiftKey)}
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
            ? ' · Shift-select to build a comparison'
            : ''}
        </span>
      </button>
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
{/if}
