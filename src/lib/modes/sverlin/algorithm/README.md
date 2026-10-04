# Input, design, and algorithm blocks

A component describes its visualization in `<script lang="sverlin">` blocks, written in a restricted subset of JavaScript, followed by an ordinary Svelte view. The algorithm block is required, even for a single step (`yield 'Start';`); the input and design blocks are optional.

1. `<script lang="sverlin" input>`: the fixed starting data. Declare the initial state with `const` or `let`, such as `const values = [3, 8, 5, 2, 7];`. Every presentation shares it.
2. `<script lang="sverlin">`: the algorithm. It starts from the input variables, may update them and declare more, and marks steps with `yield`. It runs once; every presentation shows the same algorithm.
3. `<script lang="sverlin" design>`: presentation choices drawn from each presentation's seed, so the two presentations in a comparison can differ. Each top-level `const` is a design value.

The view receives every top-level input and algorithm variable as it was at the selected step, every design value, and `step` and `seed`, as props: `let { values, i, found, layout } = $props();`.

## Steps

- `yield 'label';` records a step: a copy of every top-level input and algorithm variable. Variables declared inside loops or blocks are not recorded; declare a loop index at the top level (`let i = -1;`) and write `for (i = 0; ...)` when the view needs it. A top-level variable not yet declared at a step is `null`.
- Labels must be unique across the whole algorithm, because comparisons align steps by label. Inside loops, include what distinguishes the step, such as ``yield `Compare index ${i}`;``.
- `yield optional('label');` marks a step a presentation may omit. With the design value `const detail = pick(['coarse', 'fine']);`, coarse presentations omit every optional step; without `detail`, optional steps are kept. `yield optional('label', 0.5);` keeps the step with that probability, drawn from the seed. The first and last steps are always kept.
- When a presentation omits a step, it keeps showing its previous step while the other advances, so the view should read the state it receives rather than assume which step came before.
- `return;` stops the algorithm early.

## Design values

- Draws are `pick(['row', 'grid'])`, `int(3, 6)` (inclusive), `real(0.5, 1.5)`, and `chance(0.3)`, each only as the whole value of a top-level `const`, such as `const layout = pick(['row', 'grid']);`. Other design constants may combine earlier ones.
- Use design values for styling, layout, wording, library component props, and `detail`. The input and algorithm cannot see them, so steps never depend on the seed.
- Design names must differ from input and algorithm names.

## The subset

- Allowed: numbers, strings, booleans, `null`, arrays, plain objects; `if`, `for`, `for (const x of array)`, `while`, `do`, `break`, `continue`; arithmetic, comparison with `===`/`!==`, `&&`, `||`, `??`, `? :`, template strings, `+=` and `++`; `Math.abs/ceil/floor/max/min/pow/round/sign/sqrt/trunc`, `Math.PI`; array `.length`, `.push`, `.pop`, `.shift`, `.unshift`, `.slice`, `.indexOf`, `.includes`, `.reverse`, `.join`.
- Not allowed: functions of any kind, `new`, classes, `this`, `==`, string methods, other globals, and the names `step` and `seed`. Write helper logic inline.
- Limits: 200 steps, 1,000,000 operations, 10,000 entries per array or object, and 10,000 characters per string.
