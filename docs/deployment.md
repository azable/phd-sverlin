# Railway deployment and research-data operations

[`Railway`](https://docs.railway.com/) is the supported hosted target. The checked-in
[`railway.ts`](../.railway/railway.ts) defines the same small set of services and
data stores independently in staging and production:

- one public `web` service running `node build`;
- one private `worker` service running `node build-worker/index.js`;
- one PostgreSQL database for Better Auth, Timelines, ownership, and pg-boss;
- one private Railway Bucket (object storage) for immutable compiler resources.

The web and worker build the same Git commit with the same
[`Dockerfile`](../Dockerfile#L258-L280). Its final image contains the web,
database-migration, and worker bundles:

```dockerfile
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/build ./build
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/build-migrate ./build-migrate
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/build-worker ./build-worker

CMD ["node", "build"]
```

When this image starts without another command, Docker uses its final `CMD` and
runs `node build`, which starts the web server. The service commands are written
directly in `.railway/railway.ts`: the `web` definition contains
`start: 'node build'` and `preDeploy: 'node build-migrate/index.js'`, while the
`worker` definition contains `start: 'node build-worker/index.js'`. When the
infrastructure definition is applied, these fields tell Railway what to run for
each service and when to run the web database migration.

Source: [`web` service definition](../.railway/railway.ts#L22-L42) and
[`worker` service definition](../.railway/railway.ts#L44-L60). The excerpt is
abridged to show only the relevant fields:

```ts
const web = service('web', {
  // Source and image-build settings omitted.
  start: 'node build',
  preDeploy: 'node build-migrate/index.js'
  // Health-check, deployment, and environment settings omitted.
});

const worker = service('worker', {
  // Source and image-build settings omitted.
  start: 'node build-worker/index.js'
  // Replica, deployment, and environment settings omitted.
});
```

Building one shared image avoids separate web and worker build definitions while
keeping their runtime processes independent.

One copy of the worker runs at a time. During a deployment, Railway allows the
previous copy up to 1,860 seconds to finish before forcing it to stop. This is a
maximum allowance, not a fixed delay: the previous worker stops as soon as its
active command finishes, so a normal deployment is likely to use much less
time. The long upper bound accommodates an unusually slow AI command that needs
both its initial generation and its one permitted repair attempt. The
[drain period](https://docs.railway.com/deployments/deployment-teardown) is the
application's 1,800-second job-expiry default plus a 60-second shutdown margin;
the values come from [`jobs.ts`](../src/lib/server/projects/jobs.ts) and
[`railway.ts`](../.railway/railway.ts).

Staging automatically follows `main` commits that passed GitHub's `verify` check.
Production follows the same branch but has
[automatic deployments](https://docs.railway.com/guides/github-autodeploys)
disabled in Railway, so releases happen only when an operator chooses
**Deploy Latest Commit**.

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

## Infrastructure configuration

`pnpm install` installs the Railway command-line tool and TypeScript library as
development dependencies. The checked-in `railway.ts` file is the source of
truth for one complete project environment at a time. Railway calls this
[TypeScript infrastructure as code](https://docs.railway.com/infrastructure-as-code):
the repository describes the required Railway resources, and Railway compares
that description with the selected environment. Sign in and link this working
copy to the intended Railway project before the first use.

```sh
pnpm exec railway login
pnpm exec railway link
pnpm exec railway environment production
pnpm run infra:plan
```

The production plan creates the two services, PostgreSQL database, Bucket, and
two visual groups in Railway's project view. A plan is only a preview; it does
not change Railway. Review the complete preview, paying particular attention to
anything Railway proposes to remove or recreate. Applying the reviewed plan is
a separate operation:

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
`pnpm exec railway environment staging` before later preview or apply
operations. The checked-in definition connects both environments to `main`
with GitHub checks enabled, so Railway waits for the `verify` job before
deploying a commit.

After applying the definition, open each service's source settings in Railway.
Keep automatic deployments enabled for staging `web` and `worker`. Disable them
for production `web` and `worker`. This switch is not represented by the
current TypeScript library, so this is a manual dashboard setting. Check it
after the first apply and after changing either service's source settings.

Never commit generated Railway domains, project UUIDs, tokens, or secret values.
Do not add a `railway.json`; the TypeScript definition manages both services and
their project resources. Keep the command-line tool and TypeScript library
versions controlled through the lockfile, and review release notes when
upgrading them.

The definition intentionally does not create generated public domains. Generate
a distinct Railway domain for each environment's `web` service, then create
the following
[shared variables](https://docs.railway.com/variables/reference#shared-variables)
separately in staging and production. Shared means they are entered once per
environment and referenced by the services that need them; it does not mean
staging and production share values. Mark the three secrets as
[sealed](https://docs.railway.com/variables#sealed-variables), which prevents
their values from being viewed again in Railway after they are saved.

| Variable                    | Visibility | Purpose                                                             |
| --------------------------- | ---------- | ------------------------------------------------------------------- |
| `BETTER_AUTH_SECRET`        | Sealed     | Signs login sessions; use a different random value per environment. |
| `SVERLIN_ADMIN_SETUP_TOKEN` | Sealed     | One-time administrator setup link.                                  |
| `OPENAI_API_KEY`            | Sealed     | Enables AI-assisted editing in the web service.                     |
| `BETTER_AUTH_URL`           | Normal     | The environment's public `web` URL.                                 |
| `OPENAI_MODEL`              | Normal     | Model name, normally `gpt-5.6-luna`.                                |
| `CHATBOT_CONFIG`            | Normal     | Bot configuration, normally `ai-assistant`.                         |

`BETTER_AUTH_TRUSTED_ORIGINS` follows `BETTER_AUTH_URL` in the TypeScript
definition. Database and Bucket variables come directly from the Railway
resources rather than being copied into this list. The application selects
PostgreSQL on Railway and uses its checked-in defaults for pool size, job
timings, and request timeouts. Do not copy the local `.env` file to Railway. The
private Railway database URL normally does not require encrypted transport;
set `PGSSLMODE` only when the selected connection URL requires TLS.

Changing shared variables may trigger a staging deployment. Confirm that
production automatic deployments are still disabled before changing production
variables. The definition fixes both services in Singapore, configures the readiness health
check and restart policy, and gives the compiler worker a 4 GiB memory limit.
Adjust that limit only after measuring representative workloads.

## GitHub checks and manual production release

The required GitHub `verify` job builds the Docker `verification` stage and then
the final cached `runtime` stage. Verification compiles the real runtime inputs
and runs checks, lint, file-mode unit tests, and every catalogued example.
Protect `main` in GitHub so `verify` must pass before merge. Railway also waits
for that check, so it does not deploy a failed commit.

No Railway token, project ID, deployment URL, or Railway environment is needed
in GitHub. GitHub verifies the code; Railway stores the hosted configuration and
performs deployments.

Use this release sequence:

1. In GitHub, confirm the latest commit on `main` has a successful `verify` job.
2. In Railway staging, confirm both `web` and `worker` successfully deployed
   that same commit. Run this quick deployment check:
   `SVERLIN_SMOKE_URL=https://<staging-domain> pnpm run smoke:deployment` and
   exercise one disposable queued command.
3. Check `main` again immediately before release. If it advanced, wait for the
   new commit to pass its GitHub checks and staging instead of releasing an
   older revision.
4. In Railway production, open `web` and choose **Deploy Latest Commit**. Wait
   for its pre-deploy migration and readiness check to succeed.
5. Open production `worker` and choose **Deploy Latest Commit**. Wait for it to
   become ready and confirm it reports the same commit as `web`.
6. Run `SVERLIN_SMOKE_URL=https://<production-domain> pnpm run smoke:deployment`
   and record the released commit in the study's operations log.

The services deploy independently, so migrations must remain backward
compatible. If `web` succeeds and `worker` fails, retry the same latest commit
after diagnosing the worker. Do not roll the database backward automatically.

## First deployment

1. Apply the reviewed production infrastructure plan, generate its web domain,
   set its shared variables, and disable automatic deployments for both services.
2. Create empty staging, apply its reviewed infrastructure plan, generate its
   web domain, set distinct staging variables, and leave automatic deployments
   enabled.
3. Require the GitHub `verify` job on `main`.
4. Push a commit to `main`; wait for its GitHub checks and both staging services,
   then run
   `SVERLIN_SMOKE_URL=https://<staging-domain> pnpm run smoke:deployment`.
5. Visit `https://<staging-domain>/setup?token=<staging-token>` and register a
   staging administrator. Exercise a disposable participant and queued command.
6. Release the tested latest commit manually: production `web` first, then
   production `worker`, then the production smoke test.
7. Visit `https://<production-domain>/setup?token=<production-token>`, register
   the production admin passkey, then remove or rotate the one-time setup token.

`GET /api/health/live` checks the Node process. `GET /api/health/ready` checks
configuration, PostgreSQL, scratch space, and the compiler. Railway health
checks gate deployments but are not continuous monitoring.

## Deployment diagnostics

Install Railway's remote Model Context Protocol (MCP) connection, which lets
Codex query Railway through the signed-in command-line tool. Restart Codex after
installation so future sessions can use the connection without storing a
project token in the repository:

```sh
pnpm exec railway mcp install --agent codex --remote
```

The devcontainer mounts a Docker-managed `railway-state` volume at
`/root/.railway`. It preserves the command-line login and local project link
across container rebuilds without copying credentials into the image or
repository. Removing the Compose volumes also removes this saved login.

Connect the GitHub integration in Codex as well. Permit deployment, log, metric,
workflow, check, and issue reads; retain approval for writes such as redeploying,
changing variables, or creating an issue. These account connections are local
operator setup, not repository state.

The pinned local command-line tool remains useful when exact, scriptable output
is needed. Always identify the project, environment, and service explicitly,
and limit log queries so an investigation does not download an unbounded log:

```sh
pnpm exec railway deployment list --project <project-id> --environment production --service web --json
pnpm exec railway logs --project <project-id> --environment production --service web --latest --lines 200 --json
pnpm exec railway logs --project <project-id> --environment production --service worker --lines 200 --filter '@level:error' --json
pnpm exec railway metrics --project <project-id> --environment production --all --since 1h --json
```

For an incident, start with the failed deployment and its Git commit, then
inspect the matching GitHub check, Railway build logs, runtime logs, and metrics.
Do not redeploy, mutate variables, or file a GitHub issue without explicit
approval.

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
