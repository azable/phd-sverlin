<script lang="ts">
  import * as Alert from '$lib/components/ui/alert';
  import { Badge, type BadgeVariant } from '$lib/components/ui/badge';
  import * as Card from '$lib/components/ui/card';
  import { ScrollArea } from '$lib/components/ui/scroll-area';
  import * as Tabs from '$lib/components/ui/tabs';

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
  const diagnosticsOutput = $derived(
    debug?.stderr ? debug.stderr : 'No diagnostics were written to stderr.'
  );
  const compiledOutput = $derived(
    debug?.stdout ? debug.stdout : 'No compiled JSON was written to stdout.'
  );
</script>

{#if open}
  <Card.Root
    size="sm"
    class="flex max-h-[40vh] min-h-0 w-full max-w-5xl flex-none"
    aria-label="Compile debug output"
  >
    <Card.Header class="flex-none">
      <Card.Title>Debug output</Card.Title>
      <Card.Description>Compile backend command, timing, diagnostics, and JSON.</Card.Description>
      <Card.Action>
        <Badge variant={statusVariant}>{status}</Badge>
      </Card.Action>
    </Card.Header>

    <Card.Content class="flex min-h-0 flex-1 flex-col gap-3">
      <dl class="grid flex-none gap-x-3 gap-y-1 text-xs sm:grid-cols-[7rem_minmax(0,1fr)]">
        {#if debug}
          <dt class="text-muted-foreground">Command</dt>
          <dd class="min-w-0">
            <code class="font-mono break-words">{[debug.command, ...debug.args].join(' ')}</code>
          </dd>

          <dt class="text-muted-foreground">Working dir</dt>
          <dd class="min-w-0">
            <code class="font-mono break-words">{debug.cwd}</code>
          </dd>

          <dt class="text-muted-foreground">Duration</dt>
          <dd>
            <code class="font-mono">{debug.durationMs}ms</code>
          </dd>

          <dt class="text-muted-foreground">Exit code</dt>
          <dd>
            <code class="font-mono">{debug.exitCode ?? 'not started'}</code>
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

      <Tabs.Root value="diagnostics" class="min-h-0 flex-1">
        <Tabs.List>
          <Tabs.Trigger value="diagnostics">Diagnostics</Tabs.Trigger>
          <Tabs.Trigger value="compiled">compiled.json</Tabs.Trigger>
        </Tabs.List>

        <Tabs.Content value="diagnostics" class="min-h-0">
          <ScrollArea class="h-full rounded-lg border bg-muted/40">
            <pre
              class="p-3 font-mono text-xs break-words whitespace-pre-wrap">{diagnosticsOutput}</pre>
          </ScrollArea>
        </Tabs.Content>

        <Tabs.Content value="compiled" class="min-h-0">
          <ScrollArea class="h-full rounded-lg border bg-muted/40">
            <pre
              class="p-3 font-mono text-xs break-words whitespace-pre-wrap">{compiledOutput}</pre>
          </ScrollArea>
        </Tabs.Content>
      </Tabs.Root>
    </Card.Content>
  </Card.Root>
{/if}
