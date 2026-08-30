<script lang="ts">
  import { resolve } from '$app/paths';
  import { tick } from 'svelte';
  import { fly } from 'svelte/transition';

  import { Button } from '$lib/client/components/ui/button';
  import { ScrollArea } from '$lib/client/components/ui/scroll-area';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import type { ProjectSession } from '$lib/client/projects/project-session.svelte';

  import TimelineEventCard from './TimelineEventCard.svelte';

  /** Public properties for the project Timeline. */
  type Props = { session: ProjectSession; seed: number; inspect?: boolean };

  let { session, seed, inspect = false }: Props = $props();
  let viewport = $state<HTMLElement | null>(null);
  let timelineEnd = $state<HTMLElement | null>(null);
  let following = $state(true);
  const projectPath = $derived(
    `${resolve('/projects/[projectId]', { projectId: session.projectId })}${inspect ? '?dev=1' : ''}`
  );
  const visibleEvents = $derived(
    inspect
      ? session.events
      : session.events.filter((event) =>
          [
            'project.created',
            'feedback.submitted',
            'assistant.responded',
            'visualization.rendered',
            'visualization.presented',
            'visualization.preference-recorded',
            'operation.failed',
            'system.notified'
          ].includes(event.type)
        )
  );

  $effect(() => {
    const node = viewport;
    if (!node) return;
    const updateFollowing = () => {
      following = node.scrollHeight - node.scrollTop - node.clientHeight < 48;
    };
    updateFollowing();
    node.addEventListener('scroll', updateFollowing, { passive: true });
    return () => node.removeEventListener('scroll', updateFollowing);
  });

  $effect.pre(() => {
    const eventCount = session.events.length + session.timeline.length;
    if (!session.atHead || !following || eventCount === 0) return;
    void tick().then(() => timelineEnd?.scrollIntoView({ block: 'end' }));
  });
</script>

<section class="flex min-h-0 flex-1 flex-col" aria-label="Project Timeline">
  {#if !session.atHead}
    <div class="flex items-center gap-2 border-b bg-muted px-4 py-2 text-xs">
      <span class="mr-auto"
        >Viewing historical state · mutations are disabled; playback remains available</span
      >
      <Button href={projectPath} size="sm" variant="outline">Return to present</Button>
    </div>
  {/if}
  <ScrollArea bind:viewportRef={viewport} class="min-h-0 flex-1">
    <ol class="timeline flex flex-col gap-3 p-4 pr-6">
      {#if session.timeline.length}
        {#each session.timeline as entry (entry.id)}
          <li class="timeline-event relative pl-8" in:fly={{ y: 12, duration: 180 }}>
            <article class="rounded-xl border bg-card px-4 py-3 shadow-sm">
              <p class="text-sm font-medium">{entry.title}</p>
              {#if entry.detail}
                <p class="mt-1 line-clamp-6 text-sm whitespace-pre-wrap text-muted-foreground">
                  {entry.detail}
                </p>
              {/if}
            </article>
          </li>
        {/each}
      {:else}
        {#each visibleEvents as event (event.id)}
          <li class="timeline-event relative pl-8" in:fly={{ y: 12, duration: 180 }}>
            <TimelineEventCard {event} {seed} {session} {inspect} />
          </li>
        {/each}
      {/if}
      {#if session.pending}
        <li class="timeline-event relative pl-8" in:fly={{ y: 12, duration: 180 }}>
          <div
            class="flex items-center gap-2 rounded-xl border bg-card px-4 py-3 text-sm text-muted-foreground"
            role="status"
          >
            <Spinner />
            <span>The assistant is working…</span>
          </div>
        </li>
      {/if}
      <li class="h-px" aria-hidden="true"><span bind:this={timelineEnd}></span></li>
    </ol>
  </ScrollArea>
</section>

<style>
  .timeline {
    --timeline-stalk: color-mix(in oklab, var(--primary) 42%, var(--border));
  }

  .timeline-event::before {
    position: absolute;
    top: -0.75rem;
    bottom: -0.75rem;
    left: 0.72rem;
    width: 2px;
    content: '';
    background: var(--timeline-stalk);
  }

  .timeline-event:first-child::before {
    top: 1rem;
  }

  .timeline-event:nth-last-child(2)::before {
    bottom: calc(100% - 1rem);
  }
</style>
