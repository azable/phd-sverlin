# sverlin component library

The components `Stage` and `Node` are already in scope in every component; use them without importing. Never write `import` statements, and never declare your own variables or components with these reserved names. Prefer these components over hand-written markup and styles; they keep visualizations consistent across revisions.

The components say nothing about what a structure means: a `Node` with items laid out as a row can show an array, a list of linked nodes, a queue, or anything else. Decide the meaning from the participant's request, and when they leave it open, express the open choice as a design value so the two presentations of a pair can show different interpretations.

- `<Stage title subtitle?>`: the page frame and theme. Wrap the whole visualization in exactly one Stage.
- `<Node …>`: every other part of a visualization. A node is one of three things:
  - a value: `<Node value={7} />` shows a primitive (a number, string, boolean, or `null`);
  - content: `<Node>any text or markup</Node>` shows its children, for explanations, captions, and labels;
  - a collection: `<Node items={values} layout="row" />` arranges child nodes. Without an `item` snippet, each primitive item becomes a value node and each array item a nested collection; to control each item, give `{#snippet item(value, index)} <Node {value} … /> {/snippet}`.
- Props for nodes with `items`:
  - `items`: an array of values.
  - `layout`: `'row'` (default), `'column'`, `'wrap'` (a row that wraps onto new lines), or `'grid'`.
  - `columns`: the number of grid columns; defaults to a near-square grid.
  - `nested`: the layout for items that are themselves arrays, such as the rows of a matrix (default `'row'`).
- Props for every node, including collections:
  - `shape`: `'box'` (a cell; the default for a value), `'plain'` (no frame; the default for content and collections), `'card'` (a framed surface), or `'circle'`. A framed collection draws its frame around the whole group.
  - `role`: `'idle'` (default), `'active'` (being examined now), `'visited'` (already examined), `'found'`, or `'muted'`.
  - `label`: small text, shown in the corner of a value or content node (such as an index) and as a caption above a collection.
  - `marker`: text attached to the node, such as a pointer name; it hangs below the node, or sits beside it inside a column.
  - `font`: `'sans'`, `'serif'`, or `'mono'`; nested nodes inherit it unless they set their own.
  - `size`: `'small'`, `'medium'`, `'large'`, `'xlarge'`, or a number of rem such as `1.2`, so it can come from `pick([...])` or `real(0.9, 1.4)`; nested nodes scale with it.
  - Every prop is a natural design dimension, especially `layout`, `shape`, `font`, and `size`.

Component props are a natural place for design values: draw them in the design block and pass them through, such as `layout={flow}`, `shape={shape}`, or `label={showIndices ? index : undefined}`, so seeded presentations differ in presentation while showing the same steps.

Example, with input, algorithm, design, and a script-free view:

```svelte
<script lang="sverlin" input>
  const values = [3, 8, 5];
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
  const flow = pick(['row', 'column']);
  const showIndices = chance(0.5);
  const textSize = real(0.9, 1.3);
</script>

<Stage title="Array walk">
  <Node items={values} layout={flow}>
    {#snippet item(value, index)}
      <Node
        {value}
        label={showIndices ? index : undefined}
        marker={index === i ? 'i' : undefined}
        role={index < i ? 'visited' : index === i ? 'active' : 'idle'}
      />
    {/snippet}
  </Node>
  <Node shape="card" size={textSize}>
    {i < 0 ? 'Start at the left.' : i < values.length ? `Visiting index ${i}.` : 'Every cell visited.'}
  </Node>
</Stage>
```

A matrix needs no snippet: `<Node items={grid} layout="column" nested="row" />` draws each inner array as a row of nodes.
