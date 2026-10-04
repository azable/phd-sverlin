<!-- Short explanation for the current step. -->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { NoteTone } from './types';

  let { tone = 'neutral', children }: { tone?: NoteTone; children: Snippet } = $props();
</script>

<aside class="sv-note {tone}">{@render children()}</aside>

<style>
  .sv-note {
    padding: 0.75rem 1rem;
    border-left: 4px solid var(--sv-line);
    border-radius: var(--sv-radius);
    background: var(--sv-surface);
    line-height: 1.5;
  }
  .info {
    border-left-color: var(--sv-visited-line);
  }
  .success {
    border-left-color: var(--sv-found-line);
  }
  .warning {
    border-left-color: var(--sv-active-line);
  }
</style>
