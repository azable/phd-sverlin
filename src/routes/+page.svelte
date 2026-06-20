<script lang="ts">
  import { onMount } from 'svelte';

  import TraceCanvas from '$lib/visualization/TraceCanvas.svelte';
  import TraceDebugPanel from '$lib/visualization/TraceDebugPanel.svelte';
  import TraceToolbar from '$lib/visualization/TraceToolbar.svelte';
  import { TracePlayer } from '$lib/visualization/trace-player.svelte';
  import type {
    CompileDebug,
    CompiledTrace,
    VisualizationResponse
  } from '$lib/visualization/types';

  const staticTraceSrc = '/compiled.json';
  const regenerateSrc = '/api/visualization';

  const player = new TracePlayer();

  let loadingStatic = $state(true);
  let regenerating = $state(false);
  let staticError = $state<string | null>(null);
  let regenerateError = $state<string | null>(null);
  let latestDebug = $state<CompileDebug | null>(null);
  let latestSeed = $state<number | null>(null);
  let seedText = $state('');
  let details = $state(false);
  let debugOpen = $state(false);

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

      player.setTrace((await response.json()) as CompiledTrace);
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
      debugOpen = true;
      return;
    }

    regenerating = true;
    regenerateError = null;

    try {
      const response = await fetch(regenerateSrc, {
        method: 'POST',
        headers: {
          'content-type': 'application/json'
        },
        body: JSON.stringify({
          seed,
          details
        })
      });
      const payload = await readVisualizationResponse(response);

      if (payload.debug) {
        latestDebug = payload.debug;
      }

      if (typeof payload.seed === 'number') {
        latestSeed = payload.seed;
      }

      if (!response.ok || !payload.ok) {
        throw new Error(payload.ok ? response.statusText : payload.error);
      }

      player.setTrace(payload.trace);
    } catch (err) {
      regenerateError = err instanceof Error ? err.message : String(err);
      debugOpen = true;
    } finally {
      regenerating = false;
    }
  }

  async function readVisualizationResponse(response: Response): Promise<VisualizationResponse> {
    const text = await response.text();

    try {
      return JSON.parse(text) as VisualizationResponse;
    } catch {
      throw new Error(`Server returned non-JSON response: ${text.slice(0, 240)}`);
    }
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

<div class="page">
  <TraceToolbar
    bind:debugOpen
    bind:details
    bind:seedText
    canNext={player.canNext}
    canPrevious={player.canPrevious}
    currentStep={player.currentStep}
    hasTrace={player.hasTrace}
    {latestSeed}
    {loadingStatic}
    onNext={() => player.next()}
    onPrevious={() => player.previous()}
    onRegenerate={regenerateTrace}
    onReload={loadStaticTrace}
    onReset={() => player.reset()}
    {regenerating}
    stepCount={player.stepCount}
  />

  <TraceDebugPanel debug={latestDebug} error={regenerateError} open={debugOpen} {regenerating} />

  {#if loadingStatic && !player.hasTrace}
    <p class="status">Loading {staticTraceSrc}...</p>
  {/if}

  {#if pageError}
    <p class="error">{pageError}</p>
  {/if}

  {#if player.hasTrace}
    <TraceCanvas
      elements={player.elements}
      height={player.canvasHeight}
      width={player.canvasWidth}
    />
  {/if}
</div>

<style>
  .page {
    width: 100vw;
    height: 100vh;
    overflow: auto;
    background-color: rgb(30, 30, 30);
    padding: 12px;
    box-sizing: border-box;
  }

  .status {
    color: white;
    font-family: system-ui, sans-serif;
  }

  .error {
    color: rgb(255, 120, 120);
    font-family: system-ui, sans-serif;
  }
</style>
