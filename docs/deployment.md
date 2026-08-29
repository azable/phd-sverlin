# Railway deployment and research-data operations

Railway is the supported hosted target. The checked-in
[`railway.ts`](../.railway/railway.ts) defines the same deliberately small
Singapore topology independently in staging and production:

- one public `web` service running `node build`;
- one private `worker` service running `node build-worker/index.js`;
- one PostgreSQL database for Better Auth, Timelines, ownership, and pg-boss;
- one private Bucket for immutable compiler resources.

The web and worker build the same Dockerfile revision. Only the web runs
`node build-migrate/index.js` as a pre-deploy migration. The worker is kept at
one replica with one-command concurrency and a 1,860-second drain window, longer
than the default 1,800-second job expiry. Staging follows CI-green `main`
commits. Production is source-empty and receives only manually promoted,
reviewed commits.

Both services use the Dockerfile's final `runtime` stage. Its official slim
Haskell base retains GHC because generated Sverlin source is interpreted during
project commands, but build and editor tooling stays in discarded stages. The
runtime copies the prepared compiler and only its integrity-checked source,
font, package-store, solver dependencies, and registered in-place library
artifacts; it does not contain HLS, formatters, linters, browser tooling, CMake,
Git, jq, pnpm, or executable/test build trees.

Singapore hosting does not replace the Australian university's research-data
governance. Before recruitment, record institutional approval for the hosting
location, data classes, retention period, access roles, incident process, and
the transfer from Railway to university-managed storage. Treat this guide as an
engineering control, not legal or ethics advice.

## Infrastructure as code

`pnpm install` installs both the Railway CLI and TypeScript IaC SDK as
development dependencies. TypeScript IaC is generally available and owns one
complete project environment at a time. Authenticate and link the project
before the first use.

```sh
pnpm exec railway login
pnpm exec railway link
pnpm exec railway environment production
pnpm run infra:plan
```

The production plan creates four resources and two canvas groups. Review the
complete plan, especially any destroy/replace actions. Applying changes is a
separate, deliberate operation:

```sh
pnpm run infra:apply
```

Create staging as an empty, isolated environment rather than duplicating
production data or secrets, then plan and apply the same definition there:

```sh
pnpm exec railway environment new staging
pnpm exec railway environment staging
pnpm run infra:plan
# Review the complete staging plan.
pnpm run infra:apply
```

Use `pnpm exec railway environment production` or
`pnpm exec railway environment staging` before later plan/apply operations. IaC
connects staging services to `main` with check suites enabled. It deliberately
leaves production services without a repository source so a push cannot bypass
staging and the promotion gate.

Never commit generated Railway domains, project UUIDs, tokens, or secret values.
Do not add a `railway.json`; the TypeScript definition owns both services and
their project resources. Keep CLI and SDK versions controlled through the
lockfile and review release notes when upgrading them.

The definition intentionally does not create generated public domains. Generate
a distinct Railway domain for each environment's `web` service, then create
these shared variables separately in staging and production:

```text
BETTER_AUTH_SECRET=<at least 32 random bytes>
BETTER_AUTH_URL=https://<web domain>
SVERLIN_ADMIN_SETUP_TOKEN=<long one-time setup secret>
OPENAI_API_KEY=<provider secret, when AI feedback is enabled>
```

`BETTER_AUTH_TRUSTED_ORIGINS` follows `BETTER_AUTH_URL` in IaC. Database and
Bucket credentials are resource references rather than copied secrets. The
private Railway database URL normally does not require TLS; set `PGSSLMODE` only
when the selected connection URL requires it.

Adding shared variables may trigger a staging deployment without changing the
IaC graph. Production remains deployed through the promotion workflow. IaC
fixes both services in Singapore, configures the readiness health check, restart
policy, pool and job timings, and gives the compiler worker a 4 GiB memory
limit. Adjust that limit only after measuring representative workloads.

## CI and exact-SHA promotion

The required GitHub `verify` job builds the Docker `verification` stage and then
the final cached `runtime` stage. Verification compiles the real runtime inputs
and runs checks, lint, file-mode unit tests, and every catalogued example.
Protect `main` in GitHub so `verify` must pass before merge. Railway's staging
sources also use check suites, so a failed push check is skipped instead of
deployed.

Create GitHub environments named `staging` and `production`. Configure each
with credentials for only its matching Railway environment:

| Location              | Name                 | Value                                   |
| --------------------- | -------------------- | --------------------------------------- |
| Repository variable   | `RAILWAY_PROJECT_ID` | Railway project UUID                    |
| `staging` secret      | `RAILWAY_TOKEN`      | Staging-scoped Railway project token    |
| `staging` variable    | `SVERLIN_SMOKE_URL`  | Staging web URL                         |
| `production` secret   | `RAILWAY_TOKEN`      | Production-scoped Railway project token |
| `production` variable | `SVERLIN_SMOKE_URL`  | Production web URL                      |

When the GitHub plan supports it, require a reviewer on the `production`
environment. Manual workflow dispatch remains an explicit gate either way.

To release, copy the full 40-character SHA of a CI-green `main` commit whose
staging deployment is ready, then run the `Promote production` workflow with
that SHA. The workflow:

1. Confirms the SHA belongs to `main` and has a successful `verify` check.
2. Finds successful staging web and worker deployments for that exact SHA.
3. Smoke-tests staging and verifies the web reports that SHA.
4. Sets the web's `SVERLIN_BUILD_SHA` without triggering a deployment, uploads
   the checked-out SHA, and waits for migration, readiness, and terminal
   deployment success.
5. Sets the same worker build identity without deploying, uploads the same tree,
   and waits for terminal success.
6. Smoke-tests production, requires its version endpoint to report the promoted
   SHA, and records that SHA in the workflow summary and Railway messages.

GitHub-triggered services otherwise deploy independently, so migrations must
remain backward compatible. If web succeeds and worker fails, production is in
a deliberate partial-release state: retry the same SHA after diagnosing the
worker. Do not roll the database backward automatically.

## First deployment

1. Apply the reviewed production IaC plan, then generate its web domain and set
   its shared variables.
2. Create empty staging, apply its reviewed IaC plan, generate its web domain,
   and set distinct staging variables.
3. Configure the GitHub repository/environments above and require `verify` on
   `main`.
4. Push a commit to `main`; wait for CI and both staging services, then run
   `SVERLIN_SMOKE_URL=https://<staging-domain> pnpm run smoke:deployment`.
5. Visit `https://<staging-domain>/setup?token=<staging-token>` and register a
   staging administrator. Exercise a disposable participant and queued command.
6. Promote the successful SHA through GitHub Actions.
7. Visit `https://<production-domain>/setup?token=<production-token>`, register
   the production admin passkey, then remove or rotate the one-time setup token.

`GET /api/health/live` checks the Node process. `GET /api/health/ready` checks
configuration, PostgreSQL, scratch space, and the compiler. Railway health
checks gate deployments but are not continuous monitoring.

## Deployment diagnostics

Install Railway's remote MCP for Codex, authenticate it with user OAuth, and
restart Codex so future sessions can inspect project state without storing a
project token in the repository:

```sh
pnpm exec railway mcp install --agent codex --oauth
```

Connect the GitHub integration in Codex as well. Permit deployment, log, metric,
workflow, check, and issue reads; retain approval for writes such as redeploying,
changing variables, or creating an issue. These account connections are local
operator setup, not repository state.

The pinned local CLI remains the deterministic fallback. Always scope reads to
the exact project, environment, and service, and keep log queries bounded:

```sh
pnpm exec railway deployment list --project <project-id> --environment production --service web --json
pnpm exec railway logs --project <project-id> --environment production --service web --latest --lines 200 --json
pnpm exec railway logs --project <project-id> --environment production --service worker --lines 200 --filter '@level:error' --json
pnpm exec railway metrics --project <project-id> --environment production --all --since 1h --json
```

For an incident, start with the failed GitHub job and its exact SHA, then inspect
the matching Railway deployment, build logs, runtime logs, and metrics. Do not
redeploy, mutate variables, or file a GitHub issue without explicit approval.

## Reliability and monitoring

- Keep one worker running. PostgreSQL retains queued work through worker restarts,
  but commands do not progress while it is absent.
- Alert on readiness, worker restarts, queue age and failures, PostgreSQL
  capacity, Bucket errors, and worker memory before participant recruitment.
- Keep web and worker on the same Git revision and make migrations backward compatible.
- Do not attach a Railway Volume. PostgreSQL and the Bucket are durable;
  container filesystems and export temp files are disposable.
- Enable backups appropriate to the approved retention window. Treat database
  backups and Bucket copies as one recovery set and test restoration elsewhere.

## Verified exports and deletion

The administrator page provides participant and whole-study ZIP exports. An
export contains participant metadata, complete immutable project Timelines,
sanitized queue outcomes, resource metadata, and every referenced Bucket object.
It excludes passwords, sessions, passkeys, provider credentials, and raw command
payloads. Every resource is checked against its byte length, SHA-256 digest, and
content-addressed ID. `manifest.json` records scope, build identity, counts, and
hashes for every payload file in the archive.

A whole-study export is allowed only while the queue is completely idle. A
participant export is refused while that participant has active work.

For the planned university transfer:

1. Stop participant activity and wait for the queue to become idle.
2. Download the whole-study export over a trusted connection.
3. Record the archive filename and SHA-256 hash outside Railway.
4. Move it to the approved university system and verify its hash there.
5. Inspect `manifest.json` and sample a participant, project, and resource.
6. Only after the institutional copy is accepted, perform the approved Railway
   deletion and retain the required audit record outside participant data.

Participant deletion requires `DELETE <participant ID>`; study deletion requires
`DELETE STUDY DATA`. The application disables the participant and revokes
sessions, refuses active jobs, deletes Bucket prefixes and projects, removes
retained queue records, then removes the Better Auth user. The admin is
preserved. Deletion is not automatic after download because a browser download
does not prove university transfer and verification.

Purging live data does not erase independent Railway backups. Expire those under
the approved retention schedule and document provider-side deletion separately.

## Rollback and incidents

For an application regression, deploy the last known-good Git revision while
leaving PostgreSQL and the Bucket intact. Pause the worker before investigating
possible corruption. For a suspected incident, disable affected participants,
preserve evidence required by university policy, rotate exposed secrets, and
follow the institutional reporting process.

Relevant official Railway documentation:

- [TypeScript infrastructure as code](https://docs.railway.com/infrastructure-as-code)
- [PostgreSQL](https://docs.railway.com/databases/postgresql)
- [Storage Buckets](https://docs.railway.com/storage-buckets)
- [Deployment teardown and drain](https://docs.railway.com/deployments/deployment-teardown)
- [Health checks](https://docs.railway.com/deployments/healthchecks)
- [Variables](https://docs.railway.com/variables/reference)
