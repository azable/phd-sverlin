<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';

  import { Button } from '$lib/client/components/ui/button';
  import * as Card from '$lib/client/components/ui/card';
  import ExamplePreview from '$lib/client/visualization/ExamplePreview.svelte';
  import {
    examplePreviewPath,
    randomExampleSeed
  } from '$lib/client/visualization/example-preview-navigation';
  import { page } from '$app/state';

  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();
  const examples = $derived(data.templates.filter(({ id }) => id !== 'blank'));
  let selectedTemplateId = $derived(examples[0]?.id ?? '');
  const exampleId = $derived(page.url.searchParams.get('example') ?? '');
  const requestedSeed = $derived(Number(page.url.searchParams.get('seed')));
  const seed = $derived(
    Number.isSafeInteger(requestedSeed) && requestedSeed > 0 ? requestedSeed : undefined
  );

  function loadExample(event: SubmitEvent) {
    event.preventDefault();
    if (!selectedTemplateId) return;
    const path = examplePreviewPath(selectedTemplateId, randomExampleSeed());
    // eslint-disable-next-line svelte/no-navigation-without-resolve
    void goto(path);
  }
</script>

<svelte:head><title>Examples · Sverlin</title></svelte:head>

{#if examples.some(({ id }) => id === exampleId)}
  <ExamplePreview {exampleId} {seed} templates={examples} />
{:else}
  <main class="mx-auto flex min-h-screen w-full max-w-3xl flex-col gap-6 p-8">
    <Button href={resolve('/')} size="sm" variant="outline" class="self-start">Projects</Button>
    <Card.Root>
      <Card.Header>
        <Card.Title>Explore Sverlin examples</Card.Title>
        <Card.Description>
          Choose a source to compile and view its visualization without creating a project.
        </Card.Description>
      </Card.Header>
      <Card.Content>
        <form class="flex flex-wrap items-end gap-3" onsubmit={loadExample}>
          <label
            class="flex min-w-64 flex-1 flex-col gap-1 text-sm font-medium"
            for="example-source"
          >
            Example
            <select
              id="example-source"
              class="h-9 rounded-md border bg-background px-3"
              bind:value={selectedTemplateId}
            >
              {#each examples as example (example.id)}
                <option value={example.id}>{example.title}</option>
              {/each}
            </select>
          </label>
          <Button type="submit" disabled={!selectedTemplateId}>Load example</Button>
        </form>
      </Card.Content>
    </Card.Root>
  </main>
{/if}
