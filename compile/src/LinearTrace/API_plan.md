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
fact construction, payload vocabulary, operator vocabulary, and queries shared
by Program and Render. Keep the declaration representation abstract so the
facade can validate a complete domain before executing a program or compiling
render rules.

Move the following existing interfaces into Domain:

- Facts and queries: `FactValue`, `Fact`, `Facts`, `emptyFacts`, `factAtom`,
  `factSymbol`, `factInt`, `factsUnion`, `factsToList`, `PayloadView`,
  `Traceable`, `Query`, `QueryInt`, `emptyQuery`, `queryAtom`, `queryInt`,
  `queryFacts`, `payload`, `QueryField`, `(@:)`, `(<&>)`, and `fromLabel`.
- Payload and operator vocabulary: `Payload`, `LUnit`, `LBool`, `LInt`,
  `LDouble`, `LString`, `LOperator`, `CoreOperator`, `LinearPayload`,
  `Applicable1`, `Applicable2`, `applyLinear1`, `applyLinear1Into`,
  `applyLinear2`, and `applyLinear2Into`.

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

- Program context: `Program` (replacing `Choreography`).
- Linear resources: `Block`, `SlotHandle`, and `Pending`; `Payload` is defined
  by Domain and consumed here.
- Lifecycle operations: `create`, `copy`, `use`, `apply1`, `apply2`, `replace`,
  `materialize`, `materializeWithTags`, `commit`, `destroy`, and `checkpoint`.
- Lifecycle results: `OneUse`, `Create`, `Observe`, `Use`, `Copy`, `Replace`,
  `Apply1`, `Apply2`, `Destroy`, `Seal`, `Unseal`, `(<$>)`, and `(<*>)`.

Restore the lowercase `seal` and `unseal` operations alongside the existing
`Seal` and `Unseal` result types. Keep `SlotHandle` opaque and linear. Do not
add declaration, read, write, variable, or other workflow helpers to Program;
higher-level APIs and authored programs compose those behaviors from the
general primitives.

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

Restore public `seal`. It consumes a live owner and child and returns the same
owner plus an opaque occupied `SlotHandle`. The trace records their association:
the owner identifies a stable storage location and the child identifies its
current occupant. Render can constrain that occupant to the owner's location.

```haskell
Seal owner slot <- seal owner value
```

##### Unseal

Restore public `unseal`. It consumes the owner and occupied slot and returns the
same owner plus the stored child. It exposes the occupant for arbitrary Program
composition—copy, replace, use, destroy, or reseal—without embedding a fixed
read/write abstraction in the core language.

```haskell
Unseal owner value <- unseal owner slot
```

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

Content interfaces are `ContentValue`, `text`, `content`, `fitText`,
`codeContent`, `codeWrap`, `highlightCode`, `CodeRange`, `codeRange`, and
`emphasizeCode`.

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
node sourceSelection $ do
  codeWrap $
    highlightCode "haskell" $
      emphasizeCode "step" [codeRange 0 12] $
        codeContent (text "x = x + 1")
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
`styleOf`, `NodeStyle`, `Opacity`, `ZIndex`, `FontSize`, `Radius`, `StrokeWidth`,
`Alpha`, `Fill`, `Stroke`, `BorderStyle`, `FontFamily`, `FontWeight`,
`FontStyle`, `TextAlign`, `WhiteSpace`, `Hsl`, `Color`, and `sat`.

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

- `seal` consumes a live owner and live child, then returns `Seal` containing
  the same owner capability and a new occupied `Slot`.
- `unseal` consumes a live owner and occupied `Slot`, then returns `Unseal`
  containing the same owner capability and stored child.
- Preserve owner and child identity in `TraceSeal` and `TraceUnseal`; the owner
  represents the stable storage location while occupants may change.
- Do not encode declaration, read, or write semantics in these primitives.
  Copy-and-reseal and replace-and-reseal are author-level compositions.

## View and rendering

## Compiler and runtime boundary

## Migration and compatibility

## Examples and tests

## Implementation order

## Open decisions
