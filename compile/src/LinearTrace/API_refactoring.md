# LinearTrace API refactoring investigation

## Purpose and resume status

This is the durable handoff for the API-refactoring discussion conducted against
the tree at `3572577` on 29 August 2026. It explains the original TODOs, checks
the current implementation, and records relevant behavior from older commits.
It is an analysis and implementation plan: no API behavior described as
"recommended" below has been implemented merely by adding this file.

## Current refactor discussion handoff

Continue the active API design in `API_plan.md`. This investigation remains the
evidence and rationale archive; the plan is the concise, authoritative record
of agreed target behavior. Do not reconstruct current decisions from the older
recommendations below when the plan states a newer decision.

The decisions recorded so far are:

- the authored API has three builder/monadic parts: a new `Domain`, `Program`
  (the renamed public `TraceBuilder`/`Choreography` API), and `Render` (the
  renamed author-facing `VisualizationBuilder` context);
- `Sverlin` is the sole authored facade that composes and documents those three
  parts;
- graph construction, solving, statistics, and concrete runner types move out
  of the authored facade into a narrow host/compiler seam;
- public `Choreography` and final `runChoreography*` terminology are removed;
- Program remains general-purpose: restore public `seal` and `unseal`, keep the
  slot opaque and linear, and add no declaration/read/write slot helpers at
  this layer; and
- Program documentation is organized into resource lifecycle operations,
  materialization, and checkpoint-based timeline grouping. Each operation has
  its own minimal example and explains its trace and Render significance.

No implementation of this target API has begun. After a restart, read
`API_plan.md` completely and continue updating it under its existing headings
as decisions are made. Before changing Haskell behavior, reconcile the target
surface with the generated DSL API index and select a staged implementation
slice. Acquire the app lock before any accompanying Svelte behavior change.

The original questions came from:

- inline TODOs in `LinearTrace.Choreography`, `LinearTrace.View.Build`,
  `LinearTrace.Visualization.IR`, and `examples/LinearSearch.sverlin`;
- the now-deleted `COMPILE_INTERFACE_AUDIT.md`, which can still be read with
  `git show 4198fba:COMPILE_INTERFACE_AUDIT.md`; and
- the follow-up conversation about slots, owner lineage, view identity,
  `RenderContinue`, and frontend behavior lost during earlier refactors.

The most important conclusion is that the old slot idea **was facilitated**,
but by a combination of identities and view rules rather than by the `Slot`
token alone. The persistent owner `BlockId` represented the storage location;
the stored child had its own replaceable identity; and the old view layer kept
successive children at the owner's bounds. The current Core still records the
owner/child pairs in `TraceSeal` and `TraceUnseal`, but the current view graph
drops both events and the public facade does not expose `seal` or `unseal`.

If work resumes after a container restart, start with [Decisions to make before
implementation](#decisions-to-make-before-implementation) and [Recommended
implementation order](#recommended-implementation-order). The first concrete
implementation slice should be selected deliberately; the analysis does not
support restoring an old branch wholesale.

## Short answer to each original inline TODO

| Original TODO                                                                                                                | Finding                                                                                                                                                                                                                                           | Suggested resolution                                                                                                                                                                                                                                       |
| ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `LinearTrace.Choreography`: remove `commit` and call `materialize` without arguments?                                        | Core `commit` is exactly an alias for untagged Core `materialize`. The facade shadows that name with `materialize :: Query -> Pending tag %1 -> Choreography (Block tag)`. `commit` is not a transaction or checkpoint.                           | Remove the misleading `commit` alias after compatibility checks. Keep `materialize query pending` and use `emptyQuery`, or add an explicitly named `materializeUntagged`. Do not simulate optional arguments with another overloaded type class.           |
| `LinearTrace.Choreography`: restore slots, seal/unseal, the read/write lifecycle, view projection, examples, and a `SlotId`? | Yes. Core has most of the linear lifecycle, and the historical view model demonstrates the intended stable-location behavior. The present facade and projection are incomplete.                                                                   | Restore the lifecycle as one end-to-end feature, including identities, view intents, frontend animation, examples, and tests. Add a distinct `SlotId` before allowing multiple same-typed slots on one owner.                                              |
| `LinearTrace.Choreography`: how can symmetric `=/ ... /=` work with affine constraints when OR is not affine?                | It currently lowers to `abs (lhs - rhs) == delta`, which is non-affine and falls back to the legacy optimizer. The `Or` in the implementation's type-class names is not a solver disjunction.                                                     | Lower a scalar symmetric bridge to two finite affine cases: `lhs + delta == rhs` or `rhs + delta == lhs`. Give the decision a deterministic ID and define vector-component semantics explicitly. Hide or clearly document the operator until this is done. |
| `LinearTrace.View.Build`: are automatic `800 x 600` and canvas limits arbitrary; should they be parameterized?               | They are historical logical-canvas policy, not browser measurements. They affect constraint solving, text layout, and reproducibility.                                                                                                            | Keep deterministic defaults, but put them in host compiler configuration and include that configuration in provenance/fingerprints. Do not derive them from the browser viewport.                                                                          |
| `LinearTrace.Visualization.IR`: must `StyleVariableBinding` change for every new style attribute?                            | No. It is already a generic sparse `field path -> [VariableId]` record, and `styleVariableBindings` traverses style-field metadata. A new concrete field still has to cross the Haskell IR, compiler, generated TS, runtime schema, and renderer. | Rename the broader collection to reflect that it also contains box fields, and consider a typed `VisualField` key to prevent string drift. Do not add one binding-record member per style property.                                                        |
| `examples/LinearSearch.sverlin`: where is style family `"target"` defined?                                                   | It is not declared in a registry. `styleFamily "target"` supplies a grouping key inline. Elements with the same key share automatic profile choices; authored style values still override them.                                                   | Clarify this in facade documentation. Keep semantic family keys author-defined unless a future profile vocabulary intentionally makes them closed.                                                                                                         |

## Slot semantics, owner lineage, and the correction to the earlier assessment

### What Core says today

The current Core representation is:

```haskell
data Slot owner tag where
  Slot :: Block tag %1 -> Slot owner tag
```

The `owner` parameter is phantom: a `Slot` contains the child block but does not
store an owner value or a separate slot identifier. Nevertheless, `seal` and
`unseal` receive a live owner block and emit events containing snapshots of both
the actual owner and child:

```text
TraceSeal ownerSnapshot childSnapshot
TraceUnseal ownerSnapshot childSnapshot
```

Both operations return the same live owner capability, with its `BlockId`
unchanged. Therefore the earlier claim that “there is no fact in Core saying
that slot1 and slot2 represent the same storage location” was too strong.
When a program unseals and reseals through the same owner block, the Core trace
does contain repeated owner/child associations with the same owner `BlockId`.
They are trace events rather than queryable semantic `Facts`, but the identity
evidence exists.

What Core does **not** provide is equally important:

- the reconstructed `Slot` token has no stable identity of its own;
- the type parameter proves only the owner _type_, not attachment to one
  particular owner value, so two owners of the same type can be confused unless
  a higher layer prevents it;
- one owner cannot distinguish two same-typed storage positions;
- there is no persistent storage relation in the current view graph, because
  `LinearTrace.Choreography.Graph.viewOutputForEvent` maps both `TraceSeal` and
  `TraceUnseal` to `mempty`; and
- the public choreography facade exports aliases/wrappers such as `SlotHandle`,
  `Seal`, and `Unseal`, but not the operations that make them reachable.

The correct current diagnosis is thus: **Core retains enough event identity to
reconstruct the one-slot-per-owner model, but the public and visual layers no
longer interpret it.** It is not correct to judge stable storage solely by
comparing the consumed `slot1` token with the newly constructed `slot2` token.

### How the old model represented stable storage

Commit `970907d` is the clearest reference implementation. In
`compile/app/DSL/Main.hs`, a `VarBlock` was the persistent owner/location while
the current value was a separate child block stored in a linear `Slot`.

The lifecycle was:

```text
declare: create owner + create value -> seal value into owner
read:    unseal -> copy current value -> reseal original -> return the copy
write:   unseal -> replace/destroy current value -> seal new value
```

`DeclareVar` and `WriteVar` projected an owner `BlockRef` into the view and used
`sameBounds` between that persistent owner and the stored child. Consequently:

- the owner `BlockId` remained the storage-location identity;
- each replacement child could have a new `BlockId`;
- the new child nevertheless occupied the same visual location; and
- a copied read result could leave the location using ordinary fork lineage.

This answers the original design question: stable-slot replacement was
facilitated. It was not encoded as “the Slot token has a stable ID.” It emerged
from the stable owner ID plus the owner/child view relation.

### The old renderer used two different identities

The view and frontend history adds an important distinction that should be
preserved in a restoration.

At commit `52f842b`:

- `compile/app/LinearTrace/Compile.hs` emitted explicit `RenderPatch` values;
- `replaceNode` transferred the **incoming block's `RenderId`** to the output,
  destroyed the old occupant, and emitted an update for the incoming render
  identity; and
- `src/routes/sandbox/output/+page.svelte` keyed rendered DOM by `RenderId` and
  CSS-transitioned position and dimensions.

Commit `4a28efb` then added fork-origin metadata so a copied value could animate
from its source.

The old system therefore distinguished:

1. a stable **location identity** supplied by the owner and its geometry; and
2. a replaceable **occupant identity** supplied by the block/render instance
   moving into that location.

That distinction is more expressive than treating every write as continuation
of the old occupant.

### Why current `RenderContinue` is not the slot feature

`RenderContinue` exists in the current implementation, but it is an internal
view intent generated for `TraceReplace`; it is not a public compile API
operation. During IR compilation it reuses the old/source render instance for
the replacement target. This is useful when one semantic entity changes
version while remaining the same visible thing.

It is not by itself a benefit of the current slot model, because there is no
current public slot model at the facade/view boundary. It also encodes a
different identity choice from the historical slot write:

- **continuation/replace:** the old occupant continues as the output;
- **slot write/store:** the storage location continues, while a potentially
  independent incoming occupant moves into it.

Current `replace` consumes an old `Block` and a `Pending` output. It cannot take
an already materialized incoming `Block` and preserve that incoming block's
live lineage. A restored slot write should therefore either be a separate
three-party operation or produce an explicit render intent such as
`RenderAdopt location oldOccupant incomingOccupant output`. Reusing
`RenderContinue` for both concepts would erase meaningful identity.

### View-level refactoring required for slots

A minimal restoration needs all of the following; exposing two Core functions
alone is insufficient.

1. **Model the storage relation.** Preserve a binding equivalent to
   `StorageBinding { slotId, ownerViewId, occupantViewId }` while trace events
   are projected. For a first one-slot-per-owner version, the owner `BlockId`
   can temporarily identify the slot.
2. **Introduce `SlotId` before multiplicity.** Use an owner plus a stable
   author-declared role/key. A phantom owner type cannot distinguish two
   same-typed slots and cannot prevent cross-owner swapping.
3. **Give the location geometry.** Either render a stable slot anchor or expose
   the owner's content box, then constrain each current occupant to that box.
   This is the modern equivalent of `sameBounds` in `970907d`.
4. **Represent occupant replacement explicitly.** A write needs the old
   occupant, incoming occupant, output, and stable location, or an equivalent
   identity-preserving formulation. Read should remain a fork from the stored
   occupant while that occupant is resealed.
5. **Compile generic timeline intents.** The client should not need a special
   “slot” branch if the IR tells it the stable instance, incoming origin,
   destination geometry, and removal correctly.
6. **Validate illegal attachment.** Reject unsealing a slot with a different
   same-typed owner, duplicate occupancy, and resealing into the wrong `SlotId`.
7. **Define lifecycle at checkpoints.** Decide whether seal/unseal are visible
   only through the enclosing read/write operation or can leave a temporarily
   empty location at a checkpoint.

### Reference examples and tests required by the original TODO

The TODO in `LinearTrace.Choreography` explicitly names the variable/Fibonacci
example from `970907d`. Adapt it to the current body-only source contract when
the API is restored. It should be the intended-behavior reference, not merely a
compilation smoke test.

The test scenario should assert:

- declare seals the initial value;
- read unseals, copies, and reseals the original;
- write unseals, changes the occupant, and reseals;
- the owner/`SlotId` is stable across every write;
- occupant `BlockId`s may change;
- successive occupants use the same location geometry;
- a read copy receives fork origin from the occupant;
- a write adopts or moves the intended incoming lineage rather than
  accidentally continuing the removed value; and
- forward and reverse timeline playback both stage movement and removal
  correctly.

The existing continuity/fork tests are useful but do not establish these slot
properties. Add the two focused examples requested by the inline TODO under
`examples/`, and compile them through the real compiler and TypeScript decoder.

## Frontend transition findings relevant to slot restoration

The current client retains render-instance lineage in
`src/lib/client/visualization/visualization-player.svelte.ts`, including fork
origin staging. However,
`src/lib/client/visualization/VisualizationViewport.svelte` currently applies
CSS transitions only to fill/stroke-like styling. SVG `x`, `y`, `width`, and
`height` attributes change without a geometry transition, and removals are
immediate. A test comment says Svelte owns the outro, but the current viewport
has no actual `out:` transition. Thus stable IDs alone do not currently produce
the old movement behavior.

The history identifies where this changed:

| Commit                     | Relevant behavior                                                                                                                                                                     |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `52f842b`                  | Keyed render IDs and CSS transitions for position/dimensions in the original Svelte output.                                                                                           |
| `4a28efb`                  | Fork-origin metadata for copy animation.                                                                                                                                              |
| `b7d2d85`                  | Mainline “Fix svelte transitions”; HTML elements had `transition:scale` plus geometry CSS transitions.                                                                                |
| `9efb493`                  | HarfBuzz/compiler-shaped typography and SVG rendering replaced the HTML/`foreignObject` approach; geometry and enter/exit transitions were lost here.                                 |
| `0ff53cc`                  | Removed `View.Patch`, but that patch layer was declaration-time style/content/geometry accumulation, not temporal playback. Restoring it would not restore animation.                 |
| `03c4e14` (archive branch) | Rebuilt robust SVG transitions: translated local-coordinate groups, entering/exiting state, delayed removal, reverse origins, connectors, reduced motion, and direct component tests. |

The frontend regression therefore predates and is independent of the removal
of `View.Patch`. The useful donor for current SVG animation is `03c4e14`, not
the old patch accumulator.

Porting the archived SVG technique requires care with current compiler-shaped
text. If an element is wrapped in a translated group, absolute text positions
such as `lineOriginX` and `lineBaselineY` must be converted into element-local
coordinates by subtracting the element rectangle's origin. Clip paths,
highlights, and legacy text need the same coordinate convention. The group can
then animate its transform and dimensions while its text remains correctly
aligned.

Other archived frontend changes should be evaluated independently rather than
silently bundled into slots:

- per-viewport SVG ID namespaces matter when two visualizations are shown at
  once;
- keyboard selection, focus semantics, and contrast-aware foreground colors
  are worthwhile accessibility improvements;
- a `resetKey` prevents state leaking between different artifacts;
- connector rendering requires compiler/IR relation data, not just client
  inference;
- grouping timeline cards by operation ID remains compatible with the current
  immutable event model; and
- actual Svelte component/E2E tests should replace source-string assertions for
  transition behavior.

The archived comparison and hydration systems are different cases. The full
sample-set/preference-study flow depended on backend/event-model work that was
not retained, so it is not a frontend-only regression. The old hydration
helper is obsolete because current `visualization.rendered` events contain the
render JSON inline. A simpler comparison view could group current render events
by source hash and seed; persisted preferences would require a new event and
command.

## `commit` versus `materialize`

In Core:

```haskell
materialize :: Pending tag %1 -> TraceBuilder (Block tag)
commit = materialize
```

In the facade, `materialize` instead requires a `Query` so it can attach facts,
while `commit` exposes the untagged Core operation. There are no current example
uses of `commit`, and `materialize emptyQuery pending` has the same intended
meaning.

Haskell does not provide ordinary default arguments. An overloaded
“one-argument or two-argument materialize” class would make inference errors
and generated documentation worse. Preferred options, in order, are:

1. keep `materialize query pending`, remove `commit`, and document
   `emptyQuery`;
2. add `materializeUntagged pending` if that common case needs a name; or
3. in a deliberate breaking change, reserve `materialize` for the untagged
   primitive and call the query form `materializeAs` or `materializeTagged`.

Before changing it, add a test for copy/rematerialization facts. A copied
`Pending` value does not automatically inherit the source block's semantic
facts; only the query supplied at materialization attaches new facts. That may
be intentional, but it should not remain accidental.

## Symmetric bridges and affine solving

The TODO beside `(=/)` is justified. The current numeric implementation of:

```text
lhs =/ delta /= rhs
```

lowers each component to:

```text
abs (lhs - rhs) == delta
```

`abs` is non-affine, so this cannot use the normal bounded-affine design-space
sampler. It uses the nonlinear penalty optimizer instead. The word `Or` in
internal relation classes refers to Haskell type dispatch between numeric and
categorical behavior; it is not an affine OR operation.

For non-negative scalar `delta`, the same relation is a finite union of two
affine branches:

```text
lhs + delta == rhs
OR
rhs + delta == lhs
```

The solver already has finite alternatives, so the right lowering is a
deterministic `Cases`/`oneOf` decision whose selected branch contains only
affine constraints. The decision ID should derive from the visual rule,
declaration, and component so a seed remains reproducible.

For vectors, the present componentwise absolute value permits each component
to select its sign independently. Preserving that meaning creates up to `2^n`
branches. Either document the operator as scalar-only, generate the Cartesian
product explicitly for small fixed dimensions, or define a different vector
meaning. Do not accidentally force one sign for every component.

Directed bridges `=| delta |=` are already affine and should remain the default
recommendation. Until finite lowering exists, either hide the symmetric form
from authored Sverlin or document its optimizer fallback and performance
implications honestly.

## Automatic canvas constants

`LinearTrace.View.Build` currently uses a minimum axis size of `20`, a maximum
of `4096`, and an automatic logical canvas of `800 x 600`. `800 x 600` appears
in the earliest visualization compile path (`52f842b`); `8eac3d6` changed a
fixed view environment into the current automatic-envelope behavior.

These values are arbitrary in the sense that they are policy choices, but they
are not harmless display defaults. They influence solver bounds, layout
variation, font sizing, and wrapping. The browser scales the compiled root and
should not feed its current viewport back into server-side compilation, because
that would make the same source and seed nondeterministic across clients.

Recommended shape:

```haskell
data CanvasDefaults = CanvasDefaults
  { automaticWidth  :: Double
  , automaticHeight :: Double
  , minimumAxis     :: Double
  , maximumAxis     :: Double
  }
```

Keep the existing numbers as compatibility defaults, allow the trusted host to
configure them, record the selected profile in compile provenance, and cover
explicit width/height, automatic axes, aspect ratios, and boundary clamping in
tests.

## Style-variable bindings and style-family keys

### `StyleVariableBinding`

`StyleVariableBinding` is sparse provenance, not a parallel copy of
`VisualStyle`. It says which solver variables contributed to a concrete field.
Literal-only fields need no entry. Because the style metadata traversal emits a
field path generically, adding a new style field does not require a new member
on this binding record.

It does still require end-to-end work in the concrete contract:

1. define the Haskell style field and its typed value;
2. add the concrete IR property;
3. compile/materialize it;
4. regenerate the TypeScript declaration;
5. update the runtime Valibot structure;
6. render it; and
7. add a real-output decoder test.

The current `elementStyleVariables` collection also receives box/layout paths
from `nodeBoxVariableBindings`, so its name is narrower than its contents.
Rename it to something like `elementVariableBindings` or `valueProvenance`.
String paths are flexible but can drift; a closed Haskell `VisualField` sum
encoded to stable strings would preserve generic storage while making renames
and coverage checkable.

### `styleFamily "target"`

There is no separate definition of the `"target"` family in
`LinearSearch.sverlin`. The string itself becomes the family key. With
generative styles enabled, the compiler makes automatic choices coherently per
family (surface/profile, font weight, palette, and related defaults). Explicit
author style fields take precedence, and the family can cascade through a
generated hierarchy.

Without an explicit key, trace leaves fall back to a family derived from their
payload kind. In `LinearSearch`, ordinary value nodes would otherwise tend to
share one family. Giving the target and probe nodes distinct keys isolates
their coherent automatic choices. A family used only once still acts as an
isolation key; it is not looked up in a predefined style table.

## Answers to the TODOs in the historical interface audit

### Split the author facade before renaming internals

`LinearTrace.Choreography` currently combines the author language with trusted
host operations such as graph construction, solving, statistics, and runner
functions. It also aliases `Choreography` directly to `TraceBuilder`.

The smallest useful boundary change is:

```text
authored body       -> Sverlin
generated footer    -> Sverlin.Runner (or another tiny opaque seam)
compiler executable -> Sverlin.Compiler
wire consumers      -> LinearTrace.Visualization.IR
solver users        -> Solver
```

Introduce `type Program = TraceBuilder` in the author facade, and make generated
sources import only `Sverlin`. Interpret the authored `program :: Program ()`
and `visualization :: VisualizationBuilder ()` through a narrow host function;
the generated body should not need graph/solve/statistics names. Keep
`LinearTrace.Choreography` as a temporary compatibility facade.

Do not start by renaming every internal `Choreography` module. The benefit comes
from narrowing what authored source and the AI API index can see, not from a
large mechanical rename.

Likewise, do not literally remove the Cabal `app`: an executable still needs a
`Main`. Move reusable compilation work from `compile/app` into a library-owned
`Sverlin.Compiler` seam, and leave a thin CLI `Main` that parses arguments and
calls it.

### Overloads, error messages, and generated API documentation

The audit's “unify the overloaded interface” question should not be solved by
putting more operations behind one larger type class. Some current spellings
perform genuinely different author actions depending on context: `width` can
read a selection or set the current node, `node` can represent a selected trace
value or construct a generated parent, and `select` covers different payload
shapes. Numeric literals and `at`/`by`/`shift` also rely on useful but sometimes
opaque inference machinery.

First narrow the `Sverlin` facade and generate the DSL API index only from that
surface. Then split the most error-prone author operations into explicit names,
one feature group at a time, while retaining compatibility aliases long enough
to migrate examples. Supporting classes such as `BoundsExpr`, `AddExpr`, and
`RelateValues` may remain internal inference machinery; they should not be
presented as author concepts merely because GHC prints them in a signature.

A dedicated syntax/parser boundary can eventually translate internal type
failures into source-level DSL diagnostics. Before that boundary exists, do not
contort every Haskell class solely to hide its name: explicit facade functions,
Haddocks, examples, and a reachability audit provide more reliable clarity.

### `use`, arbitrary `create`, and semantic provenance

The current linear types prove consumption, but `use` can still launder
provenance: it consumes a block, exposes its payload once, permits arbitrary
Haskell computation, and a later `create` need not state how its payload was
derived. The trace sees “use” and “create,” not the transformation between
them.

`LinearSearch.sverlin` currently needs to inspect a comparison result and
branch, so simply deleting `use` would remove necessary expressivity. A better
replacement is a typed branch/inspection eliminator that returns an opaque
branch token and controlled successor resources. The `BranchToken`/`matches`
ideas in `03c4e14` are useful donors, but should be adapted rather than copied
with the entire branch.

For creation, distinguish allowed origins such as external input, literal,
operator, and annotation. Derived values should normally be produced by typed
`apply`/branch operations that record provenance. Track origin in the trace and
validate the resulting graph.

This cannot be made a security boundary with open Haskell type classes alone.
As long as authored files can express arbitrary Haskell computation or declare
instances, smart constructors are conventions rather than complete
enforcement. Hide low-level capabilities as an interim improvement; use a
restricted syntax tree for actual enforcement.

### Restricted DSL and nested case expressions

The current body-only source, fixed imports, `NoImplicitPrelude`, and
`RebindableSyntax` reduce accidental capability exposure, but they are not a
sandbox. Arbitrary recursion and nontermination remain possible, and ordinary
Haskell declarations can undermine closed-world policy.

`ifThenElse` alone also cannot safely solve linear branching: an ordinary
function receives both branch expressions, which can capture and apparently
duplicate the same linear resources. Safe branch syntax needs either an
explicit resource bundle/continuation representation or a parser/lowering pass
that builds branch IR with one linear environment per arm.

Do not use regex rewriting of Haskell. A staged direction is:

1. interim: parse with the GHC parser, whitelist declarations/expressions, and
   report source-span diagnostics;
2. retain worker isolation, timeouts, and resource limits because a whitelist
   is still not a security proof; and
3. long term: define a small `.sverlin` parser/AST with structured `if`/`else`,
   closed declarations, and lowering to the typed internal program.

The dedicated parser is also the right place to prevent deeply nested
generated `case` expressions and replace internal type-class errors with DSL
vocabulary. Flat named continuations are preferable to syntactic case towers.

### Typography: one solve or two?

The current typography pipeline is not redundant. It first solves visual
geometry, then shapes text and selects fonts/wrapping with HarfBuzz, and finally
adds affine text-fit constraints for a second solve. The second solve pins much
of the first geometry, so it mainly validates/refines typography; it does not
currently allow intrinsic text size to redesign every box.

For a fixed font and fixed line-break candidate, text width/height can be
expressed affinely in font size. The difficult choices are discrete font and
wrapping candidates. A true one-pass model could pre-shape a finite set of
candidates and encode each as a finite affine alternative, but that risks a
large Cartesian product and changes solution ranking.

Keep the two-pass implementation unless text-driven layout is an explicit
requirement. If it becomes one, introduce clear sizing modes:

- **intrinsic/hug:** text minimum/preferred size constrains the box;
- **fit text:** the box constrains font size; and
- **wrap:** line-break candidates are finite choices.

Intrinsic minimum, preferred, and maximum-content sizes are more useful than
one unconditional “text minimum” rule.

### Why resources are content-addressed attachments

The resource package is intentional. IR JSON contains descriptors while bytes
are written under `resources/<sha256>` and checked against the manifest. This:

- keeps font/glyph data out of base64 JSON;
- deduplicates identical immutable data;
- enables cacheable, target-neutral attachments;
- gives byte length, media type, and SHA-256 integrity checks; and
- lets the server persist JSON and binary resources appropriately.

This is a useful boundary, not unnecessary abstraction. Individual target or
diagnostic helpers can still be audited for real consumers.

### IR documentation, generation, and structural schema drift

The Haskell IR/Aeson encoding is the canonical JSON shape. The generator emits
TypeScript declarations, while `src/lib/shared/visualization/schema.ts`
manually repeats the runtime structure and adds semantic validation such as
unique IDs, valid references, acyclic hierarchy, and valid text ranges.

The semantic checks should remain handwritten, but the duplicated structural
schema can drift. For example:

- adding an optional Haskell field or union constructor widens generated TS,
  while the older strict Valibot schema can still compile and reject real new
  JSON;
- removing an optional field can leave the old schema requiring something the
  compiler no longer writes; and
- widening an enum can be type-compatible elsewhere while the runtime decoder
  rejects the new token.

Generate the structural Valibot layer or JSON Schema from the Haskell
description, then compose readable handwritten invariants on top. Add an IR
design document covering coordinate systems, identity/lineage, lifecycle,
resources, and versioning; generated types document structure but not those
semantics.

### Style profile definition and configuration

The generative style system currently has private profile choices such as
transparent, outline, flat, soft-card, and pill surfaces, plus fixed font,
weight, occupancy, and palette domains. `runChoreographyWithGenerativeStyles`
selects this policy; authored code supplies semantic families and explicit
overrides rather than selecting a host profile set.

Adding a new profile currently touches the constructor/domain and all mappings
for fill, stroke, borders, padding, radius, alignment, and tests. Convert the
private collection into a non-empty data-driven `StyleProfileConfig`, selected
by a trusted host `ProfileSetId`. Include that ID/config revision in
provenance. Keep author-facing `styleFamily` semantic rather than exposing the
global styling algorithm as a collection of decoration commands.

### Solver architecture and public operators

The historical audit's request for a top-level solver facade is already mostly
complete: `Solver` is the intended external API and `Solver.*` modules are
implementation details in Cabal. Do not merge that library API blindly into
the authored Sverlin dialect.

`DesignSpace` does not turn arbitrary nonlinear expressions into affine ones.
It handles finite choices/disjunctions when each resolved branch is a bounded
affine problem, then enumerates or conditions a branch and samples its convex
polytope. Expressions such as variable-by-variable multiplication, `abs`,
`min`/`max`, variable division, powers, and `signum` use the fallback optimizer.
Unresolved finite cases mixed into a nonlinear fallback can fail rather than
being usefully optimized.

For authored Sverlin, prefer affine-safe expression types. Multiplication and
division should require a fixed scalar/ratio unless the author explicitly asks
for a nonlinear expression. Keep the broader internal solver operations for
direct library users, but do not imply that every ordinary numeric expression
has the same diversity, performance, or guarantees.

The “visualize the gap with a red line” request exposes a separate boundary.
The IR contains solved variables and field bindings, so an inspector can show
which variables influenced a field. It does not contain relation endpoints, so
the client cannot infer that a constraint connects element A to element B.

Two valid approaches are:

- author a thin ordinary visual node/guide whose geometry is constrained
  between the elements; or
- add a general `VisualRelation`/connector IR record with source/target anchors,
  relation/constraint ID, and contributing variable IDs.

The archived connector and projection-provenance work in `03c4e14` is a useful
donor for the second approach. Do not infer semantic relationships in Svelte by
parsing variable names.

### Non-affine examples and soft constraints

There is no catalogued `.sverlin` example intentionally demonstrating the
nonlinear fallback. Direct solver tests cover cases such as `x * x == 0.25`, and
the public symmetric bridge is currently another path into it.

More seriously, the bounded-affine sampler deliberately ignores all soft
constraints. Therefore the facade description of `encourage` as improving
ranking is not true for the normal affine visualization path. A direct test
currently confirms broad sampling despite a softened target.

A public author feature should not be silently ignored. Choose one of:

1. hide/remove `encourage` until it has defined behavior;
2. make compilation emit an explicit diagnostic/error when the selected
   backend ignores it; or
3. implement preference-aware post-sampling/ranking while preserving hard-space
   correctness and record that policy in provenance.

Add separate tests for optimizer-mode soft influence, affine-mode handling, and
backend diagnostics. If a nonlinear example is added, label it diagnostic
rather than presenting fallback optimization as the preferred DSL style.

### Test organization and API reachability

Do not move test modules into `compile/src/Solver`; Cabal tests under
`compile/test` are conventional. Instead split the large `SolverTest` into
focused test modules with a small test `Main` while keeping stable reusable
fixtures under `compile/test-support/Solver/TestFixtures.hs`.

The old audit's claim that only the minimal example crossed the full source
boundary is now stale: the production example test compiles all six catalogued
examples at multiple seeds. Source-generation tests remain relatively small,
and archived component transition tests were not retained. Continue the audit
with an explicit reachability matrix:

| Surface                  | Meaning                                         |
| ------------------------ | ----------------------------------------------- |
| Author source            | Available from the future `Sverlin` import.     |
| Generated runner         | Needed only by generated footer/interpretation. |
| Trusted host             | Compiler pipeline and diagnostics.              |
| External Haskell library | Stable `Solver`/IR contracts.                   |
| Internal                 | No compatibility promise.                       |

Likely deprecation candidates are `commit`, orphan lifecycle wrappers,
host-runner names in the author facade, raw solver/global primitives in
Sverlin, and purely mechanical aliases. Preserve capabilities until examples
and tests cover their intended replacements.

### What exactly is incomplete about `Slot` and `observe`?

The facade exports the `SlotHandle`, `Observe`, `Seal`, and `Unseal` result
types, but not `observe`, `seal`, or `unseal`. Those wrappers are therefore
unreachable to normal authored source.

Core `observe` only snapshots/logs `TraceObserve` and returns the same block; it
does not expose the payload. The current view projection drops `TraceObserve`
as well. Unless an observable event-marker purpose is defined, remove `Observe`
from the author facade rather than completing it by name alone. Slot is
different: it has a recoverable historical storage purpose and should be
restored end to end.

## Historical commits worth retaining as evidence

These commits are donors and regression evidence, not a sequence to cherry-pick
wholesale:

| Commit    | Evidence to inspect                                                                                                  |
| --------- | -------------------------------------------------------------------------------------------------------------------- |
| `180eaec` | First Core seal/unseal model.                                                                                        |
| `970907d` | Variable owner, same-bounds slot projection, read/write lifecycle, and Fibonacci example.                            |
| `52f842b` | Original compile-to-Svelte render patches, incoming render identity on replace, keyed geometry transitions.          |
| `4a28efb` | Fork-origin animation.                                                                                               |
| `b7d2d85` | Mainline Svelte transition repair before SVG typography.                                                             |
| `9efb493` | Compiler typography/resources and the SVG conversion where geometry/entry/exit transitions were lost.                |
| `0ff53cc` | Template/API-index refactor and removal of non-temporal `View.Patch`.                                                |
| `4f88244` | Later `Sverlin`/compiler seam, slot and semantic ideas; reuse boundary topology selectively.                         |
| `0f7eb5b` | Prepared compiler and comparison/hydration work; hydration assumptions are obsolete.                                 |
| `a5084ba` | Stable render IDs, semantic offsets, viewport fixes, and stronger tests on the archived line.                        |
| `03c4e14` | Most complete archived slot/branch/connector/robust-SVG-transition reference.                                        |
| `dc018bb` | Mainline restoration based on the `181a53d` baseline; it deliberately did not merge the archived redesign wholesale. |

For historical files, use `git show <commit>:<path>` so investigation remains
possible even when the file was later moved or deleted. The deleted
`POST_181_REFACTOR_INDEX.md` is also useful for distinguishing proven donors
from experiments that were intentionally not restored.

## Decisions to make before implementation

The evidence narrows the choices, but these are product/API decisions rather
than facts recoverable from Git:

1. **Slot write identity:** does writing a live value move/adopt that value's
   occupant lineage, or is every write defined as continuation of the previous
   occupant? Historical behavior supports adoption; ordinary `replace` supports
   continuation. Keeping both operations is the clearest design.
2. **First slot scope:** ship one slot per owner first, or require explicit
   `SlotId` immediately? The inline TODO correctly requires `SlotId` before
   multiple same-typed slots. Adding it immediately avoids a second wire-format
   migration.
3. **Soft preferences:** remove, diagnose, or implement ranking in affine mode.
   Keeping silent no-op behavior is not acceptable.
4. **Symmetric bridge vectors:** scalar-only, independent component signs, or a
   different vector-distance definition.
5. **Facade compatibility:** whether `LinearTrace.Choreography` remains a
   deprecated re-export for one release or changes with the new `Sverlin`
   facade immediately.
6. **Syntax boundary:** how much interim GHC-AST restriction is worthwhile
   before implementing a dedicated parser.

## Recommended implementation order

1. **Capture behavior first.** Add focused current-contract tests and historical
   slot/transition fixtures. Specify location identity, occupant identity,
   forward playback, reverse playback, and illegal owner/slot combinations.
2. **Split author and host facades.** Add `Sverlin` and `Program`, narrow the
   generated runner seam, repoint the generated API index, and keep a temporary
   compatibility module. This makes every later API decision visible in the
   correct surface.
3. **Restore general SVG transitions.** Port the local-coordinate transition
   model from `03c4e14` to current typography and add real Svelte/E2E coverage.
   Slot animation can then rely on a tested renderer rather than masking a
   general regression.
4. **Restore slots end to end.** Add stable `SlotId`/storage binding, facade
   operations, view projection, occupant-adoption intent, IR validation,
   variable/Fibonacci and focused examples, and forward/reverse tests.
5. **Make solver guarantees truthful.** Lower symmetric bridges to finite
   affine alternatives, decide soft-constraint behavior, restrict author
   arithmetic to affine-safe forms, and expose nonlinear fallback explicitly.
6. **Generate the structural wire schema.** Retain handwritten semantic
   invariants and document IR coordinate/identity rules.
7. **Data-drive host style profiles and canvas defaults.** Record their profile
   revisions in compile provenance.
8. **Introduce restricted syntax incrementally.** Start with parsed
   whitelist/diagnostics if useful, then move branching and provenance to a
   dedicated `.sverlin` AST rather than accumulating fragile Haskell tricks.

Each stage that changes the public DSL must update facade Haddocks,
`dsl-interface.md`, the generated API index, body-only examples, Haskell tests,
and the real source-to-TypeScript integration in the same change.
