<script lang="ts">
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';

  import AddParticipantDialog from '$lib/client/admin/AddParticipantDialog.svelte';
  import AdminProjectList from '$lib/client/admin/AdminProjectList.svelte';
  import DeleteParticipantDialog from '$lib/client/admin/DeleteParticipantDialog.svelte';
  import GeneratePasswordDialog from '$lib/client/admin/GeneratePasswordDialog.svelte';
  import GiftCardDialog from '$lib/client/admin/GiftCardDialog.svelte';
  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import * as Field from '$lib/client/components/ui/field';
  import { Input } from '$lib/client/components/ui/input';
  import { Separator } from '$lib/client/components/ui/separator';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import * as ToggleGroup from '$lib/client/components/ui/toggle-group';

  import type { SubmitFunction } from '@sveltejs/kit';

  import type { ActionData, PageData } from './$types';

  let { data, form }: { data: PageData; form: ActionData } = $props();
  let preparingPreview = $state(false);
  let selectedPreviewKey = $derived(data.previewOptions[0]?.key ?? '');
  const selectedPreview = $derived(
    data.previewOptions.find(({ key }) => key === selectedPreviewKey)
  );

  function selectPreview(value: string | string[]) {
    if (typeof value === 'string' && value) selectedPreviewKey = value;
  }

  const preparePreview: SubmitFunction = () => {
    preparingPreview = true;
    return async ({ update }) => {
      await update();
      preparingPreview = false;
    };
  };
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
  {#if form?.giftCardUpdated}
    <p class="rounded-md border p-3">Updated the participant gift-card link.</p>
  {/if}
  {#if form?.error}<p class="rounded-md border border-destructive p-3 text-destructive">
      {form.error}
    </p>{/if}

  <section class="flex flex-col gap-4 rounded-lg border p-5">
    <div>
      <h2 class="text-xl font-medium">Study preview</h2>
      <p class="text-sm text-muted-foreground">
        Create a fresh administrator project using one active study condition. Its configured timer
        starts after the initial visualization is ready.
      </p>
    </div>
    <form method="POST" action="?/createPreview" use:enhance={preparePreview}>
      <Field.FieldSet disabled={preparingPreview}>
        <Field.FieldLegend>Condition</Field.FieldLegend>
        <Field.FieldDescription>
          Preview projects are retained in the project directory for later inspection.
        </Field.FieldDescription>
        <input type="hidden" name="previewKey" value={selectedPreviewKey} />
        <ToggleGroup.Root
          type="single"
          value={selectedPreviewKey}
          onValueChange={selectPreview}
          spacing={2}
          variant="outline"
          class="flex-wrap justify-start"
          aria-label="Study condition to preview"
        >
          {#each data.previewOptions as option (option.key)}
            <ToggleGroup.Item value={option.key} class="h-auto min-w-44 flex-col items-start p-3">
              <span class="font-medium">{option.name}</span>
              <span class="text-xs font-normal text-muted-foreground">{option.label}</span>
            </ToggleGroup.Item>
          {/each}
        </ToggleGroup.Root>
        <Button type="submit" disabled={!selectedPreview || preparingPreview}>
          {#if preparingPreview}
            <Spinner data-icon="inline-start" />Preparing preview
          {:else}
            Create {selectedPreview?.name ?? 'study'} preview
          {/if}
        </Button>
      </Field.FieldSet>
    </form>
  </section>

  <section class="flex flex-col gap-3">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-xl font-medium">All projects</h2>
        <p class="text-sm text-muted-foreground">
          Administrator and participant projects, most recently updated first.
        </p>
      </div>
      <Button href={resolve('/admin/exports/analysis')} variant="outline">
        Download analysis export
      </Button>
    </div>
    <AdminProjectList
      projects={data.allProjects}
      emptyMessage="No projects have been created."
      showOwner
    />
  </section>

  <section class="flex min-w-0 flex-col gap-3">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-xl font-medium">Participants</h2>
        <p class="text-sm text-muted-foreground">
          Exports contain research data and verified resources, not authentication secrets.
        </p>
      </div>
      <div class="flex flex-wrap justify-end gap-2">
        <AddParticipantDialog />
        <Button href={resolve('/admin/exports/study')} variant="outline">
          Download study export
        </Button>
      </div>
    </div>
    {#if data.participants.length === 0}
      <p class="text-muted-foreground">No participants have been provisioned.</p>
    {:else}
      {#each data.participants as participant (participant.id)}
        <article class="flex flex-wrap items-center gap-4 rounded-lg border p-4">
          <div class="mr-auto">
            <div class="flex items-center gap-2">
              <h3 class="font-mono font-medium">{participant.participantId}</h3>
              <Badge variant={participant.giftCardUrl ? 'default' : 'destructive'}>
                {participant.giftCardUrl ? 'Gift card assigned' : 'No gift card'}
              </Badge>
            </div>
            <p class="text-sm text-muted-foreground">
              {participant.projectCount} project{participant.projectCount === 1 ? '' : 's'} ·
              {participant.enabled ? 'enabled' : 'disabled'}
            </p>
          </div>
          {#if participant.enabled}
            <GeneratePasswordDialog {participant} />
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

          <GiftCardDialog {participant} />

          <div class="flex basis-full flex-col gap-2">
            <h4 class="font-medium">Projects</h4>
            <AdminProjectList
              projects={participant.projects}
              emptyMessage="This participant has no projects yet."
            />
          </div>

          <Separator class="basis-full" />
          <DeleteParticipantDialog {participant} />
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
