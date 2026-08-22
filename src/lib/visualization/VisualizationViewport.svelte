<script lang="ts">
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';
  import { scale } from 'svelte/transition';

  import { Button } from '$lib/components/ui/button';

  import type { HslColor, LiveElement, RenderInstanceId } from './types';

  /** Public properties for the pannable, zoomable visualization viewport. */
  type Props = {
    width: number;
    height: number;
    elements: LiveElement[];
    selectedIds?: RenderInstanceId[];
    onSelectionChange?: (ids: RenderInstanceId[]) => void;
  };

  let {
    width,
    height,
    elements,
    selectedIds = $bindable<RenderInstanceId[]>([]),
    onSelectionChange = (_ids: RenderInstanceId[]) => {}
  }: Props = $props();

  let svg = $state<SVGSVGElement | null>(null);
  let zoom = $state(1);
  let panX = $state(0);
  let panY = $state(0);
  let pointerId = $state<number | null>(null);
  let dragMode = $state<'pan' | 'select' | null>(null);
  let dragStart = $state({ x: 0, y: 0 });
  let dragCurrent = $state({ x: 0, y: 0 });

  const minZoom = 0.25;
  const maxZoom = 6;

  const transform = $derived(`translate(${panX} ${panY}) scale(${zoom})`);
  const orderedElements = $derived(
    elements.toSorted(
      (left, right) =>
        (left.style.zIndex ?? 0) - (right.style.zIndex ?? 0) ||
        Number(left.kind.kind !== 'group') - Number(right.kind.kind !== 'group') ||
        left.id - right.id
    )
  );
  const selectionBox = $derived(
    dragMode === 'select'
      ? {
          x: Math.min(dragStart.x, dragCurrent.x),
          y: Math.min(dragStart.y, dragCurrent.y),
          width: Math.abs(dragCurrent.x - dragStart.x),
          height: Math.abs(dragCurrent.y - dragStart.y)
        }
      : null
  );

  function resetViewport() {
    zoom = 1;
    panX = 0;
    panY = 0;
  }

  function onWheel(event: WheelEvent) {
    event.preventDefault();
    const nextZoom = clamp(zoom * (event.deltaY < 0 ? 1.1 : 1 / 1.1), minZoom, maxZoom);
    const point = scenePoint(event.clientX, event.clientY);

    panX += point.x * (1 - nextZoom / zoom);
    panY += point.y * (1 - nextZoom / zoom);
    zoom = nextZoom;
  }

  function onPointerDown(event: PointerEvent) {
    if (!svg || event.button === 2) return;

    const target = (event.target as Element | null)?.closest<SVGGraphicsElement>(
      '[data-instance-id]'
    );
    const instanceIdText = target?.dataset.instanceId;
    const instanceId = instanceIdText === undefined ? undefined : Number(instanceIdText);
    const wantsPan = event.button === 1 || event.altKey || event.ctrlKey;

    if (instanceId !== undefined && !wantsPan) {
      setSelection(
        event.shiftKey
          ? selectedIds.includes(instanceId)
            ? selectedIds.filter((id) => id !== instanceId)
            : [...selectedIds, instanceId]
          : [instanceId]
      );
      return;
    }

    pointerId = event.pointerId;
    dragMode = wantsPan ? 'pan' : 'select';
    dragStart =
      dragMode === 'pan'
        ? viewportPoint(event.clientX, event.clientY)
        : scenePoint(event.clientX, event.clientY);
    dragCurrent = dragStart;
    svg.setPointerCapture(event.pointerId);
    event.preventDefault();
  }

  function onPointerMove(event: PointerEvent) {
    if (pointerId !== event.pointerId || !dragMode) return;

    const point =
      dragMode === 'pan'
        ? viewportPoint(event.clientX, event.clientY)
        : scenePoint(event.clientX, event.clientY);
    if (dragMode === 'pan') {
      panX += point.x - dragCurrent.x;
      panY += point.y - dragCurrent.y;
    }
    dragCurrent = point;
  }

  function onPointerUp(event: PointerEvent) {
    if (!svg || pointerId !== event.pointerId) return;

    if (dragMode === 'select' && selectionBox) {
      const dragged = selectionBox.width > 4 || selectionBox.height > 4;
      const ids = dragged
        ? elements
            .filter((element) => intersects(selectionBox!, element))
            .map(({ instanceId }) => instanceId)
        : [];
      setSelection(event.shiftKey ? unique([...selectedIds, ...ids]) : ids);
    }

    svg.releasePointerCapture(event.pointerId);
    pointerId = null;
    dragMode = null;
  }

  function setSelection(ids: RenderInstanceId[]) {
    selectedIds = unique(ids);
    onSelectionChange(selectedIds);
  }

  function viewportPoint(clientX: number, clientY: number) {
    if (!svg) return { x: 0, y: 0 };
    const screenTransform = svg.getScreenCTM();
    if (!screenTransform) return { x: 0, y: 0 };

    const pointer = svg.createSVGPoint();
    pointer.x = clientX;
    pointer.y = clientY;
    return pointer.matrixTransform(screenTransform.inverse());
  }

  function scenePoint(clientX: number, clientY: number) {
    const point = viewportPoint(clientX, clientY);

    return {
      x: (point.x - panX) / zoom,
      y: (point.y - panY) / zoom
    };
  }

  function intersects(
    box: { x: number; y: number; width: number; height: number },
    element: LiveElement
  ) {
    const style = element.style;
    return (
      style.left < box.x + box.width &&
      style.left + style.width > box.x &&
      style.top < box.y + box.height &&
      style.top + style.height > box.y
    );
  }

  function color(value: HslColor | undefined, alpha = 1, fallback = 'transparent') {
    if (!value) return fallback;
    return `hsl(${value.hue} ${value.saturation * 100}% ${value.lightness * 100}% / ${alpha})`;
  }

  function clamp(value: number, lower: number, upper: number) {
    return Math.min(upper, Math.max(lower, value));
  }

  function unique(ids: RenderInstanceId[]) {
    return [...new Set(ids)];
  }
</script>

<div class="viewport" aria-label="Visualization canvas">
  <Button
    class="absolute top-3 right-3 z-10"
    variant="outline"
    size="sm"
    onclick={resetViewport}
    aria-label="Reset zoom and pan"
  >
    <RotateCcwIcon data-icon="inline-start" />
    Reset view
  </Button>
  <svg
    bind:this={svg}
    class="scene"
    viewBox={`0 0 ${width} ${height}`}
    preserveAspectRatio="xMidYMid meet"
    role="img"
    aria-label={`Visualization aspect ratio ${width}:${height}`}
    onwheel={onWheel}
    onpointerdown={onPointerDown}
    onpointermove={onPointerMove}
    onpointerup={onPointerUp}
    onpointercancel={onPointerUp}
  >
    <g {transform}>
      <rect {width} {height} fill="white" />
      <rect
        class="scene-boundary"
        {width}
        {height}
        fill="none"
        stroke="currentColor"
        stroke-dasharray="6 4"
        vector-effect="non-scaling-stroke"
      />
      <foreignObject x="0" y="0" {width} {height}>
        <div class="visual-canvas" xmlns="http://www.w3.org/1999/xhtml">
          {#each orderedElements as element (element.instanceId)}
            {@const style = element.style}
            <div
              data-visual-id={element.id}
              data-instance-id={element.instanceId}
              class="visual-presence"
              aria-label={`${element.role} ${element.id}`}
              style:top={`${style.top}px`}
              style:left={`${style.left}px`}
              style:width={`${style.width}px`}
              style:height={`${style.height}px`}
              style:z-index={style.zIndex}
              transition:scale={{ duration: 300, start: 0.9 }}
            >
              <div
                class:selected={selectedIds.includes(element.instanceId)}
                class="visual-element"
                style:opacity={style.opacity ?? 1}
                style:padding={`${style.padding ?? 0}px`}
                style:border-radius={`${style.radius ?? 0}px`}
                style:border-width={`${style.borderStyle === 'none' ? 0 : (style.strokeWidth ?? 0)}px`}
                style:border-style={style.borderStyle ?? 'solid'}
                style:border-color={color(style.stroke, style.alpha)}
                style:background-color={color(style.fill, style.alpha)}
                style:font-family={style.fontFamily}
                style:font-size={`${style.fontSize ?? 14}px`}
                style:font-weight={style.fontWeight}
                style:font-style={style.fontStyle}
                style:text-align={style.textAlign ?? 'center'}
                style:white-space={style.whiteSpace ?? 'normal'}
              >
                {#if element.content}
                  <div class="visual-content">
                    {element.content}
                  </div>
                {/if}
              </div>
            </div>
          {/each}
        </div>
      </foreignObject>

      {#if selectionBox}
        <rect class="selection-box" {...selectionBox} />
      {/if}
    </g>
  </svg>
</div>

<style>
  .viewport {
    position: relative;
    display: grid;
    width: 100%;
    height: 100%;
    min-width: 0;
    min-height: 0;
    place-items: center;
    overflow: hidden;
    background: white;
    touch-action: none;
  }

  .scene {
    width: 100%;
    height: 100%;
    min-width: 0;
    min-height: 0;
    cursor: crosshair;
    user-select: none;
  }

  .scene-boundary {
    color: #94a3b8;
    pointer-events: none;
  }

  .visual-canvas {
    position: relative;
    width: 100%;
    height: 100%;
    overflow: hidden;
    color: #0f172a;
  }

  .visual-presence {
    position: absolute;
    box-sizing: border-box;
    transition:
      top 300ms ease,
      left 300ms ease,
      width 300ms ease,
      height 300ms ease;
  }

  .visual-element {
    display: flex;
    width: 100%;
    height: 100%;
    box-sizing: border-box;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    cursor: pointer;
    user-select: none;
    transition:
      opacity 300ms ease,
      padding 300ms ease,
      border-color 300ms ease,
      border-radius 300ms ease,
      border-width 300ms ease,
      background-color 300ms ease,
      font-size 300ms ease;
  }

  .visual-content {
    width: 100%;
    overflow: hidden;
  }

  .visual-element.selected {
    box-shadow:
      0 0 0 2px #2563eb,
      0 0 5px rgb(37 99 235 / 0.9);
  }

  .selection-box {
    fill: rgb(37 99 235 / 0.12);
    stroke: #2563eb;
    stroke-dasharray: 4 3;
    vector-effect: non-scaling-stroke;
    pointer-events: none;
  }
</style>
