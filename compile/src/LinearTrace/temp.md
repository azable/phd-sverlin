Yes. I recommend removing the nonlinear penalty optimizer from the production solver, not
merely disabling its automatic fallback. This substantially simplifies the architecture and
better matches the uniform-sampling goal.

There are two separate decisions:

1. Do not automatically fall back when Render encounters unsupported constraints. The plan
   already proposes this.

2. Delete the penalty-optimizer backend, its configuration, dependencies and retry paths
   altogether. This is the additional simplification.

HiGHS would remain: it solves discrete and linear feasibility problems, not arbitrary
nonlinear layout equations.

### Practical drawbacks

Existing capability Affine-only replacement
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
x \* y, x / y, powers Reject when both operands contain solver
variables
──────────────────────────────────────────── ─────────────────────────────────────────────
abs, min, max Compile into exact finite cases
──────────────────────────────────────────── ─────────────────────────────────────────────
Symmetric distance such as abs (x - y) == Compile into two affine cases
gap
──────────────────────────────────────────── ─────────────────────────────────────────────
Cyclic angle equality Normalize before solving or enumerate the
finite ±360k cases
──────────────────────────────────────────── ─────────────────────────────────────────────
Unbounded variables Require or infer finite bounds for every
remaining free variable
──────────────────────────────────────────── ─────────────────────────────────────────────
encourage and minimize Remove, or give them new explicitly non-
uniform sampling semantics

The genuine feature loss is variable-by-variable nonlinear geometry. Examples include:

width _ height == desiredArea
x _ x + y _ y == radius _ radius
distance(pointA, pointB) == 100

That affects radial layouts, exact circles, rotations involving variable angles, force-
directed layouts and area constraints. These would receive a clear diagnostic.
Multiplication by a fixed number remains affine and supports ordinary layout operations
such as:

width == height \* 1.5
centerX == left + width / 2

The current authored API permits general expression multiplication and division (compile/
src/LinearTrace/Choreography/Layout.hs:384), so it should eventually distinguish fixed
scalars from solver-derived scalars more strictly. Otherwise authors—or the LLM—will only
discover the restriction at compile time.

### The more important issue: soft preferences

The current optimizer is the only backend capable of honoring encourage and minimize. The
affine sampler explicitly ignores them (compile/src/Solver/Affine.hs:44), even though
encourage is public (compile/src/LinearTrace/Choreography/Constraint.hs:348).

For example:

ensure $ gap .>=. 10
ensure $ gap .<=. 100
encourage $ gap .==. 20

A uniform sampler produces gaps throughout 10–100. Honoring the encouragement would
deliberately bias results toward 20, so the result would no longer be uniform.

The cleanest initial design is therefore:

- Use hard ranges for acceptable visual quality, such as 15 <= gap <= 25.
- Use explicit weights for choices such as font or orientation.
- Remove encourage from the authored Render API until a weighted-sampling contract is
  deliberately designed.

- Do not silently ignore preferences.

  exact affine cases.

- The normal affine path already ignores soft constraints, so removing the optimizer
  exposes an existing semantic gap rather than creating a new one.

The implementation cleanup would be meaningful. It could remove:

- Solver.Optimize;
- the numeric-optimization, automatic-differentiation and L-BFGS-B dependencies;
- optimizer tolerances and constraint-energy weights from SolveConfig;
- backend selection and fallback diagnostics;
- optimizer statistics and energy-based retry code;
- the legacy view fallback in compile/src/LinearTrace/View/Solve.hs:23.

The main operational downside is stricter compilation. AI-generated source that previously
happened to obtain an approximate optimizer result will instead fail and use the one
permitted repair attempt. The authored API and prompt context should therefore prevent or
clearly explain unsupported arithmetic before this removal lands.

My recommended sequence is:

1. Define the supported affine and exactly case-splittable expression language.
2. Lower abs, min, max, symmetric bridges and cyclic equality exactly.
3. Decide to remove or temporarily hide encourage.
4. Require finite bounds and produce source-specific diagnostics for missing bounds.
5. Make the affine/design-space path handle every catalogued example.
6. Delete the optimizer backend, dependencies, configuration and tests.

If nonlinear layout is wanted later, it should be introduced as an explicit separate layout
engine with different guarantees—not as a silent fallback from the uniform finite-design-
space solver.

I have not changed the plan or implementation in this response.
