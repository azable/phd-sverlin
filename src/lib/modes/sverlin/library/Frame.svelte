<!--
  The page around every view: a canvas at a fixed logical size, centred in the page and scaled to
  fit it, that arranges the view's top-level nodes in a column. Its edges are a dashed outline, and
  participants zoom with the wheel, pan by dragging, and reset with a double click. The view is
  reported to the app, which restores it when the next step reloads the sandboxed page.
-->
<script lang="ts">
  import { untrack, type Component } from 'svelte';

  import { defaultsContext } from './type-context';
  import {
    alignments,
    frameRatios,
    frameWidth,
    justifications,
    measure,
    spacings
  } from './node/presets';
  import type { FrameSettings } from './node/props';

  let {
    view: View,
    props,
    settings
  }: {
    /** The authored view. */
    view: Component<Record<string, unknown>>;
    /** The view's props: the step's state, design values, step, and seed. */
    props: Record<string, unknown>;
    settings: FrameSettings;
  } = $props();

  const drawn = defaultsContext();
  const width = frameWidth;
  const height = $derived(Math.round(frameWidth / frameRatios[settings.ratio]));

  // The canvas element's own size, observed directly: the window size and its resize events can lag
  // behind the iframe's real size, such as when the app opens a pane, and a stale size would both
  // misfit the frame and move the point zooming keeps still.
  let viewport = $state({ width: 0, height: 0 });
  // A margin keeps the outline in view at the fitted size.
  const margin = 16;
  const scale = $derived(
    viewport.width > 2 * margin && viewport.height > 2 * margin
      ? Math.min((viewport.width - 2 * margin) / width, (viewport.height - 2 * margin) / height)
      : 1
  );

  // The wheel zooms around the pointer, dragging pans, and a double click resets.
  const minZoom = 0.25;
  const maxZoom = 8;
  type CanvasView = { zoom: number; panX: number; panY: number };
  const restored = untrack(() => {
    const saved = (window as { __sverlinView?: Partial<CanvasView> }).__sverlinView;
    return saved && [saved.zoom, saved.panX, saved.panY].every(Number.isFinite)
      ? (saved as CanvasView)
      : { zoom: 1, panX: 0, panY: 0 };
  });
  let zoom = $state(Math.min(Math.max(restored.zoom, minZoom), maxZoom));
  let panX = $state(restored.panX);
  let panY = $state(restored.panY);
  let dragging = $state<{ pointer: number; x: number; y: number } | undefined>();
  const shown = $derived(scale * zoom);

  function report() {
    if (window.parent !== window)
      window.parent.postMessage({ type: 'sverlin:view', zoom, panX, panY }, '*');
  }

  function onWheel(event: WheelEvent) {
    event.preventDefault();
    // Deltas in lines or pages become pixels, so every device zooms by the distance it scrolls: a
    // mouse wheel notch (about 100 pixels) zooms by 10%, and a trackpad's many small events add up
    // smoothly. A pinch arrives as a wheel event with ctrlKey and small deltas, so it counts more.
    const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? viewport.height : 1;
    // Sideways scrolling, as on a trackpad, pans instead.
    panX -= event.deltaX * unit;
    const rate = event.ctrlKey ? 0.01 : Math.log(1.1) / 100;
    const next = Math.min(Math.max(zoom * Math.exp(-event.deltaY * unit * rate), minZoom), maxZoom);
    // Keep the point under the pointer still. The frame's centre sits at the canvas centre plus the
    // pan, so positions are taken relative to the canvas centre, measured now.
    const box = (event.currentTarget as Element).getBoundingClientRect();
    const x = event.clientX - (box.left + box.width / 2);
    const y = event.clientY - (box.top + box.height / 2);
    panX = x - (x - panX) * (next / zoom);
    panY = y - (y - panY) * (next / zoom);
    zoom = next;
    report();
  }

  function onPointerDown(event: PointerEvent) {
    if (event.button !== 0) return;
    dragging = { pointer: event.pointerId, x: event.clientX, y: event.clientY };
    (event.currentTarget as Element).setPointerCapture(event.pointerId);
  }

  function onPointerMove(event: PointerEvent) {
    if (dragging?.pointer !== event.pointerId) return;
    panX += event.clientX - dragging.x;
    panY += event.clientY - dragging.y;
    dragging = { ...dragging, x: event.clientX, y: event.clientY };
  }

  function onPointerUp(event: PointerEvent) {
    if (dragging?.pointer !== event.pointerId) return;
    dragging = undefined;
    report();
  }

  function resetView() {
    zoom = 1;
    panX = 0;
    panY = 0;
    report();
  }

  // The outline is drawn unscaled, just outside the frame, so its dashes keep their size on screen.
  const edgeOffset = 6;
  const edgeWidth = 1.5;
  const edge = $derived({
    width: width * shown + 2 * edgeOffset,
    height: height * shown + 2 * edgeOffset
  });
</script>

<div
  class="sv-viewport"
  bind:clientWidth={viewport.width}
  bind:clientHeight={viewport.height}
  class:dragging={dragging !== undefined}
  role="application"
  aria-label="Visualization canvas: scroll to zoom, drag to pan, double-click to reset"
  onwheel={onWheel}
  onpointerdown={onPointerDown}
  onpointermove={onPointerMove}
  onpointerup={onPointerUp}
  onpointercancel={onPointerUp}
  ondblclick={resetView}
>
  <div
    class="sv-frame"
    style:width="{width}px"
    style:height="{height}px"
    style:transform="translate(-50%, -50%) translate({panX}px, {panY}px) scale({shown})"
    style:padding={measure(spacings, settings.padding)}
    style:gap={measure(spacings, drawn?.gap ?? 'medium')}
    style:justify-content={justifications[settings.justify ?? drawn?.frame.justify ?? 'start']}
    style:align-items={alignments[settings.align ?? drawn?.frame.align ?? 'center']}
  >
    <View {...props} />
  </div>
  <svg
    class="sv-edge"
    width={edge.width}
    height={edge.height}
    style:transform="translate(-50%, -50%) translate({panX}px, {panY}px)"
    aria-hidden="true"
  >
    <rect
      x={edgeWidth / 2}
      y={edgeWidth / 2}
      width={edge.width - edgeWidth}
      height={edge.height - edgeWidth}
      rx="4"
      stroke-width={edgeWidth}
      stroke-dasharray="14 9"
    />
  </svg>
</div>

<style>
  .sv-viewport {
    position: fixed;
    inset: 0;
    overflow: hidden;
    cursor: grab;
    touch-action: none;
  }
  .sv-viewport.dragging {
    cursor: grabbing;
  }
  /* Both are centred on the page by their own size, then panned; only the frame is scaled. */
  .sv-frame,
  .sv-edge {
    position: absolute;
    left: 50%;
    top: 50%;
  }
  .sv-frame {
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
    transform-origin: center;
    background: var(--sv-surface);
  }
  .sv-edge {
    pointer-events: none;
    overflow: visible;
  }
  .sv-edge rect {
    fill: none;
    stroke: var(--sv-muted);
  }
</style>
