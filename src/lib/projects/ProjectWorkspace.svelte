<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { onDestroy, onMount, untrack } from 'svelte';

  import FilePlusIcon from '@lucide/svelte/icons/file-plus-2';
  import PencilIcon from '@lucide/svelte/icons/pencil';

  import * as Alert from '$lib/components/ui/alert';
  import { Button } from '$lib/components/ui/button';
  import { Input } from '$lib/components/ui/input';
  import * as Resizable from '$lib/components/ui/resizable';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import * as Tabs from '$lib/components/ui/tabs';
  import FeedbackComposer from '$lib/timeline/FeedbackComposer.svelte';
  import Timeline from '$lib/timeline/Timeline.svelte';
  import { TracePlayer } from '$lib/visualization/trace-player.svelte';
  import TraceToolbar from '$lib/visualization/TraceToolbar.svelte';
  import TraceViewport from '$lib/visualization/TraceViewport.svelte';
  import type { VisualId } from '$lib/visualization/types';

  import ProjectArtifactPanel, {
    type ProjectArtifactEditMode
  } from './ProjectArtifactPanel.svelte';
  import ProjectOperationStatus from './ProjectOperationStatus.svelte';
  import { ProjectSession } from './project-session.svelte';
  import type { ProjectPageState, ProjectSummary, VisualSelectionAttachment } from './types';

  let { data }: { data: ProjectPageState & { projects: ProjectSummary[] } } = $props();

  const session = new ProjectSession(() => data);
  const player = new TracePlayer();

  let seedText = $state(String(untrack(() => data.snapshot.activeRender?.payload.seed ?? 1)));
  let selectedVisualIds = $state<VisualId[]>([]);
  let editMode = $state<ProjectArtifactEditMode>('readonly');
  let renaming = $state(false);
  let titleDraft = $state(untrack(() => data.snapshot.title));
  let loadedRenderEventId: string | null = null;

  const sourceEditing = $derived(editMode === 'editing');
  const interactionLocked = $derived(sourceEditing || !!session.pending || !session.atHead);
  const activeSeed = $derived(readSeed(seedText, session.snapshot.activeRender?.payload.seed ?? 1));
  const visualSelection = $derived.by<VisualSelectionAttachment | undefined>(() => {
    const render = session.snapshot.activeRender;
    if (!render || player.currentStep < 0 || selectedVisualIds.length === 0) return undefined;
    const elements = player.elements
      .filter((element) => selectedVisualIds.includes(element.id))
      .map((element) => ({
        elementId: element.id,
        instanceId: element.instanceId,
        role: element.role,
        ...(element.content ? { content: element.content } : {}),
        kind: element.kind,
        style: element.style,
        styleVariables: element.styleVariables
      }));
    if (elements.length === 0) return undefined;
    return {
      kind: 'visual-selection',
      renderEventId: render.eventId,
      sourceEventId: render.eventId,
      judgement: 'neutral',
      step: { index: player.currentStep, label: player.currentStepLabel },
      elements
    };
  });

  onMount(() => session.connectLive());

  $effect(() => {
    const renderEventId = session.snapshot.activeRender?.eventId ?? null;
    const trace = session.trace;
    if (!trace) {
      if (player.hasTrace) player.clear();
      loadedRenderEventId = null;
      selectedVisualIds = [];
      return;
    }
    if (renderEventId === loadedRenderEventId) return;
    const priorStep = player.currentStep;
    loadedRenderEventId = renderEventId;
    player.setTrace(trace, { initialStep: priorStep < 0 ? 0 : priorStep });
    seedText = String(session.snapshot.activeRender?.payload.seed ?? 1);
    selectedVisualIds = [];
  });

  onDestroy(() => player.dispose());

  async function regenerate(nextSeed = seedText) {
    seedText = nextSeed;
    const seed = parseSeed(nextSeed);
    if (seed === null) {
      session.error = 'Seed must be a positive safe integer.';
      return;
    }
    await session.runAction('render', { seed: String(seed) });
  }

  async function rename(event: SubmitEvent) {
    event.preventDefault();
    const succeeded = await session.runAction('rename', { title: titleDraft });
    if (succeeded) renaming = false;
  }

  function selectProject(event: Event) {
    const projectId = (event.currentTarget as HTMLSelectElement).value;
    if (projectId !== session.document.projectId) {
      void goto(resolve('/projects/[projectId]', { projectId }));
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
              value={session.document.projectId}
              onchange={selectProject}
              aria-label="Open project"
              disabled={!!session.pending || sourceEditing}
            >
              {#each data.projects as project (project.projectId)}
                <option value={project.projectId}>
                  {project.projectId === session.document.projectId
                    ? session.snapshot.title
                    : project.title}
                </option>
              {/each}
            </select>
            {#if renaming}
              <form class="flex items-center gap-1" onsubmit={rename}>
                <Input class="h-8 w-40" bind:value={titleDraft} aria-label="Project title" />
                <Button type="submit" size="sm" disabled={!titleDraft.trim()}>Save</Button>
                <Button type="button" size="sm" variant="ghost" onclick={() => (renaming = false)}>
                  Cancel
                </Button>
              </form>
            {:else}
              <Button
                type="button"
                size="sm"
                variant="ghost"
                onclick={() => {
                  titleDraft = session.snapshot.title;
                  renaming = true;
                }}
                disabled={!session.atHead || !!session.pending || sourceEditing}
                aria-label="Rename project"
              >
                <PencilIcon />
              </Button>
            {/if}
            <form method="POST" action="?/newProject">
              <Button type="submit" size="sm" variant="ghost" disabled={!!session.pending}>
                <FilePlusIcon data-icon="inline-start" />New project
              </Button>
            </form>
          </Tabs.List>
          <Tabs.Content value="timeline" class="flex min-h-0 flex-1 flex-col">
            <Timeline {session} seed={activeSeed} />
            <FeedbackComposer {session} seed={activeSeed} selection={visualSelection} />
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
            <TraceToolbar
              bind:seedText
              canNext={player.canNext}
              canPrevious={player.canPrevious}
              currentStep={player.currentStep}
              hasTrace={player.hasTrace}
              locked={interactionLocked}
              loadingTrace={!player.hasTrace && !!session.pending}
              onNext={() => player.next()}
              onPrevious={() => player.previous()}
              onRegenerate={regenerate}
              onReset={() => player.reset()}
              regenerating={session.pending?.action === 'render'}
              stepCount={player.stepCount}
            />

            <div
              class="relative min-h-0 flex-1 overflow-hidden bg-white"
              aria-label="Visualization canvas"
            >
              {#if player.hasTrace}
                <TraceViewport
                  bind:selectedIds={selectedVisualIds}
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
                  <ProjectOperationStatus {session} />
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

  {#if session.error}
    <div class="pointer-events-none fixed inset-x-6 bottom-6 z-50 mx-auto max-w-3xl">
      <Alert.Root variant="destructive" class="pointer-events-auto">
        <Alert.Title>Project operation failed</Alert.Title>
        <Alert.Description>{session.error}</Alert.Description>
      </Alert.Root>
    </div>
  {/if}
</div>
