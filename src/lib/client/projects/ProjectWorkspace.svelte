<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { onMount, untrack } from 'svelte';

  import FilePlusIcon from '@lucide/svelte/icons/file-plus-2';
  import PencilIcon from '@lucide/svelte/icons/pencil';

  import * as Alert from '$lib/client/components/ui/alert';
  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import { Input } from '$lib/client/components/ui/input';
  import * as Resizable from '$lib/client/components/ui/resizable';
  import { Skeleton } from '$lib/client/components/ui/skeleton';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import * as Tabs from '$lib/client/components/ui/tabs';
  import FeedbackComposer from '$lib/client/timeline/FeedbackComposer.svelte';
  import Timeline from '$lib/client/timeline/Timeline.svelte';
  import { presentProjectEvent } from '$lib/client/timeline/event-presentation';
  import { VisualizationPlayer } from '$lib/client/visualization/visualization-player.svelte';
  import VisualizationToolbar from '$lib/client/visualization/VisualizationToolbar.svelte';
  import VisualizationViewport from '$lib/client/visualization/VisualizationViewport.svelte';
  import type { EventId } from '$lib/shared/projects/events';
  import type { VisualSelection } from '$lib/shared/projects/events/values';
  import type { RenderInstanceId } from '$lib/shared/visualization';

  import ProjectArtifactPanel, {
    type ProjectArtifactEditMode
  } from './ProjectArtifactPanel.svelte';
  import { ProjectSession } from './project-session.svelte';

  /** Public properties for a complete project workspace. */
  type Props = { projectId: string; at?: EventId };

  let { projectId, at }: Props = $props();

  // The parent keys this component by projectId, so this is intentionally instance-scoped.
  // svelte-ignore state_referenced_locally
  const session = new ProjectSession(projectId);
  const player = new VisualizationPlayer();

  let seedText = $state('1');
  let selectedInstanceIds = $state<RenderInstanceId[]>([]);
  let editMode = $state<ProjectArtifactEditMode>('readonly');
  let renaming = $state(false);
  let titleDraft = $state('');
  let loadedRenderEventId: EventId | null = null;

  const sourceEditing = $derived(editMode === 'editing');
  const playbackDisabled = $derived(sourceEditing || !!session.pending);
  const renderDisabled = $derived(playbackDisabled || !session.atHead);
  const activeSeed = $derived(
    readSeed(seedText, session.resource ? (session.snapshot.activeRender?.payload.seed ?? 1) : 1)
  );
  const selection = $derived.by<VisualSelection | undefined>(() => {
    const render = session.resource ? session.snapshot.activeRender : undefined;
    if (!render || player.currentStep < 0 || selectedInstanceIds.length === 0) return undefined;
    return {
      render: render.id,
      step: player.currentStep,
      instances: selectedInstanceIds,
      judgement: 'neutral'
    };
  });
  const operationMessage = $derived.by(() => {
    const event = session.pendingEvent;
    if (event) return presentProjectEvent(event).progress;
    if (session.connection === 'reconnecting') return 'Working; reconnecting live updates…';
    if (session.pending?.type === 'feedback') return 'Submitting feedback…';
    if (session.pending?.type === 'rename') return 'Renaming the project…';
    return 'Compiling and loading…';
  });

  onMount(() => {
    void session.open();
    return () => session.dispose();
  });

  $effect(() => {
    const selectedAt = at;
    untrack(() => session.select(selectedAt));
  });

  $effect(() => {
    const renderEventId = session.resource ? (session.snapshot.activeRender?.id ?? null) : null;
    const visualization = session.visualization;
    if (renderEventId === loadedRenderEventId) return;
    loadedRenderEventId = renderEventId;
    const seed = session.resource ? (session.snapshot.activeRender?.payload.seed ?? 1) : 1;

    untrack(() => {
      if (visualization) player.setVisualization(visualization, { initialStep: 0 });
      else if (player.hasVisualization) player.clear();
      seedText = String(seed);
      selectedInstanceIds = [];
    });
  });

  onMount(() => () => player.dispose());

  async function regenerate(nextSeed = seedText) {
    seedText = nextSeed;
    const seed = parseSeed(nextSeed);
    if (seed === null) {
      session.error = 'Seed must be a positive safe integer.';
      return;
    }
    await session.runCommand({ type: 'render', seed });
  }

  async function rename(event: SubmitEvent) {
    event.preventDefault();
    const succeeded = await session.runCommand({ type: 'rename', title: titleDraft });
    if (succeeded) renaming = false;
  }

  function startRenaming() {
    titleDraft = session.snapshot.title;
    renaming = true;
  }

  function selectProject(event: Event) {
    const selectedProjectId = (event.currentTarget as HTMLSelectElement).value;
    if (selectedProjectId !== projectId) {
      void goto(resolve('/projects/[projectId]', { projectId: selectedProjectId }));
    }
  }

  function parseSeed(value: string) {
    const seed = Number(value.trim());
    return Number.isSafeInteger(seed) && seed > 0 ? seed : null;
  }

  function readSeed(value: string, fallback: number) {
    return parseSeed(value) ?? fallback;
  }
</script>

<div class="dark h-screen overflow-hidden bg-background text-foreground">
  {#if session.resource}
    <main class="h-full min-w-0 overflow-x-auto" inert={!!session.pending}>
      <Resizable.PaneGroup direction="horizontal" class="min-h-full min-w-[72rem]">
        <Resizable.Pane defaultSize={35} minSize={25} class="min-w-0">
          <Tabs.Root value="timeline" class="h-full min-w-0 gap-0 rounded-none border-r">
            <Tabs.List
              variant="line"
              class="w-full shrink-0 justify-start rounded-none border-b px-4"
            >
              <Tabs.Trigger value="timeline">Timeline</Tabs.Trigger>
              <select
                class="ml-auto h-8 max-w-44 rounded-md border bg-background px-2 text-xs"
                value={projectId}
                onchange={selectProject}
                aria-label="Open project"
                disabled={!!session.pending || sourceEditing}
              >
                {#each session.projects as project (project.projectId)}
                  <option value={project.projectId}>
                    {project.projectId === projectId ? session.snapshot.title : project.title}
                  </option>
                {/each}
              </select>
              {#if renaming}
                <form class="flex items-center gap-1" onsubmit={rename}>
                  <Input class="h-8 w-40" bind:value={titleDraft} aria-label="Project title" />
                  <Button type="submit" size="sm" disabled={!titleDraft.trim()}>Save</Button>
                  <Button
                    type="button"
                    size="sm"
                    variant="ghost"
                    onclick={() => (renaming = false)}
                  >
                    Cancel
                  </Button>
                </form>
              {:else}
                <Button
                  type="button"
                  size="sm"
                  variant="ghost"
                  onclick={startRenaming}
                  disabled={!session.atHead || !!session.pending || sourceEditing}
                  aria-label="Rename project"
                >
                  <PencilIcon />
                </Button>
              {/if}
              <Button
                type="button"
                size="sm"
                variant="ghost"
                disabled={!!session.pending}
                onclick={() => session.createProject()}
              >
                <FilePlusIcon data-icon="inline-start" />New project
              </Button>
            </Tabs.List>
            <Tabs.Content value="timeline" class="flex min-h-0 flex-1 flex-col">
              <Timeline {session} seed={activeSeed} />
              <FeedbackComposer {session} seed={activeSeed} {selection} />
            </Tabs.Content>
          </Tabs.Root>
        </Resizable.Pane>

        <Resizable.Handle withHandle />

        <Resizable.Pane defaultSize={65} minSize={45} class="min-w-0">
          <Resizable.PaneGroup direction="vertical" class="h-full min-h-0">
            <Resizable.Pane
              defaultSize={65}
              minSize={40}
              class="flex min-h-0 flex-col overflow-hidden"
            >
              <VisualizationToolbar
                bind:seedText
                canNext={player.canNext}
                canPrevious={player.canPrevious}
                currentStep={player.currentStep}
                hasVisualization={player.hasVisualization}
                {playbackDisabled}
                {renderDisabled}
                loadingVisualization={!player.hasVisualization && !!session.pending}
                onNext={() => player.next()}
                onPrevious={() => player.previous()}
                onRegenerate={regenerate}
                onReset={() => player.reset()}
                regenerating={session.pending?.type === 'render'}
                stepCount={player.stepCount}
              />

              <div
                class="relative min-h-0 flex-1 overflow-hidden bg-white"
                aria-label="Visualization canvas"
              >
                {#if player.hasVisualization}
                  <VisualizationViewport
                    bind:selectedIds={selectedInstanceIds}
                    elements={player.elements}
                    height={player.canvasHeight}
                    width={player.canvasWidth}
                  />
                {:else}
                  <div class="flex min-h-full min-w-full items-center justify-center p-6">
                    <div class="flex w-full max-w-md flex-col gap-3">
                      <Skeleton class="h-8 w-48" />
                      <Skeleton class="h-4 w-2/3" />
                      <Skeleton class="h-4 w-5/6" />
                    </div>
                  </div>
                {/if}

                {#if session.pending}
                  <div
                    class="pointer-events-none absolute inset-0 grid place-items-center bg-background/40 backdrop-blur-[1px]"
                  >
                    <Badge variant="secondary" role="status" aria-live="polite">
                      <Spinner
                        data-icon="inline-start"
                        aria-label="Project operation in progress"
                      />
                      {operationMessage}
                    </Badge>
                  </div>
                {/if}
              </div>
            </Resizable.Pane>

            <Resizable.Handle withHandle />

            <Resizable.Pane defaultSize={35} minSize={25} class="min-h-0">
              <ProjectArtifactPanel {session} seed={activeSeed} bind:editMode />
            </Resizable.Pane>
          </Resizable.PaneGroup>
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
</div>
