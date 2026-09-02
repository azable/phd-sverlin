# Compiler refactor review

## Scope and conclusion

This review covers the Haskell compiler after the refactor introduced in
`6d86c0c` and its follow-up commits, inspected at `ab51a93` on 2 September 2026. The working tree also contained developer-owned compilation-metrics
changes; those were reviewed in place but not modified.

The refactor has a sound top-level architecture: authored source enters through
the explicit [`Sverlin`](../src/Sverlin.hs) facade, semantic execution and
render planning are separate, the top-level [`Solver`](../src/Solver.hs) module
remains the solver boundary, and the browser contract stays behind the
visualization IR. The first three findings below have now been resolved:
provenance names the authored contract explicitly, current compiler tests run
routinely, and the test-only legacy pipeline has been removed.

At a high level, [`Sverlin.Source`](../app/Sverlin/Source.hs) turns the supplied
body into a generated Haskell module with one public facade import and a fixed
three-part result:

```haskell
import Sverlin
import Sverlin.Compiler (SverlinProgram)
import qualified Sverlin.Compiler as Compiler (sverlinProgram)

_sverlinResult :: SverlinProgram
_sverlinResult = Compiler.sverlinProgram domain program render
```

That result then follows the active implementation path:

```text
.sverlin body -> Sverlin.Source -> Sverlin.Compiler
              -> semantic trace -> render compilation
              -> LinearTrace.Visualization.IR -> JSON
```

## Module use

| Category                        | Modules                                                                                                                                                                                                                                                                                                                                                                                  | Status                                                                                                                   |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Current DSL and compiler        | [`Sverlin`](../src/Sverlin.hs), [`Sverlin.Compiler`](../src/Sverlin/Compiler.hs), [`Sverlin.Linear`](../src/Sverlin/Linear.hs), [`Sverlin.Syntax`](../src/Sverlin/Syntax.hs), and [`Sverlin.Internal.*`](../src/Sverlin/Internal/)                                                                                                                                                       | Production path. `Sverlin` and `Sverlin.Linear` are imported dynamically by the generated source wrapper.                |
| Solver                          | [`Solver`](../src/Solver.hs) and [`Solver.*`](../src/Solver/)                                                                                                                                                                                                                                                                                                                            | Production, tests, and benchmarks.                                                                                       |
| Shared output implementation    | [`LinearTrace.Visualization.IR`](../src/LinearTrace/Visualization/IR.hs), [`Options`](../src/LinearTrace/Visualization/Options.hs), [`Resource`](../src/LinearTrace/Visualization/Resource.hs), [`Target`](../src/LinearTrace/Visualization/Target.hs), [`FontCatalog`](../src/LinearTrace/Visualization/FontCatalog.hs), and [`HarfBuzz`](../src/LinearTrace/Visualization/HarfBuzz.hs) | Still active; do not remove with the old pipeline.                                                                       |
| Executable and generation tools | [`Main`](../app/Main.hs), [`Sverlin.Source`](../app/Sverlin/Source.hs), [`Sverlin.Interpreter`](../app/Sverlin/Interpreter.hs), [`GenerateVisualizationTypes`](../app/GenerateVisualizationTypes.hs), and its [TypeScript generator](../app/GenerateVisualizationTypes/TypeScript.hs)                                                                                                    | Active host/tooling path.                                                                                                |
| Retired pipeline                | `LinearTrace.Choreography*`, `LinearTrace.Core*`, `LinearTrace.View.*`, and `LinearTrace.Visualization.{Compile,Typography,CodeHighlight}`                                                                                                                                                                                                                                               | Removed after relevant characterization coverage was moved to the current semantic, render-guard, and typography suites. |

At review time, Cabal and the old solver test suite still compiled the retired
pipeline even though production did not import it. This made "compiled" a
weaker signal than "used by production". The orphaned `Invalid.sverlin`
fixture likewise used the retired API and was only listed as an extra source
file. The retired modules, fixture, and Cabal entries have now been removed.

## Resolution of findings 1–3

- [`DslRevision`](../../src/lib/shared/projects/events/values.ts) now
  fingerprints one explicit authored-contract set: [`Sverlin.Source`](../app/Sverlin/Source.hs),
  [`Sverlin`](../src/Sverlin.hs), [`Sverlin.Linear`](../src/Sverlin/Linear.hs),
  and the [generated DSL API index](../../src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md).
  Its [Git dirty check](../../src/lib/server/projects/fingerprints.ts) uses the
  same paths. Compiler internals, assistant policy, and the neutral
  [`dsl-interface.md`](../../src/lib/server/chat-bots/sverlin-assistant/dsl-interface.md)
  pointer are deliberately excluded; the [prepared-compiler fingerprint](../../src/lib/server/compiler/prepared-compiler.js)
  continues to cover implementation and build inputs. Both fingerprints use
  the shared [enumeration and hashing module](../../src/lib/server/repository-fingerprints.js).
- [`pnpm run test:compiler`](../../package.json) runs `semantic-test` and
  `sverlin-source-test`. The normal test command and the
  [container verification stage](../../Dockerfile) both invoke it.
- [`solver-test`](../test/SolverTest.hs) now exercises only the supported
  [`Solver`](../src/Solver.hs) facade and [stable solver fixtures](../test-support/Solver/TestFixtures.hs).
  Current behavior formerly protected by the old suite was moved into
  [`RenderGuardTest`](../test/RenderGuardTest.hs) and
  [`TypographyTest`](../test/TypographyTest.hs) before the obsolete modules and
  the large `Choreography.TestFixtures` support module were deleted.
- The small [`dsl-interface.md`](../../src/lib/server/chat-bots/sverlin-assistant/dsl-interface.md)
  file now points without additional policy to the [generated API index](../../src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md).
  Authoring policy remains in the [assistant configuration](../../src/lib/server/chat-bots/sverlin-assistant/index.ts),
  and this pointer is not a DSL revision input. The sibling
  [`index.ts`](../../src/lib/server/chat-bots/sverlin-assistant/index.ts)
  attaches the generated reference as `dslApiIndex` to every model request;
  that generated reference is a DSL revision input.
- [`compile.cabal`](../compile.cabal) remains the package and component
  description. Stack's current documentation distinguishes that package
  description from the project-level [`stack.yaml`](../stack.yaml); because
  this repository has no Hpack `package.yaml`, Stack consumes the Cabal file
  directly. See
  [Stack's package-description documentation](https://docs.haskellstack.org/en/stable/tutorial/package_description/).

The request-time attachment in the
[`sverlin-assistant` configuration](../../src/lib/server/chat-bots/sverlin-assistant/index.ts)
is deliberately direct (abridged here to show the boundary):

```ts
const [dslInterface, dslApiIndex] = await Promise.all([
  loadDslInterfaceContext(),
  loadDslApiIndex()
]);

return { dslInterface, dslApiIndex, project, attemptContext: attempt };
```

Consequently the generated index is supplied as its own structured context
field on every authoring request; the neutral interface file is only a pointer
and compatibility field.

## Prioritized findings

### 1. Fix DSL revision provenance — resolved

At review time, [`fingerprints.ts`](../../src/lib/server/projects/fingerprints.ts)
claimed to fingerprint the active Haskell DSL, but hashed
`LinearTrace.Choreography*` and `Sverlin.Source` rather than the authored
contract. As a result:

- changes to the active facade could leave the recorded `contentSha256`
  unchanged;
- active compiler edits may be reported as a clean working tree; and
- changes to retired choreography code can alter the recorded revision without
  changing production output.

The resolved boundary is intentionally narrower than the prepared compiler:
the DSL revision identifies authored syntax and documented API, while semantic
and rendering implementation changes affect the prepared-compiler fingerprint.
Path-sensitive tests now assert the exact contract set, each included path, and
representative excluded implementation and prompt-context paths.

The canonical list lives in
[`repository-fingerprints.js`](../../src/lib/server/repository-fingerprints.js)
and is consumed directly by
[`fingerprints.ts`](../../src/lib/server/projects/fingerprints.ts):

```js
export const dslContractInputPaths = Object.freeze([
  'compile/app/Sverlin/Source.hs',
  'compile/src/Sverlin.hs',
  'compile/src/Sverlin/Linear.hs',
  'src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md'
]);
```

The corresponding [fingerprint tests](../../src/lib/server/projects/fingerprints.test.ts)
mutate every included file, check representative exclusions, and create a
temporary Git repository to prove that the dirty-path check cannot silently
drift from this list.

### 2. Run the current Haskell tests routinely — resolved

At review time, the 46-test `semantic-test` component in
[`compile.cabal`](../compile.cabal) covered the new semantic engine, render
guards, typography, and metrics, but neither the normal scripts in
[`package.json`](../../package.json) nor the verification stage in
[`Dockerfile`](../../Dockerfile) ran it. End-to-end example tests cover the
production path, but do not replace these focused regressions.

The new `test:compiler` command runs `semantic-test` and
`sverlin-source-test`; normal and container verification now include it.

The relevant [`package.json`](../../package.json) scripts make that relationship
explicit:

```json
{
  "test:compiler": "stack --stack-yaml compile/stack.yaml test compile:semantic-test compile:sverlin-source-test",
  "test": "pnpm run test:unit && pnpm run test:compiler && pnpm run test:postgres && pnpm run test:examples"
}
```

[`Dockerfile`](../../Dockerfile) invokes the same `test:compiler` command in its
verification stage, so the container does not maintain a second test-suite
enumeration.

### 3. Isolate and retire the old pipeline — resolved

The current plan already says that `RenderPlan` replaces old query matching,
`View.Access`, `View.Template`, and `StyleProfile`; see
[`API_plan_final.md`](API_plan_final.md#internal-compiler-and-renderer-shape).
At review time, [`SolverTest.hs`](../test/SolverTest.hs) still imported the old
facade, core, visualization compiler, and typography implementation, backed by
the 876-line `Choreography.TestFixtures` module.

Relevant characterization assertions now protect current behavior in
[`RenderGuardTest`](../test/RenderGuardTest.hs) and
[`TypographyTest`](../test/TypographyTest.hs); [`solver-test`](../test/SolverTest.hs)
goes through the public facade. The retired modules and
[`compile.cabal`](../compile.cabal) entries were removed while retaining the six
shared output modules listed above.

### 4. Split the render implementation at validated phase boundaries

[`Sverlin.Internal.Render.Compile`](../src/Sverlin/Internal/Render/Compile.hs)
is about 5,318 lines with 178 top-level signatures. The builder module
[`Sverlin.Internal.Render`](../src/Sverlin/Internal/Render.hs) is about 2,540
lines and represents the plan as fifteen parallel declaration lists. Guard
promotion manually traverses those lists, so adding a declaration kind requires
coordinated edits across state, finalization, promotion, counting, and lowering.

The existing transitions provide natural module boundaries:

```text
RenderPlan -> ExpandedPlan -> PreparedCompilation -> visualization IR
```

Separate semantic expansion/projection, constraint lowering, style resolution,
and IR materialization around those states. A shared scoped-declaration wrapper
would also remove much of the parallel guard plumbing.

### 5. Replace `Show`-based evaluation and identity

[`Sverlin.Internal.Compiler`](../src/Sverlin/Internal/Compiler.hs) forces plans
and traces with `length (show value)`. The render compiler does the same for
expanded plans and constraints. This allocates complete debug strings and makes
the recorded phase timings include debug rendering work.

The scenario key also hashes `show trace`, so persisted identity depends on a
derived debugging representation. Use `NFData` or explicit strict summaries for
phase evaluation, and a versioned canonical encoding of the intended trace
identity fields for hashing.

### 6. Correct the total-duration metric

[`Main.hs`](../app/Main.hs) starts `compilerInternalTotal` before source
interpretation and stops it after target encoding and file writing. The metric
therefore includes several phases that its name says are external. Either
rename it as an overall compiler-process duration or measure only the
`compileProgramBatch` interval.

### 7. Remove remaining documentation and fixture drift — resolved

At review time, [`AGENTS.md`](../../AGENTS.md) still named
`LinearTrace.Choreography` as the canonical facade and linked to a nonexistent
`API_refactoring.md`; the actual
[`dsl-api-index.mjs`](../../scripts/dsl-api-index.mjs) generator correctly read
[`Sverlin.hs`](../src/Sverlin.hs). Several planning links also assumed that
examples lived under `compile/plan/examples/`. The standing instructions and
planning links now name the current sources, and the obsolete invalid fixture
has been removed.

## Remaining cleanup order

1. Split render compilation along its existing validated phase boundaries.
2. Replace `Show`-based forcing and hashing, then correct the total-duration
   metric.

## Baseline verification performed during review

- All 54 library modules compiled.
- All 46 [`semantic-test`](../test/SemanticTest.hs) cases passed.
- All 120 [`solver-test`](../test/SolverTest.hs) cases passed, including the
  legacy characterization groups.
- Both [`sverlin-source-test`](../test/SverlinSourceTest.hs) cases passed.
- The [generated API index](../../src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md)
  verified all 175 documented [`Sverlin`](../src/Sverlin.hs) names.
- `git diff --check` passed.
- HLint reported five existing non-functional suggestions, so the HLint gate
  was not clean.

The test run required a temporary corrected package database because the
preseeded `tasty-hunit` registration referenced the old
`/opt/sverlin-dev/stack-root` path. No repository or system package database was
changed.
