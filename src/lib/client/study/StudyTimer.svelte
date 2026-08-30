<script lang="ts">
  import { onMount } from 'svelte';

  type Props = { deadlineAt: string; onExpire?: () => void };
  let { deadlineAt, onExpire }: Props = $props();
  let now = $state(Date.now());
  let expiredNotified = false;
  const remaining = $derived(Math.max(0, new Date(deadlineAt).getTime() - now));
  const label = $derived(
    `${String(Math.floor(remaining / 60_000)).padStart(2, '0')}:${String(Math.floor((remaining % 60_000) / 1_000)).padStart(2, '0')}`
  );

  onMount(() => {
    const timer = setInterval(() => (now = Date.now()), 250);
    return () => clearInterval(timer);
  });

  $effect(() => {
    if (remaining > 0 || expiredNotified) return;
    expiredNotified = true;
    onExpire?.();
  });
</script>

<span class="font-mono text-sm tabular-nums" role="timer" aria-live="polite">{label}</span>
