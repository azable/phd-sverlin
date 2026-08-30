# AGENTS.md

## Project Context

This repo contains a SvelteKit application (root), and a Haskell application under `compile/`. The SvelteKit app stores projects as immutable event Timelines in PostgreSQL. The web process accepts asynchronous operations into those Timelines and executes them through a bounded in-process executor; interrupted work is explicitly failed and retried by the user. The compiler is exposed to server code only as a service that accepts `.sverlin` content and one or more seeds. The Haskell application generates the data that the SvelteKit application displays, but that implementation detail does not cross the compiler service boundary.

## Communication and Documentation

- Write explanations for a developer with in-depth programming knowledge but only
  basic DevOps and Render knowledge. Be concise, but include the context needed to
  understand why an operational step or constraint exists; do not assume familiarity
  with infrastructure-specific terminology.
- Prefer plain language. Define an unavoidable specialist term at its first meaningful
  use when the intended reader may not know it. In repository documentation, link that
  first use to an authoritative source when the definition would otherwise interrupt
  the explanation, prioritizing official product documentation, standards, research
  papers, and then a suitable reference such as Wikipedia.
- Do not add links for ordinary programming terms, repeat the same explanatory link
  throughout a document, or link a term whose meaning is already clear from nearby
  text. The goal is reader understanding rather than exhaustive annotation.
- If a terminology choice remains ambiguous after applying these guidelines, ask for
  clarification. When the same user preference recurs across tasks, suggest adding it
  to this file, but do not modify the standing instructions without approval.
- In Markdown documentation, link references to repository files with relative
  Markdown links so that they remain navigable in GitHub and can be opened directly
  from the documentation in VS Code. Prefer a named heading or symbol when a specific
  passage matters; use a line anchor only for a fixed revision where its line numbers
  cannot drift. Otherwise, link to the file. Use inline code, not a link, for
  illustrative or nonexistent paths.
- When documenting behavior, keep the explanation close to its source of truth. Name
  the relevant source file, configuration, test, or external documentation, and make
  clear whether a statement is established behavior, a recommendation, or an
  assumption. If sources conflict or the behavior cannot be verified, state the
  uncertainty and ask before turning it into a durable instruction.
- During guided external-service setup, account explicitly for every warning or error
  in command output before giving the next step. Classify it as blocking, actionable,
  or harmless; follow any applicable skill remediation; and verify the resulting
  external state with a read-only check where possible.
- Keep human-facing project documentation in the root `README.md`; do not add a
  `docs/` directory or separate project guides without developer approval. Keep
  the README concise, current, and free of duplicated source-level detail.
  Machine-consumed prompt/index files, installed skill instructions, licenses,
  source-adjacent provenance, and a temporary `HANDOVER.md` are not project
  guides. Identify conflicting or stale material before consolidating it.
- Document the rationale and source for operational constants, limits, timeouts, retry
  counts, and other non-obvious numeric choices.
- In response code examples, keep expressions on one line when they remain readable;
  do not mechanically split ordinary function applications across several lines. For
  example, prefer `Selected limits <- select @Number (#limit <&> payload limitLabel)`
  over a vertically expanded equivalent. Use multiple lines when the expression's
  length or structure makes that materially clearer.

## How To Navigate

- The SvelteKit application is located in the root directory, and its source code can be found in the `src/` directory.
- Environment-neutral project contracts, event schemas, projections, and generated visualization IR types live under `src/lib/shared/`; browser sessions, bundled presentation assets, and UI live under `src/lib/client/`; persistence, AI providers, project commands, and compilation live under `src/lib/server/`. Files requiring stable public URLs live under `static/`. Preserve this one-way boundary and its ESLint rules.
- The Haskell application is located in the `compile/` directory. Reusable Haskell library modules live in `compile/src/`; executable-only modules live in `compile/app/`.
- Stable direct solver fixtures live in `compile/test-support/Solver/TestFixtures.hs`; use these for solver tests and benchmarks instead of depending on the editable frontend artifact.
- Use the top-level `Solver` module as the solver API. It intentionally exposes opaque numeric expressions/constraints, finite categorical choices, preprocessing diagnostics, and solve/compile entrypoints; modules under `compile/src/Solver/` are implementation modules unless a task explicitly requires changing solver internals.

## Commands

- Prepare the Haskell executable with `pnpm run prepare:compiler` after changing compiler inputs. The frontend development command prepares it automatically.
- To run the Haskell application manually with a seed-based workspace output path, use `pnpm run compile -- --source examples/Minimal.sverlin --seed 1` from the root directory. `--source FILE` is required. Pass `--output FILE` for an explicit path or when omitting `--seed`; the web app no longer reads `static/compiled.json`.
- To run the SvelteKit application, use `pnpm run dev` from the root directory. It applies pending database migrations, prepares the compiler, and starts the development server with hot-reloading.
- `pnpm run dev:web` skips migration and compiler preparation but still includes asynchronous project-operation execution; there is no separate worker process.

## Engineering Rules

- Before starting a local development server or a check that starts or connects to
  one, test whether `.local/state/sverlin/.server.lock` is currently held. If it is,
  tell the developer that their existing server must be stopped with Ctrl+C and wait
  for confirmation before continuing. Do not bypass the guard, remove the lock file,
  or start with another `SVERLIN_STATE_DIR` unless the developer explicitly confirms
  that the previous server has stopped and asks for that recovery action.
- If completing an active task requires a devcontainer rebuild or Codex restart,
  create or update a temporary root `HANDOVER.md` before stopping. Record the
  task objective, completed work, current working-tree changes and their
  ownership, the next safe action, remaining work or blockers, validations
  already run, and relevant operational state. Do not create a handover for
  completed work or use it as a chronological log.
- On the first turn after a devcontainer rebuild or Codex restart, read
  `HANDOVER.md` completely when it exists, inspect `git status` and the relevant
  diffs, and verify any recorded operational state before changing files.
  Continue from the recorded next safe action, rerun only checks invalidated by
  the restart, and preserve user and concurrent-worker changes. Delete
  `HANDOVER.md` once the resumed task is complete so stale instructions cannot
  affect later work.
- Repository-local skills are available under `.agents/skills/`; their `SKILL.md`
  files describe when and how to use them. Review the available skills for work that
  matches their scope, follow every applicable skill, and consider whether a suitable
  skill exists when the repository does not already provide one. Before adding a skill,
  explain the expected benefit and ask the developer for approval. Manage skills with
  the `skills` CLI, normally invoked through `npx skills`; it installs skill directories
  under `.agents/skills/` and records their source and content hash in the root
  `skills-lock.json`. Use the CLI to add, update, or remove skills rather than editing
  installed skill directories or the lockfile by hand. Treat either file set as a normal
  repository change that must be reviewed and committed. A newly added, removed, or
  updated skill may require a fresh agent session before its availability changes.
- This project uses shadcn-svelte for reusable Svelte UI components. Generated component source intentionally lives under the client boundary at `src/lib/client/components/ui/`, with its helper module at `src/lib/client/components/utils.ts`. The aliases in `components.json` are authoritative for this layout.
- When adding or updating shadcn-svelte UI components, use `pnpm dlx shadcn-svelte@latest` from the repository root and keep imports aligned with the aliases in `components.json`.
- When edits change project structure, commands, generated artifacts, setup steps, or user-facing development workflow, update `README.md` in the same change where necessary.
- `pnpm run test:unit` is the fast TypeScript suite. `pnpm run test` additionally compiles every catalogued example through the real compiler. Run `pnpm run test:e2e` after Svelte behavior changes.
- When changing solver behavior, constraint lowering, or seeded initialization, run `pnpm run test:solver`.
- When changing solver performance, constraint lowering, or initialization, prefer `pnpm run bench:solver` for stable before/after timings. It reports compile/lowering, backend solve, total duration, problem size, native bounds, energy terms, raw/canonical/eliminated counts, optimizer iterations, and function/gradient evaluation counts for fixed fixtures, including the app-shaped fixture. Write benchmark result JSON to `outputs/` unless the user explicitly asks to save it in the repo.
- `pnpm run compile -- --source examples/Minimal.sverlin --seed 1 --details` includes phase timings for source loading, the view graph, solver, materialization, JSON encoding, and JSON writing. Seeded manual, compile server, and benchmark paths use generated JSON paths grouped under the ignored workspace `outputs/seed-<seed>/` directory by default; stdout/stderr are diagnostic logs.
- AI-generated Sverlin source is compiled through the complete visualization pipeline for one or two fresh server-selected seeds before it can become the active artifact. A failed batch may be repaired by one explicit second generation using the same seeds; provider retries and open-ended orchestration loops are disabled. Generated source, prompts, responses, compiler output, failures, accepted artifacts, and successful presentations are stored inline in the complete project event log with hashes for provenance. Direct HTML turns similarly accept at most one safe manifest and one explicit correction.
- The visualization path intentionally uses a tuned solver config rather than raw `defaultSolveConfig`; preserve this separation so direct solver tests stay conservative while regeneration avoids long L-BFGS-B tails.
- Keep solver tests focused on the top-level `Solver` facade unless the behavior under test is deliberately internal. Add or update stable fixtures in `compile/test-support/Solver/TestFixtures.hs` when solver preprocessing, categorical choices, or backend optimization behavior needs repeatable coverage.

## DSL LLM Authoring Context

- For current implemented behavior, use
  `compile/src/LinearTrace/Choreography.hs` and the generated DSL API index described
  below. For proposed API changes, consult
  [`compile/src/LinearTrace/API_plan.md`](compile/src/LinearTrace/API_plan.md); it
  describes a target design and does not override current behavior until implemented.
  [`compile/src/LinearTrace/API_refactoring.md`](compile/src/LinearTrace/API_refactoring.md)
  is supporting rationale rather than the current implementation contract.
- `compile/src/LinearTrace/Choreography.hs` is the canonical public-name and
  per-symbol behavior contract. Keep one Haddock description on every explicit
  facade export. `scripts/dsl-api-index.mjs` validates and indexes those comments
  together with GHC-inferred public signatures; run
  `pnpm run generate:dsl-api-index` after changing them. Never edit the
  generated `src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md` by hand.
- `src/lib/server/chat-bots/sverlin-assistant/dsl-interface.md` is the complementary
  human-readable composition and authoring guide for the primary `sverlin-assistant`
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
- For performance-sensitive solver changes, also run `pnpm run bench:solver`.
