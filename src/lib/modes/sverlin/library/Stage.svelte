<!-- Page frame and theme tokens shared by every library component. -->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { title, subtitle, children }: { title: string; subtitle?: string; children: Snippet } =
    $props();
</script>

<main class="sv-stage">
  <header>
    <h1>{title}</h1>
    {#if subtitle}<p>{subtitle}</p>{/if}
  </header>
  {@render children()}
</main>

<style>
  :global(:root) {
    --sv-ink: #172033;
    --sv-muted: #5d6880;
    --sv-line: #d7deea;
    --sv-surface: #ffffff;
    --sv-canvas: #f6f8fb;
    --sv-active: #fef3c7;
    --sv-active-line: #d4a72c;
    --sv-visited: #e8f0fe;
    --sv-visited-line: #7aa5ea;
    --sv-found: #e3f7ec;
    --sv-found-line: #3caf78;
    --sv-radius: 10px;
    font-family: system-ui, sans-serif;
  }
  :global(body) {
    margin: 0;
    background: var(--sv-canvas);
    color: var(--sv-ink);
  }
  .sv-stage {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
    max-width: 960px;
    margin: 0 auto;
    padding: 2rem;
  }
  h1 {
    margin: 0;
    font-size: 1.75rem;
  }
  p {
    margin: 0.5rem 0 0;
    color: var(--sv-muted);
  }
</style>
