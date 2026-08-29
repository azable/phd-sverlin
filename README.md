# Sverlin

Sverlin is a SvelteKit research application for building and reviewing event-sourced visualizations. A Haskell compiler interprets the Sverlin DSL, solves the layout, and produces the visualization data displayed by the browser.

Each project is an immutable Timeline. In the production-style path, SvelteKit queues project commands through pg-boss and a separate worker performs AI generation and compilation. PostgreSQL stores authentication, ownership, events, and jobs; a private Railway Bucket stores immutable compiler resources.

## Local development

The recommended environment is the checked-in devcontainer. It uses the root [`Dockerfile`](Dockerfile), while [`compose.yaml`](compose.yaml) adds PostgreSQL and persistent development volumes. The repository source remains bind-mounted so host and container editors see the same files; high-churn generated data (`node_modules`, Stack's local-package work directories and package root, PostgreSQL, and application state) stays in Docker-managed named volumes instead of crossing the host filesystem boundary. The generated-data volumes mount under `/opt/sverlin-dev`, outside the workspace bind. A small post-create helper links only the conventional workspace paths that Node and Stack require (`node_modules` and each local package's `.stack-work`); Stack's package root is used directly through `STACK_ROOT`. This remains reliable when an editor or agent overlays the workspace mount. The official Docker-in-Docker feature provides an isolated Docker daemon, Buildx, and Compose for running the repository's container checks locally without exposing the host Docker socket.

### 1. Prepare the environment

On macOS with the beta Docker VMM, first add this repository (or a parent directory) explicitly under **Docker Desktop → Settings → Resources → File Sharing**; Docker VMM does not add bind-mounted paths automatically. Keep Docker Desktop current because Docker VMM and its VirtioFS implementation are still evolving.

Start the host SSH agent and load any key needed by the repository, then in VS Code run **Dev Containers: Rebuild and Reopen in Container**. Dev Containers forwards the active agent and copies the host Git configuration, so private SSH keys and `.gitconfig` are not bind-mounted into the workspace container. The image caches the pinned Stack snapshot; post-create installs Node dependencies into its named volume, seeds the persistent Stack package root when empty, and migrates PostgreSQL. It does not compile project-owned Haskell source. The development workspace receives `SYS_ADMIN` and an unconfined seccomp profile so Codex can use Bubblewrap inside the container. Docker-in-Docker also requires the workspace container to run privileged; its daemon and persistent data volumes are managed by the feature and remain separate from the host Docker daemon. These settings apply only to the local Compose workspace service, which should run trusted repository code.

If the container is already current, rerun individual setup steps when needed:

```sh
pnpm install --frozen-lockfile
pnpm run db:migrate
```

### 2. Start the application

Start the web app and durable project worker together:

```sh
pnpm run dev
```

The first run prepares project-owned compiler source, then pnpm prefixes the web and worker logs in one terminal. To run them separately instead:

```sh
pnpm run dev:web
pnpm run dev:worker
```

Open <http://localhost:5173>. VS Code notifies when the port is available but does not open browser windows automatically. Project mutations remain queued if only `dev:web` is running.

### 3. Create the administrator

For the default local Compose configuration, visit:

<http://localhost:5173/setup?token=development-setup-token>

Register an administrator passkey. Setup becomes unavailable after the administrator exists; if the route returns 404, sign in at `/login` with the passkey already registered in the persistent PostgreSQL volume.

### 4. Test participant access

1. Sign in as the administrator and open `/admin`.
2. Create a participant ID and copy its generated password.
3. Open `/login` in a private/incognito window and enter those credentials.
4. Create a project and confirm that the worker logs its job.
5. Verify that the participant sees only their projects while the administrator can see all projects.

Passwords can be rotated from `/admin`; rotation and disabling an account revoke its active sessions.
The same page provides verified participant/study exports and explicitly
confirmed research-data deletion. Exports omit authentication secrets and
verify every immutable resource before download.

AI feedback is optional and requires `OPENAI_API_KEY` in the worker environment:

```sh
export OPENAI_API_KEY=your_api_key_here
pnpm run dev
```

Normal project compilation does not require an OpenAI key.

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
  -> SvelteKit validates ownership and queues a command
  -> pg-boss stores and delivers the durable PostgreSQL job
  -> worker serializes commands for each project owner
  -> prepared Haskell compiler runs in isolated scratch space
  -> PostgreSQL receives immutable Timeline events
  -> Railway Bucket receives content-addressed resources
  -> browser polls the job and Timeline until complete
```

The root container files have distinct responsibilities:

| File                                                                 | Responsibility                                                                               |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| [`Dockerfile`](Dockerfile)                                           | Shared development, build, verification, and Railway runtime image targets.                  |
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

| Path                                 | Responsibility                                                                                         |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| [`src/lib/shared/`](src/lib/shared/) | Environment-neutral event schemas, projections, project contracts, and generated visualization types.  |
| [`src/lib/client/`](src/lib/client/) | Svelte UI, project sessions, Timeline presentation, and visualization playback.                        |
| [`src/lib/server/`](src/lib/server/) | Better Auth, authorization, PostgreSQL/Bucket persistence, jobs, AI providers, and compiler execution. |
| [`src/routes/`](src/routes/)         | SvelteKit pages and authenticated APIs.                                                                |
| [`compile/src/`](compile/src/)       | Reusable Haskell libraries and the public `Solver`/choreography APIs.                                  |
| [`compile/app/`](compile/app/)       | Executable-only Sverlin loading, compilation, and generated-type tools.                                |
| [`examples/`](examples/)             | Catalogued `.sverlin` examples and the minimal starting template.                                      |

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

See [`examples/README.md`](examples/README.md) for the example catalogue and [`docs/compiler-runtime.md`](docs/compiler-runtime.md) for compiler isolation, job recovery, and scaling limits.

## Command reference

These tables cover every script declared in `package.json`. Pass script-specific arguments after `--`, for example `pnpm run compile -- --source examples/Minimal.sverlin --seed 1`.

### Development and runtime

| Command                      | Purpose                                                                    |
| ---------------------------- | -------------------------------------------------------------------------- |
| `pnpm run dev`               | Prepare the compiler, then run the web app and PostgreSQL worker together. |
| `pnpm run dev:web`           | Run only the lock-protected Vite development server.                       |
| `pnpm run dev:worker`        | Run only the PostgreSQL project worker directly with TypeScript.           |
| `pnpm run worker:dev`        | Compatibility alias for `pnpm run dev:worker`.                             |
| `pnpm run preview`           | Prepare the compiler and preview the production frontend locally.          |
| `pnpm run start`             | Start the built adapter-node web service.                                  |
| `pnpm run start:worker`      | Start the built project worker.                                            |
| `pnpm run start:migrate`     | Apply migrations with the built migration entrypoint.                      |
| `pnpm run build`             | Prepare the compiler and build the web, worker, and migration bundles.     |
| `pnpm run build:worker`      | Build only `build-worker/index.js`.                                        |
| `pnpm run build:migrate`     | Build only `build-migrate/index.js`.                                       |
| `pnpm run prepare`           | Internal package lifecycle hook that synchronizes SvelteKit types.         |
| `pnpm run prepare:compiler`  | Build and fingerprint the direct Haskell compiler executable.              |
| `pnpm run stack -- <args>`   | Run Stack against the repository's pinned snapshot and package set.        |
| `pnpm run compile -- <args>` | Compile a `.sverlin` source through the prepared executable.               |

### Database, data, and operations

| Command                         | Purpose                                                          |
| ------------------------------- | ---------------------------------------------------------------- |
| `pnpm run db:generate`          | Generate a Drizzle migration from the TypeScript schema.         |
| `pnpm run db:migrate`           | Apply checked-in Drizzle migrations to `DATABASE_URL`.           |
| `pnpm run data:export`          | Export and verify the legacy/local file project repository.      |
| `pnpm run infra:plan`           | Plan the checked-in Railway TypeScript infrastructure changes.   |
| `pnpm run infra:apply`          | Apply a separately reviewed plan to the linked Railway project.  |
| `pnpm run smoke:deployment`     | Check a deployed service configured by `SVERLIN_SMOKE_URL`.      |
| `pnpm run app:lock -- "reason"` | Put local application mutations into read-only maintenance mode. |
| `pnpm run app:lock:status`      | Inspect the local maintenance lock.                              |
| `pnpm run app:unlock`           | Release the local maintenance lock.                              |

### Checks, generation, and formatting

| Command                                 | Purpose                                                        |
| --------------------------------------- | -------------------------------------------------------------- |
| `pnpm run check`                        | Run Svelte and TypeScript diagnostics.                         |
| `pnpm run check:watch`                  | Run Svelte diagnostics continuously.                           |
| `pnpm run lint`                         | Check Prettier, ESLint, and generated DSL-index consistency.   |
| `pnpm run lint:haskell`                 | Run HLint over all project-owned Haskell directories.          |
| `pnpm run format`                       | Format the repository with Prettier.                           |
| `pnpm run format:haskell`               | Run Hindent and then Stylish Haskell over Haskell sources.     |
| `pnpm run generate:dsl-api-index`       | Regenerate the model-facing public DSL reference.              |
| `pnpm run check:dsl-api-index`          | Verify public DSL documentation and generated-index freshness. |
| `pnpm run show:dsl-api`                 | Print the indexed public DSL contract as JSON.                 |
| `pnpm run generate:visualization-types` | Regenerate TypeScript visualization IR types from Haskell.     |
| `pnpm run check:visualization-types`    | Regenerate and fail if visualization types drift from Git.     |

### Tests and benchmarks

| Command                        | Purpose                                                            |
| ------------------------------ | ------------------------------------------------------------------ |
| `pnpm run test:unit -- --run`  | Run the fast TypeScript suite once.                                |
| `pnpm run test:postgres`       | Run the opt-in real PostgreSQL/pg-boss durability test.            |
| `pnpm run test`                | Run unit tests and compile every catalogued example.               |
| `pnpm run test:examples`       | Compile every catalogued example through the production boundary.  |
| `pnpm run test:e2e`            | Run Playwright against an isolated file-backed application server. |
| `pnpm run test:sverlin-source` | Run the Haskell source/elaboration tests.                          |
| `pnpm run test:solver`         | Run direct solver tests against stable fixtures.                   |
| `pnpm run bench:solver`        | Benchmark solver lowering and execution on stable fixtures.        |
| `pnpm run bench:compile`       | Benchmark the complete prepared-compiler path.                     |

The Playwright suite does not exercise PostgreSQL authentication or the durable worker. Use the two-terminal administrator/participant walkthrough above for that path.

After Haskell changes, run the relevant compile, Haskell tests, solver tests, and HLint commands, then finish with `pnpm run format:haskell`. When the public DSL changes, update the facade Haddock descriptions and regenerate the DSL index. Do not edit the generated [`dsl-api-index.md`](src/lib/server/chat-bots/ai-assistant/dsl-api-index.md) by hand; cross-cutting guidance lives in [`dsl-interface.md`](src/lib/server/chat-bots/ai-assistant/dsl-interface.md).

## Railway deployment

Railway uses the same runtime image for an isolated web service and durable
worker:

```text
web:       node build
worker:    node build-worker/index.js
predeploy: node build-migrate/index.js
```

Each Railway environment has its own PostgreSQL database, private Bucket,
variables, services, and network. The complete Singapore topology lives in
[`.railway/railway.ts`](.railway/railway.ts). Bootstrap or update the currently
linked Railway environment with the project-pinned CLI:

```sh
pnpm exec railway login
pnpm exec railway link
pnpm exec railway environment production
pnpm run infra:plan
# Review the complete plan before mutating Railway resources.
pnpm run infra:apply
```

The required `verify` workflow builds the Docker `verification` target for pull
requests and `main`. CI-green `main` commits deploy automatically to staging;
production has no GitHub source and accepts only an exact-SHA run of the manual
`Promote production` workflow. That workflow verifies both staging services,
then deploys web/migrations before worker and runs the deployment smoke test.

Follow [`docs/deployment.md`](docs/deployment.md) for environment creation,
GitHub and Railway variables, administrator bootstrap, promotion, diagnostics,
backups, scaling, and rollback.

## Maintenance lock

Before changing application behavior while someone may have the frontend open:

```sh
pnpm run app:lock -- "reason"
pnpm run app:lock:status
pnpm run app:unlock
```

The lock makes mutations read-only while preserving project inspection and playback. It survives a stopped agent or shell, so release it explicitly only after checks pass.

## Agent tooling

Repository-local skills under [`.agents/skills/`](.agents/skills/) provide Svelte 5, shadcn-svelte, and Railway deployment/operations guidance in trusted clones. [`AGENTS.md`](AGENTS.md) contains the complete engineering and verification rules; [`AGENTS_LOG.md`](AGENTS_LOG.md) is the current uncommitted-work handoff.
