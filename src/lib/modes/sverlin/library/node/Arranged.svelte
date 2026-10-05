<!--
  Places a node's children by constraint layout (see arrange.ts): it measures each child as laid out
  inside, solves for their positions, places them, and takes the size that hugs them, drawing any
  links as lines or arrows. A nested arrangement that settles later asks its parent to lay out
  again, so sizes flow up and the final layout uses every child's final size.
-->
<script lang="ts">
  import { untrack, type Snippet } from 'svelte';

  import {
    arrangementParentContext,
    layoutMemoryContext,
    provideArrangementParent,
    seedContext,
    type LayoutRecord
  } from '../type-context';
  import { arrange, keyedRandom, type Anchor, type ArrangeEdge, type Template } from './arrange';
  import { measure, spacings } from './presets';
  import type { Align, Spacing } from './props';

  let {
    template,
    align,
    links = [],
    constraints = [],
    flow,
    gap,
    scope,
    children
  }: {
    template: Template;
    align?: Align;
    links?: readonly string[];
    constraints?: readonly string[];
    flow?: 'x' | 'y';
    gap: Spacing;
    /** Keys this arrangement's random starts, such as the node's id. */
    scope: string;
    children?: Snippet;
  } = $props();

  const seed = seedContext();
  const memory = layoutMemoryContext();
  // Node ids hold : and #, which an SVG fragment reference cannot.
  const markerId = $derived(`sv-arrow-${scope.replace(/[^\w-]/gu, '_')}`);
  const parent = arrangementParentContext();
  let host = $state<HTMLDivElement>();
  let result = $state<{ width: number; height: number; edges: ArrangeEdge[] }>();
  // Bumped when a nested arrangement settles, to lay out again with its new size.
  let revision = $state(0);
  let pending = false;
  provideArrangementParent({
    changed() {
      if (pending) return;
      pending = true;
      queueMicrotask(() => {
        pending = false;
        revision++;
      });
    }
  });

  // Lay out again whenever a child's size changes: a page loaded while hidden measures every child
  // as empty, and children only take their sizes once it is shown.
  $effect(() => {
    if (!host) return;
    let queued = false;
    const observer = new ResizeObserver(() => {
      if (queued) return;
      queued = true;
      queueMicrotask(() => {
        queued = false;
        revision++;
      });
    });
    for (const child of host.children) observer.observe(child);
    return () => observer.disconnect();
  });

  $effect(() => {
    void revision;
    if (!host) return;
    const elements = [...host.children].filter(
      (child): child is HTMLElement => child instanceof HTMLElement
    );
    const fontSize = parseFloat(getComputedStyle(host).fontSize) || 16;
    const space = parseFloat(measure(spacings, gap) ?? '0') * fontSize;
    const boxes = elements.map((element, index) => ({
      key: element.dataset.svKey ?? `#${index}`,
      // Layout sizes, unaffected by the frame's scale; offsetWidth rounds, so a pixel more keeps
      // a fractional width from wrapping once placed.
      width: element.offsetWidth + 1,
      height: element.offsetHeight + 1
    }));
    // Links attach to the node they name: a keyed node inside a child, or, for a keyed child that
    // holds one value cell among labels, that cell, so arrows meet the value and not its labels.
    const anchors: Record<string, Anchor> = {};
    elements.forEach((element, box) => {
      const frame = element.getBoundingClientRect();
      // Rects are scaled with the frame; the child's own size gives the scale back.
      const ratio = frame.width ? element.offsetWidth / frame.width : 1;
      const anchor = (inner: Element): Anchor => {
        const rect = inner.getBoundingClientRect();
        return {
          box,
          x: (rect.left - frame.left) * ratio,
          y: (rect.top - frame.top) * ratio,
          width: rect.width * ratio,
          height: rect.height * ratio
        };
      };
      for (const inner of element.querySelectorAll<HTMLElement>('[data-sv-key]'))
        if (inner.dataset.svKey) anchors[inner.dataset.svKey] = anchor(inner);
      const cells = [...element.querySelectorAll('[data-sv-node]')].filter((inner) =>
        inner.querySelector(':scope > .value')
      );
      if (element.dataset.svKey && cells.length === 1)
        anchors[element.dataset.svKey] = anchor(cells[0]);
    });
    // With layout memory (see LayoutMemory), recording solves each step from the one before, and
    // showing a step replays its record within the bounds of every step. A step whose children
    // differ from its record, such as after fonts change, is solved afresh from the record.
    let remembered = memory?.scopes.get(scope);
    if (memory && !remembered) memory.scopes.set(scope, (remembered = { steps: new Map() }));
    const record = memory ? remembered?.steps.get(memory.step) : undefined;
    const replay =
      !!memory &&
      !memory.recording &&
      !!record &&
      boxes.length === record.placements.length &&
      boxes.every(({ key, width, height }) => {
        const size = record.sizes[key];
        return size && Math.abs(size.width - width) < 1 && Math.abs(size.height - height) < 1;
      });
    const previous = memory ? remembered?.steps.get(memory.step - 1) : undefined;
    let laidOut: LayoutRecord;
    if (replay && record) laidOut = record;
    else {
      const solved = untrack(() =>
        arrange(boxes, {
          anchors,
          template,
          align,
          links,
          constraints,
          flow,
          gap: space,
          random: keyedRandom(seed, scope),
          starts: memory ? (record ?? previous)?.centres : undefined,
          // Children the same size as at the previous step stay where they were.
          still: previous
            ? new Set(
                boxes
                  .filter(({ key, width, height }) => {
                    const size = previous.sizes[key];
                    return (
                      size && Math.abs(size.width - width) < 1 && Math.abs(size.height - height) < 1
                    );
                  })
                  .map(({ key }) => key)
              )
            : undefined
        })
      );
      for (const problem of solved.problems) console.warn(`Node layout: ${problem}`);
      laidOut = {
        sizes: Object.fromEntries(boxes.map(({ key, width, height }) => [key, { width, height }])),
        centres: solved.centres,
        origin: solved.origin,
        placements: solved.placements,
        edges: solved.edges
      };
      if (memory?.recording && remembered && boxes.length) {
        remembered.steps.set(memory.step, laidOut);
        const right = solved.origin.x + solved.width;
        const bottom = solved.origin.y + solved.height;
        const bounds = remembered.bounds;
        remembered.bounds = bounds
          ? {
              left: Math.min(bounds.left, solved.origin.x),
              top: Math.min(bounds.top, solved.origin.y),
              right: Math.max(bounds.right, right),
              bottom: Math.max(bounds.bottom, bottom)
            }
          : { left: solved.origin.x, top: solved.origin.y, right, bottom };
      }
    }
    // Placed within the bounds of every step, so the arrangement keeps one size and what does not
    // move between steps stays exactly where it was.
    const own = {
      right: Math.max(0, ...boxes.map(({ width }, i) => (laidOut.placements[i]?.x ?? 0) + width)),
      bottom: Math.max(0, ...boxes.map(({ height }, i) => (laidOut.placements[i]?.y ?? 0) + height))
    };
    const bounds = remembered?.bounds;
    const dx = bounds ? laidOut.origin.x - bounds.left : 0;
    const dy = bounds ? laidOut.origin.y - bounds.top : 0;
    const width = bounds ? Math.max(bounds.right - bounds.left, own.right + dx) : own.right;
    const height = bounds ? Math.max(bounds.bottom - bounds.top, own.bottom + dy) : own.bottom;
    elements.forEach((element, index) => {
      element.style.left = `${(laidOut.placements[index]?.x ?? 0) + dx}px`;
      element.style.top = `${(laidOut.placements[index]?.y ?? 0) + dy}px`;
    });
    const shown = {
      width,
      height,
      edges: laidOut.edges.map(({ x1, y1, x2, y2, directed }) => ({
        x1: x1 + dx,
        y1: y1 + dy,
        x2: x2 + dx,
        y2: y2 + dy,
        directed
      }))
    };
    const resized =
      untrack(() => result?.width) !== shown.width ||
      untrack(() => result?.height) !== shown.height;
    result = shown;
    if (resized) parent?.changed();
  });
</script>

<div
  class="sv-arranged"
  style:width={result ? `${result.width}px` : undefined}
  style:height={result ? `${result.height}px` : undefined}
  style:visibility={result ? undefined : 'hidden'}
>
  {#if result?.edges.length}
    <svg class="links" width={result.width} height={result.height} aria-hidden="true">
      <defs>
        <marker
          id={markerId}
          viewBox="0 0 10 10"
          refX="10"
          refY="5"
          markerWidth="7"
          markerHeight="7"
          orient="auto-start-reverse"
        >
          <path d="M0,0 L10,5 L0,10 z" />
        </marker>
      </defs>
      {#each result.edges as edge, index (index)}
        <line
          x1={edge.x1}
          y1={edge.y1}
          x2={edge.x2}
          y2={edge.y2}
          marker-end={edge.directed ? `url(#${markerId})` : undefined}
        />
      {/each}
    </svg>
  {/if}
  <!-- Until laid out, children have room to take their natural width. -->
  <div class="placed" bind:this={host} style:width={result ? undefined : '10000px'}>
    {@render children?.()}
  </div>
</div>

<style>
  .sv-arranged {
    position: relative;
    flex: none;
  }
  .placed {
    position: absolute;
    inset: 0;
  }
  /* Every child is placed by the layout, at its natural size. */
  .placed > :global(*) {
    position: absolute;
  }
  .links {
    position: absolute;
    inset: 0;
    overflow: visible;
    pointer-events: none;
  }
  .links line {
    stroke: var(--sv-muted);
    stroke-width: 1.5;
  }
  .links path {
    fill: var(--sv-muted);
  }
</style>
