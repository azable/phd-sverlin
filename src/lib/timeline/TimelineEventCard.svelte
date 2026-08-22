<script lang="ts">
  import { resolve } from '$app/paths';
  import type { Pathname } from '$app/types';

  import AlertCircleIcon from '@lucide/svelte/icons/circle-alert';
  import BotIcon from '@lucide/svelte/icons/bot';
  import CodeIcon from '@lucide/svelte/icons/code-2';
  import MessageIcon from '@lucide/svelte/icons/message-circle';
  import PlayIcon from '@lucide/svelte/icons/play';
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';

  import { Badge } from '$lib/components/ui/badge';
  import { Button } from '$lib/components/ui/button';
  import * as Card from '$lib/components/ui/card';
  import type { ProjectSession } from '$lib/projects/project-session.svelte';
  import type { ProjectEvent } from '$lib/projects/types';

  import { presentProjectEvent } from './event-presentation';

  let { event, seed, session }: { event: ProjectEvent; seed: number; session: ProjectSession } =
    $props();

  const presentation = $derived(presentProjectEvent(event));

  async function restore() {
    await session.runAction('restore', {
      restoredFromEventId: event.eventId,
      seed: String(seed)
    });
  }

  function formatTime(value: string) {
    return new Intl.DateTimeFormat(undefined, { timeStyle: 'short' }).format(new Date(value));
  }
</script>

<span
  class="timeline-node absolute top-4 left-0 flex size-6 items-center justify-center rounded-full border bg-background"
  data-tone={presentation.tone}
>
  {#if presentation.icon === 'message'}
    <MessageIcon class="size-3" />
  {:else if presentation.icon === 'assistant'}
    <BotIcon class="size-3" />
  {:else if presentation.icon === 'code'}
    <CodeIcon class="size-3" />
  {:else if presentation.icon === 'visualization'}
    <PlayIcon class="size-3" />
  {:else if presentation.icon === 'failure'}
    <AlertCircleIcon class="size-3" />
  {:else}
    <span class="size-1.5 rounded-full bg-current"></span>
  {/if}
</span>

<article aria-current={session.cursorEventId === event.eventId ? 'step' : undefined}>
  <Card.Root size="sm">
    <Card.Header>
      <Card.Title>
        <a
          class="hover:underline"
          href={resolve(
            `/projects/${encodeURIComponent(session.document.projectId)}?at=${encodeURIComponent(event.eventId)}` as Pathname
          )}>{presentation.title}</a
        >
      </Card.Title>
      <Card.Action>
        <Badge variant={presentation.tone === 'destructive' ? 'destructive' : 'outline'}>
          #{event.sequence}
        </Badge>
      </Card.Action>
      <Card.Description class="line-clamp-4 whitespace-pre-wrap">
        {presentation.detail}
      </Card.Description>
    </Card.Header>
    <Card.Footer class="flex-wrap gap-2">
      <span class="mr-auto text-[0.7rem] text-muted-foreground">
        {formatTime(event.createdAt)}
      </span>
      {#if session.atHead && event.eventId !== session.headEventId}
        <Button
          size="xs"
          variant="ghost"
          onclick={() => session.attachTimelineEvent(event.eventId, 'reference')}
        >
          Attach
        </Button>
      {/if}
      {#if presentation.restorable && event.eventId !== session.headEventId}
        <Button size="xs" variant="ghost" onclick={restore} disabled={!!session.pending}>
          <RotateCcwIcon data-icon="inline-start" />Restore
        </Button>
      {/if}
    </Card.Footer>
  </Card.Root>
</article>

<style>
  .timeline-node {
    color: var(--primary);
    border-color: var(--timeline-stalk);
  }

  .timeline-node[data-tone='destructive'] {
    color: var(--destructive);
    border-color: var(--destructive);
  }
</style>
