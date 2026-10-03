# Sverlin

Sverlin is a SvelteKit research application for creating and reviewing algorithm visualizations. PostgreSQL stores each project as an immutable event Timeline. The web process accepts operations into the Timeline, runs them asynchronously with bounded in-process capacity, and records success or failure. Participants can discuss, edit, step through, and compare retained presentations.

## Visualization modes

Developer-registered modes are listed in [`src/lib/modes/catalog.ts`](src/lib/modes/catalog.ts). Each mode folder owns its starter artifact, assistant, validation/build code, and playback component:

| Mode      | Authored artifact                                     | Playback                                                                              |
| --------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `sverlin` | One self-contained Svelte 5 component (`Main.svelte`) | Bundled Svelte runtime and component, seeded and stepped in an isolated browser frame |
| `html`    | A JSON manifest of script-free, complete HTML frames  | Sanitized HTML, one frame per step                                                    |
| `html-js` | JSON containing separate HTML and JavaScript          | Sanitized HTML plus JavaScript in an isolated browser frame                           |

Administrator projects offer a blank starter in every mode and one populated Svelte example, [linear search](src/lib/modes/sverlin/contract.ts). No other example programs are bundled.

Generated JavaScript is compiled but **never executed by the server** or in the application origin. Authored HTML is vetted with [`sanitize-html`](https://github.com/apostrophecms/sanitize-html); executable presentations use an opaque-origin, sandboxed iframe and a restrictive [Content Security Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) that blocks external imports, resource loads, and network APIs. A browser sandbox alone cannot guarantee that arbitrary JavaScript never attempts to navigate its own frame to an external URL. The static HTML condition forbids scripts entirely. Source limits and import checks are in the mode build files, and iframe policy is in [`src/lib/modes/sandbox.ts`](src/lib/modes/sandbox.ts).

Shared project orchestration lives in [`src/lib/server/projects/`](src/lib/server/projects/) and its environment-neutral contracts in [`src/lib/shared/projects/`](src/lib/shared/projects/). The browser workspace lives in [`src/lib/client/projects/`](src/lib/client/projects/). Module-specific code stays under its mode folder; browser-safe contracts do not import server code.

A **mode** owns the authoring workflow, validation/build implementation, and playback component. A **build** validates source and prepares a **presentation**; **playback** displays and steps through that presentation in the browser. Study conditions select a mode and configure its workspace; a study run's **kind** distinguishes participant runs from previews. Labels and artifact formats come from the mode catalogue.

## Development

Use the Dev Container and its checked-in devenv environment. [`devenv.nix`](devenv.nix) supplies Node 24, pnpm 10, PostgreSQL 17, and the local process manager. Interactive terminals activate the environment through [`.envrc`](.envrc); for a non-interactive command, use `devenv shell -- COMMAND`. If `.env` does not exist, copy [`.env.example`](.env.example) to `.env` and set `OPENAI_API_KEY` for AI-assisted editing. Keep personal values out of Git.

In VS Code, install the recommended Svelte extension. [`.vscode/settings.json`](.vscode/settings.json) enables its TypeScript plugin so `.ts` files can resolve Svelte components and their props. If component imports remain marked as missing, run **TypeScript: Restart TS Server** from the Command Palette. Use `pnpm run check` for project diagnostics; plain `tsc` does not understand Svelte component declarations.

Server commands (`dev`, `dev:web`, `preview`, and `start`) reload the current `.env` through [`scripts/run-with-env.sh`](scripts/run-with-env.sh), overriding stale inherited values. Shells and server launches share [`scripts/load-env.sh`](scripts/load-env.sh); blank database and authentication settings receive development defaults only inside devenv. After editing `.env`, restart the web process (`devenv processes restart web` when managed by devenv); the process manager and PostgreSQL can stay running. Environment changes require a new server launch, rather than relying on Vite's hot reload. PostgreSQL tests keep their isolated database URL because the test runner invokes migrations directly.

```sh
devenv up                 # PostgreSQL, migration, and the application
devenv down               # stop managed processes
devenv up -d postgres     # PostgreSQL alone for database tests
pnpm run dev              # migrate and run the application when managing PostgreSQL separately
pnpm run dev:web          # run the application when migrations are already current
```

The application uses <http://localhost:5173>. Source edits, type checks, linting, and tests can run while the development server stays up; Vite applies source changes through hot reload. Reuse that server for browser verification and check listening ports before starting another. PostgreSQL integration tests use an isolated test database, as described below. Coordinate changes that require a restart or may interrupt active work. The web process owns asynchronous work and cancels it on shutdown; see [`src/lib/server/runtime-state.ts`](src/lib/server/runtime-state.ts). `/api/health/ready` reports whether the local process is ready.

The consolidated [`drizzle/0000_lying_jean_grey.sql`](drizzle/0000_lying_jean_grey.sql) is a **fresh-database baseline**. It does not migrate projects or credentials from earlier compiler versions. The local development database was reset for this branch; any other existing database needs its own deliberate reset before applying this baseline, followed by new administrator registration. Do not treat `.devenv/state/postgres` as a disposable build cache. The canonical export command below is the supported way to inspect complete project histories or retained operation failures.

```sh
pnpm run check
pnpm run lint
pnpm run test:unit
pnpm run test:postgres
pnpm run test               # unit and PostgreSQL integration tests
pnpm run build
pnpm run export:data -- --scope projects
```

`test:postgres` creates an isolated test database and requires only PostgreSQL to be running. `pnpm run export:data -- --scope projects --project PROJECT_ID` selects one project. Exports include complete Timelines, versioned study definitions, and interaction telemetry where available; see [`src/lib/server/data-export.ts`](src/lib/server/data-export.ts).

Project and export formats start at version 1. The fresh database baseline uses `mode` for visualization workflows and `kind` for participant/preview study runs.

## Study and operations

[`src/lib/studies/main.ts`](src/lib/studies/main.ts) defines the sole main study (`main-study`, version 1), registered for enrollment in [`src/lib/shared/study/registry.ts`](src/lib/shared/study/registry.ts). Concrete study definitions live under `src/lib/studies/`; reusable study contracts, projections, and interaction schemas remain under [`src/lib/shared/study/`](src/lib/shared/study/). The main study compares Svelte-backed `sverlin` in a two-candidate workspace with script-free, per-frame `html` in a single-candidate workspace. The separate `html-js` mode is not a study condition. The protocol defines the counterbalanced order, 15-minute task duration, and interaction-capture policy; the comments beside its limits explain their sampling and delivery tradeoffs.

New blank projects start with three intake turns before authoring. The assistants use a bounded five-call ladder: one initial call, up to three repairs, and a simpler fallback that explains what it reduced. Provider retries are disabled. The default 180-second request ceiling and study deadline bound each attempt; see [`src/lib/server/chat-bots/attempt-profiles.ts`](src/lib/server/chat-bots/attempt-profiles.ts), [`src/lib/server/projects/commands.ts`](src/lib/server/projects/commands.ts), and [`src/lib/server/projects/operations.ts`](src/lib/server/projects/operations.ts). Generated source, attempts, diagnostics, accepted artifacts, and presentations remain in the project Timeline. Interrupted work is explicitly failed and can be retried by the user.

After resetting the database, open the app and register a new administrator passkey at the one-time setup page. From `/admin`, create a participant, assign the open study version, and use a preview to verify both conditions before inviting participants.
