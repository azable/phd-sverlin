<!--
  One node of a visualization: a primitive `value`, children content, or, with `items`, a
  collection. A layout arranges a collection's items, and arranges children too when one is set,
  so annotations such as an index or a pointer are simply nodes beside a value. A shape is only a
  preset of defaults; every visual property is also a prop of its own.
-->
<script lang="ts" generics="T">
  import { untrack, type Snippet } from 'svelte';

  import Node from './Node.svelte';
  import { paletteColor } from './palette';
  import { markRendering, rendererFor, typeContext, type NodeProps } from './type-context';
  import type {
    Align,
    Border,
    Layout,
    MinSize,
    NodeColor,
    NodeFont,
    NodeShape,
    NodeSize,
    Primitive,
    Radius,
    Spacing,
    Weight
  } from './types';

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
    color,
    font,
    size,
    weight,
    padding,
    gap,
    align,
    radius,
    border,
    minSize,
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
    /** A preset: 'box' for a value, 'plain' for content and collections, unless given. */
    shape?: NodeShape;
    /** Background colour: a palette name such as 'amber' (a light shade), or any CSS colour. */
    fill?: NodeColor;
    /** Border colour: a palette name (a strong shade), or any CSS colour. */
    stroke?: NodeColor;
    /** From 0 (invisible) to 1 (default). */
    opacity?: number;
    /** Text colour: a palette name ('neutral' is muted), or any CSS colour. */
    color?: NodeColor;
    /** Font family; nested nodes inherit it unless they set their own. */
    font?: NodeFont;
    /** A named size, or a size in rem such as 1.2; nested nodes inherit it. */
    size?: NodeSize | number;
    weight?: Weight;
    /** Space inside the frame: a named spacing, or a number of em. */
    padding?: Spacing;
    /** Space between arranged items or children. */
    gap?: Spacing;
    /** How arranged items line up across the layout direction. */
    align?: Align;
    radius?: Radius;
    border?: Border;
    /** The smallest width and height. */
    minSize?: MinSize;
    children?: Snippet;
  } = $props();

  type Preset = {
    padding?: Spacing;
    radius?: Radius;
    border?: Border;
    minSize?: MinSize;
    fill?: NodeColor;
    stroke?: NodeColor;
    weight?: Weight;
    /** Text size relative to the enclosing node, in em. */
    scale?: number;
  };
  const presets: Record<NodeShape, Preset> = {
    box: {
      padding: 'small',
      radius: 'medium',
      border: 'thin',
      minSize: 'medium',
      fill: 'neutral',
      stroke: 'neutral',
      weight: 'bold',
      scale: 1.25
    },
    card: {
      padding: 'medium',
      radius: 'medium',
      border: 'thin',
      fill: 'neutral',
      stroke: 'neutral'
    },
    plain: { padding: 'none', radius: 'small', border: 'none' }
  };
  const spacings = { none: '0', small: '0.4em', medium: '0.75em', large: '1.25em' };
  const radii = { none: '0', small: '0.25rem', medium: 'var(--sv-radius)', full: '9999px' };
  const borders = { none: '0', thin: '2px', thick: '4px' };
  const minSizes = { none: '0', small: '2em', medium: '2.8em', large: '4em' };
  const namedSizes: Record<NodeSize, number> = { small: 0.85, medium: 1, large: 1.25, xlarge: 1.6 };
  const alignments = { start: 'flex-start', center: 'center', end: 'flex-end' };

  /** A named scale value, or a number in em. */
  const measure = (scale: Record<string, string>, setting: string | number | undefined) =>
    setting === undefined
      ? undefined
      : typeof setting === 'number'
        ? Number.isFinite(setting)
          ? `${Math.min(Math.max(setting, 0), 20)}em`
          : undefined
        : scale[setting];

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
      Object.entries({
        shape,
        fill,
        stroke,
        opacity,
        color,
        font,
        size,
        weight,
        padding,
        radius,
        border,
        minSize
      }).filter(([, setting]) => setting !== undefined)
    ) as NodeProps
  );
  const unit = $derived(type ? types?.unit(type) : undefined);

  const collection = $derived(items !== undefined);
  const resolvedShape = $derived(shape ?? (collection || children ? 'plain' : 'box'));
  const arrangement = $derived(layout ?? (collection ? 'row' : undefined));
  // A framed group keeps the frame but not a cell's text size, weight, or minimum size.
  const preset = $derived(
    arrangement
      ? { ...presets[resolvedShape], scale: undefined, weight: undefined, minSize: undefined }
      : presets[resolvedShape]
  );
  const fontSize = $derived(
    typeof size === 'number' && Number.isFinite(size)
      ? `${Math.min(Math.max(size, 0.5), 4)}rem`
      : size !== undefined
        ? `${namedSizes[size as NodeSize] ?? 1}rem`
        : preset.scale
          ? `${preset.scale}em`
          : undefined
  );
  const resolvedWeight = $derived(weight ?? preset.weight);
  const gridColumns = $derived(
    columns ?? Math.max(1, Math.ceil(Math.sqrt(items?.length ?? (arrangement === 'grid' ? 4 : 1))))
  );
  const alignment = $derived(alignments[align ?? (arrangement === 'column' ? 'center' : 'start')]);
</script>

{#if rendered}
  {@render rendered.snippet(value ?? null, callerProps)}
{:else}
  <div
    class="sv-node {font ?? ''}"
    class:cell={!arrangement && resolvedShape === 'box'}
    style:font-size={fontSize}
    style:font-weight={resolvedWeight === undefined
      ? undefined
      : resolvedWeight === 'bold'
        ? 700
        : 400}
    style:color={paletteColor(color, 'text')}
    style:background-color={paletteColor(fill ?? preset.fill, 'fill')}
    style:border-color={paletteColor(stroke ?? preset.stroke, 'stroke')}
    style:border-width={borders[border ?? preset.border ?? 'none']}
    style:border-radius={radii[radius ?? preset.radius ?? 'none']}
    style:padding={measure(spacings, padding ?? preset.padding)}
    style:min-width={measure(minSizes, minSize ?? preset.minSize)}
    style:min-height={measure(minSizes, minSize ?? preset.minSize)}
    style:opacity={typeof opacity === 'number' && Number.isFinite(opacity)
      ? Math.min(Math.max(opacity, 0), 1)
      : undefined}
  >
    {#if arrangement}
      <div
        class="items {arrangement}"
        style:--sv-columns={gridColumns}
        style:gap={measure(spacings, gap ?? 'medium')}
        style:align-items={alignment}
      >
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
    box-sizing: border-box;
    border-style: solid;
    line-height: 1.5;
  }
  .cell {
    display: grid;
    place-items: center;
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
