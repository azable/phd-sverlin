<script lang="ts">
  import * as Alert from '$lib/components/ui/alert';
  import { Badge, type BadgeVariant } from '$lib/components/ui/badge';
  import * as Card from '$lib/components/ui/card';
  import { ScrollArea } from '$lib/components/ui/scroll-area';

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

  const status = $derived(
    regenerating ? 'Running' : error ? 'Failed' : debug ? 'Complete' : 'Idle'
  );
  const statusVariant = $derived<BadgeVariant>(
    error ? 'destructive' : regenerating ? 'secondary' : debug ? 'default' : 'outline'
  );
</script>

{#if open}
  <Card.Root class="w-full max-w-5xl" aria-label="Compile debug output">
    <Card.Header>
      <Card.Title>Debug output</Card.Title>
      <Card.Description>Compile backend command, timing, and raw process streams.</Card.Description>
      <Card.Action>
        <Badge variant={statusVariant}>{status}</Badge>
      </Card.Action>
    </Card.Header>

    <Card.Content class="flex flex-col gap-4">
      <dl class="grid gap-2 text-sm sm:grid-cols-[8rem_minmax(0,1fr)]">
        <dt class="text-muted-foreground">Status</dt>
        <dd>
          <Badge variant={statusVariant}>{status}</Badge>
        </dd>

        {#if debug}
          <dt class="text-muted-foreground">Command</dt>
          <dd class="min-w-0">
            <code class="font-mono text-sm break-words"
              >{[debug.command, ...debug.args].join(' ')}</code
            >
          </dd>

          <dt class="text-muted-foreground">Working dir</dt>
          <dd class="min-w-0">
            <code class="font-mono text-sm break-words">{debug.cwd}</code>
          </dd>

          <dt class="text-muted-foreground">Duration</dt>
          <dd>
            <code class="font-mono text-sm">{debug.durationMs}ms</code>
          </dd>

          <dt class="text-muted-foreground">Exit code</dt>
          <dd>
            <code class="font-mono text-sm">{debug.exitCode ?? 'not started'}</code>
          </dd>
        {/if}
      </dl>

      {#if error}
        <Alert.Root variant="destructive">
          <Alert.Title>Regeneration failed</Alert.Title>
          <Alert.Description>{error}</Alert.Description>
        </Alert.Root>
      {/if}

      {#if !debug && !error && !regenerating}
        <p class="text-sm text-muted-foreground">Regenerate to capture compile diagnostics.</p>
      {/if}

      {#if debug?.stderr}
        <section class="flex flex-col gap-2">
          <h3 class="text-sm font-medium">stderr</h3>
          <ScrollArea class="h-48 rounded-lg border bg-muted/40">
            <pre class="p-3 font-mono text-xs whitespace-pre-wrap">{debug.stderr}</pre>
          </ScrollArea>
        </section>
      {/if}

      {#if debug?.stdout}
        <section class="flex flex-col gap-2">
          <h3 class="text-sm font-medium">stdout</h3>
          <ScrollArea class="h-48 rounded-lg border bg-muted/40">
            <pre class="p-3 font-mono text-xs whitespace-pre-wrap">{debug.stdout}</pre>
          </ScrollArea>
        </section>
      {/if}
    </Card.Content>
  </Card.Root>
{/if}
