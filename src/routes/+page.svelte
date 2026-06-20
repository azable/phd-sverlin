<script lang="ts">
  import { deserialize } from '$app/forms';
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
    CompiledTrace,
    VisualizationFailure,
    VisualizationResponse,
    VisualizationSuccess
  } from '$lib/visualization/types';

  const staticTraceSrc = '/compiled.json';
  const regenerateSrc = '?/regenerate';

  const player = new TracePlayer();

  let loadingStatic = $state(true);
  let regenerating = $state(false);
  let staticError = $state<string | null>(null);
  let regenerateError = $state<string | null>(null);
  let latestDebug = $state<CompileDebug | null>(null);
  let currentSeed = $state<number | null>(null);
  let seedText = $state('');
  let debugEnabled = $state(false);

  const pageError = $derived(staticError ?? regenerateError);

  onMount(() => {
    void loadStaticTrace();

    return () => {
      player.dispose();
    };
  });

  async function loadStaticTrace() {
    loadingStatic = true;
    staticError = null;

    try {
      const response = await fetch(staticTraceSrc);

      if (!response.ok) {
        throw new Error(
          `Failed to load ${staticTraceSrc}: ${response.status} ${response.statusText}`
        );
      }

      const trace = (await response.json()) as CompiledTrace;

      player.setTrace(trace);
      currentSeed = typeof trace.seed === 'number' ? trace.seed : null;
    } catch (err) {
      staticError = err instanceof Error ? err.message : String(err);
    } finally {
      loadingStatic = false;
    }
  }

  async function regenerateTrace() {
    let seed: number | null;

    try {
      seed = parseOptionalSeed(seedText);
    } catch (err) {
      regenerateError = err instanceof Error ? err.message : String(err);
      debugEnabled = true;
      return;
    }

    regenerating = true;
    regenerateError = null;

    try {
      const formData = new FormData();

      if (seed !== null) {
        formData.set('seed', String(seed));
      }

      formData.set('details', String(debugEnabled));

      const response = await fetch(regenerateSrc, {
        method: 'POST',
        body: formData
      });
      const payload = await readVisualizationResponse(response);

      if (payload.debug) {
        latestDebug = payload.debug;
      }

      if (typeof payload.seed === 'number') {
        currentSeed = payload.seed;
      }

      if (!response.ok || !payload.ok) {
        throw new Error(payload.ok ? response.statusText : payload.error);
      }

      player.setTrace(payload.trace);
    } catch (err) {
      regenerateError = err instanceof Error ? err.message : String(err);
      debugEnabled = true;
    } finally {
      regenerating = false;
    }
  }

  async function readVisualizationResponse(response: Response): Promise<VisualizationResponse> {
    const text = await response.text();
    const fallbackError = `Server returned non-action response: ${text.slice(0, 240)}`;
    let result: ReturnType<typeof deserialize>;

    try {
      result = deserialize(text);
    } catch {
      throw new Error(fallbackError);
    }

    if (result.type === 'success') {
      return (
        (result.data as VisualizationSuccess | undefined) ?? {
          ok: false,
          error: 'Regeneration returned an empty success response.'
        }
      );
    }

    if (result.type === 'failure') {
      return (
        (result.data as VisualizationFailure | undefined) ?? {
          ok: false,
          error: `Regeneration failed with status ${result.status}.`
        }
      );
    }

    if (result.type === 'redirect') {
      return {
        ok: false,
        error: `Regeneration redirected to ${result.location}.`
      };
    }

    return {
      ok: false,
      error:
        result.error instanceof Error
          ? result.error.message
          : `Regeneration failed with status ${result.status ?? response.status}.`
    };
  }

  function parseOptionalSeed(value: string): number | null {
    const trimmed = value.trim();

    if (!trimmed) return null;

    const seed = Number(trimmed);

    if (!Number.isInteger(seed) || !Number.isSafeInteger(seed)) {
      throw new Error('Seed must be an integer that JavaScript can represent safely.');
    }

    return seed;
  }
</script>

<div class="dark min-h-screen bg-background text-foreground">
  <TraceToolbar
    bind:debugEnabled
    bind:seedText
    canNext={player.canNext}
    canPrevious={player.canPrevious}
    currentStep={player.currentStep}
    hasTrace={player.hasTrace}
    {currentSeed}
    {loadingStatic}
    onNext={() => player.next()}
    onPrevious={() => player.previous()}
    onRegenerate={regenerateTrace}
    onReset={() => player.reset()}
    {regenerating}
    stepCount={player.stepCount}
  />

  <main class="mx-auto flex w-full max-w-screen-2xl flex-col items-center gap-4 p-4">
    {#if loadingStatic && !player.hasTrace}
      <Card.Root class="w-full max-w-5xl">
        <Card.Header>
          <Card.Title>Loading trace</Card.Title>
          <Card.Description>{staticTraceSrc}</Card.Description>
        </Card.Header>
        <Card.Content class="flex flex-col gap-3">
          <Skeleton class="h-8 w-48" />
          <Skeleton class="h-96 w-full" />
        </Card.Content>
      </Card.Root>
    {/if}

    {#if pageError}
      <Alert.Root variant="destructive" class="w-full max-w-5xl">
        <Alert.Title>Visualization error</Alert.Title>
        <Alert.Description>{pageError}</Alert.Description>
      </Alert.Root>
    {/if}

    {#if player.hasTrace}
      <Card.Root class="w-full max-w-screen-xl" aria-label="Visualization canvas">
        <Card.Header class="sr-only">
          <Card.Title>Visualization canvas</Card.Title>
        </Card.Header>
        <Card.Content class="p-3">
          <ScrollArea orientation="both" class="w-full rounded-lg border">
            <div class="w-max">
              <TraceCanvas
                elements={player.elements}
                height={player.canvasHeight}
                width={player.canvasWidth}
              />
            </div>
          </ScrollArea>
        </Card.Content>
      </Card.Root>

      <TraceDebugPanel
        debug={latestDebug}
        error={regenerateError}
        open={debugEnabled}
        {regenerating}
      />
    {/if}
  </main>
</div>
