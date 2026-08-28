# Railway deployment guide

Railway is the supported production target. The smallest suitable topology is:

- one public **web** service running `node build`;
- one private **worker** service running `node build-worker/index.js`;
- one Railway **PostgreSQL** database;
- one private Railway **Bucket**.

Web and worker use the same repository image. PostgreSQL stores Better Auth,
project ownership, immutable Timeline events, and pg-boss jobs. The Bucket
stores content-addressed compiler resources. Container filesystems hold only
temporary compiler workspaces.

Keeping compilation in the worker is deliberate: project mutations return HTTP
202 without depending on request or web-deployment duration. Start with one web
and one 4 GB worker replica. Add worker replicas only after measuring queue
latency, memory, and CPU; pg-boss serializes commands for each participant
across replicas.

## Local development

The devcontainer and `compose.yaml` use the root Dockerfile's `development`
target. Compose adds PostgreSQL and persistent local volumes; it is not another
production definition. Rebuild the devcontainer after changing these files,
then run:

```sh
pnpm run db:migrate
pnpm run worker:dev
```

Run `pnpm run dev` in a second terminal. The worker is required only for queued
project mutations. Local resources use the ignored state directory when Bucket
credentials are absent.

## Create the project

1. Create a Railway project from this Git repository.
2. Add PostgreSQL and a Bucket.
3. Add a **web** service from the repository. Use the root `Dockerfile`, start
   command `node build`, health path `/api/health/ready`, and a public domain.
4. Add a **worker** service from the same repository and revision. Use the same
   Dockerfile and start command `node build-worker/index.js`; do not expose a
   domain or configure an HTTP health check.
5. Add PostgreSQL `DATABASE_URL` and Bucket `BUCKET`, `ENDPOINT`,
   `ACCESS_KEY_ID`, `SECRET_ACCESS_KEY`, and `REGION` as Railway reference
   variables on both services.
6. Set the web pre-deploy command to `node build-migrate/index.js`. Only the web
   service owns Drizzle migrations. pg-boss safely manages its own schema when
   the web producer or worker starts.

The Docker image is intentionally substantial. Runtime compilation uses Hint,
so it needs the pinned Node, pnpm, GHC, HiGHS, solver/native libraries, prepared
compiler, and GHC package environment. A plain Node/Railpack image is not
sufficient.

This repo intentionally has no `railway.json`: Railway Configuration as Code is
deprecated for new services, and duplicating two service-specific start/drain
configurations in another file would add little value. Keep the settings above
in the Railway service configuration. Consider Railway IaC only if the
infrastructure grows enough to justify a reviewed provisioning program.

## Variables

Set on the web service:

```text
DATABASE_URL=<PostgreSQL reference>
BETTER_AUTH_SECRET=<at least 32 random bytes>
BETTER_AUTH_URL=https://<public domain>
BETTER_AUTH_TRUSTED_ORIGINS=https://<public domain>
SVERLIN_ADMIN_SETUP_TOKEN=<long one-time setup secret>
BUCKET=<Bucket reference>
ENDPOINT=<Bucket reference>
ACCESS_KEY_ID=<Bucket reference>
SECRET_ACCESS_KEY=<Bucket reference>
REGION=<Bucket reference>
SVERLIN_PROJECT_STORE=postgres
RAILWAY_DEPLOYMENT_DRAINING_SECONDS=30
```

Set the database and Bucket references on the worker, plus:

```text
SVERLIN_PROJECT_STORE=postgres
SVERLIN_JOB_EXPIRE_SECONDS=1800
SVERLIN_JOB_HEARTBEAT_SECONDS=60
SVERLIN_COMPILE_TIMEOUT_MS=300000
CHATBOT_REQUEST_TIMEOUT_MS=180000
RAILWAY_DEPLOYMENT_DRAINING_SECONDS=1860
```

The worker also needs `OPENAI_API_KEY` when AI-assisted feedback is enabled.
`SVERLIN_DATABASE_POOL_SIZE=5` is a reasonable initial Drizzle pool per process;
pg-boss uses a separate small pool. Count both across replicas before scaling.

The private Railway database URL normally does not require TLS. Set
`PGSSLMODE=require` only for a URL that requires it. Keep the services in the
same Railway project and environment so private networking and references
resolve consistently.

Leave `RAILWAY_DEPLOYMENT_OVERLAP_SECONDS` at its default zero initially. The
worker's 1,860-second drain exceeds its default 1,800-second job expiry, giving
graceful shutdown time before Railway sends `SIGKILL`. If either timeout is
changed, keep the drain longer than the expiry.

## First login and participants

After the first healthy deploy, visit:

```text
https://<public domain>/setup?token=<SVERLIN_ADMIN_SETUP_TOKEN>
```

Register the administrator passkey. Setup becomes unavailable after the admin
exists; rotate or remove the setup variable afterward.

From `/admin`, create a participant ID and copy the generated password. The
participant signs in at `/login` with those credentials. Password rotation and
disabling an account revoke active sessions. Projects are keyed to the Better
Auth user ID, so participants see only their projects while the administrator
can inspect all projects. No email service is required.

## Deployment safety and monitoring

- Keep one worker running; queued jobs remain durable while it is absent but do
  not progress.
- pg-boss handles delivery, one backoff retry, heartbeat recovery, and global
  per-participant concurrency. Timeline expected-head checks and terminal events
  make replay outcomes explicit.
- Do not attach a Railway Volume. PostgreSQL and the Bucket are the durable
  stores, while Railway Volumes are replica-local.
- Keep web and worker on the same image revision and make migrations backward
  compatible when rollback across revisions matters.
- Railway health checks gate a deployment; they are not continuous uptime
  monitors. Add Railway observability alerts or an external monitor for ongoing
  liveness, readiness, queue age, job failures, database capacity, and worker
  memory before participant recruitment.

No GitHub Actions workflow is bundled. Railway deploys from the repository;
checks remain explicit local commands unless another CI system is added later.

## Verification

After deployment:

```sh
SVERLIN_SMOKE_URL=https://<public domain> pnpm run smoke:deployment
```

- `GET /api/health/live` proves adapter-node responds.
- `GET /api/health/ready` checks configuration, PostgreSQL, scratch, and the
  prepared compiler.
- `GET /api/version` reports package/build/compiler identity.
- Authenticated `POST /api/health/compiler` performs a real compilation.

The public smoke does not need reusable participant credentials. For acceptance,
also sign in, create a disposable project, and confirm its job succeeds.

## Backups and rollback

Treat Railway PostgreSQL backups and Bucket backups/exports as one retention
set; Timeline rows without referenced Bucket objects are incomplete. Test a
restore into a separate environment before recruitment. The admin project reset
is destructive, so take a snapshot first when retention policy requires it.

`pnpm run data:export` covers only the legacy local file repository. A production
export needs a consistent PostgreSQL dump and S3 object export or a dedicated
versioned application export.

Relevant Railway documentation:

- [Services and workers](https://docs.railway.com/guides/saas-backend)
- [PostgreSQL](https://docs.railway.com/databases/postgresql)
- [Storage Buckets](https://docs.railway.com/storage-buckets)
- [Deployment teardown and drain](https://docs.railway.com/deployments/deployment-teardown)
- [Health checks](https://docs.railway.com/deployments/healthchecks)
- [Railway variables](https://docs.railway.com/variables/reference)
- [Configuration as Code deprecation](https://docs.railway.com/config-as-code)
