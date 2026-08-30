# Proposed Sverlin API — quick list

This is the compact inventory of the proposed authored `Sverlin` facade. The
detailed contract and rationale remain in [API_plan.md](API_plan.md). This is a
proposal, not the currently implemented API.

Keep this file synchronized with `API_plan.md` whenever a public name is added,
removed, renamed, or resolved. Constructors and class members are shown only
when they are public. Repeated type-class constraints are omitted where they do
not change the shape of an operation. **Open** means the capability belongs in
the facade but its final name or signature is not settled.

Authored source imports only `Sverlin` and supplies three definitions:

```haskell
domain :: Domain ()
program :: Program ()
render :: Render ()
```

The shared flow is: Domain declares a typed `Kind`; Program attaches it to a
materialized block; Render selects that kind. A declared `RelationKind` uses the
same `select` entry point for the relations active in each exposed frame. Typed,
nestable Program steps replace free-form checkpoint labels; Render uses general
`always` and `sometimes` wrappers to choose which step occurrences become frames.

```haskell
type Shown = "shown"
type Removed = "removed"

program = do
  value <- step @Shown $ do
    Create pending <- create (LInt 3)
    materialize valueKind pending
  step @Removed $ do
    Destroy <- destroy value
    pure ()

render = do
  always $ frame @Shown
  always $ frame @Removed

  Selected values <- select valueKind
  node values $ content (text "value")

  Selected adjacentLinks <- select adjacent
  relation adjacentLinks $ do
    previous <- first adjacentLinks
    next <- second adjacentLinks
    ensure $ left next .==. right previous + shift 12
```

## Domain

Domain declares the semantic vocabulary shared by Program and Render.

### Declarations

```haskell
data Domain a
data Kind tag                         -- abstract block classification
data RelationKind source target      -- abstract location relation
```

**Open:** final declaration operations for kinds, operators, and ordered or
symmetric relation kinds. Names such as `declareKind`, `declareOperator`, and
`declareRelation` in examples are placeholders, not settled exports.

**Open declaration shape:** Domain also declares the finite set of typed step
identities used by Program and Render. `declareSteps @'[Shown, Removed]` is the
working spelling; the declaration name and packaging remain open.

### Payloads

```haskell
class Traceable tag where
  type Payload tag = payload | payload -> tag

data LUnit tag              = LUnit
data LBool tag              = LBool Bool
data LInt tag               = LInt Int
data LDouble tag            = LDouble Double
data LString tag            = LString String
data LOperator operator tag = LOperator
```

One instance declares both the trace type and its payload representation. Here,
`Number` is only an author-defined example name, not a built-in Sverlin type:

```haskell
data Number

instance Traceable Number where
  type Payload Number = LInt Number
```

### Operators

```haskell
class Applicable1 op arg where
  type Apply1Result op arg
  applyPayload1 :: Payload op %1 -> Payload arg %1 -> Payload (Apply1Result op arg)

class Applicable2 op lhs rhs where
  type Apply2Result op lhs rhs
  applyPayload2 :: Payload op %1 -> Payload lhs %1 -> Payload rhs %1 -> Payload (Apply2Result op lhs rhs)
```

`LOperator` carries no runtime value. Its type selects the `Applicable1` or
`Applicable2` instance; changing values such as a scale factor are ordinary
operands. Core persists the marker internally, and operator spelling belongs
to Render.

## Program

Program creates an immutable trace. Its resource handles are linear: each must
be threaded to another operation or consumed exactly once.

### Resources and results

The compact constructor notation below omits linear field arrows; the operation
signatures show how every resource is consumed and returned.

```haskell
data Program a
data Block tag                  -- abstract live value
data Slot owner tag             -- abstract stored value at an owner location
data Pending tag                -- abstract unfinished lifecycle result

data OneUse a       = OneUse a
data Create tag     = Create (Pending tag)
data Use tag        = Use (OneUse (Payload tag))
data Copy tag       = Copy (Block tag) (Pending tag)
data Replace tag    = Replace (Pending tag)
data Apply1 op arg  = Apply1 (Pending (Apply1Result op arg))
data Apply2 op l r  = Apply2 (Pending (Apply2Result op l r))
data Destroy tag    = Destroy
data Seal owner tag = Seal (Block owner) (Slot owner tag)
data Unseal owner tag = Unseal (Block owner) (Block tag)
data Relate ... = Relate sourceSlot targetSlot
```

`Relate` is a public result wrapper. Its exact type parameters remain **open**;
its pattern shape is settled:

```haskell
Relate sourceSlot targetSlot
```

### Lifecycle

```haskell
create  :: Payload tag %1 -> Program (Create tag)
copy    :: Block tag %1 -> Program (Copy tag)
use     :: Block tag %1 -> Program (Use tag)
apply1  :: Block op %1 -> Block arg %1 -> Program (Apply1 op arg)
apply2  :: Block op %1 -> Block lhs %1 -> Block rhs %1 -> Program (Apply2 op lhs rhs)
replace :: Block tag %1 -> Pending tag %1 -> Program (Replace tag)
destroy :: Block tag %1 -> Program (Destroy tag)

seal   :: Block owner %1 -> Block tag %1 -> Program (Seal owner tag)
unseal :: Block owner %1 -> Slot owner tag %1 -> Program (Unseal owner tag)

materialize :: Kind tag -> Pending tag %1 -> Program (Block tag)
materializeWithKind :: (Payload tag -> Kind tag) -> Pending tag %1 -> Program (Block tag)
commit :: Pending tag %1 -> Program (Block tag)

(<$>) :: (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
(<*>) :: OneUse (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
```

**Open signature:** `relate` consumes and reissues two matching `Slot`s. The
compiler records a relation between their stable owners but returns no relation
token. It may occur after an earlier exposed frame. Relation-derived geometry joins
the fixed constraints over the stable owners' overlapping lifetimes, while the
relation itself is visible only after this Program event. Unsealing or resealing a
slot does not change existing relations, which end automatically when either owner
is destroyed. Conflicting accumulated constraints are a compile-time error, not a
reason to keep sampling.

```haskell
relate :: RelationKind source target -> ... -> Program (Relate ...)
```

### Named steps

```haskell
step :: forall name a. ... => Program a %1 -> Program a
```

`step @Name action` gives a reusable Program action a typed identity. Steps may
nest, and the result of the wrapped action is returned unchanged. The same identity
is used by `frame`, `fragment`, and `fragmentMany`; there is no public
`checkpoint :: String -> Program ()` in the target API.

**Open signature:** the constraints connecting `name` to the Domain declaration
remain unsettled. The `step` name, type application, nesting behavior, and
result-preserving shape are settled.

## Render

Render declares selections, nodes, text, relations, layout, style, and visual
constraints independently of Program execution.

### Conditional composition

```haskell
always    :: ... => Render a -> Render a
sometimes :: ... => Render a -> Render a
```

The wrappers apply to values whose presence Render can track:

```haskell
Selected explanation <- sometimes $ node $ content (text "comparison failed")

Selected detail <- node $ do
  Selected current <- self
  content (text "try the next element")
  ensure $ top current .==. bottom explanation + by 12

Selected counter <- node $ content (text "iteration")
```

If a seed omits `explanation`, Render also omits `detail` and its constraint
because they consume the optional handle; the independent `counter` remains.
Presence conditions remain internal, so authors do not handle `Maybe` or repeat
guards. Several optional inputs must all be present, and `Render ()` groups its
effects under one condition. Arbitrary plain Haskell values do not acquire this
tracking; the exact private constraint on `a` remains open.

The choice is created at the current match scope, such as one matched node or
relation lifetime. `always` adds no choice and cannot override an inherited absent
dependency. Optional geometry creates include and omit design branches;
geometry-neutral choices are sampled separately from affine layout.

### Frames

```haskell
frame :: forall name. ... => Render ()
```

`frame @StepA` turns each occurrence of that typed Program step into a candidate
frame. Execution order, including repeated steps, determines frame order:

```haskell
always $ frame @InitializeTarget
sometimes $ frame @CompareTarget
always $ frame @FinishSearch
```

An `always` frame is required. A `sometimes` frame receives an independent,
equal-weighted include/omit choice for each executed step occurrence. Frame
inclusion is geometry-neutral and therefore does not multiply affine solver
configurations.

### Rules, selections, and nodes

```haskell
data Render a
data MatchSpec                    -- abstract compiled rules
data Selected tag                 -- abstract selected node or node set
data Variable a    = Variable a
data Bound a       = Bound a
data SelectionBinding a = Selected a
data GeneratedNode
data CanvasNode

class Selectable selector result | selector -> result where
  select :: selector -> Render (SelectionBinding result)

instance Selectable (Kind tag) (Selected tag)
instance Selectable (RelationKind source target) (Relations source target)

visualize :: Render () -> MatchSpec  -- TODO is this public?

class Node input result | input -> result where
  node :: input -> result

instance Node (Selected tag) (Render () -> Render ())
instance Node (Render ()) (Render (SelectionBinding (Selected GeneratedNode)))

self   :: Render (SelectionBinding (Selected GeneratedNode))
canvas :: Selected CanvasNode
```

The two `Selectable` instances are library-provided: `select valueKind` binds
live blocks, while `select Adjacent` binds active relations in the current exposed
frame. Selecting relations does not draw them or make them acceptable to `node`.

### Text

```haskell
data ContentValue                 -- abstract fixed or bound text
text    :: String -> ContentValue
content :: ... -> Render ()       -- fixed/default size; the node hugs the line
fitText :: ... -> Render ()       -- bounded size variation; never maximizes or wraps

data TextBuilder a
literal      :: String -> TextBuilder ()
fragment     :: ...               -- fragment @Step "text"
fragmentMany :: ...               -- fragmentMany @'[StepA, StepB] "text"
```

**Open signatures:** `content` and `fitText` accept ordinary `ContentValue` and
composed `TextBuilder` input; the exact supporting overload and typed step
representation are not settled. `content` uses an authored or theme-default
fixed size and normal `Hug` sizing derives the node from the shaped line.
`fitText` uses an explicit bounded `FontSize` variable or creates one in the
theme-defined fit range. It permits any feasible size rather than choosing the
largest. Every text node remains one independently positioned, shaped line;
neither operation wraps it.

### Relations and structural rankings

```haskell
data Relations source target
data Ranking node
data FixedInt

relation :: Relations source target -> Render () -> Render ()
first :: Relations source target -> Render (Selected source)
second :: Relations source target -> Render (Selected target)

asSequence :: Relations node node -> Selected node -> Render (Ranking node)
asTree     :: Relations node node -> Selected node -> Render (Ranking node)
asDag      :: Relations node node -> Selected node -> Render (Ranking node)

rankOf :: Ranking node -> Render FixedInt

asScalar :: FixedInt -> Scalar
asText   :: FixedInt -> ContentValue
```

`Relations` is the reusable result of `Selected links <- select relationKind`.
Its endpoints always support ordinary spatial constraints. A relation is drawn
only when an optional connector is declared inside its spatial scope. The exact
connector, anchor, and arrow vocabulary remains open.

`node selectedBlocks` and `relation selectedRelations` are the corresponding
Render mappings. `relation` creates one spatial scope per selected relation and
`first selectedRelations` and `second selectedRelations` retrieve that scope's
statically typed endpoint nodes. The compiler rejects either lookup outside the
matching relation scope, or when passed a different relation selection. For an
ordered kind, `first` is its source and `second` its target. For a symmetric
kind, the order is stable for reproducible output but carries no meaning. A
connector inside the scope is optional.

`asSequence`, `asTree`, and `asDag` take the same selected relations and nodes.
Every supplied relation must have both endpoints in the supplied node selection;
none is silently filtered. Each operation also rejects structures that do not
have the requested shape. Authors keep using the same node selection with
`node` and relation selection with `relation`; the checked views expose only
their validated rankings. The context-local
`rankOf ranking` operation reads the current matched node inside `node`; the
compiler rejects it outside the ranking's matching node scope. A sequence rank
is its zero-based position, a tree rank is its distance from the root, and a DAG
rank is its longest-path level. Here, `as` means "validate and expose as this
view," not an unchecked cast. There are no generic projections of the
complete input selections, aggregate graph counts, separate `forEach*`
traversal helpers, general graph handle, or all-pairs API. General graphs use
their original node and relation selections directly. If one relation kind
later spans several independent structures, an explicit endpoint-based
relation-selection operation must scope it before validation; the checked view
will not perform that filtering.

### Reusable values and finite choices

```haskell
bindContent  :: Render (Bound ContentValue)
variable     :: ... => Render (Variable value)
choice       :: forall value. ... => Render (Variable (Choice value))
global       :: ... => String -> value

data Choice value                  -- abstract finite decision
newtype RandomSeed = RandomSeed Int
```

`choice @FontStyle` and similar calls are limited to finite domains declared by
the library. The compiler owns their alternatives and stable serialization tokens;
there is no public `ChoiceDomain` class. Fresh `variable`, `choice`, and
`fontChoice` calls receive compiler-owned identities. `global` is the explicit
string-named sharing escape hatch. Custom constraint alternatives use `oneOf`, and
optional presence uses `sometimes`; add an explicit `choiceOf` operation later only
if a concrete use case needs a reusable author-defined category.

### Layout and box model

| Cluster                      | Public API                                                                                                                                                             |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- | --- |
| Numeric domains              | `Coord`, `Span`, `Offset`, `Scalar`, `VisualExpr role`, `Free`, `Unit`, `Angle`                                                                                        |
| Containers                   | `Vec2(..)`, `vec2`, `Bounds(..)`                                                                                                                                       |
| Edge and centre overloads    | `Left`, `left`, `Top`, `top`, `Right`, `right`, `Bottom`, `bottom`, `Width`, `width`, `Height`, `height`, `X`, `x`, `Y`, `y`, `Center(..)`, `center`, `size`, `bounds` |
| Fixed values and conversions | `at`, `by`, `shift`, `num`, `asCoord`, `asSpan`, `asScalar`                                                                                                            |
| Affine arithmetic            | `fromInteger`, `fromRational`, `(+)`, `(-)`, `(*)`, `(/)`, `(                                                                                                          | +   | )`  |
| Insets                       | `Insets`, `uniform`, `symmetric`, `edges`, `padding`, `margin`                                                                                                         |
| Child fitting                | `Axis(..)` = `Horizontal \| Vertical \| Both`; `ContentFit(..)` = `Hug \| Contain`; `contentFit`                                                                       |
| Parent-relative layout       | `Percent`, `percent`, `xAt`, `yAt`, `widthOf`, `heightOf`                                                                                                              |
| Canvas                       | `aspectRatio`                                                                                                                                                          |

`Bounds a` exposes `Bounds top left width height`; `Vec2 a` exposes `Vec2 x y`.
All solver-backed numeric values must have finite bounds by compile time.

### Styles and colour

```haskell
data NodeStyle                    -- abstract accumulated style

style        :: forall field input. ... => input -> Render ()
withoutStyle :: ...
styleCase    :: ...
styleFamily  :: String -> Render ()
styleOf      :: ...
```

`style @Field input` accepts a fixed field value, its matching solver `Choice`, or
the field's symbolic numeric or colour expression. A choice assignment is always
present and remains readable through `styleOf`. Unsupported field/input pairs are
type errors. `styleCase` maps a choice to different values or to conditional
absence. The input-conversion class and fixed-or-variable sum remain internal;
there is no public wrapper or separate choice setter.

| Cluster        | Public API                                                                                                                                                                                                                 |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Numeric fields | `Opacity`, `FontSize`, `Radius`, `StrokeWidth`, `Alpha`                                                                                                                                                                    |
| Paint fields   | `Fill`, `Stroke`                                                                                                                                                                                                           |
| Border         | `BorderStyle(..)` = `BorderNone \| BorderSolid \| BorderDashed \| BorderDotted \| BorderDouble`                                                                                                                            |
| Font filter    | `FontKind(..)` = `Monospace \| Proportional`; abstract `FontFilter`; `fontKind`; `fontChoice`                                                                                                                              |
| Font family    | `FontFamily(..)` = `FontInter \| FontSystem \| FontMono \| FontSerif \| FontSourceSans3 \| FontAtkinsonHyperlegibleNext \| FontSpaceGrotesk \| FontSourceSerif4 \| FontLiterata \| FontJetBrainsMonoNL \| FontIBMPlexMono` |
| Font weight    | `FontWeight(..)` = `FontWeightNormal \| FontWeightBold \| FontWeightBolder \| FontWeightLighter \| FontWeightNumber Int`                                                                                                   |
| Font style     | `FontStyle(..)` = `FontStyleNormal \| FontStyleItalic \| FontStyleOblique`                                                                                                                                                 |
| Text alignment | `TextAlign(..)` = `TextAlignLeft \| TextAlignCenter \| TextAlignRight \| TextAlignJustify`                                                                                                                                 |
| Colour         | `Hsl(..)`, `hue`, `saturation`, `lightness`, `sat`, `Color`                                                                                                                                                                |

```haskell
fontKind   :: FontKind -> FontFilter
fontChoice :: FontFilter -> Render (Variable (Choice FontFamily))
```

`BorderDouble` rendering and single-line `TextAlignJustify` remain open
decisions; neither may survive merely as a duplicate visual outcome.

### Constraints and alternatives

```haskell
data VisualConstraint              -- abstract
data VisualAlternative             -- abstract

ensure    :: VisualConstraint -> Render ()
encourage :: VisualConstraint -> Render ()

alternative :: String -> [VisualConstraint] -> VisualAlternative
oneOf      :: String -> VisualAlternative -> [VisualAlternative] -> Render ()
caseOf     :: Choice value -> (value -> [VisualConstraint]) -> Render ()

separatedBy :: Span -> Selected first -> Selected second -> VisualConstraint

(.<=.), (.>=.), (.==.) :: ...
(=|), (|=)             :: ...       -- directed affine gap bridge
(=/), (/=)             :: ...       -- symmetric bridge; lowering still open
```

`encourage` remains in the proposed inventory, but its meaning without nonlinear
optimization is still open.

## Deliberately absent from `Sverlin`

- Old facade names and aliases: `Choreography`, `TraceBuilder`,
  `VisualizationBuilder`, and `SlotHandle`.
- Compiler/runner machinery: `VisualTraceGraph`, `ViewGraph`,
  `runChoreography*`, `buildViewGraph`, `solveViewGraph*`, and
  `viewGraphStats`.
- Free facts and queries: `FactValue`, `Fact`, `Facts`, all `fact*` and
  `query*` operations, `Query`, `QueryInt`, `QueryField`, `(@:)`, query
  `(<&>)`, query `fromLabel`, and `bindInt`.
- Query-era selection and binding: `AnyPayload`, `PayloadQuery`, the old
  query-based `Select` class, `payload`, and `NodeBinding` (replaced by
  `SelectionBinding`).
- Mutable relation lifecycle: public `Relation`, `Unrelate`, and `unrelate`.
  Relations are compiler-owned and end with either stable endpoint owner.
- Legacy payload metadata: `PayloadView` and `payloadKind`.
- Specialized or wrapped code text: `codeContent`, `codeWrap`,
  `highlightCode`, `CodeRange`, `codeRange`, and `emphasizeCode`.
- Removed styles: `WhiteSpace(..)` and `ZIndex`.
- Orphan observation API: `Observe` and `observe`.
- Removed operator-persistence API: `CoreOperator`,
  `persistOperatorPayload`, and `operatorPayloadText`.
- Internal payload-unpacking family: `LinearPayload`, `withPayload`,
  `buildPayload`, `applyLinear1`, `applyLinear1Into`, `applyLinear2`, and
  `applyLinear2Into`.
- Solver choice-domain metadata: `ChoiceDomain`, `choiceDomain`, and
  `choiceToken`. Built-in choice domains and tokens are compiler-owned.
- Categorical style adapters and setters: `StyleChoice`, `FixedStyle`,
  `VariableStyle`, `styleFrom`, and `styleChoice`. The overloaded `style` accepts
  both fixed and solver-selected field values.
- Fixed-expression binding helper: `variableFrom`. Use an ordinary `let`; only
  `variable` creates a fresh solver value.

## Still preventing a fully final facade

1. Domain declaration names and packaging.
2. Exact `Relate` type parameters and operation signature.
3. Exact Domain declaration and type-class constraints for typed step identities.
4. Internal provenance representation and supporting constraint for values returned
   by `sometimes`.
5. Exact `TextBuilder` input and fragment signatures.
6. Whether three materialization operations remain separate.
7. The Render projection from a stable slot owner to its current occupant.
8. Connector and anchor APIs, graph-template APIs, and their sampling weights.
9. Affine meanings for `encourage` and the symmetric bridge.
10. Whether `BorderDouble` and `TextAlignJustify` remain public.
