# sverlin component library

The components `Stage`, `ArrayCells`, and `Note` are already in scope in every component; use them without importing. Never write `import` statements, and never declare your own variables or components with these reserved names. Prefer these components over hand-written markup and styles; they keep visualizations consistent across revisions.

- `<Stage title subtitle?>`: the page frame and theme. Wrap the whole visualization in exactly one Stage.
- `<ArrayCells values states? pointers? indices? label?>`: one row of cells.
  - `values`: array of numbers or strings.
  - `states`: array aligned with `values`; each entry is `'idle'`, `'active'` (being examined now), `'visited'` (already examined), `'found'`, or `'muted'`. Missing entries are idle.
  - `pointers`: object mapping a short label to an index, such as `{ i: 2, target: 4 }`; labels appear under that cell.
  - `indices`: show index numbers above values (default `true`).
- `<Note tone?>children</Note>`: a short explanation for the current step. `tone` is `'neutral'` (default), `'info'`, `'success'`, or `'warning'`.

Example:

```svelte
<script lang="sverlin">
  const values = [3, 8, 5];
  let i = -1;
  yield 'Start';
  for (i = 0; i < values.length; i++) {
    yield `Visit ${values[i]}`;
  }
</script>

<script>
  let { values, i } = $props();
</script>

<Stage title="Array walk">
  <ArrayCells
    {values}
    states={values.map((_, index) => (index < i ? 'visited' : index === i ? 'active' : 'idle'))}
    pointers={i < 0 ? {} : { i }}
  />
  <Note tone="info">{i < 0 ? 'Start at the left.' : `Visiting index ${i}.`}</Note>
</Stage>
```
