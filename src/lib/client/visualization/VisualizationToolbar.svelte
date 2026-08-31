<script lang="ts">
  import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
  import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';
  import RefreshCwIcon from '@lucide/svelte/icons/refresh-cw';
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';
  import ShuffleIcon from '@lucide/svelte/icons/shuffle';

  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import * as Field from '$lib/client/components/ui/field';
  import { Input } from '$lib/client/components/ui/input';
  import { Spinner } from '$lib/client/components/ui/spinner';

  /** Public properties for visualization playback and regeneration controls. */
  type Props = {
    loadingVisualization: boolean;
    regenerating: boolean;
    hasVisualization: boolean;
    canPrevious: boolean;
    canNext: boolean;
    currentStep: number;
    stepCount: number;
    seedText?: string;
    playbackDisabled?: boolean;
    renderDisabled?: boolean;
    onReset: () => void;
    onPrevious: () => void;
    onNext: () => void;
    onRegenerate: (seedText?: string) => void | Promise<void>;
  };

  let {
    loadingVisualization,
    regenerating,
    hasVisualization,
    canPrevious,
    canNext,
    currentStep,
    stepCount,
    seedText = $bindable(''),
    playbackDisabled = false,
    renderDisabled = false,
    onReset,
    onPrevious,
    onNext,
    onRegenerate
  }: Props = $props();

  const playbackBusy = $derived(loadingVisualization || playbackDisabled);
  const renderBusy = $derived(loadingVisualization || regenerating || renderDisabled);
  const minSeed = 1;
  const maxSeedExclusive = 2147483647;

  function submitRegeneration(event: SubmitEvent) {
    event.preventDefault();
    void onRegenerate();
  }

  function randomizeAndRegenerate() {
    const nextSeedText = randomSeedText();

    seedText = nextSeedText;
    void onRegenerate(nextSeedText);
  }

  function randomSeedText(): string {
    const [value] = crypto.getRandomValues(new Uint32Array(1));
    const seed = (value % (maxSeedExclusive - minSeed)) + minSeed;

    return String(seed);
  }
</script>

<form
  class="flex min-h-16 w-full flex-wrap items-center gap-3 border-b bg-background/95 px-4 py-3 text-foreground"
  onsubmit={submitRegeneration}
>
  <div class="flex flex-wrap items-center gap-3">
    <div class="flex flex-wrap items-center gap-2" aria-label="Visualization playback">
      <Button
        type="button"
        variant="outline"
        size="sm"
        onclick={onReset}
        disabled={!hasVisualization || playbackBusy}
      >
        <RotateCcwIcon data-icon="inline-start" />
        Reset
      </Button>
      <Button
        aria-label="Previous step"
        type="button"
        variant="outline"
        size="lg"
        onclick={onPrevious}
        disabled={!canPrevious || playbackBusy}
      >
        <ChevronLeftIcon data-icon="inline-start" />
        Previous
      </Button>
      <Button
        aria-label="Next step"
        type="button"
        variant="outline"
        size="lg"
        onclick={onNext}
        disabled={!canNext || playbackBusy}
      >
        Next
        <ChevronRightIcon data-icon="inline-end" />
      </Button>
    </div>

    {#if hasVisualization}
      <div class="flex flex-wrap items-center gap-2" aria-label="Visualization status">
        <Badge variant="secondary">Step {currentStep + 1} of {stepCount}</Badge>
      </div>
    {/if}
  </div>

  <div
    class="ml-auto flex flex-wrap items-center justify-end gap-3 max-sm:ml-0 max-sm:w-full max-sm:justify-start"
    aria-label="Compile controls"
  >
    <Field.Field
      orientation="horizontal"
      class="w-auto flex-none items-center gap-2 [&>[data-slot=field-label]]:flex-none"
    >
      <Field.Label for="next-seed" class="shrink-0 text-muted-foreground">Next seed</Field.Label>
      <Input
        id="next-seed"
        class="w-36"
        bind:value={seedText}
        disabled={renderBusy}
        inputmode="numeric"
        placeholder="random"
        type="text"
      />
      <Button
        type="button"
        variant="outline"
        size="sm"
        onclick={randomizeAndRegenerate}
        disabled={renderBusy}
      >
        <ShuffleIcon data-icon="inline-start" />
        Random
      </Button>
    </Field.Field>

    <Button type="submit" disabled={renderBusy}>
      {#if regenerating}
        <Spinner data-icon="inline-start" />
        Regenerating
      {:else}
        <RefreshCwIcon data-icon="inline-start" />
        Regenerate
      {/if}
    </Button>
  </div>
</form>
