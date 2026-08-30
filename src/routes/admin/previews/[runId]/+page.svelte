<script lang="ts">
  import { resolve } from '$app/paths';

  import { Button } from '$lib/client/components/ui/button';
  import * as Card from '$lib/client/components/ui/card';
  import StudyFlowWireframe from '$lib/client/study/StudyFlowWireframe.svelte';

  import type { ActionData, PageData } from './$types';

  let { data, form }: { data: PageData; form: ActionData } = $props();
  const phase = $derived(data.state.phase);
  const title = $derived(phase.kind === 'task' ? phase.instructions.title : phase.title);
</script>

<svelte:head><title>{title} · Study preview</title></svelte:head>

<main class="dark grid min-h-screen place-items-center bg-background p-6 text-foreground">
  <div class="flex w-full max-w-3xl flex-col gap-4">
    <StudyFlowWireframe flow={data.state.flow} />
    <Card.Root>
      <Card.Header>
        <Card.Title>{title}</Card.Title>
        <Card.Description>Durable administrator preview</Card.Description>
      </Card.Header>
      <Card.Content class="flex flex-col gap-3 text-sm text-muted-foreground">
        {#if form?.error}<p role="alert" class="text-destructive">{form.error}</p>{/if}
        {#if phase.kind === 'task'}
          <p>{phase.instructions.prompt}</p>
        {:else}
          {#each phase.paragraphs as paragraph (paragraph)}<p>{paragraph}</p>{/each}
        {/if}
      </Card.Content>
      <Card.Footer class="flex justify-between gap-3">
        <Button href={resolve('/admin')} variant="outline">Return to administration</Button>
        {#if !data.state.completed}
          <form method="POST"><Button type="submit">Force next phase</Button></form>
        {/if}
      </Card.Footer>
    </Card.Root>
  </div>
</main>
