<script lang="ts">
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';

  import { Button } from '$lib/client/components/ui/button';
  import * as Field from '$lib/client/components/ui/field';
  import { Input } from '$lib/client/components/ui/input';

  import type { ActionData, PageData } from './$types';

  let { data, form }: { data: PageData; form: ActionData } = $props();
</script>

<svelte:head><title>Sverlin administration</title></svelte:head>

<main class="mx-auto flex min-h-screen max-w-5xl flex-col gap-10 p-8 text-foreground">
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
  {#if form?.participantPurged}
    <p class="rounded-md border p-3">Deleted participant {form.participantPurged}.</p>
  {/if}
  {#if form?.studyPurged}
    <p class="rounded-md border p-3">
      Deleted live study data for {form.participantsPurged} participant{form.participantsPurged ===
      1
        ? ''
        : 's'}.
    </p>
  {/if}
  {#if form?.error}<p class="rounded-md border border-destructive p-3 text-destructive">
      {form.error}
    </p>{/if}

  <section class="flex flex-col gap-4 rounded-lg border p-5">
    <h2 class="text-xl font-medium">Add participant</h2>
    <form method="POST" action="?/create" use:enhance class="flex max-w-xl items-end gap-3">
      <Field.Field class="flex-1">
        <Field.FieldLabel for="participant-id">Participant ID</Field.FieldLabel>
        <Input
          id="participant-id"
          name="participantId"
          required
          maxlength={128}
          autocomplete="off"
        />
      </Field.Field>
      <Button type="submit">Create participant</Button>
    </form>
  </section>

  <section class="flex flex-col gap-3">
    <div class="flex items-center justify-between gap-3">
      <div>
        <h2 class="text-xl font-medium">Participants</h2>
        <p class="text-sm text-muted-foreground">
          Exports contain research data and verified resources, not authentication secrets.
        </p>
      </div>
      <Button href={resolve('/admin/exports/study')} variant="outline">Download study export</Button
      >
    </div>
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
          <Button
            href={resolve('/admin/exports/participant/[userId]', { userId: participant.id })}
            variant="outline">Download export</Button
          >
          <form method="POST" action="?/access" use:enhance>
            <input type="hidden" name="id" value={participant.id} />
            <input type="hidden" name="enabled" value={String(!participant.enabled)} />
            <Button type="submit" variant={participant.enabled ? 'destructive' : 'secondary'}>
              {participant.enabled ? 'Disable' : 'Enable'}
            </Button>
          </form>
          <form
            method="POST"
            action="?/purgeParticipant"
            use:enhance
            class="flex basis-full items-end gap-3 border-t pt-4"
          >
            <input type="hidden" name="id" value={participant.id} />
            <Field.Field class="max-w-md flex-1">
              <Field.FieldLabel for={`purge-${participant.id}`}>
                Enter DELETE {participant.participantId}
              </Field.FieldLabel>
              <Input
                id={`purge-${participant.id}`}
                name="confirmation"
                required
                autocomplete="off"
              />
              <Field.FieldDescription>
                Export first if the approved research protocol permits retaining this data.
              </Field.FieldDescription>
            </Field.Field>
            <Button type="submit" variant="destructive">Delete participant data</Button>
          </form>
        </article>
      {/each}
    {/if}
  </section>

  <section class="flex flex-col gap-4 rounded-lg border border-destructive/50 p-5">
    <div>
      <h2 class="text-xl font-medium">Delete live study data</h2>
      <p class="text-sm text-muted-foreground">
        Download and verify the study export first. This deletes every participant account, project,
        retained queue record, and private resource while preserving the administrator.
      </p>
    </div>
    <form method="POST" action="?/purgeStudy" use:enhance class="flex max-w-xl items-end gap-3">
      <Field.Field class="flex-1">
        <Field.FieldLabel for="study-confirmation">Enter DELETE STUDY DATA</Field.FieldLabel>
        <Input id="study-confirmation" name="confirmation" required autocomplete="off" />
      </Field.Field>
      <Button type="submit" variant="destructive">Delete study data</Button>
    </form>
  </section>
</main>
