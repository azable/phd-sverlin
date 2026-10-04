# sverlin component library

The component `Node` is already in scope in every component; use it without importing. Never write `import` statements, and never declare your own variables or components named `Node`. Build every part of a visualization from nodes; the page already has a theme, a canvas, and spacing between its top-level nodes.

Nodes say nothing about what a structure means: a node with items laid out as a row can show an array, a list of linked nodes, a queue, or anything else. Decide the meaning from the participant's request, and when they leave it open, express the open choice as a design value so the two presentations of a pair can show different interpretations.

## Node

A node is one of three things:

- a value: `<Node value={7} />` shows a primitive (a number, string, boolean, or `null`);
- content: `<Node>any text or markup</Node>` shows its children, for titles, explanations, captions, indices, and pointer names;
- a collection: `<Node items={values} layout="row" />` arranges child nodes. Without an `item` snippet, each primitive item becomes a value node (drawn by its type's renderer, if typed) and each array item a nested collection; to control each item, give `{#snippet item(value, index, type)} <Node {value} {type} … /> {/snippet}`, where `type` is the item's atomic type name or `undefined`.

Titles and annotations are nodes too: `<Node size="xlarge" weight="bold">Linear search</Node>` makes a title, and arranging a node's children with `layout` puts an index, caption, or pointer name beside or above a value: `<Node layout="column"><Node size="small" color="neutral">{index}</Node><Node {value} /></Node>`. Without `layout`, children flow as ordinary text.

### Props

`shape` is a preset of defaults, and every value it sets can be overridden by the matching prop:

- `shape`: `'box'` (a cell: small padding, medium radius, thin neutral stroke and fill, a minimum size, and bold, slightly larger text; the default for a value), `'card'` (a framed surface with medium padding), or `'plain'` (no frame or padding; the default for content and collections). A framed node with a layout draws its frame around the whole group.

Arrangement:

- `layout`: `'row'`, `'column'`, `'wrap'` (a row that wraps onto new lines), or `'grid'`; arranges a collection's items (default `'row'`) or, when set, a node's children.
- `gap`: space between arranged items (default `'medium'`).
- `align`: `'start'`, `'center'`, or `'end'`; how arranged items line up across the layout direction (rows default to `'start'`, columns to `'center'`).
- `columns`: the number of grid columns; defaults to a near-square grid.
- `nested`: the layout for items that are themselves arrays, such as the rows of a matrix (default `'row'`).

Frame and colour:

- `padding`: space inside the frame.
- `radius`: `'none'`, `'small'`, `'medium'`, or `'full'` (a circle for a short value, a pill for a long one).
- `strokeWidth`: `'none'`, `'thin'`, `'thick'`, or a number of pixels.
- `minSize`: `'none'`, `'small'`, `'medium'`, `'large'`, or a number of em; the smallest width and height.
- `fill` and `stroke`: background and stroke (border) colours, each a palette name (`'neutral'`, `'blue'`, `'green'`, `'amber'`, `'red'`, `'purple'`; a light shade as a fill and a strong shade as a stroke) or any CSS colour. `stroke="none"` (or `stroke={false}`) turns the stroke off whatever its width. What a colour means, such as the element being examined or one already checked, is up to you; make it consistent within a visualization, and draw it in the design block when the request leaves it open.
- `opacity`: from 0 to 1, such as 0.4 to fade a node.

Text:

- `color`: a palette name (`'neutral'` is muted grey) or any CSS colour.
- `font`: `'sans'`, `'serif'`, or `'mono'`; nested nodes inherit it unless they set their own.
- `size`: `'small'`, `'medium'`, `'large'`, `'xlarge'`, or a number of rem such as `1.2`, so it can come from `pick([...])` or `real(0.9, 1.4)`; nested nodes scale with it.
- `weight`: `'normal'` or `'bold'`.

Spacing values (`padding`, `gap`) are `'none'`, `'small'`, `'medium'`, `'large'`, or a number of em.

Types:

- `type`: an atomic type name, such as `'Int'`. If the view defines a renderer snippet for that type, or for a type it refines, the node is drawn by it (see the block guide's Type renderers); otherwise it draws its default box with the type's `unit` after the value.

Unspecified props vary by themselves: every presentation draws its own `radius`, `strokeWidth` (sometimes none at all), `padding`, and a pale fill and stroke tint for boxes and cards, plus the gap between arranged items and the page font, so two presentations of a pair look different even when no prop is set. Set a prop whenever its value matters, such as a colour that shows which element is current; a node's own props and its type's renderer always win over drawn defaults. To use the plain presets instead, put `const defaults = 'fixed';` in the design block, for example once the participant has settled on a look.

Every prop is a natural design dimension, especially `layout`, `gap`, `radius`, `font`, and `size`: draw values in the design block and pass them through, such as `layout={flow}`, or use them to decide which annotation nodes to show. Type renderers can use them too, so seeded presentations differ in presentation while showing the same steps. Prefer a few drawn values used consistently over ad hoc values on individual nodes.

Example, with domain, input, algorithm, design, and a script-free view:

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
  const intRadius = pick(['medium', 'full']);
  const flow = pick(['row', 'column']);
  const showIndices = chance(0.5);
  const textSize = real(0.9, 1.3);
</script>

{#snippet Int(value, node)}
  <Node radius={intRadius} {value} {...node} />
{/snippet}

<Node size="xlarge" weight="bold">Array walk</Node>
<Node items={values} layout={flow}>
  {#snippet item(value, index, type)}
    <Node layout="column">
      {#if showIndices}<Node size="small" color="neutral">{index}</Node>{/if}
      {@const colour = index === i ? 'amber' : index < i ? 'blue' : undefined}
      <Node {value} {type} fill={colour} stroke={colour} />
      {#if index === i}<Node size="small" color="neutral">i</Node>{/if}
    </Node>
  {/snippet}
</Node>
<Node shape="card" size={textSize}>
  {i < 0 ? 'Start at the left.' : i < values.length ? `Visiting index ${i}.` : 'Every cell visited.'}
</Node>
```

A matrix needs no snippet: `<Node items={grid} layout="column" nested="row" />` draws each inner array as a row of nodes.
