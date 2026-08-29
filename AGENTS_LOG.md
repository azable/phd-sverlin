# Generated-storage cleanup and deployment build simplification

This snapshot removes obsolete generated storage and keeps production Docker
builds independent of editor, browser-test, lint, and formatter tooling.

| File                                                                                   | Change                                                                                                               |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| [`.devcontainer/link-workspace-storage.mjs`](.devcontainer/link-workspace-storage.mjs) | Remove quarantine creation and retry deletion briefly before surfacing a real failure.                               |
| [`.gitignore`](.gitignore), [`.dockerignore`](.dockerignore)                           | Remove exclusions for retired `.sverlin-stale-storage`, `.pnpm-store`, and `.swc` paths.                             |
| [`.prettierignore`](.prettierignore)                                                   | Remove the obsolete Cabal `compile/dist-newstyle*` exclusion.                                                        |
| [`Dockerfile`](Dockerfile)                                                             | Resolve Stack dependencies in a shared production-safe stage rather than copying them through the development image. |
| [`scripts/build.mjs`](scripts/build.mjs)                                               | Generate SvelteKit's derived configuration explicitly before the clean production build.                             |

## Resume

Implementation is complete. The next safe action is to commit and push these
seven modified files, then resume Railway setup one controlled step at a time. No
application lock is held. A read-only Railway limits query confirms that the
workspace is now on Hobby with an 8 GB per-replica memory ceiling, so the
configured 4 GiB worker is within the live limit. Production's PostgreSQL
service is running; its web and worker deployments still reflect the old commit
and failed at the former 20-minute build limit. Their GitHub deployment triggers
were disabled manually in the Railway UI. The empty staging environment exists,
but its earlier infrastructure apply returned success without creating the
planned resources.

## Architecture and behavior

The post-create helper still links `node_modules` and both local-package
`.stack-work` paths to their Docker-managed volumes under `/opt/sverlin-dev`.
When replacing an old real directory or incorrect symlink, it now makes three
short retries, 200 ms apart, and reports a persistent filesystem error instead
of moving generated data into an indefinitely retained hidden directory.

```js
await rm(linkPath, { recursive: true, force: true, maxRetries: 3, retryDelay: 200 });
```

The existing ignored quarantine contained only the old dependency tree from the
VirtioFS-to-volume migration. It was not consumed by any build and was removed,
recovering approximately 567 MB.

A wider storage audit also removed the 643 MB workspace `.pnpm-store` created by
a deleted 2026-08-21 devcontainer script. Current pnpm resolves its store to
`/root/.local/share/pnpm/store/v10`, and active dependencies live in the
Docker-managed `node_modules` volume. The empty root `dist-newstyle` directory
and broken `.cache/cabal` and `.local/state/cabal` symlinks were also removed;
current build configuration uses Stack and no Cabal paths or volumes.

The 4.1 MB `.swc` cache was also removed. Its sole Wasm binary identified itself
as Workflow DevKit's SWC transform for `"use workflow"` and `"use step"`
directives. Sverlin has no current Workflow DevKit dependency, directive, or
source import; durable project commands use PostgreSQL and pg-boss instead.

A second hygiene pass removed an older 12 MB shadcn-svelte `pnpm dlx`
extraction after verifying that pnpm's live `pkg` link targets the newer cache
entry and no process had the superseded extraction open. Empty untracked
`src/workflows/` and `src/routes/dev/` directories were also removed; Git
history contains no tracked files at either path and current routing/source has
no consumer.

The Docker stage graph now forks after production compiler dependencies have
been resolved:

```dockerfile
FROM toolchain AS compiler-dependencies
RUN stack build --jobs=1 --only-dependencies

FROM compiler-dependencies AS development
FROM compiler-dependencies AS build
```

Only `development` installs Playwright browser libraries, Haskell Language
Server, hindent, HLint, and stylish-haskell. The production `build` stage no
longer inherits or copies from that stage. A clean build also runs `svelte-kit
sync` before Vite, avoiding the warning caused by reading `tsconfig.json` before
`.svelte-kit/tsconfig.json` exists.

Project timelines and archives under `data/`, compiler and benchmark artifacts
under `outputs/`, active Stack/Node volumes, Playwright/pnpm/TypeScript caches,
recent Docker images, and Docker build cache were deliberately retained. They
are either source-of-truth data, current configured storage, or useful recent
rebuild inputs rather than demonstrated stale storage.

## Verification

- `node --check .devcontainer/link-workspace-storage.mjs` passed.
- Running the helper reported all three links already use Docker-managed storage.
- Each link resolves to its expected `/opt/sverlin-dev` volume path.
- The quarantine no longer exists; only this work-log record still names it.
- Current `pnpm store path` is `/root/.local/share/pnpm/store/v10`, and
  `pnpm list --depth 0` passes without recreating `.pnpm-store`.
- The old pnpm/Cabal paths no longer exist; repository search finds no live
  configuration or source reference to them.
- `.swc` no longer exists, and neither the current dependency graph nor project
  source contains Workflow DevKit or its directives.
- The shadcn `dlx` cache retains its live target and the retired extraction is
  absent; the two abandoned empty source directories are absent.
- Docker parsed all eight named targets, including the new
  `compiler-dependencies` stage.
- A cold ARM64 `runtime` image build completed successfully without executing
  the `development` stage. The shared Stack dependency layer took about 12.8
  minutes; the application build then completed in about 70 seconds.
- The runtime image smoke test confirmed Node 24.19.0, GHC 9.10.3, HiGHS
  1.15.1, the web/worker/migration bundles, and the prepared compiler. It also
  confirmed that HLS, hindent, HLint, and stylish-haskell are absent.
- The complete Docker `verification` target passed: `svelte-check` reported zero
  errors and warnings; formatting, ESLint, and the generated DSL API index check
  passed; 105 enabled unit tests passed; and every catalogued starter compiled
  successfully through the production boundary.
- The final `runtime` target rebuilt successfully from the verified application
  layers after the explicit SvelteKit sync was added.
- `git diff --check` passed before this log update.

## Limitations and excluded changes

- A destructive-path recovery test was not performed because it would replace
  active dependency/build links. The normal idempotent path was exercised.
- The production build reports an existing non-blocking Vite warning for a
  client chunk larger than 500 kB. Addressing application code splitting is a
  separate performance change and is not required for deployment correctness.
- Warnings from pinned third-party and vendored Haskell packages remain
  non-fatal. No project-owned Haskell source changed.
- Railway's [public Hobby summary](https://railway.com/pricing) says five
  replicas, while its comparison table, [detailed plan
  documentation](https://docs.railway.com/pricing/plans), and this workspace's
  live limit say six. The live limits query also returned `$0` for included
  usage, while both official pricing pages say Hobby includes $5 monthly usage.
  Use the Billing dashboard as the authority for charges; neither discrepancy
  affects the configured single-replica services.
- The live limits API does not expose build timeout. Railway's current pricing
  table publishes a 40-minute Hobby limit, but the first upgraded deployment is
  still needed to confirm enforcement for this workspace.
- No Railway resource was mutated while diagnosing or simplifying this build.
