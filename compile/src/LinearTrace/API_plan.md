# LinearTrace API refactor plan

This file records concise, agreed implementation instructions. Keep historical
evidence and extended rationale in `API_refactoring.md`; update this plan as
decisions are made.

## Goals

## Public API

This section is the declarative target surface. It must restate every public
interface, including interfaces retained unchanged and agreed additions. The
generated DSL API index remains authoritative for exact inferred signatures;
this plan records grouping, purpose, and intended composition.

The authored API comprises exactly three conceptual parts, each with its own
builder/monadic context:

1. `Domain` declares semantic vocabulary and matching language.
2. `Program` constructs the immutable linear trace.
3. `Render` declares how domain values and program events are visualized.

The new `Sverlin` module is the supported author facade. It wires these three
parts together, re-exports their intended author vocabulary, and owns the
maintainable overview and composition documentation. `Choreography` must
disappear as a public API name; do not preserve it as the conceptual umbrella.

### Domain

Add a new Domain module and builder context. Domain owns semantic declarations,
fact construction, payload vocabulary, operator and relation vocabulary, and
queries shared by Program and Render. Keep the declaration representation
abstract so the facade can validate a complete domain before executing a
program or compiling render rules. A relation kind supplies the semantic label
for a slot-to-slot relation and defines whether endpoint order is meaningful;
the exact declaration combinators remain open with the rest of Domain.

Move the following existing interfaces into Domain:

- Facts and queries: `FactValue`, `Fact`, `Facts`, `emptyFacts`, `factAtom`,
  `factSymbol`, `factInt`, `factsUnion`, `factsToList`, `PayloadView`,
  `Traceable`, `Query`, `QueryInt`, `emptyQuery`, `queryAtom`, `queryInt`,
  `queryFacts`, `payload`, `QueryField`, `(@:)`, `(<&>)`, and `fromLabel`.
- Payload and operator vocabulary: `Payload`, `LUnit`, `LBool`, `LInt`,
  `LDouble`, `LString`, `LOperator`, `CoreOperator`, `LinearPayload`,
  `Applicable1`, `Applicable2`, `applyLinear1`, `applyLinear1Into`,
  `applyLinear2`, and `applyLinear2Into`.

Revise `CoreOperator` so that it retains only the semantics needed to preserve
and apply an operator payload. It must not require `operatorPayloadText` or any
other presentation value. Operator spellings such as `+`, `==`, or `equals`
belong to the particular Render mapping.

The exact declaration combinators and concrete builder type name are still to
be designed. They must support this separation without requiring authors to
import internal Core modules.

```haskell
domain :: Domain ()
domain = do
  -- Declare the payload tags, operators, and semantic vocabulary used by the
  -- program and render rules. Exact declaration combinators remain open.
  declarePayload @Value
  declareOperator Add
```

```haskell
let tag = queryAtom "value" <&> (#index @: 3)
let facts = queryFacts tag
```

### Program

The Program interface constructs an immutable trace while linear values enforce
resource ownership. Rename the public `Choreography` monad and underlying
author-facing `TraceBuilder` API to `Program`; target authored signatures must
use `Program` exclusively. Internal implementation types may remain temporarily
while modules are migrated.

The Slot restoration baseline is commit `970907d` from 16 June 2026. Restore
that model deliberately: public `Slot owner tag`, one slot per owner, the owner
`BlockId` as stable storage-location identity, `unseal` consuming the slot and
returning owner plus occupant, and `seal` reconstructing the slot with the same
owner. Reads compose unseal, copy, and reseal; writes compose unseal, replace,
and reseal. Do not import the August experimental `SlotId`/`SlotRef`,
vacant/occupied typestate, `declareSlot`, `occupySlot`, `vacateSlot`, or
`retireSlot` APIs into this restoration.

- Program context: `Program` (replacing `Choreography`).
- Linear resources: `Block`, `Slot`, `RelationHandle`, and `Pending`;
  `Payload` and relation-kind vocabulary are defined by Domain and consumed
  here.
- Lifecycle operations: `create`, `copy`, `use`, `apply1`, `apply2`, `replace`,
  `seal`, `unseal`, `relate`, `unrelate`, `materialize`,
  `materializeWithTags`, `commit`, `destroy`, and `checkpoint`.
- Lifecycle results: `OneUse`, `Create`, `Observe`, `Use`, `Copy`, `Replace`,
  `Apply1`, `Apply2`, `Destroy`, `Seal`, `Unseal`, `Relate`, `Unrelate`,
  `(<$>)`, and `(<*>)`.

Restore the lowercase `seal` and `unseal` operations alongside the existing
`Seal` and `Unseal` result types. Add `relate` and `unrelate` only for slot
locations; do not overload them for blocks. `Slot` and `RelationHandle` remain
linear values supplied by lifecycle operations: authors cannot construct them,
inspect their internal identities, or extract a stored child except through the
corresponding Program operation. Do not add declaration, read, write, variable,
or other workflow helpers to Program; higher-level APIs and authored programs
compose those behaviors from the general primitives.

Q: What is RelationHandle? Is this a API public interface? Or is this a newly
defined idea, based on the relate/unrelate operations? Maybe call it Relation?

#### Lifecycle operations

Lifecycle operations create, transform, expose, associate, or consume linear
resources. Operations that produce `Pending` results are completed through the
separate materialization interface below.

##### Create

`create` introduces a payload as a `Pending` obligation. It describes the
origin of a value, but the create event is not complete until the pending value
is materialized. Render can use the resulting origin event for an entering
visual instance.

```haskell
Create pending <- create (LInt 3)
```

##### Copy

`copy` preserves the original block and produces one pending duplicate. After
materialization, the trace records fork lineage from source to copy. Render can
use that lineage to stage the new visual instance from the source instance.

```haskell
Copy original pendingCopy <- copy original
duplicate <- materialize (queryAtom "copy") pendingCopy
```

##### Use

`use` consumes a block and exposes its payload exactly once through `OneUse`.
It describes terminal observation or branching in the Program and records which
trace value was consumed. The linear `(<$>)` and `(<*>)` operations compose
one-use payload calculations without making the payload unrestricted.

```haskell
Use oneValue <- use value
let displayed = toDisplay <$> oneValue
```

`Observe` currently has a public result wrapper but no public `observe`
operation. Decide separately whether a non-consuming trace observation has a
clear renderable meaning; otherwise remove the orphan wrapper from Sverlin.

TODO remove Observe entirely
TODO consider how Use should be used, or if it should be removed. does it
confer semantics other lifecycle ops don't already permit?

##### Apply one

`apply1` consumes an operator block and one argument block, then produces one
pending result. It makes unary computation provenance explicit so Render can
depict the operator, input, and result rather than infer their relationship
from payload text.

```haskell
Apply1 pendingResult <- apply1 negateOperator argument
result <- materialize (queryAtom "result") pendingResult
```

##### Apply two

`apply2` consumes an operator block and two argument blocks, then produces one
pending result. It records both ordered inputs, enabling Render to visualize a
binary computation and its data flow.

```haskell
Apply2 pendingSum <- apply2 addOperator leftOperand rightOperand
sumBlock <- materialize (queryAtom "sum") pendingSum
```

##### Replace

`replace` consumes an existing block and a compatible pending value, producing
a new pending value whose event records continuation from old identity to new
identity. It describes an evolving trace entity. Render can keep the old visual
instance continuous while updating its payload, facts, content, and geometry.

```haskell
Replace pendingNext <- replace current pendingValue
next <- materialize (queryAtom "current") pendingNext
```

Replacement is distinct from storing an independent live value in a slot:
replacement continues the old occupant, while slot storage preserves the
location and may adopt a different occupant lineage.

##### Destroy

`destroy` consumes a live block without producing a successor. It records the
end of that value's lifetime, allowing Render to remove or animate the exiting
visual instance at the corresponding checkpoint.

```haskell
Destroy <- destroy obsolete
```

##### Seal

Restore public `seal`. It takes exclusive ownership of a live owner and child,
then reissues the owner with the same `BlockId` and returns a linear `Slot`
containing the child. The child is no longer available as a `Block` while it is
inside the slot; it can be recovered only by passing that slot with the matching
owner to `unseal`. The trace records the association: the owner identifies the
stable storage location and the contained child identifies its current
occupant. Render can constrain that occupant to the owner's location.

```haskell
Seal owner slot <- seal owner value
```

##### Unseal

Restore public `unseal`. It takes exclusive ownership of a live owner and a
`Slot` containing a child, verifies that the owner matches the slot's location,
then reissues the same owner and returns the contained child as a live `Block`.
The consumed slot no longer exists; calling `seal` with that owner and a child
constructs the next slot for the same location. The recovered child is available
for arbitrary Program composition—copy, replace, use, destroy, or reseal—without
embedding a fixed read/write abstraction in the core language.

```haskell
Unseal owner value <- unseal owner slot
```

##### Relate

`relate` creates a temporal semantic relation between two persistent slot
locations. It consumes two `Slot`s, each containing its current child, and
returns both slots unchanged together with a new linear `RelationHandle`.
Consuming and returning the slots threads their capabilities without giving the
relation ownership of either child. The relation records the owner `BlockId`s
that identify the two locations, not the `BlockId`s of their current occupants.

```haskell
Relate sourceSlot1 targetSlot1 relation <-
  relate DependsOn sourceSlot0 targetSlot0
```

The June baseline supports one slot per owner, so the owner `BlockId` is the
complete location identity. Unsealing and resealing through that owner
reconstructs a `Slot` for the same location and does not create a new relation
endpoint. Multiple slots per owner are outside this restoration and require a
separate design discussion; they must not cause `SlotId` to leak into the
authored facade by default.

##### Unrelate

`unrelate` removes exactly the relation represented by a linear
`RelationHandle`. It consumes that handle plus the current `Slot`s for both
endpoints, verifies that their owner identities match the relation, and returns
the two slots. Supplying the current slots makes endpoint identity explicit and
ensures the operation composes with ordinary linear slot threading.

```haskell
Unrelate sourceSlot2 targetSlot2 <-
  unrelate relation sourceSlot1 targetSlot1
```

A slot may participate in several relations: thread the returned `Slot` through
each `relate` or `unrelate` call while retaining one distinct linear
`RelationHandle` per active edge. Every relation handle must eventually be
consumed. An owner or slot cannot complete its lifecycle while a relation to
that location remains active.

Q: is a slot (using the restored design) a special case of a relation semantically?

#### Materialization

Materialization resolves the `Pending` obligations produced by lifecycle
operations. It assigns a block identity, completes the pending trace event, and
optionally attaches Domain facts used by Render selection.

##### Materialize

`materialize` resolves a `Pending` value into a live `Block` and attaches facts
from a `Query`. It gives the value its stable block identity and completes the
pending create/copy/apply/replace event so Domain queries and Render selections
can address it.

```haskell
block <- materialize (queryAtom "value" <&> (#index @: 3)) pending
```

##### Materialize with tags

`materializeWithTags` combines fixed query facts with facts derived from the
payload being materialized. Use it when Render selection needs semantic
properties computed from the concrete result rather than known before the
operation runs.

```haskell
tagged <- materializeWithTags (queryAtom "value") tagsFromPayload pendingTagged
```

##### Commit

`commit` materializes a pending value without attaching semantic facts. Use it
for traceable intermediate values that Render addresses only through operation
lineage, or that should not participate in semantic selection.

```haskell
untagged <- commit pendingUntagged
```

Q: why are three interfaces needed for materialization? can we merge
into 1?

#### Timeline

##### Checkpoint

`checkpoint` commits the pending trace-event batch under a stable label. It
defines the temporal states that Render and the visualization player expose;
operations before the checkpoint appear together as one program step.

```haskell
checkpoint "value stored"
```

Use checkpoints after complete logical operations. In particular, ordinary
slot workflows should unseal and reseal before checkpointing unless an empty
storage location is deliberately part of the trace.

#### Proposed new "step" interface

a program is made up of named steps, which can be composed together
in a reusable way. a
step has an associated code fragment to allow for mapping to source
code visualisations.

TODO expand on this with an insertion sort example below

```haskell
program :: Program ()
program = do
  --TODO
```

```
int linear_search(int A[], int n, int target) {
  for (int i = 0; i < n; i++) {
    if (A[i] == target) {
      return i;
    }
  }
  return -1;
}
```

fragment tag: linear operation/s
i-init: create (literal 0)
i-var: create (integer variable)
i-var-assign: = (seal) -> slot
i-read: unseal -> copy -> seal
n-read: unseal -> copy -> seal
i-lt-n: < apply2

etc

#### Complete Program

Every linear resource and pending obligation must be consumed by the completed
`Program`. A typical definition composes the primitives above; higher-level
domain libraries may package such compositions without adding specialized
operations to the general Program interface.

```haskell
program :: Program ()
program = do
  Create pending <- create initialValue
  value <- materialize (queryAtom "value") pending
  checkpoint "created"
  Destroy <- destroy value
  checkpoint "removed"
  pure ()
```

### Render

Render owns the visual-rule builder, semantic selection, hierarchy, content,
layout, style, and visual constraints. Rename the author-facing
`VisualizationBuilder` context to `Render`. A separate compiled rule/spec type
may remain internally, but authored signatures and documentation must use
Render terminology.

#### Rules, selection, and hierarchy

The visualization interface declares reusable rules independently of program
execution. Retain `MatchSpec`, `Selected`, `Variable`, `Bound`, `NodeBinding`,
`AnyPayload`, `GeneratedNode`, `CanvasNode`, `PayloadQuery`,
`VisualizationBuilder` (to be replaced publicly by `Render`), `Select`,
`select`, `visualize`, `Node`, `node`, `self`, and `canvas`.

Retain the general content interfaces `ContentValue`, `text`, `content`, and
`fitText`. Redefine `fitText` as allowing the solver to vary a single line's
font size within explicit bounds so that the line fits its content box; it must
not insert line breaks. Remove the specialized `codeContent`, `codeWrap`,
`highlightCode`, `CodeRange`, `codeRange`, and `emphasizeCode` interfaces. Code
is not a distinct kind of visual content: it is one possible Render mapping of
the Program.

Add a general composed-text builder. The target vocabulary is `TextBuilder`,
`literal`, `fragment`, and `fragmentMany`; exact supporting types may be refined
during implementation. A fragment associates a typed step definition with a
text range, while `fragmentMany` associates the same range with several step
definitions. The builder must lower one independently positioned line to one
shaped string plus validated range metadata. It must not shape each fragment as
an independent text node, because doing so would lose the font renderer's
whole-line kerning, bidirectional-text, and ligature behavior.

A text node represents one independently positioned line. Automatic wrapping,
soft wrapping, hyphenation, and compiler-inserted line breaks are outside the
target API. Newline-containing content must be lowered to separate generated
nodes; a visualization that needs two lines places two ordinary text nodes one
above the other. Render uses the normal hierarchy, affine constraints, and
style API to align and space those nodes. This adds variables and constraints
roughly in proportion to the number of authored lines instead of creating a
Cartesian product of possible wrap patterns. Typed fragment ranges permit
step-sensitive styling and animation without making code syntax part of Domain
or Program.

```haskell
render :: Render ()
render = do
  NodeBinding values <- select (queryAtom "value")
  node $ do
    NodeBinding group <- self
    padding (uniform (by 12))
    node values $ do
      fitText (text "value")
      ensure (width group .>=. width values)

  node canvas $ aspectRatio 4 3
```

```haskell
Selected returnLine <- node $ do
  content $ do
    literal "return "
    fragment @ReturnFound "i"
    literal ";"
  style @FontFamily (FixedStyle FontIBMPlexMono)

ensure $ left returnLine .==. left comparisonLine + shift (num 24)
ensure $ top returnLine .==. bottom comparisonLine + shift (num 4)
```

#### Reusable values and finite decisions

Retain `bindInt`, `bindContent`, `variable`, `variableFrom`, `choice`,
`ChoiceDomain`, `Choice`, and `RandomSeed`. Bound query values are reused within
one matched rule; variables and choices introduce solver-backed values.

```haskell
Bound index <- bindInt
Variable gap <- variableFrom (asScalar index)
Variable alignment <- choice

ensure (x current .==. at 20 + shift gap)
caseOf alignment $ \case
  AlignLeft  -> [left current .==. left canvas]
  AlignRight -> [right current .==. right canvas]
```

#### Layout, geometry, and box model

Retain the typed numeric domains `Coord`, `Span`, `Offset`, `Scalar`,
`VisualExpr`, `Vec2`, `Bounds`, `Free`, `Unit`, and `Angle`. Retain geometry
classes and accessors `Left`, `Top`, `Right`, `Bottom`, `Width`, `Height`, `X`,
`Y`, `Center`, `left`, `top`, `right`, `bottom`, `width`, `height`, `x`, `y`,
`center`, `size`, and `bounds`.

Retain constructors and arithmetic `vec2`, `at`, `by`, `shift`, `asScalar`,
`asCoord`, `asSpan`, `num`, `fromInteger`, `fromRational`, `(+)`, `(-)`, `(*)`,
`(/)`, and `(|+|)`.

Retain the hierarchical box model `Insets`, `uniform`, `symmetric`, `edges`,
`padding`, `margin`, `Axis`, `ContentFit`, `contentFit`, `aspectRatio`, `Percent`,
`percent`, `xAt`, `yAt`, `widthOf`, and `heightOf`.

```haskell
node selected $ do
  center (vec2 (at 200) (at 120))
  width (by 160)
  height (by 80)
  padding (symmetric (by 8) (by 12))
  margin (edges (by 4) (by 8) (by 4) (by 8))
  contentFit Both Hug
  xAt (percent 50)
  widthOf (percent 40)

ensure (left second =| by 24 |= right first)
ensure (size second .==. size first)
```

#### Style authoring and colour

Retain `StyleChoice`, `style`, `withoutStyle`, `styleCase`, `styleFamily`,
`styleOf`, `NodeStyle`, `Opacity`, `FontSize`, `Radius`, `StrokeWidth`,
`Alpha`, `Fill`, `Stroke`, `BorderStyle`, `FontFamily`, `FontWeight`,
`FontStyle`, `TextAlign`, `Hsl`, `Color`, and `sat`. Remove `WhiteSpace`: a text
node contains one line, so there is no authored wrapping mode to select.

Also remove `ZIndex` and make this implicitly determined for now.

```haskell
node selected $ do
  styleFamily "value"
  style (FixedStyle (Hsl (num 220) (num 0.6) (num 0.5)) :: StyleChoice Fill)
  style (FixedStyle FontWeightBold)
  withoutStyle @Stroke

ensure (sat (styleOf @Fill selected) .>=. num 0.4)
```

#### Constraints and alternatives

Retain `ensure`, `encourage`, `VisualAlternative`, `alternative`, `oneOf`,
`caseOf`, `(.<=.)`, `(.>=.)`, `(.==.)`, `(=|)`, `(=/)`, `(|=)`, and `(/=)`.
Retain `global` for stable named solver values.

```haskell
ensure (width item .>=. by 80)
encourage (x item .==. x canvas)
ensure (right first =| by 16 |= left second)

oneOf "flow"
  (alternative "row" [right first .<=. left second])
  [alternative "column" [bottom first .<=. top second]]
```

The symmetric bridge `(=/) ... (/=)` remains public for now, but its affine
lowering and vector semantics remain an open decision below. `encourage`
likewise remains listed because it exists, even though affine-mode behavior
must be made explicit before the refactor is complete.

### Sverlin facade and host boundary

`Sverlin` is the only supported import for authored source. Its documentation
must introduce Domain, Program, and Render in that order, state their ownership
and linearity invariants once, and show one complete composition example. Avoid
re-exporting host execution machinery merely because generated source or the
compiler needs it.

```haskell
domain :: Domain ()
domain = ...

program :: Program ()
program = ...

render :: Render ()
render = ...
```

Move `VisualTraceGraph`, `ViewGraph`, `runChoreography`, `runChoreographyWith`,
`runChoreographyWithGenerativeStyles`, `buildViewGraph`,
`solveViewGraphWithSeed`, `solveViewGraphWithSeeds`,
`solveViewGraphWithPinnedSolution`, and `viewGraphStats` out of the authored
facade. Place them behind a narrow compiler/runner module that combines a
validated Domain, completed Program, and compiled Render description. Rename
that host API independently using Sverlin terminology; do not carry
`runChoreography*` names into the final boundary.

The generated footer and compiler executable may import the host module.
Authored body source may import only `Sverlin`.

## Semantics and invariants

- `seal` takes exclusive ownership of a live owner and child, reissues the same
  owner identity, and returns a linear `Slot` containing the child. No separate
  child capability remains available while the child is stored.
- `unseal` takes exclusive ownership of the matching live owner and that `Slot`,
  consumes the slot, reissues the same owner identity, and returns the contained
  child as a live `Block`.
- Preserve owner and child identity in `TraceSeal` and `TraceUnseal`; the owner
  represents the stable storage location while occupants may change.
- Do not encode declaration, read, or write semantics in these primitives.
  Copy-and-reseal and replace-and-reseal are author-level compositions.
- `relate` and `unrelate` operate only on slot locations. There is no general
  block relation: exact-block provenance remains represented by create, copy,
  apply, replace, use, and destroy events, while purely visual connections
  belong to Render.
- `relate` consumes and returns two `Slot`s containing their children plus a
  fresh linear `RelationHandle`. The relation handle contains stable endpoint
  identities but no owner or child capability; it cannot expose, copy, replace,
  or destroy either child.
- A relation remains active when either slot is unsealed, temporarily empty,
  resealed, or given a replacement occupant. It follows neither old nor new
  occupant `BlockId`: its endpoints remain the same persistent locations, so no
  retarget event is produced by a write.
- `unrelate` consumes the exact `RelationHandle` and the current `Slot`s for its
  two endpoints, validates both owner identities, and returns those slots.
  Passing a slot reconstructed through another same-typed owner is an error.
- Active relations must be removed before their endpoint locations or owners
  are destroyed. Relation creation and removal are checkpointed trace events;
  relation lifetime is independent of occupant lifetime.

## View and rendering

Project `relate` and `unrelate` as explicit `TraceRelate relationId kind
leftOwnerId rightOwnerId` and `TraceUnrelate relationId` events. Render resolves
each endpoint against the stable owner geometry rather than the current
occupant element. Consequently a rendered connector stays anchored while an
occupant exits, enters, or changes identity, and it may remain visible when a
slot is deliberately empty at a checkpoint. Forward playback introduces and
removes the relation at its events; reverse playback performs the inverse using
the same `relationId`. Render rules may choose how a declared relation kind is
drawn, but they must not infer semantic relations from block lineage, solver
variable names, or proximity.

## Compiler and runtime boundary

## Migration and compatibility

## Examples and tests

## Implementation order

## Open decisions

### Proposed solver architecture

Render constraints compile into a bounded finite piecewise-affine design space. The
compiler resolves explicit choices and exact algebraic case splits into affine
configurations. Small decision spaces may be enumerated; large spaces are conditioned
using a discrete feasibility solver. A seeded sampler then selects a configuration and
samples its convex affine region. Constraints that cannot be represented exactly in this
model are rejected with a source-level diagnostic; they do not silently fall back to
nonlinear optimization.

The compiled representation must preserve why each discrete split exists:

- An authored design choice, such as font, orientation, or connector routing, is part of
  the intended random design distribution. Give its alternatives equal weight by default
  and eventually permit explicit author weights.
- A compiler-created algebraic split, such as the positive and negative cases of `abs`,
  only partitions a numeric region. It must not become an extra equally weighted design
  choice. Weight such cells by the relative size of their valid numeric regions, with
  deterministic boundary ownership, so equivalent lowerings do not change the resulting
  distribution.

For example, if sans-serif text leaves nine times as much valid positioning space as
serif text, equal authored font weights still select each font half of the time; numeric
positions are then sampled inside the selected font's valid region. By contrast, splitting
one font's numeric range into two compiler-generated cases must not double that font's
probability.

For each seed, the proposed sampling order is therefore:

1. Select an assignment for the authored design choices according to their declared
   weights after removing assignments made impossible by the hard constraints.
2. Select among that assignment's compiler-created affine cells without introducing
   probability merely because the compiler split an expression into more cases.
3. Sample approximately uniformly inside the selected convex affine region.

A font whose metrics affect text bounds is consequently a genuine design branch. For
example, `horizontal + serif`, `horizontal + sans`, `vertical + serif`, and
`vertical + sans` may be four configurations, and every seed may select any feasible
one. If a discrete presentation choice does not affect solver geometry, sample it
separately rather than multiplying the affine configurations.

#### Typography branches and variable font size

Typography shaping is compiler-owned preparation rather than numeric solver arithmetic.
For a fixed font resource and face, weight, style, variation-axis values, shaping
features, source line, and text direction, shape the line once at the font's units-per-em
scale. Glyph advances, ink bounds, ascender, descender, and line height then become
constant coefficients belonging to that branch. Font size remains a bounded continuous
solver variable unless the author explicitly fixes it.

For a sampled font size `s`, node width `w`, node height `h`, and affine padding and
border expressions, a shaped line contributes constraints of the following form:

```text
minimumFontSize <= s <= maximumFontSize
horizontalInsets + lineWidthEm * s <= w
verticalInsets + lineHeightEm * s <= h
```

`lineWidthEm` and `lineHeightEm` are compiler-produced constants, so multiplication by
`s` remains affine. Left, centre, and right alignment also remain affine; for example,
centering uses `contentLeft + (contentWidth - lineWidthEm * s) / 2`. Several text nodes
may share the same font-size variable, in which case every line adds another affine fit
constraint and the tightest line limits the shared value.

Font family, weight, style, and any metric-affecting variation axes are authored discrete
choices. Each resolved choice supplies different shaping constants but leaves font size
continuous inside its region. A continuously varying weight or automatic optical-size
axis is not covered by this model because changing the axis can change the shaped metrics;
fix or discretize such axes before affine compilation. Missing glyphs or an unavailable
font invalidate that branch, with a source-level diagnostic if no font branch remains.

Font feasibility must be tested with the shaped text constraints before selecting a
branch. The compiler must not choose a font without considering its text, discover that
the line cannot fit above the minimum size, and fail when another font would have worked.
For small choice spaces, shape and certify every eligible font branch. For larger spaces,
cache shaping results by font-resource hash, face and axis values, features, and source
line, then expose the branch-specific affine constraints to the discrete feasibility
solver. A selected font branch is therefore known to contain at least one valid
combination of font size and geometry.

There are no automatic wrapping branches. A long line must fit by varying its bounded
font size or box geometry; otherwise compilation reports that the line must be shortened,
given a larger box, or split into separate text nodes. Explicitly authored lines may still
share font choices, font-size variables, alignment constraints, and vertical gap variables,
all without leaving one convex affine region.

The existing typography implementation already emits affine inequalities of this shape
in [Typography.hs](Visualization/Typography.hs). Its current two-pass flow nevertheless
selects a fitted size, replaces it with a numeric literal, and pins the initially sampled
width, height, padding, and stroke before the final solve. The target flow must remove
those pins: shaping supplies constants and constraints, while the final sampler jointly
chooses font size and geometry. Final IR materialization scales the prepared glyph metrics
by the sampled size and retains a small documented safety margin for output rounding.

`fitText` means bounded size variation inside this feasible region; it does not mean
"choose the largest possible size." Maximum-fit typography, if retained, is a separate
explicit policy that solves a linear boundary objective and therefore does not provide
font-size diversity. An authored fixed-size policy likewise creates a zero-dimensional
font-size slice while leaving other geometry available for sampling.

Uniform sampling over the complete region does not imply a uniform font-size marginal:
smaller text may permit more box positions and dimensions, giving it more valid geometric
space. If equal coverage of small, medium, and large text is desired, define explicit
size-band choices or a separate font-size prior and record that non-uniform geometric
policy in provenance.

#### Preparation, feasibility, and reuse

"Prepare a region once" means normalizing its constraints, reducing exact equalities,
certifying that it is non-empty, finding a valid starting point, and caching the numeric
data used by the sampler. It does not pin that configuration or reuse a previous sampled
layout. A new seed still selects a configuration and generates a new point. Cache only
deterministic prepared data so the same source, configuration, and seed produce the same
result regardless of cache warmth or batch order.

Enumeration should prepare every feasible configuration only while the estimated work
is small. Large spaces should retain a compact guarded representation, prepare the
discrete feasibility model once, and prepare individual affine regions lazily as they
are selected. A randomized optimization objective may find varied feasible assignments,
but it is not uniform sampling over them; the large-space strategy must either implement
the declared distribution or expose and justify a documented approximation.

Feasibility must be established by a dedicated deterministic feasibility phase rather
than by whether one random sample succeeds. Unsupported expressions and proven-empty
spaces fail immediately with source provenance. A feasible region that encounters a
numeric sampling failure may use a small bounded set of derived-seed retries and then
report a distinct numeric-backend diagnostic. A valid but visually unacceptable result
may similarly use a bounded sample batch and select an acceptable or best-scoring result.
Neither case permits open-ended retries or fallback to nonlinear optimization.

The following choices remain open before implementation:

- Define whether default equality applies independently at each authored choice or over
  complete feasible choice assignments, especially for nested or conditional choices.
- Choose a practical approximately uniform discrete sampler for large conditioned spaces;
  randomized MIP optimization alone is insufficient.
- Define how region sizes are compared when feasible affine cells have different numbers
  of free numeric dimensions, and how overlapping boundaries are assigned exactly once.
- Define the default font-size bounds and whether font-size diversity follows the joint
  geometric measure, explicit size bands, or a separately declared continuous prior.
- Decide whether maximum-fit typography remains as an explicitly non-random policy or is
  removed in favour of bounded `fitText` and authored fixed sizes.
- Set shaping-cache and eligible-font limits from text-heavy application benchmarks. The
  cache key must include every input that can change glyph metrics.
- Replace the raw configuration-count enumeration cutoff with a benchmarked cost policy
  that accounts for variables, constraints, equality reduction, and feasibility work.
- Set and justify construction, sampling, and retry budgets from optimized application-
  shaped benchmarks, and preserve every attempted derived seed in solver provenance.
