<script lang="ts">
  import type { PageProps } from './$types';
  import { onMount, untrack } from 'svelte';

  import * as Alert from '$lib/components/ui/alert';
  import * as Card from '$lib/components/ui/card';
  import * as Resizable from '$lib/components/ui/resizable';
  import { ScrollArea } from '$lib/components/ui/scroll-area';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import * as Tabs from '$lib/components/ui/tabs';
  import ArtifactPanel from '$lib/artifacts/ArtifactPanel.svelte';
  import type { ArtifactEditMode } from '$lib/artifacts/types';
  import { ChatState } from '$lib/chat/chat-state.svelte';
  import ChatPanel from '$lib/chat/ChatPanel.svelte';
  import TraceCanvas from '$lib/visualization/TraceCanvas.svelte';
  import TraceToolbar from '$lib/visualization/TraceToolbar.svelte';
  import { TracePlayer } from '$lib/visualization/trace-player.svelte';
  import type {
    CompileLockHolder,
    CompileStatus,
    CompileStreamFailure,
    CompileStreamStatus,
    CompileStreamSuccess
  } from '$lib/visualization/types';

  let { data }: PageProps = $props();

  type CompilePhase = 'initial' | 'regenerate';

  const compileSrc = '/api/visualization';
  const compileStatusStreamSrc = '/api/visualization/status/stream';

  const player = new TracePlayer();
  const chat = new ChatState(untrack(() => data));

  let loadingTrace = $state(true);
  let regenerating = $state(false);
  let compileError = $state<string | null>(null);
  let seedText = $state('');
  let editMode = $state<ArtifactEditMode>('readonly');
  let compileMounted = $state(false);
  let lastArtifactStreamVersion = untrack(() => data.artifact.streamVersion);
  let activeCompileSource: EventSource | null = null;
  let activeCompileStatusSource: EventSource | null = null;
  let compileRetryTimer: ReturnType<typeof setTimeout> | null = null;
  let externalCompileLock = $state<CompileLockHolder | null>(null);
  let compileRunId = 0;
  const compileBusyRetryMs = 1_000;

  const compiling = $derived(loadingTrace || regenerating);
  const externalCompileActive = $derived(externalCompileLock !== null && !compiling);
  const toolbarExternalCompiling = $derived(externalCompileLock !== null && !loadingTrace);
  const interactionLocked = $derived(editMode !== 'readonly');
  const pageError = $derived(compileError);

  $effect(() => {
    if (!compileMounted) return;
    if (interactionLocked) return;
    const streamVersion = chat.artifact?.streamVersion;
    if (streamVersion === undefined || streamVersion === lastArtifactStreamVersion) return;
    lastArtifactStreamVersion = streamVersion;
    startCompile({ phase: 'regenerate' });
  });

  onMount(() => {
    compileMounted = true;
    startCompile({ phase: 'initial' });
    startCompileStatusStream();

    return () => {
      clearCompileRetry();
      stopCompileStatusStream();
      activeCompileSource?.close();
      player.dispose();
    };
  });

  function startCompile({
    phase = 'regenerate',
    nextSeedText = seedText
  }: {
    phase?: CompilePhase;
    nextSeedText?: string;
  } = {}) {
    let seed: number | null;

    try {
      seed = parseOptionalSeed(nextSeedText);
    } catch (err) {
      compileError = err instanceof Error ? err.message : String(err);
      return;
    }

    const runId = compileRunId + 1;
    compileRunId = runId;
    activeCompileSource?.close();
    clearCompileRetry();

    if (phase === 'initial') {
      loadingTrace = true;
    } else {
      regenerating = true;
    }

    externalCompileLock = null;
    compileError = null;

    const source = new EventSource(compileUrl(seed));
    activeCompileSource = source;

    function isCurrentRun() {
      return compileRunId === runId && activeCompileSource === source;
    }

    function finish() {
      if (!isCurrentRun()) return;

      source.close();
      activeCompileSource = null;
      loadingTrace = false;
      regenerating = false;
    }

    function fail(error: string, payload?: CompileStreamFailure) {
      if (!isCurrentRun()) return;

      if (payload?.status === 409) {
        if (typeof payload?.seed === 'number') {
          seedText = String(payload.seed);
        }

        source.close();
        activeCompileSource = null;
        compileRetryTimer = setTimeout(() => {
          if (compileRunId === runId) {
            startCompile({ phase, nextSeedText });
          }
        }, compileBusyRetryMs);
        return;
      }

      if (typeof payload?.seed === 'number') {
        seedText = String(payload.seed);
      }

      compileError = error;
      finish();
    }

    source.addEventListener('status', (event) => {
      if (!isCurrentRun()) return;

      try {
        const payload = readStreamEvent<CompileStreamStatus>(event);
        seedText = String(payload.seed);
      } catch (err) {
        fail(err instanceof Error ? err.message : String(err));
      }
    });

    source.addEventListener('trace', (event) => {
      if (!isCurrentRun()) return;

      try {
        const payload = readStreamEvent<CompileStreamSuccess>(event);
        seedText = String(payload.seed);
        player.setTrace(payload.trace, {
          initialStep: phase === 'initial' ? 0 : player.currentStep
        });
        finish();
      } catch (err) {
        fail(err instanceof Error ? err.message : String(err));
      }
    });

    source.addEventListener('error', (event) => {
      if (!isCurrentRun()) return;

      if (event instanceof MessageEvent && event.data) {
        try {
          const payload = readStreamEvent<CompileStreamFailure>(event);
          fail(payload.error, payload);
        } catch (err) {
          fail(err instanceof Error ? err.message : String(err));
        }
      } else {
        fail('Compile stream connection failed.');
      }
    });
  }

  function regenerateTrace(nextSeedText = seedText) {
    startCompile({ phase: 'regenerate', nextSeedText });
  }

  function startCompileStatusStream() {
    const source = new EventSource(compileStatusStreamSrc);
    activeCompileStatusSource = source;

    source.addEventListener('status', (event) => {
      if (activeCompileStatusSource !== source) return;

      try {
        applyCompileStatus(readStreamEvent<CompileStatus>(event));
      } catch {
        externalCompileLock = null;
      }
    });
  }

  function stopCompileStatusStream() {
    activeCompileStatusSource?.close();
    activeCompileStatusSource = null;
  }

  function applyCompileStatus(status: CompileStatus) {
    if (compiling) {
      externalCompileLock = null;
      return;
    }

    externalCompileLock = status.running ? status : null;

    if (status.running && typeof status.seed === 'number') {
      seedText = String(status.seed);
    }
  }

  function clearCompileRetry() {
    if (compileRetryTimer === null) return;

    clearTimeout(compileRetryTimer);
    compileRetryTimer = null;
  }

  function compileUrl(seed: number | null) {
    const url = new URL(compileSrc, window.location.origin);

    if (seed !== null) {
      url.searchParams.set('seed', String(seed));
    }

    return url;
  }

  function readStreamEvent<T>(event: Event): T {
    if (!(event instanceof MessageEvent) || typeof event.data !== 'string') {
      throw new Error('Compile stream sent an unreadable event.');
    }

    return JSON.parse(event.data) as T;
  }

  function parseOptionalSeed(value: string): number | null {
    const trimmed = value.trim();

    if (!trimmed) return null;

    const seed = Number(trimmed);

    if (!Number.isInteger(seed) || !Number.isSafeInteger(seed) || seed <= 0) {
      throw new Error('Seed must be a positive integer that JavaScript can represent safely.');
    }

    return seed;
  }
</script>

<div class="dark h-screen overflow-hidden bg-background text-foreground">
  <main class="h-full min-w-0 overflow-x-auto">
    <Resizable.PaneGroup direction="horizontal" class="min-h-full min-w-[72rem]">
      <Resizable.Pane defaultSize={35} minSize={25} class="min-w-0">
        <Tabs.Root value="chat" class="h-full min-w-0 gap-0 rounded-none border-r">
          <Tabs.List
            variant="line"
            class="w-full shrink-0 justify-start rounded-none border-b px-4"
          >
            <Tabs.Trigger value="chat">Chat</Tabs.Trigger>
          </Tabs.List>
          <Tabs.Content value="chat" class="flex min-h-0 flex-1 flex-col">
            <ChatPanel {chat} disabled={interactionLocked} />
          </Tabs.Content>
        </Tabs.Root>
      </Resizable.Pane>

      <Resizable.Handle withHandle />

      <Resizable.Pane defaultSize={65} minSize={45} class="min-w-0">
        <Resizable.PaneGroup direction="vertical" class="h-full min-h-0">
          <Resizable.Pane defaultSize={65} minSize={40} class="min-h-0 overflow-y-auto">
            <TraceToolbar
              bind:seedText
              canNext={player.canNext}
              canPrevious={player.canPrevious}
              currentStep={player.currentStep}
              externalCompiling={toolbarExternalCompiling}
              hasTrace={player.hasTrace}
              locked={interactionLocked}
              {loadingTrace}
              onNext={() => player.next()}
              onPrevious={() => player.previous()}
              onRegenerate={regenerateTrace}
              onReset={() => player.reset()}
              {regenerating}
              stepCount={player.stepCount}
            />

            <div
              class="mx-auto flex min-h-0 w-full max-w-screen-2xl flex-col items-center gap-4 p-4"
            >
              {#if loadingTrace || player.hasTrace}
                <Card.Root class="flex min-h-0 w-full flex-none">
                  <Card.Header>
                    <Card.Title
                      >{player.hasTrace ? 'Trace visualization' : 'Compiling trace'}</Card.Title
                    >
                    <Card.Description>
                      {#if player.hasTrace}
                        {#if externalCompileActive && externalCompileLock !== null}
                          External {externalCompileLock.owner} compile running
                        {:else}
                          Seed {seedText || 'random'}
                        {/if}
                      {:else}
                        {compileSrc}
                      {/if}
                    </Card.Description>
                  </Card.Header>

                  <Card.Content class="flex min-h-0 flex-col gap-3">
                    {#if player.hasTrace}
                      <ScrollArea
                        orientation="both"
                        class="min-h-0 rounded-lg border"
                        style={`height: ${player.canvasHeight + 24}px`}
                        aria-label="Visualization canvas"
                      >
                        <div
                          class="flex h-max min-h-full w-max min-w-full items-start justify-center py-3"
                        >
                          <div class="shrink-0">
                            <TraceCanvas
                              elements={player.elements}
                              height={player.canvasHeight}
                              width={player.canvasWidth}
                            />
                          </div>
                        </div>
                      </ScrollArea>
                    {:else}
                      <Skeleton class="h-8 w-48" />
                      <ScrollArea class="h-96 rounded-lg border bg-muted/40">
                        <div class="flex h-full flex-col gap-3 p-3">
                          <Skeleton class="h-4 w-2/3" />
                          <Skeleton class="h-4 w-5/6" />
                          <Skeleton class="h-4 w-1/2" />
                        </div>
                      </ScrollArea>
                    {/if}
                  </Card.Content>
                </Card.Root>
              {/if}

              {#if pageError}
                <Alert.Root variant="destructive" class="w-full">
                  <Alert.Title>Visualization error</Alert.Title>
                  <Alert.Description>{pageError}</Alert.Description>
                </Alert.Root>
              {/if}
            </div>
          </Resizable.Pane>
          <Resizable.Handle withHandle />
          <Resizable.Pane defaultSize={35} minSize={25} class="min-h-0">
            <ArtifactPanel {chat} bind:editMode />
          </Resizable.Pane>
        </Resizable.PaneGroup>
      </Resizable.Pane>
    </Resizable.PaneGroup>
  </main>
</div>
