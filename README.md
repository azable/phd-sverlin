# sverlin

`sverlin` is a SvelteKit trace viewer backed by a Haskell trace compiler and visualization solver.

The Haskell application under `compile/` loads a supplied Sverlin source file, builds its linear trace, solves its visual layout, and writes a compiled visualization descriptor. The SvelteKit app streams backend compilation logs through `/api/visualization` and renders the visualization only after the backend has successfully produced valid JSON.

## Project Structure

- `src/` contains the SvelteKit application.
- `src/lib/chat/` contains the client-side chat panel used by the workspace; its server-backed OpenAI endpoint is exposed at `/api/chat`.
- `src/lib/visualization/` contains the lightweight checkpoint-step player, interactive SVG preview, toolbar, and generated IR types. The preview is a frontend view of the IR, not an export pipeline.
- `src/lib/server/compile-visualization.ts` runs the Haskell compiler and streams diagnostics for the UI.
- `src/routes/api/visualization/+server.ts` exposes the backend visualization stream used by the frontend.
- `examples/Minimal.sverlin` defines the frontend's blank starting canvas and can also be supplied directly to the CLI. It is bundled into server memory; edited revisions and their audit history remain there, and compilation uses an isolated `.sverlin` snapshot rather than rewriting the example.
- `.sverlin` input is a body-only Haskell authoring profile with two required declarations: `program :: Choreography ()` and `visualization :: VisualizationBuilder ()`. The compiler supplies the module, imports, extensions, and visual runner. Query terms are intersected with `<&>`, for example `#array <&> #index @: i`.
- `compile/app/` contains executable-only Haskell modules.
- `compile/app/Sverlin/` owns the small source boundary: it elaborates a `.sverlin` body into a generated Haskell module and loads the resulting typed `VisualTraceGraph` through Hint/GHC.
- `compile/src/LinearTrace/` contains the reusable trace model, public choreography DSL, focused internal view modules, and target pipeline. `LinearTrace.Choreography` exposes the lifecycle DSL directly over `LinearTrace.Core` and adapts query facts during materialization; the modules under `LinearTrace.View/` separately own graph data, output building, style/layout primitives, and solving. `LinearTrace.Visualization.Compile` lowers the solved graph directly into the canonical IR.
- `compile/src/LinearTrace/View/Style.hs` is the authoritative universal style catalogue. Each field defines its symbolic DSL value, constraints, solved value, traversal, and materialization in one place; the concrete `VisualStyle` in `compile/src/LinearTrace/Visualization/IR.hs` mirrors those fields one-for-one.
- `compile/src/LinearTrace/Visualization/IR.hs` is the canonical renderer-neutral visualization intermediate representation. It contains concrete solved style values, sparse field-to-CSP-variable traceback, an immutable element registry, and named timeline steps. Each checkpoint introduces exactly one step containing its visible instances. Future artifact renderers compile this solved IR through `LinearTrace.Visualization.Target` and must not make additional seeded choices.
- `compile/app/GenerateVisualizationTypes.hs` emits `src/lib/visualization/generated/visualization-ir.ts` from the Haskell-owned contract. Run `pnpm run generate:visualization-types` after changing the IR and use `pnpm run check:visualization-types` to detect generated-type drift.
- `compile/src/Solver.hs` is the public solver API. It exposes opaque numeric expressions/constraints, finite categorical choices, real/cyclic/bounded domains, diagnostic views, preprocessing inspection, and solve/compile entrypoints. Implementation modules live under `compile/src/Solver/` and should normally be imported through the top-level `Solver` facade.
- `compile/test-support/Solver/TestFixtures.hs` contains stable synthetic solver fixtures used by tests and benchmarks.
- `compile/test/` contains direct Haskell tests, using `tasty`, that do not run the full visualization pipeline.
- `compile/bench/` contains direct Haskell benchmarks for fixed solver fixtures.
- `cabal.project` anchors the Haskell project at the repository root. Project scripts pass `--builddir=compile/dist-newstyle` so Cabal build artifacts stay under `compile/`.

## Requirements

- Node.js and `pnpm` for the SvelteKit app.
- GHC/Cabal for the Haskell compiler under `compile/`. The devcontainer uses GHC 9.10.3 and the Haskell package defaults to `GHC2024`.
- L-BFGS-B available as `liblbfgsb` for the bounded layout solver. The devcontainer installs Debian's `liblbfgsb-dev` package.
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

`--source FILE` is required and accepts any dynamic `.sverlin` file. `--source-label PATH` controls the path shown in GHC diagnostics and compiled metadata, while `--emit-haskell FILE` writes the generated module for debugging. `--seed` makes the solver deterministic for a specific run. `--target ir-json` is currently the only output target and is the default; the target boundary is in place for future compiler-owned artifact formats, including a possible human-readable rendering of the solved `VisualizationPackage`. Targets consume only the solved IR and do not expose trace-builder events, symbolic constraints, or additional seeded choices. The source profile is trusted authoring input, not a security sandbox. The web app no longer reads or writes `static/compiled.json`.

Generated web, benchmark, and seeded manual compile outputs are kept under the ignored workspace `outputs/` directory for inspection, grouped by seed with paths like `outputs/seed-1/web-abc123/compiled-seed-1.json` or `outputs/seed-1/bench-def456/compiled-seed-1.json`. Set `SVERLIN_OUTPUT_DIR` to override that workspace output root. Every web request snapshots its exact in-memory artifact revision into its unique output directory and passes that physical file to the compiler while retaining the frontend source label. There is no application-level compile lock, so different source snapshots can compile concurrently.

App-managed compilation failures are retained as versioned, atomic JSON records under `outputs/compilation-errors/` (or the configured `SVERLIN_OUTPUT_DIR`). Records include the complete candidate, parsed and raw diagnostics, seed, originating revision, prompt/model metadata when applicable, and fingerprints for the prompt and public DSL implementation. A recovered AI transaction updates the same record with its repair outcome. These ignored local files may contain complete source and user requests, are never uploaded automatically, and have no automatic retention limit. Direct terminal compile failures remain terminal-only.

## Compile Performance Benchmark

Use the direct solver benchmark when changing the solver, constraint lowering, or seeded initialization and you want a stable workload independent of a frontend artifact:

```sh
pnpm run bench:solver
```

This runs fixed synthetic solver fixtures from `Solver.TestFixtures` and reports compile/lowering time, backend solve time, total in-process duration, problem size, native-bound count, energy-term count, raw/canonical/eliminated counts, optimizer iterations, and function/gradient evaluations. The default fixture set includes an app-shaped workload with layout and style variables so solver changes can be measured without depending on editable source. Useful options:

```sh
pnpm run bench:solver --iterations 3
pnpm run bench:solver --seed 1,320994595
pnpm run bench:solver --json
```

The solver preprocessing step flattens conjunctions, removes redundant or duplicate canonical constraints, merges direct and single-variable affine `within` ranges into native L-BFGS-B bounds, removes linear inequalities already implied by native bounds, and reports raw/canonical/eliminated counts through `ProblemInspection`. Finite categorical choices use `Choice`/`Category` plus `freeChoice`, `choose`, `sameChoice`, and `differentChoice`; they are sampled from satisfying finite assignments before numeric solving, with `withMaxCategoricalBranches` guarding accidental branch explosions.

The visualization regeneration path uses a view-specific solver configuration with looser L-BFGS-B tolerances and a lower hard-constraint penalty than `defaultSolveConfig`, with a stricter retry if the first solve fails the success/energy check. The solver backend shares each nested minimum, maximum, and squared energy operand within an evaluation, keeping shrink-wrapped group constraints linear in their child count. Compile commands print phase timings for dynamic source loading, view graph construction, solving, IR compilation, target encoding, and writing. Use `pnpm run bench:solver` for detailed solver problem sizes, preprocessing counts, and optimizer evaluation metrics; the `nested-extrema` fixture specifically guards expression-evaluation cost.

Use the full compile benchmark when changing the Haskell-to-JSON path, frontend compile stream, or anything where end-to-end behavior matters:

```sh
pnpm run bench:compile
```

The default benchmark runs the same build-and-execute wrapper used by the SvelteKit compile stream:

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

Open the printed local URL. The page starts from an empty Sverlin program and renders a blank canvas after its initial compilation; the assistant or source editor can then construct the visualization. Trace playback presents one labelled step per DSL checkpoint and animates solved geometry/style updates, entries, exits, and compiler-provided fork origins; this is a preview capability and does not constrain future artifact targets. Introductions appear in the checkpoint that records them, while removals update the starting state for the following checkpoint, so a final cleanup checkpoint still displays the completed result. The workspace has a resizable chat panel alongside a vertical authoring panel: the visualization is shown above the DSL source and its complete in-process revision history. Choose Edit to focus the source editor; chat, trace playback, regeneration, and history selection are locked until the draft is saved or cancelled. Manual revisions update the in-memory artifact and regenerate from an isolated snapshot. AI revisions instead form one locked transaction: the assistant generates a candidate, the server compiles the complete visualization with the current seed, and only a successful candidate becomes the active revision. A source or visualization failure is returned to the assistant for one internal repair attempt. The successfully compiled trace is returned with the chat response, installed before the interface unlocks, and is not compiled a second time. Saves retain optimistic revision checks; if another change wins the race, the stale candidate cannot overwrite it.

The devcontainer post-create step updates Cabal's package index and runs `cabal build -v0 compile-app --builddir=compile/dist-newstyle` to warm the build artifacts before the first browser-triggered regeneration; it does not need to produce visualization JSON. Cabal's package index, build store, and build-summary log are mounted as writable named volumes at `/home/node/.cabal/packages`, `/home/node/.cabal/store`, and `/home/node/.cabal/logs` because the base image filesystem may be read-only at runtime. Web regeneration has a server-side timeout controlled by `SVERLIN_COMPILE_TIMEOUT_MS`; it defaults to `300000` milliseconds, and the devcontainer sets that value explicitly.

### Configure chat

The chat endpoint calls OpenAI from the SvelteKit backend using the official JavaScript SDK and the Responses API. Set the server-only key before starting the app (copy `.env.example` to `.env`):

```sh
OPENAI_API_KEY=your_api_key_here
```

`OPENAI_MODEL` is optional and defaults to the fast, lower-cost coding model `gpt-5.6-luna`; `CHATBOT_CONFIG` defaults to the provider-neutral `ai-assistant` bot. The key is never sent to the browser. Chat messages, the editable artifact, and its audit trail are held in separate server-side in-memory stores for this single-user tool; restarting the server clears them and bootstraps revision zero from the minimal example. Chat bot definitions live under `src/lib/server/chat-bots/`: each defines its initial prompt, context builder, model parameters, and structured response contract. The primary assistant's DSL authoring guide is `src/lib/server/chat-bots/ai-assistant/dsl-interface.md`; the server reads it for every model request, so a running development server uses saved guide changes without a restart. A bundled copy remains available when the source file is not present in a packaged deployment. Provider adapters live separately under `src/lib/server/chat-adapters/`, so testing another model or service does not require changing chat orchestration. `POST /api/chat` accepts an optional positive `seed`; the form submits the seed shown in the visualization toolbar, and the server generates one when it is blank. Each accepted source update records an ordered event with a stable event ID, stream cursor, complete before/after snapshots, provenance, and a JSON Patch from the previous revision. Rejected AI candidates do not enter artifact history. The chatbot receives the current artifact plus the complete ordered artifact audit history, never an arbitrary “last N” window; only the current failed candidate and its structured compiler feedback are added during the single internal repair. `CHATBOT_MAX_CONTEXT_CHARS` (default `500000`) is only a guard against exceeding the provider context; it fails explicitly rather than dropping history. Use `GET /api/artifacts/dsl-main?after=<streamVersion>` for incremental synchronization or `PATCH /api/artifacts/dsl-main` for a validated manual source update with `baseRevision`. The source editor uses a small Svelte 5 runes adapter over modular CodeMirror 6, while the history view uses CodeMirror’s merge extension for read-only revision diffs. Use the chat panel’s Reset chat button to clear the transcript and append an auditable reset event when the source has changed; the audit history is retained until the server restarts.

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
