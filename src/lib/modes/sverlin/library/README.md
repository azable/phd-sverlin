# sverlin component library

The components `Stage` and `Node` are already in scope in every component; use them without importing. Never write `import` statements, and never declare your own variables or components with these reserved names. Prefer these components over hand-written markup and styles; they keep visualizations consistent across revisions.

The components say nothing about what a structure means: a `Node` with items laid out as a row can show an array, a list of linked nodes, a queue, or anything else. Decide the meaning from the participant's request, and when they leave it open, express the open choice as a design value so the two presentations of a pair can show different interpretations.

- `<Stage title subtitle?>`: the page frame and theme. Wrap the whole visualization in exactly one Stage.
- `<Node …>`: every other part of a visualization. A node is one of three things:
  - a value: `<Node value={7} />` shows a primitive (a number, string, boolean, or `null`);
  - content: `<Node>any text or markup</Node>` shows its children, for explanations, captions, indices, and pointer names;
  - a collection: `<Node items={values} layout="row" />` arranges child nodes. Without an `item` snippet, each primitive item becomes a value node (drawn by its type's renderer, if typed) and each array item a nested collection; to control each item, give `{#snippet item(value, index, type)} <Node {value} {type} … /> {/snippet}`, where `type` is the item's atomic type name or `undefined`.
- Annotations are nodes too. Arrange a node's children with `layout` to put an index, caption, or pointer name beside or above a value:
  `<Node layout="column"><Node size="small">{index}</Node><Node {value} /><Node size="small">i</Node></Node>`. Without `layout`, children flow as ordinary text.
- Props for every node:
  - `layout`: `'row'`, `'column'`, `'wrap'` (a row that wraps onto new lines), or `'grid'`; arranges a collection's items (default `'row'`) or, when set, a node's children.
  - `columns`: the number of grid columns; defaults to a near-square grid.
  - `nested`: the layout for items that are themselves arrays, such as the rows of a matrix (default `'row'`).
  - `shape`: `'box'` (a cell; the default for a value), `'plain'` (no frame; the default for content and collections), `'card'` (a framed surface), or `'circle'`. A framed node with a layout draws its frame around the whole group.
  - `fill` and `stroke`: background and border colours, each a palette name (`'neutral'`, `'blue'`, `'green'`, `'amber'`, `'red'`, `'purple'`; a light shade as a fill and a strong shade as a stroke) or any CSS colour. What a colour means, such as the element being examined or one already checked, is up to you; make it consistent within a visualization, and draw it in the design block when the request leaves it open.
  - `opacity`: from 0 to 1, such as 0.4 to fade a node.
  - `font`: `'sans'`, `'serif'`, or `'mono'`; nested nodes inherit it unless they set their own.
  - `size`: `'small'`, `'medium'`, `'large'`, `'xlarge'`, or a number of rem such as `1.2`, so it can come from `pick([...])` or `real(0.9, 1.4)`; nested nodes scale with it.
  - `type`: an atomic type name, such as `'Int'`. If the view defines a renderer snippet for that type, or for a type it refines, the node is drawn by it (see the block guide's Type renderers); otherwise it draws its default box with the type's `unit` after the value.
  - Every prop is a natural design dimension, especially `layout`, `shape`, `font`, and `size`.

Component props are a natural place for design values: draw them in the design block and pass them through, such as `layout={flow}`, or use them to decide which annotation nodes to show, and type renderers can use them too, so seeded presentations differ in presentation while showing the same steps.

Example, with input, algorithm, design, and a script-free view:

```svelte
<script lang="sverlin" domain>
  const Int = type('integer');
</script>

<script lang="sverlin" input>
  const values = [Int(3), Int(8), Int(5)];
</script>

<script lang="sverlin">
  let i = -1;
  yield 'Start';
  for (i = 0; i < values.length; i++) {
    yield `Visit index ${i}`;
  }
  yield 'Done';
</script>

<script lang="sverlin" design>
  const intShape = pick(['box', 'circle']);
  const flow = pick(['row', 'column']);
  const showIndices = chance(0.5);
  const textSize = real(0.9, 1.3);
</script>

{#snippet Int(value, node)}
  <Node shape={intShape} {value} {...node} />
{/snippet}

<Stage title="Array walk">
  <Node items={values} layout={flow}>
    {#snippet item(value, index, type)}
      <Node layout="column">
        {#if showIndices}<Node size="small">{index}</Node>{/if}
        {@const colour = index === i ? 'amber' : index < i ? 'blue' : undefined}
        <Node {value} {type} fill={colour} stroke={colour} />
        {#if index === i}<Node size="small">i</Node>{/if}
      </Node>
    {/snippet}
  </Node>
  <Node shape="card" size={textSize}>
    {i < 0 ? 'Start at the left.' : i < values.length ? `Visiting index ${i}.` : 'Every cell visited.'}
  </Node>
</Stage>
```

A matrix needs no snippet: `<Node items={grid} layout="column" nested="row" />` draws each inner array as a row of nodes.
