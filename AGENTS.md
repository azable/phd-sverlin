# AGENTS.md

## Project Context

This repo contains a SvelteKit application (root), and a Haskell application under `compile/`. The SvelteKit app stores projects as immutable event Timelines: local file mode uses `data/projects/`, while the Railway target uses PostgreSQL plus a private Bucket. PostgreSQL project commands enter a pg-boss queue and are completed by a separate worker running the Haskell executable; local file-mode commands execute synchronously. The Haskell application generates the data that the SvelteKit application displays.

## How To Navigate

- The SvelteKit application is located in the root directory, and its source code can be found in the `src/` directory.
- Environment-neutral project contracts, event schemas, projections, and generated visualization IR types live under `src/lib/shared/`; browser sessions, bundled presentation assets, and UI live under `src/lib/client/`; persistence, AI providers, project commands, and compilation live under `src/lib/server/`. Files requiring stable public URLs live under `static/`. Preserve this one-way boundary and its ESLint rules.
- The Haskell application is located in the `compile/` directory. Reusable Haskell library modules live in `compile/src/`; executable-only modules live in `compile/app/`.
- Stable direct solver fixtures live in `compile/test-support/Solver/TestFixtures.hs`; use these for solver tests and benchmarks instead of depending on the editable frontend artifact.
- Use the top-level `Solver` module as the solver API. It intentionally exposes opaque numeric expressions/constraints, finite categorical choices, preprocessing diagnostics, and solve/compile entrypoints; modules under `compile/src/Solver/` are implementation modules unless a task explicitly requires changing solver internals.

## Commands

- Prepare the Haskell executable with `pnpm run prepare:compiler` after changing compiler inputs. The frontend development command prepares it automatically.
- To run the Haskell application manually with a seed-based workspace output path, use `pnpm run compile -- --source examples/Minimal.sverlin --seed 1` from the root directory. `--source FILE` is required. Pass `--output FILE` for an explicit path or when omitting `--seed`; the web app no longer reads `static/compiled.json`.
- To run the SvelteKit application, use `pnpm run dev` from the root directory. This will start the development server, with hot-reloading.
- With the PostgreSQL project store, run `pnpm run worker:dev` in a second terminal so queued project commands can progress.

## Engineering Rules

- Before an agent modifies Svelte application behavior, announce it and run `pnpm run app:lock -- "reason"`. The persistent ignored lock makes an already-open app read-only without disabling inspection or playback and survives a killed agent. Check it with `pnpm run app:lock:status`; unlock explicitly with `pnpm run app:unlock` only after static checks and focused tests pass. Taking the shared dev server offline remains appropriate for server-boundary changes, but never stop unrelated processes or modify project data to establish the lock.
- At the end of every completed task, update the top-level `AGENTS_LOG.md` as a replaceable snapshot of the current uncommitted working-tree changes authored by agents. It is not a chronological diary. Its two purposes are to let a developer quickly understand the implementation and to let an agent safely resume after a devcontainer or conversation restart without reconstructing the work from chat history. Base it on `git status` and the relevant diffs, include staged, unstaged, and untracked agent-authored files until they are committed, and exclude changes known to belong to the user or another concurrent worker.
- Start `AGENTS_LOG.md` with a short scope statement followed immediately by a table of the important added, modified, moved, or deleted files. Use relative Markdown links to live files; for a moved or deleted file, link its replacement or containing directory when the old path no longer exists. Group closely related files where that makes the implementation easier to understand, and prioritize architectural entry points over exhaustive low-value listings. Follow the table with a plain-language architecture and behavior summary, representative small code snippets, verification performed, limitations, and any known changes deliberately excluded from the summary.
- If `AGENTS_LOG.md` is already modified or untracked when a task begins, revise that same file in place so it continues to summarize **all** current uncommitted agent-authored changes. Do not discard earlier uncommitted work, reduce the log to only the latest task, append a dated diary entry, or create a second work-log file. Once the existing log and the changes it describes have been committed, replace its contents for the next task's new working-tree snapshot.
- Keep a concise resume section near the top of `AGENTS_LOG.md`. State whether implementation is complete or mid-flight, the next safe action, remaining work or blockers, validations already run and their outcomes, and any relevant operational state such as an intentionally held app lock. Record durable facts and commands rather than transient process IDs. The log must be self-contained enough to resume safely without relying on the conversation transcript.
- On the first turn after a devcontainer rebuild or agent restart, read `AGENTS.md` and `AGENTS_LOG.md` completely, inspect `git status` and the relevant diffs, and check any operational state named in the resume section before changing files. Continue from the recorded next safe action, re-run only checks invalidated by the rebuild, preserve user and concurrent-worker changes, and update the same log when the resumed task completes.
- This project uses shadcn-svelte for reusable Svelte UI components. Generated component source intentionally lives under the client boundary at `src/lib/client/components/ui/`, with its helper module at `src/lib/client/components/utils.ts`. The aliases in `components.json` are authoritative for this layout, and the shadcn-svelte skill is installed under `.agents/skills/shadcn-svelte`.
- When adding or updating shadcn-svelte UI components, use `pnpm dlx shadcn-svelte@latest` from the repository root and keep imports aligned with the aliases in `components.json`.
- Railway's official `use-railway` skill is installed under `.agents/skills/use-railway`. Use it for Railway setup, deployment, configuration, and operations tasks; it is repository-local so trusted clones inherit the same guidance.
- When edits change project structure, commands, generated artifacts, setup steps, or user-facing development workflow, update `README.md` in the same change where necessary.
- `pnpm run test:unit -- --run` is the fast TypeScript suite. `pnpm run test` additionally compiles every catalogued example through the real compiler. Run `pnpm run test:e2e` after Svelte behavior changes.
- When changing solver behavior, constraint lowering, or seeded initialization, run `pnpm run test:solver`.
- When changing solver performance, constraint lowering, or initialization, prefer `pnpm run bench:solver` for stable before/after timings. It reports compile/lowering, backend solve, total duration, problem size, native bounds, energy terms, raw/canonical/eliminated counts, optimizer iterations, and function/gradient evaluation counts for fixed fixtures, including the app-shaped fixture. Use `pnpm run bench:compile` as an additional end-to-end check when the compile server path or generated JSON pipeline can be affected. Write benchmark result JSON to `outputs/` unless the user explicitly asks to save it in the repo.
- `pnpm run compile -- --source examples/Minimal.sverlin --seed 1 --details` includes phase timings for source loading, the view graph, solver, materialization, JSON encoding, and JSON writing. Seeded manual, compile server, and benchmark paths use generated JSON paths grouped under the ignored workspace `outputs/seed-<seed>/` directory by default; stdout/stderr are diagnostic logs.
- AI-generated source is compiled through the complete visualization pipeline for the submitted UI seed before it can become the active artifact. One failed candidate may be repaired by one explicit second generation; provider retries and open-ended orchestration loops are disabled. Candidates, prompts, responses, compiler output, failures, accepted artifacts, and successful renders are stored inline in the complete project event log with hashes for provenance.
- The visualization path intentionally uses a tuned solver config rather than raw `defaultSolveConfig`; preserve this separation so direct solver tests stay conservative while regeneration avoids long L-BFGS-B tails.
- Keep solver tests focused on the top-level `Solver` facade unless the behavior under test is deliberately internal. Add or update stable fixtures in `compile/test-support/Solver/TestFixtures.hs` when solver preprocessing, categorical choices, or backend optimization behavior needs repeatable coverage.

## DSL LLM Authoring Context

- `compile/src/LinearTrace/Choreography.hs` is the canonical public-name and
  per-symbol behavior contract. Keep one Haddock description on every explicit
  facade export. `scripts/dsl-api-index.mjs` validates and indexes those comments
  together with GHC-inferred public signatures; run
  `pnpm run generate:dsl-api-index` after changing them. Never edit the
  generated `src/lib/server/chat-bots/ai-assistant/dsl-api-index.md` by hand.
- `src/lib/server/chat-bots/ai-assistant/dsl-interface.md` is the complementary
  human-readable composition and authoring guide for the primary `ai-assistant`
  bot (currently configured as `gpt-5.6-luna`). It should explain cross-cutting
  invariants, syntax hazards, and examples without duplicating the exhaustive API
  index.
- The guide and generated index are read from disk for every model request during
  local development, so saved edits are picked up without restarting the
  SvelteKit server. The sibling `index.ts` keeps the short role prompt, model
  configuration, structured response contract, and bundled fallbacks for
  packaged deployments.
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
  minimal starting example. Do not document private implementation details as if
  they were stable DSL affordances, and do not invent helpers that are not
  exported by the facade. `pnpm run check:dsl-api-index` must pass; the normal
  lint command also enforces generated-index drift and missing export docs.
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
- After any Haskell source change, run the same formatter pipeline as VSCode on project-owned Haskell source directories (`compile/app compile/src compile/test compile/bench compile/test-support`): first `hindent`, then `stylish-haskell -i`. Run this full formatting pipeline exactly once per task, at the very end after the implementation, lint-driven fixes, and other source changes are complete. Do not run it speculatively or repeatedly during development. The `stylish-haskell -i` pass should be the final source-modifying step; afterward, perform only non-modifying verification unless a necessary source correction requires another final formatting pass.
- For performance-sensitive solver changes, also run `pnpm run bench:solver`; use `pnpm run bench:compile` for end-to-end compile performance.
