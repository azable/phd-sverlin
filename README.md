# sverlin

`sverlin` is a SvelteKit trace viewer backed by a Haskell trace compiler and visualization solver.

The Haskell application under `compile/` builds a linear-search trace, solves a visual layout for it, and writes a compiled visualization descriptor. The SvelteKit app streams backend compilation logs through `/api/visualization` and renders the visualization only after the backend has successfully produced valid JSON.

## Project Structure

- `src/` contains the SvelteKit application.
- `src/lib/visualization/` contains the trace player, canvas, toolbar, debug panel, and shared visualization types.
- `src/lib/server/compile-visualization.ts` runs the Haskell compiler and streams diagnostics for the UI.
- `src/routes/api/visualization/+server.ts` exposes the backend visualization stream used by the frontend.
- `compile/app/` contains executable-only Haskell modules and the current visualization example.
- `compile/app/DSL/Main.hs` defines the current example program and its visual styling/constraints. Query terms are intersected with `<&>`, for example `#array <&> #index @: i`.
- `compile/src/LinearTrace/` contains the reusable trace model, choreography DSL, view compiler, and JSON output pipeline.
- `compile/src/Solver.hs` is the public solver API. It exposes opaque numeric expressions/constraints, finite categorical choices, generic real/cyclic domains, diagnostic views, preprocessing inspection, and solve/compile entrypoints. Implementation modules live under `compile/src/Solver/` and should normally be imported through the top-level `Solver` facade.
- `compile/test-support/Solver/TestFixtures.hs` contains stable synthetic solver fixtures used by tests and benchmarks.
- `compile/test/` contains direct Haskell tests, using `tasty`, that do not run the full visualization pipeline.
- `compile/bench/` contains direct Haskell benchmarks for fixed solver fixtures.
- `cabal.project` anchors the Haskell project at the repository root. Project scripts pass `--builddir=compile/dist-newstyle` so Cabal build artifacts stay under `compile/`.

## Requirements

- Node.js and `pnpm` for the SvelteKit app.
- GHC/Cabal for the Haskell compiler under `compile/`. The devcontainer uses GHC 9.10.3 and the Haskell package defaults to `GHC2024`.
- L-BFGS-B available as `liblbfgsb` for the bounded layout solver. The devcontainer installs Debian's `liblbfgsb-dev` package.
- `hlint`, `hindent`, and `stylish-haskell` for Haskell checks/formatting. The devcontainer installs these into `/home/node/.cabal/bin`.

## Generate Visualization JSON Manually

Manual JSON generation requires an explicit output file:

```sh
pnpm run compile -- --output /tmp/sverlin-compiled.json
```

Useful compiler options:

```sh
pnpm run compile -- --output /tmp/sverlin-compiled.json --seed 1988735004
pnpm run compile -- --output /tmp/sverlin-compiled.json --details
pnpm run compile -- --output /tmp/sverlin-compiled.json --json
```

`--seed` makes the solver deterministic for a specific run. `--json` is accepted for compatibility, but compiled visualization JSON is always written to a file. The web app no longer reads or writes `static/compiled.json`; `pnpm run compile` and direct `compile-app` invocations must pass `--output FILE`.

Supported compile entrypoints share a filesystem lock under `${TMPDIR:-/tmp}` so the web app, `pnpm run compile`, devcontainer warmup, and `pnpm run bench:compile` do not run `compile-app` concurrently. A manual compile fails fast if another supported compile is active, while the web UI reports active external compiles, syncs their seed when known, and retries instead of starting a conflicting backend build. Raw ad hoc `cabal run ... compile-app` commands bypass this coordination and should be avoided during frontend development.

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

The visualization regeneration path uses a view-specific solver configuration with looser L-BFGS-B tolerances and a lower hard-constraint penalty than `defaultSolveConfig`, with a stricter retry if the first solve fails the success/energy check. This keeps direct solver tests conservative while avoiding very long regeneration tails. `pnpm run compile -- --output /tmp/sverlin-compiled.json --details` prints variables, native bounds, energy terms, eliminated constraints, optimizer iterations, function/gradient evaluations, and phase timings for view graph construction, solve, materialization, JSON encoding, and JSON writing; use those numbers when investigating slow seeds.

Use the full compile benchmark when changing the Haskell-to-JSON path, frontend compile stream, or anything where end-to-end behavior matters:

```sh
pnpm run bench:compile
```

The default benchmark runs the same Haskell command used by the SvelteKit compile stream and participates in the shared compile lock:

```sh
cabal run -v0 compile-app --builddir=compile/dist-newstyle -- --output <temp-file> --json --seed <seed>
```

It uses a fixed seed set, validates the generated JSON file, and reports min/mean/median/p95/max durations. To compare changes over time, write benchmark artifacts outside the repo:

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

Benchmark `--details` separately because it intentionally includes diagnostic rendering and extra stdout/stderr output.

## Run The Frontend

Install dependencies, then start Vite:

```sh
pnpm install
pnpm run dev
```

Open the printed local URL. The page starts a backend compile stream on load, shows diagnostics while the backend runs, and renders the visualization after compilation succeeds. If another supported compile command is already running, the page shows a busy compile state and retries instead of launching a conflicting backend build; it also subscribes to a compile-lock status stream so manual and benchmark compiles are visible while the page is open. The seed can be supplied through the UI and is sent to `/api/visualization` as a positive integer query parameter.

The devcontainer post-create step runs one compile into `/tmp` to warm Cabal's build artifacts before the first browser-triggered regeneration. Web regeneration has a server-side timeout controlled by `SVERLIN_COMPILE_TIMEOUT_MS`; it defaults to `300000` milliseconds, and the devcontainer sets that value explicitly.

## Frontend Checks

```sh
pnpm run check
pnpm run lint
pnpm run test
```

## Haskell Checks

After changing Haskell source:

```sh
pnpm run compile -- --output /tmp/sverlin-compiled.json
pnpm run test:solver
pnpm run lint:haskell
```

Before finishing Haskell edits, run the same formatter pipeline used by the editor:

```sh
pnpm run format:haskell
```

`stylish-haskell -i` should be the final source-modifying formatter pass.

## TODO

- Consider a clearer unified presentation API for visualization styles: keep assignment/override semantics distinct from relational constraints, e.g. an explicit `set`-style API for properties while reserving `ensure`/`encourage` for relationships.
