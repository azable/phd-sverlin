# sverlin

`sverlin` is a project-based SvelteKit visualization workspace backed by a Haskell linear-trace compiler and visualization solver.

The Haskell application under `compile/` loads a supplied Sverlin source file, builds its linear trace, solves its visual layout, and writes a compiled visualization descriptor. The SvelteKit app keeps each project as one immutable, linear Timeline. Committed events are streamed to open clients while an operation runs, and the interface unlocks only after any requested AI generation and compilation has finished and the resulting project state has loaded.

## Project Structure

- `src/` contains the SvelteKit application.
- `src/lib/shared/` contains environment-neutral contracts and pure projections. `shared/projects/events/` defines the immutable event schemas and exhaustive dispatch API, `shared/projects/model.ts` defines documents, commands, and transport resources, and `shared/projects/projection.ts` reconstructs historical state. `shared/visualization/` contains the generated Haskell IR types and wire decoder.
- `src/lib/client/` contains browser behavior and UI. Its project session owns live synchronization and local history selection; the timeline, artifact editor, and visualization player are consumer views over that session. Bundled presentation assets live in `client/assets/`; files requiring stable public URLs live in `static/`. `client/components/ui/` contains the generated shadcn-svelte design-system source, with its styling and prop helpers colocated in `client/components/utils.ts`. This placement is intentional: UI is part of the client boundary, while `components.json` points future shadcn additions and updates at these paths.
- `src/lib/server/projects/` owns durable project documents, whole-command serialization, AI orchestration, and compilation event recording. AI-specific history projection lives beside the assistant under `src/lib/server/chat-bots/ai-assistant/`.
- `src/lib/server/compiler/` runs the Haskell compiler against isolated source snapshots and owns process diagnostics. ESLint enforces the shared/client/server import direction.
- `examples/Minimal.sverlin` defines the default blank template. The other catalogued templates cover lifecycle, lineage, typed operations, code, typography, hierarchy, relational layout, and seeded CSP composition. See `examples/README.md`; project edits never rewrite these bundled sources.
- `.sverlin` input is a body-only Haskell authoring profile with two required declarations: `program :: Choreography ()` and `visualization :: VisualizationBuilder ()`. The compiler supplies the module, imports, extensions, and visual runner. Query terms are intersected with `<&>`, for example `#array <&> #index @: i`.
- `compile/app/` contains executable-only Haskell modules.
- `compile/app/Sverlin/` owns the small source boundary: it elaborates a `.sverlin` body into a generated Haskell module and loads the resulting typed `VisualTraceGraph` through Hint/GHC.
- `compile/src/LinearTrace/` contains the reusable trace model, public choreography DSL, focused internal view modules, and target pipeline. `LinearTrace.Choreography` exposes the lifecycle DSL directly over `LinearTrace.Core` and adapts query facts during materialization; the modules under `LinearTrace.View/` separately own graph data, output building, style/layout primitives, and solving. `LinearTrace.Visualization.Compile` lowers the solved graph directly into the canonical IR.
- `compile/src/LinearTrace/View/Style.hs` is the authoritative universal style catalogue. Each field defines its symbolic DSL value, constraints, solved value, traversal, and materialization in one place. Fields may be required, forbidden, or conditionally present; the concrete `VisualStyle` in `compile/src/LinearTrace/Visualization/IR.hs` remains sparse and contains only the selected solved fields.
- Body-only Sverlin compilation enables balanced automatic style profiles after authored rules and selected-style access have been applied. Trace leaves share a profile and palette by payload type, `styleFamily` can override that inference, and generated structural parents remain transparent unless explicitly styled. Direct Haskell use of `runChoreographyWith` retains sparse omission semantics.
- `compile/src/LinearTrace/Visualization/IR.hs` is the canonical renderer-neutral visualization intermediate representation. Root-based version 1 represents the canvas as element `-1`, and every element has a border box, four-edge padding and margin, and a uniform child-ID list alongside concrete solved style values, explicit text baselines, exact resource descriptors, compiler findings, sparse field-to-CSP-variable traceback, and named timeline steps. Geometry and typography are expressed in scalable logical layout units with no CSS-pixel or physical-resolution assumption; renderers map the root viewport to their target. Child references form an acyclic single-parent hierarchy rooted at the persistent canvas; timeline steps contain only trace/generated render instances because the canvas is always present. Artifact renderers consume a versioned `CompilationPackage` through the pure `LinearTrace.Visualization.Target` boundary and must not make additional seeded choices.
- `compile/app/GenerateVisualizationTypes.hs` emits `src/lib/shared/visualization/generated/visualization-ir.ts` from the Haskell-owned contract. Run `pnpm run generate:visualization-types` after changing the IR and use `pnpm run check:visualization-types` to detect generated-type drift.
- `compile/src/Solver.hs` is the public solver API. It exposes opaque numeric expressions/constraints, named finite disjunctions, typed categorical choices, real/cyclic/bounded domains, backend diagnostics, preprocessing inspection, and solve/compile/sample entrypoints. `CompiledDesignSpace` separates seed-independent branch compilation from repeated sampling. Bounded affine branches use normalized hit-and-run; large discrete spaces use MIP plus HiGHS for feasible conditioning; nonlinear, cyclic-equality, or unbounded legacy problems retain the penalty optimizer. Implementation modules live under `compile/src/Solver/` and should normally be imported through the top-level `Solver` facade.
- `compile/test-support/Solver/TestFixtures.hs` contains stable synthetic solver fixtures used by tests and benchmarks.
- `compile/test/` contains direct Haskell tests, using `tasty`, that do not run the full visualization pipeline.
- `compile/bench/` contains direct Haskell benchmarks for fixed solver fixtures.
- `compile/vendor/` contains Haskell source dependencies patched and pinned specifically for the compiler; keeping it beside the consuming Haskell package avoids making vendored package internals part of the JavaScript workspace root.
- `compile/cabal.project` anchors the complete Haskell project beside its package and vendored source. Project scripts use `scripts/run-cabal.mjs`, which starts Cabal with `compile/` as its working directory and the repository's explicit Cabal config. This keeps Cabal's project build tree at `compile/dist-newstyle` even for commands that eagerly create their default build path.
- The devcontainer sets both `CABAL_CONFIG` and `CABAL_DIR` to workspace-mounted paths. Cabal logs, packages, and state therefore stay writable under `.cache/cabal` and `.local/state/cabal` for direct shell commands as well as project scripts; they never fall back to `/root/.cache/cabal`, which is outside the agent workspace sandbox.

## Requirements

- Node.js and `pnpm` for the SvelteKit app.
- GHC/Cabal for the Haskell compiler under `compile/`. The devcontainer uses GHC 9.10.3 and the Haskell package defaults to `GHC2024`.
- L-BFGS-B available as `liblbfgsb` for nonlinear fallback, BLAS/LAPACK for `hmatrix` affine reduction, the `highs` executable for MIP-conditioned disjunctions above the exact-enumeration limit, HarfBuzz for deterministic compiler-owned font shaping, and FreeType for the planned outline/font-validation target seam. The devcontainer installs these native libraries and builds a pinned HiGHS release. Rebuild an existing devcontainer after pulling this change so the native libraries persist; the vendored MIP and `skylighting-core` changes alone do not require an image rebuild.
- `hlint`, `hindent`, and `stylish-haskell` for Haskell checks/formatting. The devcontainer pins and installs these into `/usr/local/bin` during the image build, so they are available before post-create setup runs.
- `jq` for inspecting generated JSON and validating devcontainer metadata; the devcontainer installs the distro package.

## Generate Visualization JSON

Seeded `pnpm run compile` commands use the shared workspace output layout when no
explicit output file is provided:

```sh
pnpm run compile -- --source examples/Minimal.sverlin --seed 1988735004
```

This writes to a path like `outputs/seed-1988735004/manual-abc123/compiled-seed-1988735004.json`.
Pass `--output` when you want a specific file path or when you omit `--seed`.
Run `pnpm run prepare:compiler` after compiler inputs change. Preparation builds
`compile-app` once and records its direct executable plus the GHC package
environment required by dynamic Sverlin loading. Manual and web compilation then
use that prepared executable without putting Cabal inside every request. A stale
or missing preparation fails explicitly instead of silently running an old
compiler. The descriptor is bound to the checkout from which the command is run;
prepare separately in each checkout or worktree. `dev`, `build`, `preview`, and
the adapter-node `start` command all prepare before serving. `pnpm run cabal --
...` remains available for ad hoc Cabal commands.
Direct compiler invocations still require `--output FILE`.

Useful compiler options:

```sh
pnpm run compile -- --source examples/Minimal.sverlin --output outputs/sverlin-seed-1988735004.json --seed 1988735004
pnpm run compile -- --source examples/Minimal.sverlin --output outputs/sverlin-compiled.json --target ir-json
pnpm run compile -- --source examples/Search.sverlin --output outputs/search.json
pnpm run compile -- --source examples/Search.sverlin --source-label examples/Search.sverlin --emit-haskell outputs/Search.generated.hs --output outputs/search.json
pnpm run compile -- --source examples/Minimal.sverlin --seed 1 --count 8 --output outputs/minimal-samples.json
```

`--source FILE` is required and accepts any dynamic `.sverlin` file. `--source-label PATH` controls the path shown in GHC diagnostics and compiled metadata, while `--emit-haskell FILE` writes the generated module for debugging. `--seed` makes geometry, categorical choices, and automatic family styles deterministic for a specific run. `--count INT` builds the view graph and affine design space once, then samples consecutive seeds; one sample retains the normal object response and multiple samples write a JSON array. `--target ir-json` is currently the only output target and is the default. Every target returns a primary artifact, attachments, diagnostics, and provenance; the CLI writes `<output>.manifest.json` plus content-addressed files under `resources/`. This package contract is shared by future SVG, LaTeX, and PDF targets, which may choose different faithful or semantic renderings while retaining compiler-selected text lines, resource identity, and findings. Targets consume only solved IR and make no new seeded choices. The source profile is trusted authoring input, not a security sandbox. The web app no longer reads or writes `static/compiled.json`.

Generated project, benchmark, and seeded manual compile outputs are kept under the ignored workspace `outputs/` directory for inspection, grouped by seed with paths like `outputs/seed-1/project-abc123/compiled-seed-1.json` or `outputs/seed-1/bench-def456/compiled-seed-1.json`. Set `SVERLIN_OUTPUT_DIR` to override that workspace output root. Every compile snapshots its exact artifact or AI candidate into a unique output directory and passes that physical file to the compiler while retaining the project-facing source label. Whole commands are serialized per project, while different projects can compile concurrently.

Project state is retained under the ignored `data/projects/<project-id>/project.json` file by default; set `SVERLIN_PROJECT_DIR` to move the root. The readable v1 event log is complete and lossless: source versions, render JSON, compiler stdout/stderr, AI prompts, provider responses, candidate source, and provider error details are stored inline with their SHA-256 provenance and media type. Font and glyph-run bytes live beside it in `resources/sha256-<digest>` and events retain strict immutable descriptors plus package, text-run, shaping-engine, font-catalog provenance, and non-fatal target diagnostics. A successful append verifies size and SHA-256, commits missing blobs before the atomic document rename, and safely deduplicates existing content. The browser fetches referenced blobs from `GET /api/projects/:projectId/resources/:resourceId` with immutable caching and a second digest check. Each event's numeric `id` is its stable 1-based array position, and a UUID `operationId` groups the visible stages of one command. Event batches are written atomically before they are published to live clients; there is no deferred persistence or automatic retention limit. Project files can contain complete source and user requests and are never uploaded automatically except through the deliberately filtered context for an explicit AI feedback request.

### Compiler-owned typography and code

Text is shaped with HarfBuzz between the initial aesthetic solve and a second constraint solve. The second solve pins every finite aesthetic choice and every text-sizing input from the first solve (box width and height, padding, stroke width, and any authored size cap), reuses that solution as its initialization, and adds hard content-box width and exact vertical ink/line-box constraints. Typography therefore adapts to solved geometry without silently changing the seed's design family or enlarging its box to make text fit. Compiler-selected lines and baselines are authoritative; the SVG browser renderer loads the exact project font with `FontFace`, emits one SVG text node per line, and never delegates wrapping to CSS. Text stays hidden if the exact font is unavailable instead of falling back silently. Runtime metric mismatch observations remain ephemeral and separate from immutable compiler findings.

For unspecified presentation, one exact managed font face and one balanced occupancy target (68%, 78%, 86%, or 94% of the maximum feasible size) are selected globally, while semantic families independently select surface treatment and a 400, 500, or 600 weight. Peers in one family share the smallest feasible fitted size so a list or table remains typographically coherent. These independent, uniformly sampled decisions provide broad defaults without inferring roles from payload names or content. Automatic fitting has a 12-layout-unit managed minimum and uses 0.25-layout-unit steps.

A literal `style @FontSize` on `content` is fixed. `fitText "label"` with no `FontSize` chooses the largest size that fits the solved content box; with a `FontSize`, that value is an upper bound. Font sizes are bounded by the canvas rather than the former 48-layout-unit ceiling, so a valid explicit request such as 56 layout units is not rejected before typography measures it. Normal text prefers one line and may insert at most two deterministic breaks. `WhiteSpacePre` preserves authored lines, while compiler no-fit and missing-glyph cases fail with actionable diagnostics. Size reduction, minimum managed layout size, inserted wrapping, and static weight substitution remain inspectable as IR findings and are included in AI project context. Repeated content should first receive sensible solver geometry—for example, a bounded list lane with count-appropriate shared cell dimensions and gaps—then typography naturally becomes smaller as more items must share that lane.

The managed preset families are Inter, Source Sans 3, Atkinson Hyperlegible Next, Space Grotesk, Source Serif 4, Literata, JetBrains Mono NL, and IBM Plex Mono. Generic `system-ui`, `serif`, and `monospace` tokens resolve to exact managed faces. Every bundled face is license-bearing, hash-pinned, and embedded as a target resource. The catalog/resource seam is intentionally compatible with future project-uploaded fonts, but upload validation and OpenType sanitization are not yet exposed in the frontend.

Code uses the same geometry and resource pipeline with verbatim whitespace, JetBrains Mono NL by default, and text-run format v2 token ranges. Start with `codeContent`, optionally wrap it in `codeWrap`, then wrap that in `highlightCode "language"`; the two-break budget can be distributed across authored lines. `emphasizeCode "checkpoint" [codeRange start end]` adds optional step-specific emphasis using half-open Unicode character offsets. The compiler converts those to canonical UTF-8 ranges on each matching render instance, independently of immutable syntax tokens. Invalid ranges or checkpoint labels where the element is not visible fail compilation. Supported highlighting aliases cover Sverlin/Haskell, JavaScript/TypeScript and common C-like languages, Python/shell, JSON, CSS, and SQL. The embedded grammar subset is authored in this BSD-3-Clause project and interpreted by the exact tested `skylighting-core-0.14.7`; the GPL KDE XML corpus is not bundled. Semantic token roles remain renderer-neutral so later SVG, LaTeX, and PDF targets can apply their own themes.

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

Bounded affine hard constraints are normalized to a unit box, reduced through `hmatrix` SVD, projected to feasibility, and sampled with seeded hit-and-run. This targets the uniform distribution over the feasible hard-constraint region; finite burn-in makes it an approximation, so it should be understood as uniform-ish rather than a proof of perfect mixing. `soften` and `minimize` are intentionally ignored on this sampling path: hard constraints define the permitted design space and the seed explores it instead of converging on a preferred point. Style ranges from the style catalogue remain hard authoritative bounds, and an empty hard region now fails instead of silently compromising contradictory requirements. `oneOf` and exhaustive typed `caseOf` define named disjunctive affine regions. The default balanced strategy gives each feasible enumerated alternative equal mass before continuous sampling. An opt-in geometric strategy estimates relative intrinsic branch volume with bounded nested-ball hit-and-run; it reports failure rather than hiding an unmet uncertainty or walk budget. Above the exact branch limit, the Haskell `MIP` package lowers one-hot choices and tightly bounded guarded affine rows to the external HiGHS executable, then hit-and-run samples inside the selected region. Every visualization records sampling mode and decision coverage in its generated IR provenance.

Problems with nonlinear expressions, cyclic equalities, or missing finite bounds still fall back to L-BFGS-B when they do not use finite disjunctions, and continue to honor soft objectives. A disjunctive design space must remain bounded and affine because mixing penalty minima has no well-defined uniform base measure. `withNumericBackend` can force the legacy numeric path for testing. The published `MIP 0.2.0.1` release relies on a `ParseSettings` instance removed from `xml-conduit` 1.9. `compile/vendor/MIP-0.2.0.1` pins that audited BSD-3-Clause source beside its sole Haskell consumer and applies only the two-call `XML.def` compatibility patch, allowing the project to share current `xml-conduit` with `skylighting-core`; this Haskell dependency change does not require a devcontainer rebuild.

The visualization regeneration path uses a view-specific penalty configuration only when optimizer fallback is selected, with a stricter retry if that solve fails the success/energy check. Affine samples do not run that redundant retry. A generated node's default `Hug` fit remains affine: containment covers every child margin box and named edge decisions select a tight child on each edge. `Contain` keeps containment while permitting extra room. Parent-relative percentages lower to affine constraints over the parent content box. The legacy optimizer still shares nested minimum, maximum, and squared energy operands within an evaluation for explicit nonlinear problems and the stable `nested-extrema` fixture. Compile commands with `--details` print the selected solver backend and its work counters alongside phase timings for dynamic source loading, view graph construction, solving, IR compilation, target encoding, and writing.

Use the full compile benchmark when changing the Haskell-to-JSON path, project compilation path, or anything where end-to-end behavior matters:

```sh
pnpm run bench:compile
```

The default benchmark runs the same prepared-executable wrapper used by SvelteKit project compilation:

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

**New project** opens the server-owned template catalog. The blank
`Minimal.sverlin` template and every executable example use the same creation
path: the selected source is copied into a new independent Timeline and its
`templateId` is retained in the root event. Template selection does not change
the available editor or assistant behavior. Creation chooses a fresh random
positive seed for every template; the catalog does not pin examples to showcase
seeds. Fixed seed lists belong only in repeatable tests and benchmarks.

**Dev mode** is a reversible frontend detail toggle, not a project type. It
shows complete event payloads, retained compiler/provider records, and raw
project JSON for whichever project is open. The preference is represented by
`?dev=1`, so it survives project and history navigation without becoming part
of immutable project history.

### Read-only maintenance lock

Use the repository-local lock when changing application behavior while another
person may have the frontend open:

```sh
pnpm run app:lock -- "Updating project command boundaries"
pnpm run app:lock:status
pnpm run app:unlock
```

The ignored `.cache/sverlin/app-lock.json` file survives a killed shell or agent,
so unlocking is always explicit. While locked, the server returns HTTP 423 with
`code: "app_locked"` for every mutation under `/api/projects`, including future
mutation methods and sub-routes. Project reads, history inspection, raw JSON,
Dev details, and visualization playback remain available. Open browsers poll the
status every two seconds and disable creation, feedback, editing, rename,
restore, and regeneration controls. Set `SVERLIN_APP_LOCK_PATH` only when an
isolated test or deployment needs a different lock path.

The workspace has a resizable Timeline beside the visualization and source artifact. Every internal operation is visible as its own event; there is no separate chat history, edit history, or compilation-error store. A per-project server-sent event feed publishes complete events only after their atomic project write, so AI, compilation, repair, and activation stages appear while a command is still running. The browser immutably appends those events and derives its snapshot and active visualization locally; it reloads only to recover from a stream gap or failed command. Select an old event to reconstruct that exact read-only project state without a server request; its visualization can still be stepped, selected, panned, and zoomed even as later events arrive. **Restore** copies its artifacts forward as new events rather than changing history. Prior events can be focused while browsing history and then included in feedback after returning to the present. Canvas feedback stores only the render event, checkpoint, and selected render-instance IDs; the AI projection resolves their semantic roles and solved styles from the inline immutable render.

Playwright exercises real compiled project creation, maintenance behavior, and
Dev-detail display headlessly and
stores screenshots, traces, videos, isolated project Timelines, and compiler
artifacts under ignored `outputs/playwright/`; no X11 display is required.

Editing source, changing a seed, restoring, and giving AI feedback are project commands. The interface stays locked while their correlated Timeline events arrive and unlocks only after the command response installs the authoritative complete project resource. The live delivery adapter is process-local, matching the single Node process and local project directory used by the app; durable catch-up survives browser reconnections and server restarts. Manual source is retained even when it fails compilation, with no stale visualization paired to it. AI source remains an unaccepted candidate until it compiles. A source or pipeline failure permits exactly one explicit repair generation and compile; provider retries are disabled, infrastructure failures are not sent back for repair, and there is no internal retry loop. A failed attempt and its terminal notice remain immutable Timeline events.

The v1 Timeline event types are:

- project lifecycle: `project.created`, `project.renamed`;
- input and response: `feedback.submitted`, `assistant.responded`, `system.notified`;
- AI audit: `ai.generation-requested`, `ai.generation-succeeded`, `ai.generation-failed`;
- artifact state: `artifact.version-created`;
- rendering and compilation: `compilation.requested`, `compilation.succeeded`, `compilation.failed`, `visualization.rendered`.

The schema deliberately remains version 1 while the product is refined. Valibot schemas are the source of the TypeScript event, command, and transport types, and event IDs must be contiguous from 1. Historical state is derived by a pure fold over the prefix ending at the selected event. Every event must be added to the aggregate event schema and exhaustively handled by the state projection, Timeline presentation, AI timeline index, and AI conversation projection; TypeScript reports a missing case. Concurrent mutations include the expected numeric head so a stale command cannot overwrite a newer result. The client loads the lossless resource from `GET /api/projects/:projectId`, submits discriminated JSON commands to `POST /api/projects/:projectId`, and follows durable complete events from `GET /api/projects/:projectId/events?after=<event-id>`. The URL's `at` parameter is a client-owned history cursor and does not alter the resource request.

The devcontainer post-create step updates Cabal's package index and prepares `compile-app` with the repository Cabal config before the first browser-triggered regeneration; it does not need to produce visualization JSON. That config explicitly places the package index and logs under `.cache/cabal` and the store and world file under `.local/state/cabal`; the devcontainer mounts both as persistent workspace-local volumes and points HLS at the workspace-local XDG cache. Every package script passes the config explicitly, so sandboxed commands do not fall back to `/root/.cache/cabal` even when an inherited environment variable is absent. Rebuild or reopen an existing devcontainer once after this change so its long-lived processes inherit the new XDG paths. Web regeneration has a server-side timeout controlled by `SVERLIN_COMPILE_TIMEOUT_MS`; it defaults to `300000` milliseconds, and the devcontainer sets that value explicitly.

### Configure the AI assistant

Project feedback calls OpenAI from the SvelteKit backend using the official JavaScript SDK and the Responses API. Set the server-only key before starting the app (copy `.env.example` to `.env`):

```sh
OPENAI_API_KEY=your_api_key_here
```

`OPENAI_MODEL` is optional and defaults to the fast, lower-cost coding model `gpt-5.6-luna`; `CHATBOT_CONFIG` defaults to the provider-neutral `ai-assistant` bot. The default authoring request uses low reasoning effort and a 12,000-token shared reasoning/output budget so complete Sverlin source fits without routinely exhausting the response. `CHATBOT_REQUEST_TIMEOUT_MS` defaults to `180000`. The SDK is configured with zero provider retries. The key is never sent to the browser. Bot definitions live under `src/lib/server/chat-bots/`; each defines its initial prompt, context builder, model parameters, and strict structured response contract. The public `LinearTrace.Choreography` facade owns the canonical Haddock description for every exposed DSL name. `pnpm run generate:dsl-api-index` combines those descriptions with GHC-inferred signatures in the assistant's compact `dsl-api-index.md`, while `dsl-interface.md` supplies composition rules and examples. The server reads both documents for every model request, so a running development server uses saved guide and generated-index changes without a restart; bundled copies remain available in packaged deployments. `pnpm run lint` rejects undocumented facade exports and stale generated output. Provider adapters live separately under `src/lib/server/chat-adapters/`, so testing another model or service does not require changing project orchestration.

The chatbot receives the current source workspace, a compact body-free index of the complete Timeline, conversation messages derived from feedback and assistant-response events, and expanded event/workspace or visual details only for references explicitly selected by the user. It never receives an arbitrary “last N” window. Unselected provider prompts, responses, compiler streams, and render bodies remain in the durable project but are represented to the model only by compact metadata and hashes. Exact provider prompts and responses are retained for later prompt evaluation without being recursively embedded in future contexts. `CHATBOT_MAX_CONTEXT_CHARS` (default `500000`) is only a guard against exceeding the provider context; it fails explicitly rather than dropping history. The source editor uses a small Svelte 5 runes adapter over modular CodeMirror 6.

## Frontend Checks

```sh
pnpm run check
pnpm run lint
pnpm run test
```

`pnpm run test:unit -- --run` is the fast TypeScript suite. `pnpm run test`
runs that suite and then compiles every catalogued `.sverlin` example through
the production boundary at fixed test seeds. Keep `pnpm run test:e2e` separate
because it starts a browser and an isolated application server.

For browser-level mode, diagnostics, playback, and rendering checks, install the
headless Chromium build once and run Playwright:

```sh
PLAYWRIGHT_BROWSERS_PATH=.cache/ms-playwright pnpm exec playwright install chromium
pnpm run test:e2e
```

## Haskell Checks

After changing Haskell source:

```sh
pnpm run compile -- --source examples/Minimal.sverlin --seed 1
pnpm run test:sverlin-source
pnpm run test:solver
pnpm run lint:haskell
pnpm run check:dsl-api-index
```

Before finishing Haskell edits, run the same formatter pipeline used by the editor:

```sh
pnpm run format:haskell
```

`stylish-haskell -i` should be the final source-modifying formatter pass.

When changing the public DSL, edit the facade export and its adjacent Haddock
description together, then run `pnpm run generate:dsl-api-index`. Do not edit the
generated assistant index directly. The generated Markdown is also a human-facing
reference, and `pnpm run lint` checks that it remains synchronized.
`pnpm run show:dsl-api` prints the same names, compiled signatures, categories,
and descriptions as JSON for other indexers and documentation tooling. The
facade comments use standard Haddock markup, so the same contract is ready for a
future published Haddock site.

## DSL Notes

- The `visualization` body is the persistent canvas root: root-level `width`, `height`, `aspectRatio`, `padding`, `contentFit`, and style declarations configure it. `aspectRatio 16 9` is affine: one explicit axis derives the other, content-driven auto-sizing hugs the limiting axis, and an empty canvas becomes 800×450 inside the normal 800×600 envelope. The AI authoring helper prefers 16:9 for an unspecified fixed presentation format but retains natural content-driven proportions for lists, tables, and diagrams. Under the default `Hug` fit, omitted axes hug retained children up to 800×600 layout units, while explicit dimensions may be as large as 4096 units per axis. `node selected $ do ...` declares selected trace leaves, while `Selected parent <- node $ do ...` creates a recursively nestable structural parent whose nested node declarations are its children. Generated parents are ordinary handles; they default to affine `Hug` fit and are transparent unless styled. `contentFit` permits extra room, `padding`/`margin` use `uniform`, `symmetric`, or four-edge `edges`, and `xAt`/`yAt`/`widthOf`/`heightOf` express percentages of the parent content box. Every style field cascades from parents unless a child explicitly overrides or forbids it. `content` keeps an authored `FontSize` fixed; with `fitText`, an omitted size means maximum feasible fit and an authored size is a cap. Verbatim code composes as `highlightCode "haskell" (codeWrap (codeContent "..."))`. `style @Field ...` requires a field, `withoutStyle @Field` forbids it, omission delegates it to the automatic family profile, and `styleCase @Field choice` controls conditional presence. Selected style constraints use `styleOf @Field selected` and therefore require guaranteed presence. Numeric variables use `variable @Span`/`variable @Angle`; categorical variables use `choice @FontFamily`. Substantially different numeric compositions use `oneOf`; `caseOf` connects an existing typed choice to numeric visual constraints.
