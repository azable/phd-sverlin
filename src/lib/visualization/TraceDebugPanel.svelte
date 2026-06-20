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
    <div class="panel-heading">
      <h2>Run details</h2>
      <span>{regenerating ? 'Running' : error ? 'Failed' : debug ? 'Complete' : 'Idle'}</span>
    </div>

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
      <h3>stderr</h3>
      <pre>{debug.stderr}</pre>
    {/if}

    {#if debug?.stdout}
      <h3>stdout</h3>
      <pre>{debug.stdout}</pre>
    {/if}
  </section>
{/if}

<style>
  .debug-panel {
    width: min(100%, 1040px);
    padding: 14px;
    border: 1px solid rgb(30, 41, 59);
    border-radius: 8px;
    background: rgb(15, 23, 42);
    color: rgb(226, 232, 240);
    box-sizing: border-box;
    font-family: system-ui, sans-serif;
  }

  .panel-heading {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    align-items: center;
    margin-bottom: 12px;
  }

  .panel-heading h2 {
    margin: 0;
    font-size: 0.95rem;
    font-weight: 650;
  }

  .panel-heading span {
    color: rgb(148, 163, 184);
    font-size: 0.82rem;
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

  .debug-grid span {
    color: rgb(148, 163, 184);
  }

  code {
    overflow-wrap: anywhere;
  }

  h3 {
    margin: 12px 0 6px;
    color: rgb(203, 213, 225);
    font-size: 0.9rem;
  }

  pre {
    max-height: 240px;
    overflow: auto;
    margin: 0;
    padding: 8px;
    background: rgb(2, 6, 23);
    border: 1px solid rgb(30, 41, 59);
    border-radius: 4px;
    white-space: pre-wrap;
  }

  .error {
    color: rgb(254, 202, 202);
    margin: 8px 0;
  }
</style>
