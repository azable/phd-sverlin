<script lang="ts">
  import { Button } from '$lib/client/components/ui/button';

  type Props = {
    /** How many steps the component being stepped through has enumerated. */
    stepCount: number;
    /** Selected step; -1 before the first step. */
    index?: number;
  };

  let { stepCount, index = $bindable(-1) }: Props = $props();

  /** Pace chosen so each step is readable without making a full run tedious. */
  const stepDelayMs = 500;

  let playing = $state(false);

  const started = $derived(index >= 0);
  const finished = $derived(index >= stepCount - 1);

  function step() {
    if (!finished) index += 1;
  }

  function reset() {
    playing = false;
    index = -1;
  }

  /** Start, pause, or replay the automatic run. */
  function togglePlay() {
    if (finished) reset();
    playing = !playing;
  }

  $effect(() => {
    if (!playing) return;
    const timer = setInterval(() => {
      if (finished) {
        playing = false;
        return;
      }
      index += 1;
    }, stepDelayMs);
    return () => clearInterval(timer);
  });
</script>

<div class="flex flex-wrap items-center gap-2">
  <Button onclick={togglePlay}>
    {playing ? 'Pause' : finished ? 'Replay' : 'Play'}
  </Button>
  <Button variant="outline" onclick={step} disabled={playing || finished}>Step</Button>
  <Button variant="outline" onclick={reset} disabled={!started && !playing}>Reset</Button>
  <span class="text-sm text-muted-foreground tabular-nums">
    step {Math.max(index + 1, 0)} / {stepCount}
  </span>
</div>
