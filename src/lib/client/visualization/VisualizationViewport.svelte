<script lang="ts">
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';

  import { Button } from '$lib/client/components/ui/button';

  import { codeRenderSegments } from './code-emphasis';
  import {
    compilerFontFamily,
    ensureCompilerFont,
    fontFeatureSettings,
    fontVariationSettings
  } from './font-resources';
  import type {
    HslColor,
    CodeTokenKind,
    LiveElement,
    RenderInstanceId,
    TextRuntimeObservation,
    VisualElement
  } from './types';

  /** Public properties for the pannable, zoomable visualization viewport. */
  type Props = {
    width: number;
    height: number;
    root: VisualElement;
    elements: LiveElement[];
    selectedIds?: RenderInstanceId[];
    resourceBaseUrl?: string;
    onSelectionChange?: (ids: RenderInstanceId[]) => void;
    onFontLoadFailure?: (resourceId: string, message: string) => void;
    onRuntimeObservation?: (observation: TextRuntimeObservation) => void;
  };

  let {
    width,
    height,
    root,
    elements,
    selectedIds = $bindable<RenderInstanceId[]>([]),
    resourceBaseUrl,
    onSelectionChange = (_ids: RenderInstanceId[]) => {},
    onFontLoadFailure = (_resourceId: string, _message: string) => {},
    onRuntimeObservation = (_observation: TextRuntimeObservation) => {}
  }: Props = $props();

  let svg = $state<SVGSVGElement | null>(null);
  let zoom = $state(1);
  let panX = $state(0);
  let panY = $state(0);
  let pointerId = $state<number | null>(null);
  let dragMode = $state<'pan' | 'select' | null>(null);
  let dragStart = $state({ x: 0, y: 0 });
  let dragCurrent = $state({ x: 0, y: 0 });
  let fontStates = $state<Record<string, 'loading' | 'ready' | 'failed'>>({});

  const minZoom = 0.25;
  const maxZoom = 6;

  const transform = $derived(`translate(${panX} ${panY}) scale(${zoom})`);
  const orderedElements = $derived(
    elements.toSorted(
      (left, right) =>
        (left.style.zIndex ?? 0) - (right.style.zIndex ?? 0) ||
        Number(left.children.length === 0) - Number(right.children.length === 0) ||
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

  $effect(() => {
    for (const element of elements) {
      if (
        element.content?.kind !== 'plainTextContent' &&
        element.content?.kind !== 'codeTextContent'
      ) {
        continue;
      }
      const font = element.content.textLayout.layoutFont;
      const resourceId = font.instanceResourceId;
      if (fontStates[resourceId]) continue;
      if (!resourceBaseUrl) {
        fontStates[resourceId] = 'failed';
        onFontLoadFailure(resourceId, 'No compiler resource URL was supplied for this font.');
        continue;
      }

      fontStates[resourceId] = 'loading';
      const resourceUrl = `${resourceBaseUrl.replace(/\/$/, '')}/${encodeURIComponent(resourceId)}`;
      void ensureCompilerFont(font, resourceUrl).then(
        () => {
          fontStates[resourceId] = 'ready';
        },
        (cause: unknown) => {
          fontStates[resourceId] = 'failed';
          onFontLoadFailure(resourceId, cause instanceof Error ? cause.message : String(cause));
        }
      );
    }
  });

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
    const bounds = element.box.bounds;
    return (
      bounds.rectX < box.x + box.width &&
      bounds.rectX + bounds.rectWidth > box.x &&
      bounds.rectY < box.y + box.height &&
      bounds.rectY + bounds.rectHeight > box.y
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

  function borderDasharray(borderStyle: string | undefined): string | undefined {
    if (borderStyle === 'dashed') return '6 4';
    if (borderStyle === 'dotted') return '2 3';
    return undefined;
  }

  function codeTokenColor(kind: CodeTokenKind): string {
    switch (kind) {
      case 'codeKeyword':
        return '#7c3aed';
      case 'codeType':
        return '#0f766e';
      case 'codeNumber':
        return '#1d4ed8';
      case 'codeString':
        return '#15803d';
      case 'codeComment':
        return '#64748b';
      case 'codeFunction':
        return '#0369a1';
      case 'codeVariable':
        return '#9a3412';
      case 'codeOperator':
        return '#334155';
      case 'codeError':
        return '#dc2626';
      case 'codeNormal':
        return '#0f172a';
    }
  }

  function legacyTextX(element: LiveElement): number {
    const bounds = element.box.bounds;
    const padding = element.box.padding;
    if (element.style.textAlign === 'left') return bounds.rectX + padding.left;
    if (element.style.textAlign === 'right') {
      return bounds.rectX + bounds.rectWidth - padding.right;
    }
    return bounds.rectX + bounds.rectWidth / 2;
  }

  function legacyTextAnchor(element: LiveElement): 'start' | 'middle' | 'end' {
    if (element.style.textAlign === 'left') return 'start';
    if (element.style.textAlign === 'right') return 'end';
    return 'middle';
  }

  type TextProbe = {
    instanceId: RenderInstanceId;
    elementId: number;
    lineIndex: number;
    fontResourceId: string;
    expectedAdvance: number;
    fontState: 'loading' | 'ready' | 'failed' | undefined;
  };

  function observeText(node: SVGTextElement, initial: TextProbe) {
    let probe = initial;
    let disposed = false;
    let lastReport = '';

    function measure() {
      if (disposed || probe.fontState !== 'ready') return;
      void document.fonts.ready.then(() => {
        requestAnimationFrame(() => {
          if (disposed) return;
          const textLength = node.getAttribute('textLength');
          node.removeAttribute('textLength');
          const measuredAdvance = node.getComputedTextLength();
          if (textLength !== null) node.setAttribute('textLength', textLength);
          const difference = Math.abs(measuredAdvance - probe.expectedAdvance);
          const tolerance = Math.max(0.25, probe.expectedAdvance * 0.005);
          const reportKey = `${probe.fontResourceId}:${probe.expectedAdvance}:${measuredAdvance.toFixed(3)}`;
          if (difference <= tolerance || reportKey === lastReport) return;
          lastReport = reportKey;
          onRuntimeObservation({
            code: 'text.metric-mismatch',
            instanceId: probe.instanceId,
            elementId: probe.elementId,
            lineIndex: probe.lineIndex,
            fontResourceId: probe.fontResourceId,
            expectedAdvance: probe.expectedAdvance,
            measuredAdvance,
            difference
          });
        });
      });
    }

    measure();
    return {
      update(next: TextProbe) {
        probe = next;
        measure();
      },
      destroy() {
        disposed = true;
      }
    };
  }
</script>

<div class="viewport" aria-label="Visualization viewport">
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
      <rect
        data-visual-id={root.id}
        {width}
        {height}
        rx={root.style.radius ?? 0}
        fill={color(root.style.fill, root.style.alpha, 'white')}
        opacity={root.style.opacity ?? 1}
        stroke={root.style.borderStyle === 'none'
          ? 'none'
          : color(root.style.stroke, root.style.alpha, 'transparent')}
        stroke-width={root.style.borderStyle === 'none' ? 0 : (root.style.strokeWidth ?? 0)}
        stroke-dasharray={borderDasharray(root.style.borderStyle)}
      />
      <rect
        class="scene-boundary"
        {width}
        {height}
        fill="none"
        stroke="currentColor"
        stroke-dasharray="6 4"
        vector-effect="non-scaling-stroke"
      />
      <defs>
        {#each orderedElements as element (element.instanceId)}
          <clipPath id={`visual-clip-${element.instanceId}`}>
            <rect
              x={element.box.bounds.rectX}
              y={element.box.bounds.rectY}
              width={element.box.bounds.rectWidth}
              height={element.box.bounds.rectHeight}
              rx={element.style.radius ?? 0}
            />
          </clipPath>
        {/each}
      </defs>

      {#each orderedElements as element (element.instanceId)}
        {@const style = element.style}
        {@const bounds = element.box.bounds}
        <g
          data-visual-id={element.id}
          data-instance-id={element.instanceId}
          class="visual-presence"
          aria-label={`${element.role} ${element.id}`}
          opacity={style.opacity ?? 1}
        >
          <rect
            class="visual-element"
            x={bounds.rectX}
            y={bounds.rectY}
            width={bounds.rectWidth}
            height={bounds.rectHeight}
            rx={style.radius ?? 0}
            fill={color(style.fill, style.alpha)}
            stroke={style.borderStyle === 'none'
              ? 'none'
              : color(style.stroke, style.alpha, 'currentColor')}
            stroke-width={style.borderStyle === 'none' ? 0 : (style.strokeWidth ?? 0)}
            stroke-dasharray={borderDasharray(style.borderStyle)}
          />

          {#if element.content?.kind === 'plainTextContent'}
            {@const layout = element.content.textLayout}
            {@const font = layout.layoutFont}
            <g
              class:font-ready={fontStates[font.instanceResourceId] === 'ready'}
              class="compiler-text"
              clip-path={`url(#visual-clip-${element.instanceId})`}
              aria-label={layout.layoutSource}
            >
              {#each layout.layoutLines as line, lineIndex (lineIndex)}
                <text
                  use:observeText={{
                    instanceId: element.instanceId,
                    elementId: element.id,
                    lineIndex,
                    fontResourceId: font.instanceResourceId,
                    expectedAdvance: line.lineAdvance,
                    fontState: fontStates[font.instanceResourceId]
                  }}
                  x={line.lineOriginX}
                  y={line.lineBaselineY}
                  fill="#0f172a"
                  font-family={compilerFontFamily(font.instanceResourceId)}
                  font-size={layout.layoutFontSize}
                  font-style={font.instanceStyle}
                  font-weight={font.instanceWeight}
                  direction={layout.layoutDirection === 'textRightToLeft' ? 'rtl' : 'ltr'}
                  text-anchor="start"
                  lengthAdjust="spacing"
                  textLength={line.lineAdvance > 0 ? line.lineAdvance : undefined}
                  style:font-feature-settings={fontFeatureSettings(font)}
                  style:font-optical-sizing="none"
                  style:font-variation-settings={fontVariationSettings(font)}
                  >{line.lineDisplayText}</text
                >
              {/each}
            </g>
          {:else if element.content?.kind === 'codeTextContent'}
            {@const layout = element.content.textLayout}
            {@const font = layout.layoutFont}
            <g
              class:font-ready={fontStates[font.instanceResourceId] === 'ready'}
              class="compiler-text"
              clip-path={`url(#visual-clip-${element.instanceId})`}
              aria-label={layout.layoutSource}
            >
              {#each layout.layoutLines as line, lineIndex (lineIndex)}
                {@const highlights = element.content.textHighlightLines[lineIndex]}
                {@const segments = codeRenderSegments(highlights ?? [], element.codeEmphasisRanges)}
                <text
                  use:observeText={{
                    instanceId: element.instanceId,
                    elementId: element.id,
                    lineIndex,
                    fontResourceId: font.instanceResourceId,
                    expectedAdvance: line.lineAdvance,
                    fontState: fontStates[font.instanceResourceId]
                  }}
                  x={line.lineOriginX}
                  y={line.lineBaselineY}
                  fill="#0f172a"
                  font-family={compilerFontFamily(font.instanceResourceId)}
                  font-size={layout.layoutFontSize}
                  font-style={font.instanceStyle}
                  font-weight={font.instanceWeight}
                  direction={layout.layoutDirection === 'textRightToLeft' ? 'rtl' : 'ltr'}
                  text-anchor="start"
                  lengthAdjust="spacing"
                  textLength={line.lineAdvance > 0 ? line.lineAdvance : undefined}
                  style:font-feature-settings={fontFeatureSettings(font)}
                  style:font-optical-sizing="none"
                  style:font-variation-settings={fontVariationSettings(font)}
                  >{#each segments as segment, segmentIndex (segmentIndex)}<tspan
                      class:code-emphasis={segment.emphasized}
                      fill={codeTokenColor(segment.tokenKind)}>{segment.text}</tspan
                    >{/each}</text
                >
              {/each}
            </g>
          {:else if element.content?.kind === 'legacyTextContent'}
            <text
              class="legacy-text"
              x={legacyTextX(element)}
              y={bounds.rectY + bounds.rectHeight / 2}
              fill="#0f172a"
              font-family={style.fontFamily}
              font-size={style.fontSize ?? 14}
              font-style={style.fontStyle}
              font-weight={style.fontWeight}
              text-anchor={legacyTextAnchor(element)}
              dominant-baseline="middle"
              clip-path={`url(#visual-clip-${element.instanceId})`}
              >{element.content.textSource}</text
            >
          {/if}

          {#if selectedIds.includes(element.instanceId)}
            <rect
              class="selection-outline"
              x={bounds.rectX}
              y={bounds.rectY}
              width={bounds.rectWidth}
              height={bounds.rectHeight}
              rx={style.radius ?? 0}
            />
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

  .visual-presence {
    cursor: pointer;
  }

  .visual-element {
    transition:
      fill 300ms ease,
      stroke 300ms ease;
  }

  .compiler-text,
  .legacy-text {
    pointer-events: none;
    white-space: pre;
  }

  .compiler-text {
    font-synthesis: none;
    opacity: 0;
    transition: opacity 120ms ease;
  }

  .compiler-text.font-ready {
    opacity: 1;
  }

  .code-emphasis {
    text-decoration-line: underline;
    text-decoration-color: var(--chart-1);
    text-decoration-thickness: 0.14em;
    text-underline-offset: 0.18em;
  }

  .selection-outline {
    fill: none;
    stroke: #2563eb;
    stroke-width: 2;
    vector-effect: non-scaling-stroke;
    pointer-events: none;
    filter: drop-shadow(0 0 2px rgb(37 99 235 / 0.9));
  }

  .selection-box {
    fill: rgb(37 99 235 / 0.12);
    stroke: #2563eb;
    stroke-dasharray: 4 3;
    vector-effect: non-scaling-stroke;
    pointer-events: none;
  }
</style>
