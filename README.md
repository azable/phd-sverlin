# sverlin

`sverlin` is a project-based SvelteKit visualization workspace backed by a Haskell linear-trace compiler and visualization solver.

The Haskell application under `compile/` loads a supplied Sverlin source file, builds its linear trace, solves its visual layout, and writes a compiled visualization descriptor. The SvelteKit app keeps each project as one immutable, linear Timeline. Committed events are streamed to open clients while an operation runs, and the interface unlocks only after any requested AI generation and compilation has finished and the resulting project state has loaded.

## Project Structure

- `src/` contains the SvelteKit application.
- `src/lib/shared/` contains environment-neutral contracts and pure projections. `shared/projects/events/` defines the immutable event schemas and exhaustive dispatch API, `shared/projects/model.ts` defines documents, commands, and transport resources, and `shared/projects/projection.ts` reconstructs historical state. `shared/visualization/` contains the generated Haskell IR types and wire decoder.
- `src/lib/client/` contains browser behavior and UI. Its project session owns live synchronization and local history selection; the timeline, artifact editor, and visualization player are consumer views over that session. Bundled presentation assets live in `client/assets/`; files requiring stable public URLs live in `static/`. `client/components/ui/` contains the generated shadcn-svelte design-system source, with its styling and prop helpers colocated in `client/components/utils.ts`. This placement is intentional: UI is part of the client boundary, while `components.json` points future shadcn additions and updates at these paths.
- `src/lib/server/projects/` owns durable project documents, whole-command serialization, AI orchestration, and compilation event recording. AI-specific history projection lives beside the assistant under `src/lib/server/chat-bots/ai-assistant/`.
- `src/lib/server/compiler/` runs the Haskell compiler against isolated source snapshots and owns process diagnostics. ESLint enforces the shared/client/server import direction.
- `examples/Minimal.sverlin` defines every new project's blank starting canvas and can also be supplied directly to the CLI. Project edits never rewrite this example.
- `.sverlin` input is a body-only Haskell authoring profile with two required declarations: `program :: Choreography ()` and `visualization :: VisualizationBuilder ()`. The compiler supplies the module, imports, extensions, and visual runner. Query terms are intersected with `<&>`, for example `#array <&> #index @: i`.
- `compile/app/` contains executable-only Haskell modules.
- `compile/app/Sverlin/` owns the small source boundary: it elaborates a `.sverlin` body into a generated Haskell module and loads the resulting typed `VisualTraceGraph` through Hint/GHC.
- `compile/src/LinearTrace/` contains the reusable trace model, public choreography DSL, focused internal view modules, and target pipeline. `LinearTrace.Choreography` exposes the lifecycle DSL directly over `LinearTrace.Core` and adapts query facts during materialization; the modules under `LinearTrace.View/` separately own graph data, output building, style/layout primitives, and solving. `LinearTrace.Visualization.Compile` lowers the solved graph directly into the canonical IR.
- `compile/src/LinearTrace/View/Style.hs` is the authoritative universal style catalogue. Each field defines its symbolic DSL value, constraints, solved value, traversal, and materialization in one place; the concrete `VisualStyle` in `compile/src/LinearTrace/Visualization/IR.hs` mirrors those fields one-for-one.
- `compile/src/LinearTrace/Visualization/IR.hs` is the canonical renderer-neutral visualization intermediate representation. It contains concrete solved style values, sparse field-to-CSP-variable traceback, an immutable element registry, and named timeline steps. Each checkpoint introduces exactly one step containing its visible instances. Future artifact renderers compile this solved IR through `LinearTrace.Visualization.Target` and must not make additional seeded choices.
- `compile/app/GenerateVisualizationTypes.hs` emits `src/lib/shared/visualization/generated/visualization-ir.ts` from the Haskell-owned contract. Run `pnpm run generate:visualization-types` after changing the IR and use `pnpm run check:visualization-types` to detect generated-type drift.
- `compile/src/Solver.hs` is the public solver API. It exposes opaque numeric expressions/constraints, finite categorical choices, real/cyclic/bounded domains, backend diagnostics, preprocessing inspection, and solve/compile entrypoints. Bounded affine hard constraints use normalized hit-and-run sampling; nonlinear, cyclic-equality, or unbounded problems retain the penalty optimizer. Implementation modules live under `compile/src/Solver/` and should normally be imported through the top-level `Solver` facade.
- `compile/test-support/Solver/TestFixtures.hs` contains stable synthetic solver fixtures used by tests and benchmarks.
- `compile/test/` contains direct Haskell tests, using `tasty`, that do not run the full visualization pipeline.
- `compile/bench/` contains direct Haskell benchmarks for fixed solver fixtures.
- `cabal.project` anchors the Haskell project at the repository root. Project scripts pass `--builddir=compile/dist-newstyle` so Cabal build artifacts stay under `compile/`.

## Requirements

- Node.js and `pnpm` for the SvelteKit app.
- GHC/Cabal for the Haskell compiler under `compile/`. The devcontainer uses GHC 9.10.3 and the Haskell package defaults to `GHC2024`.
- L-BFGS-B available as `liblbfgsb` for nonlinear fallback, plus BLAS/LAPACK for `hmatrix` affine reduction. The devcontainer installs Debian's `liblbfgsb-dev`, `libopenblas-dev`, and `liblapack-dev` packages.
- `hlint`, `hindent`, and `stylish-haskell` for Haskell checks/formatting. The devcontainer installs these into `/home/node/.cabal/bin`.

## Generate Visualization JSON

Seeded `pnpm run compile` commands use the shared workspace output layout when no
explicit output file is provided:

```sh
pnpm run compile -- --source examples/Minimal.sverlin --seed 1988735004
```

This writes to a path like `outputs/seed-1988735004/manual-abc123/compiled-seed-1988735004.json`.
Pass `--output` when you want a specific file path or when you omit `--seed`.
The wrapper refreshes `compile-app` and launches it through `cabal exec`, which
supplies the package environment required by Hint. For a direct invocation of an
already-built executable, use
`cabal exec --builddir=compile/dist-newstyle -- compile-app ...`; direct
invocations still require `--output FILE`.

Useful compiler options:

```sh
pnpm run compile -- --source examples/Minimal.sverlin --output outputs/sverlin-seed-1988735004.json --seed 1988735004
pnpm run compile -- --source examples/Minimal.sverlin --output outputs/sverlin-compiled.json --target ir-json
pnpm run compile -- --source examples/Search.sverlin --output outputs/search.json
pnpm run compile -- --source examples/Search.sverlin --source-label examples/Search.sverlin --emit-haskell outputs/Search.generated.hs --output outputs/search.json
```

`--source FILE` is required and accepts any dynamic `.sverlin` file. `--source-label PATH` controls the path shown in GHC diagnostics and compiled metadata, while `--emit-haskell FILE` writes the generated module for debugging. `--seed` makes the solver deterministic for a specific run. `--target ir-json` is currently the only output target and is the default; the target boundary is in place for future compiler-owned artifact formats, including a possible human-readable rendering of the solved `Visualization`. Targets consume only the solved IR and do not expose trace-builder events, symbolic constraints, or additional seeded choices. The source profile is trusted authoring input, not a security sandbox. The web app no longer reads or writes `static/compiled.json`.

Generated project, benchmark, and seeded manual compile outputs are kept under the ignored workspace `outputs/` directory for inspection, grouped by seed with paths like `outputs/seed-1/project-abc123/compiled-seed-1.json` or `outputs/seed-1/bench-def456/compiled-seed-1.json`. Set `SVERLIN_OUTPUT_DIR` to override that workspace output root. Every compile snapshots its exact artifact or AI candidate into a unique output directory and passes that physical file to the compiler while retaining the project-facing source label. Whole commands are serialized per project, while different projects can compile concurrently.

Project state is retained under the ignored `data/projects/<project-id>/project.json` file by default; set `SVERLIN_PROJECT_DIR` to move the root. The readable v1 event log is complete and lossless: source versions, render JSON, compiler stdout/stderr, AI prompts, provider responses, candidate source, and provider error details are stored inline with their SHA-256 provenance and media type. Each event's numeric `id` is its stable 1-based array position, and a UUID `operationId` groups the visible stages of one command. Event batches are written atomically before they are published to live clients; there is no deferred persistence or automatic retention limit. Project files can contain complete source and user requests and are never uploaded automatically except through the deliberately filtered context for an explicit AI feedback request.

AI-generation and compilation-request events record a `dslRevision` containing the exact DSL source hash, the repository's current commit when Git is available, and whether the relevant DSL paths are clean, dirty, or unknown. This is recalculated for every request, so a running development server records saved Haskell DSL edits without a restart. The source hash remains authoritative when the working tree is dirty; a clean commit provides a directly check-outable revision of the whole compiler.

## Compile Performance Benchmark

Use the direct solver benchmark when changing the solver, constraint lowering, or seeded initialization and you want a stable workload independent of a frontend artifact:

```sh
pnpm run bench:solver
```

This runs fixed synthetic solver fixtures from `Solver.TestFixtures` and reports compile/lowering time, backend solve time, total in-process duration, selected backend, problem size, native-bound count, energy-term count, raw/canonical/eliminated counts, affine reduced dimension and burn-in, or optimizer iterations and function/gradient evaluations. The default fixture set includes an app-shaped workload with layout and style variables so solver changes can be measured without depending on editable source. Useful options:

```sh
pnpm run bench:solver --iterations 3
pnpm run bench:solver --seed 1,320994595
pnpm run bench:solver --json
```

The solver preprocessing step flattens conjunctions, removes redundant or duplicate canonical constraints, merges direct and single-variable affine `within` ranges into authoritative variable bounds, removes linear inequalities already implied by those bounds, and reports raw/canonical/eliminated counts through `ProblemInspection`. Finite categorical choices take their domains directly from `ChoiceDomain` and use `freeChoice`, `choose`, `sameChoice`, and `differentChoice`. Unrelated choices are split into connected components and sampled exactly uniformly from each component's satisfying assignments; `withMaxCategoricalBranches` guards the Cartesian search inside any one component rather than multiplying unrelated components together.

Bounded affine hard constraints are normalized to a unit box, reduced through `hmatrix` SVD, projected to feasibility, and sampled with seeded hit-and-run. This targets the uniform distribution over the feasible hard-constraint region; finite burn-in makes it an approximation, so it should be understood as uniform-ish rather than a proof of perfect mixing. `soften` and `minimize` are intentionally ignored on this sampling path: hard constraints define the permitted design space and the seed explores it instead of converging on a preferred point. Style ranges from the style catalogue remain hard authoritative bounds, and an empty hard region now fails instead of silently compromising contradictory requirements. Problems with nonlinear expressions, cyclic equalities, or missing finite bounds fall back to L-BFGS-B and continue to honor soft objectives. `withNumericBackend` can force either path for testing. The phase-I feasibility function is kept behind a narrow internal boundary; a MIP implementation can replace it later if needed, but no external MIP solver or license/runtime dependency is currently introduced.

The visualization regeneration path uses a view-specific penalty configuration only when optimizer fallback is selected, with a stricter retry if that solve fails the success/energy check. Affine samples do not run that redundant retry. The penalty optimizer shares each nested minimum, maximum, and squared energy operand within an evaluation, keeping shrink-wrapped group constraints linear in their child count. Compile commands with `--details` print the selected solver backend and its work counters alongside phase timings for dynamic source loading, view graph construction, solving, IR compilation, target encoding, and writing. Use `pnpm run bench:solver` for detailed solver problem sizes and backend-specific work; the `nested-extrema` fixture specifically guards expression-evaluation cost.

Use the full compile benchmark when changing the Haskell-to-JSON path, project compilation path, or anything where end-to-end behavior matters:

```sh
pnpm run bench:compile
```

The default benchmark runs the same build-and-execute wrapper used by SvelteKit project compilation:

```sh
node scripts/run-compile.mjs -- --source examples/Minimal.sverlin --output <generated-seed-output-file> --target ir-json --seed <seed>
```

It writes compile artifacts under paths like `outputs/seed-1/bench-abc123/compiled-seed-1.json`, validates the generated JSON file, and reports min/mean/median/p95/max durations. To compare changes over time, write benchmark artifacts under the ignored workspace `outputs/` directory:

```sh
pnpm run bench:compile -- --output outputs/compile-before.json
pnpm run bench:compile -- --output outputs/compile-after.json
```

Useful options:

```sh
pnpm run bench:compile -- --iterations 3
pnpm run bench:compile -- --seed 1,320994595
```

## Run The Frontend

Install dependencies, then start Vite:

```sh
pnpm install
pnpm run dev
```

Open the printed local URL. The root opens the most recently updated project or creates one from the empty minimal source. **New project** creates another independent Timeline. Trace playback presents one labelled step per DSL checkpoint and animates solved geometry/style updates, entries, exits, and compiler-provided fork origins; this is a preview capability and does not constrain future artifact targets. Introductions appear in the checkpoint that records them, while removals update the starting state for the following checkpoint, so a final cleanup checkpoint still displays the completed result.

The workspace has a resizable Timeline beside the visualization and source artifact. Every internal operation is visible as its own event; there is no separate chat history, edit history, or compilation-error store. A per-project server-sent event feed publishes complete events only after their atomic project write, so AI, compilation, repair, and activation stages appear while a command is still running. The browser immutably appends those events and derives its snapshot and active visualization locally; it reloads only to recover from a stream gap or failed command. Select an old event to reconstruct that exact read-only project state without a server request; its visualization can still be stepped, selected, panned, and zoomed even as later events arrive. **Restore** copies its artifacts forward as new events rather than changing history. Prior events can be focused while browsing history and then included in feedback after returning to the present. Canvas feedback stores only the render event, checkpoint, and selected render-instance IDs; the AI projection resolves their semantic roles and solved styles from the inline immutable render.

Editing source, changing a seed, restoring, and giving AI feedback are project commands. The interface stays locked while their correlated Timeline events arrive and unlocks only after the command response installs the authoritative complete project resource. The live delivery adapter is process-local, matching the single Node process and local project directory used by the app; durable catch-up survives browser reconnections and server restarts. Manual source is retained even when it fails compilation, with no stale visualization paired to it. AI source remains an unaccepted candidate until it compiles. A source or pipeline failure permits exactly one explicit repair generation and compile; provider retries are disabled, infrastructure failures are not sent back for repair, and there is no internal retry loop. A failed attempt and its terminal notice remain immutable Timeline events.

The v1 Timeline event types are:

- project lifecycle: `project.created`, `project.renamed`;
- input and response: `feedback.submitted`, `assistant.responded`, `system.notified`;
- AI audit: `ai.generation-requested`, `ai.generation-succeeded`, `ai.generation-failed`;
- artifact state: `artifact.version-created`;
- rendering and compilation: `compilation.requested`, `compilation.succeeded`, `compilation.failed`, `visualization.rendered`.

The schema deliberately remains version 1 while the product is refined. Valibot schemas are the source of the TypeScript event, command, and transport types, and event IDs must be contiguous from 1. Historical state is derived by a pure fold over the prefix ending at the selected event. Every event must be added to the aggregate event schema and exhaustively handled by the state projection, Timeline presentation, AI timeline index, and AI conversation projection; TypeScript reports a missing case. Concurrent mutations include the expected numeric head so a stale command cannot overwrite a newer result. The client loads the lossless resource from `GET /api/projects/:projectId`, submits discriminated JSON commands to `POST /api/projects/:projectId`, and follows durable complete events from `GET /api/projects/:projectId/events?after=<event-id>`. The URL's `at` parameter is a client-owned history cursor and does not alter the resource request.

The devcontainer post-create step updates Cabal's package index and runs `cabal build -v0 compile-app --builddir=compile/dist-newstyle` to warm the build artifacts before the first browser-triggered regeneration; it does not need to produce visualization JSON. Cabal's package index, build store, and build-summary log are mounted as writable named volumes at `/home/node/.cabal/packages`, `/home/node/.cabal/store`, and `/home/node/.cabal/logs` because the base image filesystem may be read-only at runtime. Web regeneration has a server-side timeout controlled by `SVERLIN_COMPILE_TIMEOUT_MS`; it defaults to `300000` milliseconds, and the devcontainer sets that value explicitly.

### Configure the AI assistant

Project feedback calls OpenAI from the SvelteKit backend using the official JavaScript SDK and the Responses API. Set the server-only key before starting the app (copy `.env.example` to `.env`):

```sh
OPENAI_API_KEY=your_api_key_here
```

`OPENAI_MODEL` is optional and defaults to the fast, lower-cost coding model `gpt-5.6-luna`; `CHATBOT_CONFIG` defaults to the provider-neutral `ai-assistant` bot. The default authoring request uses low reasoning effort and a 12,000-token shared reasoning/output budget so complete Sverlin source fits without routinely exhausting the response. `CHATBOT_REQUEST_TIMEOUT_MS` defaults to `180000`. The SDK is configured with zero provider retries. The key is never sent to the browser. Bot definitions live under `src/lib/server/chat-bots/`; each defines its initial prompt, context builder, model parameters, and strict structured response contract. The primary assistant's DSL authoring guide is `src/lib/server/chat-bots/ai-assistant/dsl-interface.md`; the server reads it for every model request, so a running development server uses saved guide changes without a restart. A bundled copy remains available when the source file is not present in a packaged deployment. Provider adapters live separately under `src/lib/server/chat-adapters/`, so testing another model or service does not require changing project orchestration.

The chatbot receives the current source workspace, a compact body-free index of the complete Timeline, conversation messages derived from feedback and assistant-response events, and expanded event/workspace or visual details only for references explicitly selected by the user. It never receives an arbitrary “last N” window. Unselected provider prompts, responses, compiler streams, and render bodies remain in the durable project but are represented to the model only by compact metadata and hashes. Exact provider prompts and responses are retained for later prompt evaluation without being recursively embedded in future contexts. `CHATBOT_MAX_CONTEXT_CHARS` (default `500000`) is only a guard against exceeding the provider context; it fails explicitly rather than dropping history. The source editor uses a small Svelte 5 runes adapter over modular CodeMirror 6.

## Frontend Checks

```sh
pnpm run check
pnpm run lint
pnpm run test
```

## Haskell Checks

After changing Haskell source:

```sh
pnpm run compile -- --source examples/Minimal.sverlin --seed 1
pnpm run test:sverlin-source
pnpm run test:solver
pnpm run lint:haskell
```

Before finishing Haskell edits, run the same formatter pipeline used by the editor:

```sh
pnpm run format:haskell
```

`stylish-haskell -i` should be the final source-modifying formatter pass.

## DSL Notes

- Choreography style assignment uses `render selected $ do ...` for node patches and `style @Field ...` for individual style fields. Selected style constraints use `styleOf @Field selected`, keeping assignment distinct from `ensure`/`encourage` relations. Center positioning uses `center selected` in constraints and `center (vec2 x y)` inside `render`. Numeric variables use `variable @Span`/`variable @Angle`; categorical variables use `choice @FontFamily`.
