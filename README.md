# sverlin

`sverlin` is a SvelteKit trace viewer backed by a Haskell trace compiler and visualization solver.

The Haskell application under `compile/` builds a linear-search trace, solves a visual layout for it, and writes the compiled visualization descriptor to `static/compiled.json`. The SvelteKit app reads that JSON and renders an interactive step-by-step visualization in the browser.

## Project Structure

- `src/` contains the SvelteKit application.
- `src/lib/visualization/` contains the trace player, canvas, toolbar, debug panel, and shared visualization types.
- `src/lib/server/compile-visualization.ts` runs the Haskell compiler from the SvelteKit server action used by the UI.
- `static/compiled.json` is the generated visualization consumed by the frontend.
- `compile/app/` contains the Haskell application and visualization DSL.
- `compile/app/DSL/Main.hs` defines the current example program and its visual styling/constraints.
- `compile/app/LinearTrace/` contains the core trace model, choreography DSL, solver, view compiler, and JSON output pipeline.
- `compile.sh` runs the Haskell app from the repository root.

## Requirements

- Node.js and `pnpm` for the SvelteKit app.
- GHC/Cabal for the Haskell compiler under `compile/`.
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
hlint compile/app
```

Before finishing Haskell edits, run the same formatter pipeline used by the editor:

```sh
find compile/app -name '*.hs' -print0 | xargs -0 hindent
find compile/app -name '*.hs' -print0 | xargs -0 stylish-haskell -i
```

`stylish-haskell -i` should be the final source-modifying formatter pass.

## TODO

- Consider a clearer unified presentation API for visualization styles: keep assignment/override semantics distinct from relational constraints, e.g. an explicit `set`-style API for properties while reserving `ensure`/`encourage` for relationships.
