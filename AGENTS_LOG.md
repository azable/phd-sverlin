# Stack-based compiler workflow, CI-gated deployment, and API analysis

## Resume

Implementation is complete. The next safe action is review and commit the
current agent-authored migration, deployment, and API-analysis changes while
preserving the concurrent files named under limitations. Cabal-install,
`cabal.project`, Cabal cache/state volumes, and `dist-newstyle` have been
replaced by Stack 3.3.1 with pinned LTS 24.52. The rebuilt devcontainer uses
`/opt/sverlin-dev/stack-root` plus linked named-volume paths for `node_modules`,
the compiler `.stack-work`, and vendored MIP `.stack-work`. Compiler preparation,
static checks, Haskell checks, solver tests, unit tests, all starter examples,
the Docker verification target, and the final runtime compiler smoke test pass.

The required full Hindent then Stylish Haskell pipeline ran exactly once after
the final Haskell source changes; all subsequent verification was non-modifying.
The application lock has been released. The runtime preserves Stack/GHC package
databases at their original absolute paths, validates the prepared compiler's
exact mutable local unit registration, and includes the native linker names
needed by request-time Hint interpretation. No live Railway or GitHub project
state was changed.

The old VirtioFS-backed `node_modules` could not be recursively removed because
some generated files returned `EBADF`; the helper preserved it under the
ignored `.sverlin-stale-storage/` quarantine and installed a clean dependency
volume. Repository integrity is sound: `git fsck` passed and all 503 present
tracked files were readable with no I/O errors. Remove the quarantine from the
host only after the devcontainer is closed; it is not used by any build.

The LinearTrace API/slot investigation is complete as analysis. Its restart-safe
handoff is `compile/src/LinearTrace/API_refactoring.md`; no recommended API or
frontend behavior has been implemented by that document. The next safe API
action is to select one staged slice from its decision/implementation sections,
then acquire the app lock before any Svelte behavior change. The note preserves
the inline TODO answers, corrects the earlier owner-lineage assessment, names
the relevant historical commits/files, and distinguishes proven regressions
from archived experiments. `compile/src/LinearTrace/API_plan.md` is the current
authoritative target design. The evidence document now includes a concise
restart handoff pointing to that plan and summarizing the settled Domain,
Program, Render, Sverlin-facade, host-boundary, and slot decisions. No API
implementation has begun.

| Files                                                                                                                                                                                                                                                                                | Change                                                                                                                                                                                                     |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json), [`.devcontainer/devcontainer-lock.json`](.devcontainer/devcontainer-lock.json), [`.devcontainer/link-workspace-storage.mjs`](.devcontainer/link-workspace-storage.mjs), [`compose.yaml`](compose.yaml)         | Add pinned isolated Docker-in-Docker; persist Node/Stack data outside the workspace overlay; repair the three conventional tool paths during post-create; quarantine irrecoverably stale generated trees.  |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml), [`.github/workflows/promote-production.yml`](.github/workflows/promote-production.yml)                                                                                                                                       | Add full Docker verification and manual, exact-SHA staging verification plus ordered production promotion.                                                                                                 |
| [`.railway/railway.ts`](.railway/railway.ts)                                                                                                                                                                                                                                         | Make staging a CI-gated `main` source and production an empty source deployable only through the promotion workflow.                                                                                       |
| [`Dockerfile`](Dockerfile)                                                                                                                                                                                                                                                           | Seed and reuse a metadata-keyed Stack snapshot at one stable absolute path, build through Stack, and package exact package databases plus request-time linker libraries into the slim interpreter runtime. |
| [`compile/stack.yaml`](compile/stack.yaml), [`compile/stack.yaml.lock`](compile/stack.yaml.lock), [`compile/compile.cabal`](compile/compile.cabal), [`compile/hie.yaml`](compile/hie.yaml), [`compile/.gitignore`](compile/.gitignore)                                               | Pin LTS 24.52 and non-snapshot solver dependencies, use the Stack HLS cradle, accept Stack's Cabal library, and ignore linked `.stack-work` paths.                                                         |
| [`package.json`](package.json), [`scripts/stack-environment.mjs`](scripts/stack-environment.mjs), [`scripts/run-stack.mjs`](scripts/run-stack.mjs), [`scripts/prepare-compiler.mjs`](scripts/prepare-compiler.mjs), [`scripts/run-compile.mjs`](scripts/run-compile.mjs)             | Replace Cabal command orchestration with signal-aware Stack commands and generate the direct compiler's exact GHC package environment from Stack package databases.                                        |
| [`src/lib/server/compiler/prepared-compiler.js`](src/lib/server/compiler/prepared-compiler.js), [`src/lib/server/compiler/prepared-compiler.test.ts`](src/lib/server/compiler/prepared-compiler.test.ts), [`src/lib/server/compiler/compile.ts`](src/lib/server/compiler/compile.ts) | Fingerprint Stack metadata, ignore generated `.stack-work`, reject stale exact local package registrations, test both drift modes, and update compiler-boundary terminology.                               |
| [`scripts/dsl-api-index.mjs`](scripts/dsl-api-index.mjs), [`src/lib/server/chat-bots/ai-assistant/dsl-api-index.md`](src/lib/server/chat-bots/ai-assistant/dsl-api-index.md)                                                                                                         | Run facade inspection in Stack GHCi and normalize qualified GHC 9.10 output; regenerate the 208-name index with a stable `Maybe` signature.                                                                |
| [`.devcontainer/`](.devcontainer/), [`scripts/`](scripts/)                                                                                                                                                                                                                           | Delete obsolete Cabal configuration and command/environment wrappers; replace them with the linked-storage and Stack helpers above.                                                                        |
| [`README.md`](README.md), [`docs/deployment.md`](docs/deployment.md)                                                                                                                                                                                                                 | Document the Stack dev workflow, isolated environments, CI, promotion, partial failures, configuration, and diagnostics; remove the redundant `.railway/README.md`.                                        |
| [`compile/src/LinearTrace/Choreography.hs`](compile/src/LinearTrace/Choreography.hs)                                                                                                                                                                                                 | Record the slot-restoration contract: owner identity, read/write lifecycle, historical example/test, view projection, and multi-slot boundary.                                                             |
| [`compile/src/LinearTrace/API_refactoring.md`](compile/src/LinearTrace/API_refactoring.md), [`compile/src/LinearTrace/API_plan.md`](compile/src/LinearTrace/API_plan.md)                                                                                                             | Preserve the full API evidence and restart handoff alongside the concise, authoritative target API design and per-operation examples.                                                                      |
| [`compile/src/LinearTrace/View/Build.hs`](compile/src/LinearTrace/View/Build.hs), [`compile/src/LinearTrace/Visualization/IR.hs`](compile/src/LinearTrace/Visualization/IR.hs)                                                                                                       | Normalize two comment gaps through the required full Haskell formatter pipeline.                                                                                                                           |

## Architecture and behavior

One TypeScript IaC graph still owns web, worker, PostgreSQL, Bucket, references,
placement, health checks, and drain policy in each environment. Its source is
selected from Railway environment context:

```ts
const source = ctx.isEnvironment('staging')
  ? github('azable/phd-sverlin', { branch: 'main', checkSuites: true })
  : empty();
```

Pull requests and `main` build the Docker `verification` target and final
`runtime` target under one required `verify` job. A manual promotion accepts
only a full SHA on `main` with a successful check, requires the latest staging
deployments for both services to be that SHA and successful, and verifies
staging's reported build SHA. It then sets each service's `SVERLIN_BUILD_SHA`
without triggering a deployment and uploads that checkout to production web
first, allowing migrations and readiness to finish, followed by worker and an
exact-SHA production smoke test. Railway messages and the GitHub workflow
summary record the SHA and actor. A worker
failure after web succeeds is reported as a partial release and is retried at
the same SHA; database rollback is never automatic.

Production and staging use separate GitHub environments, Railway project
tokens, smoke URLs, shared secrets, PostgreSQL databases, Buckets, and private
networks. The root README remains a compact entry point; the deployment runbook
owns setup, release, diagnostics, backup, and incident detail.

The devcontainer declares the official `docker-in-docker:4` feature. Its
lockfile resolves version `4.1.0` by digest; feature metadata supplies the
privileged runtime, Docker daemon entrypoint, Buildx/Compose tooling, and
per-devcontainer Docker/containerd volumes. This keeps local Docker builds
isolated from the host socket and avoids duplicating feature-owned mounts or
lifecycle configuration in `compose.yaml`.

Only editable repository source crosses Docker VMM's VirtioFS bind. Compose
mounts Node modules, Stack's package root, and both local-package work trees at
stable paths under `/opt/sverlin-dev`. The post-create helper links the three
conventional workspace paths (`node_modules` and the two `.stack-work` paths)
before installation or compilation; Stack uses its package root directly via
`STACK_ROOT`. If a corrupt generated tree cannot be removed, the helper first
renames it into `.sverlin-stale-storage` so setup can continue without data
loss. This layout avoids editor or agent workspace overlays hiding nested named
volumes. PostgreSQL and application state remain separate volumes. Docker VMM
users must explicitly share the repository path before rebuilding. Direct
read-only binds of `~/.ssh` and `~/.gitconfig` were removed; VS Code Dev
Containers forwards an active host SSH agent and copies host Git configuration
without exposing private-key files.

Stack is now the only project build driver. `compile/stack.yaml` selects LTS
24.52/GHC 9.10.3, includes the vendored MIP package, pins extra solver packages
through `stack.yaml.lock`, requires the image-provided GHC, and enables the
LBFGSB backend. The `.cabal` files remain solely as package manifests consumed
by Stack's Cabal library; the `cabal` executable, project/freeze configuration,
index/cache state, and `dist-newstyle` are gone. Package scripts route builds,
tests, benchmarks, GHCi API inspection, and compiler preparation through Stack.
Preparation records the Stack binary and creates a GHC environment containing
the snapshot and local package databases plus exact unit IDs, so request-time
Hint interpretation does not need Stack itself.

The final deployable image starts from `haskell:9.10.3-slim-bookworm` instead of
inheriting the complete build toolchain. GHC and registered library artifacts
remain necessary because project commands interpret generated Sverlin source at
request time. The image copies a stable prepared-compiler descriptor, compiler
binary, GHC environment, Stack snapshot/local package databases at their
original absolute paths, selected compiler source/font/vendor inputs, solver,
production Node dependencies, and runtime shared libraries. Stack and
cabal-install are removed from the runtime; HLS, HLint, Hindent, Stylish
Haskell, browser tooling, CMake, Git, jq, and pnpm remain in discarded
development or build stages.

The official Railway OAuth MCP entry was installed for Codex outside the
repository. Restart Codex and complete OAuth before using it. The current
session exposes no GitHub connector installer, so GitHub read access must be
connected through Codex plugin settings; writes should continue to require
approval.

The choreography facade now records the intended restoration boundary without
changing behavior: the persistent owner `BlockId` identifies one storage
location, `Slot` is its reconstructed linear occupancy proof, reads and writes
cycle through unseal/copy-or-replace/reseal, and the view must retain the
owner-child relationship. Multiple same-typed slots on one owner require an
explicit owner/key/role `SlotId` rather than overloading owner identity.
The TODO also identifies the concrete historical projection in commit
`970907d`'s `compile/app/DSL/Main.hs`: declaration and write used `sameBounds`
with `BlockRef`-derived owner geometry, allowing replacement children with new
IDs to reuse the persistent location. Its variable/Fibonacci program is also
named as the example to adapt to the current body-only source contract and use
as an end-to-end regression: seal on declaration, copy and reseal on read, and
replace and reseal on write.

The API-refactoring handoff extends that concise TODO with the broader evidence
needed to implement it safely. Core already records `TraceSeal` and
`TraceUnseal` with actual owner/child snapshots, so reusing the same owner
`BlockId` does provide trace-level storage lineage; the missing current behavior
is that `Choreography.Graph` drops those events and the facade omits the public
operations. Historical rendering also separated stable owner/location identity
from replaceable occupant/render identity. Current internal `RenderContinue`
only models continuation of the old occupant and is not a public slot feature,
so a restored write needs an adoption/three-party identity decision rather than
blindly reusing continuation.

The same handoff answers the remaining inline and deleted-audit questions. It
recommends a narrow `Sverlin`/`Program` author facade and separate host seam;
finite affine cases for symmetric bridges; explicit treatment of soft
constraints currently ignored by affine sampling; configurable but
deterministic canvas/style profiles; generated structural IR validation with
handwritten semantic invariants; and an eventual parsed DSL boundary instead of
treating body-only Haskell as a sandbox. It also locates the frontend geometry
and enter/exit transition regression at the SVG typography conversion in
`9efb493`, not at the later removal of the non-temporal `View.Patch`, and names
`03c4e14` as the most complete SVG-transition/slot donor to adapt to current
typography.

## Verification

- `pnpm run check` passed with zero diagnostics; `pnpm run lint` passed
  Prettier, ESLint, and the generated 208-name DSL index drift check.
- `SVERLIN_PROJECT_STORE=file pnpm run test:unit -- --run` passed 105 tests;
  two opt-in tests skipped. The prepared-compiler suite passed all 10 cases,
  including source drift and mutable Stack package-registration drift.
- `pnpm run test:examples` passed every catalogued starter through the
  production compiler boundary. The seeded Minimal compile also passed.
- LTS 24.52 resolved, compiler preparation passed with exact package unit IDs,
  `pnpm run test:solver` passed all 96 cases, and `pnpm run lint:haskell`
  reported no hints.
- The required final `pnpm run format:haskell` pipeline (Hindent followed by
  Stylish Haskell) completed exactly once; subsequent checks were read-only.
- `docker build --target verification -t sverlin-verification:stack .` passed
  static checks, lint, 105 unit tests with two skips, and all starter examples.
  The metadata-keyed dependency seed was reused by the source-keyed build stage.
- `docker build --target runtime -t sverlin-runtime:stack .` passed. Inside the
  final arm64 image, Node 24.19.0, GHC 9.10.3, HiGHS 1.15.1, and `flock` ran;
  Stack and Cabal were absent; direct Hint-backed compilation of
  `examples/Minimal.sverlin` produced non-empty JSON. Image size is 979,116,108
  bytes.
- `docker build --target development -t sverlin-development:stack .` passed
  from a cold Stack cache. Its smoke test confirmed Stack 3.3.1, HLS 2.14.0.0,
  Hindent 6.3.0, HLint 3.10, Stylish Haskell 0.15.1.0, and the snapshot seed.
- Dev Container CLI `0.82.0` resolved Docker-in-Docker `4.1.0` and its integrity
  digest; the checked-in lockfile matches.
- `docker compose config --quiet` — passed; the rendered workspace graph uses
  external Node/Stack volumes beneath `/opt/sverlin-dev` and no generated-data
  volume is nested under the workspace bind.
- Storage recovery — the helper quarantined the unreadable generated
  `node_modules`, linked all three Node/Stack work paths to Docker storage, and
  `pnpm install --frozen-lockfile` completed against the clean volume. Its own
  syntax check and ignore checks pass.
- Repository corruption audit — `git fsck --no-progress` exited zero (only
  ordinary dangling edit objects); a complete read audit covered all 503
  currently present tracked files with zero failures. Six tracked paths are
  intentionally deleted by the current uncommitted work.
- Railway graph evaluation produced the expected six-resource staging and
  production graphs; the promotion parser passed synthetic latest-deployment
  SHA/status extraction. No live infrastructure was changed.
- API-refactoring handoff — all named historical commits resolved with
  `git log --no-walk`; `git diff --check` passed for the tracked tree, and
  `git diff --no-index --check -- /dev/null compile/src/LinearTrace/API_refactoring.md`
  emitted no whitespace diagnostics for the new file (its expected status is 1
  because the file differs from `/dev/null`).
- Stack migration syntax/whitespace — all new JavaScript helpers pass
  `node --check`; `.stack-work` symlinks are ignored; `git diff --check` passes;
  the lockfile has normal `0644` permissions.

## Limitations and operational notes

- Docker storage was expanded after the earlier exhaustion. The isolated daemon
  completed the cold snapshot, verification, and runtime builds.
- The clean Node/Stack links work in the current container, but the checked-in
  Compose/devcontainer lifecycle and newly seeded image must still be exercised
  by rebuilding. Do not delete `.sverlin-stale-storage` from inside the running
  container; close it and remove that ignored quarantine from the host when it
  is no longer needed.
- Rotate the current `OPENAI_API_KEY`: `docker compose config` expanded it into
  diagnostic command output while the mount graph was being inspected. The
  value is not recorded in this file.
- The Railway CLI is not authenticated or linked in this workspace. No live
  plan, environment creation, apply, source change, domain, variable, token,
  deployment, log, metric, or smoke operation was performed.
- GitHub branch protection, environments, reviewer policy, variables, secrets,
  and connector authorization remain operator setup steps documented in the
  runbook.
- The CLI installed Railway's official OAuth MCP config at the user level; a
  Codex restart is required before it becomes available.
- The pre-existing `commit` and affine-constraint TODOs in
  `compile/src/LinearTrace/Choreography.hs` appeared before the facade TODO and
  remain unmodified user or concurrent-worker work. Their current/history
  analysis is now preserved in `compile/src/LinearTrace/API_refactoring.md`.
- `examples/LinearSearch.sverlin` changed while this task was in progress and is
  deliberately excluded as user or concurrent-worker work.
- `compile/src/LinearTrace/API_plan.md` also appeared and changed while the Stack
  migration was in progress; it is treated as concurrent-worker work and was
  not modified or summarized by this task.
