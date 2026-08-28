<script lang="ts">
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';

  import { Button } from '$lib/client/components/ui/button';
  import { Input } from '$lib/client/components/ui/input';
  import { Label } from '$lib/client/components/ui/label';

  import type { ActionData, PageData } from './$types';

  let { data, form }: { data: PageData; form: ActionData } = $props();
</script>

<svelte:head><title>Sverlin administration</title></svelte:head>

<main class="mx-auto min-h-screen max-w-5xl space-y-10 p-8 text-foreground">
  <header class="flex items-center justify-between">
    <div>
      <p class="text-sm text-muted-foreground">Administration</p>
      <h1 class="text-3xl font-semibold">Research participants</h1>
    </div>
    <div class="flex items-center gap-2">
      <Button href={resolve('/')} variant="outline">Back to projects</Button>
      <form method="POST" action={resolve('/logout')}>
        <Button type="submit" variant="outline">Sign out</Button>
      </form>
    </div>
  </header>

  {#if form?.participantPassword}
    <section class="rounded-lg border border-primary/30 bg-muted p-5">
      <h2 class="font-medium">Credentials for {form.participantId}</h2>
      <p class="mt-1 text-sm text-muted-foreground">
        Copy this password now. It is shown once and cannot be recovered.
      </p>
      <Input class="mt-3 font-mono text-sm" readonly value={form.participantPassword} />
    </section>
  {/if}
  {#if form?.error}<p class="rounded-md border border-destructive p-3 text-destructive">
      {form.error}
    </p>{/if}

  <section class="space-y-4 rounded-lg border p-5">
    <h2 class="text-xl font-medium">Add participant</h2>
    <form method="POST" action="?/create" use:enhance class="flex max-w-xl items-end gap-3">
      <div class="flex-1 space-y-2">
        <Label for="participant-id">Participant ID</Label>
        <Input
          id="participant-id"
          name="participantId"
          required
          maxlength={128}
          autocomplete="off"
        />
      </div>
      <Button type="submit">Create participant</Button>
    </form>
  </section>

  <section class="space-y-3">
    <h2 class="text-xl font-medium">Participants</h2>
    {#if data.participants.length === 0}
      <p class="text-muted-foreground">No participants have been provisioned.</p>
    {:else}
      {#each data.participants as participant (participant.id)}
        <article class="flex flex-wrap items-center gap-4 rounded-lg border p-4">
          <div class="mr-auto">
            <h3 class="font-mono font-medium">{participant.participantId}</h3>
            <p class="text-sm text-muted-foreground">
              {participant.projectCount} project{participant.projectCount === 1 ? '' : 's'} ·
              {participant.enabled ? 'enabled' : 'disabled'}
            </p>
          </div>
          {#if participant.enabled}
            <form method="POST" action="?/password" use:enhance>
              <input type="hidden" name="id" value={participant.id} />
              <Button type="submit" variant="outline">Generate new password</Button>
            </form>
          {/if}
          <form method="POST" action="?/access" use:enhance>
            <input type="hidden" name="id" value={participant.id} />
            <input type="hidden" name="enabled" value={String(!participant.enabled)} />
            <Button type="submit" variant={participant.enabled ? 'destructive' : 'secondary'}>
              {participant.enabled ? 'Disable' : 'Enable'}
            </Button>
          </form>
        </article>
      {/each}
    {/if}
  </section>

  <section class="space-y-4 rounded-lg border border-destructive/50 p-5">
    <div>
      <h2 class="text-xl font-medium">Reset study projects</h2>
      <p class="text-sm text-muted-foreground">
        Deletes every project and private project resource. Participant accounts remain.
      </p>
    </div>
    <form method="POST" action="?/resetProjects" use:enhance class="flex max-w-xl items-end gap-3">
      <div class="flex-1 space-y-2">
        <Label for="confirmation">Enter DELETE PROJECTS</Label>
        <Input id="confirmation" name="confirmation" required autocomplete="off" />
      </div>
      <Button type="submit" variant="destructive">Reset projects</Button>
    </form>
  </section>
</main>
