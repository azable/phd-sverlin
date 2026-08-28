# Railway deployment and research-data operations

Railway is the supported hosted target. The checked-in
[`railway.ts`](../.railway/railway.ts) defines a deliberately small Singapore
topology:

- one public `web` service running `node build`;
- one private `worker` service running `node build-worker/index.js`;
- one PostgreSQL database for Better Auth, Timelines, ownership, and pg-boss;
- one private Bucket for immutable compiler resources.

The web and worker build the same pinned Dockerfile revision. Only the web runs
`node build-migrate/index.js` as a pre-deploy migration. The worker is kept at
one replica with one-command concurrency and a 1,860-second drain window, longer
than the default 1,800-second job expiry.

Singapore hosting does not replace the Australian university's research-data
governance. Before recruitment, record institutional approval for the hosting
location, data classes, retention period, access roles, incident process, and
the transfer from Railway to university-managed storage. Treat this guide as an
engineering control, not legal or ethics advice.

## Infrastructure as code

`pnpm install` installs both the pinned Railway CLI and the TypeScript IaC SDK as
development dependencies. The CLI supplies the plan/apply engine and is kept
above the SDK's minimum supported version. Authenticate it before the first use.

```sh
railway login
railway link
pnpm run infra:plan
```

The first plan creates the four resources and two canvas groups. Review the
complete plan, especially any destroy/replace actions. Applying changes is a
separate, deliberate operation:

```sh
pnpm run infra:apply
```

Never commit generated Railway domains, project UUIDs, or secret values. Do not
add a `railway.json`; the TypeScript definition owns both services and their
project resources. Railway TypeScript IaC is currently beta, so keep the pinned
SDK version and review release notes before upgrading it.

The source definition intentionally does not create a generated public domain.
The initial apply can provision the topology before these references exist, but
the web deployment will not become ready until they do. Generate a Railway
domain for `web`, then create these shared variables in the environment:

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

Adding shared variables triggers deployment without changing the IaC graph. IaC
fixes both services in Singapore, configures the readiness health check, restart
policy, pool and job timings, and gives the compiler worker a 4 GiB memory
limit. Adjust that limit only after measuring representative workloads.

## First deployment

1. Apply the reviewed IaC plan to provision all four resources.
2. Generate the web domain, set the shared variables above, and wait for web and
   worker to become healthy.
3. Visit `https://<web domain>/setup?token=<setup token>` and register the admin passkey.
4. Remove or rotate `SVERLIN_ADMIN_SETUP_TOKEN` after setup succeeds.
5. Create a disposable participant, sign in privately, create a project, and
   wait for its queued command to complete.
6. Run `SVERLIN_SMOKE_URL=https://<web domain> pnpm run smoke:deployment`.

`GET /api/health/live` checks the Node process. `GET /api/health/ready` checks
configuration, PostgreSQL, scratch space, and the compiler. Railway health
checks gate deployments but are not continuous monitoring.

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
