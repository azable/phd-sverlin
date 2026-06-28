# AGENTS.md

## Project Context

This repo contains a SvelteKit application (root), and a Haskell application under `compile/`. The SvelteKit app streams backend compilation through `/api/visualization`, which runs the Haskell executable, streams diagnostics, and returns a compiled visualization only after valid JSON has been produced. The Haskell application is responsible for generating the data that the SvelteKit application uses to display information to the user.

## How To Navigate

- The SvelteKit application is located in the root directory, and its source code can be found in the `src/` directory.
- The Haskell application is located in the `compile/` directory. Reusable Haskell library modules live in `compile/src/`; executable-only modules and the current example live in `compile/app/`.
- Stable direct solver fixtures live in `compile/test-support/Solver/TestFixtures.hs`; use these for solver tests and benchmarks instead of depending on the changing example in `compile/app/DSL/Main.hs`.
- Use the top-level `Solver` module as the solver API. It intentionally exposes opaque numeric expressions/constraints, finite categorical choices, preprocessing diagnostics, and solve/compile entrypoints; modules under `compile/src/Solver/` are implementation modules unless a task explicitly requires changing solver internals.

## Commands

- To run the Haskell application manually, use `./compile.sh --output /tmp/sverlin-compiled.json` from the root directory. Manual runs must pass `--output`; the web app no longer reads `static/compiled.json`.
- To run the SvelteKit application, use `npm run dev` from the root directory. This will start the development server, with hot-reloading.

## Engineering Rules

- This project uses shadcn-svelte for reusable Svelte UI components. The project configuration is tracked in `components.json`, and the shadcn-svelte skill is installed under `.agents/skills/shadcn-svelte`.
- When adding or updating shadcn-svelte UI components, use `pnpm dlx shadcn-svelte@latest` from the repository root and keep imports aligned with the aliases in `components.json`.
- When edits change project structure, commands, generated artifacts, setup steps, or user-facing development workflow, update `README.md` in the same change where necessary.
- When changing solver behavior, constraint lowering, or seeded initialization, run `pnpm run test:solver`.
- When changing solver performance, constraint lowering, or initialization, prefer `pnpm run bench:solver` for stable before/after timings. It reports compile/lowering, backend solve, total duration, problem size, native bounds, energy terms, raw/canonical/eliminated counts, optimizer iterations, and function/gradient evaluation counts for fixed fixtures, including the app-shaped fixture. Use `pnpm run bench:compile` as an additional end-to-end check when the compile server path or generated JSON pipeline can be affected. Write benchmark result JSON to `/tmp` unless the user explicitly asks to save it in the repo.
- `./compile.sh --output /tmp/sverlin-compiled.json --details` includes phase timings for the view graph, solver, materialization, JSON encoding, and JSON writing. The compile server and benchmark paths use a file output path for generated JSON; stdout/stderr are diagnostic logs, including when `--json --details` is passed.
- The visualization path intentionally uses a tuned solver config rather than raw `defaultSolveConfig`; preserve this separation so direct solver tests stay conservative while regeneration avoids long L-BFGS-B tails.
- Keep solver tests focused on the top-level `Solver` facade unless the behavior under test is deliberately internal. Add or update stable fixtures in `compile/test-support/Solver/TestFixtures.hs` when solver preprocessing, categorical choices, or backend optimization behavior needs repeatable coverage.

## Verification

Before finishing:

- If modifying the Haskell application, run `./compile.sh --output /tmp/sverlin-compiled.json` from the root directory to compile and run the Haskell application.
- For solver or view-solver changes, run `pnpm run test:solver`.
- Use `hlint compile/src compile/app compile/test compile/bench compile/test-support` to check for any Haskell code style issues.
- After any Haskell source change, run the same formatter pipeline as VSCode on project-owned Haskell source directories (`compile/app compile/src compile/test compile/bench compile/test-support`): first `hindent`, then `stylish-haskell -i`. The `stylish-haskell -i` pass should be the final source-modifying step.
- For performance-sensitive solver changes, also run `pnpm run bench:solver`; use `pnpm run bench:compile` for end-to-end compile performance.
