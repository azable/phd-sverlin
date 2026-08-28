<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';

  import { Button } from '$lib/client/components/ui/button';

  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();
  let creating = $state(false);
  let error = $state<string | null>(null);

  async function createProject(templateId: string) {
    if (creating) return;
    creating = true;
    error = null;
    try {
      const response = await fetch('/api/projects', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ templateId })
      });
      const value = (await response.json()) as {
        projectId?: string;
        jobId?: string;
        error?: string;
      };
      if (!response.ok || !value.projectId)
        throw new Error(value.error || 'Project creation failed.');
      const path = resolve('/projects/[projectId]', { projectId: value.projectId });
      // The route is resolved above; the optional query resumes durable work.
      // eslint-disable-next-line svelte/no-navigation-without-resolve
      await goto(value.jobId ? `${path}?job=${encodeURIComponent(value.jobId)}` : path);
    } catch (cause) {
      error = cause instanceof Error ? cause.message : 'Project creation failed.';
    } finally {
      creating = false;
    }
  }
</script>

<svelte:head><title>Sverlin</title></svelte:head>

<main class="mx-auto flex min-h-screen max-w-4xl items-center p-8">
  <section class="w-full space-y-6">
    <div class="flex items-start justify-between gap-4">
      <div>
        <p class="text-sm text-muted-foreground">Sverlin</p>
        <h1 class="text-3xl font-semibold">Create your first project</h1>
        <p class="mt-2 text-muted-foreground">
          Choose a starting point. Compilation continues safely in the background.
        </p>
      </div>
      {#if data.isAdmin}<Button href={resolve('/admin')} variant="outline">Administration</Button
        >{/if}
    </div>
    {#if error}<p class="rounded-md border border-destructive p-3 text-destructive">{error}</p>{/if}
    <div class="grid gap-4 sm:grid-cols-2">
      {#each data.templates as template (template.id)}
        <article class="flex flex-col rounded-lg border p-5">
          <h2 class="text-lg font-medium">{template.title}</h2>
          <p class="mt-2 flex-1 text-sm text-muted-foreground">{template.summary}</p>
          <Button class="mt-5" disabled={creating} onclick={() => createProject(template.id)}>
            {creating ? 'Creating…' : 'Use template'}
          </Button>
        </article>
      {/each}
    </div>
  </section>
</main>
