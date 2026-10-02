# Sverlin

Sverlin is a SvelteKit research application for building and reviewing event-sourced visualizations. Its renderer-neutral service accepts authoring input and produces one or more steppable presentations; projects can use either compiled Sverlin source or script-free HTML frames.

Each project is an immutable Timeline stored in PostgreSQL together with authentication, ownership, and content-addressed compiler resources. The SvelteKit server accepts a project operation into that Timeline, executes it asynchronously in the same process, and records a terminal success or failure event. Queue mechanics and compiler implementation details are not part of the browser API.

## Local development

Development runs natively through [devenv](https://devenv.sh/): [`devenv.nix`](devenv.nix) supplies the pinned Nix toolchain and manages PostgreSQL and the application processes, while [`devenv.lock`](devenv.lock) pins the package sources. The root [`Dockerfile`](Dockerfile) remains production-only.

### 1. Prepare the environment

Install [Nix](https://nixos.org/download/), [devenv](https://devenv.sh/getting-started/installation/), and [direnv](https://direnv.net/). Everything the project builds against — GHC, HiGHS, Node 24, pnpm 10, PostgreSQL 17, and the editor tools — comes from `devenv.nix`, so those three are the only host prerequisites.

Allow direnv once per clone so the checked-in [`.envrc`](.envrc) activates devenv for terminals and the VS Code extension host. Entering the environment starts no services.

```sh
direnv allow
```

If `.env` does not already exist, copy [`.env.example`](.env.example) to `.env`
before entering the shell. Keep personal values in `.env`; it is ignored by
Git. Do not overwrite an existing file.

```sh
cp .env.example .env
```

Without direnv, prefix commands with `devenv shell --`, for example `devenv shell -- pnpm run lint`.

The environment includes the [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [OpenCode](https://opencode.ai/) coding-agent CLIs (`claude-code` is unfree, so [`devenv.yaml`](devenv.yaml) permits that one package). `devenv.nix` points `XDG_DATA_HOME` at the ignored `.local/share/`, so their history stays inside the checkout and must be set up once per clone by running `claude` or `opencode auth login`. Each reads its ordinary host configuration from `~/.config/`.

[Editor settings](.vscode/settings.json) use HLS from `PATH` and leave Haskell formatting to `pnpm run format:haskell`, since HLS applies one formatter and that pipeline is Hindent followed by Stylish Haskell. Formatting on save is off for Cabal files too, whose HLS default is `cabal-gild`, a formatter the environment does not provide. devenv generates the matching [extension recommendations](.vscode/extensions.json).

On its first activation the Haskell extension asks how it should find HLS, before it reads this workspace's `haskell.manageHLS`, so answer `Manually via PATH`. Answering `Automatically via GHCup` instead fails with `Project requires GHCup but it isn't installed`: decline that install, because `devenv.nix` already supplies `haskell-language-server` built against the project's GHC, then run `Developer: Reload Window` to pick the setting up. The extension's `Haskell` output channel logs the `PATH` it searched, which confirms whether the devenv environment reached the extension host.

### 2. Start the application

Start everything with one command:

```sh
devenv up
```

This installs locked Node dependencies, starts PostgreSQL, waits until it is ready, applies pending migrations, prepares the compiler, and then starts SvelteKit on <http://localhost:5173>. Keeping that origin stable preserves Better Auth passkey identity.

Dependency installation, migration, and compiler preparation are devenv tasks (`sverlin:setup`, `sverlin:migrate`, `sverlin:compiler`) rather than steps inside the service, so the `web` process owns only the server and its `/api/health/ready` probe reports the service instead of the build. Applied migrations are recorded in PostgreSQL, so subsequent starts only check for new ones. The first compiler preparation builds Stack dependencies and takes considerably longer than later starts.

Use `devenv down` to stop managed processes. A foreground `devenv up` started from scratch also stops them with Ctrl+C; attaching to an already-running manager only detaches on Ctrl+C. For database-backed tests or a manually controlled application, start only PostgreSQL:

```sh
devenv up -d postgres
pnpm run dev
```

`pnpm run dev` chains migration, compiler preparation, and the server, so it remains the entry point for tooling that does not go through devenv. Use `pnpm run dev:web` when migrations and compiler preparation are already current. Stop any existing application before starting another server; the server lock protects the checkout's operation state.

PostgreSQL 17 stores data in the checkout at `.devenv/state/postgres`, which survives restarts. The development role has `CREATEDB` for isolated test databases. PostgreSQL listens on `127.0.0.1` only, and devenv supplies the matching `DATABASE_URL`. An explicit `DATABASE_URL` in `.env` instead selects an external database for application commands.

The shell loads `.env` at runtime as trusted shell-compatible assignments, avoiding devenv's [dotenv integration](https://devenv.sh/integrations/dotenv/), which copies the file into the Nix store. Direnv reloads after `.env` changes; restart managed processes so they receive the new values. Dependencies and build caches live in the ignored `node_modules`, `.cache`, and Stack `.stack-work` directories; application state lives in `.local`. Do not delete `.devenv/state/postgres` as a cache-cleanup step.

### 3. Create the administrator

Open <http://localhost:5173>. When the database has no administrator, the app opens
the one-time setup page automatically. Register an administrator passkey promptly:
until one exists, the first visitor to the deployment can claim administrator access.
Setup becomes unavailable after the administrator exists; sign in at `/login` with
the passkey already registered in the persistent PostgreSQL database.

### 4. Test participant access

1. Sign in as the administrator and open `/admin`.
2. Create a participant ID, select an open study version, copy its generated password, and assign its static HTTPS gift-card URL. The exact study/version and counterbalanced arm cannot be reassigned afterward.
3. Confirm that the participant initially shows **Not started** with every configured phase unfilled. The same flow fills as the participant progresses and is marked **Completed** at the terminal phase.
4. From a configured-study card, create either a full-flow preview or an isolated phase preview. Choose the arm explicitly; full-flow previews can be advanced without waiting for task timers, while isolated previews stop after their selected phase.
5. Open `/login` in a private/incognito window and enter the participant credentials.
6. Continue from the welcome screen into the first timed task, request a visualization, and confirm that its generated candidate bubbles appear.
7. Verify that expiry locks the task and opens a blocking dialog whose Continue action advances to the counterbalanced second renderer. A task with `allowEarlyCompletion` enabled in its immutable study definition also offers a confirmed early-finish action that immediately locks it.
8. Verify that the participant Timeline shows separate user, assistant, and visualization bubbles. Selecting a visualization should activate it; in comparison mode, Shift-select two compatible bubbles to compare them.
9. Open a participant task from its admin flow. The project must be read-only, and participant-authored messages must use the participant ID rather than “You”. Only password/access changes, gift-card management, exports, and explicitly confirmed purges are administrative mutations.

Passwords can be rotated from `/admin`; rotation and disabling an account revoke its active sessions.
The same page provides verified participant, exact-version study, all-study, and all-project
downloads alongside explicitly confirmed participant-data deletion. Every delivery path uses
the same snapshot, manifest, path-safety, and immutable-resource verification pipeline. Study
and participant downloads select projects through study phase links, include the registered
definitions plus complete projected flows, and exclude administrator previews and unrelated
participant-owned projects. The all-project download includes active administrator projects and
previews. Gift-card URLs are operational data and are omitted from every data download.

The local command mirrors those administrator downloads, including scope resolution, operation
guards, snapshots, filenames, and verification, but writes a readable directory:

```sh
pnpm run export:data -- --scope projects
pnpm run export:data -- --scope projects --project PROJECT_ID --output outputs/my-project
pnpm run export:data -- --scope participant --participant PARTICIPANT_ID
pnpm run export:data -- --scope study --study main-study --version 1
pnpm run export:data -- --scope study
```

The default destination is a new UTC-timestamped directory under
`outputs/data-export/`. The command refuses to overwrite an existing
directory. It reads PostgreSQL directly, so `DATABASE_URL` must identify the
database to inspect.

Set `OPENAI_API_KEY` in the root `.env` for AI-assisted editing and the HTML study condition. New blank projects in both modes begin with the same three-turn intake covering the algorithm, target cohort and learning outcomes, then visual style or a request for options. The scripted questions are Timeline events and do not invoke visualization generation. A Luna low-reasoning classifier is used after the first two answers only to recognize an explicit refusal or request to skip the remaining intake; its 200-token ceiling is deliberately small because its strict response has only two values. A classifier failure is recorded and safely advances the intake without displaying an error. Existing projects and projects created from a populated template do not acquire this gate retroactively.

The visualization mode selects its compatible assistant implicitly, and the resolved assistant ID is copied into every project’s immutable creation event. Model choice belongs to that agent definition: generation starts with Luna at low reasoning, escalates through three Sol repair profiles, and may make one final Sol simplification pass. This follows [OpenAI's GPT-5.6 role guidance](https://developers.openai.com/api/docs/guides/upgrading-to-gpt-5p6-sol). Provider retries remain disabled, so every model call is an explicit, recorded Timeline attempt. Compiling already-authored Sverlin source does not require an OpenAI key.

In Sverlin comparison mode, selections in the top and bottom candidates remain active together and become exact feedback context. Feedback and preferences are recorded immediately, then durably queued for one background assistant turn per project; interactions submitted while a turn is running are combined into the next turn. The participant can keep chatting, selecting, and comparing the current pair during generation. The assistant revises source when accumulated evidence supports a concrete change, may ask a more granular question with clickable element references, and otherwise records an observation without advancing candidates. Explicit requests for more alternatives resample the accepted source.

`CHATBOT_REQUEST_TIMEOUT_MS` defaults to 180,000 ms (three minutes). A timed study operation may begin a subsequent repair or simplification only when that complete allowance remains, and in-flight AI or compiler work is cancelled at the phase deadline. This keeps the five-call ceiling inside the 15-minute task phase while allowing standalone administrator projects to use the normal per-request timeout.

### Health checks

```sh
curl http://localhost:5173/api/health/live
curl http://localhost:5173/api/health/ready
curl http://localhost:5173/api/version
```

The authenticated `POST /api/health/compiler` endpoint performs a real minimal compilation for a signed-in operator.

## How the pieces fit together

```text
authenticated browser
  -> SvelteKit authorizes and returns the participant's complete project Timeline
  -> study service resolves the centrally defined phase, renderer, layout, and deadline
  -> project command appends operation.accepted
  -> feedback/preferences are recorded and queued without waiting for generation
  -> bounded in-process executor claims queued interactions for a background assistant turn
  -> Sverlin prompts compile one scenario with one or two fresh view seeds in one process; HTML prompts may return one safe manifest
  -> the resulting presentation set enters the Timeline directly
  -> PostgreSQL receives immutable Timeline events and content-addressed resources
  -> operation.completed or operation.failed closes the Timeline boundary
  -> browser polls Timeline deltas and locally derives participant conversation or Developer detail
```

The environment and deployment files have distinct responsibilities:

| File                                                       | Responsibility                                                                                |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| [`devenv.nix`](devenv.nix)                                 | Development toolchain, generated editor configuration, PostgreSQL, and application processes. |
| [`devenv.yaml`](devenv.yaml), [`devenv.lock`](devenv.lock) | Package sources and their reproducible revisions.                                             |
| [`.envrc`](.envrc)                                         | Direnv activation for terminals and the VS Code extension host.                               |
| [`Dockerfile`](Dockerfile)                                 | Production build, verification, and Render runtime image targets.                             |

GHC and HiGHS versions are aligned between devenv and the production image. Stack's existing [snapshot](compile/stack.yaml) owns Haskell dependencies. Nix pins Node 24, pnpm 10, editor tools, and native libraries, while the Dockerfile pins its separate production Linux toolchain.

The production `runtime` target is separate from the build and
verification stages. It uses the official slim Haskell image and includes only
the Node server, runtime libraries, prepared Sverlin compiler, solver, and the
GHC package data required to interpret generated Sverlin source. Editor tools
belong to devenv; C/C++/Fortran build tools, Git, pnpm, and executable/test
build trees remain in discarded build stages. The two in-place Haskell
libraries retain only their registered library artifacts.

## Project layout

| Path                                                         | Responsibility                                                                                                           |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| [`src/lib/shared/`](src/lib/shared/)                         | Environment-neutral event schemas, projections, project contracts, and generated visualization types.                    |
| [`src/lib/client/`](src/lib/client/)                         | Svelte UI, project sessions, Timeline presentation, and visualization playback.                                          |
| [`src/lib/server/`](src/lib/server/)                         | Better Auth, authorization, PostgreSQL persistence, operations, AI providers, and compiler execution.                    |
| [`src/routes/`](src/routes/)                                 | SvelteKit pages and authenticated APIs.                                                                                  |
| [`compile/src/Sverlin.hs`](compile/src/Sverlin.hs)           | Sole public facade imported by authored `.sverlin` source.                                                               |
| [`compile/src/Sverlin/`](compile/src/Sverlin/)               | Compiler-owned Domain, Program, Render, typography, output contracts, generated-source host, and linear Prelude support. |
| [`compile/src/Sverlin/Output/`](compile/src/Sverlin/Output/) | Versioned visualization IR, content-addressed resources, and output-target packaging.                                    |
| [`compile/src/Solver.hs`](compile/src/Solver.hs)             | Stable solver facade; sibling `Solver/` modules are its private implementation.                                          |
| [`compile/app/`](compile/app/)                               | Executable-only source elaboration, interpretation, compilation, and generated-type tools.                               |
| [`examples/`](examples/)                                     | Catalogued `.sverlin` examples and the minimal starting template.                                                        |

The TypeScript boundaries are one-way: `shared` may be used everywhere, `client` owns browser-only behavior, and `server` owns secrets and persistence. ESLint enforces this separation. Study protocols are registered by ID and version in [`src/lib/shared/study/registry.ts`](src/lib/shared/study/registry.ts); the active protocol in [`src/lib/shared/study/main-v1.ts`](src/lib/shared/study/main-v1.ts) centrally defines timing, counterbalance order, renderer, and workspace layout.

## Compile from the command line

Compile the minimal example with a deterministic seed:

```sh
pnpm run compile -- --source examples/Minimal.sverlin --seed 1
```

Seeded commands write beneath `outputs/seed-<seed>/`. The `--seed` value selects the scenario and its first view. Repeat `--view-seed INT` to sample additional presentations of that same input and trace in the same compiler process. `--count N` is the convenience form for consecutive view seeds beginning at `--seed`; it cannot be combined with explicit `--view-seed` values. A batch reuses prepared affine regions but samples a fresh layout for every view. Use `--output FILE` for an explicit destination or when omitting `--seed`, and add `--details` for phase timings and workload counts. The visualization service stores the same structured measurements in compilation Timeline events, including its own queue, process, validation, and cleanup times. Historical events without metrics remain valid.

```sh
pnpm run compile -- \
  --source examples/LinearSearch.sverlin \
  --seed 42 \
  --view-seed 91 \
  --details
```

Run `pnpm run prepare:compiler` after changing compiler inputs. Preparation and execution use coordinated locks, so an executable cannot be rebuilt underneath an active compile. Source input is trusted Haskell-based authoring input, not a hostile-code sandbox.

In authored source, `content` without an explicit `FontSize` samples a single-line text size constrained by the node's width and height. An implicit Hug height follows the visible glyph bounds plus padding; an explicit height only has to contain the glyphs. An explicit `style @FontSize` pins or bounds text size. The [text lowering](compile/src/Sverlin/Internal/Render/Compile.hs) and [typography preparation](compile/src/Sverlin/Internal/Render/Typography.hs) define these relationships.

Project templates are registered in [`examples/catalog.json`](examples/catalog.json). To add one, add its `.sverlin` source, one unique catalog entry, and a focused assertion when it introduces new behavior. Catalog validation rejects missing, duplicate, and unregistered sources so the creation menu and compiler-example suite stay aligned.

In local development, administrators can open the [Examples page](src/routes/examples/+page.svelte) from Projects to compile a catalogued source directly, without creating a project or using chat. The preview has step controls, source inspection, and a seed in its URL for repeatable layouts. Saving the selected `.sverlin` file recompiles the preview with that seed; a failed compile leaves the last successful view visible. After changing Haskell compiler inputs, run `pnpm run prepare:compiler`, then use **Retry** on the page. The direct preview uses the same bounded [compiler service](src/lib/server/compiler/index.ts) as projects.

## Command reference

These tables cover the common local scripts. Pass script-specific arguments after `--`, for example `pnpm run compile -- --source examples/Minimal.sverlin --seed 1`.

### Development and runtime

| Command                             | Purpose                                                                    |
| ----------------------------------- | -------------------------------------------------------------------------- |
| `devenv tasks run sverlin:setup`    | Install locked Node dependencies.                                          |
| `devenv up`                         | Run setup, migration, and compiler tasks, then PostgreSQL and the service. |
| `devenv up -d postgres`             | Start only PostgreSQL in the background.                                   |
| `devenv tasks run sverlin:migrate`  | Apply pending migrations against the managed database.                     |
| `devenv tasks run sverlin:compiler` | Build and fingerprint the compiler through devenv.                         |
| `devenv down`                       | Stop managed processes while retaining database data.                      |
| `pnpm run dev`                      | Apply migrations, prepare the compiler, then run the service.              |
| `pnpm run dev:web`                  | Run the service without migrating or preparing the compiler first.         |
| `pnpm run preview`                  | Prepare the compiler and preview the production frontend locally.          |
| `pnpm run start`                    | Start the built adapter-node web service.                                  |
| `pnpm run build`                    | Prepare the compiler and build the web and migration bundles.              |
| `pnpm run build:data`               | Build the canonical local PostgreSQL data-export command.                  |
| `pnpm run build:migrate`            | Build only `build-migrate/index.js`.                                       |
| `pnpm run prepare`                  | Internal package lifecycle hook that synchronizes SvelteKit types.         |
| `pnpm run prepare:compiler`         | Build and fingerprint the direct Haskell compiler executable.              |
| `pnpm run compile -- <args>`        | Compile a `.sverlin` source through the prepared executable.               |

### Database, data, and operations

| Command                          | Purpose                                                  |
| -------------------------------- | -------------------------------------------------------- |
| `pnpm run db:generate`           | Generate a Drizzle migration from the TypeScript schema. |
| `pnpm run db:migrate`            | Apply checked-in Drizzle migrations to `DATABASE_URL`.   |
| `pnpm run export:data -- <args>` | Export project, participant, or study data.              |

### Checks, generation, and formatting

| Command                                 | Purpose                                                        |
| --------------------------------------- | -------------------------------------------------------------- |
| `pnpm run check`                        | Run Svelte and TypeScript diagnostics.                         |
| `pnpm run check:watch`                  | Run Svelte diagnostics continuously.                           |
| `pnpm run lint`                         | Check formatting, ESLint, and generated-file consistency.      |
| `pnpm run lint:haskell`                 | Run HLint over all project-owned Haskell directories.          |
| `pnpm run format`                       | Format the repository with Prettier.                           |
| `pnpm run format:haskell`               | Run Hindent and then Stylish Haskell over Haskell sources.     |
| `pnpm run generate:dsl-api-index`       | Regenerate the model-facing public DSL reference.              |
| `pnpm run check:dsl-api-index`          | Verify public DSL documentation and generated-index freshness. |
| `pnpm run generate:visualization-types` | Regenerate TypeScript visualization IR types from Haskell.     |
| `pnpm run check:visualization-types`    | Verify visualization types without modifying the working tree. |

### Tests and benchmarks

| Command                        | Purpose                                                                |
| ------------------------------ | ---------------------------------------------------------------------- |
| `pnpm run test:unit`           | Run the fast TypeScript suite once.                                    |
| `pnpm run test:postgres`       | Run focused persistence tests in a temporary database.                 |
| `pnpm run test`                | Run unit, compiler, PostgreSQL, and catalogued compiler-example tests. |
| `pnpm run test:compiler`       | Run the current Haskell semantic and source/elaboration suites.        |
| `pnpm run test:examples`       | Compile every catalogued example through the production boundary.      |
| `pnpm run test:sverlin-source` | Run the Haskell source/elaboration tests.                              |
| `pnpm run test:solver`         | Run direct solver tests against stable fixtures.                       |
| `pnpm run bench:solver`        | Benchmark solver lowering and execution on stable fixtures.            |

Unit tests replace the narrow persistence, compiler, and chatbot interfaces with
in-memory fakes. PostgreSQL integration tests create a uniquely named
PostgreSQL database, migrate it, and force-drop only that validated test database
afterward. There is currently no automated E2E suite; manually verify affected
browser interactions after UI changes.

After Haskell changes, run the relevant compile, compiler tests, solver tests, and HLint commands, then finish with `pnpm run format:haskell`. When the public DSL changes, update the Haddock descriptions in the authored [`Sverlin` facade](compile/src/Sverlin.hs) and regenerate the DSL index. Do not edit the generated [`dsl-api-index.md`](src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md) by hand. The supplemental [`dsl-interface.md`](src/lib/server/chat-bots/sverlin-assistant/dsl-interface.md) intentionally contains only a neutral pointer to that generated reference; authoring policy belongs to the assistant configuration.

## Production deployment

[`render.yaml`](render.yaml) is a Render [Blueprint](https://render.com/docs/infrastructure-as-code) for one 4 GiB web service and one managed PostgreSQL database in Singapore. Connect the repository as a new Blueprint in the Render dashboard; no deployment CLI is required. Automatic deploys are disabled so a study is not restarted by an unrelated commit; deploy deliberately from the Render dashboard outside active sessions.

The web service runs checked-in migrations before each deploy and exposes `/api/health/ready` as its health check. Render generates the Better Auth secret. When a fresh database has no administrator, opening the generated `onrender.com` URL redirects to one-time passkey setup; complete it promptly because the first visitor can claim administrator access. Better Auth derives the public origin from Render's `RENDER_EXTERNAL_HOSTNAME`; set `BETTER_AUTH_URL` explicitly only when using a custom domain.

The web service keeps the established 4 GiB ceiling because it owns compilation and the native solver. It accepts at most two slow project operations concurrently, runs at most one assistant turn per project, and serializes compiler invocations to bound peak memory for the expected couple of simultaneous users. Short feedback and preference writes remain available during a turn. Render allows at most 300 seconds for graceful shutdown, so application work is cancelled after 270 seconds, leaving 30 seconds to record failure boundaries and close PostgreSQL. An interrupted claimed turn is marked cancelled rather than silently retried; unclaimed interactions remain durable and are scheduled after restart. PostgreSQL stores resource bytes directly and each immutable resource is limited to 16 MiB. Add `OPENAI_API_KEY` to the web service when AI-assisted editing is required. Assistant and model-profile selection are owned by the visualization mode and recorded in each project Timeline.

## Agent tooling

Repository-local skills under [`.agents/skills/`](.agents/skills/) provide authentication, Svelte 5, and shadcn-svelte guidance in trusted clones. [`AGENTS.md`](AGENTS.md) contains the complete engineering and verification rules.
