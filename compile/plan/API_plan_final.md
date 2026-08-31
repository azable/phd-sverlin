# Final Sverlin API and implementation plan

This document is the target contract for the Sverlin overhaul. The older
[`API_plan.md`](API_plan.md), [`API_plan_list.md`](API_plan_list.md),
[`API_requirements.md`](API_requirements.md), and
[`example.sverlin`](example.sverlin) are retained unchanged as design history.
They are useful for rationale, but this document is the authority when they
disagree with it.

The examples in [`examples/`](examples/) are complete body-only sources for this
target API. The current compiler does not yet accept them.

## Design in one page

The generated wrapper imports `Sverlin` as its only DSL facade; the body-only
authored source defines three independent builders:

```haskell
domain  :: Domain ()
program :: Program ()
render  :: Render ()
```

- **Domain** declares typed classifications, relations, steps, and finite
  seed-generated input.
- **Program** consumes that input to construct one immutable linear trace.
- **Render** independently selects trace objects and relations, then describes
  their text, hierarchy, appearance, connectors, and bounded affine layout.

The compiler rejects unsupported nonlinear or unbounded constraints. It never
falls back to nonlinear optimization.

The following small fragment shows the shared typed vocabulary. Marker types
such as `Values` and `Adjacent` provide stable compiler identities; they are not
runtime data or authored string keys.

```haskell
data Number
instance Traceable Number where
  type Payload Number = LInt Number

data Cell
instance Traceable Cell where
  type Payload Cell = LUnit Cell

data Values
data Cells
data Adjacent
data SearchInputRole
data Initialized
data Displayed

valueKind :: Kind Number
valueKind = kind @Values

cellKind :: Kind Cell
cellKind = kind @Cells

adjacent :: RelationKind Cell Cell
adjacent = orderedRelation @Adjacent

searchInput :: Input [Int]
searchInput = input @SearchInputRole

domain = do
  declareKind valueKind
  declareKind cellKind
  declareRelation adjacent
  declareSteps @'[Initialized, Displayed]
  variable searchInput (listOf 4 9 (between 0 99))

program = do
  values <- resolveInput searchInput
  let visit [] = pure ()
      visit (value : rest) = do
        valueBlock <- step @Initialized $ do
          Create pending <- create (LInt value)
          materialize valueKind pending
        valueBlock1 <- step @Displayed (pure valueBlock)
        Destroy <- destroy valueBlock1
        visit rest
  visit values

render = do
  always $ frame @Initialized
  sometimes $ frame @Displayed
  values <- select valueKind
  node values $ bindContent >>= fitText
```

Complete programs using longer-lived blocks, Slots, and relations are provided
in the example suite.

### Body-only source context

A `.sverlin` file contains declarations, helpers, `domain`, `program`, and
`render`; it does not write a module header or imports. The generated wrapper
supplies the linear Haskell prelude, including the qualified `Linear` name used
inside `Applicable1` and `Applicable2` implementations, and imports `Sverlin`
as the sole DSL facade. It must not expose `LinearTrace.*` implementation
modules to authored code.

Ordinary linear-prelude arithmetic remains unqualified for pure input and
Program calculations. Symbolic Render values deliberately have no ordinary
`Num`/`Fractional` instances and use the dotted affine operators instead. This
lets `index + 1` remain normal Haskell while `right cell .+. gap` is visibly a
solver expression.

The target profile supplies at least `DataKinds`, `GADTs`, `LinearTypes`,
`MultiParamTypeClasses`, `NoImplicitPrelude`, `OverloadedStrings`,
`RebindableSyntax`, `TypeApplications`, `TypeFamilies`, and
`TypeFamilyDependencies`, plus only the instance-related extensions needed by
the public classes. Remove `OverloadedLabels` when the old fact/query syntax
disappears. The private generated footer passes the three builders to the host
runner; `VisualTraceGraph`, `visualize`, and runner names are not in the
authored body contract.

## Public facade at a glance

This is the complete intended `Sverlin` export inventory. Constraints used only
to implement closed overloads are deliberately absent.

| Area | Public names |
|---|---|
| Builders | `Domain`, `Program`, `Render` |
| Domain identities | `Kind`, `kind`, `declareKind`, `RelationKind`, `orderedRelation`, `symmetricRelation`, `declareRelation`, `declareSteps`, `Input`, `input` |
| Input generation | `Generator`, Domain-form `variable`, `resolveInput`, `between`, `elementOf`, `weighted`, `listOf`, `shuffle` |
| Payloads | `Traceable(Payload)`, `LUnit(..)`, `LBool(..)`, `LInt(..)`, `LDouble(..)`, `LString(..)`, `LOperator(..)` |
| Operators | `Applicable1(Apply1Result, applyPayload1)`, `Applicable2(Apply2Result, applyPayload2)` |
| Linear resources | `Block`, `Pending`, `Slot`, `Create(..)`, `Use(..)`, `Copy(..)`, `Replace(..)`, `Apply1(..)`, `Apply2(..)`, `Destroy(..)`, `Seal(..)`, `Unseal(..)`, `Relate(..)` |
| Program operations | `create`, `copy`, `use`, `apply1`, `apply2`, `replace`, `destroy`, `materialize`, `seal`, `unseal`, `relate`, `step` |
| Presence and frames | `always`, `sometimes`, `frame` |
| Selection and hierarchy | `Selected`, `Relations`, `GeneratedNode`, `CanvasNode`, `select`, `node`, `self`, `canvas`, `within`, `relation`, `first`, `second` |
| Structure | `Ranking`, `FixedInt`, `asSequence`, `asTree`, `asDag`, `rankOf`, `asScalar`, `asText`, `payloadScalar`, `Arrangement(..)`, `arrange` |
| Text | `TextBuilder`, `ContentValue`, `text`, `literal`, `fragment`, `fragmentMany`, `bindContent`, `content`, `fitText` |
| Connectors | `ConnectorAnchor`, `AnchorPlacement(..)`, `anchor`, `Marker(..)`, `connector`, `startMarker`, `endMarker` |
| Numeric values | Render-form `variable`, `Coord`, `at`, `Span`, `by`, `Offset`, `shift`, `Scalar`, `num`, `VisualExpr`, `Unit`, `Angle`, `Vec2(..)`, `vec2`, `(.+.)`, `(.-.)`, `(.*.)`, `(./.)` |
| Geometry | `left`, `top`, `right`, `bottom`, `width`, `height`, `x`, `y`, `center`, `size`, `Insets`, `uniform`, `symmetric`, `edges`, `padding`, `margin`, `Axis(..)`, `ContentFit(..)`, `contentFit`, `Percent`, `percent`, `xAt`, `yAt`, `widthOf`, `heightOf`, `aspectRatio`, `separatedBy` |
| Choices and constraints | `Choice`, `choice`, `caseOf`, `VisualConstraint`, `ensure`, `(.<=.)`, `(.>=.)`, `(.==.)`, `VisualAlternative`, `alternative`, `oneOf` |
| Style operations | `style`, `withoutStyle`, `styleOf` |
| Numeric and paint fields | `Opacity`, `FontSize`, `Radius`, `StrokeWidth`, `Alpha`, `Hsl(..)`, `Color`, `Fill`, `Stroke` |
| Categorical fields | `BorderStyle(..)`, `FontKind(..)`, `FontFilter`, `fontKind`, `fontChoice`, `FontFamily(..)`, `FontWeight(..)`, `FontStyle(..)`, `TextAlign(..)` |

## Domain

### `Domain`

```haskell
data Domain a
```

`Domain` validates the complete vocabulary before input is sampled or Program
is run. Declarations return `()` because the reusable typed handles are ordinary
top-level values. The compiler records the marker type and source location for
diagnostics and stable identity.

One marker type names one declaration across kinds, relations, inputs, and
steps. Reusing it in another declaration category is diagnosed; this keeps
serialized identity independent of an extra string namespace.

### `Kind`

```haskell
data Kind tag

kind
  :: forall identity tag.
     (Typeable identity, Traceable tag)
  => Kind tag

declareKind :: Kind tag -> Domain ()
```

Every materialized block has exactly one declared `Kind`. Several kinds may
classify the same payload type, such as input numbers and result numbers.
Declaring a kind does not draw it; Render alone decides whether it has a visual
mapping.

Using an undeclared handle, declaring the same marker twice, or reusing one
marker with a different type is a source diagnostic.

### `RelationKind`

```haskell
data RelationKind source target

orderedRelation
  :: forall identity source target.
     (Typeable identity, Traceable source, Traceable target)
  => RelationKind source target

symmetricRelation
  :: forall identity node.
     (Typeable identity, Traceable node)
  => RelationKind node node

declareRelation :: RelationKind source target -> Domain ()
```

An ordered relation gives its endpoints distinct source and target roles;
reversing them changes the relation. `Adjacent`, `ParentOf`, `Contains`, and
`SourceOf` are typical ordered relations. A symmetric relation has one endpoint
role, so reversing its same-typed endpoints denotes the same pair.

Ordered does not mean visually left-to-right, and symmetric relations do not
gain a meaningful orientation from their stable output order.

### Typed steps

```haskell
declareSteps :: forall steps. StepList steps => Domain ()

declareSteps @'[StepA, StepB, StepC] :: Domain ()
```

Each list member is a nullary marker type with a `Typeable` identity. `StepList`
is a closed compiler constraint and is not exported for authored instances.
Program uses the same identities with `step`; Render uses them with `frame`,
`fragment`, and `fragmentMany`. Undeclared and duplicate step identities are
diagnosed.

Nested `step` calls express hierarchy directly. There is no public type-level
path-concatenation operator or separate branch declaration.

### `Input` and `Generator`

```haskell
data Input value
data Generator value

input
  :: forall identity value.
     (Typeable identity, Typeable value)
  => Input value

-- Domain specialization of the closed `variable` operation.
variable :: Input value -> Generator value -> Domain ()

resolveInput :: Input value -> Program value
```

An `Input` is a typed reference to one declared seed-generated value.
`resolveInput` returns the value sampled for the current scenario; repeated
calls return that same value. Render cannot resolve Program input directly.

Each declared input receives a deterministic sub-seed derived from the scenario
seed and its marker identity. Reordering declarations or adding an unrelated
input therefore does not perturb existing values. Inputs that must be
correlated are fields of one author-defined composite value generated by one
`Generator`, as the examples do.

`Generator` has library-provided `Functor`, `Applicative`, and `Monad`
instances. Custom valid structures are ordinary top-level functions returning
`Generator a`.

```haskell
between  :: Int -> Int -> Generator Int
elementOf :: value -> [value] -> Generator value
weighted :: (Int, Generator value) -> [(Int, Generator value)] -> Generator value
listOf   :: Int -> Int -> Generator value -> Generator [value]
shuffle  :: [value] -> Generator [value]
```

- `between low high` is inclusive and uniform.
- `elementOf first rest` is uniform over its non-empty positions.
- `weighted first rest` requires positive integer weights.
- `listOf minimum maximum item` selects the length uniformly, then samples
  items independently.
- `shuffle` produces a uniform permutation of the supplied positions.

Invalid bounds, impossible lengths, and non-positive weights are Domain
diagnostics. The leading argument makes `elementOf` and `weighted` non-empty by
construction. There is no public raw seed, predicate filter, retry loop, or
rejection-sampling operation. Valid graph, tree, and DAG generators must
construct valid values directly.

### `Traceable` and `Payload`

```haskell
class Traceable tag where
  type Payload tag = payload | payload -> tag

data LUnit tag     = LUnit
data LBool tag     = LBool Bool
data LInt tag      = LInt Int
data LDouble tag   = LDouble Double
data LString tag   = LString String
data LOperator tag = LOperator
```

`tag` is the semantic block type; `Payload tag` is its trusted linear carrier.
`Number` below is an author-defined example, not a built-in Sverlin type:

```haskell
data Number
instance Traceable Number where
  type Payload Number = LInt Number
```

Non-finite `LDouble` payloads are rejected. The compiler owns persistence and
display conversion of the supported wrappers. `Payload` is distinct from
`Kind`: it stores the value, while `Kind` classifies the block's role.

### `Applicable1` and `Applicable2`

```haskell
class Applicable1 operator argument where
  type Apply1Result operator argument
  applyPayload1
    :: Payload operator %1
    -> Payload argument %1
    -> Payload (Apply1Result operator argument)

class Applicable2 operator left right where
  type Apply2Result operator left right
  applyPayload2
    :: Payload operator %1
    -> Payload left %1
    -> Payload right %1
    -> Payload (Apply2Result operator left right)
```

These are the only public operator extension classes. Operators use a stateless
`LOperator tag`; changing parameters are ordinary trace operands.

```haskell
data Add
instance Traceable Add where
  type Payload Add = LOperator Add

instance Applicable2 Add Number Number where
  type Apply2Result Add Number Number = Number
  applyPayload2 LOperator (LInt leftValue) (LInt rightValue) =
    LInt (Linear.+ leftValue rightValue)
```

An operator receives an ordinary `Kind` like every other materialized block.
There is no separate `declareOperator` operation. Render may map that Kind just
like any other, or leave it invisible:

```haskell
addOperators <- select addOperatorKind
sometimes $ node addOperators $ do
  content (text "+")
  style @Radius (by 8)
```

## Program

### Linear resources and result patterns

```haskell
data Program a
data Block tag
data Pending tag
data Slot owner value

data Create tag = Create (Pending tag)
data Use tag where
  Use :: Payload tag %1 -> Use tag
data Copy tag = Copy (Block tag) (Pending tag)
data Replace tag = Replace (Pending tag)
data Apply1 operator argument = Apply1 (Pending (Apply1Result operator argument))
data Apply2 operator left right = Apply2 (Pending (Apply2Result operator left right))
data Destroy tag = Destroy
data Seal owner value = Seal (Block owner) (Slot owner value)
data Unseal owner value = Unseal (Block owner) (Block value)

data Relate source sourceValue target targetValue where
  Relate
    :: Slot source sourceValue %1
    -> Slot target targetValue %1
    -> Relate source sourceValue target targetValue
```

Constructors shown here are public pattern constructors. The resource
constructors themselves remain abstract. Every linear value must be passed to
another operation or consumed exactly once before Program finishes.

### Lifecycle operations

```haskell
create
  :: Payload tag %1
  -> Program (Create tag)

copy
  :: Block tag %1
  -> Program (Copy tag)

use
  :: Block tag %1
  -> Program (Use tag)

apply1
  :: Block operator %1
  -> Block argument %1
  -> Program (Apply1 operator argument)

apply2
  :: Block operator %1
  -> Block left %1
  -> Block right %1
  -> Program (Apply2 operator left right)

replace
  :: Block tag %1
  -> Pending tag %1
  -> Program (Replace tag)

destroy
  :: Block tag %1
  -> Program (Destroy tag)

materialize
  :: Kind tag
  -> Pending tag %1
  -> Program (Block tag)
```

`create`, `copy`, `apply1`, `apply2`, and `replace` produce an unfinished
`Pending` value that must be materialized exactly once. `copy` also reissues
the original identity. `use`, `apply*`, `replace`, and `destroy` end the input
block lifetime; `copy` does not. There is one materialization operation and no
unclassified block.

`Use` exposes the terminal payload directly, but the constructor field remains
linear: the author must pattern-match and consume it exactly once. The former
`OneUse` applicative wrapper existed to feed the removed generic `compute` flow;
its public constructor added no stronger guarantee and is not retained.

### `seal` and `unseal`

```haskell
seal
  :: Block owner %1
  -> Block value %1
  -> Program (Seal owner value)

unseal
  :: Block owner %1
  -> Slot owner value %1
  -> Program (Unseal owner value)
```

Each live owner has at most one Slot. `seal` hides the occupant and reissues the
same stable owner identity; `unseal` consumes the matching Slot and returns that
owner plus its current occupant. Unsealing, replacing an occupant, and resealing
does not change the owner identity.

### `relate`

```haskell
relate
  :: RelationKind source target
  -> Slot source sourceValue %1
  -> Slot target targetValue %1
  -> Program (Relate source sourceValue target targetValue)
```

`relate` records a relation between the two stable owners retained privately by
the Slot capabilities, then reissues both Slots. Occupant types need not match
the owner or each other. No public relation handle is returned.

The semantic relation becomes visible after the event, but its Render
constraints join the one fixed constraint system over the endpoint owners'
overlapping linear lifetimes. It survives unseal, occupant replacement, and
reseal. It ends when either endpoint owner reaches a terminal operation. A
successor owner does not inherit it automatically. There is no `unrelate`.

Here a terminal operation includes `use`, `apply1`, `apply2`, `replace`, or
`destroy` on an endpoint owner; `copy` alone is not a cut. Replacing an owner
and materializing its successor is therefore the explicit way to end old
relations and build a new relation set while preserving ordinary replacement
lineage for animation.

Adding the same relation kind twice between the same ordered pair, or either
orientation of the same symmetric pair, is a source diagnostic.

### `step`

```haskell
step
  :: forall name a.
     Typeable name
  => Program a %1
  -> Program a
```

`step @Name action` records the typed definition, runtime occurrence, nesting
path, and complete event span, then returns the action's result unchanged.
An occurrence completes after its body. For nested steps, the inner occurrence
therefore completes before the outer one. Repeated calls create distinct
occurrences of the same definition.

## Render

### `Render`, `always`, and `sometimes`

```haskell
data Render a

always    :: Render a -> Render a
sometimes :: Render a -> Render a
```

`always` introduces no random decision. `sometimes` creates one equal-weighted
include/omit decision at the current match scope. Opaque values returned from
the body retain that condition, and later components consuming them inherit it.
Nested conditions are conjoined. An ordinary pure Haskell value carries no
Render provenance, which is correct because using it does not depend on an
optional visual component.

Inside a selected node or relation rule the decision is independent per match.
At root it is shared once, except that `frame` deliberately expands its policy
over runtime step occurrences as described below. `always` cannot override an
absent inherited condition.

### `frame`

```haskell
frame
  :: forall name.
     Typeable name
  => Render ()
```

`frame @Name` exposes every runtime occurrence of that declared Program step.
`always $ frame @Name` includes every occurrence. `sometimes $ frame @Name`
creates an independent equal-weight include/omit choice for each occurrence,
not one shared choice for the definition. These geometry-neutral decisions are
sampled outside the affine configuration count. Every candidate occurrence is
still matched, structurally validated, and included in design-space
preparation; the presence bit only filters emitted presentation frames. An
omitted frame therefore cannot hide an invalid topology or change layout
feasibility.

Bare `frame @Name` is rejected so presence policy is explicit. At least one
declared `always` frame must execute in every generated scenario, giving every
view a shared baseline; otherwise compilation reports the step declarations
and scenario seed. Duplicate frame declarations for one step definition are
rejected. `frame` is valid only at the root of Render.

### Selection and nodes

```haskell
data Selected tag
data Relations source target
data GeneratedNode
data CanvasNode

select :: Kind tag -> Render (Selected tag)
select :: RelationKind source target -> Render (Relations source target)

node :: Selected tag -> Render () -> Render ()
node :: Render () -> Render (Selected GeneratedNode)

self   :: Render (Selected GeneratedNode)
canvas :: Selected CanvasNode
```

The overload dispatch behind `select` and `node` is closed and private.
Authors cannot add instances. `node selected body` creates one visual mapping
per current semantic match; `node body` creates one generated node in the
current scope.

Both forms may contain children. A selected Slot owner containing a selected
occupant maps only its current matching occupant, not every selected block.
Generated descendants instantiate once per outer match and inherit its
lifetime and presence.

`Selected` denotes semantic matches rather than one visual object, so it may be
mapped more than once. Every `node selected` occurrence has a distinct visual
identity. Inside its body the handle means that occurrence. Elsewhere the
compiler searches outward through generated-parent scopes and requires exactly
one nearest mapping; ambiguity reports all candidate source locations.

Presence conditions participate in that check. Mappings in mutually exclusive
`oneOf` or `caseOf` branches do not conflict merely because they map the same
selection; each feasible branch must still have exactly one context-local
mapping at a use site. A branch that intentionally shows the same selection
twice disambiguates the mappings with separate generated-parent scopes.

`self` is available only inside a generated-node body. A selected parent is
addressed through its captured `Selected` handle. `canvas` is the persistent
root geometry handle and is not emitted as a child.

### `within`

```haskell
within
  :: Relations owner member
  -> Selected owner
  -> Render a
  -> Render a
```

`within membership owners body` establishes a semantic membership scope; it
does not create a node, containment, or geometry. It is used inside the current
single owner match. Selections of `member` are restricted to targets related to
that owner, and homogeneous member relations are induced to edges whose two
endpoints are in the restricted set. Other selection types are unaffected.

The membership relation must be ordered owner-to-member. Scopes may nest.
Symmetric membership, an unbound or multi-valued current owner, and unrelated
heterogeneous traversal are diagnosed rather than silently broadened.

### Relation scopes

```haskell
relation
  :: Relations source target
  -> Render ()
  -> Render ()

first
  :: Relations source target
  -> Render (Selected source)

second
  :: Relations source target
  -> Render (Selected target)
```

`relation links body` evaluates once per active relation. `first links` and
`second links` retrieve that exact scope's typed endpoint mappings. They reject
use outside the matching relation scope or with another relation selection.
For an ordered relation, `first` is its source and `second` its target. For a
symmetric relation their stable order is reproducible but semantically
meaningless. A relation supplies spatial endpoints but draws nothing itself.

### Structural validation and rank

```haskell
data Ranking node
data FixedInt

asSequence :: Relations node node -> Selected node -> Render (Ranking node)
asTree     :: Relations node node -> Selected node -> Render (Ranking node)
asDag      :: Relations node node -> Selected node -> Render (Ranking node)

rankOf  :: Ranking node -> Render FixedInt
asScalar :: FixedInt -> Scalar
asText   :: FixedInt -> ContentValue
```

The `as*` functions validate the supplied selections without replacing or
filtering them. They require ordered relations and run for every declared
candidate frame occurrence where used, including an occurrence omitted from a
particular view by `sometimes`.

- A sequence is empty, a singleton, or one complete non-forking acyclic chain.
- A tree is non-empty, has one root, gives every other node one parent, and
  reaches every selected node.
- A DAG is acyclic and may have several roots or disconnected components.

Inside a matching `node` scope, `rankOf` is the sequence position, tree depth,
or longest-path DAG level. It is invalid in another node scope. No root, length,
node-count, edge-count, child-count, or subtree-size APIs are exposed.

`FixedInt` is calculated before numeric solving. `asScalar` makes it a constant
affine coefficient; `asText` formats it as deterministic decimal text.

### `payloadScalar`

```haskell
payloadScalar :: Selected tag -> Render Scalar
```

This closed operation is available only when `Payload tag` is `LInt tag` or
`LDouble tag`. In the current single match it returns a compiler-fixed,
unitless constant for that frame and lifetime. It is not a Program value,
predicate, category, or fresh solver variable.

```haskell
node values $ do
  value <- payloadScalar values
  height (minimumHeight .+. (heightUnit .*. value))
```

The product remains affine because `value` is fixed before lowering. Negative
values are valid; the author's final size constraints must still be feasible.

### Prepared arrangements

```haskell
data Arrangement node
  = ArrangeGrid Int (Vec2 Span)
  | ArrangeLayered (Relations node node) (Vec2 Span)
  | ArrangeRadial (Relations node node) (Vec2 Span)
  | ArrangeTree (Relations node node) (Vec2 Span)

arrange :: Arrangement node -> Selected node -> Render ()
```

An arrangement prepares one deterministic finite template, then emits only
relative affine constraints. `Vec2` gives the minimum horizontal and vertical
clear gaps; it is not an absolute pitch. The caller supplies hierarchy,
containment, and anchoring.

- Grid requires a positive fixed column count.
- Layered requires an ordered DAG and uses longest-path levels.
- Tree requires an ordered valid tree and deterministic tidy sibling order.
- Radial accepts ordered or symmetric graph relations and prepares fixed
  trigonometric coefficients before affine lowering.

There is no hidden sampled candidate. Authors put several arrangements in an
explicit `oneOf`, giving each authored alternative its normal weight. Invalid
topology, escaped endpoints, ambiguous visual mappings, unbounded output, and
infeasible prepared constraints are diagnostics. Row and column helpers are
unnecessary because ordinary adjacency constraints already express them.

## Text

### `TextBuilder` and `ContentValue`

```haskell
data TextBuilder a
type ContentValue = TextBuilder ()

text         :: String -> ContentValue
literal      :: String -> TextBuilder ()
fragment     :: forall step. Typeable step => String -> TextBuilder ()
fragmentMany :: forall steps. FragmentSteps steps => String -> TextBuilder ()

instance Semigroup ContentValue
instance Monoid ContentValue
instance IsString ContentValue
instance Functor TextBuilder
instance Applicative TextBuilder
instance Monad TextBuilder
```

`FragmentSteps` is a closed compiler constraint and is not exported for custom
instances. `fragmentMany @'[A, B] value` requires a non-empty declared step
list, removes duplicate identities, and associates the range with the logical
OR of those steps. Nested or overlapping associations are unioned.

`TextBuilder` resolves all literal, bound, and structural pieces into one
logical line before shaping. Concatenation inserts no whitespace. The compiler
then maps ranges through bidirectional reordering and HarfBuzz glyph clusters;
it never shapes each fragment independently.

```haskell
comparisonLine :: ContentValue
comparisonLine = do
  literal "if ("
  fragment @ReadElement "A[i]"
  fragmentMany @'[Compare, ReadTarget] " == "
  fragment @ReadTarget "target"
  literal ")"
```

The source must contain no newline. Multiple displayed lines are separate
ordinary nodes positioned through Render constraints. Different fonts within
one shaped line are not supported.

Indentation is therefore an ordinary relative layout decision, not spaces
inserted into a wrapped text node. This complete Render fragment creates three
separately shaped code lines while preserving whole-line highlighting:

```haskell
codeFont <- fontChoice (fontKind Monospace)
indent <- variable @Span
lineGap <- variable @Span
ensure $ indent .>=. by 16
ensure $ indent .<=. by 32
ensure $ lineGap .>=. by 4
ensure $ lineGap .<=. by 10

codeBlock <- node $ do
  contentFit Both Hug

  conditionLine <- node $ do
    content $ do
      literal "if "
      fragment @Compare "A[i] == target"
      literal ":"
    style @FontFamily codeFont

  returnLine <- node $ do
    current <- self
    content $ fragment @ReturnResult "return i"
    style @FontFamily codeFont
    ensure $ left current .==. (left conditionLine .+. indent)
    ensure $ top current .==. (bottom conditionLine .+. lineGap)

  continueLine <- node $ do
    current <- self
    content $ fragment @ContinueSearch "continue"
    style @FontFamily codeFont
    ensure $ left current .==. left conditionLine
    ensure $ top current .==. (bottom returnLine .+. lineGap)
```

`Compare`, `ReturnResult`, and `ContinueSearch` are example step marker types.
The leading offset is geometric, so changing fonts cannot destroy indentation
and the renderer still shapes each complete source line once.

### `bindContent`, `content`, and `fitText`

```haskell
bindContent :: Render ContentValue
content     :: ContentValue -> Render ()
fitText     :: ContentValue -> Render ()
```

`bindContent` exposes the current selected block's compiler-defined payload
text. Unit and operator blocks should normally use authored `text` because they
have no meaningful automatic spelling.

`content` shapes at an authored or theme-default fixed size and contributes
intrinsic line bounds to normal `Hug` geometry. `fitText` uses the current
bounded `FontSize`, or creates one in the documented theme range, and requires
the line to fit its content box. It samples any feasible size; it does not
maximize, wrap, hyphenate, or insert line breaks.

For `content`, the effective `FontSize` must be fixed before numeric solving; a
sampled size is diagnosed with guidance to use `fitText`. With no explicit
size, `content` uses the theme's fixed ordinary text size.

The baseline theme range for an implicit fitted size is 12 through 32 layout
units. The lower bound preserves the existing tested readability floor in
[`Typography.hs`](../src/LinearTrace/Visualization/Typography.hs); the finite
upper bound permits useful label variation without allowing text alone to set
an arbitrary canvas scale. A later theme may change both bounds, but they are
compiled into the design-space identity and output provenance rather than read
during materialization.

One node may declare content exactly once. Calling both operations, or calling
either twice, is a source diagnostic.

## Connectors

### `ConnectorAnchor` and `AnchorPlacement`

```haskell
data ConnectorAnchor

data AnchorPlacement
  = AtCenter
  | AtBoundary
  | AtTop
  | AtRight
  | AtBottom
  | AtLeft

anchor :: AnchorPlacement -> Selected node -> ConnectorAnchor
```

`AtBoundary` intersects the centre-to-centre line with a rectangular node
boundary. The side placements use edge centres. Coincident centres produce a
deterministic zero-length connector rather than a new layout choice.

### `Marker` and `connector`

```haskell
data Marker
  = NoMarker
  | ArrowMarker
  | CircleMarker
  | DiamondMarker

connector
  :: ConnectorAnchor
  -> ConnectorAnchor
  -> Render ()
  -> Render ()

startMarker :: Marker -> Render ()
endMarker   :: Marker -> Render ()
```

A connector is a straight, optional visual component. Its body accepts
`Stroke`, `StrokeWidth`, `Opacity`, and endpoint markers. Both markers default
to `NoMarker`. It is evaluated from solved node geometry and adds no layout
constraint.

Inside `relation`, it inherits that exact relation identity and lifetime.
Outside it, it joins two context-local node mappings. Presence is the
conjunction of both endpoints, the surrounding scope, and any explicit
`sometimes`. Curves, orthogonal routing, obstacle avoidance, and connector
labels are not in the baseline.

## Solver-backed values and finite choices

### `variable`

The Render form of the same closed operation creates a fresh numeric value:

```haskell
variable @Coord  :: Render Coord
variable @Span   :: Render Span
variable @Offset :: Render Offset
variable @Scalar :: Render Scalar
variable @Unit   :: Render Unit
variable @Angle  :: Render Angle
```

Every call receives a compiler-owned identity. Create a value outside a helper
when several uses should share it; create it inside when every invocation or
match should be independent. There is no string-named global variable.

### `Choice` and `choice`

```haskell
data Choice value

choice @BorderStyle :: Render (Choice BorderStyle)
choice @FontWeight  :: Render (Choice FontWeight)
choice @FontStyle   :: Render (Choice FontStyle)
choice @TextAlign   :: Render (Choice TextAlign)

caseOf :: Choice value -> (value -> Render ()) -> Render ()
```

`Choice value` is an abstract symbolic finite value. `choice` and `fontChoice`
create fresh random values; `styleOf` can project an already assigned
categorical field into the same type without creating another decision. The
compiler owns each finite domain and its stable serialization tokens; authors
cannot define a `ChoiceDomain` instance. `caseOf` is an exhaustive map from any
such value to complete Render blocks. Font-family choices use `fontChoice`, not
`choice @FontFamily`. Custom alternatives use `oneOf` rather than a reusable
custom category in the baseline.

## Layout and box model

The read/set overloads in this section use private closed dispatch. The
supporting classes are not exported as authored extension points.

### `Coord`

`Coord` is a non-negative absolute canvas coordinate.

```haskell
data Coord
at :: Double -> Coord
```

A fresh `variable @Coord` must acquire a finite upper bound through authored or
derived constraints. Adding a `Span` or `Offset` produces a coordinate;
subtracting coordinates produces an `Offset`.

### `Span`

`Span` is a non-negative length used for dimensions, gaps, text size, radius,
stroke, padding, and margin.

```haskell
data Span
by :: Double -> Span
```

Fresh spans require a finite upper bound. Subtracting spans produces an
`Offset`.

### `Offset`

`Offset` is a signed displacement.

```haskell
data Offset
shift :: Double -> Offset
```

It deliberately has no `asCoord` or `asSpan` reinterpretation helper.

### `Scalar`

`Scalar` is unitless and may scale an expression when the other factor is fixed
before numeric solving.

```haskell
data Scalar
num :: FixedNumeric value => Double -> value
```

`FixedNumeric` is private closed dispatch with instances for `Scalar`, `Unit`,
and `Angle`; it is not an authored class. `num` constructs the fixed role
inferred by its use and rejects non-finite or out-of-domain values. A sampled
Scalar must be finitely bounded.

### `VisualExpr`

```haskell
data VisualExpr role
```

`VisualExpr role` is a read-only affine expression returned by selected node
geometry or style access. Authors cannot construct or set it directly. The role
retains distinctions such as coordinate, span, unit, and angle.

### `Unit`

```haskell
data Unit
```

`Unit` is intrinsically bounded to the inclusive interval zero to one. It is
used for opacity, alpha, saturation, and lightness.

### `Angle`

```haskell
data Angle
```

`Angle` is the bounded HSL hue domain. The compiler gives the equivalent zero
and 360 degree boundary one canonical representation.

### `Vec2`

```haskell
data Vec2 a = Vec2 a a
vec2 :: a -> a -> Vec2 a
```

`Vec2` groups horizontal then vertical values. Equality and supported
arithmetic lower component by component.

### Geometry

```haskell
left, top, right, bottom :: geometry overloads
width, height           :: geometry overloads
x, y, center, size      :: geometry overloads
```

Each operation has only its documented setter and accessor forms:

| Operation | Current-node setter | Selected-node accessor |
|---|---|---|
| `left`, `top`, `right`, `bottom`, `x`, `y` | `Coord -> Render ()` | `Selected a -> VisualExpr Coord` |
| `width`, `height` | `Span -> Render ()` | `Selected a -> VisualExpr Span` |
| `center` | `Vec2 Coord -> Render ()` | `Selected a -> Vec2 (VisualExpr Coord)` |
| `size` | no setter | `Selected a -> Vec2 (VisualExpr Span)` |

```haskell
ensure $ left next .==. (right previous .+. gap)
ensure $ center group .==. center canvas
```

The uppercase overload classes are private and are not facade exports.

### `Insets`

```haskell
data Insets

uniform   :: Span -> Insets
symmetric :: Span -> Span -> Insets
edges     :: Span -> Span -> Span -> Span -> Insets

padding :: Insets -> Render ()
margin  :: Insets -> Render ()
```

`symmetric vertical horizontal` and `edges top right bottom left` use CSS order.
Padding contributes inside parent containment; margin contributes around a
child when its parent contains or hugs it.

### `Axis` and `ContentFit`

```haskell
data Axis = Horizontal | Vertical | Both
data ContentFit = Hug | Contain

contentFit :: Axis -> ContentFit -> Render ()
```

Both policies keep children and text within the padded parent. `Hug`
additionally makes relevant parent edges touch the extremal content;
`Contain` permits extra space. Both axes default to `Hug`. The policy is fixed,
not a solver choice. At the root, `Contain` therefore needs bounded canvas
width and height: bounded children provide a minimum but no maximum. A root
using `Hug` can instead derive bounded dimensions when all of its content is
bounded.

### `Percent`

```haskell
data Percent
percent :: Double -> Percent

xAt, yAt, widthOf, heightOf :: Percent -> Render ()
```

`Percent` validates a fixed value from zero to 100. `xAt` and `yAt` position the
current node centre in its parent content box; `widthOf` and `heightOf` size it
relative to the parent. A sampled percentage is not supported because
multiplying it by a sampled parent dimension would be bilinear.

### `aspectRatio`

```haskell
aspectRatio :: Double -> Double -> Render ()
```

This root-only operation gives the canvas a fixed positive horizontal-to-
vertical ratio. It does not bound the canvas scale, so a `Contain` canvas still
needs a bounded width or height (or both).

### `separatedBy`

```haskell
separatedBy
  :: Span
  -> Selected first
  -> Selected second
  -> VisualConstraint
```

It requires at least the supplied gap to the left, right, above, or below. The
union is lowered into disjoint compiler-created cells rather than four
overlapping, equally weighted choices. A fixed left, right, above, then below
precedence adds the negation of each earlier case to later cells; equality
boundaries belong to the first matching case. This tie-breaking changes no
positive-volume region and prevents a diagonally separated layout from being
counted twice.

### Affine arithmetic

```haskell
(.+.), (.-.), (.*.), (./.) :: affine overloads

infixl 6 .+., .-.
infixl 7 .*., ./.
```

The supporting dispatch is closed and private. Dotted operators distinguish
Render expressions from ordinary Haskell arithmetic in Domain and Program.
The inferred operand and result roles must form a supported combination, such
as coordinate plus span, coordinate minus coordinate, or fixed scalar times
span. Use `at`, `by`, `shift`, and `num` for fixed visual values.

Multiplication requires one factor fixed before numeric solving; division
requires a fixed non-zero denominator. Variable-by-variable products and
variable denominators are source diagnostics.

## Style authoring and colour

### Shared style operations

```haskell
style        :: forall field input. input -> Render ()
withoutStyle :: forall field. Render ()
styleOf      :: forall field node. Selected node -> StyleValue field
```

These are closed overloaded operations: the compiler supplies every supported
field/input pair and the result type represented by `StyleValue field`.
`StyleValue` and the dispatch classes are implementation details, not exported
names. A call to `style @Field` accepts the fixed value, numeric expression, or
matching `Choice` documented for that field. Unsupported pairs are type errors.

`withoutStyle @Field` suppresses an inherited or generated value.
`styleOf @Field selected` reads the final value as a symbolic expression and
requires the field to be present in every active branch. When presence itself
is conditional, constrain the driving choice instead.

Choices made outside a helper are shared by its callers; choices made inside
the helper are fresh each time:

```haskell
labelFont <- fontChoice (fontKind Proportional)
border <- choice @BorderStyle

let labelAppearance = do
      style @FontFamily labelFont
      style @BorderStyle border
      style @Radius (by 8)

node keys labelAppearance
node values labelAppearance
```

There is no public `NodeStyle`, style conversion class, `styleCase`, or
string-named style family.

### `Opacity`

```haskell
data Opacity
```

`style @Opacity` accepts `Unit`. It fades the complete node, including its
shape and text. `styleOf @Opacity` returns `VisualExpr Unit`.

```haskell
fade <- variable @Unit
node inactive $ style @Opacity fade
ensure $ fade .>=. num 0.35
ensure $ fade .<=. num 0.75
```

### `FontSize`

```haskell
data FontSize
```

`style @FontSize` accepts `Span`. A fixed value pins a line's size. A bounded
variable remains part of the affine sample when the node uses `fitText`.
`styleOf @FontSize` returns `VisualExpr Span`.

```haskell
labelSize <- variable @Span
node labels $ do
  style @FontSize labelSize
  bindContent >>= fitText
ensure $ labelSize .>=. by 14
ensure $ labelSize .<=. by 28
```

Every line sharing `labelSize` contributes a fit constraint, so the sampled
size must fit all of them. `fitText` samples a feasible size; it never searches
for the largest size.

### `Radius`

```haskell
data Radius
```

`style @Radius` accepts a non-negative `Span` for corner radius.
`styleOf @Radius` returns `VisualExpr Span`.

```haskell
radius <- variable @Span
node cells $ style @Radius radius
ensure $ radius .>=. by 6
ensure $ radius .<=. by 18
```

### `StrokeWidth`

```haskell
data StrokeWidth
```

`style @StrokeWidth` accepts a non-negative `Span`; it is visible when the
border style is not `BorderNone`. `styleOf @StrokeWidth` returns
`VisualExpr Span`.

```haskell
lineWidth <- variable @Span
node cells $ do
  style @BorderStyle BorderSolid
  style @StrokeWidth lineWidth
ensure $ lineWidth .>=. by 1
ensure $ lineWidth .<=. by 4
```

### `Alpha`

```haskell
data Alpha
```

`style @Alpha` accepts `Unit` and changes fill and stroke paint transparency.
Unlike `Opacity`, it does not fade text or the node as a composed group.
`styleOf @Alpha` returns `VisualExpr Unit`.

```haskell
paintAlpha <- variable @Unit
node visited $ style @Alpha paintAlpha
ensure $ paintAlpha .>=. num 0.55
ensure $ paintAlpha .<=. num 1
```

### `Hsl`

```haskell
data Hsl hue component = Hsl
  { hue        :: hue
  , saturation :: component
  , lightness  :: component
  }
```

`Hsl` is public so fixed and symbolic components can be combined. Hue uses an
`Angle`; saturation and lightness use `Unit`.

```haskell
accentHue <- variable @Angle
accentSaturation <- variable @Unit
let accent = Hsl accentHue accentSaturation (num 0.52) :: Color
ensure $ accentSaturation .>=. num 0.55
```

### `Color`

```haskell
type Color = Hsl Angle Unit
```

`Color` deliberately has no alpha component. Use the separate `Alpha` field.

```haskell
let quietBlue = Hsl (num 215) (num 0.35) (num 0.62) :: Color
```

### `Fill`

```haskell
data Fill
```

`style @Fill` accepts `Color`. `styleOf @Fill` returns
`Hsl (VisualExpr Angle) (VisualExpr Unit)`, allowing component constraints.

```haskell
fillLightness <- variable @Unit
node cells $ style @Fill (Hsl (num 210) (num 0.70) fillLightness)
ensure $ fillLightness .>=. num 0.35
ensure $ fillLightness .<=. num 0.68
```

### `Stroke`

```haskell
data Stroke
```

`style @Stroke` accepts `Color`. `styleOf @Stroke` returns
`Hsl (VisualExpr Angle) (VisualExpr Unit)`. Stroke may be inherited,
constrained, or suppressed with `withoutStyle @Stroke`.

```haskell
node current $ do
  style @Stroke (Hsl (num 220) (num 0.55) (num 0.30))
  style @BorderStyle BorderSolid
ensure $ saturation (styleOf @Stroke current) .>=. num 0.40
```

### `BorderStyle`

```haskell
data BorderStyle
  = BorderNone
  | BorderSolid
  | BorderDashed
  | BorderDotted
```

`style @BorderStyle` accepts a fixed `BorderStyle` or
`Choice BorderStyle`. `styleOf @BorderStyle` returns `Choice BorderStyle` for
that selected mapping; it does not create a new random value. `BorderNone`
suppresses visible stroke even when colour and width are present.
`BorderDouble` is absent because the current renderer gives it no distinct
result; retaining it would give solid borders extra random weight.

### `FontKind`, `FontFilter`, and `fontChoice`

```haskell
data FontKind = Monospace | Proportional
data FontFilter

fontKind   :: FontKind -> FontFilter
fontChoice :: FontFilter -> Render (Choice FontFamily)
```

`FontFilter` is abstract. `fontKind` uses catalog metadata rather than guessing
from family names. `fontChoice` diagnoses an empty result and is the only way
to create a font-family choice. It returns unique concrete families, so aliases
cannot give one face extra weight.

```haskell
codeFont <- fontChoice (fontKind Monospace)
proseFont <- fontChoice (fontKind Proportional)
node codeLines $ style @FontFamily codeFont
node explanations $ style @FontFamily proseFont
```

Each call creates an authored choice. Reuse its result to share a family.
Different fonts cannot be assigned to fragments of one shaped line; use
separate text nodes for code and explanation lines.

### `FontFamily`

```haskell
data FontFamily
  = FontInter
  | FontSourceSans3
  | FontAtkinsonHyperlegibleNext
  | FontSpaceGrotesk
  | FontSourceSerif4
  | FontLiterata
  | FontJetBrainsMonoNL
  | FontIBMPlexMono
```

`style @FontFamily` accepts one concrete family or a value returned by
`fontChoice`. `styleOf @FontFamily` returns `Choice FontFamily` for that
selected mapping. Generic aliases such as system, serif, and monospace are not
separate public families.

### `FontWeight`

```haskell
data FontWeight
  = FontWeightNormal
  | FontWeightBold
  | FontWeightBolder
  | FontWeightLighter
  | FontWeightNumber Int
```

`style @FontWeight` accepts a fixed value or `Choice FontWeight`.
`FontWeightNumber` accepts supported hundreds from 100 through 900. Relative
weights are resolved against inheritance before shaping. Unsupported faces
invalidate that typography branch rather than being synthesized. Concrete
duplicates are removed before weighting. `styleOf @FontWeight` returns the
selected mapping's `Choice FontWeight` without adding a random decision.

The finite domain of `choice @FontWeight` is the nine canonical
`FontWeightNumber` values from 100 through 900, reduced to real weights
supported by the selected family. `FontWeightNormal`, `FontWeightBold`,
`FontWeightBolder`, and `FontWeightLighter` are fixed authoring conveniences;
they resolve to a canonical number and never add duplicate random candidates.
Use `oneOf` when the intended random set is a smaller named subset such as only
normal or bold.

### `FontStyle`

```haskell
data FontStyle = FontStyleNormal | FontStyleItalic
```

`style @FontStyle` accepts a fixed value or `Choice FontStyle`.
`FontStyleOblique` is absent because the current font resolver aliases it to
italic. A family without the selected real face invalidates that branch.
`styleOf @FontStyle` returns the selected mapping's `Choice FontStyle`.

### `TextAlign`

```haskell
data TextAlign = TextAlignLeft | TextAlignCenter | TextAlignRight
```

`style @TextAlign` accepts a fixed value or `Choice TextAlign`. Alignment is a
post-shaping affine offset within the content box. Single-line justification is
absent because it is not distinct without wrapping or another spacing model.
`styleOf @TextAlign` returns the selected mapping's `Choice TextAlign`.

## Constraints and authored alternatives

### `VisualConstraint` and comparison operators

```haskell
data VisualConstraint

ensure :: VisualConstraint -> Render ()

(.<=.) :: Comparable a b => a -> b -> VisualConstraint
(.>=.) :: Comparable a b => a -> b -> VisualConstraint
(.==.) :: Comparable a b => a -> b -> VisualConstraint

infix 4 .<=., .>=., .==.
```

`Comparable` above denotes private closed dispatch; it is not an authored
class. Equality and inequalities accept only compatible affine geometry,
style, vector, or categorical expressions. A diagnostic names the source
expression and unsupported operation before solving.

```haskell
gap <- variable @Span
ensure $ gap .>=. by 12
ensure $ gap .<=. by 36
ensure $ left next .==. (right previous .+. gap)
```

### `VisualAlternative`, `alternative`, and `oneOf`

```haskell
data VisualAlternative

alternative :: String -> Render () -> VisualAlternative
oneOf :: String -> VisualAlternative -> [VisualAlternative] -> Render ()
```

`oneOf` creates one authored finite choice with a diagnostic name and a
non-empty set of labelled alternatives. Labels must be unique within it. Each
feasible alternative has equal authored weight in the baseline. A body may
contain complete nodes, styles, connectors, and constraints, not just one
equation.

The strings are human-facing diagnostic and provenance labels. Choice identity
comes from the declaration and lexical occurrence, so reusing a label elsewhere
does not couple choices or recreate a string-named `global`.

```haskell
oneOf "layout"
  (alternative "row" $ ensure $ left second .==. (right first .+. gap))
  [ alternative "column" $ ensure $ top second .==. (bottom first .+. gap)
  ]
```

`caseOf` maps a previously created typed choice; `oneOf` creates a new choice.
Compiler-created cases needed to lower `separatedBy` or other exact
piecewise-affine expressions are not authored alternatives and receive no
extra design weight. There are no bridge operators or soft `encourage` API.

## Scenario seeds, frame presence, and playback

The compiler service accepts an ordered non-empty batch of integer seeds. Call
its first element `s1` and each element at position `i` `si`.

- `s1` is the **scenario seed**. Domain input is generated once and Program
  constructs one shared trace for the whole batch.
- Every `si`, including `s1`, is a **view seed**. It controls Render choices,
  numeric sampling, and independent `sometimes` decisions.
- A singleton batch uses its one seed for both roles.
- Output records both seeds and a `scenarioKey`. Authored source cannot read
  them.

This permits several presentations of exactly the same input and trace while
still allowing a `sometimes $ frame @Compare` to appear in one presentation
and be absent in another. It does not permit comparing different generated
inputs as if they were the same execution.

Each runtime `step` occurrence receives a stable hierarchical key from its
typed definition, nested runtime path, and trace order. Playback of views from
one scenario uses the ordered union of their included keys. If a view omitted
an inner frame, it holds its most recent included frame until the next shared
outer occurrence. This keeps the presentations synchronized at shared
hierarchical points without manufacturing a missing frame.

`scenarioKey` is a hash of the compiler/schema version, authored-source
identity, scenario seed, deterministic Domain generation transcript, and
canonical Program trace hash. The transcript records generator decisions, so
arbitrary author-defined input values need no new public serialization class.
Only views with exactly the same key may align. Different seeds, source,
generated inputs, or traces therefore have separate playback contexts even
when step names or labels happen to match. The current equal-step-signature
activation check must become exact scenario-key compatibility plus hierarchical
occurrence mapping.

For the convenience form `--seed s --count n`, the intended batch has scenario
seed `s` and view seeds `[s .. s + n - 1]`. Its second output is not required to
equal a separate singleton compilation at seed `s + 1`, because that singleton
has a different scenario input. An initial implementation may rerun the same
scenario privately for each view if it verifies identical trace identity;
sharing the Domain and Program result is the eventual efficient path.

## Compiled affine design space

### Meaning and sampling order

Render lowers to a bounded finite collection of convex regions described by
affine equalities and inequalities. A convex region is simply a set where the
straight line between any two valid layouts is also valid. Unsupported
nonlinear expressions, unbounded variables, and empty designs are source-level
diagnostics. There is no nonlinear optimization fallback.

The compiler preserves two different reasons for branching:

1. **Authored decisions** are intended design variation: a `oneOf`, font,
   border, alignment, or `sometimes` component. Feasible alternatives receive
   their declared weight (equal by default).
2. **Algebraic partitions** are exact bookkeeping, such as the four possible
   directions in `separatedBy`. Splitting one numeric region must not make that
   design more likely. Partition cells are selected according to their numeric
   measure within the already selected authored assignment.

For each view seed, the compiler first samples a feasible authored assignment,
then selects an algebraic cell without branch-count bias, then samples a point
approximately uniformly inside that cell. Geometry-neutral choices and frame
presence are sampled separately so they do not multiply affine configurations.

Equal authored alternatives remain equal after infeasible alternatives are
removed. Nested choices apply equality locally at each reached choice. This is
the baseline distribution; a future weighted visual choice must be explicit
rather than inferred from how many compiler cases an alternative creates.

Regions of different affine dimension cannot be compared by ordinary volume.
The compiler treats an authored equality that deliberately fixes a dimension
as part of that alternative's weight, then compares algebraic cells only within
the same reduced affine space. If compiler-created cells for one authored
assignment unexpectedly have different dimensions, preparation rejects the
ambiguous measure rather than silently choosing a policy.

### Typography stays affine

For each concrete font family, face, weight, style, source line, direction, and
shaping configuration, shape once at the font's units-per-em scale. Glyph
advances and line bounds become constants for that branch. A fitted
`fontSize`, box dimensions, insets, and the prepared `lineWidthEm` and
`lineHeightEm` coefficients then add affine constraints:

```haskell
ensure $ fontSize .>=. minimumFontSize
ensure $ fontSize .<=. maximumFontSize
ensure $ (horizontalInsets .+. (lineWidthEm .*. fontSize)) .<=. boxWidth
ensure $ (verticalInsets .+. (lineHeightEm .*. fontSize)) .<=. boxHeight
```

The two metric coefficients are fixed before solving, so their products with
`fontSize` are affine. Font family and any metric-changing face are discrete
authored branches; font size and box geometry remain jointly variable in each
region. The compiler checks shaping
and minimum-size feasibility before selecting a font. Missing glyphs or faces
remove only that branch, and become a source diagnostic if none remain.

There are no automatic wrapping branches. Split intended lines into separate
nodes. The renderer shapes every `TextBuilder` line as one string so kerning,
ligatures, bidirectional text, and fragment-to-glyph highlighting remain
correct.

### Preparation, caching, and retries

Preparing a region means normalizing constraints, reducing exact equalities,
proving feasibility, finding one interior starting point, and caching the
matrix data used for sampling. It does not cache a sampled layout. Ten view
seeds reuse the deterministic preparation but each still choose decisions and
generate a new numeric point.

Small choice spaces prepare all feasible authored assignments. Large spaces
keep guarded constraints in a discrete feasibility model. Visit reached
authored choices in stable lexical order. For each alternative, ask whether at
least one feasible completion exists; discard only alternatives with none, then
sample the survivors using that choice's local declared weights. Condition the
model on the result and continue. This implements the local weighting rule
without enumerating or counting complete assignments, then prepares the
selected affine region lazily. A randomized MIP objective may answer
feasibility queries, but choosing its preferred complete assignment is not a
random sampler and must not stand in for this process.

Feasibility is deterministic and independent of whether one random walk
succeeds. A prepared valid region may use a small, documented number of
derived-seed attempts for a numeric backend failure, preserving each attempt in
provenance. Exhausting those attempts reports a numeric sampling error, not
infeasibility and not permission to invoke another optimizer. Concrete limits
must be set from application-shaped benchmarks and documented beside their
configuration.

### Existing solver components to retain

The implementation should evolve the current top-level
[`Solver`](../src/Solver.hs) facade and its internals rather than introduce a
second solver stack:

- retain affine classification and representation from
  [`Solver.Affine`](../src/Solver/Affine.hs);
- retain categorical compilation, but distinguish authored decisions from
  compiler algebraic partitions;
- retain [`Solver.Highs`](../src/Solver/Highs.hs) for deterministic linear
  feasibility and conditioning;
- retain normalization, equality reduction, hit-and-run, and volume machinery
  from [`Solver.Sample`](../src/Solver/Sample.hs), correcting its weighting and
  reuse boundaries; and
- extend [`CompiledDesignSpace`](../src/Solver/DesignSpace.hs) so deterministic
  normalized, equality-reduced region data can be reused across view seeds.

The existing `containers` dependency and `Data.Graph`, `Data.Map`, and
`Data.Set` are sufficient for sequence, tree, and DAG validation. Do not add a
graph package merely to hold the same nodes and edges. No new Haskell solver
library is required for this phase.

Current behavior that must change includes random-MIP assignment posing as
uniform choice, repeated preparation for every sample, a seed-zero sample used
as a feasibility test, string solver identities, and the penalty/L-BFGS-B
fallback. Remove the old optimizer path and its dependencies only after the
affine path has equivalent characterization coverage.

## Internal compiler and renderer shape

### One private `RenderPlan`

Lower authored Render code once into a private `RenderPlan` that owns semantic
matches, generated hierarchy, presence conditions, style cascade, text lines,
connectors, prepared graph templates, affine constraints, and source
provenance. The current Box, Style, Build, and typography algorithms are useful
implementation donors. Some intermediate types are exported by today's legacy
modules; they must not remain public APIs in the target facade.

Collapse query matching, `View.Access`, `View.Template`, `StyleProfile`, and
the authored graph/solve surfaces after their retained behavior has moved into
that plan. Do not keep empty forwarding layers. Preserve lexical match scope,
stable visual identity, parent containment, and independent mappings of the
same semantic selection.

Typography preparation happens before numeric solving for every feasible
metric branch. Remove the current solve, shape/max-fit, pin, and re-solve flow:
prepared glyph coefficients and fit inequalities enter the same final affine
sample as box geometry.

The first migration should follow this ownership map:

| Current source | Target ownership | Action |
|---|---|---|
| [`LinearTrace.Choreography`](../src/LinearTrace/Choreography.hs) | `Sverlin` | Replace the authored facade; retain a compatibility shim only for current fixtures during cutover. |
| [`LinearTrace.Core.Internal`](../src/LinearTrace/Core/Internal.hs) | private Domain/Program trace engine | Preserve linear resources, provenance, allocation, and event ordering; replace facts and string labels at its boundary. |
| `LinearTrace.Choreography.Match`, `Graph`, and `View.Access` | private `RenderPlan` matching/projection | Merge semantic scope and identity logic after characterization tests. |
| `View.Template`, `Build`, and `StyleProfile` | private `RenderPlan` lowering | Reuse useful algorithms, then remove public/authored template and automatic-profile layers. |
| `View.Box`, `View.Style`, and `View.Primitives` | private affine box/style representation | Retain typed geometry and cascade behavior; stop exposing accumulated implementation records. |
| [`Visualization.FontCatalog`](../src/LinearTrace/Visualization/FontCatalog.hs), `HarfBuzz`, and [`Typography`](../src/LinearTrace/Visualization/Typography.hs) | typography branch preparation | Add font-kind metadata and whole-line branch caching; remove maximum-fit and pinned second solve. |
| [`Visualization.CodeHighlight`](../src/LinearTrace/Visualization/CodeHighlight.hs) | none | Remove the code-special Skylighting path after step fragments replace it; then remove `skylighting-core` when Typography no longer imports it. |
| `Visualization.Compile`, `IR`, `Resource`, and `Target` | versioned output pipeline | Retain resource and serialization behavior while adding scenario, fragment, relation, and connector provenance. |
| [`Solver.DesignSpace`](../src/Solver/DesignSpace.hs) and other `Solver.*` modules | stable top-level `Solver` facade | Adapt the existing affine pipeline; remove the optimizer path only after equivalent coverage. |

This map intentionally unifies overlapping internal representations. It does
not imply one large module: boundaries should follow ownership of validated
state, not historical public module names.

### Trace, projection, and identity

Compile Domain declarations into a typed registry, generate finite input, and
run Program as an immutable event stream. Nested step occurrences retain typed
definition identity and runtime paths. Relations are trace events attached to
stable slot owners, not current occupants.

A stable visual projection identity includes the Render declaration, semantic
scope, block or owner identity, and generated occurrence path. It must not use
authored strings or incidental map order. Relations project to stable endpoint
owner mappings and survive occupant changes until either owner lifetime ends.

### IR and browser contract

The generated IR needs `scenarioKey`, scenario and view seeds, hierarchical
step occurrence keys, conditional frame presence, relation and connector
identities, shaped fragment cluster metadata, stable transition provenance,
and deterministic ordering. Connectors render behind their endpoint nodes. Add
fields to the current version where old readers can safely ignore them;
otherwise introduce an explicit version transition and keep decoding existing
stored artifacts.

Preserve content/resource hashes, forward and reverse transition identity, and
whole-line shaping data. Fragment metadata must identify glyph clusters rather
than assume one source character equals one glyph.

The application-side migration is small but cannot be skipped:

- [`compile/app/Main.hs`](../app/Main.hs) already builds one `VisualTraceGraph`
  and one `ViewGraph` before solving several seeds. Preserve that shared-graph
  batch, but give its first seed the explicit scenario role and pass the full
  ordered view-seed batch into the new host.
- [`src/lib/server/compiler/index.ts`](../../src/lib/server/compiler/index.ts)
  currently implements a batch by invoking the single-seed compiler repeatedly.
  Change that boundary to one batch invocation, or temporarily pass the same
  explicit scenario seed to each invocation and verify identical `scenarioKey`
  values.
- [`src/lib/server/projects/service.ts`](../../src/lib/server/projects/service.ts)
  currently accepts synchronized presentations by hashing flat step labels.
  Store and compare `scenarioKey`, then retain hierarchical occurrence keys
  instead of requiring identical optional-frame lists.
- Regenerate the shared IR types under
  [`src/lib/shared/visualization/`](../../src/lib/shared/visualization/) and
  update client playback under
  [`src/lib/client/visualization/`](../../src/lib/client/visualization/) to use
  the ordered union and hold rule. Persisted project events remain immutable;
  compatibility belongs in the IR decoder/projection rather than by rewriting
  old events.

### Host and package boundary

The generated wrapper imports `Sverlin` as its only DSL module, alongside the
fixed language prelude described above. A private host module combines the
validated `domain`, completed `program`, compiled `render`, and service seeds.
The compiler remains one service accepting `.sverlin` content plus a non-empty
seed batch; Haskell implementation types do not cross into the SvelteKit
server.

Expose only:

- the authored `Sverlin` facade;
- a narrow compiler/runner boundary used by the executable;
- the intentionally stable top-level `Solver` facade; and
- an IR module only if another package deliberately consumes that Haskell type.

Historical modules are behavioral donors, not compatibility commitments. Audit
callers and characterize behavior before collapsing them. In particular inspect
commits `970907d` (slot owner projection), `52f842b` and `a5084ba` (render
identity and transitions), `9efb493` (typography/resources), `0ff53cc`
(template and API-index boundary), and `03c4e14` (archived slots, connectors,
and SVG transition edge cases).

## Deliberately absent from `Sverlin`

The target facade does not expose:

- old builder/facade names, compiler runners, graph builders, solver entrypoints,
  or view statistics;
- free facts, queries, atoms, integer bindings, payload predicates, query-era
  selections, or alternate materialization calls;
- `SelectionBinding`, `Variable`, `Bound`, `NodeBinding`, `NodeStyle`, or the
  closed overload classes behind selection, nodes, geometry, styles, and
  choices;
- public `Relation`, relation handles, `Unrelate`, `unrelate`, graph aggregate
  views/counts, node-pair traversal, or separate endpoint-pair callback
  helpers;
- `LinearPayload`, generic payload unpack/rebuild helpers, payload metadata,
  `OneUse`, the old generic compute flow, `CoreOperator`, operator persistence,
  or parameter-carrying operator values;
- wrapped/code-special text, text wrapping, whitespace policy, z-index, or
  per-fragment font shaping;
- `ChoiceDomain`, custom choice tokens, `styleChoice`, `styleCase`,
  `styleFamily`, `variableFrom`, string-named `global`, or authored seed access;
- `Free`, bulk `Bounds`, `bounds`, `asCoord`, `asSpan`, `sat`, bridge operators,
  ordinary arithmetic on symbolic visual values, or `encourage`;
- generic font aliases, oblique-as-italic, `BorderDouble`, or single-line
  `TextAlignJustify`; or
- nonlinear constraints, nonlinear optimizer fallback, and soft objectives.

## Implementation phases

### Phase 1: freeze and exercise the contract

Treat this document and the ten sources in [`examples/`](examples/) as the
candidate contract. Add parser/typecheck fixtures from the examples as each API
slice lands. Keep [`API_issues.md`](API_issues.md) limited to demonstrated gaps
that cannot be expressed by composing this facade.

### Phase 2: typed Domain and Program

Introduce the `Sverlin` facade and private host. Implement typed declarations,
constructive seed input, one materialization path, typed steps, stable Slots,
and relation events. The old fact/query representation may temporarily lower
these features internally, but authored source cannot name it.

### Phase 3: one Render plan

Implement typed selections and relations, generated hierarchy, presence
provenance, structural rankings, text builders, connectors, prepared
arrangements, closed style fields, and affine constraints in one private plan.
Characterize projection identity, containment, relation lifetime, and reverse
transitions before removing their legacy owners.

### Phase 4: bounded piecewise-affine compilation

Prepare typography branches before solving; distinguish authored decisions
from algebraic partitions; add deterministic feasibility, prepared-region
reuse, and approximately uniform region sampling. Remove pinned typography,
penalty objectives, nonlinear fallback, and obsolete optimizer dependencies
after the affine path passes its fixtures and benchmarks.

### Phase 5: IR, playback, and package cleanup

Emit the new provenance and hierarchical frame data, update the browser to
align only views from one scenario, preserve old artifact decoding, then narrow
exposed Haskell modules and remove empty legacy layers.

## Verification gates

Before treating a phase as complete:

- every example must parse and typecheck against `Sverlin`; later phases must
  compile it for several scenario and view seeds;
- for one fixed scenario seed and fixed view-seed list, each view's result must
  not depend on cache warmth, view processing or scheduling order, map order,
  or process reuse; request order itself remains meaningful because its first
  seed selects the scenario;
- tests must cover linear ownership, exactly-once pending materialization,
  Slot owner identity, late relation creation, duplicate relations, structural
  diagnostics, optional dependency propagation, whole-line shaping, and
  fragment cluster mapping;
- solver fixtures must distinguish authored weighting from algebraic splitting,
  exercise lower-dimensional alternatives, reject unsupported/unbounded input,
  and show that repeated view seeds reuse preparation without reusing samples;
- IR tests must cover old artifact decoding, deterministic ordering, connector
  lifetime, reverse playback, same-key hierarchical frame alignment, and
  rejection of alignment for changed source, input transcript, or trace even
  when step labels match;
- application-shaped benchmarks must report construction, feasibility,
  preparation, sampling, typography, and materialization separately before any
  numeric budget is fixed; and
- the public module/export audit must show every `Sverlin` name documented and
  every implementation class or legacy module absent from authored imports.

## Example suite

| Source | Main pressure on the API |
|---|---|
| [`LinearSearch.sverlin`](examples/LinearSearch.sverlin) | array membership, optional labels, comparison fragments |
| [`BinarySearch.sverlin`](examples/BinarySearch.sverlin) | narrowing ranges, midpoint relations, optional detail frames |
| [`BubbleSort.sverlin`](examples/BubbleSort.sverlin) | stable cells, occupant replacement, adjacency, swap steps |
| [`MergeSort.sverlin`](examples/MergeSort.sverlin) | nested steps, split/merge structures, alternate layouts |
| [`HeapSort.sverlin`](examples/HeapSort.sverlin) | one trace shown as an array, a tree, or both |
| [`LinkedListReversal.sverlin`](examples/LinkedListReversal.sverlin) | persistent nodes, changing directed links, connectors |
| [`BreadthFirstSearch.sverlin`](examples/BreadthFirstSearch.sverlin) | general graph arrangement, queue membership, visit levels |
| [`DijkstraShortestPath.sverlin`](examples/DijkstraShortestPath.sverlin) | weighted semantic values and directed edge visuals |
| [`TopologicalSort.sverlin`](examples/TopologicalSort.sverlin) | DAG validation, rank-based layers, optional order view |
| [`LongestCommonSubsequence.sverlin`](examples/LongestCommonSubsequence.sverlin) | two input sequences, a dynamic-programming grid, code text |

These are target-design fixtures, not current compiler demonstrations. Their
comments explain composition and call out any genuinely missing operation in
[`API_issues.md`](API_issues.md) rather than inventing an unlisted public name.
