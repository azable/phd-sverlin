# Input, algorithm, design, and view

A component describes its visualization in `<script lang="sverlin">` blocks, written in a restricted subset of JavaScript, followed by a script-free Svelte view. The algorithm block is required, even for a single step (`yield 'Start';`); the domain, input, and design blocks are optional.

1. `<script lang="sverlin" input>`: the fixed starting data. Declare the initial state with `const` or `let`, such as `const values = [Int(3), Int(8), Int(5)];` with `Int` defined in the domain block. Every presentation shares it.
2. `<script lang="sverlin">`: the algorithm. It starts from the input variables, may update them and declare more, and marks steps with `yield`. It runs once; every presentation shows the same algorithm.
3. `<script lang="sverlin" design>`: presentation choices drawn from each presentation's seed, so the two presentations in a comparison can differ. Each top-level `const` is a design value.

## View

The view is markup and an optional `<style>` only; it has no `<script>` of its own. Every top-level input and algorithm variable (as it was at the selected step), every design value, `step`, `seed`, and the library's `Node` are already in scope, so markup uses them directly: `{values[i]}`, `<Node items={values} layout={flow} />`.

Compute everything inline in markup. Svelte re-evaluates template expressions whenever the values they read change, so inline derivations stay correct. For a value used more than once or too long to read inline, use `{@const name = expression}` as the first child of the nearest component or block, such as directly inside a `<Node>`, `{#if}`, or `{#each}`:

```svelte
<Node layout="column" align="start">
  {@const current = i >= 0 && i < values.length ? values[i] : null}
  <Node items={values}>
    {#snippet item(value, index)}
      <Node
        {value}
        fill={index === i ? 'amber' : undefined}
        stroke={index === i ? 'amber' : undefined}
      />
    {/snippet}
  </Node>
  <Node>{current === null ? 'Not started' : `Checking ${current}`}</Node>
</Node>
```

Facts about the algorithm, such as which cells were checked, are often clearer recorded as algorithm variables; keep purely visual choices in the view and design block. Values must not reuse the library component names.

### Type renderers

A top-level snippet named after a domain type is that type's default renderer: every node showing a value of the type is drawn by it, including items drawn without an `item` snippet, `<Node type="Int" … />`, and nodes given an item's `type`. It takes the plain value and `node`, the props the caller set on that node (such as `fill` or `size`), so spreading `{...node}` after the renderer's own props lets the caller's settings win:

```svelte
{#snippet Int(value, node)}
  <Node shape={intShape} {value} {...node} />
{/snippet}

{#snippet Height(value, node)}
  <Node shape="card" {...node}>{value}<small> cm</small></Node>
{/snippet}
```

A type without a renderer uses the renderer of the nearest type it refines, and otherwise the default box with its `unit`. A renderer can use design values and step state, so a draw can change how every value of a type looks. The `Node` inside a renderer has no type, so it never calls the renderer again.

## Steps

- `yield 'label';` records a step: a copy of every top-level input and algorithm variable. Variables declared inside loops or blocks are not recorded; declare a loop index at the top level (`let i = -1;`) and write `for (i = 0; ...)` when the view needs it. A top-level variable not yet declared at a step is `null`.
- Labels must be unique across the whole algorithm, because they identify steps when presentations are compared. Inside loops, include what distinguishes the step, such as ``yield `Compare index ${i}`;``.
- `return;` stops the algorithm early.

## Atomic types

Give values meaning with atomic types. No types are predefined: define each one the request needs, including basic ones such as `Int`, in an optional `<script lang="sverlin" domain>` block, each as a top-level `const`:

- a primitive kind, `'integer'`, `'number'`, `'boolean'`, or `'text'`: `const Int = type('integer');`
- a refinement of a type defined earlier, with optional `unit`, `min`, and `max`: `const Height = type(Int, { unit: 'cm', min: 0 });`
- an enumeration of allowed text or number values: `const Suit = type(['♠', '♥', '♦', '♣']);`

Create typed values with a type's name in the input or algorithm block, such as `const values = [Int(3), Int(8), Int(5)];` and `const target = Int(8);`. Plain values remain allowed and stay untyped.

Typed values behave like their plain values in comparisons, conditions, `===`, `.indexOf`, `.includes`, template strings, and indexing, and they keep their type as the algorithm moves them between variables and arrays. Arithmetic keeps types too: `Int + Int` is an `Int`; a refined type combined with the type it refines or with a plain number keeps the refined type (`Height(150) + 5` is a `Height`); an integer type whose result is no longer whole, such as `Int(7) / Int(2)`, gives an untyped number. Combining or comparing unrelated types, such as a `Height` and a `Weight`, arithmetic on enumerations or boolean types, and leaving a type's `min` or `max` are errors. Type names cannot be used as variable names.

The view receives plain values; types only affect how nodes are drawn (see Type renderers under View).

## Design values

- Draws are `pick(['row', 'grid'])`, `int(3, 6)` (inclusive), `real(0.5, 1.5)`, and `chance(0.3)`, each only in the value of a top-level `const`, either the whole value or inside its object and array literals, such as `const layout = pick(['row', 'grid']);` or `const look = { cells: pick(['box', 'circle']), sizes: [int(1, 3)] };`. Other design constants may combine earlier ones.
- Use design values for styling, layout, wording, and library component props. The input and algorithm cannot see them, so steps never depend on the seed.
- The design value `defaults` controls drawn `Node` defaults: `'drawn'` (the default) gives every presentation its own seeded radius, stroke width (sometimes none), padding, tints, gap, and font wherever props leave them unset; `'fixed'` uses the plain presets.
- The design value `frame` shapes the page that holds the view's top-level nodes: a ratio such as `const frame = '4:3';`, or an object with any of `ratio` (`'16:9'`, the default, `'4:3'`, `'3:2'`, `'1:1'`, `'3:4'`, or `'9:16'`), `justify`, `align`, and `padding` (default `'large'`), such as `const frame = { justify: 'between' };`. Settings may be drawn, as in `{ justify: pick(['start', 'center']) }`; unset `justify` and `align` are drawn defaults.
- Design names must differ from input and algorithm names.

## The subset

- Allowed: numbers, strings, booleans, `null`, arrays, plain objects; `if`, `for`, `for (const x of array)`, `while`, `do`, `break`, `continue`; arithmetic, comparison with `===`/`!==`, `&&`, `||`, `??`, `? :`, template strings, `+=` and `++`; `Math.abs/ceil/floor/max/min/pow/round/sign/sqrt/trunc`, `Math.PI`; array `.length`, `.push`, `.pop`, `.shift`, `.unshift`, `.slice`, `.indexOf`, `.includes`, `.reverse`, `.join`.
- Not allowed: functions of any kind, `new`, classes, `this`, `==`, string methods, other globals, and the names `step` and `seed`. Write helper logic inline.
- Limits: 200 steps, 1,000,000 operations, 10,000 entries per array or object, and 10,000 characters per string.
