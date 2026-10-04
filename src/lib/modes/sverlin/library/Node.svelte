<!--
  One node of a visualization: a primitive `value`, children content, or, with `items`, a
  collection. A layout arranges a collection's items, and arranges children too when one is set,
  so annotations such as an index or a pointer are simply nodes beside a value. Every visual
  difference is a prop.
-->
<script lang="ts" generics="T">
  import { untrack, type Snippet } from 'svelte';

  import Node from './Node.svelte';
  import { paletteColor } from './palette';
  import { markRendering, rendererFor, typeContext, type NodeProps } from './type-context';
  import type { Layout, NodeColor, NodeFont, NodeShape, NodeSize, Primitive } from './types';

  let {
    value,
    items,
    layout,
    columns,
    nested = 'row',
    item,
    type,
    shape,
    fill,
    stroke,
    opacity,
    font,
    size,
    children
  }: {
    /** A primitive to display, when the node has neither items nor children. */
    value?: Primitive;
    /** Child values, which make this node a collection. */
    items?: readonly T[];
    /** How items (default 'row') or, when set, children are arranged. */
    layout?: Layout;
    /** Grid columns; defaults to a near-square grid. */
    columns?: number;
    /** Layout for items that are themselves arrays, when no item snippet is given. */
    nested?: Layout;
    /** Renders each item of a collection from its value, index, and atomic type name, if typed. */
    item?: Snippet<[T, number, string | undefined]>;
    /** An atomic type name, such as 'Int'; its renderer snippet, if the view defines one, draws the value. */
    type?: string;
    /** Defaults to 'box' for a value and 'plain' for a collection or children. */
    shape?: NodeShape;
    /** Background colour: a palette name such as 'amber' (a light shade), or any CSS colour. */
    fill?: NodeColor;
    /** Border colour: a palette name (a strong shade), or any CSS colour. */
    stroke?: NodeColor;
    /** From 0 (invisible) to 1 (default). */
    opacity?: number;
    /** Font family; nested nodes inherit it unless they set their own. */
    font?: NodeFont;
    /** A named size, or a size in rem such as 1.2; nested nodes inherit it. */
    size?: NodeSize | number;
    children?: Snippet;
  } = $props();

  const types = typeContext();
  // A typed value node draws through its type's renderer, if the view defines one. Resolved once:
  // each step mounts afresh, and the renderer is marked so nodes inside it never call it again.
  const rendered = untrack(() =>
    type !== undefined && items === undefined && children === undefined
      ? rendererFor(type)
      : undefined
  );
  if (rendered) markRendering(rendered.name);
  // Only the props the caller set, so a renderer can spread them over its own defaults.
  const callerProps = $derived(
    Object.fromEntries(
      Object.entries({ fill, stroke, opacity, shape, font, size }).filter(
        ([, setting]) => setting !== undefined
      )
    ) as NodeProps
  );
  const unit = $derived(type ? types?.unit(type) : undefined);

  const namedSizes: Record<NodeSize, number> = { small: 0.85, medium: 1, large: 1.25, xlarge: 1.6 };
  const collection = $derived(items !== undefined);
  const resolvedShape = $derived(shape ?? (collection || children ? 'plain' : 'box'));
  const arrangement = $derived(layout ?? (collection ? 'row' : undefined));
  const rem = $derived(
    typeof size === 'number' && Number.isFinite(size)
      ? Math.min(Math.max(size, 0.5), 4)
      : size === undefined
        ? undefined
        : (namedSizes[size as NodeSize] ?? 1)
  );
  const gridColumns = $derived(
    columns ?? Math.max(1, Math.ceil(Math.sqrt(items?.length ?? (arrangement === 'grid' ? 4 : 1))))
  );
</script>

{#if rendered}
  {@render rendered.snippet(value ?? null, callerProps)}
{:else}
  <div
    class="sv-node {resolvedShape} {font ?? ''}"
    class:arranged={arrangement !== undefined}
    style:font-size={rem === undefined ? undefined : `${rem}rem`}
    style:background-color={paletteColor(fill, 'fill')}
    style:border-color={paletteColor(stroke, 'stroke')}
    style:opacity={typeof opacity === 'number' && Number.isFinite(opacity)
      ? Math.min(Math.max(opacity, 0), 1)
      : undefined}
  >
    {#if arrangement}
      <div class="items {arrangement}" style:--sv-columns={gridColumns}>
        {#if collection}
          {#each items ?? [] as child, index (index)}
            {#if item}
              {@render item(child, index, types?.itemType(items, index))}
            {:else if Array.isArray(child)}
              <Node items={child} layout={nested} />
            {:else}
              <Node
                value={child !== null && typeof child === 'object'
                  ? JSON.stringify(child)
                  : (child as Primitive)}
                type={types?.itemType(items, index)}
              />
            {/if}
          {/each}
        {:else}
          {@render children?.()}
        {/if}
      </div>
    {:else if children}
      {@render children()}
    {:else}
      <span class="value"
        >{value === null || value === undefined ? '∅' : String(value)}{#if unit}<span class="unit"
            >{unit}</span
          >{/if}</span
      >
    {/if}
  </div>
{/if}

<style>
  .sv-node {
    border: 2px solid transparent;
    line-height: 1.5;
  }
  /* Sized in em so a size set on any enclosing node scales its boxes too. */
  .box,
  .circle {
    display: grid;
    place-items: center;
    min-width: 2.8em;
    min-height: 2.8em;
    padding: 0 0.5em;
    border-color: var(--sv-line);
    border-radius: var(--sv-radius);
    background: var(--sv-surface);
    font-size: 1.25em;
    font-weight: 700;
  }
  .circle {
    aspect-ratio: 1;
    padding: 0;
    border-radius: 50%;
  }
  .card {
    padding: 0.75rem 1rem;
    border-color: var(--sv-line);
    border-radius: var(--sv-radius);
    background: var(--sv-surface);
  }
  .plain {
    padding: 0.1rem 0.25rem;
    border-radius: 0.25rem;
  }
  .arranged.box,
  .arranged.circle {
    padding: 0.6rem;
    font-size: inherit;
    font-weight: inherit;
  }
  .arranged.plain {
    padding: 0;
  }
  .sans {
    font-family: system-ui, sans-serif;
  }
  .serif {
    font-family: ui-serif, Georgia, 'Times New Roman', serif;
  }
  .mono {
    font-family: ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace;
  }
  .value {
    white-space: nowrap;
  }
  .unit {
    margin-left: 0.2em;
    color: var(--sv-muted);
    font-size: 0.6em;
    font-weight: 400;
  }
  .items {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }
  .row {
    flex-direction: row;
    align-items: flex-start;
  }
  .column {
    flex-direction: column;
  }
  .wrap {
    flex-flow: row wrap;
    align-items: flex-start;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(var(--sv-columns), max-content);
  }
</style>
