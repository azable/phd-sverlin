<!--
  One node of a visualization. With `items` it is a collection whose children are arranged by
  `layout` (nested arrays become nested collections); otherwise it shows a primitive `value` or
  any children content. Every visual difference is a prop.
-->
<script lang="ts" generics="T">
  import type { Snippet } from 'svelte';

  import Node from './Node.svelte';
  import { currentLayout, provideLayout } from './layout-context';
  import type { Layout, NodeFont, NodeRole, NodeShape, NodeSize, Primitive } from './types';

  let {
    value,
    items,
    layout = 'row',
    columns,
    nested = 'row',
    item,
    shape,
    role = 'idle',
    label,
    marker,
    font,
    size,
    children
  }: {
    /** A primitive to display, when the node has neither items nor children. */
    value?: Primitive;
    /** Child values, which make this node a collection. */
    items?: readonly T[];
    /** How a collection arranges its children. */
    layout?: Layout;
    /** Grid columns; defaults to a near-square grid. */
    columns?: number;
    /** Layout for items that are themselves arrays, when no item snippet is given. */
    nested?: Layout;
    /** Renders each item of a collection from its value and index. */
    item?: Snippet<[T, number]>;
    /** Defaults to 'box' for a value and 'plain' for a collection or children. */
    shape?: NodeShape;
    role?: NodeRole;
    /** Small text: a corner label such as an index, or a collection's caption. */
    label?: string | number;
    /** Text attached to the node, such as a pointer name. */
    marker?: string;
    /** Font family; nested nodes inherit it unless they set their own. */
    font?: NodeFont;
    /** A named size, or a size in rem such as 1.2; nested nodes inherit it. */
    size?: NodeSize | number;
    children?: Snippet;
  } = $props();

  // Read the parent's layout before providing this collection's own to its children.
  const parentLayout = currentLayout();
  provideLayout(() => layout);

  const namedSizes: Record<NodeSize, number> = { small: 0.85, medium: 1, large: 1.25, xlarge: 1.6 };
  const collection = $derived(items !== undefined);
  const resolvedShape = $derived(shape ?? (collection || children ? 'plain' : 'box'));
  const rem = $derived(
    typeof size === 'number' && Number.isFinite(size)
      ? Math.min(Math.max(size, 0.5), 4)
      : size === undefined
        ? undefined
        : (namedSizes[size as NodeSize] ?? 1)
  );
  const gridColumns = $derived(columns ?? Math.max(1, Math.ceil(Math.sqrt(items?.length ?? 0))));
  const hasLabel = $derived(label !== undefined && label !== null && label !== '');
</script>

<div class="sv-node" class:beside={parentLayout === 'column'}>
  <div
    class="content {resolvedShape} {role} {font ?? ''}"
    class:collection
    style:font-size={rem === undefined ? undefined : `${rem}rem`}
  >
    {#if collection}
      {#if hasLabel}<span class="caption">{label}</span>{/if}
      <div class="items {layout}" style:--sv-columns={gridColumns}>
        {#each items ?? [] as child, index (index)}
          {#if item}
            {@render item(child, index)}
          {:else if Array.isArray(child)}
            <Node items={child} layout={nested} />
          {:else}
            <Node
              value={child !== null && typeof child === 'object'
                ? JSON.stringify(child)
                : (child as Primitive)}
            />
          {/if}
        {/each}
      </div>
    {:else}
      {#if hasLabel}<span class="label">{label}</span>{/if}
      {#if children}
        {@render children()}
      {:else}
        <span class="value">{value === null || value === undefined ? '∅' : String(value)}</span>
      {/if}
    {/if}
  </div>
  {#if marker}<span class="marker">{marker}</span>{/if}
</div>

<style>
  .sv-node {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.3rem;
  }
  .sv-node.beside {
    flex-direction: row;
  }
  .content {
    position: relative;
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
  .collection.box,
  .collection.circle {
    padding: 0.6rem;
    font-size: inherit;
    font-weight: inherit;
  }
  .collection.plain {
    padding: 0;
  }
  .active {
    border-color: var(--sv-active-line);
    background: var(--sv-active);
  }
  .visited {
    border-color: var(--sv-visited-line);
    background: var(--sv-visited);
  }
  .found {
    border-color: var(--sv-found-line);
    background: var(--sv-found);
  }
  .muted {
    opacity: 0.4;
  }
  .plain.active,
  .plain.visited,
  .plain.found {
    border-color: transparent;
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
  .label {
    position: absolute;
    top: 0.2rem;
    left: 0.35rem;
    color: var(--sv-muted);
    font-size: 0.65rem;
    font-weight: 400;
  }
  .caption {
    display: block;
    margin-bottom: 0.75rem;
    color: var(--sv-muted);
    font-size: 0.875rem;
    font-weight: 400;
  }
  .value {
    white-space: nowrap;
  }
  .marker {
    color: var(--sv-muted);
    font-size: 0.7rem;
    font-weight: 700;
    white-space: nowrap;
  }
  .items {
    display: flex;
    align-items: flex-start;
    gap: 0.75rem;
  }
  .row {
    flex-direction: row;
  }
  .column {
    flex-direction: column;
  }
  .wrap {
    flex-flow: row wrap;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(var(--sv-columns), max-content);
  }
</style>
