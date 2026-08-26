# Executable DSL examples

This directory is the first executable specification of the public Sverlin
authoring surface. Every `.sverlin` file is a selectable project template
registered in `catalog.json`, including the deliberately blank default
`Minimal.sverlin`. Project creation copies the selected bundled source into an
ordinary immutable project Timeline.

The examples are intentionally small and explicit. They demonstrate the
contract without trying to hide lifecycle or visual constraints behind helper
layers.

| Example                     | Program and lifetime behavior                                                            | Visual behavior                                                                                       |
| --------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `Minimal.sverlin`           | Empty choreography                                                                       | Empty canvas; blank baseline                                                                          |
| `Lifecycle.sverlin`         | Create one typed `Block`, checkpoint it, then consume it with `destroy`                  | Select by semantic facts and show disappearance at the next checkpoint                                |
| `TypedAddition.sverlin`     | Consume two typed inputs with `apply2` and create a typed result                         | Group inputs, operator, and result under a generated parent with relational layout constraints        |
| `ContinuityAndFork.sverlin` | Contrast `copy` with `replace` on one linear value                                       | Check fork origin, stable render-instance identity across replacement, and a temporary selected style |
| `LinearSearch.sverlin`      | Recursive ownership, typed comparison, and an explicit query fact for each runtime index | Array values, active item, result, checkpoints, typography, and highlighted code                      |
| `CspCompositions.sverlin`   | One stable semantic trace                                                                | Seeded `oneOf` alternatives produce valid row and column compositions                                 |

Run the complete contract suite from the repository root:

```sh
pnpm run test:examples
```

The suite prepares one compiler, then sends every template through the same
server compiler boundary used by projects at seeds 1,
2, 7, and 11. It decodes the result, verifies retained resources and target
diagnostics, and checks the behaviors in the table—including linear lineage and
both CSP alternatives. A compile-only unit test is not a substitute for this
suite because failures can occur during source elaboration, solving,
materialization, target encoding, or decoding.

This is not yet exhaustive. In particular, the restored public facade has no
connector or arrow primitive, so these examples do not pretend to provide one
by creating semantically unrelated trace values. A connector example belongs
here when that visual primitive is deliberately restored or redesigned.

For a single manual run:

```sh
pnpm run prepare:compiler
pnpm run compile -- --source examples/LinearSearch.sverlin --seed 7 --details
```

To add an example, add one `.sverlin` file and one unique entry to
`catalog.json`, then add a focused semantic assertion to the integration test
when the example introduces a new contract. Catalog validation rejects missing,
duplicated, and unregistered `.sverlin` files, which keeps the creation menu and test
surface in sync.
