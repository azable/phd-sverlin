# Compiler refactor review

## Scope and conclusion

This review covers the Haskell compiler after the refactor introduced in
`6d86c0c` and its follow-up commits, inspected at `ab51a93` on 2 September 2026. The working tree also contained developer-owned compilation-metrics
changes; those were reviewed in place but not modified.

The refactor has a sound top-level architecture: authored source enters through
the explicit [`Sverlin`](../src/Sverlin.hs) facade, semantic execution and
render planning are separate, the top-level [`Solver`](../src/Solver.hs) module
remains the solver boundary, and the browser contract stays behind the
visualization IR. The repository is not yet in a clean post-refactor state,
however. Provenance and verification still point partly at the retired
pipeline, and 24 legacy source modules remain reachable only through tests.

## Module use

| Category                           | Modules                                                                                                                                    | Status                                                                                                    |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| Current DSL and compiler           | `Sverlin`, `Sverlin.Compiler`, `Sverlin.Linear`, `Sverlin.Syntax`, and `Sverlin.Internal.*`                                                | Production path. `Sverlin` and `Sverlin.Linear` are imported dynamically by the generated source wrapper. |
| Solver                             | `Solver` and all `Solver.*` modules                                                                                                        | Production, tests, and benchmarks.                                                                        |
| Shared output implementation       | `LinearTrace.Visualization.IR`, `Options`, `Resource`, `Target`, `FontCatalog`, and `HarfBuzz`                                             | Still active; do not remove with the old pipeline.                                                        |
| Executable and generation tools    | `Main`, `Sverlin.Source`, `Sverlin.Interpreter`, and `GenerateVisualizationTypes*`                                                         | Active host/tooling path.                                                                                 |
| Retired pipeline retained by tests | `LinearTrace.Choreography*`, `LinearTrace.Core*`, `LinearTrace.View.*`, and `LinearTrace.Visualization.{Compile,Typography,CodeHighlight}` | No production importer; 24 modules and approximately 11,346 source lines.                                 |

There are no wholly unreachable Haskell modules because Cabal and the old
solver test suite still compile the retired pipeline. This makes "compiled" a
weaker signal than "used by production". The old
[`Invalid.sverlin`](../test/fixtures/Invalid.sverlin) fixture is genuinely
orphaned: it uses the retired API and is only listed as an extra source file.

## Prioritized findings

### 1. Fix DSL revision provenance

[`fingerprints.ts`](../../src/lib/server/projects/fingerprints.ts) claims to
fingerprint the active Haskell DSL, but hashes
`LinearTrace.Choreography*` and `Sverlin.Source` rather than the current
`Sverlin` implementation. As a result:

- changes to the active facade or semantic/render implementation may leave the
  recorded `contentSha256` unchanged;
- active compiler edits may be reported as a clean working tree; and
- changes to retired choreography code can alter the recorded revision without
  changing production output.

Use one canonical active-source enumeration, preferably shared with prepared
compiler fingerprinting. Extend the fingerprint test so it detects path drift,
not merely a well-formed digest.

### 2. Run the current Haskell tests routinely

The 46-test `semantic-test` component in [`compile.cabal`](../compile.cabal)
covers the new semantic engine, render guards, typography, and metrics. Neither
the normal scripts in [`package.json`](../../package.json) nor the verification
stage in [`Dockerfile`](../../Dockerfile) runs it. End-to-end example tests cover
the production path, but do not replace these focused regressions.

Add a `test:compiler` command for `semantic-test` and
`sverlin-source-test`, then include it in normal and container verification.

### 3. Isolate and retire the old pipeline

The current plan already says that `RenderPlan` replaces old query matching,
`View.Access`, `View.Template`, and `StyleProfile`; see
[`API_plan_final.md`](API_plan_final.md#internal-compiler-and-renderer-shape).
Nevertheless, [`SolverTest.hs`](../test/SolverTest.hs) still imports the old
facade, core, visualization compiler, and typography implementation, backed by
the 876-line
[`Choreography.TestFixtures`](../test-support/Choreography/TestFixtures.hs).

First migrate any characterization assertions that still protect current
behavior into `SemanticTest`, `RenderGuardTest`, or `TypographyTest`. Until that
is complete, put the remaining tests in an explicitly named legacy suite so
`test:solver` again means tests through the supported `Solver` facade. Then
remove the retired modules and their Cabal entries while retaining the six
shared output modules listed above.

### 4. Split the render implementation at validated phase boundaries

[`Sverlin.Internal.Render.Compile`](../src/Sverlin/Internal/Render/Compile.hs)
is about 5,318 lines with 178 top-level signatures. The builder module
[`Sverlin.Internal.Render`](../src/Sverlin/Internal/Render.hs) is about 2,540
lines and represents the plan as fifteen parallel declaration lists. Guard
promotion manually traverses those lists, so adding a declaration kind requires
coordinated edits across state, finalization, promotion, counting, and lowering.

The existing transitions provide natural module boundaries:

`RenderPlan -> ExpandedPlan -> PreparedCompilation -> visualization IR`

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

### 7. Remove remaining documentation and fixture drift

[`AGENTS.md`](../../AGENTS.md) still names `LinearTrace.Choreography` as the
canonical facade and links to a nonexistent `API_refactoring.md`; the actual
index generator correctly reads `Sverlin.hs`. Several planning links also still
assume that examples live under `compile/plan/examples/`. Update the standing
instructions and links, and either remove the orphaned invalid fixture or
rewrite it as a real negative test for the current body-only contract.

## Recommended cleanup order

1. Correct DSL revision fingerprinting and add a path-sensitive regression
   test.
2. Wire `semantic-test` and `sverlin-source-test` into routine verification.
3. Split legacy characterization tests from direct solver tests.
4. Port still-relevant behavior to the new test suites, then delete the 24
   retired modules and obsolete fixture.
5. Split render compilation along its existing validated phase boundaries.
6. Replace `Show`-based forcing and hashing, then correct the total-duration
   metric.
7. Synchronize `AGENTS.md` and repair the moved-example links.

## Verification performed during review

- All 54 library modules compiled.
- All 46 `semantic-test` cases passed.
- All 120 `solver-test` cases passed, including the legacy characterization
  groups.
- Both `sverlin-source-test` cases passed.
- The generated API index verified all 175 documented `Sverlin` names.
- `git diff --check` passed.
- HLint reported five existing non-functional suggestions, so the HLint gate
  was not clean.

The test run required a temporary corrected package database because the
preseeded `tasty-hunit` registration referenced the old
`/opt/sverlin-dev/stack-root` path. No repository or system package database was
changed.
