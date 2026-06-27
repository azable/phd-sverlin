# sverlin

`sverlin` is a SvelteKit trace viewer backed by a Haskell trace compiler and visualization solver.

The Haskell application under `compile/` builds a linear-search trace, solves a visual layout for it, and writes the compiled visualization descriptor to `static/compiled.json`. The SvelteKit app reads that JSON and renders an interactive step-by-step visualization in the browser.

## Project Structure

- `src/` contains the SvelteKit application.
- `src/lib/visualization/` contains the trace player, canvas, toolbar, debug panel, and shared visualization types.
- `src/lib/server/compile-visualization.ts` runs the Haskell compiler from the SvelteKit server action used by the UI.
- `static/compiled.json` is the generated visualization consumed by the frontend.
- `compile/app/` contains executable-only Haskell modules and the current visualization example.
- `compile/app/DSL/Main.hs` defines the current example program and its visual styling/constraints. Query terms are intersected with `<&>`, for example `#array <&> #index @: i`.
- `compile/src/LinearTrace/` contains the reusable trace model, choreography DSL, view compiler, and JSON output pipeline.
- `compile/src/Solver.hs` is the public solver API. It exposes opaque numeric expressions/constraints, finite categorical choices, generic real/cyclic domains, diagnostic views, preprocessing inspection, and solve/compile entrypoints. Implementation modules live under `compile/src/Solver/` and should normally be imported through the top-level `Solver` facade.
- `compile/test-support/Solver/TestFixtures.hs` contains stable synthetic solver fixtures used by tests and benchmarks.
- `compile/test/` contains direct Haskell tests, using `tasty`, that do not run the full visualization pipeline.
- `compile/bench/` contains direct Haskell benchmarks for fixed solver fixtures.
- `compile.sh` runs the Haskell app from the repository root.

## Requirements

- Node.js and `pnpm` for the SvelteKit app.
- GHC/Cabal for the Haskell compiler under `compile/`.
- L-BFGS-B 3.0 available as `liblbfgsb` for the bounded layout solver. The devcontainer builds this from the official Fortran source.
- `hlint`, `hindent`, and `stylish-haskell` for Haskell checks/formatting.

## Generate Visualization JSON

Run the Haskell compiler from the repository root:

```sh
./compile.sh
```

This prints trace/solver diagnostics and writes:

```text
static/compiled.json
```

Useful compiler options:

```sh
./compile.sh --seed -1988735004
./compile.sh --details
./compile.sh --json
```

`--seed` makes the solver deterministic for a specific run. `--json` writes the compiled visualization to stdout instead of `static/compiled.json`.

## Compile Performance Benchmark

Use the direct solver benchmark when changing the solver, constraint lowering, or seeded initialization and you want a stable workload that is independent of `DSL/Main.hs`:

```sh
pnpm run bench:solver
```

This runs fixed synthetic solver fixtures from `Solver.TestFixtures` and reports compile/lowering time, backend solve time, total in-process duration, problem size, native-bound count, energy-term count, raw/canonical/eliminated counts, optimizer iterations, and function/gradient evaluations. The default fixture set includes an app-shaped workload with layout and style variables so solver changes can be measured without depending on the current `DSL/Main.hs`. Useful options:

```sh
pnpm run bench:solver --iterations 3
pnpm run bench:solver --seed 1,320994595
pnpm run bench:solver --json
```

The solver preprocessing step flattens conjunctions, removes redundant or duplicate canonical constraints, merges direct and single-variable affine `within` ranges into native L-BFGS-B bounds, removes linear inequalities already implied by native bounds, and reports raw/canonical/eliminated counts through `ProblemInspection`. Finite categorical choices use `Choice`/`Category` plus `freeChoice`, `choose`, `sameChoice`, and `differentChoice`; they are sampled from satisfying finite assignments before numeric solving, with `withMaxCategoricalBranches` guarding accidental branch explosions.

The visualization regeneration path uses a view-specific solver configuration with looser L-BFGS-B tolerances and a lower hard-constraint penalty than `defaultSolveConfig`, with a stricter retry if the first solve fails the success/energy check. This keeps direct solver tests conservative while avoiding very long regeneration tails. `./compile.sh --details` prints variables, native bounds, energy terms, eliminated constraints, optimizer iterations, function/gradient evaluations, and phase timings for view graph construction, solve, materialization, JSON encoding, and JSON writing; use those numbers when investigating slow seeds.

Use the full compile benchmark when changing the Haskell-to-JSON path, frontend server action, or anything where end-to-end behavior matters:

```sh
pnpm run bench:compile
```

The default benchmark runs the same path used by the SvelteKit server action:

```sh
./compile.sh --json --seed <seed>
```

It uses a fixed seed set, validates that stdout is valid JSON, and reports min/mean/median/p95/max durations. To compare changes over time, write benchmark artifacts outside the repo:

```sh
pnpm run bench:compile -- --output /tmp/compile-before.json
pnpm run bench:compile -- --output /tmp/compile-after.json
```

Useful options:

```sh
pnpm run bench:compile -- --iterations 3
pnpm run bench:compile -- --seed 1,320994595
pnpm run bench:compile -- --details
```

Benchmark `--details` separately because it intentionally includes diagnostic rendering and stderr output that the normal JSON server path suppresses.

## Run The Frontend

Install dependencies, then start Vite:

```sh
pnpm install
pnpm run dev
```

Open the printed local URL. The page loads `static/compiled.json` by default and can regenerate the visualization through the server action in the UI.

## Frontend Checks

```sh
pnpm run check
pnpm run lint
pnpm run test
```

## Haskell Checks

After changing Haskell source:

```sh
./compile.sh
pnpm run test:solver
hlint compile/src compile/app compile/test compile/bench compile/test-support
```

Before finishing Haskell edits, run the same formatter pipeline used by the editor:

```sh
find compile/app compile/src compile/test compile/bench compile/test-support -name '*.hs' -print0 | xargs -0 hindent
find compile/app compile/src compile/test compile/bench compile/test-support -name '*.hs' -print0 | xargs -0 stylish-haskell -i
```

`stylish-haskell -i` should be the final source-modifying formatter pass.

## TODO

- Consider a clearer unified presentation API for visualization styles: keep assignment/override semantics distinct from relational constraints, e.g. an explicit `set`-style API for properties while reserving `ensure`/`encourage` for relationships.
