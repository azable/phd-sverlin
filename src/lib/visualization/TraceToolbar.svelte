<script lang="ts">
  import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
  import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';
  import RefreshCwIcon from '@lucide/svelte/icons/refresh-cw';
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';

  import { Badge } from '$lib/components/ui/badge';
  import { Button } from '$lib/components/ui/button';
  import * as Field from '$lib/components/ui/field';
  import { Input } from '$lib/components/ui/input';
  import { Spinner } from '$lib/components/ui/spinner';
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

<form
  class="flex min-h-16 w-full flex-wrap items-center gap-3 border-b bg-background/95 px-4 py-3 text-foreground"
  onsubmit={submitRegeneration}
>
  <div class="flex flex-wrap items-center gap-3">
    <div class="flex flex-wrap items-center gap-2" aria-label="Trace playback">
      <Button variant="outline" size="sm" onclick={onReset} disabled={!hasTrace || busy}>
        <RotateCcwIcon data-icon="inline-start" />
        Reset
      </Button>
      <Button
        aria-label="Previous step"
        variant="outline"
        size="icon-sm"
        onclick={onPrevious}
        disabled={!canPrevious || busy}
      >
        <ChevronLeftIcon />
      </Button>
      <Button
        aria-label="Next step"
        variant="outline"
        size="icon-sm"
        onclick={onNext}
        disabled={!canNext || busy}
      >
        <ChevronRightIcon />
      </Button>
    </div>

    {#if hasTrace}
      <div class="flex flex-wrap items-center gap-2" aria-label="Trace status">
        <Badge variant="secondary">Step {currentStep + 1} of {stepCount}</Badge>
        {#if currentSeed !== null}
          <Badge variant="outline">Seed {currentSeed}</Badge>
        {/if}
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
        disabled={busy}
        inputmode="numeric"
        placeholder="random"
        type="text"
      />
    </Field.Field>

    <Field.Field
      orientation="horizontal"
      class="w-auto flex-none items-center gap-2 [&>[data-slot=field-label]]:flex-none"
    >
      <Switch id="debug-enabled" bind:checked={debugEnabled} />
      <Field.Label for="debug-enabled" class="shrink-0 font-normal">Debug</Field.Label>
    </Field.Field>

    <Button type="submit" disabled={busy}>
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
