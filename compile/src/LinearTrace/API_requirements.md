# LinearTrace API requirements

This file records requirements and the rationale behind them for the LinearTrace
API refactor. It is not an API specification and does not commit the project to
particular public names, syntax, types, or implementation techniques. Proposed
designs in [API_plan.md](API_plan.md) should be checked against these requirements
so that simplifying the authored API does not accidentally discard an existing
invariant.

## Prevent escape from linear ownership

Authored code must not be able to sidestep a trace object's linear lifecycle by
hiding its value inside an unrestricted or more complex user-defined Haskell type.
Payload construction, extraction, transformation, and persistence must pass through
trusted interfaces that preserve linear ownership, including when the underlying
value is ordinarily unrestricted or an unrestricted trace snapshot must be retained.

The closed payload machinery and wrappers such as `LInt` in
[Core/Internal.hs](Core/Internal.hs) provide this boundary today. The new API may
hide, derive, retain, or replace that mechanism, but must provide the same guarantee.
It need not associate payloads or operators with display text; presentation belongs
to `Render`.

## Derive aggregate geometry from local constraints

Render should prefer local relationships—parent-child containment, padding,
adjacency, and alignment—over APIs that expose aggregate measurements or require
authors to calculate absolute extents. The compiler should derive a group's size
and position from those relationships: for example, a hugging array parent gets
its width from its children's bounds and padding, not from a node count multiplied
by their spacing. Add a count or absolute-extent accessor only when that value must
itself be visualized or cannot be derived from existing constraints.

Examples:

- In an array row, constrain each declared adjacent pair to share an axis and have
  a fixed or sampled gap. A hugging parent plus padding then determines the row's
  complete bounds; the author does not need its length or a calculated width.
- For one shaped text line, its text, chosen font, and variable font size determine
  its intrinsic bounds. Text fitting and parent containment should use those bounds
  directly rather than exposing a character count or asking the author to estimate
  width from an average glyph size.

## Keep constraints stable within a linear lifetime

The compiler sees the complete trace before it solves any layout. It should collect
all Render constraints that refer to a linear object's lifetime and solve them as one
fixed system, even when the fact that contributes a constraint is declared after an
earlier exposed frame. This is not a frame-time mutation: the later declaration
becomes part of the constraints used for that whole lifetime. Solver values may
still be sampled within the resulting feasible region, and geometry-neutral
presentation state may change.

When Program consumes an object and produces a successor, that linear transition is
a "cut" between lifetimes. Constraints attached to the old identity do not silently
retarget to the successor. The compiler should derive these scopes from linear
ownership rather than rely on authors to coordinate frame-specific changes.

Relations are one instance of this rule. `relate` may occur after either location has
already appeared. If Render maps that relation to layout constraints, those
constraints join the fixed system over the overlapping lifetimes of its stable slot
owners; only the relation's semantic visibility begins at the `relate` event.
Unsealing, replacing an occupant, and resealing may change occupant block identity
without recreating the relation or its constraints. If later relation rules conflict
with constraints already collected for those lifetimes, compilation must report an
infeasible design with the relevant source locations; repeated sampling cannot make
an inconsistent system feasible.

## Propagate optional view presence through dependencies

Render should allow any tracked view component, not only a frame, to be included or
omitted by a seeded choice. An optional component still returns its normal symbolic
handle. Components and constraints that consume that handle automatically inherit
its presence condition; independent components remain present. Combining optional
inputs requires all of them to exist. This keeps conditional composition inside the
Render builder without exposing `Maybe` or requiring authors to repeat guards.

Presence tracking applies only to abstract values whose provenance Render controls.
Passing an optional handle through an ordinary Haskell value that loses that
provenance must be rejected. Omitting a geometry-neutral component does not create
another affine solver branch; optional geometry does.

## Preserve behavior while collapsing implementation layers

The authored package boundary should expose only `Sverlin`; compiler assembly
belongs to a narrow host boundary, while `Solver` and any deliberately stable IR
contract remain separate. Historical Core, View, and Visualization modules are
not public merely because the compiler currently imports them.

Removing or merging an internal layer must preserve its behavior at a tested
boundary before its module disappears. In particular, retain linear ownership and
identity, slot-owner continuity, relation lifetimes, Render scope and presence
provenance, hierarchy and style cascade, deterministic typography and resource
resolution, source-level diagnostics, serialized IR invariants, transition
identity, and seeded sampling semantics. Previous implementations are evidence for
these edge cases, not APIs that must be restored wholesale. Do not retain empty
forwarding layers solely for old import names once their behavior has a clear new
owner.
