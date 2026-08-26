# Post-`181a53d` refactor index

## Purpose and recovery point

`181a53dd8da80bbf131e4f1d8c23f682c8d5759f` is the restored baseline. It is
the direct parent of the large 24 August 2026 refactor and already contains the
linear `Block` choreography, affine/MIP visual solver, coherent generative style
profiles, managed typography, bundled fonts, code highlighting, API-index
generation, and unified canvas grouping.

The complete post-baseline history remains reachable at branch
`archive/post-181-refactor`, currently pointing to
`b0b51a30004777b56fa67d5fdb14f9d0b2598dae`. This branch was created before
resetting `main`; no uncommitted work needed to be stashed.

Useful inspection commands:

```sh
git log --reverse --oneline 181a53d..archive/post-181-refactor
git show <commit> -- <path>
git diff 181a53d..archive/post-181-refactor -- <path>
```

The commits after this point are highly coupled. Prefer extracting a bounded
feature or restoring selected paths over cherry-picking either major refactor
wholesale.

The 35 project timelines created after the baseline commit time, including all
content-addressed source, prompt, compiler-log, and render resources, are stored
under `data/project-archives/post-181a53d-runs-20260824-20260826/`. Its README
records the selection boundary and restoration procedure, while `manifest.tsv`
indexes each project by schema, timestamps, event/error counts, and size. The
archive is intentionally ignored by Git.

## Baseline API and behavior

The supported body-only source has two declarations:

```haskell
program :: Choreography ()
visualization :: VisualizationBuilder ()
```

The public facade has 208 indexed names:

- 70 program, lifecycle, payload, fact/query, and result-wrapper names;
- 138 visual selection, hierarchy, geometry, style, typography, solver, and
  constraint names.

Important baseline properties:

- `Block tag` is an opaque linearly consumed live resource.
- Lifecycle operations produce linear `Pending` obligations that must be
  materialized or otherwise discharged.
- `copy` records a fork; `replace` records continuity; the visualization
  compiler lowers these to `RenderFork` and `RenderContinue` so render instances
  can animate lineage smoothly.
- Facts and typed `select @Tag` queries bind semantic snapshots to visual nodes.
- The visual API supports nested generated nodes, affine geometry, bounded
  variables, hard constraints, named `oneOf` composition alternatives, style
  families, and compiler-generated coherent profiles.
- Typography is measured and compiled with HarfBuzz and bundled font resources.
  Code supports wrapping, language-aware highlighting, and checkpoint-specific
  emphasized source ranges.

Known baseline limitations:

- The large visual API is difficult for a code model to author reliably. Logs
  contain parse/type errors, overconstraint, overlap, dangling notation, and
  visually odd compositions.
- The pre-refactor linear-search generation failed first on a visual-alternative
  parse error and then on an `Int`/`QueryInt` mismatch.
- `use` consumes a Block correctly but exposes its payload for a one-use
  calculation. The type system therefore protects lifetime ownership more
  strongly than it protects semantic/provenance completeness.
- The internal `Slot owner tag` and `seal`/`unseal` implementation exists, but
  the canonical facade exports `SlotHandle` and result wrappers without
  exporting the operations. Slot authoring is incomplete at this exact commit.
- There is no first-class finite input/flow model, persistent typed
  relation/event API, or connector authoring API.
- Static generated nodes could be pruned unexpectedly; one successful
  pre-refactor Fibonacci render lost its authored title this way.

## Commit index

### `4f8824409ddd2ea8d1a8d63bd2a14f441430c8f2` — Major refactor temp commit #1

Size: 100 files, 25,358 insertions, 6,439 deletions.

Introduced a broad vNext design:

- finite input and flow `Design`s with stable keys;
- unrestricted `Entity` identity, unrestricted immutable `Version` snapshots,
  and a linear current `Live` capability;
- typed operations, derivation/revision, equality branch tokens, and owned Slot
  typestate;
- typed predicates, events, milestones, invariants, evidence, and checkpoints;
- source documents and program points;
- typed patterns, projections, nodes, connectors, routes, and terminal markers;
- a generated visualization TypeScript contract;
- thirteen planning examples and two research bundles.

Assessment:

- `Entity`/`Version`/`Live` was a plausible type-enforced separation, not a
  formal proof and not shown to improve the authoring guarantee over a public
  linear Block plus compiler-internal immutable snapshots.
- The semantic and projection ideas are useful reference material.
- The 255-name facade, nested subsystems, 13 large examples, and parallel old/new
  implementations are too broad to restore as one unit.
- Do not cherry-pick wholesale. Inspect semantic declarations, stable identity,
  typed connectors, and program-point work separately if those become concrete
  requirements.

### `369bf0dc381e732a315913cec3239b6bd991e4d4` — Fix cabal locking issue

Size: 13 files, 128 insertions, 518 deletions.

Removed the first custom Cabal-lock mechanism, adjusted the devcontainer/build
scripts, and refined diagnostics/schema checks.

Assessment:

- Depends on the refactored build layout from `4f88244`.
- Later prepared-compiler work superseded much of it. Treat it as historical
  evidence for avoiding per-request Cabal locking, not as a direct cherry-pick.

### `0f7eb5b9d25d9b85e3a5c82f6a2346fcd43b5cb1` — Major refactor stage #2

Size: 183 files, 12,245 insertions, 36,085 deletions.

This was a deletion-heavy replacement rather than a cleanup of the baseline:

- deleted the old choreography, core, view, style-profile, typography,
  HarfBuzz, font-resource, code-highlighting, and target/resource stacks;
- replaced public linear ownership with compiler-managed unrestricted `Ref`;
- introduced `Program`, managed structural traversal, sequences, sets and
  graphs;
- retained typed relations/events and introduced a smaller visual domain API;
- introduced strict IR v3, project schema v2, content-addressed sample sets,
  project comparison/hydration UI, and a prepared compiler path;
- removed old event schemas and compatibility normalizers.

Assessment:

- The unrestricted `Ref` model removes the static lifetime proof that motivated
  the DSL. Do not restore it as an authoring convenience.
- Deleting exact typography and coherent profiles materially reduced visual
  quality. Do not repeat that deletion.
- Potentially reusable work is concentrated in the strict producer/consumer IR
  boundary, prepared executable, compact event/sample storage, and selected UI
  reliability changes. These should be ported independently.

### `a5084ba534ad67c25394cc5abb97eedb7fa6350d` — Temp commit 2

Size: 49 files, 3,378 insertions, 425 deletions.

Refined the managed prototype:

- added `Role` for same-payload semantic distinctions;
- added high-level `arrange` and bounded `record` content;
- strengthened content-fit, non-overlap and connector-routing validation;
- improved stable render identity and semantic timeline offsets;
- added canvas loading/failure recovery, cross-batch comparison, timeline
  grouping, and bounded comparison evidence for later explicit edits;
- added tests around project comparison, workspace hydration, timeline and
  viewport behavior.

Assessment:

- `Role`, relation-aware routing, hard fit/non-overlap checks, stable render
  identity, and focused UI tests are useful donors.
- It depends on the `Ref`/IR-v3/schema-v2 rewrite and should not be cherry-picked
  as a whole.

### `03c4e14808d268d49cd95801fc2c833ca3e2eb38` — Temp commit

Size: 113 files, 40,899 insertions, 5,346 deletions. Roughly 30,000 inserted
lines were extracted research materials later removed by `0af81eb`.

Restored several core design ideas while retaining the post-refactor compiler
and application architecture:

- replaced unrestricted `Ref` with a public linear `Block` and a free linear
  `Program`;
- added multiplicity-aware do notation;
- added independent finite `input` and `flow` designs and compiler-minted linear
  external sources;
- added typed operations with read/revision successors, explicit copy lineage,
  equality-only branch observation, persistent relations, immutable events,
  temporary tags, and typed Slot lifecycles;
- added type-wide `representNodes`, typed relation projection, routed connectors,
  compiler-owned highlights, captions, records, code panels, and one high-level
  arrangement restriction;
- added examples for branching/events, continuity, roles/content,
  sequential reuse, slots/copies, and BFS;
- expanded command, feedback, comparison, error, and timeline behavior;
- changed solver MIP conditioning to retain a numeric feasibility witness.

Assessment:

- The Block/operation/relation/tag/Slot concepts are the most relevant semantic
  donors, but the implementation is coupled to the large replacement compiler.
- The change removed public geometry/style freedom almost completely and the
  active guide explicitly discouraged whole-visual alternatives. That
  overcorrected against the desired CSP-level structural diversity.
- The MIP numeric witness was fed directly into affine sampling. HiGHS commonly
  returned a boundary vertex, from which hit-and-run often could not move. This
  collapsed continuous variation to boundary values while categorical shape
  choices still changed.
- The same path emitted numerical residue such as saturation
  `-4.440892098500626e-16`. Haskell JSON tests accepted it, while the strict
  TypeScript decoder rejected the production output.
- Do not cherry-pick this commit wholesale. Extract semantic types and tests in
  small slices, and redesign solver initialization around an interior feasible
  point plus explicit output-domain normalization.

### `0af81ebfa3bb544f0198a945241398e17fe44d52` — Remove generated planning docs for now

Size: 35 files, 30,433 deletions.

Removed the extracted research trees and their two source archives. It contains
no product implementation worth cherry-picking. The reports remain recoverable
from `03c4e14` or its parent on the archive branch.

### `b0b51a30004777b56fa67d5fdb14f9d0b2598dae` — Remove possibly stale docs

Size: 3 files, 533 deletions.

Removed `docs/architecture-decisions.md` and `docs/effort-log.md`. Those files
contain useful archaeology but also optimistic claims later contradicted by
production logs. Read them from `03c4e14` as historical evidence, not as an
active contract.

## Feature lookup

| Feature                                         | Best post-baseline reference               | Porting note                                                                                                                                                 |
| ----------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Stable authored keys                            | `4f88244`, later narrowed in `03c4e14`     | Useful for repeated occurrences and reproducible lineage; keep internal IDs separate from display text.                                                      |
| Finite input and flow choices                   | `4f88244`, `03c4e14`                       | Port as independent deterministic phases; do not let view seeds change program behavior.                                                                     |
| Linear operations with successor versions       | `03c4e14`                                  | Preserve the baseline public Block idea; immutable versions can remain compiler-internal.                                                                    |
| Typed persistent relations and immutable events | `4f88244`, `03c4e14`                       | Useful for arrows and interval semantics; active relation proofs should remain linear.                                                                       |
| Temporary typed selection/tag                   | `03c4e14`                                  | Good FRP-style selection model; renderer can derive an outline without authored style state.                                                                 |
| Typed Slot lifecycle                            | `4f88244`, `03c4e14`                       | Completes the baseline's inaccessible Slot operations; add only with visual/trace tests.                                                                     |
| Type-consistent semantic projection             | `03c4e14`                                  | `representNodes @Type` is a useful narrow alternative to arbitrary overlapping fact rules. Preserve a way to distinguish Roles.                              |
| Connectors and routing                          | `4f88244`, `a5084ba`, `03c4e14`            | Keep typed endpoint coverage and obstacle checks. The latest long U-shaped arrow shows that collision-free routing is not sufficient for perceptual quality. |
| Records and captions                            | `a5084ba`, `03c4e14`                       | Bounded structural content is useful; do not grow it into a general widget tree.                                                                             |
| Strict IR producer/consumer boundary            | `0f7eb5b`, `a5084ba`                       | Reuse only with an end-to-end test that runs the real TypeScript decoder on every example/seed.                                                              |
| Prepared compiler executable                    | `0f7eb5b` and follow-up files in `a5084ba` | Useful performance/reliability work; adapt to the baseline build rather than importing schema-v2 wholesale.                                                  |
| Candidate sample sets and Compare/Next UI       | `0f7eb5b`, `a5084ba`                       | Potentially reusable after compiler correctness; avoid background AI/watch orchestration.                                                                    |
| Example-suite compilation                       | `03c4e14`                                  | Recreate against the chosen API. Compilation alone is insufficient: add semantic, production-schema and perceptual checks.                                   |
| Research requirement catalogues                 | tree at `03c4e14`                          | Consult selectively. They were never part of normal model context and should not become an exhaustive DSL mandate.                                           |

## Failure patterns to retain as regression tests

1. Body-only syntax and generated-header failures, including `if` expressions
   requiring missing `ifThenElse` under `RebindableSyntax`.
2. Every checked-in example must compile through the actual generated module,
   not only typecheck helper fragments.
3. Every compiled example/seed must pass the production TypeScript IR decoder.
4. Solver values must be normalized to their declared closed domains before IR
   emission; tolerance residue must not escape as invalid HSL/unit values.
5. Diversity must be perceptual and structural. A distinct solver fingerprint
   or one changed corner radius is not sufficient.
6. Scenario/input, flow, and visual seeds must be independently reproducible,
   and the UI must make clear which axis is being varied.
7. Algorithm examples need behavioral assertions. A repair that makes ten
   elements visible must not silently remove successful targets or early exit.
8. Relations need semantic and perceptual routing checks. Deleting a strange
   arrow or replacing it with a highlight is not a valid routing repair unless
   the semantic encoding itself changed.
9. Lineage tests must cover continuation, fork, destruction, temporary tags and
   occupied Slots through timeline transitions.
10. Model context must treat the current source as authoritative and must not
    repeat historical assistant claims as verified behavior.

## Recommended extraction order

1. Make the restored baseline demo and its existing tests reliable without an
   API redesign.
2. Add an end-to-end production-schema gate and a small representative example
   suite.
3. Preserve/repair the baseline typography, code, coherent style-profile and
   affine sampling machinery.
4. Add stable keys and finite input/flow phases as small independent features.
5. Complete the public Block/Slot lifetime story and add typed relation/event/tag
   intervals without exposing unrestricted live handles.
6. Add arrows and relation-aware routing while retaining the mature typography
   and layout stack.
7. Narrow the old low-level visual surface only after equivalent high-level CSP
   diversity and hierarchy are demonstrated by tests and rendered examples.

Avoid another all-at-once semantic, IR, persistence, UI, prompt and solver
rewrite. The two major refactors changed 100 and 183 files respectively, and
the later corrective commit changed 113 more; this made it difficult to tell
which fix caused each regression.
