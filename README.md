# sverlin

`sverlin` is a SvelteKit trace viewer backed by a Haskell trace compiler and visualization solver.

The Haskell application under `compile/` builds a linear-search trace, solves a visual layout for it, and writes a compiled visualization descriptor. The SvelteKit app streams backend compilation logs through `/api/visualization` and renders the visualization only after the backend has successfully produced valid JSON.

## Project Structure

- `src/` contains the SvelteKit application.
- `src/lib/chat/` contains the client-side chat panel used by the workspace; its server-backed OpenAI endpoint is exposed at `/api/chat`.
- `src/lib/visualization/` contains the trace player, canvas, toolbar, debug panel, and shared visualization types.
- `src/lib/server/compile-visualization.ts` runs the Haskell compiler and streams diagnostics for the UI.
- `src/routes/api/visualization/+server.ts` exposes the backend visualization stream used by the frontend.
- `compile/app/` contains executable-only Haskell modules and the current visualization example.
- `compile/app/DSL/Main.hs` defines the current example program and its visual styling/constraints. Query terms are intersected with `<&>`, for example `#array <&> #index @: i`.
- `compile/src/LinearTrace/` contains the reusable trace model, public choreography DSL, internal view graph compiler, and JSON output pipeline. `Choreography` owns the runtime bridge between Core trace events and View render output; `View` owns neutral view ids, labels, style/layout primitives, render intents, graph solving, and materialization.
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
pnpm run compile -- --seed 1988735004
```

This writes to a path like `outputs/seed-1988735004/manual-abc123/compiled-seed-1988735004.json`.
Pass `--output` when you want a specific file path or when you omit `--seed`.
Direct `compile-app` invocations still require `--output FILE`.

Useful compiler options:

```sh
pnpm run compile -- --output outputs/sverlin-seed-1988735004.json --seed 1988735004
pnpm run compile -- --output outputs/sverlin-compiled.json --details
pnpm run compile -- --output outputs/sverlin-compiled.json --json
```

`--seed` makes the solver deterministic for a specific run. `--json` is accepted for compatibility, but compiled visualization JSON is always written to a file. The web app no longer reads or writes `static/compiled.json`.

Supported compile entrypoints share a filesystem lock at `outputs/sverlin-compile.lock` by default so the web app, `pnpm run compile`, and `pnpm run bench:compile` do not run `compile-app` concurrently. Generated web, benchmark, and seeded manual compile outputs are kept under the ignored workspace `outputs/` directory for inspection, grouped by seed with paths like `outputs/seed-1/web-abc123/compiled-seed-1.json` or `outputs/seed-1/bench-def456/compiled-seed-1.json`. Set `SVERLIN_OUTPUT_DIR` to override that workspace output root. A manual compile fails fast if another supported compile is active, while the web UI reports active external compiles, syncs their seed when known, and retries instead of starting a conflicting backend build. Raw ad hoc `cabal run ... compile-app` commands bypass this coordination and should be avoided during frontend development.

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

The visualization regeneration path uses a view-specific solver configuration with looser L-BFGS-B tolerances and a lower hard-constraint penalty than `defaultSolveConfig`, with a stricter retry if the first solve fails the success/energy check. This keeps direct solver tests conservative while avoiding very long regeneration tails. `pnpm run compile -- --output outputs/sverlin-seed-1.json --seed 1 --details` prints variables, native bounds, energy terms, eliminated constraints, optimizer iterations, function/gradient evaluations, and phase timings for view graph construction, solve, materialization, JSON encoding, and JSON writing; use those numbers when investigating slow seeds.

Use the full compile benchmark when changing the Haskell-to-JSON path, frontend compile stream, or anything where end-to-end behavior matters:

```sh
pnpm run bench:compile
```

The default benchmark runs the same Haskell command used by the SvelteKit compile stream and participates in the shared compile lock:

```sh
cabal run -v0 compile-app --builddir=compile/dist-newstyle -- --output <generated-seed-output-file> --json --seed <seed>
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
pnpm run bench:compile -- --details
```

Benchmark `--details` separately because it intentionally includes diagnostic rendering and extra stdout/stderr output.

## Run The Frontend

Install dependencies, then start Vite:

```sh
pnpm install
pnpm run dev
```

Open the printed local URL. The page starts a backend compile stream on load, shows diagnostics while the backend runs, and renders the visualization after compilation succeeds. The workspace has a resizable chat panel alongside a vertical authoring panel: the visualization is shown above the read-only DSL source and its complete revision history. Choose Edit to focus the source editor; chat, trace playback, regeneration, and history selection are locked until the draft is saved or cancelled. Saves use the artifact revision as an optimistic concurrency check. If another change wins the race, the panel presents a diff and requires choosing either Reload server or Keep draft & retry. If another supported compile command is already running, the page shows a busy compile state and retries instead of launching a conflicting backend build; it also subscribes to a compile-lock status stream so manual and benchmark compiles are visible while the page is open. The seed can be supplied through the UI and is sent to `/api/visualization` as a positive integer query parameter.

The devcontainer post-create step runs `cabal build -v0 compile-app --builddir=compile/dist-newstyle` to warm Cabal's build artifacts before the first browser-triggered regeneration; it does not need to produce visualization JSON. Web regeneration has a server-side timeout controlled by `SVERLIN_COMPILE_TIMEOUT_MS`; it defaults to `300000` milliseconds, and the devcontainer sets that value explicitly.

### Configure chat

The chat endpoint calls OpenAI from the SvelteKit backend using the official JavaScript SDK and the Responses API. Set the server-only key before starting the app (copy `.env.example` to `.env`):

```sh
OPENAI_API_KEY=your_api_key_here
```

`OPENAI_MODEL` is optional and defaults to `gpt-5.6`; `CHATBOT_CONFIG` defaults to the provider-neutral `ai-assistant` bot. The key is never sent to the browser. Chat messages and artifact revisions are held in separate server-side in-memory stores for this single-user tool; restarting the server clears them. Chat bot definitions live under `src/lib/server/chat-bots/`: each defines its initial prompt, context builder, model parameters, and structured response contract. Provider adapters live separately under `src/lib/server/chat-adapters/`, so testing another model or service does not require changing chat orchestration. Each source update records an ordered event with a stable event ID, stream cursor, complete before/after snapshots, provenance, and a JSON Patch from the previous revision. The chatbot receives the current artifact plus the complete ordered artifact audit history, never an arbitrary “last N” window. `CHATBOT_MAX_CONTEXT_CHARS` (default `500000`) is only a guard against exceeding the provider context; it fails explicitly rather than dropping history. Use `GET /api/artifacts/dsl-main?after=<streamVersion>` for incremental synchronization or `PATCH /api/artifacts/dsl-main` for a validated manual source update with `baseRevision`. Chat does not overwrite or compile the tracked Haskell file; use the existing compile workflow separately. The source editor uses a small Svelte 5 runes adapter over modular CodeMirror 6, while the history view uses CodeMirror’s merge extension for read-only revision diffs. Use the chat panel’s Reset chat button to clear the transcript and append an auditable reset event when the source has changed; the audit history is retained.

## Frontend Checks

```sh
pnpm run check
pnpm run lint
pnpm run test
```

## Haskell Checks

After changing Haskell source:

```sh
pnpm run compile -- --seed 1
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
