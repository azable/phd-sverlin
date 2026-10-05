<!--
  A link between two children of the node it sits in, drawn as a line or an arrow between the nodes
  its keys name. It takes no space itself: the arranging node reads it, lays its children out with
  it, and draws it over them. Each link has an id from its place in the source, like a node, so a
  participant can select it and refer to it in feedback.
-->
<script lang="ts">
  import { untrack } from 'svelte';

  import { nodeIdsContext } from '../type-context';
  import type { NodeColor, StrokeWidth } from './props';

  let {
    from,
    to,
    directed = true,
    dashed = false,
    label,
    stroke,
    strokeWidth,
    curve,
    __ref
  }: {
    /** The key of the node the link starts from. */
    from: string;
    /** The key of the node the link goes to. */
    to: string;
    /** An arrow (true, the default) or a plain line. */
    directed?: boolean;
    dashed?: boolean;
    /** Text shown along the link, at its middle. */
    label?: string;
    /** The link's colour: a palette name or any CSS colour; unset, a muted grey. */
    stroke?: NodeColor;
    /** 'thin', 'thick', or a number of pixels; unset, a fine line. */
    strokeWidth?: StrokeWidth;
    /** Whether this link runs straight or curves, whatever its arrangement prefers. */
    curve?: 'straight' | 'curved';
    /** Internal: the source position of this link's tag, added by the compiler. */
    __ref?: string;
  } = $props();

  const nodeIds = nodeIdsContext();
  const id = untrack(() => (__ref ? nodeIds?.claim(__ref) : undefined));
</script>

<span
  class="sv-link"
  hidden
  data-sv-link={id ?? ''}
  data-from={from}
  data-to={to}
  data-directed={directed ? 'true' : 'false'}
  data-dashed={dashed ? 'true' : undefined}
  data-label={label}
  data-stroke={stroke}
  data-stroke-width={strokeWidth}
  data-curve={curve}
></span>

<style>
  .sv-link {
    display: none;
  }
</style>
