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
materialized block; Render selects that kind.

```haskell
program = do
  Create pending <- create (LInt 3)
  value <- materialize valueKind pending
  checkpoint "shown"
  Destroy <- destroy value
  checkpoint "removed"

render = do
  Selected values <- select valueKind
  node values $ fitText (text "value")
```

## Domain

Domain declares the semantic vocabulary shared by Program and Render.

### Declarations

```haskell
data Domain a
data Kind tag                         -- abstract block classification
data RelationKind source target      -- abstract location relation
```

**Open:** final declaration operations for payload types, kinds, operators, and
ordered or symmetric relation kinds. Names such as `declarePayload`,
`declareKind`, `declareOperator`, and `declareRelation` in examples are
placeholders, not settled exports.

### Payloads

```haskell
type family Payload tag = payload | payload -> tag
class Traceable tag

newtype PayloadView = PayloadView { payloadKind :: String }

data LUnit tag              = LUnit
data LBool tag              = LBool Bool
data LInt tag               = LInt Int
data LDouble tag            = LDouble Double
data LString tag            = LString String
data LOperator operator tag = LOperator
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
data Relation                   -- abstract active relation; type parameters open
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
```

`Relate` and `Unrelate` are public result wrappers. Their exact type parameters
remain **open**; their pattern shapes are settled:

```haskell
Relate sourceSlot targetSlot relation
Unrelate sourceSlot targetSlot
```

TODO question: do Relate semantics offer anything over Slot semantics? double check this.

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

checkpoint :: String -> Program ()

(<$>) :: (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
(<*>) :: OneUse (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
```

TODO question: where is step? is API_plan.md covered properly here?

**Open signatures:** `relate` consumes and reissues two matching `Slot`s and
returns one new `Relation`; `unrelate` consumes that `Relation` plus the current
two slots and reissues the slots.

```haskell
relate   :: RelationKind source target -> ... -> Program (Relate ...)
unrelate :: Relation ... %1 -> ... -> Program (Unrelate ...)
```

**Open vocabulary:** reusable named Program steps and their typed identities.
No step name is a proposed export yet.

## Render

Render declares selections, nodes, text, relations, layout, style, and visual
constraints independently of Program execution.

### Rules, selections, and nodes

```haskell
data Render a
data MatchSpec                    -- abstract compiled rules
data Selected tag                 -- abstract selected node or node set
data Variable a    = Variable a
data Bound a       = Bound a
data NodeBinding a = Selected a
data GeneratedNode
data CanvasNode

select    :: Kind tag -> Render (NodeBinding (Selected tag))
visualize :: Render () -> MatchSpec

class Node input result
node   :: Node input result => input -> result
self   :: Render (NodeBinding (Selected GeneratedNode))
canvas :: Selected CanvasNode
```

### Text

```haskell
data ContentValue                 -- abstract fixed or bound text
text    :: String -> ContentValue
content :: ... -> Render ()
fitText :: ... -> Render ()       -- one line; font size may vary within bounds

data TextBuilder a
literal      :: String -> TextBuilder ()
fragment     :: ...               -- fragment @Step "text"
fragmentMany :: ...               -- fragmentMany @'[StepA, StepB] "text"
intText      :: FixedInt -> ContentValue
```

**Open signatures:** `content` and `fitText` accept ordinary `ContentValue` and
composed `TextBuilder` input; the exact supporting overload and typed step
representation are not settled. Every text node remains one independently
positioned, shaped line.

### Relations and graph views

```haskell
data Relations source target
data Graph node
data Sequence node
data Tree node
data Dag node
data SiblingOrder node
data FixedInt

relationsOf :: RelationKind source target -> Render (Relations source target)
forEachRelation :: Relations source target -> (Selected source -> Selected target -> Render ()) -> Render ()
forEachSourceGroup :: Relations source target -> (Selected source -> Selected target -> Render ()) -> Render ()
graphOf :: Selected node -> Relations node node -> Render (Graph node)

class GraphView graph node | graph -> node where
  forEachNode     :: graph -> (Selected node -> Render ()) -> Render ()
  forEachEdge     :: graph -> (Selected node -> Selected node -> Render ()) -> Render ()
  forEachNodePair :: graph -> (Selected node -> Selected node -> Render ()) -> Render ()
  nodeCount       :: graph -> FixedInt
  edgeCount       :: graph -> FixedInt

requireSequence :: Graph node -> Render (Sequence node)
positionOf      :: Sequence node -> Selected node -> FixedInt

requireTree   :: Graph node -> Render (Tree node)
rootOf        :: Tree node -> Selected node
depthOf       :: Tree node -> Selected node -> FixedInt
childCountOf  :: Tree node -> Selected node -> FixedInt
subtreeSizeOf :: Tree node -> Selected node -> FixedInt

orderChildrenBy    :: RelationKind node node -> Tree node -> Render (SiblingOrder node)
forEachSiblingPair :: SiblingOrder node -> (Selected node -> Selected node -> Render ()) -> Render ()
siblingPositionOf  :: SiblingOrder node -> Selected node -> FixedInt

requireDag :: Graph node -> Render (Dag node)
rootsOf    :: Dag node -> Selected node
leavesOf   :: Dag node -> Selected node
levelOf    :: Dag node -> Selected node -> FixedInt

asScalar :: FixedInt -> Scalar
intText  :: FixedInt -> ContentValue
```

### Reusable values and finite choices

```haskell
bindContent  :: Render (Bound ContentValue)
variable     :: ... => Render (Variable value)
variableFrom :: value -> Render (Variable value)
choice       :: ChoiceDomain value => Render (Variable (Choice value))
global       :: ... => String -> value

class ChoiceDomain value where
  choiceDomain :: [value]
  choiceToken  :: value -> String

data Choice value                  -- abstract finite decision
newtype RandomSeed = RandomSeed Int
```

Fresh `variable`, `choice`, and `fontChoice` calls receive compiler-owned
identities. `global` is the explicit string-named sharing escape hatch.

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
data StyleChoice value
  = FixedStyle value
  | VariableStyle (Choice value)

data NodeStyle                    -- abstract accumulated style

style        :: ...
withoutStyle :: ...
styleCase    :: ...
styleFamily  :: String -> Render ()
styleOf      :: ...
```

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
caseOf     :: ChoiceDomain value => Choice value -> (value -> [VisualConstraint]) -> Render ()

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
- Query-era selection: `AnyPayload`, `PayloadQuery`, `Select`, and `payload`.
- Specialized or wrapped code text: `codeContent`, `codeWrap`,
  `highlightCode`, `CodeRange`, `codeRange`, and `emphasizeCode`.
- Removed styles: `WhiteSpace(..)` and `ZIndex`.
- Orphan observation API: `Observe` and `observe`.
- Removed operator-persistence API: `CoreOperator`,
  `persistOperatorPayload`, and `operatorPayloadText`.
- Internal payload-unpacking family: `LinearPayload`, `withPayload`,
  `buildPayload`, `applyLinear1`, `applyLinear1Into`, `applyLinear2`, and
  `applyLinear2Into`.

## Still preventing a fully final facade

1. Domain declaration names and packaging.
2. Exact `Relation`/`Relate`/`Unrelate` type parameters and operation signatures.
3. Program step vocabulary and the typed step reference used by text fragments.
4. Exact `TextBuilder` input and fragment signatures.
5. Whether three materialization operations remain separate.
6. The Render projection from a stable slot owner to its current occupant.
7. Connector and anchor APIs, graph-template APIs, and their sampling weights.
8. Affine meanings for `encourage` and the symmetric bridge.
9. Whether `BorderDouble` and `TextAlignJustify` remain public.
