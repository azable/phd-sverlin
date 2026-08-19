<script lang="ts">
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';

  import { Button } from '$lib/components/ui/button';

  import type { HslColor, LiveElement } from './types';

  let {
    width,
    height,
    background,
    elements,
    selectedIds = $bindable<string[]>([]),
    onSelectionChange = (_ids: string[]) => {}
  }: {
    width: number;
    height: number;
    background?: HslColor;
    elements: LiveElement[];
    selectedIds?: string[];
    onSelectionChange?: (ids: string[]) => void;
  } = $props();

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

  let transform = $derived(`translate(${panX} ${panY}) scale(${zoom})`);
  let orderedElements = $derived(
    elements.toSorted(
      (left, right) =>
        (left.style.zIndex ?? 0) - (right.style.zIndex ?? 0) ||
        Number(left.kind.kind === 'trace') - Number(right.kind.kind === 'trace') ||
        left.nodeId - right.nodeId
    )
  );
  let selectionBox = $derived(
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
      '[data-visual-id]'
    );
    const visualId = target?.dataset.visualId;

    if (visualId) {
      setSelection(
        event.shiftKey
          ? selectedIds.includes(visualId)
            ? selectedIds.filter((id) => id !== visualId)
            : [...selectedIds, visualId]
          : [visualId]
      );
      return;
    }

    pointerId = event.pointerId;
    dragStart = scenePoint(event.clientX, event.clientY);
    dragCurrent = dragStart;
    dragMode = event.button === 1 || event.altKey || event.ctrlKey ? 'pan' : 'select';
    svg.setPointerCapture(event.pointerId);
    event.preventDefault();
  }

  function onPointerMove(event: PointerEvent) {
    if (pointerId !== event.pointerId || !dragMode) return;

    const point = scenePoint(event.clientX, event.clientY);
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
        ? elements.filter((element) => intersects(selectionBox!, element)).map(({ id }) => id)
        : [];
      setSelection(event.shiftKey ? unique([...selectedIds, ...ids]) : ids);
    }

    svg.releasePointerCapture(event.pointerId);
    pointerId = null;
    dragMode = null;
  }

  function setSelection(ids: string[]) {
    selectedIds = unique(ids);
    onSelectionChange(selectedIds);
  }

  function scenePoint(clientX: number, clientY: number) {
    if (!svg) return { x: 0, y: 0 };
    const bounds = svg.getBoundingClientRect();
    const x = ((clientX - bounds.left) / bounds.width) * width;
    const y = ((clientY - bounds.top) / bounds.height) * height;
    return { x: (x - panX) / zoom, y: (y - panY) / zoom };
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

  function unique(ids: string[]) {
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
    <rect {width} {height} fill={color(background, 1, 'white')} />
    <rect
      class="scene-boundary"
      {width}
      {height}
      fill="none"
      stroke="currentColor"
      stroke-dasharray="6 4"
      vector-effect="non-scaling-stroke"
    />
    <g {transform}>
      {#each orderedElements as element (element.instanceId)}
        {@const style = element.style}
        <g
          data-visual-id={element.id}
          data-instance-id={element.instanceId}
          data-node-id={element.nodeId}
          class:selected={selectedIds.includes(element.id)}
          class="visual-element"
          role="button"
          aria-label={`${element.role} ${element.nodeKey}`}
        >
          <rect
            x={style.left}
            y={style.top}
            width={style.width}
            height={style.height}
            rx={style.radius ?? 0}
            fill={color(style.fill, style.alpha)}
            stroke={color(style.stroke, style.alpha)}
            stroke-width={style.borderStyle === 'none' ? 0 : (style.strokeWidth ?? 0)}
            stroke-dasharray={style.borderStyle === 'dashed'
              ? '6 4'
              : style.borderStyle === 'dotted'
                ? '2 3'
                : undefined}
            opacity={style.opacity ?? 1}
          />
          {#if element.content}
            <foreignObject
              x={style.left}
              y={style.top}
              width={style.width}
              height={style.height}
              opacity={style.opacity ?? 1}
              class="pointer-events-none overflow-visible"
            >
              <div
                class="grid h-full w-full items-center overflow-hidden text-slate-900"
                style:box-sizing="border-box"
                style:padding={`${style.padding ?? 0}px`}
                style:font-family={style.fontFamily}
                style:font-size={`${style.fontSize ?? 14}px`}
                style:font-weight={style.fontWeight}
                style:font-style={style.fontStyle}
                style:text-align={style.textAlign ?? 'center'}
                style:white-space={style.whiteSpace ?? 'normal'}
              >
                {element.content}
              </div>
            </foreignObject>
          {/if}
        </g>
      {/each}

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

  .visual-element {
    cursor: pointer;
    transition: opacity 300ms ease;
  }

  .visual-element.selected {
    filter: drop-shadow(0 0 3px rgb(37 99 235 / 0.9));
  }

  .visual-element.selected > rect {
    stroke: #2563eb;
    stroke-dasharray: 4 3;
  }

  .selection-box {
    fill: rgb(37 99 235 / 0.12);
    stroke: #2563eb;
    stroke-dasharray: 4 3;
    vector-effect: non-scaling-stroke;
    pointer-events: none;
  }
</style>
