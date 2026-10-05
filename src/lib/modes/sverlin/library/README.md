# sverlin component library

The components `Node` and `Link` are already in scope in every component; use them without importing. Never write `import` statements, and never declare your own variables or components named `Node` or `Link`. Build every part of a visualization from nodes; the page already has a theme and a frame that arranges the view's top-level nodes in a column.

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

Page:

Every view sits in a page frame: a 16:9 canvas, wider than it is tall, laid out at a fixed logical size (1200 pixels wide) and scaled to fit, so every presentation renders identically whatever the pane size. Participants select nodes by clicking or dragging a box, to point at them in feedback; they scroll to zoom, drag with the middle button or with Space held to pan, and double-click empty space to reset, and the view is kept as they step through. Every node is selectable, so draw each thing a participant might want to point at, such as a cell, a pointer name, or a caption, as a node of its own. Props starting with `__` are reserved for the library. The frame arranges the view's top-level nodes in a column, or, varying by presentation, in a free layout; shape and place them with the design value `frame` (see the block guide), which can also fix the layout and relate top-level nodes by their `key`, such as `const frame = { justify: 'between' };` to put a title at the top and a note at the bottom. Prefer the 16:9 default unless the participant asks for another shape, and use its width: lay sequences out across it rather than down it. Leave the frame's `layout` unset so the top-level arrangement varies between presentations. Write the top-level nodes directly rather than wrapping the whole view in one node.

Arrangement:

- `layout`: `'row'`, `'column'`, `'wrap'` (a row that wraps onto new lines), `'grid'`, or `'free'` (placed by layout; see Free layout below); arranges a collection's items (default `'row'`) or, when set, a node's children.
- `gap`: space between arranged items (default `'medium'`).
- `align`: `'start'`, `'center'`, or `'end'`; how arranged items line up across the layout direction (rows default to `'start'`, columns to `'center'`).
- `justify`: `'start'`, `'center'`, `'end'`, `'between'`, `'around'`, or `'evenly'`; how arranged items spread along the layout direction (default `'start'`).
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

Unspecified props vary by themselves: every presentation draws its own `radius`, `strokeWidth` (sometimes none at all), `padding`, and a pale fill and stroke tint for boxes and cards, the page frame's `justify` and `align`, the gap between arranged items, and the page font, so two presentations of a pair look different even when no prop is set. Set a prop whenever its value matters, such as a colour that shows which element is current; a node's own props and its type's renderer always win over drawn defaults. To use the plain presets instead, put `const defaults = 'fixed';` in the design block, but only when the participant asks for a consistent or plainer look: liking a presentation is not a request to stop varying the others.

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

## Free layout, links, and relations

`layout="free"` places a node's children by layout instead of in a line or grid: use it for linked structures such as linked lists, trees, and graphs, joined by `<Link>` components (below), and for groups whose arrangement is open, with or without links. The children are kept clear of each other and gathered compactly, starting from the presentation's seed, so a pair shows two arrangements while every presentation draws the same way each time. A node hugs its children whatever its layout.

- `key`: a name for a child that its parent's links and relations refer to, such as `<Node key="a" value={3} />`. Every direct child is placed, keyed or not; put content that belongs together, such as a value and its index, in one child node. A link attaches to the node its key names: give the key to the value inside a child, or to a child holding one value among labels (such as a value with an index above and a pointer name below), and the arrow meets the value, not the labels.
- `constraints`: an array of relations between children, each `'a relation b'`: `above`, `below`, `leftOf`, and `rightOf` place a directly above, below, left of, or right of b, centred on it and one gap away, and `sameRow` and `sameColumn` centre a and b on one horizontal or vertical line in either order. They work in free layouts, and in rows and columns as long as they agree with the line. Use relations for what the picture must show, such as a pointer label above its node or a caption below the structure, and leave the rest to the layout.
- `flow`: in a free layout, `'x'` or `'y'` makes arrows point rightwards or downwards, as for a list or a tree; only forms that run that way are drawn.
- `form`: the shape a free layout gives the structure its links make. The structure is read from the arrows present at every step (a link that comes and goes is drawn on top of it but does not change it): a path such as a linked list, a cycle, a tree, or a layered graph (acyclic, with nodes that have several parents). Any structure can lie along its reading order (a path in link order, a tree depth first, a layered graph each node after its parents) as `'line'`, `'snake'` (rows read back and forth), `'wave'`, `'arc'`, or `'scatter'` (free positions that keep each node near the next). A cycle can also take `'ring'`; a tree `'tree-down'`, `'tree-right'`, `'radial'`, or `'indented'`; a layered graph `'layers-down'` or `'layers-right'`. Unset, every presentation draws a form that suits the space it has and stretches it to fill that space, and arrows curve round other nodes and labels.
- `curve`: `'straight'` or `'curved'`, whether this node's arrows prefer to run straight or to curve; unset, each link draws its own.
- `layoutSeed`: keeps this node's layout of its children the same in every presentation. Each arrangement draws its shape, spacing, and curves from a seed of its own, which selections report with the element; when the participant likes a layout ("keep this layout but …"), set `layoutSeed` on the node that arranges it to the reported seed, so that layout stays while everything else still varies. Pin `form` or `curve` only if the participant names them.

Leave `form` and `flow` unset, or draw them in the design block, and draw which relations to include, so presentations differ until the participant says what they prefer; fix them only when asked, such as for a list that must run left to right.

```svelte
<Node layout="free" constraints={['head above ' + first]} flow="x">
  {#each nodes as node (node.id)}
    <Node key={node.id} value={node.value} fill={node.id === current ? 'amber' : undefined} />
  {/each}
  {#each next as [from, to]}<Link {from} {to} />{/each}
  <Node key="head" size="small" color="neutral">head</Node>
  <Link from="head" to={first} />
</Node>
```

## Link

`<Link from="a" to="b" />` draws an arrow from the child keyed `a` to the child keyed `b`. Put links among the children of the node whose children they join, beside the nodes they connect; they take no space, and the node lays its children out with them (a node with links and no `layout` is laid out freely). Each link is a component of its own, so a participant can select it and refer to it in feedback, just as they can a node.

- `from` and `to`: the keys of the two nodes, or of nodes inside them (see `key` above).
- `directed`: `false` for a plain line instead of an arrow.
- `dashed`, `stroke` (a palette name or CSS colour), and `strokeWidth` (`'thin'`, `'thick'`, or pixels): how it is drawn.
- `label`: a short text shown at the middle of the link, such as `next` or `head`.
- `curve`: `'straight'` or `'curved'` for this link alone; unset, it draws its own, whatever its siblings do.
- `bend`: an exact curve, how far the link bows to one side as a fraction of its length (`0` straight, `0.3` a clear arc, negative the other side). A selected link reports the bend it drew; when the participant likes a curve, set `bend` on that `<Link>` to the reported value.

Links can come and go with the steps: wrap one in `{#if}` to show it only while it matters, such as the pointer being followed. Its place is kept across the animation, so nothing moves when it appears.

```svelte
<Node layout="free">
  {#each nodes as node, index (node.id)}
    <Node key={node.id} value={node.value} />
    {#if index > 0}<Link from={nodes[index - 1].id} to={node.id} label="next" />{/if}
  {/each}
  <Node key="head" size="small" color="neutral">head</Node>
  <Link from="head" to={nodes[0].id} dashed />
</Node>
```
