<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';

  import AdminProjectList from '$lib/client/admin/AdminProjectList.svelte';
  import * as Alert from '$lib/client/components/ui/alert';
  import { Button } from '$lib/client/components/ui/button';
  import * as Card from '$lib/client/components/ui/card';
  import { Separator } from '$lib/client/components/ui/separator';

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
        error?: string;
      };
      if (!response.ok || !value.projectId)
        throw new Error(value.error || 'Project creation failed.');
      const path = resolve('/projects/[projectId]', { projectId: value.projectId });
      await goto(path);
    } catch (cause) {
      error = cause instanceof Error ? cause.message : 'Project creation failed.';
    } finally {
      creating = false;
    }
  }
</script>

<svelte:head><title>Sverlin</title></svelte:head>

<main class="mx-auto flex min-h-screen w-full max-w-4xl flex-col gap-10 p-8">
  <header class="flex flex-wrap items-start justify-between gap-4">
    <div>
      <p class="text-sm text-muted-foreground">Sverlin</p>
      <h1 class="text-3xl font-semibold">Projects</h1>
      <p class="mt-2 text-muted-foreground">
        Open an administrator-owned project or create a new one. Participant research remains in the
        administration panel.
      </p>
    </div>
    {#if data.isAdmin}<Button href={resolve('/admin')} variant="outline">Administration</Button
      >{/if}
  </header>

  <section class="flex flex-col gap-4" aria-labelledby="owned-projects-title">
    <div>
      <h2 id="owned-projects-title" class="text-xl font-medium">Your projects and previews</h2>
      <p class="text-sm text-muted-foreground">
        Opening a project is always explicit from this list.
      </p>
    </div>
    <AdminProjectList
      projects={data.projects}
      emptyMessage="No administrator projects have been created."
    />
  </section>

  <Separator />

  <section class="flex flex-col gap-6" aria-labelledby="create-project-title">
    <div class="flex items-start justify-between gap-4">
      <div>
        <h2 id="create-project-title" class="text-xl font-medium">Create a project</h2>
        <p class="mt-2 text-muted-foreground">
          Choose a starting point. Compilation continues safely in the background.
        </p>
      </div>
    </div>
    {#if error}
      <Alert.Root variant="destructive">
        <Alert.Title>Project creation failed</Alert.Title>
        <Alert.Description>{error}</Alert.Description>
      </Alert.Root>
    {/if}
    <div class="grid gap-4 sm:grid-cols-2">
      {#each data.templates as template (template.id)}
        <Card.Root>
          <Card.Header>
            <Card.Title>{template.title}</Card.Title>
            <Card.Description>{template.summary}</Card.Description>
          </Card.Header>
          <Card.Footer class="mt-auto">
            <Button disabled={creating} onclick={() => createProject(template.id)}>
              {creating ? 'Creating…' : 'Use template'}
            </Button>
          </Card.Footer>
        </Card.Root>
      {/each}
    </div>
  </section>
</main>
