<script lang="ts">
  import type { CompileDebug } from './types';

  let {
    open,
    debug,
    error,
    regenerating
  }: {
    open: boolean;
    debug: CompileDebug | null;
    error: string | null;
    regenerating: boolean;
  } = $props();
</script>

{#if open}
  <section class="debug-panel" aria-label="Compile debug output">
    <div class="debug-grid">
      <span>Status</span>
      <strong>{regenerating ? 'Running' : error ? 'Failed' : debug ? 'Complete' : 'Idle'}</strong>

      {#if debug}
        <span>Command</span>
        <code>{[debug.command, ...debug.args].join(' ')}</code>

        <span>Working dir</span>
        <code>{debug.cwd}</code>

        <span>Duration</span>
        <code>{debug.durationMs}ms</code>

        <span>Exit code</span>
        <code>{debug.exitCode ?? 'not started'}</code>
      {/if}
    </div>

    {#if error}
      <p class="error">{error}</p>
    {/if}

    {#if debug?.stderr}
      <h2>stderr</h2>
      <pre>{debug.stderr}</pre>
    {/if}

    {#if debug?.stdout}
      <h2>stdout</h2>
      <pre>{debug.stdout}</pre>
    {/if}
  </section>
{/if}

<style>
  .debug-panel {
    max-width: min(100%, 1200px);
    margin-bottom: 10px;
    color: rgb(235, 235, 235);
    font-family: system-ui, sans-serif;
  }

  .debug-grid {
    display: grid;
    grid-template-columns: max-content minmax(0, 1fr);
    gap: 6px 12px;
    align-items: baseline;
    margin-bottom: 8px;
  }

  code,
  pre {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }

  code {
    overflow-wrap: anywhere;
  }

  h2 {
    margin: 8px 0 4px;
    font-size: 0.9rem;
  }

  pre {
    max-height: 240px;
    overflow: auto;
    margin: 0;
    padding: 8px;
    background: rgb(12, 12, 12);
    border: 1px solid rgb(70, 70, 70);
    border-radius: 4px;
    white-space: pre-wrap;
  }

  .error {
    color: rgb(255, 150, 150);
    margin: 8px 0;
  }
</style>
