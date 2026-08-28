# Current agent work: Railway runtime, local development, and joined authentication

This snapshot covers all current uncommitted agent-authored work: a Railway-targeted SvelteKit runtime, owner-scoped PostgreSQL/Bucket persistence, Better Auth with joined Drizzle session queries, pg-boss project jobs, compiler hardening, and a simplified devcontainer workflow with reusable Cabal dependency layers.

| Status               | Important files                                                                                                                                                                                                                                                                                                               | Purpose                                                                                                                                                                                                                                                  |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Added/replaced       | [`Dockerfile`](Dockerfile), [`compose.yaml`](compose.yaml), [`.dockerignore`](.dockerignore), [devcontainer config](.devcontainer/devcontainer.json)                                                                                                                                                                          | Share one pinned toolchain, cache external Cabal dependencies in a reusable image layer, grant the local workspace the capability and seccomp settings Bubblewrap needs, seed persistent caches, and avoid expensive compiler builds during post-create. |
| Added                | [Database schema](src/lib/server/db/), [single Drizzle baseline migration](drizzle/), [`drizzle.config.ts`](drizzle.config.ts), [`src/project-migrate.ts`](src/project-migrate.ts)                                                                                                                                            | Store Better Auth and project Timeline metadata in PostgreSQL. Better Auth relations support joined session/user queries, and account identity uses the required 1.7 `(issuer, accountId)` key; pg-boss owns its separate runtime-managed schema.        |
| Added                | [`src/lib/server/auth.ts`](src/lib/server/auth.ts), [`src/lib/server/participants.ts`](src/lib/server/participants.ts), [`src/lib/server/authorization.ts`](src/lib/server/authorization.ts), [`src/hooks.server.ts`](src/hooks.server.ts), [login/setup/admin routes](src/routes/admin/)                                     | Bootstrap one passkey researcher, provision participant ID/password credentials through Better Auth's Username/Admin plugins, expose a visible POST-based admin sign-out control, ban/unban and rotate credentials, and scope projects by user ID.       |
| Added                | [`src/lib/server/projects/jobs.ts`](src/lib/server/projects/jobs.ts), [`src/lib/server/projects/recovery.ts`](src/lib/server/projects/recovery.ts), [`src/project-worker.ts`](src/project-worker.ts), [job API](src/routes/api/jobs/)                                                                                         | Use pg-boss for PostgreSQL delivery, retry/backoff, heartbeat recovery, per-participant distributed concurrency, status retention, and graceful worker drain while preserving Timeline terminal-event reconciliation.                                    |
| Modified/added       | [`src/lib/server/projects/repository.ts`](src/lib/server/projects/repository.ts), [`src/lib/server/projects/resource-store.ts`](src/lib/server/projects/resource-store.ts), [`src/lib/server/projects/service.ts`](src/lib/server/projects/service.ts)                                                                        | Add PostgreSQL Timeline storage and immutable Railway Bucket resources while retaining the local file store. Split cheap project skeleton creation from the initial queued render.                                                                       |
| Modified/added       | [`src/lib/server/compiler/`](src/lib/server/compiler/), [`scripts/prepare-compiler.mjs`](scripts/prepare-compiler.mjs), [`scripts/run-compile.mjs`](scripts/run-compile.mjs)                                                                                                                                                  | Bound compiler I/O, coordinate preparation/execution, limit concurrency, and make directory durability syncing portable across Docker bind mounts.                                                                                                       |
| Added                | [`src/lib/server/runtime-state.ts`](src/lib/server/runtime-state.ts), [`src/lib/server/runtime-config.ts`](src/lib/server/runtime-config.ts), [health/version routes](src/routes/api/health/), [`scripts/run-with-state-lock.mjs`](scripts/run-with-state-lock.mjs)                                                           | Validate production configuration, database/scratch/compiler readiness, recover file-mode operations, expose operational endpoints, and prevent local servers sharing file state.                                                                        |
| Modified             | [`src/lib/client/projects/project-session.svelte.ts`](src/lib/client/projects/project-session.svelte.ts), [`src/lib/client/projects/ProjectWorkspace.svelte`](src/lib/client/projects/ProjectWorkspace.svelte), [root/project pages](src/routes/)                                                                             | Poll durable job status and Timeline suffixes, carry initial jobs through navigation, stop polling on disposal, and keep UI state aligned with authoritative reloads.                                                                                    |
| Added/modified       | [`package.json`](package.json), [`src/project-worker.ts`](src/project-worker.ts), [server chat/catalog modules](src/lib/server/)                                                                                                                                                                                              | Add runtime scripts and a single `pnpm run dev` path; make the standalone worker use Node environment variables, filesystem-backed examples, and the same bundled entrypoint as production.                                                              |
| Added/modified       | [`README.md`](README.md), [`docs/deployment.md`](docs/deployment.md), [`docs/compiler-runtime.md`](docs/compiler-runtime.md), [`AGENTS.md`](AGENTS.md)                                                                                                                                                                        | Document scripts, the one-terminal local workflow, participant credentials, container caching, Railway operations, recovery limits, and resumable handoff state.                                                                                         |
| Added/modified tests | [`src/lib/server/projects/jobs.test.ts`](src/lib/server/projects/jobs.test.ts), [`src/lib/server/auth.test.ts`](src/lib/server/auth.test.ts), [`src/lib/server/db/schema.test.ts`](src/lib/server/db/schema.test.ts), [route tests](src/routes/api/projects/), [`e2e/project-creation.spec.ts`](e2e/project-creation.spec.ts) | Cover auth helpers and joined session query construction, job terminal/recovery decisions, repository/scheduler behavior, authorization-aware APIs, polling handoff, resource validation, and browser maintenance behavior.                              |

## Resume state

- Implementation is complete. The next safe action is `pnpm run dev`, bootstrap a fresh administrator at `http://localhost:5173/setup?token=development-setup-token`, then continue the README's participant walkthrough.
- Post-create now installs Node dependencies, seeds image-baked Cabal packages into persistent named volumes, and migrates PostgreSQL; it no longer updates Cabal or compiles project-owned Haskell source.
- A restarted agent must first read `AGENTS.md` and this log completely, inspect the working tree and recorded operational state, then continue from the next safe action above without reconstructing or discarding uncommitted work.
- The rebuilt devcontainer grants the intended Bubblewrap privileges; an approved test outside Codex's inner command sandbox successfully created the nested namespace.
- The local `sverlin` database was deliberately dropped, recreated, and migrated after collapsing the two-step Drizzle history into one clean baseline. It has nine empty application tables, one recorded migration, and no administrator, participants, projects, or pg-boss history.
- A joined Better Auth session lookup returned HTTP 200 before the final reset. Participant creation stores credential accounts with issuer `local:credential`; no development process is intentionally running.
- The administration header has a visible `Sign out` button that submits the existing POST `/logout` endpoint and redirects to `/login`; direct GET navigation remains intentionally unsupported.
- The temporary workspace app maintenance lock has been released (`locked: false`).
- A concurrent process refreshed the repository-local skills after implementation validation. The installed skills CLI discovers all six project skills, every installed directory matches its `skills-lock.json` content hash, and the Railway helper scripts pass Python or shell syntax checks. This audit did not modify the concurrent skill refresh.
- Railway production still requires owner action: provision web, worker, PostgreSQL, and Bucket; configure reference variables, the web pre-deploy migration, service start commands, and drain windows from [`docs/deployment.md`](docs/deployment.md); then deploy one image revision to web and worker.
- Before later work, inspect `git status`, preserve the excluded user change below, acquire the app lock before changing Svelte behavior, and revise this same snapshot while these changes remain uncommitted.

## Architecture and behavior

The supported Railway topology is intentionally small:

```text
public web:     node build
private worker: node build-worker/index.js
web predeploy:  node build-migrate/index.js
shared state:   Railway PostgreSQL + private Bucket
```

The web process authenticates, authorizes, validates, and enqueues a command, then returns HTTP 202. pg-boss uses the operation UUID as the idempotent job ID and the Better Auth owner ID as its group. The worker handles one job locally; `groupConcurrency: 1` serializes each participant across replicas. Start with one worker rather than pre-provisioning compile slots or replicas.

```ts
await boss.send('project-command', data, {
  id: data.operationId,
  group: { id: data.ownerUserId }
});
```

pg-boss now owns delivery, LISTEN/NOTIFY wake-up, one backoff retry, heartbeat detection, 30-minute absolute expiry, completed-job retention, and graceful stop. Application-owned `project_job`, `compile_slot`, lease renewal, requeue polling, invite, participant, and audit tables were removed.

The Timeline remains the domain truth. Expected-head appends prevent silent concurrent mutation. A retry accepts only a command-specific terminal event; interrupted compilation/generation receives explicit cancellation and notification events, and a later retry preserves the failed outcome instead of reclassifying recovery markers as success.

Better Auth provides both login modes:

- the researcher bootstraps once with a secret URL and signs in centrally with a passkey;
- the researcher creates a participant username and receives a generated 24-character password shown once;
- password rotation uses Better Auth's Admin plugin and revokes sessions;
- disabling/enabling maps to built-in ban/unban behavior; banning revokes active sessions;
- participant project and job access is filtered by the Better Auth user ID.

Better Auth keeps `advanced.database.joins` enabled. The Drizzle schema exports both sides of the user/session, user/account, and user/passkey relations, so `/get-session` can retrieve a session and user in one query without the previous query-construction failure. Account rows include Better Auth 1.7's required non-null issuer, and uniqueness is enforced on `(issuer, accountId)` rather than the legacy `(providerId, accountId)` pair. Because this is still a resettable prototype, the migration history is one clean baseline rather than carrying a legacy issuer backfill.

The Dockerfile remains larger than a conventional Node image because runtime `compile-app` uses Hint/GHC to compile submitted Sverlin source. Compose and the devcontainer do not duplicate it: Dockerfile defines image targets, Compose defines local services/volumes, and the devcontainer attaches the editor to Compose's workspace service.

The local Compose workspace grants `CAP_SYS_ADMIN` and uses `seccomp:unconfined` so the non-setuid Bubblewrap binary can create its nested namespaces. Those development-only settings are scoped to the workspace service; PostgreSQL and Railway runtime containers do not receive them.

Railway-specific choices follow the installed official skill: no Railway Volume, no deprecated `railway.json`, one migration owner, health path only on web, continuous monitoring separate from deploy-time health checks, and `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=1860` on the worker so drain exceeds the default 1,800-second job expiry.

## Verification performed

- `pnpm exec prettier --write AGENTS.md AGENTS_LOG.md` and `git diff --check -- AGENTS.md AGENTS_LOG.md`: passed for the post-rebuild handoff rule.
- The cached `skills` CLI discovers all six repository-local skills for Codex, and a read-only reproduction of its content-hash algorithm matches every `skills-lock.json` entry exactly.
- All six executable Railway helper scripts passed syntax checks (`python3 -m py_compile` or `bash -n`); their concurrent changes are executable-bit updates only.
- The skill creator's bundled `quick_validate.py` could not run because PyYAML is absent from the container. Its older frontmatter allowlist would also reject shadcn-svelte's pre-existing `user-invocable` key, although the actual installed-skills parser loads the skill successfully.
- Railway CLI freshness could not be checked because `railway` is not installed in the current container. This does not affect loading or validating the repository-local guidance.
- `npx @sveltejs/mcp svelte-autofixer` on the final admin and login components: no issues or suggestions. Earlier changed Svelte files also had no issues; `ProjectWorkspace.svelte` retained only intentional imperative player-synchronization suggestions.
- `pnpm run prepare:compiler`: succeeded on the Docker bind mount that previously raised `EBADF`; the prepared descriptor was written successfully.
- `pnpm run dev` post-reset startup: `Sverlin project worker started`, Vite became ready on port 5173, the fresh setup page returned HTTP 200, and termination drained the worker.
- `pnpm run check`: zero Svelte errors and warnings after the final changes.
- `pnpm run lint`: the final Prettier, ESLint, and `check:dsl-api-index` pass succeeded; 208 public DSL names were verified.
- `SVERLIN_PROJECT_STORE=file pnpm exec vitest run`: 100 tests passed; one catalog integration test was intentionally skipped by the fast suite, including joined-session and issuer-schema regressions.
- A signed request using the pre-reset persisted session returned HTTP 200 from `/` after a clean server restart, exercising Better Auth's joined session/user path end to end.
- The local PostgreSQL `sverlin` database was force-dropped and recreated, `pnpm run db:migrate` succeeded, and inspection confirmed one recorded migration, nine empty public tables, zero users and projects, a non-null `auth_account.issuer`, and the unique `(issuer, account_id)` index.
- `pnpm run build`: adapter-node, migration bundle, and pg-boss worker bundle built successfully.
- `pnpm run test:e2e`: all 3 Playwright tests passed after the visible admin logout control was added. The sandboxed first attempt could not bind localhost (`EPERM`); approved localhost runs pass.
- `pnpm run db:generate`: generated one nine-table baseline migration, [`drizzle/0000_sloppy_marten_broadcloak.sql`](drizzle/0000_sloppy_marten_broadcloak.sql), directly from the current schema.
- `git diff --check`: passed after the final implementation and log refresh.
- `bwrap --ro-bind / / --proc /proc --dev /dev --unshare-pid --new-session ...`: passed outside Codex's inner command sandbox after the devcontainer rebuild (`bwrap-ok pid=2`).
- Earlier in this uncommitted implementation, `pnpm run test` also passed the full real compiler example catalogue. No Haskell source was changed by the agent in this review, so Haskell formatting and solver checks were not triggered.

## Remaining acceptance and limits

- Exercise participant username/password login, password rotation/ban, owner-scoped projects, pg-boss delivery/recovery, and graceful worker shutdown against the migrated local database.
- Test a Railway image build, deploy health gate, Bucket round-trip, worker memory/CPU, 1,860-second drain configuration, and external/continuous monitoring before participant recruitment.
- The pinned compiler image is intentionally large; measure build caching, image size, and GHC/solver peak memory on Railway.
- Sverlin source is trusted Haskell-based input, not a hostile-code sandbox. Participant-authored hostile source needs an OS-isolated compiler service.
- Treat a PostgreSQL dump and Bucket export as one backup generation. `pnpm run data:export` is not a production PostgreSQL-plus-S3 backup.
- Keep web and worker on the same revision. Database migrations must remain backward compatible if rollback across revisions is required.

## Deliberately excluded changes

- The pre-existing [`COMPILE_INTERFACE_AUDIT.md`](COMPILE_INTERFACE_AUDIT.md) edit belongs to the user and is not summarized as agent work.
- A concurrent process owns the refresh under [`.agents/skills/`](.agents/skills/) and [`skills-lock.json`](skills-lock.json), including the newly installed Better Auth skills, shadcn-svelte CLI documentation, and Railway helper executable bits. This audit validated but did not modify those files.
