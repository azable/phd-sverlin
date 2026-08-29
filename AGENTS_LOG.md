# Central environment settings and simple Railway releases

This snapshot covers the completed environment-variable cleanup and the simpler
`main` → staging → manual production release path. No Railway project or
deployment was created or changed.

| Files                                                                | Change                                                                                                                                                                             |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`.railway/railway.ts`](.railway/railway.ts)                         | Connect both environments to CI-checked `main`, reference hosted settings from Railway shared variables, and express the worker drain window as job expiry plus a shutdown margin. |
| [`.env.example`](.env.example), [`compose.yaml`](compose.yaml)       | Keep local choices in `.env`, pass AI settings into the devcontainer, and persist Railway CLI login and project-link state in a named volume.                                      |
| [`.github/workflows/`](.github/workflows/)                           | Delete the custom production-promotion workflow; GitHub now verifies code but holds no Railway tokens, IDs, or deployment URLs.                                                    |
| [`README.md`](README.md), [`docs/deployment.md`](docs/deployment.md) | Explain the two sources of environment settings and the ordered manual production release in plain language, with Railway-specific terms defined where first used.                 |

## Resume

Implementation is complete, the final diff review is complete, and the application
lock is released. The next safe action is to commit these changes while preserving
the unrelated user edit listed under limitations. The CI-equivalent verification and runtime
images both build, static checks pass for the agent-authored files, all 105 unit
tests pass, and every starter example compiles through the production boundary.

When live Railway setup is authorized, create or link the intended project,
review and apply the checked-in graph separately to production and staging, add
the six shared variables named below, and turn off automatic deployments for
both production services in Railway's dashboard. No live plan, apply, variable,
domain, project, service, or deployment operation has been performed.

## Architecture and behavior

Local and hosted settings now have separate, simple homes:

- The ignored root `.env` contains only choices made by a local developer.
  Compose supplies database URLs, local application paths, and safe development
  defaults, then forwards `OPENAI_API_KEY`, `OPENAI_MODEL`, and
  `CHATBOT_CONFIG` into the devcontainer.
- The Docker-managed `railway-state` volume mounts at `/root/.railway` and
  retains Railway CLI login and local project-link state across devcontainer
  recreation without committing credentials or copying them into the image.
- Each Railway environment has one shared-variable list for
  `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL`, `SVERLIN_ADMIN_SETUP_TOKEN`,
  `OPENAI_API_KEY`, `OPENAI_MODEL`, and `CHATBOT_CONFIG`. The first, third, and
  fourth values should be sealed in Railway. Staging and production use
  different values.
- PostgreSQL and Bucket connection values remain automatic references to their
  Railway resources. Pool size, queue timing, and request timeout values come
  from checked-in application defaults, so they are not copied into deployment
  configuration.

Both services in both environments now use the same source:

```ts
const source = github('azable/phd-sverlin', {
  branch: 'main',
  checkSuites: true
});
```

Railway automatically deploys staging after the GitHub `verify` job succeeds.
Production also points to `main`, but an operator disables its automatic
deployments in Railway. A release therefore confirms staging is running the
latest `main`, manually deploys production `web` and waits for its database
update and readiness check, then manually deploys `worker` and runs the quick
deployment check. The deleted GitHub promotion workflow and its Railway secrets
are no longer part of the path.

The automatic-deployment switch is not supported by the installed TypeScript
Railway SDK. It must be set in the Railway dashboard after the initial apply and
rechecked after changing a service's source settings.

The worker drain window retains its existing 1,860-second value but now states
the policy explicitly: a 30-minute job-expiry window plus a 60-second shutdown
margin. The guide makes clear that this is a worst-case allowance for a slow AI
generation-and-repair command, not a fixed deployment delay; the old worker
stops as soon as its active command finishes.

The deployment guide now distinguishes previews from applied infrastructure
changes, names source files for the worker timing values, explains Railway terms
at first use, and uses the installed CLI's current `--remote` Codex connection
command. Repeated catch-all documentation links were removed in favor of links
next to the behavior they explain. Its runtime overview also shows the relevant
Dockerfile excerpt and explains how one image contains all three Node bundles
while Docker supplies the web command when no command is given and Railway
selects the web, migration, and worker commands explicitly, with a focused
`railway.ts` excerpt and direct line links to the complete service definitions.
The guide states directly that these command fields are authored in
`.railway/railway.ts` and become Railway service settings when it is applied.
Omission comments inside the abridged excerpt distinguish it from the complete
service objects linked immediately above it.

## Verification

- `pnpm run check` passed with zero Svelte or TypeScript diagnostics.
- `pnpm run lint` passed Prettier, ESLint, and the 208-name generated DSL index
  check before the unrelated `AGENTS.md` edit appeared. Focused Prettier and
  ESLint checks for the agent-authored configuration and documentation still
  pass; `pnpm run check:dsl-api-index` also passes.
- `SVERLIN_PROJECT_STORE=file pnpm run test:unit -- --run` passed 105 tests;
  two optional integration tests skipped.
- A local evaluation of `.railway/railway.ts` for both `staging` and
  `production` confirmed two GitHub-backed services on `main`, required GitHub
  checks, all six intended shared-variable references, and removal of redundant
  application-default overrides.
- A secret-safe rendered Compose check confirmed the devcontainer receives all
  three AI settings without printing their values.
- `docker build --target verification --tag sverlin-verification:local .`
  passed the full application build, checks, lint, unit suite, and every starter
  example.
- `docker build --target runtime --tag sverlin-runtime:local .` passed.
- The final source/documentation consistency review corrected the AI settings table
  to identify `web`, not `worker`, as the service that performs AI-assisted editing.
- `pnpm exec prettier --check docs/deployment.md AGENTS_LOG.md` and the final
  `git diff --check` passed after that correction.
- `pnpm exec prettier --check .railway/railway.ts AGENTS_LOG.md` and
  `pnpm exec eslint .railway/railway.ts` passed after naming the worker drain
  calculation; no remote Railway plan or apply was run.
- `pnpm exec prettier --check docs/deployment.md AGENTS_LOG.md` and
  `git diff --check` passed after the deployment-guide language review.
- No Svelte component behavior or Haskell source changed, so Playwright, solver
  tests, HLint, and the Haskell formatter were not required.

## Limitations and excluded changes

- Railway's production automatic-deployment setting remains a manual dashboard
  step; the runbook calls this out at setup and release time.
- The current container is not authenticated with Railway and this repository is
  not linked to a Railway project. After rebuilding, run
  `pnpm exec railway login` once; the new named volume retains that state. No
  deployment has occurred.
- Rebuild or recreate the devcontainer after changing `.env`; an already-created
  container does not receive newly forwarded Compose variables automatically.
- Rotate the current local `OPENAI_API_KEY` before hosting. An earlier diagnostic
  command expanded it into terminal output; the value is not stored here.
- The edit in
  [`.devcontainer/link-workspace-storage.mjs`](.devcontainer/link-workspace-storage.mjs)
  belongs to the user and is deliberately not modified or summarized as part of
  this implementation.
