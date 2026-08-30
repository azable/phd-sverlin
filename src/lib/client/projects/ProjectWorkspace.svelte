<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { onMount, untrack } from 'svelte';

  import LogOutIcon from '@lucide/svelte/icons/log-out';
  import PencilIcon from '@lucide/svelte/icons/pencil';
  import SettingsIcon from '@lucide/svelte/icons/settings';

  import * as Alert from '$lib/client/components/ui/alert';
  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import { Input } from '$lib/client/components/ui/input';
  import { Label } from '$lib/client/components/ui/label';
  import * as Resizable from '$lib/client/components/ui/resizable';
  import { Skeleton } from '$lib/client/components/ui/skeleton';
  import { Switch } from '$lib/client/components/ui/switch';
  import * as Tabs from '$lib/client/components/ui/tabs';
  import PhaseExpiredDialog from '$lib/client/study/PhaseExpiredDialog.svelte';
  import StudyTimer from '$lib/client/study/StudyTimer.svelte';
  import FeedbackComposer from '$lib/client/timeline/FeedbackComposer.svelte';
  import Timeline from '$lib/client/timeline/Timeline.svelte';
  import PresentationStage from '$lib/client/visualization/PresentationStage.svelte';
  import { PresentationSelection } from '$lib/client/visualization/presentation-selection.svelte';
  import type { PresentationLayout } from '$lib/shared/presentations';
  import type { ProjectTemplateSummary } from '$lib/shared/projects/creation';
  import type { EventId } from '$lib/shared/projects/events';

  import NewProjectDialog from './NewProjectDialog.svelte';
  import ProjectArtifactPanel, {
    type ProjectArtifactEditMode
  } from './ProjectArtifactPanel.svelte';
  import { ProjectSession } from './project-session.svelte';

  type StudyTask =
    | {
        context: 'participant';
        phaseId: string;
        title: string;
        prompt: string;
        deadlineAt?: string;
        expired: boolean;
        layout: PresentationLayout;
      }
    | {
        context: 'admin-preview';
        previewKey: string;
        phaseId: string;
        title: string;
        prompt: string;
        deadlineAt: string;
        expired: boolean;
        layout: PresentationLayout;
      };

  type Props = {
    projectId: string;
    templates: ProjectTemplateSummary[];
    authEnabled?: boolean;
    isAdmin?: boolean;
    at?: EventId;
    devMode?: boolean;
    study?: StudyTask;
  };

  let {
    projectId,
    templates,
    authEnabled = false,
    isAdmin = false,
    at,
    devMode = false,
    study
  }: Props = $props();

  // The route keys this component by project ID, so the session is intentionally instance-scoped.
  // svelte-ignore state_referenced_locally
  const session = new ProjectSession(
    projectId,
    isAdmin && study?.context !== 'admin-preview' && devMode,
    study?.layout ?? 'single'
  );
  const presentationSelection = new PresentationSelection();
  let editMode = $state<ProjectArtifactEditMode>('readonly');
  let renaming = $state(false);
  let titleDraft = $state('');
  // The route keys this component when the study task changes.
  // svelte-ignore state_referenced_locally
  let layout = $state<PresentationLayout>(study?.layout ?? 'single');
  // svelte-ignore state_referenced_locally
  let expired = $state(study?.expired ?? false);

  const adminPreview = $derived(study?.context === 'admin-preview');
  const showAdminControls = $derived(isAdmin && !adminPreview);
  const developerView = $derived(showAdminControls && devMode);
  const busy = $derived(!!session.pending || session.creating);
  const mutationsDisabled = $derived(busy || expired || session.readOnly || editMode === 'editing');
  const presentationCount = $derived<1 | 2>(
    session.loaded && session.snapshot.renderer === 'sverlin' && layout === 'comparison' ? 2 : 1
  );
  const activeSeed = $derived.by(() => {
    const presentation = session.loaded
      ? session.snapshot.activePresentationSet?.presentations[0]
      : undefined;
    if (presentation?.type === 'visualization.rendered') return presentation.payload.seed;
    if (
      presentation?.type === 'visualization.presented' &&
      presentation.payload.presentation.format === 'sverlin-ir-v1'
    ) {
      return presentation.payload.presentation.seed;
    }
    return 1;
  });

  onMount(() => {
    void session.open();
    return () => session.dispose();
  });

  $effect(() => {
    const selectedAt = at;
    untrack(() => session.select(selectedAt));
  });

  function selectProject(event: Event) {
    const selected = (event.currentTarget as HTMLSelectElement).value;
    if (selected === projectId) return;
    const path = resolve('/projects/[projectId]', { projectId: selected });
    // eslint-disable-next-line svelte/no-navigation-without-resolve
    void goto(developerView ? `${path}?dev=1` : path);
  }

  function startRenaming() {
    titleDraft = session.snapshot.title;
    renaming = true;
  }

  async function rename(event: SubmitEvent) {
    event.preventDefault();
    if (await session.runCommand({ type: 'rename', title: titleDraft })) renaming = false;
  }

  function toggleDevMode(enabled: boolean) {
    if (!isAdmin) return;
    const path = resolve('/projects/[projectId]', { projectId });
    // eslint-disable-next-line svelte/no-navigation-without-resolve
    void goto(enabled ? `${path}?dev=1` : path, {
      keepFocus: true,
      noScroll: true,
      replaceState: true
    });
  }
</script>

<div class="dark h-screen overflow-hidden bg-background text-foreground">
  {#if session.loaded}
    <main class="flex h-full min-w-[72rem] flex-col overflow-hidden">
      {#if study}
        <header class="flex items-center gap-3 border-b bg-card px-4 py-2">
          <div class="mr-auto min-w-0">
            <div class="flex items-center gap-2">
              <p class="text-base font-medium">{study.title}</p>
              {#if study.context === 'admin-preview'}<Badge variant="secondary">Preview</Badge>{/if}
            </div>
            <p class="truncate text-sm text-muted-foreground">{study.prompt}</p>
          </div>
          {#if study.deadlineAt && !expired}
            <Badge variant="secondary">
              <StudyTimer deadlineAt={study.deadlineAt} onExpire={() => (expired = true)} />
            </Badge>
          {/if}
          {#if study.context === 'admin-preview'}
            <form method="POST" action="?/restartPreview">
              <input type="hidden" name="previewKey" value={study.previewKey} />
              <Button type="submit" size="sm" variant="outline">Restart preview</Button>
            </form>
            <Button href={resolve('/admin')} size="sm">Return to administration</Button>
          {:else if authEnabled}
            <form method="POST" action={resolve('/logout')}>
              <Button type="submit" size="icon-sm" variant="ghost" aria-label="Sign out"
                ><LogOutIcon /></Button
              >
            </form>
          {/if}
        </header>
      {/if}

      <Resizable.PaneGroup direction="horizontal" class="min-h-0 flex-1">
        <Resizable.Pane defaultSize={32} minSize={24} class="min-w-0">
          <Tabs.Root value="timeline" class="h-full min-w-0 gap-0 rounded-none border-r">
            <Tabs.List
              variant="line"
              class="w-full shrink-0 justify-start rounded-none border-b px-4"
            >
              <Tabs.Trigger value="timeline">Timeline</Tabs.Trigger>
              {#if developerView}<Badge variant="secondary">Developer details</Badge>{/if}
              {#if showAdminControls}
                <select
                  class="ml-auto h-8 max-w-40 rounded-md border bg-background px-2 text-sm"
                  value={projectId}
                  onchange={selectProject}
                  disabled={mutationsDisabled}
                  aria-label="Open project"
                >
                  {#each session.projects as project (project.projectId)}
                    <option value={project.projectId}>{project.title}</option>
                  {/each}
                </select>
                {#if renaming}
                  <form class="flex items-center gap-1" onsubmit={rename}>
                    <Input class="h-8 w-32" bind:value={titleDraft} aria-label="Project title" />
                    <Button type="submit" size="sm">Save</Button>
                  </form>
                {:else}
                  <Button
                    size="icon-sm"
                    variant="ghost"
                    onclick={startRenaming}
                    aria-label="Rename project"><PencilIcon /></Button
                  >
                {/if}
                <NewProjectDialog
                  {session}
                  {templates}
                  devMode={developerView}
                  disabled={mutationsDisabled}
                />
              {/if}
            </Tabs.List>
            <Tabs.Content value="timeline" class="flex min-h-0 flex-1 flex-col">
              {#if developerView}
                <div class="flex items-center border-b bg-muted px-4 py-2 text-sm">
                  <span class="mr-auto text-muted-foreground">Complete retained event details</span>
                  <Button
                    href={`/api/projects/${encodeURIComponent(projectId)}`}
                    size="xs"
                    variant="outline">Raw JSON</Button
                  >
                </div>
              {/if}
              <Timeline
                {session}
                seed={activeSeed}
                selection={presentationSelection}
                {layout}
                inspect={developerView}
              />
              {#if !expired && !session.readOnly}
                <FeedbackComposer {session} {presentationCount} {presentationSelection} {layout} />
              {/if}
            </Tabs.Content>
          </Tabs.Root>
        </Resizable.Pane>

        <Resizable.Handle withHandle />

        <Resizable.Pane defaultSize={68} minSize={50} class="flex min-w-0 flex-col">
          {#if showAdminControls}
            <div class="flex items-center gap-2 border-b px-3 py-1.5 text-sm">
              <span class="text-muted-foreground">Presentation layout</span>
              <select
                class="h-7 rounded-md border bg-background px-2"
                bind:value={layout}
                disabled={busy}
              >
                <option value="single">Single</option>
                <option value="comparison">Comparison</option>
              </select>
              <div class="ml-auto flex items-center gap-1">
                <div class="flex items-center gap-1">
                  <Switch
                    id="dev-mode"
                    size="sm"
                    checked={developerView}
                    onCheckedChange={toggleDevMode}
                  />
                  <Label for="dev-mode" class="text-sm">Dev</Label>
                </div>
                {#if authEnabled}
                  <Button
                    href={resolve('/admin')}
                    size="icon-sm"
                    variant="ghost"
                    aria-label="Administration"><SettingsIcon /></Button
                  >
                  <form method="POST" action={resolve('/logout')}>
                    <Button type="submit" size="icon-sm" variant="ghost" aria-label="Sign out"
                      ><LogOutIcon /></Button
                    >
                  </form>
                {/if}
              </div>
            </div>
          {/if}
          <PresentationStage
            {session}
            selection={presentationSelection}
            {layout}
            disabled={mutationsDisabled}
          />
          <ProjectArtifactPanel {session} {presentationCount} bind:editMode />
        </Resizable.Pane>
      </Resizable.PaneGroup>
    </main>
  {:else}
    <main class="grid h-full place-items-center">
      <div class="flex w-full max-w-md flex-col gap-3">
        <Skeleton class="h-8 w-48" />
        <Skeleton class="h-4 w-2/3" />
        <Skeleton class="h-4 w-5/6" />
      </div>
    </main>
  {/if}

  {#if session.error}
    <div class="pointer-events-none fixed inset-x-6 bottom-6 z-50 mx-auto max-w-3xl">
      <Alert.Root variant="destructive" class="pointer-events-auto">
        <Alert.Title>Project operation failed</Alert.Title>
        <Alert.Description>{session.error}</Alert.Description>
      </Alert.Root>
    </div>
  {/if}
  {#if study}
    <PhaseExpiredDialog
      open={expired}
      context={study.context}
      previewKey={study.context === 'admin-preview' ? study.previewKey : undefined}
    />
  {/if}
</div>
