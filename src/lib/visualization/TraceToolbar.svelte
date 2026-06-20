<script lang="ts">
  import BugIcon from '@lucide/svelte/icons/bug';
  import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
  import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';
  import RefreshCwIcon from '@lucide/svelte/icons/refresh-cw';
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';

  import { Button } from '$lib/components/ui/button';
  import { Input } from '$lib/components/ui/input';
  import { Label } from '$lib/components/ui/label';
  import { Separator } from '$lib/components/ui/separator';
  import { Switch } from '$lib/components/ui/switch';

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
  <div class="toolbar-section" aria-label="Trace playback">
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
    <span class="step-label">Step {currentStep + 1} / {stepCount}</span>
  {/if}

  <Separator orientation="vertical" class="hidden md:block" />

  <div class="toolbar-section grow" aria-label="Compile controls">
    <Label>
      <span class="field-label">Seed</span>
      <Input
        class="w-[10ch]"
        bind:value={seedText}
        disabled={busy}
        inputmode="numeric"
        placeholder="random"
        type="text"
      />
    </Label>

    <Label class="text-slate-200">
      <Switch bind:checked={details} disabled={busy} />
      <span>Details</span>
    </Label>

    <Label class="text-slate-200">
      <Switch bind:checked={debugOpen} />
      <BugIcon size={15} />
      <span>Debug</span>
    </Label>

    <Button type="submit" disabled={regenerating}>
      <RefreshCwIcon class={regenerating ? 'animate-spin' : undefined} size={15} />
      {regenerating ? 'Regenerating...' : 'Regenerate'}
    </Button>
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
    width: 100%;
    min-height: 54px;
    padding: 9px 16px;
    border-bottom: 1px solid rgb(30, 41, 59);
    background: rgb(10, 16, 28);
    box-sizing: border-box;
    font-family: system-ui, sans-serif;
  }

  .toolbar-section {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
  }

  .grow {
    flex: 1 1 auto;
  }

  .step-label,
  .seed-label {
    color: rgb(203, 213, 225);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.82rem;
    white-space: nowrap;
  }

  .field-label {
    color: rgb(148, 163, 184);
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
