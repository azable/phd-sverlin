<script lang="ts">
  import BugIcon from '@lucide/svelte/icons/bug';
  import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
  import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';
  import RefreshCwIcon from '@lucide/svelte/icons/refresh-cw';
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';

  import { Button } from '$lib/components/ui/button';
  import { Input } from '$lib/components/ui/input';
  import { Label } from '$lib/components/ui/label';
  import { Switch } from '$lib/components/ui/switch';

  type Props = {
    loadingStatic: boolean;
    regenerating: boolean;
    hasTrace: boolean;
    canPrevious: boolean;
    canNext: boolean;
    currentStep: number;
    stepCount: number;
    currentSeed: number | null;
    seedText?: string;
    debugEnabled?: boolean;
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
    currentSeed,
    seedText = $bindable(''),
    debugEnabled = $bindable(false),
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
  <div class="toolbar-primary">
    <div class="playback-controls" aria-label="Trace playback">
      <Button variant="outline" size="sm" onclick={onReset} disabled={!hasTrace || busy}>
        <RotateCcwIcon size={15} />
        Reset
      </Button>
      <Button variant="outline" size="icon" onclick={onPrevious} disabled={!canPrevious || busy}>
        <ChevronLeftIcon size={17} />
        <span class="sr-only">Previous</span>
      </Button>
      <Button variant="outline" size="icon" onclick={onNext} disabled={!canNext || busy}>
        <ChevronRightIcon size={17} />
        <span class="sr-only">Next</span>
      </Button>
    </div>

    {#if hasTrace}
      <div class="trace-meta" aria-label="Trace status">
        <span class="meta-pill">
          <span>Step</span>
          <strong>{currentStep + 1}</strong>
          <span>of</span>
          <strong>{stepCount}</strong>
        </span>

        {#if currentSeed !== null}
          <span class="meta-pill">
            <span>Seed</span>
            <strong>{currentSeed}</strong>
          </span>
        {/if}
      </div>
    {/if}
  </div>

  <div class="compile-controls" aria-label="Compile controls">
    <Label class="seed-control">
      <span class="field-label">Next seed</span>
      <Input
        bind:value={seedText}
        disabled={busy}
        inputmode="numeric"
        placeholder="random"
        type="text"
      />
    </Label>

    <Label class="debug-control">
      <Switch bind:checked={debugEnabled} />
      <BugIcon size={15} />
      <span>Debug</span>
    </Label>

    <Button type="submit" disabled={busy}>
      <RefreshCwIcon class={regenerating ? 'animate-spin' : undefined} size={15} />
      {regenerating ? 'Regenerating...' : 'Regenerate'}
    </Button>
  </div>
</form>

<style>
  .toolbar {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 0.75rem;
    width: 100%;
    min-height: 3.75rem;
    padding: 0.625rem 1rem;
    border-bottom: 1px solid rgb(30, 41, 59);
    background: rgb(10, 16, 28);
    box-sizing: border-box;
    font-family: system-ui, sans-serif;
  }

  .toolbar-primary {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 0.625rem;
  }

  .playback-controls,
  .compile-controls,
  .trace-meta {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 0.5rem;
  }

  .compile-controls {
    margin-left: auto;
    justify-content: flex-end;
  }

  .meta-pill {
    display: inline-flex;
    min-height: 2rem;
    align-items: center;
    gap: 0.35rem;
    padding: 0.25rem 0.625rem;
    border: 1px solid rgb(51, 65, 85);
    border-radius: 0.375rem;
    background: rgb(15 23 42 / 0.72);
    color: rgb(203, 213, 225);
    font-size: 0.875rem;
    line-height: 1;
    white-space: nowrap;
  }

  .meta-pill strong {
    color: rgb(248, 250, 252);
    font-weight: 650;
    font-variant-numeric: tabular-nums;
  }

  .field-label {
    color: rgb(148, 163, 184);
    font-size: 0.8125rem;
  }

  :global(.seed-control input) {
    width: clamp(8rem, 14vw, 11rem);
  }

  :global(.debug-control) {
    color: rgb(226, 232, 240);
  }

  @media (max-width: 760px) {
    .toolbar {
      align-items: flex-start;
    }

    .toolbar-primary,
    .compile-controls {
      flex: 1 1 100%;
    }
  }

  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }
</style>
