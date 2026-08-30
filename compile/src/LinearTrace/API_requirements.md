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
