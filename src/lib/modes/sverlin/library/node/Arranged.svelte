<!--
  Places a node's children by constraint layout (see arrange.ts): it measures each child as laid out
  inside, solves for their positions, places them, and takes the size that hugs them, drawing any
  links as lines or arrows. A nested arrangement that settles later asks its parent to lay out
  again, so sizes flow up and the final layout uses every child's final size.
-->
<script lang="ts">
  import { untrack, type Snippet } from 'svelte';

  import { arrangementParentContext, provideArrangementParent, seedContext } from '../type-context';
  import { arrange, keyedRandom, type ArrangeResult, type Template } from './arrange';
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
  // Node ids hold : and #, which an SVG fragment reference cannot.
  const markerId = $derived(`sv-arrow-${scope.replace(/[^\w-]/gu, '_')}`);
  const parent = arrangementParentContext();
  let host = $state<HTMLDivElement>();
  let result = $state<ArrangeResult>();
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
    const laidOut = untrack(() =>
      arrange(boxes, {
        template,
        align,
        links,
        constraints,
        flow,
        gap: space,
        random: keyedRandom(seed, scope)
      })
    );
    for (const problem of laidOut.problems) console.warn(`Node layout: ${problem}`);
    elements.forEach((element, index) => {
      element.style.left = `${laidOut.placements[index].x}px`;
      element.style.top = `${laidOut.placements[index].y}px`;
    });
    const resized =
      untrack(() => result?.width) !== laidOut.width ||
      untrack(() => result?.height) !== laidOut.height;
    result = laidOut;
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
