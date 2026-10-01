<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { onMount, tick } from 'svelte';

  import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
  import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';
  import ShuffleIcon from '@lucide/svelte/icons/shuffle';

  import * as Alert from '$lib/client/components/ui/alert';
  import { Button } from '$lib/client/components/ui/button';
  import * as Empty from '$lib/client/components/ui/empty';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import type { ProjectTemplateSummary } from '$lib/shared/projects/creation';
  import { decodeVisualization, type Visualization } from '$lib/shared/visualization';

  import VisualizationViewport from './VisualizationViewport.svelte';
  import { VisualizationPlayer } from './visualization-player.svelte';
  import { examplePreviewPath, randomExampleSeed } from './example-preview-navigation';

  type Props = { exampleId: string; seed?: number; templates: ProjectTemplateSummary[] };
  let { exampleId, seed, templates }: Props = $props();

  type PreviewResponse = {
    exampleId: string;
    seed: number;
    source: string;
    visualization: Visualization;
    fonts: { id: string; mediaType: string; base64: string }[];
  };
  type Preview = {
    exampleId: string;
    seed: number;
    source: string;
    resourceUrls: Record<string, string>;
    version: number;
  };

  const player = new VisualizationPlayer();
  let preview = $state.raw<Preview>();
  let pending = $state(false);
  let failure = $state<string>();
  let revision = $state(0);
  let version = 0;
  let hotReloadTimer: ReturnType<typeof setTimeout> | undefined;
  // Blob URLs are external browser resources, not reactive component state.
  // eslint-disable-next-line svelte/prefer-svelte-reactivity
  const activeUrls = new Set<string>();

  function navigate(id: string, nextSeed: number, replaceState = false) {
    const path = examplePreviewPath(id, nextSeed);
    // eslint-disable-next-line svelte/no-navigation-without-resolve
    void goto(path, { replaceState, noScroll: true, keepFocus: true });
  }

  onMount(() => {
    if (seed === undefined) navigate(exampleId, randomExampleSeed(), true);
    const changed = (event: { id: string }) => {
      if (event.id !== exampleId) return;
      if (hotReloadTimer) clearTimeout(hotReloadTimer);
      // Coalesce an editor's rapid write/rename events without delaying the next compile noticeably.
      hotReloadTimer = setTimeout(() => (revision += 1), 180);
    };
    import.meta.hot?.on('sverlin:example-changed', changed);
    return () => {
      import.meta.hot?.off('sverlin:example-changed', changed);
      if (hotReloadTimer) clearTimeout(hotReloadTimer);
      for (const url of activeUrls) URL.revokeObjectURL(url);
    };
  });

  $effect(() => {
    const [id, viewSeed] = [exampleId, seed, revision] as const;
    if (viewSeed === undefined) return;
    const controller = new AbortController();
    pending = true;
    failure = undefined;
    void fetch('/api/examples/compile', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ exampleId: id, seed: viewSeed }),
      signal: controller.signal
    })
      .then(async (response) => {
        const result = (await response.json()) as PreviewResponse & { error?: string };
        if (!response.ok) throw new Error(result.error ?? 'Example compilation failed.');
        return result;
      })
      .then(async (result) => {
        if (controller.signal.aborted) return;
        const visualization = decodeVisualization(JSON.stringify(result.visualization));
        const resourceUrls: Record<string, string> = {};
        try {
          for (const font of result.fonts) {
            const bytes = Uint8Array.from(atob(font.base64), (character) =>
              character.charCodeAt(0)
            );
            const url = URL.createObjectURL(new Blob([bytes], { type: font.mediaType }));
            resourceUrls[font.id] = url;
            activeUrls.add(url);
          }
          if (controller.signal.aborted) return;
          const oldUrls = Object.values(preview?.resourceUrls ?? {});
          const previousStep = preview?.exampleId === id ? player.currentStep : 0;
          player.setVisualization(visualization, {
            initialStep: Math.min(previousStep, visualization.steps.length - 1)
          });
          preview = {
            exampleId: id,
            seed: result.seed,
            source: result.source,
            resourceUrls,
            version: ++version
          };
          pending = false;
          await tick();
          await document.fonts.ready;
          for (const url of oldUrls) {
            URL.revokeObjectURL(url);
            activeUrls.delete(url);
          }
        } catch (cause) {
          for (const url of Object.values(resourceUrls)) {
            URL.revokeObjectURL(url);
            activeUrls.delete(url);
          }
          throw cause;
        }
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) return;
        failure = cause instanceof Error ? cause.message : 'Example compilation failed.';
        pending = false;
      });
    return () => controller.abort();
  });
</script>

<div class="dark flex h-screen min-h-0 flex-col bg-background text-foreground">
  <header class="flex flex-wrap items-center gap-3 border-b bg-card px-4 py-3">
    <Button href={resolve('/examples')} size="sm" variant="outline">Examples</Button>
    <label for="example-picker" class="text-sm font-medium">Example</label>
    <select
      id="example-picker"
      class="h-9 max-w-full min-w-52 rounded-md border bg-background px-3 text-sm"
      value={exampleId}
      onchange={(event) => navigate(event.currentTarget.value, randomExampleSeed())}
    >
      {#each templates as template (template.id)}
        <option value={template.id}>{template.title}</option>
      {/each}
    </select>
    <span class="text-sm text-muted-foreground">Seed {seed ?? '…'}</span>
    <Button size="sm" variant="outline" onclick={() => navigate(exampleId, randomExampleSeed())}>
      <ShuffleIcon data-icon="inline-start" />New seed
    </Button>
    <Button size="sm" variant="outline" onclick={() => (revision += 1)} disabled={pending}>
      Retry
    </Button>
    {#if pending && preview}
      <span
        class="ml-auto inline-flex items-center gap-2 text-sm whitespace-nowrap text-muted-foreground"
        role="status"
      >
        <Spinner />Recompiling… showing the previous result
      </span>
    {/if}
  </header>

  {#if failure}
    <Alert.Root variant="destructive" class="m-3 shrink-0">
      <Alert.Title>Example compilation failed</Alert.Title>
      <Alert.Description>{failure}</Alert.Description>
    </Alert.Root>
  {/if}

  <main class="flex min-h-0 flex-1 flex-col">
    {#if preview && player.canvasRoot}
      <div class="flex min-h-0 flex-1 bg-muted/30 p-2">
        <div
          class="flex min-h-0 min-w-0 flex-1 overflow-hidden rounded-lg border bg-white shadow-sm"
        >
          {#key preview.version}
            <VisualizationViewport
              width={player.canvasWidth}
              height={player.canvasHeight}
              root={player.canvasRoot}
              elements={player.elements}
              connectors={player.connectors}
              resourceUrls={preview.resourceUrls}
              onFontLoadFailure={(_id, message) => (failure = message)}
            />
          {/key}
        </div>
      </div>
      <div class="flex min-h-14 shrink-0 items-center justify-center gap-3 border-y p-2">
        <Button variant="outline" onclick={() => player.previous()} disabled={!player.canPrevious}>
          <ChevronLeftIcon data-icon="inline-start" />Previous
        </Button>
        <span class="min-w-48 text-center text-sm">
          {player.currentStepLabel} · Step {player.currentStep + 1} of {player.stepCount}
        </span>
        <Button variant="outline" onclick={() => player.next()} disabled={!player.canNext}>
          Next<ChevronRightIcon data-icon="inline-end" />
        </Button>
      </div>
      <details class="max-h-[35vh] shrink-0 overflow-auto border-t bg-card">
        <summary class="cursor-pointer px-4 py-2 text-sm font-medium">View Sverlin source</summary>
        <pre class="overflow-auto border-t p-4 text-xs"><code>{preview.source}</code></pre>
      </details>
    {:else}
      <Empty.Root class="flex-1" aria-live="polite">
        <Empty.Header>
          <Empty.Title>
            {#if pending}
              <span class="inline-flex items-center gap-2 whitespace-nowrap">
                <Spinner />Compiling example…
              </span>
            {:else}
              Choose an example to preview.
            {/if}
          </Empty.Title>
        </Empty.Header>
      </Empty.Root>
    {/if}
  </main>
</div>
