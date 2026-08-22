<script lang="ts">
  /* eslint-disable svelte/no-navigation-without-resolve -- historyHref resolves the route before adding its query. */
  import { resolve } from '$app/paths';

  import AlertCircleIcon from '@lucide/svelte/icons/circle-alert';
  import BotIcon from '@lucide/svelte/icons/bot';
  import CodeIcon from '@lucide/svelte/icons/code-2';
  import MessageIcon from '@lucide/svelte/icons/message-circle';
  import PlayIcon from '@lucide/svelte/icons/play';
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';

  import { Badge } from '$lib/components/ui/badge';
  import { Button } from '$lib/components/ui/button';
  import * as Card from '$lib/components/ui/card';
  import type { ProjectSession } from '$lib/client/projects/project-session.svelte';
  import type { ProjectEvent } from '$lib/shared/projects/events';

  import { presentProjectEvent } from './event-presentation';

  /** Public properties for one project Timeline event card. */
  type Props = { event: ProjectEvent; seed: number; session: ProjectSession };

  let { event, seed, session }: Props = $props();

  const presentation = $derived(presentProjectEvent(event));

  async function restore() {
    await session.runCommand({
      type: 'restore',
      from: event.id,
      seed
    });
  }

  function formatTime(value: string) {
    return new Intl.DateTimeFormat(undefined, { timeStyle: 'short' }).format(new Date(value));
  }

  function historyHref() {
    return `${resolve('/projects/[projectId]', {
      projectId: session.projectId
    })}?at=${event.id}`;
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

<article aria-current={session.snapshot.at === event.id ? 'step' : undefined}>
  <Card.Root size="sm">
    <Card.Header>
      <Card.Title>
        <a class="hover:underline" href={historyHref()}>{presentation.title}</a>
      </Card.Title>
      <Card.Action>
        <Badge variant={presentation.tone === 'destructive' ? 'destructive' : 'outline'}>
          #{event.id}
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
      {#if event.id !== session.head}
        <Button
          size="xs"
          variant={session.focusedEvents.includes(event.id) ? 'secondary' : 'ghost'}
          onclick={() => session.toggleFocus(event.id)}
        >
          {session.focusedEvents.includes(event.id) ? 'Focused' : 'Focus'}
        </Button>
      {/if}
      {#if presentation.restorable && event.id !== session.head}
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
