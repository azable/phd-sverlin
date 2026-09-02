# Final Sverlin API contract and implementation notes

This document is the implemented authored-source contract for the Sverlin
overhaul. The older
[`API_plan.md`](API_plan.md), [`API_plan_list.md`](API_plan_list.md),
[`API_requirements.md`](API_requirements.md), and
[`example.sverlin`](example.sverlin) are retained unchanged as design history.
They are useful for rationale, but this document is the authority when they
disagree with it.

The examples in [`examples/`](examples/) are complete body-only sources for this
API. They remain contract and verification fixtures; this document does not by
itself assert that the end-to-end verification gates below have passed.

The semantics and safety rules below are firmer than the exact Haskell
encoding. If implementation reveals a substantially simpler signature,
constructor shape, or closed-overload encoding with equivalent authored
behaviour, it may be proposed as a replacement. The proposal must show the old
and new spelling, explain why the guarantees are unchanged, and identify any
trade-off; do not silently drift the facade or examples. A material semantic
change still needs a design decision rather than being treated as syntax.

## Design in one page

The generated wrapper imports `Sverlin` as its only DSL facade; the body-only
authored source defines three independent builders:

```haskell
domain  :: Domain initial
program :: initial %1 -> Program ()
render  :: Render ()
```

- **Domain** declares typed vocabulary, samples finite input, and constructs
  the initial linear resources.
- **Program** consumes those resources exactly once to complete one immutable
  linear trace.
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

data Values
data SearchInputRole
data Initialized
data Displayed

valueKind :: Kind Number
valueKind = kind @Values

data Initial where
  Initial :: Block Number %1 -> Initial

domain :: Domain Initial
domain = do
  declareKind valueKind
  declareSteps @'[Initialized, Displayed]
  value <- variable @SearchInputRole (between 0 99)
  Create pending <- create (LInt value)
  block <- materialize valueKind pending
  pure (Initial block)

program :: Initial %1 -> Program ()
program (Initial value) = do
  value1 <- step @Initialized (pure value)
  value2 <- step @Displayed (pure value1)
  Destroy <- destroy value2
  pure ()

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
supplies a curated linear Haskell prelude, including the qualified `Linear`
arithmetic used inside `Applicable1` and `Applicable2` implementations, and
imports `Sverlin` as the sole DSL facade. It must not expose `LinearTrace.*`
implementation modules to authored code.

The authored profile does not expose `Ur`, `move`, `dup2`, `Consumable`,
`Dupable`, `Movable`, or another operation that changes a linear binding into
an unrestricted one. Program duplication happens only through traced lifecycle
operations such as `copy`. The private compiler may use unrestricted storage
internally to persist snapshots; that representation never crosses the
authored facade.

Ordinary arithmetic remains available in Generator. Program uses the linear
prelude, so any runtime operand received through a linear value must still be
consumed according to its multiplicity. Symbolic Render values deliberately
have no ordinary `Num`/`Fractional` instances and use the dotted affine
operators instead. This lets generator-side `index + 1` remain normal Haskell
while `right cell .+. gap` is visibly a solver expression.

The generated prelude also supplies one closed `do`-notation dispatch. Domain
and Program bind results linearly; Generator, Render, and TextBuilder use
unrestricted builder values. A value crosses from Generator into Domain
through Domain-form `variable`, after which it must be consumed exactly once
while constructing the initial resources. This is ordinary
`RebindableSyntax` type-class dispatch checked by GHC, not a source-rewriting
pass. The dispatch class and its instances are fixed compiler support, not
authored APIs.

The public builder spellings have these concrete call shapes. Here `B` means
either builder named in the comment; it is not a public type or class:

```haskell
-- B is Domain or Program.
(>>=)  :: B a %1 -> (a %1 -> B b) %1 -> B b
(>>)   :: B () %1 -> B b %1 -> B b
pure   :: a %1 -> B a
return :: a %1 -> B a
fail   :: String -> B a

-- B is Generator, Render, or TextBuilder.
(>>=)  :: B a -> (a -> B b) -> B b
(>>)   :: B a -> B b -> B b
pure   :: a -> B a
return :: a -> B a
fail   :: String -> B a
```

The authored profile supplies at least `DataKinds`, `GADTs`, `LinearTypes`,
`MultiParamTypeClasses`, `NoImplicitPrelude`, `OverloadedStrings`,
`RebindableSyntax`, `TypeApplications`, `TypeFamilies`, and
`TypeFamilyDependencies`, plus only the instance-related extensions needed by
the public classes. Remove `OverloadedLabels` when the old fact/query syntax
disappears. The private generated footer passes the three builders to the host
runner; `VisualTraceGraph`, `visualize`, and runner names are not in the
authored body contract.

## Public facade at a glance

This is the complete public `Sverlin` export inventory. Constraints used only
to implement closed overloads are deliberately absent.

| Area                            | Public names                                                                                                                                                                                                                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Builders                        | `Domain`, `Program`, `Render`, `(>>=)`, `(>>)`, `pure`, `return`, `fail`                                                                                                                                                                                                             |
| Domain identities               | `Kind`, `kind`, `declareKind`, `RelationKind`, `orderedRelation`, `symmetricRelation`, `declareRelation`, `declareSteps`                                                                                                                                                             |
| Input generation                | `Generator`, Domain-form `variable`, `between`, `elementOf`, `weighted`, `listOf`, `shuffle`                                                                                                                                                                                         |
| Payloads                        | `Traceable(Payload)`, `LUnit(..)`, `LBool(..)`, `LInt(..)`, `LDouble(..)`, `LString(..)`, `LOperator(..)`                                                                                                                                                                            |
| Operators                       | `Applicable1(Apply1Result, applyPayload1)`, `Applicable2(Apply2Result, applyPayload2)`                                                                                                                                                                                               |
| Linear resources                | `Block`, `Pending`, `Slot`, `Create(..)`, `Use(..)`, `Copy(..)`, `Replace(..)`, `Apply1(..)`, `Apply2(..)`, `Destroy(..)`, `Seal(..)`, `Unseal(..)`, `Relate(..)`                                                                                                                    |
| Domain and Program construction | `create`, `materialize`, `seal`, `relate`                                                                                                                                                                                                                                            |
| Program-only lifecycle          | `copy`, `use`, `apply1`, `apply2`, `replace`, `destroy`, `unseal`, `step`                                                                                                                                                                                                            |
| Presence and frames             | `always`, `sometimes`, `frame`                                                                                                                                                                                                                                                       |
| Selection and hierarchy         | `Selected`, `Relations`, `GeneratedNode`, `CanvasNode`, `select`, `node`, `self`, `canvas`, `within`, `relation`, `first`, `second`                                                                                                                                                  |
| Structure                       | `Ranking`, `FixedInt`, `asSequence`, `asTree`, `asDag`, `rankOf`, `asScalar`, `asText`, `payloadScalar`, `Arrangement(..)`, `arrange`                                                                                                                                                |
| Text                            | `TextBuilder`, `ContentValue`, `text`, `literal`, `fragment`, `fragmentMany`, `bindContent`, `content`, `fitText`                                                                                                                                                                    |
| Connectors                      | `ConnectorAnchor`, `AnchorPlacement(..)`, `anchor`, `Marker(..)`, `connector`, `startMarker`, `endMarker`                                                                                                                                                                            |
| Numeric values                  | Render-form `variable`, `Coord`, `at`, `Span`, `by`, `Offset`, `shift`, `Scalar`, `num`, `VisualExpr`, `Unit`, `Angle`, `Vec2(..)`, `vec2`, `(.+.)`, `(.-.)`, `(.*.)`, `(./.)`                                                                                                       |
| Geometry                        | `left`, `top`, `right`, `bottom`, `width`, `height`, `x`, `y`, `center`, `size`, `Insets`, `uniform`, `symmetric`, `edges`, `padding`, `margin`, `Axis(..)`, `ContentFit(..)`, `contentFit`, `Percent`, `percent`, `xAt`, `yAt`, `widthOf`, `heightOf`, `aspectRatio`, `separatedBy` |
| Choices and constraints         | `Choice`, `choice`, `caseOf`, `VisualConstraint`, `ensure`, `(.<=.)`, `(.>=.)`, `(.==.)`, `VisualAlternative`, `alternative`, `oneOf`                                                                                                                                                |
| Style operations                | `style`, `withoutStyle`, `styleOf`                                                                                                                                                                                                                                                   |
| Numeric and paint fields        | `Opacity`, `FontSize`, `Radius`, `StrokeWidth`, `Alpha`, `Hsl(..)`, `Color`, `Fill`, `Stroke`                                                                                                                                                                                        |
| Categorical fields              | `BorderStyle(..)`, `FontKind(..)`, `FontFilter`, `fontKind`, `fontChoice`, `FontFamily(..)`, `FontWeight(..)`, `FontStyle(..)`, `TextAlign(..)`                                                                                                                                      |

### Generated-wrapper support surfaces

Two deliberately narrow public modules support the generated wrapper. They do
not add names to the unqualified authored `Sverlin` facade.

`Sverlin.Compiler` packages the three authored builders without exposing the
compiler implementation:

```haskell
data SverlinProgram

sverlinProgram
  :: Domain initial
  -> (initial %1 -> Program ())
  -> Render ()
  -> SverlinProgram
```

`Sverlin.Linear` is imported as `Linear` and exposes exactly the following
operations. “Linear numeric”, `Eq`, and `Ord` below refer to the corresponding
`linear-base` instances; their classes are not Sverlin extension points.

| Public names                    | Call shape                                                                                            |
| ------------------------------- | ----------------------------------------------------------------------------------------------------- | --- | ---------------------------- |
| `(+), (-), (*)`                 | `a %1 -> a %1 -> a` for the matching linear numeric instance                                          |
| `(/)`                           | `Fractional a => a -> a -> a`                                                                         |
| `quot, rem`                     | `Integral a => a -> a -> a`                                                                           |
| `(==), (/=)`                    | `a %1 -> a %1 -> Bool` for a linear `Eq` instance                                                     |
| `(<), (<=), (>), (>=), compare` | two linear `a` arguments for a linear `Ord` instance; `compare` returns `Ordering`, the others `Bool` |
| `not`                           | `Bool %1 -> Bool`                                                                                     |
| `(&&), (                        |                                                                                                       | )`  | `Bool %1 -> Bool %1 -> Bool` |
| `(++)`                          | `[a] %1 -> [a] %1 -> [a]`                                                                             |

The unrestricted arrows on `(/)`, `quot`, and `rem` mean they cannot consume a
linear Program binding. They remain useful in Domain generators and for closed
constants; traced linear arithmetic uses the linear operations whose call
shapes accept `%1` arguments.

## Domain

### `Domain`

```haskell
data Domain a
```

`Domain` validates the complete vocabulary, samples its generators, and emits
the constructive trace prefix before Program runs. Declaration operations
return `()` because reusable typed handles are ordinary top-level values;
construction operations return linear capabilities. The compiler records each
marker type and source location for diagnostics and stable identity.

One marker type names one declaration across kinds, relations, variables, and
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

### `Generator` and linear initialization

```haskell
data Generator value

-- Domain specialization of the closed `variable` operation.
variable
  :: forall identity value.
     Typeable identity
  => Generator value
  -> Domain value
```

`variable @Identity generator` samples once for the scenario. Its result is
bound linearly in Domain: it may be pattern-matched and transformed, but every
part must be consumed exactly once into the returned initialization structure.
There is no `Input` handle, `resolveInput`, `Ur`, or other unrestricted value
crossing into Program.

Each Domain variable receives a deterministic sub-seed derived from the
scenario seed and marker identity. Reordering declarations or adding an
unrelated variable therefore does not perturb existing values. Values that
must be correlated are fields of one author-defined composite value generated
by one `Generator`.

`Generator` has library-provided unrestricted `Functor`, `Applicative`, and
`Monad` instances. Its ordinary `do` notation supports dependent generation;
it never creates a Program `Block`, `Pending`, or `Slot`. Custom valid
structures are ordinary top-level functions returning `Generator a`.

Generator defines scenario input, including fixed alternatives and derived
input structure such as a unary path through a generated collection. It cannot
construct or capture a `Program` action. Algorithm work that should appear in
the trace remains in Program; when that work needs the same runtime value more
than once, the author uses `copy` on its Block instead of asking Generator to
smuggle duplicate live capabilities across the boundary.

There are two deliberately visible modelling choices. A trace-faithful example
performs comparisons and updates with Blocks and `Applicable*` operators, so
the trace records the computation. A replay-oriented example may instead make
a finite sequence of expected states part of its generated scenario and pass
that sequence linearly through Domain; Program then visualizes the sequence but
does not independently establish that the algorithm produced it. The latter is
useful for concise teaching material, not a hidden compiler fallback, and an
example must say when it takes that trade-off.

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

`listOf` produces an ordinary runtime Haskell list; its bounds are not a
type-level length and it creates no trace resources. The list is unrestricted
while Generator constructs the scenario. Once Domain-form `variable` returns
it, Domain's linear bind makes the whole value linear, so pattern matching must
consume each head and tail exactly once while, for example, creating Blocks.
No preprocessing pass changes the list's type.

The `value` in `elementOf` may itself be a list, record, tree, or other fixed
input. `weighted` branches over complete generators, with `pure fixedValue`
representing a fixed branch. These two operations cover equal and weighted
input alternatives without another public branching API:

```haskell
fixedList = elementOf [1, 2, 3] [[3, 1, 2], [8, 5, 3]]

fixedOrGenerated = weighted (1, pure [1, 2, 3]) [(1, listOf 4 8 (between 0 99))]
```

Monadic bind expresses a later choice that depends on an earlier one, as in
choosing a vertex count before generating exactly that many labels. Prefer
constructive branches like these to predicate filtering or retry loops.

Invalid bounds, impossible lengths, and non-positive weights are Domain
diagnostics. The leading argument makes `elementOf` and `weighted` non-empty by
construction. There is no public raw seed, predicate filter, retry loop, or
rejection-sampling operation. Valid graph, tree, and DAG generators must
construct valid values directly.

Domain shares only the constructive `create`, `materialize`, `seal`, and
`relate` operations with Program. Their supporting overload is closed and
private. Domain cannot `copy`, `use`, apply operators, replace, destroy,
`unseal`, or declare a `step`; those are algorithm actions. Every generated
value, `Pending`, `Block`, and `Slot` must be consumed once, and Domain returns
the resulting author-defined linear structure directly:

```haskell
data InitialValue

data InitialValues where
  InitialValues :: Block Number %1 -> InitialValues

domain :: Domain InitialValues
domain = do
  value <- variable @InitialValue (between 0 99)
  Create pending <- create (LInt value)
  block <- materialize valueKind pending
  pure (InitialValues block)

program :: InitialValues %1 -> Program ()
```

The private host executes this initialization prefix and Program in one trace
allocation state, passing the Domain result to `program` with a linear arrow.
Creation and relation provenance are therefore ordinary trace events. Generated
scenario data may accompany the resources only through linear fields in that
returned structure; it never reaches Program as an unrestricted value. A
dynamic resource collection is returned in an author-defined GADT whose fields
and tail are linear, not an ordinary list of reusable Blocks.

### `Traceable` and `Payload`

```haskell
class Traceable tag where
  type Payload tag = payload | payload -> tag

data LUnit tag where
  LUnit :: LUnit tag

data LBool tag where
  LBool :: Bool %1 -> LBool tag

data LInt tag where
  LInt :: Int %1 -> LInt tag

data LDouble tag where
  LDouble :: Double %1 -> LDouble tag

data LString tag where
  LString :: String %1 -> LString tag

data LOperator tag where
  LOperator :: LOperator tag
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
    LInt (leftValue Linear.+ rightValue)
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

The top-level Program consumes the value produced by Domain:

```haskell
program :: initial %1 -> Program ()
```

There is no input lookup inside Program. Any initial `Block` and `Slot`
capabilities arrive through this linear argument and must be threaded to a
terminal operation.

Program has no unrestricted bind or escape operation. A helper that receives
runtime data uses `%1` arguments, and consumes it with the qualified `Linear`
arithmetic and comparison operations supplied by the curated prelude. Closed
constants may still be ordinary Haskell values, but a generated value, payload,
resource, or structure containing one cannot enter a `%Many` argument or be
captured by an unrestricted closure. GHC rejects that source before the trace
runs. A calculation that needs to reuse a traced value must first make the
reuse explicit with `copy` and operate on the resulting Blocks.

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

The signatures below are the Program specializations. `create`, `materialize`,
`seal`, and `relate` also have the closed Domain specializations described
above; their result shapes and ownership rules are identical.

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

Visual emphasis is explicit trace state, not something inferred from every
block used within a step. Program may transition a value into a dedicated Kind
with `copy`, `replace`, and `materialize`, keep that successor alive through the
relevant frame, and later transition it again. Render selects that Kind and
assigns its visual style. This preserves the earlier linear tag/relation model:
the trace says exactly when a state exists, while Render decides how it looks.
It also avoids treating unrelated operator inputs or all earlier lineage roots
as highlighted merely because they participated in the same step.

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
selection; each feasible branch must still have exactly one applicable nearest
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
`second links` retrieve that exact occurrence's typed semantic endpoints. They
reject use outside the matching relation scope or with another relation
selection. For an ordered relation, `first` is its source and `second` its
target. For a symmetric relation their stable order is reproducible but
semantically meaningless.

The endpoint handle does not itself create a visual node. A geometry or connector
use first resolves the nearest compatible mapping of that exact semantic block in
the current generated-parent context. If a relation crosses generated groups
and no such local mapping exists, it may use a mapping elsewhere with the same
semantic source block; it never broadens the match by kind alone. Presence and
choice guards are checked on every candidate. Mutually exclusive mappings may
therefore cover different branches, while mappings that can be active together
remain an ambiguity diagnostic. A relation supplies spatial endpoints but draws
nothing itself.

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
[`Sverlin.Internal.Render.Typography`](../src/Sverlin/Internal/Render/Typography.hs); the finite
upper bound permits useful label variation without allowing text alone to set
an arbitrary canvas scale. A later theme may change both bounds, but they are
compiled into the design-space identity and output provenance rather than read
during materialization.

An implicit fitted size belongs to the content declaration and its node-mapping
lineage, not to each expanded concrete node. All peers produced by one
`node selected` declaration therefore share one sampled size, and every line
contributes a fit constraint so the longest peer limits it. A second mapping of
the same semantic selection has a distinct lineage and may sample another size.

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

`Choice value` is an abstract symbolic finite value. It is not a visual
component and draws nothing by itself. `choice` and `fontChoice` create fresh
random values; `styleOf` can project an already assigned categorical field into
the same type without creating another decision. The compiler owns each finite
domain and its stable serialization tokens; authors cannot define a
`ChoiceDomain` instance. `caseOf` is an exhaustive map from any such value to
complete Render blocks. Font-family choices use `fontChoice`, not
`choice @FontFamily`. Custom alternatives use `oneOf` rather than a reusable
custom category in the baseline.

## Layout and box model

The read/set overloads in this section use private closed dispatch. The
supporting classes are not exported as authored extension points.

### `Coord`

`Coord` is a non-negative absolute canvas coordinate.

```haskell
type Coord = VisualExpr CoordRole
at :: Double -> Coord
```

`CoordRole` is a private marker used only to keep expression roles distinct.

A fresh `variable @Coord` must acquire a finite upper bound through authored or
derived constraints. Adding a `Span` or `Offset` produces a coordinate;
subtracting coordinates produces an `Offset`.

### `Span`

`Span` is a non-negative length used for dimensions, gaps, text size, radius,
stroke, padding, and margin.

```haskell
type Span = VisualExpr SpanRole
by :: Double -> Span
```

`SpanRole` is private.

Fresh spans require a finite upper bound. Subtracting spans produces an
`Offset`.

### `Offset`

`Offset` is a signed displacement.

```haskell
type Offset = VisualExpr OffsetRole
shift :: Double -> Offset
```

`OffsetRole` is private.

It deliberately has no `asCoord` or `asSpan` reinterpretation helper.

### `Scalar`

`Scalar` is unitless and may scale an expression when the other factor is fixed
before numeric solving.

```haskell
type Scalar = VisualExpr ScalarRole

num :: Double -> Scalar
num :: Double -> Unit
num :: Double -> Angle
```

`ScalarRole` is private. The three `num` lines are the complete closed
overloads: the expected result type selects the role. `num` rejects non-finite
or out-of-domain values. A sampled Scalar must be finitely bounded.

### `VisualExpr`

```haskell
data VisualExpr role
```

`VisualExpr role` is a read-only affine expression returned by selected node
geometry or style access. Authors cannot use its constructor. `Coord`, `Span`,
`Offset`, `Scalar`, `Unit`, and `Angle` are its public aliases; their private
role markers keep otherwise similar expressions incompatible.

### `Unit`

```haskell
type Unit = VisualExpr UnitRole
```

`Unit` is intrinsically bounded to the inclusive interval zero to one. It is
used for opacity, alpha, saturation, and lightness. `UnitRole` is private.

### `Angle`

```haskell
type Angle = VisualExpr AngleRole
```

`Angle` is the bounded HSL hue domain. The compiler gives the equivalent zero
and 360 degree boundary one canonical representation. `AngleRole` is private.

### `Vec2`

```haskell
data Vec2 a = Vec2 a a
vec2 :: a -> a -> Vec2 a
```

`Vec2` groups horizontal then vertical values. Equality and supported
arithmetic lower component by component.

### Geometry

Each operation has only its documented setter and accessor forms:

| Operation                                  | Current-node setter       | Selected-node accessor     |
| ------------------------------------------ | ------------------------- | -------------------------- |
| `left`, `top`, `right`, `bottom`, `x`, `y` | `Coord -> Render ()`      | `Selected a -> Coord`      |
| `width`, `height`                          | `Span -> Render ()`       | `Selected a -> Span`       |
| `center`                                   | `Vec2 Coord -> Render ()` | `Selected a -> Vec2 Coord` |
| `size`                                     | no setter                 | `Selected a -> Vec2 Span`  |

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
bounded. The rejection is not primarily about floating-point error: a free
expansion direction has no finite range from which to sample uniformly. If
children and `Hug` determine both canvas spans, no separate canvas maximum is
needed.

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

This operation gives the current non-connector node a fixed positive
horizontal-to-vertical ratio. On the canvas it does not bound the canvas scale,
so a `Contain` canvas still needs a bounded width or height (or both).

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

The closed public call shapes are:

| Operation | Supported operand and result roles                                                                                                                                                    |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `(.+.)`   | `Coord -> Span -> Coord`, `Span -> Coord -> Coord`, `Coord -> Offset -> Coord`, `Offset -> Coord -> Coord`, and same-role addition for `Span`, `Offset`, `Scalar`, `Unit`, or `Angle` |
| `(.-.)`   | `Coord -> Span -> Coord`, `Coord -> Offset -> Coord`, `Coord -> Coord -> Offset`, `Span -> Span -> Offset`, and same-role subtraction for `Offset`, `Scalar`, `Unit`, or `Angle`      |
| `(.*.)`   | either order of `Scalar` with `Span`, `Offset`, `Scalar`, `Unit`, or `Angle`, returning the non-scalar role, or `Scalar` for two scalars                                              |
| `(./.)`   | `Span`, `Offset`, `Scalar`, `Unit`, or `Angle` divided by `Scalar`, returning the numerator role                                                                                      |

`Vec2` addition and subtraction are component-wise when the matching component
operation has the same operand and result role. The operators have the usual
fixities:

```haskell
infixl 6 .+., .-.
infixl 7 .*., ./.
```

Dotted operators distinguish Render expressions from ordinary Haskell
arithmetic in Domain and Program. Use `at`, `by`, `shift`, and `num` for fixed
visual values.

Multiplication requires one factor fixed before numeric solving; division
requires a fixed non-zero denominator. Variable-by-variable products and
variable denominators are source diagnostics.

## Style authoring and colour

### Shared style operations

These are closed overloaded operations. Their complete node call shapes are:

| Field         | `style @Field` input                  | `styleOf @Field` result |
| ------------- | ------------------------------------- | ----------------------- |
| `Opacity`     | `Unit`                                | `Unit`                  |
| `FontSize`    | `Span`                                | `Span`                  |
| `Radius`      | `Span`                                | `Span`                  |
| `StrokeWidth` | `Span`                                | `Span`                  |
| `Alpha`       | `Unit`                                | `Unit`                  |
| `Fill`        | `Color`                               | `Color`                 |
| `Stroke`      | `Color`                               | `Color`                 |
| `BorderStyle` | `BorderStyle` or `Choice BorderStyle` | `Choice BorderStyle`    |
| `FontFamily`  | `FontFamily` or `Choice FontFamily`   | `Choice FontFamily`     |
| `FontWeight`  | `FontWeight` or `Choice FontWeight`   | `Choice FontWeight`     |
| `FontStyle`   | `FontStyle` or `Choice FontStyle`     | `Choice FontStyle`      |
| `TextAlign`   | `TextAlign` or `Choice TextAlign`     | `Choice TextAlign`      |

For every row, `style @Field input :: Render ()`,
`withoutStyle @Field :: Render ()`, and
`styleOf @Field selected` takes `Selected node`. Unsupported field/input pairs
are type errors. Connector bodies accept only the subset stated in the
connector section.

`withoutStyle @Field` suppresses an inherited or generated value.
`styleOf @Field selected` reads the final symbolic value and
requires the field to be present in every active branch. When presence itself
is conditional, constrain the driving choice instead.

For a childless visual mapping, an unspecified field may be completed by a
private seeded theme. The baseline surface profiles are `transparent`,
`outline`, `flat`, `soft-card`, and `pill`; one semantic mapping lineage shares
its profile, while the presentation shares one palette. Automatic font choices
use unique concrete catalog families and real weights. Canvas, structural
parents, and generated text-only leaves remain transparent unless authored.
These defaults are compiler behavior, not a public `styleFamily` or
`StyleProfile` API.

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
shape and text. `styleOf @Opacity` returns `Unit`.

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
`styleOf @FontSize` returns `Span`.

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
`styleOf @Radius` returns `Span`.

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
`Span`.

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
`styleOf @Alpha` returns `Unit`.

```haskell
paintAlpha <- variable @Unit
node visited $ style @Alpha paintAlpha
ensure $ paintAlpha .>=. num 0.55
ensure $ paintAlpha .<=. num 1
```

### `Hsl`

```haskell
data Hsl hue component where
  Hsl
    :: { hue        :: Angle
       , saturation :: Unit
       , lightness  :: Unit
       }
    -> Hsl Angle Unit
```

`Hsl` retains two type parameters for its public type constructor, but the
public value constructor deliberately produces only `Hsl Angle Unit`. Fixed
and sampled components use the same aliases, so they can be combined directly.

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
`Color`, allowing constraints on its `Angle` and `Unit` components.

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
`Color`. Stroke may be inherited, constrained, or suppressed with
`withoutStyle @Stroke`.

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
weights are resolved against inheritance before shaping: `bolder` maps parent
weights up to 300, 400–500, and 600–900 to 400, 700, and 900 respectively;
`lighter` maps 100–500, 600–700, and 800–900 to 100, 400, and 700. Unsupported faces
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
`FontStyleOblique` is absent because the compiler does not alias or synthesize
an oblique face. Use `FontStyleItalic` when a real italic face is intended. A
family without the selected real face invalidates that branch.
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

infix 4 .<=., .>=., .==.
```

Each comparison has call shape `a -> a -> VisualConstraint`, where `a` is one
of `Coord`, `Span`, `Offset`, `Scalar`, `Unit`, `Angle`, or `Vec2 a` for one of
those six numeric aliases. Both operands must have the same public role.
Categorical values branch through `caseOf` rather than these numeric
comparisons. A diagnostic names the source expression and unsupported
operation before solving.

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
non-empty set of labelled alternatives. Labels must be unique within it. At
each reached `oneOf`, feasible alternatives have equal local authored weight in
the baseline. A nested `oneOf` is weighted only after its containing alternative
is selected, so adding nested branches does not increase that parent's weight.
A body may contain complete nodes, styles, connectors, and constraints, not
just one equation.

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

- `s1` is the **scenario seed**. Domain generation and its linear
  initialization prefix run once; Program consumes that result to construct
  one shared trace for the whole batch.
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
when step names or labels happen to match. Activation uses exact scenario-key
compatibility plus hierarchical occurrence mapping rather than flat step
signatures.

For the convenience form `--seed s --count n`, the intended batch has scenario
seed `s` and view seeds `[s .. s + n - 1]`. Its second output is not required to
equal a separate singleton compilation at seed `s + 1`, because that singleton
has a different scenario input. The compiler runs Domain and Program once for
the batch, prepares one Render design space, and samples that shared preparation
for every requested view seed.

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
   design more likely. When the complete space is small enough to prepare,
   partition cells may be weighted by their estimated numeric measure within
   the already selected authored assignment.

Small finite spaces may enumerate choices and prepare each feasible exact
affine region. Large spaces instead use one HiGHS call with seed-derived,
symmetric costs to complete all authored, categorical, and compiler-created
algebraic choices; exact affine-region preparation follows that completion.
Geometry-neutral choices and frame presence remain discrete decisions rather
than multiplying a fully enumerated set of affine configurations.

Symmetric costs naturally balance uncoupled equal choices across seeds.
Feasibility coupling can skew reachable completions, so coupled mixtures of
authored, categorical, and algebraic decisions have no perfect local or global
uniformity guarantee. A future weighted visual choice must be explicit rather
than inferred from how many compiler cases an alternative creates.

Regions of different affine dimension cannot be compared by ordinary volume.
In an enumerated small space, the compiler treats an authored equality that
deliberately fixes a dimension as part of that alternative's weight, then
compares algebraic cells only within the same reduced affine space. If
compiler-created cells for one authored assignment unexpectedly have different
dimensions, preparation rejects the ambiguous measure rather than silently
choosing a policy.

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

### Preparation, caching, and numerical repair

Preparing a region means normalizing constraints, reducing exact equalities,
proving feasibility, finding one feasible starting point, and caching the
matrix data used for sampling. It does not cache a sampled layout. Ten view
seeds reuse the deterministic preparation but each still choose decisions and
generate a new numeric point.

Small finite choice spaces may enumerate and prepare their feasible exact
regions, with algebraic cells measure-weighted within an authored assignment.
Large spaces retain guarded constraints in the HiGHS model rather than
enumerating the Cartesian product. One ordinary HiGHS call gives every
authored, categorical, and algebraic token a seed-derived symmetric cost and
returns a complete feasible assignment; exact affine-region preparation then
validates and prepares that assignment.

Only when backend completion and exact preparation disagree does a bounded,
seed-ordered backtracking fallback try alternatives with feasibility-only
calls. It permits at most the larger of 256 and `maxChoiceBranches` HiGHS
queries per view. The 256-query floor prevents a deliberately small enumeration
threshold from disabling corrective search; exhaustion is a sampling error,
not proof that the design itself is infeasible.

Once the large-space decisions identify one exact convex region, the compiler
prepares it lazily and caches it by the complete decision assignment. Repeated
view seeds that reach that assignment reuse the preparation, but sample a new
numeric point inside it. This path does not prepare every algebraic cell or
estimate their relative volumes, so it makes no global volume-uniform claim
across the oversized nonconvex union.

Feasibility is deterministic and independent of whether the seed's one random
walk succeeds. Feasibility checks, projection, and chord-boundary handling all
use the same tolerance after constraint normalization. A tolerance-sized chord
inversion collapses to its shared boundary; projection and retry use that same
threshold. Any meaningful violation beyond it remains a numeric sampling
error. This repair does not restart or reseed the walk, choose a different
direction, project ordinary valid steps, declare the region infeasible, or
invoke another optimizer.

### Solver components

The implementation uses the top-level [`Solver`](../src/Solver.hs) facade and
its internals rather than maintaining a second solver stack:

- affine classification and representation live in
  [`Solver.Affine`](../src/Solver/Affine.hs);
- categorical compilation distinguishes authored decisions from
  compiler algebraic partitions;
- [`Solver.Highs`](../src/Solver/Highs.hs) provides deterministic linear
  feasibility and seed-cost completion;
- normalization, equality reduction, hit-and-run, and volume machinery live in
  [`Solver.Sample`](../src/Solver/Sample.hs); and
- [`CompiledDesignSpace`](../src/Solver/DesignSpace.hs) owns reusable,
  deterministic normalized and equality-reduced region data plus bounded
  corrective backtracking.

The existing `containers` dependency and `Data.Graph`, `Data.Map`, and
`Data.Set` are sufficient for sequence, tree, and DAG validation. Do not add a
graph package merely to hold the same nodes and edges. No new Haskell solver
library is required for this architecture.

The removed path used random-MIP assignment as a sampler, repeated preparation
for every sample, a seed-zero sample as a feasibility test, string solver
identities, and a penalty/L-BFGS-B fallback. None is part of the authored or
solver facade contract.

## Internal compiler and renderer shape

### One private `RenderPlan`

Authored Render code lowers once into a private `RenderPlan` that owns semantic
matches, generated hierarchy, presence conditions, style cascade, text lines,
connectors, prepared graph templates, affine constraints, and source
provenance. Retained Box, Style, Build, and typography algorithms are private
implementation details rather than authored APIs.

The plan replaces the old query matching, `View.Access`, `View.Template`,
`StyleProfile`, and authored graph/solve surfaces. It preserves lexical match
scope, stable visual identity, parent containment, and independent mappings of
the same semantic selection without public forwarding layers.

Typography preparation happens before numeric solving for every feasible
metric branch. Prepared glyph coefficients and fit inequalities enter the same
affine sample as box geometry; there is no solve, shape/max-fit, pin, and
re-solve flow.

The implementation follows this ownership map. The left column records the
historical donor, not a second public API:

| Historical source                                                      | Current ownership                                                                                                                                                                                                                                                          | Retained behavior                                                                                |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `LinearTrace.Choreography`                                             | [`Sverlin`](../src/Sverlin.hs)                                                                                                                                                                                                                                             | Authored facade only; legacy code is not re-exported.                                            |
| `LinearTrace.Core.Internal`                                            | [`Sverlin.Internal.Semantic`](../src/Sverlin/Internal/Semantic.hs)                                                                                                                                                                                                         | Linear resources, provenance, allocation, and event ordering.                                    |
| `LinearTrace.Choreography.Match`, `Graph`, and `View.Access`           | private `RenderPlan` matching/projection                                                                                                                                                                                                                                   | Semantic scope and stable projection identity.                                                   |
| `View.Template`, `Build`, and `StyleProfile`                           | private `RenderPlan` lowering                                                                                                                                                                                                                                              | Useful lowering and coherent missing-style completion without a public authored profile layer.   |
| `View.Box`, `View.Style`, and `View.Primitives`                        | private affine box/style representation                                                                                                                                                                                                                                    | Typed geometry and cascade behavior without exposing accumulated records.                        |
| `Visualization.FontCatalog`, `HarfBuzz`, and `Typography`              | private [`Font`](../src/Sverlin/Internal/Render/Font.hs), [`FontCatalog`](../src/Sverlin/Internal/Render/Typography/FontCatalog.hs), [`HarfBuzz`](../src/Sverlin/Internal/Render/Typography/HarfBuzz.hs), and [`Typography`](../src/Sverlin/Internal/Render/Typography.hs) | Canonical font metadata, whole-line shaping, and affine fit coefficients.                        |
| `Visualization.CodeHighlight`                                          | none                                                                                                                                                                                                                                                                       | Typed text fragments replace the code-special highlighting surface.                              |
| `Visualization.Compile`, `IR`, `Resource`, and `Target`                | private [`Render.Compile`](../src/Sverlin/Internal/Render/Compile.hs) plus versioned [`Sverlin.Output`](../src/Sverlin/Output/) modules                                                                                                                                    | Resource and serialization behavior plus scenario, fragment, relation, and connector provenance. |
| [`Solver.DesignSpace`](../src/Solver/DesignSpace.hs) and other modules | stable top-level [`Solver`](../src/Solver.hs) facade                                                                                                                                                                                                                       | Reusable bounded affine compilation and sampling.                                                |

This map intentionally unifies overlapping internal representations. It does
not imply one large module: boundaries should follow ownership of validated
state, not historical public module names.

### Trace, projection, and identity

Compile Domain declarations into a typed registry, sample its finite
generators, and execute its constructive prefix in the trace engine. Pass the
resulting resource structure linearly into Program, which continues the same
immutable event stream. Nested step occurrences retain typed definition
identity and runtime paths. Relations are trace events attached to stable slot
owners, not current occupants.

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

The application boundary now follows the same scenario/view model:

- [`compile/app/Main.hs`](../app/Main.hs) passes the first seed as the scenario
  seed and the complete ordered view-seed batch to the narrow compiler host.
- [`src/lib/server/compiler/index.ts`](../../src/lib/server/compiler/index.ts)
  invokes one compiler process for the batch and verifies returned scenario and
  view correlation.
- [`src/lib/server/projects/service.ts`](../../src/lib/server/projects/service.ts)
  stores and compares `scenarioKey` and hierarchical occurrence keys rather
  than requiring identical optional-frame lists.
- Shared IR types under
  [`src/lib/shared/visualization/`](../../src/lib/shared/visualization/) and
  client playback under
  [`src/lib/client/visualization/`](../../src/lib/client/visualization/) use the
  ordered union and hold rule. Persisted project events remain immutable;
  compatibility belongs in the IR decoder/projection rather than by rewriting
  old events.

### Host and package boundary

The generated wrapper imports `Sverlin` as its only DSL module, alongside the
fixed language prelude described above. A private host module validates
`domain`, executes its constructive prefix, passes its result once to
`program`, compiles `render`, and applies the service seeds.
The compiler remains one service accepting `.sverlin` content plus a non-empty
seed batch; Haskell implementation types do not cross into the SvelteKit
server.

Expose only:

- the authored `Sverlin` facade;
- a narrow compiler/runner boundary used by the executable;
- the intentionally stable top-level `Solver` facade; and
- an IR module only if another package deliberately consumes that Haskell type.

Historical modules are behavioral donors, not compatibility commitments. The
refactor used characterization tests and, in particular, commits `970907d`
(slot owner projection), `52f842b` and `a5084ba` (render
identity and transitions), `9efb493` (typography/resources), `0ff53cc`
(template and API-index boundary), and `03c4e14` (archived slots, connectors,
and SVG transition edge cases).

## Deliberately absent from `Sverlin`

The `Sverlin` facade does not expose:

- old builder/facade names, compiler runners, graph builders, solver entrypoints,
  or view statistics;
- free facts, queries, atoms, integer bindings, payload predicates, query-era
  selections, or alternate materialization calls;
- `Input`, `input`, `resolveInput`, `Ur`, or another unrestricted input escape
  into Program;
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

## Implemented migration shape

This section records how the implementation is divided. It is not a claim that
the independent verification gates in the next section have all completed.

### Contract and fixtures

This document and the ten sources in [`examples/`](examples/) define the
contract. Parser and typecheck coverage derives from those sources.
[`API_issues.md`](API_issues.md) remains limited to demonstrated gaps that
cannot be expressed by composing this facade.

### Typed Domain and Program

The `Sverlin` facade and private host provide typed declarations, constructive
seeded Domain initialization, its direct linear handoff to Program, one
materialization path, typed steps, stable Slots, and relation events. Authored
source cannot name the old fact/query representation.

### One Render plan

Typed selections and relations, generated hierarchy, presence provenance,
structural rankings, text builders, connectors, prepared arrangements, closed
style fields, and affine constraints lower into one private plan. Projection
identity, containment, relation lifetime, and reverse transitions remain
covered at their compiler boundaries.

### Bounded piecewise-affine compilation

Typography branches prepare before solving. Authored decisions are distinct
from algebraic partitions, feasibility is deterministic, prepared regions are
reused across a view batch, and numeric points are sampled from bounded affine
regions. Pinned typography, penalty objectives, nonlinear fallback, and the old
optimizer path are absent.

### IR, playback, and package boundary

The IR carries scenario/view provenance and hierarchical frame data. Browser
playback aligns only views from one scenario while old artifacts retain their
decoder path. Authored code imports only `Sverlin`; the Haskell package exposure
audit remains a separate verification gate.

## Verification gates

Before treating the overhaul as verified:

- every example must parse and typecheck against `Sverlin`; later phases must
  compile it for several scenario and view seeds;
- for one fixed scenario seed and fixed view-seed list, each view's result must
  not depend on cache warmth, view processing or scheduling order, map order,
  or process reuse; request order itself remains meaningful because its first
  seed selects the scenario;
- tests must cover linear ownership, exactly-once pending materialization,
  the direct linear Domain-to-Program handoff, rejection of unrestricted
  escape operations, Slot owner identity, late relation creation, duplicate
  relations, structural diagnostics, optional dependency propagation,
  whole-line shaping, and fragment cluster mapping;
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

| Source                                                                          | Main pressure on the API                                     |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| [`LinearSearch.sverlin`](examples/LinearSearch.sverlin)                         | array membership, optional labels, comparison fragments      |
| [`BinarySearch.sverlin`](examples/BinarySearch.sverlin)                         | narrowing ranges, midpoint relations, optional detail frames |
| [`BubbleSort.sverlin`](examples/BubbleSort.sverlin)                             | stable cells, occupant replacement, adjacency, swap steps    |
| [`MergeSort.sverlin`](examples/MergeSort.sverlin)                               | nested steps, split/merge structures, alternate layouts      |
| [`HeapSort.sverlin`](examples/HeapSort.sverlin)                                 | one trace shown as an array, a tree, or both                 |
| [`LinkedListReversal.sverlin`](examples/LinkedListReversal.sverlin)             | persistent nodes, changing directed links, connectors        |
| [`BreadthFirstSearch.sverlin`](examples/BreadthFirstSearch.sverlin)             | general graph arrangement, queue membership, visit levels    |
| [`DijkstraShortestPath.sverlin`](examples/DijkstraShortestPath.sverlin)         | weighted semantic values and directed edge visuals           |
| [`TopologicalSort.sverlin`](examples/TopologicalSort.sverlin)                   | DAG validation, rank-based layers, optional order view       |
| [`LongestCommonSubsequence.sverlin`](examples/LongestCommonSubsequence.sverlin) | two input sequences, a dynamic-programming grid, code text   |

These are contract fixtures rather than evidence that runtime verification has
completed. Their comments explain composition and call out any genuinely
missing operation in
[`API_issues.md`](API_issues.md) rather than inventing an unlisted public name.
