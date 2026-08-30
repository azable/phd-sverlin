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

The complete set of Render constraints for a linear trace object should be defined
when that particular lifetime begins and remain unchanged while the object is live.
Render must not add, remove, or replace geometric constraints for the same live
object at a later checkpoint. Solver values may still be sampled within the
original feasible region, and geometry-neutral presentation state may change; the
constraint system itself remains fixed.

Changing the constraint set requires a linear transition: Program consumes the old
object and produces a successor. This consume-and-produce boundary is a "cut" in
the trace. Constraints for the old lifetime end at the cut, and the successor's
complete constraints are established when its new lifetime begins. The compiler
should derive and validate these scopes from linear ownership rather than rely on
authors to coordinate checkpoint-specific constraint mutations.

Relations are one instance of this rule. A Program relation is semantic, but Render
may map it to layout constraints or connector geometry. Once a slot location has
been exposed, its incident relations must therefore remain fixed for that linear
lifetime. Changing a slot's occupant does not change the location or its relations;
rewiring requires an explicit linear transition of every affected location. For
example, an array's adjacency is established before its cells are shown and remains
stable while those cell locations exist, even when their stored values change.
