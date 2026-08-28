# Compiler runtime boundary

Railway runs the same image as a SvelteKit web service and a private worker
service. The compiler runs directly inside each worker; it is not exposed as a
network service.

## Request and execution flow

```text
authenticated browser
  -> SvelteKit authorizes and validates a command
  -> pg-boss stores an idempotent PostgreSQL job (HTTP 202)
  -> worker receives one job for a participant
  -> prepared compile-app runs in a fresh temporary workspace
  -> bounded output is parsed and SHA-256 verified
  -> resources are stored immutably in a private Railway Bucket
  -> Timeline events and project head commit in PostgreSQL
  -> browser observes job status and Timeline deltas
```

The source boundaries remain one-way: `src/lib/shared` owns portable contracts;
`src/lib/client` owns polling and presentation; `src/lib/server/projects` owns
authorization-aware persistence and commands; `src/lib/server/compiler` owns
the compiler package boundary; and `compile/app`/`compile/src` own Haskell
orchestration and semantics.

## Queue durability and idempotency

pg-boss owns queue tables, delivery, retries, heartbeats, retention, and
distributed group concurrency. The project operation UUID is also the job ID,
so sending the same command twice returns the existing job. The participant's
Better Auth user ID is the pg-boss group ID; `groupConcurrency: 1` prevents two
commands for that participant from running concurrently across worker replicas.

The immutable Timeline remains the domain source of truth. Every mutation
includes its expected head, and the repository locks the project row before
appending contiguous events. If execution throws after an append committed, the
worker looks for the command-specific terminal event. Complete work is accepted;
partial lifecycle work receives explicit cancellation and notification events.

Normal command failures are recorded as job output and exposed as `failed` by
the API. A database or recovery failure is thrown to pg-boss, which permits one
backoff retry. Heartbeats recover work abandoned by a crashed worker, and a
30-minute absolute expiry prevents a genuinely stuck execution from remaining
active forever. Completed job metadata is retained for seven days.

## Concurrency

Each worker process handles one command at a time. Start with one Railway worker
replica; this is the least costly and safest default for the memory-heavy GHC and
solver runtime. If measurements justify more throughput, Railway replicas can
process different participants concurrently while pg-boss continues to
serialize each participant's work. There is no application-owned compile-slot
table or polling loop.

The in-process `CompileScheduler` remains relevant to local file mode and deep
health checks. Worker deployments disable speculative prefetch so durable queue
scheduling stays authoritative.

## Compiler package boundary

`prepare:compiler` builds `compile-app` once and records its executable, source
fingerprint, GHC package environment, and required package data directories.
The runtime image retains GHC because `compile-app` uses Hint to compile the
submitted Sverlin program at runtime. Replacing the Dockerfile with a plain Node
builder would therefore break compilation.

`compileSource` creates a unique scratch workspace, invokes the prepared binary
without a shell, bounds stdout/stderr and output sizes, validates the manifest
and IR, verifies content hashes, and removes disposable files.

Sverlin source remains trusted Haskell-based authoring input. Temporary
directories and direct process execution prevent accidental cross-job reuse;
they are not a hostile multi-tenant sandbox. Allowing participants to submit
arbitrary hostile source would require an OS-isolated compiler or sandbox
service.

## Persistence and authentication

PostgreSQL owns Better Auth records, project ownership and summaries, immutable
Timeline events, resource metadata, and pg-boss jobs. The private Bucket owns
immutable resources at `projects/<project-id>/sha256-<digest>`. Uploads use
create-if-absent semantics and validate existing object metadata. Container
filesystems hold only disposable scratch data.

Better Auth provides the researcher passkey and participant username/password
flows. The Admin plugin creates accounts, rotates passwords, bans/unbans users,
and revokes sessions. Projects store the Better Auth owner ID; participant
queries filter by it while the administrator may explicitly view every project.

## Shutdown and operational limits

On `SIGTERM`, pg-boss stops fetching work and waits for the active handler before
the worker closes compiler and database resources. Railway's worker drain window
must exceed `SVERLIN_JOB_EXPIRE_SECONDS`; otherwise the platform may force-kill
the process first and pg-boss will recover it after the missing heartbeat.

- Start with one worker at 4 GB RAM and measure peak memory before scaling.
- Keep `SVERLIN_JOB_HEARTBEAT_SECONDS` well below the job expiry.
- Count both Drizzle and pg-boss pools across every web and worker replica.
- Monitor queue age, failed jobs, PostgreSQL capacity, and worker memory before recruitment.
- Treat a PostgreSQL dump and Bucket export as one backup generation.
- If commands approach the 30-minute expiry, split generation and compilation
  into checkpointed stages instead of indefinitely extending one job.
