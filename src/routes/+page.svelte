<script lang="ts">
  import { onMount } from 'svelte';

  type CssValue = string | number | boolean;

  type RenderStyle = Record<string, CssValue>;

  type RenderElement = {
    blockId: number;
    kind: string;
    content: string;
    style: RenderStyle;
    className?: string;
  };

  type RenderId = string;

  type RenderPatch =
    | {
        kind: 'create';
        id: RenderId;
        element: RenderElement;
      }
    | {
        kind: 'update';
        id: RenderId;
        from: RenderElement;
        to: RenderElement;
      }
    | {
        kind: 'destroy';
        id: RenderId;
        element: RenderElement;
      };

  type CompiledTrace = {
    canvas: {
      width: number;
      height: number;
    };
    frames: RenderPatch[][];
  };

  type LiveElement = RenderElement & {
    id: RenderId;
    exiting?: boolean;
  };

  let {
    src = '/compiled.json',
    transitionMs = 300
  }: {
    src?: string;
    transitionMs?: number;
  } = $props();

  let trace = $state<CompiledTrace | null>(null);
  let elements = $state<LiveElement[]>([]);
  let currStep = $state(0);
  let loading = $state(true);
  let error = $state<string | null>(null);

  const lastStep = $derived((trace?.frames.length ?? 0) - 1);
  const canvasWidth = $derived(trace?.canvas.width ?? 1200);
  const canvasHeight = $derived(trace?.canvas.height ?? 800);

  const destroyTimers = new Map<RenderId, ReturnType<typeof setTimeout>>();

  onMount(() => {
    void loadTrace();

    return () => {
      clearDestroyTimers();
    };
  });

  async function loadTrace() {
    loading = true;
    error = null;

    try {
      const response = await fetch(src);

      if (!response.ok) {
        throw new Error(`Failed to load ${src}: ${response.status} ${response.statusText}`);
      }

      trace = (await response.json()) as CompiledTrace;
      currStep = trace.frames.length > 0 ? 0 : -1;

      rebuildToStep(currStep);
    } catch (err) {
      error = err instanceof Error ? err.message : String(err);
    } finally {
      loading = false;
    }
  }

  function recomputeLayout() {
    if (!trace) return;

    currStep = trace.frames.length > 0 ? 0 : -1;
    rebuildToStep(currStep);
  }

  function nextStep() {
    if (!trace || currStep >= lastStep) return;

    const next = currStep + 1;
    applyFrame(trace.frames[next], { animateDestroy: true });
    currStep = next;
  }

  function prevStep() {
    if (!trace || currStep <= 0) return;

    currStep -= 1;
    rebuildToStep(currStep);
  }

  function rebuildToStep(step: number) {
    if (!trace) return;

    clearDestroyTimers();

    const next = new Map<RenderId, LiveElement>();

    for (let i = 0; i <= step; i++) {
      applyPatchesToMap(next, trace.frames[i], { animateDestroy: false });
    }

    elements = Array.from(next.values());
  }

  function applyFrame(patches: RenderPatch[], options: { animateDestroy: boolean }) {
    const next = new Map<RenderId, LiveElement>();

    for (const element of elements) {
      next.set(element.id, element);
    }

    applyPatchesToMap(next, patches, options);

    elements = Array.from(next.values());
  }

  function applyPatchesToMap(
    next: Map<RenderId, LiveElement>,
    patches: RenderPatch[],
    options: { animateDestroy: boolean }
  ) {
    for (const patch of patches) {
      switch (patch.kind) {
        case 'create': {
          clearDestroyTimer(patch.id);

          next.set(patch.id, {
            ...patch.element,
            id: patch.id,
            exiting: false
          });

          break;
        }

        case 'update': {
          clearDestroyTimer(patch.id);

          next.set(patch.id, {
            ...patch.to,
            id: patch.id,
            exiting: false
          });

          break;
        }

        case 'destroy': {
          if (options.animateDestroy) {
            const current = next.get(patch.id);

            next.set(patch.id, {
              ...(current ?? patch.element),
              id: patch.id,
              exiting: true
            });

            scheduleDestroy(patch.id);
          } else {
            clearDestroyTimer(patch.id);
            next.delete(patch.id);
          }

          break;
        }
      }
    }
  }

  function scheduleDestroy(id: RenderId) {
    clearDestroyTimer(id);

    const timer = setTimeout(() => {
      elements = elements.filter((element) => element.id !== id);
      destroyTimers.delete(id);
    }, transitionMs);

    destroyTimers.set(id, timer);
  }

  function clearDestroyTimer(id: RenderId) {
    const timer = destroyTimers.get(id);

    if (timer) {
      clearTimeout(timer);
      destroyTimers.delete(id);
    }
  }

  function clearDestroyTimers() {
    for (const timer of destroyTimers.values()) {
      clearTimeout(timer);
    }

    destroyTimers.clear();
  }

  function styleToString(element: LiveElement): string {
    const style = { ...element.style };

    if (element.exiting) {
      style.opacity = 0;
      style.transform = 'scale(0.9)';
      style.pointerEvents = 'none';
    }

    return Object.entries(style)
      .map(([key, value]) => `${camelToKebab(key)}: ${value};`)
      .join(' ');
  }

  function camelToKebab(value: string): string {
    return value.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`);
  }

  function classNameFor(element: LiveElement): string {
    return ['node', element.className, element.exiting ? 'exiting' : undefined]
      .filter(Boolean)
      .join(' ');
  }
</script>

<div class="page">
  <div class="toolbar">
    <button onclick={loadTrace} disabled={loading}>Reload</button>
    <button onclick={recomputeLayout} disabled={!trace || loading}>Reset</button>
    <button onclick={prevStep} disabled={!trace || currStep <= 0}>Previous</button>
    <button onclick={nextStep} disabled={!trace || currStep >= lastStep}>Next</button>

    {#if trace}
      <span class="step-label">
        Step {currStep + 1} / {trace.frames.length}
      </span>
    {/if}
  </div>

  {#if loading}
    <p class="status">Loading {src}...</p>
  {:else if error}
    <p class="error">{error}</p>
  {:else if trace}
    <div class="canvas" style:width={`${canvasWidth}px`} style:height={`${canvasHeight}px`}>
      {#each elements as element (element.id)}
        <div
          class={classNameFor(element)}
          data-render-id={element.id}
          data-block-id={element.blockId}
          data-kind={element.kind}
          style={styleToString(element)}
        >
          {element.content}
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .page {
    width: 100vw;
    height: 100vh;
    overflow: auto;
    background-color: rgb(30, 30, 30);
    padding: 12px;
    box-sizing: border-box;
  }

  .toolbar {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 10px;
  }

  button {
    min-width: 100px;
    height: 30px;
    background-color: lightblue;
    border: 1px solid rgb(80, 80, 80);
    border-radius: 4px;
    cursor: pointer;
  }

  button:disabled {
    background-color: gray;
    cursor: default;
  }

  .step-label {
    color: white;
    margin-left: 8px;
    font-family: system-ui, sans-serif;
  }

  .status {
    color: white;
    font-family: system-ui, sans-serif;
  }

  .error {
    color: rgb(255, 120, 120);
    font-family: system-ui, sans-serif;
  }

  .canvas {
    position: relative;
    overflow: hidden;
    background-color: rgb(220, 220, 220);
    background-image:
      linear-gradient(to right, rgba(0, 0, 0, 0.08) 1px, transparent 1px),
      linear-gradient(to bottom, rgba(0, 0, 0, 0.08) 1px, transparent 1px);
    background-size: 20px 20px;
    z-index: 10000;
  }

  .node {
    box-sizing: border-box;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    user-select: none;

    transition:
      top 300ms ease,
      left 300ms ease,
      width 300ms ease,
      height 300ms ease,
      opacity 300ms ease,
      transform 300ms ease,
      background-color 300ms ease,
      border-color 300ms ease,
      border-radius 300ms ease,
      font-size 300ms ease;
  }
</style>
