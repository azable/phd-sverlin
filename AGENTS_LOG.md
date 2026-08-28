# Railway IaC and verified research-data lifecycle

## Resume

Implementation is complete. The next safe action is to review the uncommitted
diff, authenticate and link the pinned Railway CLI to an empty project, and run
`pnpm run infra:plan`. Do not apply until the exact plan has been reviewed.
There are no known implementation blockers. Static checks, file-mode unit tests,
the real PostgreSQL/pg-boss integration test, and Playwright passed. The app
maintenance lock has been released. No live Railway resources were created or
changed.

| Files                                                                                                                                                                                                    | Change                                                                                                                                    |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| [`.railway/railway.ts`](.railway/railway.ts), [`.railway/README.md`](.railway/README.md)                                                                                                                 | Define and explain the Singapore web/worker/PostgreSQL/private-Bucket topology.                                                           |
| [`src/lib/server/research-data.ts`](src/lib/server/research-data.ts), [`src/archiver.d.ts`](src/archiver.d.ts)                                                                                           | Add consistent PostgreSQL snapshots, verified ZIP archives, and retry-safe participant/study purges.                                      |
| [`src/lib/server/projects/jobs.ts`](src/lib/server/projects/jobs.ts)                                                                                                                                     | Add sanitized job export, queue-idle/active guards, cancellation, and retained-job deletion.                                              |
| [`src/routes/admin/+page.server.ts`](src/routes/admin/+page.server.ts), [`src/routes/admin/+page.svelte`](src/routes/admin/+page.svelte), [`src/routes/admin/exports/`](src/routes/admin/exports/)       | Add admin download endpoints, exact typed confirmations, and participant/study deletion controls.                                         |
| [`src/lib/server/research-data.test.ts`](src/lib/server/research-data.test.ts), [`src/lib/server/projects/jobs.postgres.integration.test.ts`](src/lib/server/projects/jobs.postgres.integration.test.ts) | Cover hash/confirmation checks and real pg-boss durability across producer/worker restart.                                                |
| [`package.json`](package.json), [`pnpm-lock.yaml`](pnpm-lock.yaml), [`pnpm-workspace.yaml`](pnpm-workspace.yaml)                                                                                         | Add Archiver, the pinned Railway CLI/TypeScript IaC SDK, CLI post-install allow-list, plan/apply scripts, and the opt-in PostgreSQL test. |
| [`README.md`](README.md), [`docs/deployment.md`](docs/deployment.md)                                                                                                                                     | Document IaC, bootstrap, monitoring, backups, verified university transfer, purge, rollback, and incidents.                               |

## Architecture and behavior

The checked-in Railway program owns the whole project instead of duplicating
per-service `railway.json` settings. It places a Docker-built web service, a
4 GiB compiler worker, PostgreSQL, and a private Bucket in Singapore. Only web
runs Drizzle migrations and exposes readiness; worker drain remains longer than
job expiry. Secrets remain shared Railway references.

Admin exports read participants, non-deleted projects, ordered Timeline events,
and immutable resource metadata in a repeatable-read transaction. Raw pg-boss
command payloads and owner IDs are excluded from exported job outcomes. Every
Bucket object is fetched and checked before it enters the ZIP:

```ts
if (digest !== expected.sha256 || expected.resourceId !== `sha256-${digest}`) {
  throw new Error(`Resource ${expected.resourceId} failed SHA-256 verification.`);
}
```

Participant export refuses active work; study export requires an idle queue.
The manifest carries scope, build identity, counts, and SHA-256/length/media
metadata for each payload. Temporary archives are removed after streaming.

Deletion is explicit and retry-safe. The server derives confirmation text from
the stored participant identity rather than trusting a hidden form field. It
disables the account and revokes sessions, refuses active work, deletes every
project Bucket prefix, deletes project rows, cancels/deletes retained jobs, and
finally removes the Better Auth user. Study deletion repeats this for normal
participants and preserves administrators. Independent Railway backups remain
subject to the institutionally approved retention schedule.

## Verification

- `pnpm run check` — passed, zero diagnostics.
- Svelte autofixer on `src/routes/admin/+page.svelte` — no issues or suggestions.
- `SVERLIN_PROJECT_STORE=file pnpm run test:unit -- --run` — 103 passed, 2 opt-in tests skipped.
- `pnpm run test:postgres` — 1 passed against real PostgreSQL; persistence,
  resumed processing, completion, cancellation, and deletion covered.
- `pnpm run test:e2e` — 3 passed.
- Targeted ESLint on every changed TypeScript/Svelte file — passed.
- `pnpm run check:dsl-api-index` — 208 names verified.
- Prettier and `git diff --check` — passed.
- Railway definition loaded and produced the expected six-resource local graph;
  the Archiver v8 ZIP probe produced a valid `PK` archive.

## Limitations and operational notes

- Railway CLI 5.45.7 is installed and executable from the project. A live
  `railway config plan` was not run because no Railway project is authenticated
  or linked; the TypeScript graph was validated locally.
- Railway TypeScript IaC is beta and the SDK is pinned; review upgrades.
- The first IaC apply provisions topology, but web cannot become ready until a
  generated domain and referenced shared auth secrets are configured.
- The first unconstrained unit run inherited `SVERLIN_PROJECT_STORE=postgres`
  from the devcontainer and caused unrelated file-repository tests to use the
  wrong backend. The documented file-mode run passed; the PostgreSQL queue path
  was then tested separately and passed.
- No Haskell source, schema, migration, participant/project data, or live Railway
  state was changed. The pg-boss test used and removed its own UUID-named queue.
