<script lang="ts">
  import { onMount } from 'svelte';

  import * as Alert from '$lib/components/ui/alert';
  import * as Card from '$lib/components/ui/card';
  import { ScrollArea } from '$lib/components/ui/scroll-area';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import TraceCanvas from '$lib/visualization/TraceCanvas.svelte';
  import TraceDebugPanel from '$lib/visualization/TraceDebugPanel.svelte';
  import TraceToolbar from '$lib/visualization/TraceToolbar.svelte';
  import { TracePlayer } from '$lib/visualization/trace-player.svelte';
  import type {
    CompileDebug,
    CompileLockHolder,
    CompileStatus,
    CompileStreamFailure,
    CompileStreamOutput,
    CompileStreamStatus,
    CompileStreamSuccess
  } from '$lib/visualization/types';

  type CompilePhase = 'initial' | 'regenerate';

  const compileSrc = '/api/visualization';
  const compileStatusStreamSrc = '/api/visualization/status/stream';

  const player = new TracePlayer();

  let loadingTrace = $state(true);
  let regenerating = $state(false);
  let compileError = $state<string | null>(null);
  let latestDebug = $state<CompileDebug | null>(null);
  let seedText = $state('');
  let debugEnabled = $state(true);
  let activeCompileSource: EventSource | null = null;
  let activeCompileStatusSource: EventSource | null = null;
  let compileRetryTimer: ReturnType<typeof setTimeout> | null = null;
  let externalCompileLock = $state<CompileLockHolder | null>(null);
  let compileRunId = 0;
  const compileBusyRetryMs = 1_000;

  const compiling = $derived(loadingTrace || regenerating);
  const externalCompileActive = $derived(externalCompileLock !== null && !compiling);
  const toolbarExternalCompiling = $derived(externalCompileLock !== null && !loadingTrace);
  const displayedDebug = $derived(
    externalCompileActive && externalCompileLock !== null
      ? lockStatusDebug(externalCompileLock)
      : latestDebug
  );
  const pageError = $derived(compileError);
  const initialCompileOutput = $derived(
    latestDebug?.stdout || latestDebug?.stderr
      ? [latestDebug.stdout, latestDebug.stderr].filter(Boolean).join('\n')
      : ''
  );

  onMount(() => {
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
      debugEnabled = true;
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
    latestDebug = null;

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
        latestDebug = payload.debug ?? busyDebug(error, payload);

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

      if (payload?.debug) {
        latestDebug = payload.debug;
      }

      if (typeof payload?.seed === 'number') {
        seedText = String(payload.seed);
      }

      compileError = error;
      debugEnabled = true;
      finish();
    }

    source.addEventListener('status', (event) => {
      if (!isCurrentRun()) return;

      try {
        const payload = readStreamEvent<CompileStreamStatus>(event);
        seedText = String(payload.seed);

        if (payload.debug) {
          latestDebug = payload.debug;
        }
      } catch (err) {
        fail(err instanceof Error ? err.message : String(err));
      }
    });

    source.addEventListener('stdout', (event) => {
      if (!isCurrentRun()) return;

      try {
        const payload = readStreamEvent<CompileStreamOutput>(event);
        appendDebugOutput('stdout', payload.chunk);
      } catch (err) {
        fail(err instanceof Error ? err.message : String(err));
      }
    });

    source.addEventListener('stderr', (event) => {
      if (!isCurrentRun()) return;

      try {
        const payload = readStreamEvent<CompileStreamOutput>(event);
        appendDebugOutput('stderr', payload.chunk);
      } catch (err) {
        fail(err instanceof Error ? err.message : String(err));
      }
    });

    source.addEventListener('trace', (event) => {
      if (!isCurrentRun()) return;

      try {
        const payload = readStreamEvent<CompileStreamSuccess>(event);
        latestDebug = payload.debug;
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

    url.searchParams.set('details', String(debugEnabled));

    return url;
  }

  function readStreamEvent<T>(event: Event): T {
    if (!(event instanceof MessageEvent) || typeof event.data !== 'string') {
      throw new Error('Compile stream sent an unreadable event.');
    }

    return JSON.parse(event.data) as T;
  }

  function appendDebugOutput(field: 'stdout' | 'stderr', chunk: string) {
    const debug = latestDebug ?? emptyDebug();

    latestDebug = {
      ...debug,
      [field]: debug[field] + chunk
    };
  }

  function emptyDebug(): CompileDebug {
    return {
      command: '',
      args: [],
      cwd: '',
      durationMs: 0,
      exitCode: null,
      stdout: '',
      stderr: ''
    };
  }

  function busyDebug(error: string, payload?: CompileStreamFailure): CompileDebug {
    const lock = payload?.lock;
    const owner = lock ? `${lock.owner} pid ${lock.pid}` : 'another compile process';

    return {
      command: lock?.command ?? '',
      args: lock?.args ?? [],
      cwd: lock?.cwd ?? '',
      outputPath: lock?.outputPath,
      durationMs: 0,
      exitCode: null,
      stdout: '',
      stderr: `${error}\nWaiting for ${owner} to finish before retrying.`
    };
  }

  function lockStatusDebug(lock: CompileLockHolder): CompileDebug {
    return {
      command: lock.command,
      args: lock.args,
      cwd: lock.cwd,
      outputPath: lock.outputPath,
      durationMs: Date.now() - Date.parse(lock.startedAt),
      exitCode: null,
      stdout: '',
      stderr: [
        `External ${lock.owner} compile is running under pid ${lock.pid}.`,
        typeof lock.seed === 'number' ? `Seed: ${lock.seed}.` : null,
        `Started at ${lock.startedAt}.`
      ]
        .filter(Boolean)
        .join('\n')
    };
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

<div class="dark flex h-screen flex-col overflow-hidden bg-background text-foreground">
  <TraceToolbar
    bind:debugEnabled
    bind:seedText
    canNext={player.canNext}
    canPrevious={player.canPrevious}
    currentStep={player.currentStep}
    externalCompiling={toolbarExternalCompiling}
    hasTrace={player.hasTrace}
    {loadingTrace}
    onNext={() => player.next()}
    onPrevious={() => player.previous()}
    onRegenerate={regenerateTrace}
    onReset={() => player.reset()}
    {regenerating}
    stepCount={player.stepCount}
  />

  <main
    class="mx-auto flex min-h-0 w-full max-w-screen-2xl flex-1 flex-col items-center gap-4 overflow-hidden p-4"
  >
    {#if loadingTrace || player.hasTrace}
      <Card.Root class="flex min-h-0 w-full max-w-5xl flex-none">
        <Card.Header>
          <Card.Title>{player.hasTrace ? 'Trace visualization' : 'Compiling trace'}</Card.Title>
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
              <div class="flex h-max min-h-full w-max min-w-full items-start justify-center py-3">
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
              {#if initialCompileOutput}
                <pre
                  class="p-3 font-mono text-xs break-words whitespace-pre-wrap">{initialCompileOutput}</pre>
              {:else}
                <div class="flex h-full flex-col gap-3 p-3">
                  <Skeleton class="h-4 w-2/3" />
                  <Skeleton class="h-4 w-5/6" />
                  <Skeleton class="h-4 w-1/2" />
                </div>
              {/if}
            </ScrollArea>
          {/if}
        </Card.Content>
      </Card.Root>
    {/if}

    {#if pageError}
      <Alert.Root variant="destructive" class="w-full max-w-5xl">
        <Alert.Title>Visualization error</Alert.Title>
        <Alert.Description>{pageError}</Alert.Description>
      </Alert.Root>
    {/if}

    <TraceDebugPanel
      debug={displayedDebug}
      error={compileError}
      open={(debugEnabled || compiling || externalCompileActive || compileError !== null) &&
        (!loadingTrace || player.hasTrace)}
      regenerating={compiling || externalCompileActive}
    />
  </main>
</div>
