<script lang="ts">
  import { resolve } from '$app/paths';

  import { Button } from '$lib/client/components/ui/button';
  import * as Card from '$lib/client/components/ui/card';

  import type { ActionData, PageData } from './$types';

  let { data, form }: { data: PageData; form: ActionData } = $props();
  const phase = $derived(data.state.phase);
  const title = $derived(phase.kind === 'task' ? phase.instructions.title : phase.title);
</script>

<svelte:head><title>{title} · Sverlin study</title></svelte:head>

<main class="dark grid min-h-screen place-items-center bg-background p-6 text-foreground">
  <Card.Root class="w-full max-w-xl">
    <Card.Header>
      <Card.Title>{title}</Card.Title>
      {#if phase.kind === 'task' && data.state.expired}
        <Card.Description>Your time for this task has ended.</Card.Description>
      {/if}
    </Card.Header>
    <Card.Content class="space-y-3 text-sm text-muted-foreground">
      {#if form?.error}
        <p
          class="rounded-md border border-destructive/50 bg-destructive/10 p-3 text-destructive"
          role="alert"
        >
          {form.error}
        </p>
      {/if}
      {#if phase.kind === 'task'}
        <p>Your project has been locked. Continue when you are ready for the next phase.</p>
      {:else}
        {#each phase.paragraphs as paragraph (paragraph)}
          <p>{paragraph}</p>
        {/each}
      {/if}
    </Card.Content>
    {#if phase.kind !== 'completion'}
      <Card.Footer>
        <form method="POST" action={resolve('/study')}>
          <Button type="submit">
            {phase.kind === 'instruction' ? phase.continueLabel : 'Continue'}
          </Button>
        </form>
      </Card.Footer>
    {/if}
  </Card.Root>
</main>
