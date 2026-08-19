<script lang="ts">
  import { onMount } from 'svelte';

  import TraceCanvas from './TraceCanvas.svelte';
  import type { LiveElement } from './types';

  let {
    width,
    height,
    elements
  }: {
    width: number;
    height: number;
    elements: LiveElement[];
  } = $props();

  let viewport = $state<HTMLElement | null>(null);
  let viewportWidth = $state(0);
  let viewportHeight = $state(0);

  // The smaller of the width and height ratios is the limiting axis. Using it
  // for both dimensions keeps the trace's aspect ratio intact and avoids
  // introducing scrollbars when the pane changes size.
  let scale = $derived(
    width > 0 && height > 0 && viewportWidth > 0 && viewportHeight > 0
      ? Math.max(0.01, Math.min(viewportWidth / width, viewportHeight / height))
      : 1
  );
  let fittedWidth = $derived(width * scale);
  let fittedHeight = $derived(height * scale);

  onMount(() => {
    if (!viewport) return;

    const observer = new ResizeObserver(([entry]) => {
      if (!entry) return;

      viewportWidth = entry.contentRect.width;
      viewportHeight = entry.contentRect.height;
    });

    observer.observe(viewport);

    return () => observer.disconnect();
  });
</script>

<div bind:this={viewport} class="viewport" aria-label="Visualization canvas">
  {#if width > 0 && height > 0}
    <div
      class="scene-slot"
      style:width={`${fittedWidth}px`}
      style:height={`${fittedHeight}px`}
      data-scale={scale}
    >
      <div
        class="scene-frame"
        style:width={`${width}px`}
        style:height={`${height}px`}
        style:transform={`scale(${scale})`}
        aria-label={`Visualization aspect ratio ${width}:${height}`}
      >
        <TraceCanvas {elements} {width} {height} />
      </div>
    </div>
  {/if}
</div>

<style>
  .viewport {
    box-sizing: border-box;
    display: flex;
    width: 100%;
    height: 100%;
    min-width: 0;
    min-height: 0;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    background: #fff;
    color: rgb(100 116 139);
  }

  .scene-slot {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 0 0 auto;
  }

  .scene-frame {
    position: relative;
    flex: 0 0 auto;
    transform-origin: center;
  }

  /* This boundary marks the fitted aspect-ratio bounds without changing the
     canvas dimensions or affecting the scale calculation. */
  .scene-frame::after {
    position: absolute;
    inset: 0;
    border: 1px dashed currentColor;
    content: '';
    pointer-events: none;
  }
</style>
