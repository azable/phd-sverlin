# Sverlin

Sverlin is a SvelteKit research application for building and reviewing event-sourced visualizations. A Haskell compiler interprets the Sverlin DSL, solves the layout, and produces the visualization data displayed by the browser.

Each project is an immutable Timeline stored in PostgreSQL together with authentication, ownership, and content-addressed compiler resources. The SvelteKit server accepts a project operation into that Timeline, executes it asynchronously in the same process, and records a terminal success or failure event. Queue mechanics and compiler implementation details are not part of the browser API.

## Local development

The recommended environment is the checked-in devcontainer. It uses the root [`Dockerfile`](Dockerfile), while [`compose.yaml`](compose.yaml) adds PostgreSQL and Docker-managed volumes for dependencies and build caches. Source remains bind-mounted for host and container editors. The official Docker-in-Docker feature provides an isolated daemon for container checks without exposing the host Docker socket.

### 1. Prepare the environment

On macOS with the beta Docker VMM, first add this repository (or a parent directory) explicitly under **Docker Desktop → Settings → Resources → File Sharing**; Docker VMM does not add bind-mounted paths automatically. Keep Docker Desktop current because Docker VMM and its VirtioFS implementation are still evolving.

If `.env` does not already exist, copy [`.env.example`](.env.example) to `.env`
before creating the devcontainer. Keep personal values in `.env`; it is ignored by
Git. Do not overwrite an existing file.

```sh
cp .env.example .env
```

Start the host SSH agent and load any key needed by the repository, then in VS Code run **Dev Containers: Rebuild and Reopen in Container**. Post-create installs Node dependencies and migrates PostgreSQL; it does not compile project-owned Haskell source. The privileged local workspace and its `SYS_ADMIN`/seccomp settings support Docker-in-Docker and Bubblewrap, so run only trusted repository code there.

If the container is already current, rerun individual setup steps when needed:

```sh
pnpm install --frozen-lockfile
pnpm run db:migrate
```

### 2. Start the application

Start the application:

```sh
pnpm run dev
```

The first run prepares project-owned compiler source, then starts the SvelteKit server. The server owns both HTTP handling and the bounded asynchronous operation executor. To skip preparation when the compiler is already current, run:

```sh
pnpm run dev:web
```

Open <http://localhost:5173>. VS Code notifies when the port is available but does not open browser windows automatically.

### 3. Create the administrator

Open <http://localhost:5173>. When the database has no administrator, the app opens
the one-time setup page automatically. Register an administrator passkey promptly:
until one exists, the first visitor to the deployment can claim administrator access.
Setup becomes unavailable after the administrator exists; sign in at `/login` with
the passkey already registered in the persistent PostgreSQL volume.

### 4. Test participant access

1. Sign in as the administrator and open `/admin`.
2. Create a participant ID and copy its generated password.
3. Open `/login` in a private/incognito window and enter those credentials.
4. Create a project and confirm that its Timeline reaches `operation.completed`.
5. Verify that the participant sees only their projects while the administrator can see all projects.

Passwords can be rotated from `/admin`; rotation and disabling an account revoke its active sessions.
The same page provides verified participant/study exports and explicitly
confirmed research-data deletion. Exports omit authentication secrets and
verify every immutable resource before download.

For debugging, administrators can also download an analysis export containing
all active projects, their safe owner labels, complete Timelines, and verified
resources. Operation outcomes are already contained in each Timeline. The equivalent local command writes the same
logical file tree as a readable directory:

```sh
pnpm run export:analysis
pnpm run export:analysis -- --project PROJECT_ID --output outputs/my-analysis
```

The default destination is a new UTC-timestamped directory under
`outputs/project-analysis/`. The command refuses to overwrite an existing
directory. It reads PostgreSQL directly, so `DATABASE_URL` must identify the
database to inspect.

AI feedback is optional. Set `OPENAI_API_KEY`, `OPENAI_MODEL`, and
`CHATBOT_CONFIG` in the root `.env`, then rebuild or recreate the devcontainer so
Compose passes them to the web process. Normal project compilation
does not require an OpenAI key.

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
  -> SvelteKit validates ownership and appends operation.accepted
  -> bounded in-process executor runs the project operation asynchronously
  -> public compiler service receives .sverlin content and seed(s)
  -> private compiler implementation runs in isolated scratch space
  -> PostgreSQL receives immutable Timeline events and content-addressed resources
  -> operation.completed or operation.failed closes the Timeline boundary
  -> browser polls only the Timeline until complete
```

The root container files have distinct responsibilities:

| File                                                                 | Responsibility                                                                               |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| [`Dockerfile`](Dockerfile)                                           | Shared development, build, verification, and Render runtime image targets.                   |
| [`compose.yaml`](compose.yaml)                                       | Local workspace, PostgreSQL service, and persistent volumes.                                 |
| [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json) | Attaches the editor, installs development features including Docker, and runs project setup. |

These definitions overlap intentionally: the Dockerfile owns the image, Compose owns the local multi-service topology, and the devcontainer owns the editor experience.

The production `runtime` target is separate from the development and
verification stages. It uses the official slim Haskell image and includes only
the Node server, runtime libraries, prepared Sverlin compiler, solver, and the
GHC package data required to interpret generated Sverlin source. HLS, Haskell
formatters and linters, browser dependencies, C/C++/Fortran build tools, Git,
pnpm, and executable/test build trees remain in discarded development or build
stages and are not shipped to staging or production. The two in-place Haskell
libraries retain only their registered library artifacts.

## Project layout

| Path                                 | Responsibility                                                                                        |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| [`src/lib/shared/`](src/lib/shared/) | Environment-neutral event schemas, projections, project contracts, and generated visualization types. |
| [`src/lib/client/`](src/lib/client/) | Svelte UI, project sessions, Timeline presentation, and visualization playback.                       |
| [`src/lib/server/`](src/lib/server/) | Better Auth, authorization, PostgreSQL persistence, operations, AI providers, and compiler execution. |
| [`src/routes/`](src/routes/)         | SvelteKit pages and authenticated APIs.                                                               |
| [`compile/src/`](compile/src/)       | Reusable Haskell libraries and the public `Solver`/choreography APIs.                                 |
| [`compile/app/`](compile/app/)       | Executable-only Sverlin loading, compilation, and generated-type tools.                               |
| [`examples/`](examples/)             | Catalogued `.sverlin` examples and the minimal starting template.                                     |

The TypeScript boundaries are one-way: `shared` may be used everywhere, `client` owns browser-only behavior, and `server` owns secrets and persistence. ESLint enforces this separation.

## Compile from the command line

Compile the minimal example with a deterministic seed:

```sh
pnpm run compile -- --source examples/Minimal.sverlin --seed 1
```

Seeded commands write beneath `outputs/seed-<seed>/`. Use `--output FILE` for an explicit destination or when omitting `--seed`; add `--details` for phase timings or `--count N` to sample multiple consecutive seeds from one prepared design space.

```sh
pnpm run compile -- \
  --source examples/Search.sverlin \
  --seed 42 \
  --details
```

Run `pnpm run prepare:compiler` after changing compiler inputs. Preparation and execution use coordinated locks, so an executable cannot be rebuilt underneath an active compile. Source input is trusted Haskell-based authoring input, not a hostile-code sandbox.

See [`examples/README.md`](examples/README.md) for the example catalogue.

## Command reference

These tables cover the common local scripts. Pass script-specific arguments after `--`, for example `pnpm run compile -- --source examples/Minimal.sverlin --seed 1`.

### Development and runtime

| Command                      | Purpose                                                            |
| ---------------------------- | ------------------------------------------------------------------ |
| `pnpm run dev`               | Prepare the compiler, then run the complete SvelteKit service.     |
| `pnpm run dev:web`           | Run the SvelteKit service without preparing the compiler first.    |
| `pnpm run preview`           | Prepare the compiler and preview the production frontend locally.  |
| `pnpm run start`             | Start the built adapter-node web service.                          |
| `pnpm run build`             | Prepare the compiler and build the web and migration bundles.      |
| `pnpm run build:analysis`    | Build the local PostgreSQL analysis-export command.                |
| `pnpm run build:migrate`     | Build only `build-migrate/index.js`.                               |
| `pnpm run prepare`           | Internal package lifecycle hook that synchronizes SvelteKit types. |
| `pnpm run prepare:compiler`  | Build and fingerprint the direct Haskell compiler executable.      |
| `pnpm run compile -- <args>` | Compile a `.sverlin` source through the prepared executable.       |

### Database, data, and operations

| Command                              | Purpose                                                  |
| ------------------------------------ | -------------------------------------------------------- |
| `pnpm run db:generate`               | Generate a Drizzle migration from the TypeScript schema. |
| `pnpm run db:migrate`                | Apply checked-in Drizzle migrations to `DATABASE_URL`.   |
| `pnpm run export:analysis -- <args>` | Export active projects for local analysis.               |

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
| `pnpm run test`                | Run unit, PostgreSQL, and catalogued compiler-example tests.           |
| `pnpm run test:examples`       | Compile every catalogued example through the production boundary.      |
| `pnpm run test:e2e`            | Run Playwright against temporary PostgreSQL and the SvelteKit service. |
| `pnpm run test:sverlin-source` | Run the Haskell source/elaboration tests.                              |
| `pnpm run test:solver`         | Run direct solver tests against stable fixtures.                       |
| `pnpm run bench:solver`        | Benchmark solver lowering and execution on stable fixtures.            |

Unit tests replace the narrow persistence, compiler, and chatbot interfaces with
in-memory fakes. Focused integration and Playwright tests create a uniquely named
PostgreSQL database, migrate it, and force-drop only that validated test database
afterward. The end-to-end authentication bypass seeds its matching administrator
row because project ownership remains enforced.

After Haskell changes, run the relevant compile, Haskell tests, solver tests, and HLint commands, then finish with `pnpm run format:haskell`. When the public DSL changes, update the facade Haddock descriptions and regenerate the DSL index. Do not edit the generated [`dsl-api-index.md`](src/lib/server/chat-bots/ai-assistant/dsl-api-index.md) by hand; cross-cutting guidance lives in [`dsl-interface.md`](src/lib/server/chat-bots/ai-assistant/dsl-interface.md).

## Production deployment

[`render.yaml`](render.yaml) is a Render [Blueprint](https://render.com/docs/infrastructure-as-code) for one 4 GiB web service and one managed PostgreSQL database in Singapore. Connect the repository as a new Blueprint in the Render dashboard; no deployment CLI is required. Automatic deploys are disabled so a study is not restarted by an unrelated commit; deploy deliberately from the Render dashboard outside active sessions.

The web service runs checked-in migrations before each deploy and exposes `/api/health/ready` as its health check. Render generates the Better Auth secret. When a fresh database has no administrator, opening the generated `onrender.com` URL redirects to one-time passkey setup; complete it promptly because the first visitor can claim administrator access. Better Auth derives the public origin from Render's `RENDER_EXTERNAL_HOSTNAME`; set `BETTER_AUTH_URL` explicitly only when using a custom domain.

The web service keeps the established 4 GiB ceiling because it owns compilation and the native solver. It accepts at most two project operations concurrently and serializes compiler invocations to bound peak memory for the expected couple of simultaneous users. Render allows at most 300 seconds for graceful shutdown, so application work is cancelled after 270 seconds, leaving 30 seconds to record failure boundaries and close PostgreSQL. An operation interrupted by an unexpected restart is marked cancelled and must be retried; already committed project events and resources remain durable. PostgreSQL stores resource bytes directly and each immutable resource is limited to 16 MiB. Add `OPENAI_API_KEY` to the web service when AI-assisted editing is required; `OPENAI_MODEL` and `CHATBOT_CONFIG` are optional overrides.

## Agent tooling

Repository-local skills under [`.agents/skills/`](.agents/skills/) provide authentication, Svelte 5, and shadcn-svelte guidance in trusted clones. [`AGENTS.md`](AGENTS.md) contains the complete engineering and verification rules.
