# Input, algorithm, design, and view

A component describes its visualization in `<script lang="sverlin">` blocks, written in a restricted subset of JavaScript, followed by a script-free Svelte view. The algorithm block is required, even for a single step (`yield 'Start';`); the input and design blocks are optional.

1. `<script lang="sverlin" input>`: the fixed starting data. Declare the initial state with `const` or `let`, such as `const values = [3, 8, 5, 2, 7];`. Every presentation shares it.
2. `<script lang="sverlin">`: the algorithm. It starts from the input variables, may update them and declare more, and marks steps with `yield`. It runs once; every presentation shows the same algorithm.
3. `<script lang="sverlin" design>`: presentation choices drawn from each presentation's seed, so the two presentations in a comparison can differ. Each top-level `const` is a design value.

## View

The view is markup and an optional `<style>` only; it has no `<script>` of its own. Every top-level input and algorithm variable (as it was at the selected step), every design value, `step`, `seed`, and the library components are already in scope, so markup uses them directly: `{values[i]}`, `<Node items={values} layout={flow} />`.

Compute everything inline in markup. Svelte re-evaluates template expressions whenever the values they read change, so inline derivations stay correct. For a value used more than once or too long to read inline, use `{@const name = expression}` as the first child of the nearest component or block, such as directly inside `<Stage>`, `{#if}`, or `{#each}`:

```svelte
<Stage title="Linear search">
  {@const current = i >= 0 && i < values.length ? values[i] : null}
  <Node items={values}>
    {#snippet item(value, index)}
      <Node {value} role={index === i ? 'active' : index < i ? 'visited' : 'idle'} />
    {/snippet}
  </Node>
  <Node>{current === null ? 'Not started' : `Checking ${current}`}</Node>
</Stage>
```

Facts about the algorithm, such as which cells were checked, are often clearer recorded as algorithm variables; keep purely visual choices in the view and design block. Values must not reuse the library component names.

## Steps

- `yield 'label';` records a step: a copy of every top-level input and algorithm variable. Variables declared inside loops or blocks are not recorded; declare a loop index at the top level (`let i = -1;`) and write `for (i = 0; ...)` when the view needs it. A top-level variable not yet declared at a step is `null`.
- Labels must be unique across the whole algorithm, because they identify steps when presentations are compared. Inside loops, include what distinguishes the step, such as ``yield `Compare index ${i}`;``.
- `return;` stops the algorithm early.

## Design values

- Draws are `pick(['row', 'grid'])`, `int(3, 6)` (inclusive), `real(0.5, 1.5)`, and `chance(0.3)`, each only as the whole value of a top-level `const`, such as `const layout = pick(['row', 'grid']);`. Other design constants may combine earlier ones.
- Use design values for styling, layout, wording, and library component props. The input and algorithm cannot see them, so steps never depend on the seed.
- Design names must differ from input and algorithm names.

## The subset

- Allowed: numbers, strings, booleans, `null`, arrays, plain objects; `if`, `for`, `for (const x of array)`, `while`, `do`, `break`, `continue`; arithmetic, comparison with `===`/`!==`, `&&`, `||`, `??`, `? :`, template strings, `+=` and `++`; `Math.abs/ceil/floor/max/min/pow/round/sign/sqrt/trunc`, `Math.PI`; array `.length`, `.push`, `.pop`, `.shift`, `.unshift`, `.slice`, `.indexOf`, `.includes`, `.reverse`, `.join`.
- Not allowed: functions of any kind, `new`, classes, `this`, `==`, string methods, other globals, and the names `step` and `seed`. Write helper logic inline.
- Limits: 200 steps, 1,000,000 operations, 10,000 entries per array or object, and 10,000 characters per string.
