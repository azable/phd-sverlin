<script lang="ts">
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';
  import { onMount } from 'svelte';

  import AddParticipantDialog from '$lib/client/admin/AddParticipantDialog.svelte';
  import AdminProjectList from '$lib/client/admin/AdminProjectList.svelte';
  import DeleteParticipantDialog from '$lib/client/admin/DeleteParticipantDialog.svelte';
  import GeneratePasswordDialog from '$lib/client/admin/GeneratePasswordDialog.svelte';
  import GiftCardDialog from '$lib/client/admin/GiftCardDialog.svelte';
  import StudyPreviewDialog from '$lib/client/admin/StudyPreviewDialog.svelte';
  import * as Alert from '$lib/client/components/ui/alert';
  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import * as Card from '$lib/client/components/ui/card';
  import * as Field from '$lib/client/components/ui/field';
  import { Input } from '$lib/client/components/ui/input';
  import { Separator } from '$lib/client/components/ui/separator';
  import StudyFlowWireframe from '$lib/client/study/StudyFlowWireframe.svelte';

  import type { ActionData, PageData } from './$types';

  let { data, form }: { data: PageData; form: ActionData } = $props();
  let polledParticipants = $state.raw<PageData['participants']>();
  const participants = $derived(polledParticipants ?? data.participants);
  let pollTimer: ReturnType<typeof setInterval> | undefined;

  // Five seconds keeps researcher-visible progress near-live without a persistent connection or
  // issuing a database query for every countdown tick.
  const progressPollMilliseconds = 5_000;

  async function refreshProgress() {
    try {
      const response = await fetch(resolve('/admin/status'), { cache: 'no-store' });
      if (!response.ok) return;
      const payload = (await response.json()) as { participants: PageData['participants'] };
      polledParticipants = payload.participants;
    } catch {
      // The next visibility change or interval retries without disrupting admin operations.
    }
  }

  function startPolling() {
    if (pollTimer || document.visibilityState !== 'visible') return;
    void refreshProgress();
    pollTimer = setInterval(() => void refreshProgress(), progressPollMilliseconds);
  }

  function stopPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = undefined;
  }

  function visibilityChanged() {
    if (document.visibilityState === 'visible') startPolling();
    else stopPolling();
  }

  function previewHref(preview: PageData['studies'][number]['previews'][number]): string {
    return preview.phase.kind === 'task' && preview.projectId && !preview.completed
      ? resolve('/projects/[projectId]', { projectId: preview.projectId })
      : resolve('/admin/previews/[runId]', { runId: preview.runId });
  }

  function studyExportHref(studyId: string, version: number): string {
    const parameters = new URLSearchParams({ studyId, version: String(version) });
    return `${resolve('/admin/exports/study')}?${parameters}`;
  }

  onMount(() => {
    startPolling();
    return stopPolling;
  });
</script>

<svelte:document onvisibilitychange={visibilityChanged} />
<svelte:head><title>Sverlin administration</title></svelte:head>

<main class="mx-auto flex min-h-screen max-w-6xl flex-col gap-10 p-8 text-foreground">
  <header class="flex flex-wrap items-center justify-between gap-3">
    <div>
      <p class="text-sm text-muted-foreground">Administration</p>
      <h1 class="text-3xl font-semibold">Research studies</h1>
    </div>
    <div class="flex items-center gap-2">
      <Button href={resolve('/')} variant="outline">Back to projects</Button>
      <form method="POST" action={resolve('/logout')}>
        <Button type="submit" variant="outline">Sign out</Button>
      </form>
    </div>
  </header>

  {#if form?.participantPassword}
    <Alert.Root>
      <Alert.Title>Credentials for {form.participantId}</Alert.Title>
      <Alert.Description>
        Copy this password now. It is shown once and cannot be recovered.
        <Input class="mt-3 font-mono text-sm" readonly value={form.participantPassword} />
      </Alert.Description>
    </Alert.Root>
  {/if}
  {#if form?.participantPurged}<Alert.Root
      ><Alert.Title>Participant deleted</Alert.Title><Alert.Description
        >Deleted participant {form.participantPurged}.</Alert.Description
      ></Alert.Root
    >{/if}
  {#if form?.studyPurged}<Alert.Root
      ><Alert.Title>Study data deleted</Alert.Title><Alert.Description
        >Deleted live study data for {form.participantsPurged} participants.</Alert.Description
      ></Alert.Root
    >{/if}
  {#if form?.giftCardUpdated}<Alert.Root><Alert.Title>Gift card updated</Alert.Title></Alert.Root
    >{/if}
  {#if form?.error}<Alert.Root variant="destructive"
      ><Alert.Title>Administration action failed</Alert.Title><Alert.Description
        >{form.error}</Alert.Description
      ></Alert.Root
    >{/if}

  <section class="flex flex-col gap-4">
    <div>
      <h2 class="text-xl font-medium">Configured studies</h2>
      <p class="text-sm text-muted-foreground">
        Definitions are immutable code configuration. Closed versions remain available for previews
        and exports.
      </p>
    </div>
    {#each data.studies as study (`${study.definition.id}@${study.definition.version}`)}
      <Card.Root>
        <Card.Header>
          <Card.Title class="flex flex-wrap items-center gap-2">
            {study.definition.name}
            <span class="text-muted-foreground">v{study.definition.version}</span>
            <Badge variant={study.enrollment === 'open' ? 'default' : 'outline'}
              >{study.enrollment}</Badge
            >
          </Card.Title>
          <Card.Description>{study.definition.description}</Card.Description>
        </Card.Header>
        <Card.Content class="flex flex-col gap-5">
          <div class="flex flex-wrap gap-2 text-sm text-muted-foreground">
            <span
              >{study.participantCount} participant{study.participantCount === 1 ? '' : 's'}</span
            >
            {#each Object.entries(study.armCounts) as [arm, total] (arm)}
              <Badge variant="outline">{arm}: {total}</Badge>
            {/each}
          </div>
          <StudyFlowWireframe flow={study.flow} linkProjects={false} />
          {#if study.previews.length}
            <div class="flex flex-col gap-2">
              <h3 class="font-medium">Durable previews</h3>
              <div class="flex flex-wrap gap-2">
                {#each study.previews as preview (preview.runId)}
                  <Button href={previewHref(preview)} size="sm" variant="outline">
                    {preview.armId} · {preview.completed ? 'Completed' : 'Resume'}
                  </Button>
                {/each}
              </div>
            </div>
          {/if}
        </Card.Content>
        <Card.Footer class="flex flex-wrap justify-end gap-2">
          <Button
            href={studyExportHref(study.definition.id, study.definition.version)}
            variant="outline">Download version export</Button
          >
          <StudyPreviewDialog definition={study.definition} />
        </Card.Footer>
      </Card.Root>
    {/each}
  </section>

  <section class="flex flex-col gap-3">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-xl font-medium">Administrator projects and previews</h2>
        <p class="text-sm text-muted-foreground">
          Participant research projects are listed only in their assigned flow below.
        </p>
      </div>
      <Button href={resolve('/admin/exports/analysis')} variant="outline"
        >Download analysis export</Button
      >
    </div>
    <AdminProjectList
      projects={data.allProjects}
      emptyMessage="No administrator projects have been created."
      showOwner
    />
  </section>

  <section class="flex min-w-0 flex-col gap-3">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-xl font-medium">Participants</h2>
        <p class="text-sm text-muted-foreground">
          Study projects and chat logs are read-only to administrators.
        </p>
      </div>
      <div class="flex flex-wrap justify-end gap-2">
        <AddParticipantDialog studies={data.studies} />
        <Button href={resolve('/admin/exports/study')} variant="outline"
          >Download all-study export</Button
        >
      </div>
    </div>
    {#if participants.length === 0}
      <p class="text-muted-foreground">No participants have been provisioned.</p>
    {:else}
      {#each participants as participant (participant.id)}
        <Card.Root>
          <Card.Header>
            <Card.Title class="flex flex-wrap items-center gap-2">
              <span class="font-mono">{participant.participantId}</span>
              <Badge variant={participant.giftCardUrl ? 'default' : 'destructive'}>
                {participant.giftCardUrl ? 'Gift card assigned' : 'No gift card'}
              </Badge>
              <Badge variant={participant.enabled ? 'secondary' : 'outline'}>
                {participant.enabled ? 'Enabled' : 'Disabled'}
              </Badge>
            </Card.Title>
            <Card.Description>
              {participant.studyId ?? 'No study assignment'}{participant.studyVersion
                ? ` · v${participant.studyVersion}`
                : ''}
            </Card.Description>
          </Card.Header>
          <Card.Content class="flex flex-col gap-4">
            {#if participant.flow}
              <StudyFlowWireframe flow={participant.flow} />
            {:else}
              <Alert.Root variant="destructive"
                ><Alert.Title>Missing study assignment</Alert.Title></Alert.Root
              >
            {/if}
            <div class="flex flex-wrap gap-2">
              {#if participant.enabled}<GeneratePasswordDialog {participant} />{/if}
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
            </div>
          </Card.Content>
          <Card.Footer class="flex flex-col items-stretch gap-3">
            <Separator />
            <DeleteParticipantDialog {participant} />
          </Card.Footer>
        </Card.Root>
      {/each}
    {/if}
  </section>

  <section class="flex flex-col gap-4 rounded-lg border border-destructive/50 p-5">
    <div>
      <h2 class="text-xl font-medium">Delete live study data</h2>
      <p class="text-sm text-muted-foreground">
        Download and verify the all-study export first. This explicitly purges participant accounts
        and linked research data.
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
