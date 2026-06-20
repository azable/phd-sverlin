<script lang="ts">
  import { deserialize } from '$app/forms';
  import { onMount } from 'svelte';

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
  let latestSeed = $state<number | null>(null);
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
        latestSeed = payload.seed;
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

<div class="page">
  <TraceToolbar
    bind:debugEnabled
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
    onReset={() => player.reset()}
    {regenerating}
    stepCount={player.stepCount}
  />

  <main class="workspace">
    {#if loadingStatic && !player.hasTrace}
      <p class="status">Loading {staticTraceSrc}...</p>
    {/if}

    {#if pageError}
      <p class="error">{pageError}</p>
    {/if}

    {#if player.hasTrace}
      <section class="canvas-panel" aria-label="Visualization canvas">
        <div class="canvas-scroll">
          <TraceCanvas
            elements={player.elements}
            height={player.canvasHeight}
            width={player.canvasWidth}
          />
        </div>
      </section>

      <TraceDebugPanel
        debug={latestDebug}
        error={regenerateError}
        open={debugEnabled}
        {regenerating}
      />
    {/if}
  </main>
</div>

<style>
  .page {
    min-width: 100vw;
    min-height: 100vh;
    overflow: auto;
    background: rgb(2, 6, 23);
    box-sizing: border-box;
  }

  .workspace {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
    padding: 20px;
    box-sizing: border-box;
  }

  .canvas-panel {
    max-width: 100%;
    padding: 12px;
    border: 1px solid rgb(30, 41, 59);
    border-radius: 8px;
    background: rgb(15, 23, 42);
    box-shadow: 0 18px 50px rgb(0 0 0 / 0.28);
    box-sizing: border-box;
  }

  .canvas-scroll {
    max-width: calc(100vw - 64px);
    overflow: auto;
  }

  .status {
    color: rgb(226, 232, 240);
    font-family: system-ui, sans-serif;
  }

  .error {
    width: min(100%, 960px);
    color: rgb(254, 202, 202);
    font-family: system-ui, sans-serif;
  }
</style>
