<script lang="ts">
  type Props = {
    loadingStatic: boolean;
    regenerating: boolean;
    hasTrace: boolean;
    canPrevious: boolean;
    canNext: boolean;
    currentStep: number;
    stepCount: number;
    latestSeed: number | null;
    seedText?: string;
    details?: boolean;
    debugOpen?: boolean;
    onReload: () => void | Promise<void>;
    onReset: () => void;
    onPrevious: () => void;
    onNext: () => void;
    onRegenerate: () => void | Promise<void>;
  };

  let {
    loadingStatic,
    regenerating,
    hasTrace,
    canPrevious,
    canNext,
    currentStep,
    stepCount,
    latestSeed,
    seedText = $bindable(''),
    details = $bindable(false),
    debugOpen = $bindable(false),
    onReload,
    onReset,
    onPrevious,
    onNext,
    onRegenerate
  }: Props = $props();

  const busy = $derived(loadingStatic || regenerating);

  function submitRegeneration(event: SubmitEvent) {
    event.preventDefault();
    void onRegenerate();
  }
</script>

<form class="toolbar" onsubmit={submitRegeneration}>
  <div class="button-group" aria-label="Trace playback">
    <button type="button" onclick={onReload} disabled={busy}>Reload</button>
    <button type="button" onclick={onReset} disabled={!hasTrace || busy}>Reset</button>
    <button type="button" onclick={onPrevious} disabled={!canPrevious || busy}>Previous</button>
    <button type="button" onclick={onNext} disabled={!canNext || busy}>Next</button>
  </div>

  {#if hasTrace}
    <span class="step-label">Step {currentStep + 1} / {stepCount}</span>
  {/if}

  <div class="compile-controls" aria-label="Compile controls">
    <label class="field">
      <span>Seed</span>
      <input
        bind:value={seedText}
        disabled={busy}
        inputmode="numeric"
        placeholder="random"
        type="text"
      />
    </label>

    <label class="toggle">
      <input bind:checked={details} disabled={busy} type="checkbox" />
      <span>Details</span>
    </label>

    <label class="toggle">
      <input bind:checked={debugOpen} type="checkbox" />
      <span>Debug</span>
    </label>

    <button type="submit" disabled={regenerating}>
      {regenerating ? 'Regenerating...' : 'Regenerate'}
    </button>
  </div>

  {#if latestSeed !== null}
    <span class="seed-label">Seed {latestSeed}</span>
  {/if}
</form>

<style>
  .toolbar {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 10px;
    margin-bottom: 10px;
    font-family: system-ui, sans-serif;
  }

  .button-group,
  .compile-controls {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
  }

  button {
    min-height: 30px;
    background-color: lightblue;
    border: 1px solid rgb(80, 80, 80);
    border-radius: 4px;
    cursor: pointer;
    padding: 0 12px;
  }

  button:disabled {
    background-color: gray;
    cursor: default;
  }

  .step-label,
  .seed-label {
    color: white;
    white-space: nowrap;
  }

  .field,
  .toggle {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    color: white;
  }

  .field input {
    width: 10ch;
    min-height: 28px;
    box-sizing: border-box;
    border: 1px solid rgb(80, 80, 80);
    border-radius: 4px;
    padding: 0 6px;
  }
</style>
