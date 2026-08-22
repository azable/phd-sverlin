# AGENTS.md

## Project Context

This repo contains a SvelteKit application (root), and a Haskell application under `compile/`. The SvelteKit app stores projects as immutable event Timelines under `data/projects/`; project commands run the Haskell executable and return only after compilation has produced valid JSON or recorded a failure event. The Haskell application is responsible for generating the data that the SvelteKit application uses to display information to the user.

## How To Navigate

- The SvelteKit application is located in the root directory, and its source code can be found in the `src/` directory.
- The Haskell application is located in the `compile/` directory. Reusable Haskell library modules live in `compile/src/`; executable-only modules live in `compile/app/`.
- Stable direct solver fixtures live in `compile/test-support/Solver/TestFixtures.hs`; use these for solver tests and benchmarks instead of depending on the editable frontend artifact.
- Use the top-level `Solver` module as the solver API. It intentionally exposes opaque numeric expressions/constraints, finite categorical choices, preprocessing diagnostics, and solve/compile entrypoints; modules under `compile/src/Solver/` are implementation modules unless a task explicitly requires changing solver internals.

## Commands

- To run the Haskell application manually with a seed-based workspace output path, use `pnpm run compile -- --source examples/Minimal.sverlin --seed 1` from the root directory. `--source FILE` is required. Pass `--output FILE` for an explicit path or when omitting `--seed`; the web app no longer reads `static/compiled.json`.
- To run the SvelteKit application, use `pnpm run dev` from the root directory. This will start the development server, with hot-reloading.

## Engineering Rules

- This project uses shadcn-svelte for reusable Svelte UI components. The project configuration is tracked in `components.json`, and the shadcn-svelte skill is installed under `.agents/skills/shadcn-svelte`.
- When adding or updating shadcn-svelte UI components, use `pnpm dlx shadcn-svelte@latest` from the repository root and keep imports aligned with the aliases in `components.json`.
- When edits change project structure, commands, generated artifacts, setup steps, or user-facing development workflow, update `README.md` in the same change where necessary.
- When changing solver behavior, constraint lowering, or seeded initialization, run `pnpm run test:solver`.
- When changing solver performance, constraint lowering, or initialization, prefer `pnpm run bench:solver` for stable before/after timings. It reports compile/lowering, backend solve, total duration, problem size, native bounds, energy terms, raw/canonical/eliminated counts, optimizer iterations, and function/gradient evaluation counts for fixed fixtures, including the app-shaped fixture. Use `pnpm run bench:compile` as an additional end-to-end check when the compile server path or generated JSON pipeline can be affected. Write benchmark result JSON to `outputs/` unless the user explicitly asks to save it in the repo.
- `pnpm run compile -- --source examples/Minimal.sverlin --seed 1 --details` includes phase timings for source loading, the view graph, solver, materialization, JSON encoding, and JSON writing. Seeded manual, compile server, and benchmark paths use generated JSON paths grouped under the ignored workspace `outputs/seed-<seed>/` directory by default; stdout/stderr are diagnostic logs.
- AI-generated source is compiled through the complete visualization pipeline for the submitted UI seed before it can become the active artifact. One failed candidate may be repaired by one explicit second generation; provider retries and open-ended orchestration loops are disabled. Candidates, prompts, responses, compiler output, failures, accepted artifacts, and successful renders are recorded through the project's event log and content-addressed blobs.
- The visualization path intentionally uses a tuned solver config rather than raw `defaultSolveConfig`; preserve this separation so direct solver tests stay conservative while regeneration avoids long L-BFGS-B tails.
- Keep solver tests focused on the top-level `Solver` facade unless the behavior under test is deliberately internal. Add or update stable fixtures in `compile/test-support/Solver/TestFixtures.hs` when solver preprocessing, categorical choices, or backend optimization behavior needs repeatable coverage.

## DSL LLM Authoring Context

- `src/lib/server/chat-bots/ai-assistant/dsl-interface.md` contains the canonical
  DSL interface context for the primary `ai-assistant` bot. It is a human-readable
  authoring reference specifically designed to guide an OpenAI code-generating
  model (currently configured as `gpt-5.6-luna`) when it edits the current Sverlin
  project artifact presented by the frontend.
- The guide is read from disk for every model request during local development,
  so saved edits are picked up without restarting the SvelteKit server. The
  sibling `index.ts` keeps the short role prompt, model configuration, structured
  response contract, and a bundled fallback for packaged deployments.
- Keep this context synchronized in the same change whenever the public DSL
  changes. At minimum, review it when editing
  `compile/src/LinearTrace/Choreography.hs`, its re-exported public modules,
  query/materialization semantics, trace lifecycle operations, visual selection
  and rendering, style fields, layout variables, or constraint operators.
- Also review it whenever the body-only Sverlin source contract changes, including
  required declarations, supplied imports/extensions, payload conventions, or
  the shape of the generated visual runner. Remove stale API names and add new public API
  before merging the corresponding implementation change.
- Derive API statements from the public choreography facade and the frontend's
  minimal starting example. Do not document private implementation
  details as if they were stable DSL affordances, and do not invent helpers that
  are not exported by the facade.
- Keep the context human-readable and organized as compact dot-point sections.
  Explain the linear ownership invariants, the semantic-fact/materialization
  bridge from trace values to visual nodes, and the separation between program
  logic and visual rules. Prefer concrete signatures and small examples when
  they prevent an otherwise likely code-generation error.
- Apply OpenAI code-generation prompting best practices: put the role and public
  contract first; state each invariant once; make scope, success criteria,
  validation expectations, and complete-source output requirements explicit; and
  keep examples only where they clarify a measured or likely failure mode. Do
  not bury critical constraints in prose or repeat the same instruction in
  multiple sections.
- Keep the prompt context independent from transient artefact history. The
  context defines the stable DSL contract; the artefact supplied by the server
  defines the current source of truth. If an API change requires a new editing
  rule, update the context rather than relying on an example hidden in history.
- When changing only the prompt context, run the Svelte checks, lint the bot
  module, and run the project command tests. When changing the DSL or its public API,
  also follow the Haskell compile, solver-test, lint, and formatter requirements
  below.

## Verification

Before finishing:

- If modifying the Haskell application, run `pnpm run compile -- --source examples/Minimal.sverlin --seed 1` from the root directory to compile and run the Haskell application.
- For solver or view-solver changes, run `pnpm run test:solver`.
- Use `hlint compile/src compile/app compile/test compile/bench compile/test-support` to check for any Haskell code style issues.
- After any Haskell source change, run the same formatter pipeline as VSCode on project-owned Haskell source directories (`compile/app compile/src compile/test compile/bench compile/test-support`): first `hindent`, then `stylish-haskell -i`. The `stylish-haskell -i` pass should be the final source-modifying step.
- For performance-sensitive solver changes, also run `pnpm run bench:solver`; use `pnpm run bench:compile` for end-to-end compile performance.
