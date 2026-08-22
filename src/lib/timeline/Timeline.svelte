<script lang="ts">
  import { resolve } from '$app/paths';
  import { tick } from 'svelte';

  import { Button } from '$lib/components/ui/button';
  import { ScrollArea } from '$lib/components/ui/scroll-area';
  import type { ProjectSession } from '$lib/projects/project-session.svelte';

  import TimelineEventCard from './TimelineEventCard.svelte';

  let { session, seed }: { session: ProjectSession; seed: number } = $props();
  let viewport = $state<HTMLElement | null>(null);
  let timelineEnd = $state<HTMLElement | null>(null);
  let following = $state(true);
  const projectPath = $derived(
    resolve('/projects/[projectId]', { projectId: session.document.projectId })
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
    const eventCount = session.events.length;
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
      {#each session.events as event (event.id)}
        <li class="timeline-event relative pl-8">
          <TimelineEventCard {event} {seed} {session} />
        </li>
      {/each}
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
