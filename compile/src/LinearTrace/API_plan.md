# LinearTrace API refactor plan

This file records concise, agreed implementation instructions. Keep historical
evidence and extended rationale in `API_refactoring.md`; update this plan as
decisions are made.

Keep the compact proposed-facade inventory in
[API_plan_list.md](API_plan_list.md) synchronized whenever a public API is
added, removed, renamed, or resolved here.

## Goals

## Public API

This section is the declarative target surface. It must restate every public
interface, including interfaces retained unchanged and agreed additions. The
generated DSL API index remains authoritative for exact inferred signatures;
this plan records grouping, purpose, and intended composition.

The authored API comprises exactly three conceptual parts, each with its own
builder/section/monadic context:

1. `Domain` declares semantic vocabulary and matching language.
2. `Program` constructs the immutable linear trace.
3. `Render` declares how domain values and program events are visualized.

The new `Sverlin` module is the supported author facade. It wires these three
parts together, re-exports their intended author vocabulary, and owns the
maintainable overview and composition documentation. `Choreography` must
disappear as a public API name; do not preserve it as the conceptual umbrella.

### Domain

Add a new Domain module and builder context. Domain owns semantic declarations,
typed classification, payload vocabulary, and operator and relation vocabulary
shared by Program and Render. Keep the declaration representation abstract so
the facade can validate a complete domain before executing a program or
compiling render rules.

#### `Kind`

```haskell
data Kind tag
```

`Kind tag` is a Domain-declared classification for a materialized `Block tag`.
It distinguishes semantic roles that share a trace tag: for example,
`valueKind` and `resultKind` may both have type `Kind Number`. The type prevents
a kind declared for `Number` from being attached to or used to select a
`Block SourceCode`. Each classified block has exactly one `Kind`; `commit`
creates a deliberately unclassified block.

Keep compound selection outside the baseline. Use a more specific kind such as
`availableValueKind` when one exclusive role needs its own Render rule, and use
a `RelationKind` for membership or association. If a concrete visualization
later requires independent, overlapping classifications on the same block, add
an explicit typed selector then rather than preserving the old general query
language now.

Kinds classify blocks; they do not store payload data or connect blocks. Use a
typed payload for a number or string and a `RelationKind` for membership,
ordering, or association. In particular, do not declare one kind per array
index, address, or numeric value. If Render later needs to filter or constrain
such data, add a typed entity-bound property interface for that concrete use
case.

The current `Fact`, `Facts`, and `Query` representations may remain temporarily
as compiler internals while this API is migrated. `Kind` declarations, rather
than free strings or overloaded labels, are the authored contract; fact
construction, query conversion, and numeric query binding are not re-exported
by `Sverlin`.

#### `Traceable` and `Payload`

```haskell
class Traceable tag where
  type Payload tag = payload | payload -> tag
```

`tag` is the semantic trace type used by `Block tag`, such as `Number`.
One `Traceable` instance declares both that the type can participate in the
trace and the linear value stored by its blocks. `Payload tag` is the associated
type selected by that instance; it is not a declaration value passed to Program
or Render. In this example, `Number` is an author-defined name for one semantic
value type; it is not a built-in Sverlin type:

```haskell
data Number

instance Traceable Number where
  type Payload Number = LInt Number
```

Here, `Number` identifies the trace type, `Payload Number` reduces to the
carrier type `LInt Number`, and `LInt 7` is a concrete payload value. The
compiler accepts an instance only when its associated payload uses a supported
wrapper that Core can preserve safely. A `Kind Number` classifies such blocks
without changing their payload representation.

This differs from `RelationKind`, which is a first-class Domain declaration
such as `Adjacent` that authors pass to `relate` and `select`. The semantic
parallel is between `Kind` and `RelationKind`; `Payload` describes stored data.
Do not rename it to `PayloadKind`, which would imply another classification
label. If the associated type later needs a more explicit name, `PayloadOf tag`
is the accurate alternative.

#### `RelationKind`

```haskell
data RelationKind source target
```

`RelationKind` is an abstract semantic label for a relation between two
persistent slot locations. `source` and `target` are the endpoint owner types,
so `ProbeAt :: RelationKind Probe Cell` cannot be applied to two cells or to a
probe and an array.

Each relation declaration also records one of these endpoint meanings:

- **Ordered endpoints:** the first and second endpoints have different roles,
  so swapping them changes the relation. Examples are `Contains` (container,
  member), `Next` or `Adjacent` (previous, next), `ParentOf` (parent, child),
  `DependsOn` (dependent, prerequisite), and `ProbeAt` (probe, cell). Ordered
  endpoints do not imply left-to-right, top-to-bottom, or any other visual
  direction; Render chooses coordinates and connector appearance separately.
- **Symmetric endpoints:** both endpoints have the same role, so
  `ConnectedTo a b` and `ConnectedTo b a` mean the same relation. A symmetric
  kind must use the same owner type at both endpoints. Program treats the
  reversed pair as a duplicate. Render may emit the endpoints in a stable order
  for deterministic output, but that order has no semantic meaning.

This distinction belongs to Domain because it affects Program validation as
well as Render traversal. Sequences, trees, and DAGs require ordered endpoints;
applying one of those operations to a symmetric relation is a source-level
error. General relation rendering accepts either meaning.

Endpoint meaning is declaration metadata rather than a public type parameter.
The relation-facing target types are therefore `RelationKind source target`,
and Render's `Relations source target`; Program records relations through
`relate` but exposes no relation handle. Authors do not carry `Directed` or
`Undirected` through signatures. The exact declaration combinators that choose
ordered or symmetric endpoints remain open with the rest of Domain.

Move the following existing interfaces into Domain:

- Classification: add `Kind tag` as defined above. Do not re-export
  `FactValue`, `Fact`, `Facts`, `emptyFacts`,
  `factAtom`, `factSymbol`, `factInt`, `factsUnion`, `factsToList`, `Query`,
  `QueryInt`, `emptyQuery`, `queryAtom`, `queryInt`, `queryFacts`, `QueryField`,
  `(@:)`, query conjunction `(<&>)`, or query `fromLabel` construction.
- Relations: `RelationKind source target`; each Domain declares its concrete
  relation kinds, including their ordered or symmetric endpoint meaning, and
  shares them with Program and Render.
- Payload and operator vocabulary: `Traceable`, its associated type `Payload`,
  `LUnit`, `LBool`, `LInt`, `LDouble`, `LString`, `LOperator`, `Applicable1`,
  and `Applicable2`.

Do not re-export `PayloadView` or `payloadKind`. They are legacy wrappers around
a compiler-derived type-name string, not authored payload data or a Domain
`Kind`. Render receives content through its binding API and classifications
through typed `Kind` declarations. Any temporary snapshot equivalent remains
compiler-internal.

Do not re-export `LinearPayload`, `withPayload`, `buildPayload`,
`applyLinear1`, `applyLinear1Into`, `applyLinear2`, or `applyLinear2Into` from
`Sverlin`. The helper functions all expose `LinearPayload` constraints, so
hiding only the class would still leak the internal payload-unpacking
abstraction through public signatures. Keep that family compiler-internal.
Authors define operator behavior through `Applicable1` and `Applicable2`,
pattern matching the public `LUnit`, `LBool`, `LInt`, `LDouble`, `LString`, or
`LOperator` wrappers and constructing the result wrapper directly.

`LOperator` is a stateless marker: its operator type selects the corresponding
`Applicable1` or `Applicable2` instance, but it carries no runtime value.
Remove `CoreOperator`, `persistOperatorPayload`, and `operatorPayloadText` from
the public API; Core persists the marker internally. Operator parameters are
ordinary operands, so a scale factor such as `2.5` is a traceable `Number`
input rather than hidden state inside a `Scale` operator. Operator spellings
such as `+`, `==`, or `equals` belong to the particular Render mapping.

The exact declaration combinators and concrete builder type name are still to
be designed. `Traceable` instances are the payload declarations, so Domain does
not repeat them with `declarePayload`. The remaining declarations must support
this separation without requiring authors to import internal Core modules.

```haskell
domain :: Domain ()
domain = do
  -- Declare kinds, operators, and relation kinds used by the program and
  -- render rules. Exact declaration combinators remain open.
  declareKind valueKind
  declareKind resultKind
  declareOperator @Add
  declareSteps @'[Shown, Removed]
```

Illustrative declared values are typed and shared by Program and Render:

```haskell
valueKind :: Kind Number
resultKind :: Kind Number
availableValueKind :: Kind Number
```

The exact declaration combinators and how declared values are packaged for the
three builders remain open. This includes the working `declareSteps` spelling for
the finite set of typed step identities. Declarations must provide stable names for
diagnostics and serialization without requiring authors to repeat string keys at
each use.

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
- Linear resources: `Block`, `Slot`, and `Pending`; `Payload` and relation-kind
  vocabulary are defined by Domain and consumed here.
- Lifecycle operations: `create`, `copy`, `use`, `apply1`, `apply2`, `replace`,
  `seal`, `unseal`, `relate`, `materialize`, `materializeWithKind`, `commit`,
  and `destroy`.
- Named Program composition: typed, nestable `step`.
- Lifecycle results: `OneUse`, `Create`, `Use`, `Copy`, `Replace`, `Apply1`,
  `Apply2`, `Destroy`, `Seal`, `Unseal`, `Relate`, `(<$>)`, and `(<*>)`.

Restore the lowercase `seal` and `unseal` operations alongside the existing
`Seal` and `Unseal` result types. Add `relate` only for slot locations; do not
overload it for blocks. `Slot` remains a linear value supplied by lifecycle
operations: authors cannot construct it, inspect its internal identity, or
extract a stored child except through the corresponding Program operation. A
relation is compiler-owned trace state rather than another public linear token.
Do not add declaration, read, write, variable, or other workflow helpers to
Program; higher-level APIs and authored programs compose those behaviors from
the general primitives.

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
duplicate <- materialize copiedValueKind pendingCopy
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

Remove the orphan `Observe` result wrapper from `Sverlin`; there is no public
`observe` operation and no distinct authored lifecycle behavior to accompany
it.

TODO consider how Use should be used, or if it should be removed. does it
confer semantics other lifecycle ops don't already permit?

##### Apply one

`apply1` consumes an operator block and one argument block, then produces one
pending result. It makes unary computation provenance explicit so Render can
depict the operator, input, and result rather than infer their relationship
from payload text.

```haskell
Apply1 pendingResult <- apply1 negateOperator argument
result <- materialize resultKind pendingResult
```

##### Apply two

`apply2` consumes an operator block and two argument blocks, then produces one
pending result. It records both ordered inputs, enabling Render to visualize a
binary computation and its data flow.

```haskell
Apply2 pendingSum <- apply2 addOperator leftOperand rightOperand
sumBlock <- materialize sumKind pendingSum
```

##### Replace

`replace` consumes an existing block and a compatible pending value, producing
a new pending value whose event records continuation from old identity to new
identity. It describes an evolving trace entity. Render can keep the old visual
instance continuous while updating its payload, kind, content, and geometry.

```haskell
Replace pendingNext <- replace current pendingValue
next <- materialize currentValueKind pendingNext
```

Replacement is distinct from storing an independent live value in a slot:
replacement continues the old occupant, while slot storage preserves the
location and may adopt a different occupant lineage.

##### Destroy

`destroy` consumes a live block without producing a successor. It records the
end of that value's lifetime, allowing Render to remove or animate the exiting
visual instance in the corresponding exposed frame.

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
returns both slots unchanged. Consuming and returning the slots lets the
compiler read their stable owner identities without giving the relation
ownership of either child. The compiler records the relation against the owner
`BlockId`s that identify the two locations, not the `BlockId`s of their current
occupants. No public relation token is returned.

```haskell
Relate sourceSlot1 targetSlot1 <-
  relate DependsOn sourceSlot0 targetSlot0
```

The consume-and-reissue step is the Program event at which the semantic relation
begins. `relate` may occur after either location has appeared in an earlier exposed
frame: it does not mutate either input `Slot` in place, but returns successor
capabilities for the same persistent locations. Once created, the relation is
anchored to the stable owners rather than to those particular `Slot` values.

Render constraints derived from the relation are not added to the solver only from
that frame onward. The compiler sees the whole trace and includes them in the
single constraint system over the overlapping lifetimes of the two stable owners.
The relation itself, including an optional connector, is visible only while the
semantic relation is active. A rule discovered later can therefore affect an
earlier layout without showing the relation there. If it contradicts another rule
over either lifetime, compilation reports the incompatible source constraints;
trying another random sample cannot repair an empty feasible region.

At most one relation of the same kind may be active between the same endpoint
locations. For a symmetric kind, reversing the arguments is the same pair.
Rejecting duplicates makes structural graph checks operate on unique
associations and prevents Render from applying the same edge rule twice to an
indistinguishable pair. The same location may still relate to several neighbours
or use several different relation kinds.

The June baseline supports one slot per owner, so the owner `BlockId` is the
complete location identity. Unsealing and resealing through that owner
reconstructs a `Slot` for the same location. Its relations and their Render
constraints remain attached to that stable owner while the slot is unsealed,
temporarily has no stored occupant, or is resealed with a replacement. Multiple
slots per owner are outside this restoration and require a separate design
discussion; they must not cause `SlotId` to leak into the authored facade by
default.

A relation remains active while both endpoint owners are live and ends
automatically when either owner is destroyed. The relation's visible lifetime ends
there; its geometry was already part of the fixed constraint system for the owners'
overlapping lifetimes. There is no public relation token or removal operation. A
slot may participate in several relations by threading each successor through later
`relate` calls.

A `Slot` is not a special relation. It owns the right to recover or replace one
stored child at a persistent location. A relation is compiler-owned semantic
state attached to two stable owner locations and owns neither endpoint nor
occupant.

#### Materialization

Materialization resolves the `Pending` obligations produced by lifecycle
operations. It assigns a block identity, completes the pending trace event, and
optionally attaches declared Domain kinds used by Render selection.

##### Materialize

`materialize` resolves a `Pending` value into a live `Block` and attaches one
declared `Kind` of the same trace type. It gives the value its stable block
identity and completes the pending create/copy/apply/replace event so Render can
select it.

```haskell
materialize :: Kind tag -> Pending tag %1 -> Program (Block tag)
```

```haskell
block <- materialize availableValueKind pending
```

##### Materialize with a payload-derived kind

`materializeWithKind` chooses one declared kind from the payload being
materialized. The classifier may choose among predeclared finite
classifications such as `negativeValueKind` and `nonNegativeValueKind`; it must
not turn each numeric payload into a new kind.

```haskell
materializeWithKind
  :: (Payload tag -> Kind tag)
  -> Pending tag %1
  -> Program (Block tag)
```

```haskell
classified <- materializeWithKind classifySign pending
```

##### Commit

`commit` materializes a pending value without attaching Domain kinds. Use it
for traceable intermediate values that Render addresses only through operation
lineage, or that should not participate in semantic selection.

```haskell
unclassified <- commit pendingUnclassified
```

#### Named steps

A Program is composed from typed, reusable steps. `step @Name action` records the
identity and event span of the action, returns its result unchanged, and may nest
inside another step. The exact declaration constraint remains open, but the target
shape is:

```haskell
step :: forall name a. ... => Program a %1 -> Program a
```

Step identities are shared with Render. `frame @Name` can expose an occurrence as a
presentation frame, while `fragment @Name` can highlight the corresponding source
range. Program itself does not decide which steps become frames, and the target API
has no public `checkpoint :: String -> Program ()`.

Complete logical operations should normally be steps. In particular, an ordinary
slot workflow should unseal and reseal within one step unless an empty storage
location is deliberately part of the trace.

#### Complete Program

Every linear resource and pending obligation must be consumed by the completed
`Program`. A typical definition composes the primitives above; higher-level
domain libraries may package such compositions without adding specialized
operations to the general Program interface.

```haskell
program :: Program ()
program = do
  value <- step @Created $ do
    Create pending <- create initialValue
    materialize valueKind pending
  step @Removed $ do
    Destroy <- destroy value
    pure ()
```

### Render

Render owns the visual-rule builder, semantic selection, hierarchy, content,
layout, style, and visual constraints. Rename the author-facing
`VisualizationBuilder` context to `Render`. A separate compiled rule/spec type
may remain internally, but authored signatures and documentation must use
Render terminology.

#### Conditional composition

Render decides which tracked view components are required or optional:

```haskell
always    :: ... => Render a -> Render a
sometimes :: ... => Render a -> Render a
```

`always` includes the wrapped component without creating a choice. `sometimes`
creates an equal-weighted seeded include/omit choice at the component's current
match scope. These wrappers are general over values whose presence Render can
track. A value returned by `sometimes` remains a symbolic handle at authoring time
and carries a hidden presence condition. Any later component that consumes it
inherits that condition automatically:

```haskell
Selected explanation <- sometimes $ node $ content (text "comparison failed")

Selected detail <- node $ do
  Selected current <- self
  content (text "try the next element")
  ensure $ top current .==. bottom explanation + by 12

Selected counter <- node $ content (text "iteration")
```

When a seed omits `explanation`, it also omits `detail` and the dependent
constraint; `counter` remains. A component consuming several conditional values is
guarded by all of their presence conditions. A `Render ()` body groups all effects
it emits under the wrapper's one condition. Authors do not handle `Maybe` or repeat
guards. The compiler keeps the presence metadata on abstract Render values and
diagnoses an attempt to pass an optional value through an ordinary Haskell value
that cannot retain it. The exact private type-class constraint on `a` remains open;
it must not become another authored vocabulary.

`always` preserves any condition inherited from an enclosing optional component;
it cannot force an absent dependency to exist. Geometry-neutral choices such as
frame inclusion are sampled separately from the affine layout space. When an
optional component contributes geometry, its include and omit cases are explicit
authored design branches, and an infeasible include case may be removed without
changing the omit case.

#### Frames

```haskell
frame :: forall name. ... => Render ()
```

`frame @Name` makes each occurrence of that typed Program step a candidate
presentation frame. Execution order, including repeated steps, determines frame
order. Wrapping it in `always` includes every occurrence; wrapping it in
`sometimes` gives each occurrence an independent seeded include/omit choice:

```haskell
always $ frame @InitializeTarget
sometimes $ frame @CompareTarget
always $ frame @FinishSearch
```

Frame inclusion is geometry-neutral, so these choices are sampled separately from
the affine layout space.

#### Rules, selections, and nodes

The visualization interface declares reusable rules independently of program
execution. Retain `MatchSpec`, `Selected`, `Variable`, `Bound`, `GeneratedNode`,
`CanvasNode`, `select`, `visualize`, `Node`, `node`, `self`, and `canvas`.
Generalize the node-specific `NodeBinding` wrapper to `SelectionBinding`, then
replace the query-based `Select`, `AnyPayload`, and `PayloadQuery` surface with
typed block-kind and relation-kind selection:

```haskell
data SelectionBinding a = Selected a

class Selectable selector result | selector -> result where
  select :: selector -> Render (SelectionBinding result)

instance Selectable (Kind tag) (Selected tag)
instance Selectable (RelationKind source target) (Relations source target)

class Node input result | input -> result where
  node :: input -> result

instance Node (Selected tag) (Render () -> Render ())
instance Node (Render ()) (Render (SelectionBinding (Selected GeneratedNode)))

self   :: Render (SelectionBinding (Selected GeneratedNode))
canvas :: Selected CanvasNode
```

`Selectable` has only these library-provided cases in the target interface;
authors declare `Kind` and `RelationKind` values rather than selection
instances. A `Kind` determines the selected payload type, so block selection no
longer needs a type application such as `select @Number`. It selects every live
block in the current exposed frame with that one declared kind. A `RelationKind`
selects every active relation of that kind in the same frame; the resulting
`Relations` value is documented below. Both uses have the same author-facing
binding form:

```haskell
Selected values <- select valueKind
Selected adjacentLinks <- select Adjacent
```

`SelectionBinding` only supports the unrestricted `Selected` pattern used to
name a selection. Selecting a relation does not make it a visual node, and
`node` accepts only node selections or a generated-node body. The two
library-provided `Node` instances are the complete supported set; authors do not
define more. `node selected body` applies the body once per matched node. A
trace-selected node is terminal and cannot contain children. `node body`
creates one generated node in the current Render scope and returns its handle
through `SelectionBinding`; generated nodes may contain selected or nested
nodes.

`self` retrieves the current generated node's handle from inside `body`, before
`node` returns it; using `self` at the root or inside a trace-selected node is a
source-level error. `canvas` is the persistent root handle for geometry
expressions and is not emitted as a child node. Compound classification,
selection across unrelated payload types, and exact payload-value predicates
are outside this baseline; declare separate typed rules, or add a typed selector
or predicate API later when a concrete use case requires one.

Retain the general content interfaces `ContentValue`, `text`, `content`, and
`fitText`, and add the structural-value conversion `asText` documented below.
`content` shapes one line at its authored or theme-default fixed font size. The
node's normal `Hug` sizing makes the box follow that shaped line and its padding,
so text does not grow merely because a larger box is available.
`fitText` instead opts into bounded font-size variation and requires the line to
remain inside its content box. It uses an explicitly styled bounded `FontSize`
variable when supplied; otherwise it creates a fresh size within the
theme-defined fit range. A fixed `FontSize` pins the size. `fitText` neither
maximizes the size nor inserts line breaks.

```haskell
Selected title <- node $ do
  content (text "Search result")
  padding (uniform (by 8))

Variable labelSize <- variable @Span
ensure $ labelSize .>=. by 14
ensure $ labelSize .<=. by 28

Selected label <- node $ do
  fitText (text "Search result")
  style @FontSize labelSize
  width (by 160)
  height (by 40)
```

The first node hugs fixed-size text. The second samples any size from 14 to 28
that fits; it is not forced to 28. Remove the specialized `codeContent`, `codeWrap`,
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

Font selection applies to the complete shaped line. The catalog-filtered
`FontFamily`, `FontKind`, and `FontFilter` interfaces are documented together
under style authoring below. A `fragment` does not switch font family: code and
explanation text that require different font kinds use separate positioned
nodes, as below. Mixed-font shaping within one line would need an explicit
font-run API and remains outside this baseline.

For example, a rendered comparison line can associate each semantic part of the
displayed code with the Program steps that produce or use it. The extended
example renders an explanatory line and a code block with two indentation
levels:

```haskell
comparisonText :: TextBuilder ()
comparisonText = do
  literal "if ("
  fragment @ReadElement "A[i]"
  fragmentMany @'[CompareTarget, CreateEqualOperator, ApplyEquality] " == "
  fragment @ReadTarget "target"
  literal ") {"

render :: Render ()
render = do
  Variable codeFont <- fontChoice (fontKind Monospace)
  Variable explanationFont <- fontChoice (fontKind Proportional)
  Variable codeSize <- variable @Span

  Selected explanationLine <- node $ do
    fitText (text "Compare each element with the target; return its index when they match.")
    style @FontFamily explanationFont

  Selected loopLine <- node $ do
    fitText (literal "for (int i = 0; i < n; ++i) {")
    style @FontFamily codeFont
    style @FontSize codeSize

  Selected comparisonLine <- node $ do
    fitText comparisonText
    style @FontFamily codeFont
    style @FontSize codeSize

  Selected returnLine <- node $ do
    fitText (literal "return i;")
    style @FontFamily codeFont
    style @FontSize codeSize

  Selected innerCloseLine <- node $ do
    fitText (literal "}")
    style @FontFamily codeFont
    style @FontSize codeSize

  Selected outerCloseLine <- node $ do
    fitText (literal "}")
    style @FontFamily codeFont
    style @FontSize codeSize

  ensure $ codeSize .>=. by 14
  ensure $ codeSize .<=. by 24
  ensure $ left explanationLine .==. at 36
  ensure $ top explanationLine .==. at 64
  ensure $ left loopLine .==. left explanationLine
  ensure $ top loopLine .==. bottom explanationLine + shift 16
  ensure $ left comparisonLine .==. left loopLine + shift 24
  ensure $ top comparisonLine .==. bottom loopLine + shift 4
  ensure $ left returnLine .==. left loopLine + shift 48
  ensure $ top returnLine .==. bottom comparisonLine + shift 4
  ensure $ left innerCloseLine .==. left comparisonLine
  ensure $ top innerCloseLine .==. bottom returnLine + shift 4
  ensure $ left outerCloseLine .==. left loopLine
  ensure $ top outerCloseLine .==. bottom innerCloseLine + shift 4
```

The `comparisonText` builder produces one shaped line,
`if (A[i] == target) {`, plus compiler-owned source ranges. `A[i]` is associated
with `ReadElement`, `target` with `ReadTarget`, and `==` with all three listed
step definitions. Authors do not
calculate character offsets. During playback, the default interpretation is
that a fragment is active while any associated step definition is active;
`fragmentMany` therefore uses logical OR. A repeated Program step activates the
same associated fragment for each runtime occurrence of that definition.

The indentation is geometric: each deeper line has an affine horizontal offset
from `loopLine`. It is not encoded as leading spaces, so changing the sampled
font cannot change the block structure. All code lines reuse `codeFont` and
`codeSize`, while `explanationLine` has an independently sampled proportional
family. The shared size remains free between 14 and 24 units and every shaped
code line contributes a fit constraint; the longest line therefore limits the
feasible upper size without turning size into another discrete font branch.

The compiler maps logical source ranges through bidirectional reordering and
HarfBuzz glyph clusters after shaping. If one glyph cluster, such as a ligature
or base character plus combining mark, crosses a fragment boundary, associate
the complete cluster with the union of the overlapping fragment step
definitions. Do not split the glyph or reshape the fragments independently.

There are three reasonable highlighting surfaces:

1. **Implicit active-fragment emphasis (recommended baseline).** `fragment` and
   `fragmentMany` need no additional appearance arguments. The compiled IR
   records stable step-definition identities and glyph-cluster ranges, and the
   presentation theme applies one standard active-fragment treatment. This is
   the smallest API and gives generated source a reliable default.
2. **Named fragment roles.** A possible later `fragmentAs` variant could attach
   a general role such as `PrimaryEmphasis` or `SecondaryEmphasis`, for example
   `fragmentAs @ReadElement PrimaryEmphasis "A[i]"`. The theme would map the
   role and active state to presentation without embedding colours in Program
   semantics. This supports a small number of intentional emphasis levels while
   preserving automatic step activation.
3. **Returned fragment handles.** `fragment` could instead return a typed
   `FragmentRef`, followed by a general Render rule such as
   `whenFragmentActive elementFragment activePaint`. This permits independent
   styling, overlapping rules, and instance-specific behavior, but adds handle
   lifetime, precedence, and composition questions. Defer this surface until a
   concrete visualization cannot be expressed by the baseline or named roles.

Active-fragment treatments must be geometry-neutral: text fill, opacity,
underline, or a background derived from the prepared glyph bounds are valid.
Changing font family, weight, size, shaping features, or content would alter
the affine text measurements and requires another prepared design branch rather
than a playback-only highlight. Step-linked highlighting is general text-range
emphasis, not language-specific syntax highlighting; it therefore does not
restore `highlightCode`, `CodeRange`, or manual offset APIs.

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
  Selected values <- select valueKind
  node $ do
    Selected currentGroup <- self
    padding (uniform (by 12))
    node values $ do
      content (text "value")
      ensure (width currentGroup .>=. width values)

  aspectRatio 4 3
```

#### Relations and structural rankings

Relations describe which persistent Program locations are associated. They do
not prescribe coordinates, spacing, or connector routing. Render projects the
relations active in one exposed frame and then applies ordinary visual
constraints. The same relation data can therefore support a row, a freely
placed linked list, a tree, or another layout without changing Program.

The target Render vocabulary is:

```haskell
data Relations source target
data Ranking node
data FixedInt

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

asSequence
  :: Relations node node
  -> Selected node
  -> Render (Ranking node)

asTree
  :: Relations node node
  -> Selected node
  -> Render (Ranking node)

asDag
  :: Relations node node
  -> Selected node
  -> Render (Ranking node)

rankOf
  :: Ranking node
  -> Render FixedInt
```

`Selected links <- select kind` selects the relations of one declared kind that
are active in the current exposed frame. `Relations` is the resulting reusable
selection, parallel to the `Selected` node set returned when `select` receives a
block `Kind`. It contains the stable identity and endpoints of every matched
relation; authors cannot construct it or mutate its membership.

`relation selectedRelations body` is the relation counterpart of
`node selectedBlocks body`: it creates one spatial Render scope for every
selected relation. `first selectedRelations` and `second selectedRelations`
retrieve that scope's two stable owner nodes. Their result types come from
`Relations source target`, so a heterogeneous relation preserves its endpoint
types without a callback. Calling either operation outside the matching
`relation` scope, or with a different relation selection, is a source-level
error.

The exact relation identity remains in the compiler's match context. A
variable, choice, or future connector created inside the body therefore belongs
to that exact relation lifetime, from its initialization until either stable
owner is destroyed. The relation cannot be removed or recreated while both
owners remain live. For a kind with ordered endpoints, `first` is the source and
`second` is the target. For a symmetric kind, the two operations have a stable
order only so output and generated choice IDs are repeatable; its rule must be
symmetric or make any visual orientation an explicit Render choice.

`asSequence`, `asTree`, and `asDag` consistently take selected relations first
and selected nodes second. Every supplied relation must have both endpoints in
the supplied node selection; any relation outside it is a scope error rather
than being silently filtered. Each operation also validates the requested
structure and returns a `Ranking` for its nodes. Authors continue using the
original node and relation selections for rendering. If several independent
structures later share one relation kind, add an explicit relation-selection
operation that scopes those relations before validation. In this family, `as`
means "validate and expose as this view," not an unchecked cast.

A selected relation is always available as a spatial relation: its endpoint
nodes can participate in ordinary affine constraints even when no line or arrow
is drawn. A relation may connect different endpoint types without an integer
join. For example, `ProbeAt` can directly constrain a probe against its target
cell:

```haskell
Selected probeLinks <- select ProbeAt

relation probeLinks $ do
  probe <- first probeLinks
  cell <- second probeLinks
  ensure $ x probe .==. x cell
  ensure $ bottom probe .<=. top cell - by 12
```

Visual projection is optional. `relation` establishes the spatial scope but
does not automatically draw a line. The intended connector interface will
optionally create visual geometry inside that scope and resolve its anchors
from the two endpoint nodes. For example, the eventual vocabulary should
support the following shape; `connector`, `from`, `to`, and `markerEnd` remain
illustrative rather than settled exports:

```haskell
Selected branches <- select ParentOf

relation branches $ do
  parent <- first branches
  child <- second branches
  ensure $ top child .>=. bottom parent + shift 72
  connector $ do
    from (bottom parent)
    to (top child)
    markerEnd Arrow
```

Selecting `ParentOf` does not itself draw anything. Another Render rule may use
the same relations only for layout, draw an unmarked line, or choose a different
visual direction. In particular, ordered semantic endpoints do not silently
choose an arrow direction, and a symmetric relation has no semantic direction
at all. A generated connector must inherit the exact selected relation identity
so forward and reverse playback follow its creation and the lifetimes of its
stable owners.

##### Fixed structural values

`FixedInt` is an exact integer calculated from the current relation graph before
numeric solving. It may differ in another frame, but it is fixed while the
current Render rule is solved. Addition and subtraction by fixed integers remain
exact.

```haskell
asScalar :: FixedInt -> Scalar
asText   :: FixedInt -> ContentValue
```

`asScalar` makes the integer usable in affine layout expressions. Multiplying a
solver-backed span by an `asScalar` result remains affine because the integer
has already been fixed. `asText` formats the same value as deterministic
base-10 text for an index or level label.

##### Sequence validation and ranking

A sequence is one ordered chain. It covers arrays, ordinary lists, and linked
lists whose nodes use a relation with ordered endpoints such as `Adjacent` or
`Next`.

`asSequence relations nodes` accepts an empty graph, a single node with no edge,
or one non-empty chain. Every supplied relation must join two supplied nodes. A
non-empty chain must have one start, one end, no cycle or fork, and every
selected node must belong to it. Inside a `node` scope for one of those nodes,
`rankOf ranking` returns its zero-based position `0, 1, 2, ...`. Calling it
outside the ranking's matching node scope
is a source-level error. The selected relation kind must have ordered endpoints;
otherwise there is no defined first item or next item. Failure reports the
relation kind and offending endpoints before numeric sampling begins. Taking
the selected relations and nodes directly avoids exposing a graph handle that
authors would use only for this check. The baseline exposes no sequence length:
a visual parent's containment and padding derive its bounds from the positioned
children without one.

The following example assumes `cells` selects one non-empty array's cells and
`Adjacent` points from each cell to the next. The generated parent is the visual
array box; no separate Program array owner or `Contains` relation is needed. A
sampled centre-to-centre spacing is shared by the complete selection, while the
default hugging containment derives the parent width from its children and
padding:

```haskell
Selected cells <- select cellKind
Selected adjacentLinks <- select Adjacent
cellRanking <- asSequence adjacentLinks cells

Variable spacing <- variable @Span
ensure $ spacing .>=. by 64
ensure $ spacing .<=. by 96

node $ do
  Selected array <- self
  padding (uniform (by 16))

  node cells $ do
    position <- rankOf cellRanking
    ensure $ width cells .==. by 64
    ensure $ height cells .==. by 48
    ensure $ x cells .==. left array + shift 48 + spacing * asScalar position
    ensure $ y cells .==. y array
```

When cell widths vary, replace the centre-spacing rule with constraints over
the same supplied adjacency relations:

```haskell
Variable gap <- variable @Span
ensure $ gap .>=. by 8
ensure $ gap .<=. by 24

relation adjacentLinks $ do
  previous <- first adjacentLinks
  next <- second adjacentLinks
  ensure $ left next .==. right previous + gap
  ensure $ y next .==. y previous
```

These are alternative layout rules. A linked-list view can use the same checked
ranking for its structural positions while `relation nextLinks` supplies
endpoint pairs to a connector helper once that visual interface is defined.
Separate bounded constraints or prepared templates can place its nodes without
overlap. The relation does not force either layout. If several dynamic arrays
later share the same cell kind and relation kind, add a relation-selection
operation only with that concrete use case rather than adding replacement
projections or a special grouping API now.

##### Tree validation and levels

A tree is a graph whose relation has ordered parent-to-child endpoints and
exactly one root. Every other node must have one parent, every node must be
reachable from the root, and cycles are rejected.

The baseline does not expose the root, child count, or subtree size. For a tree,
`rankOf` is the number of parent-to-child edges from the root. It is available
inside a `node` scope matching one of the nodes validated by `asTree`; any other
scope is a source-level error.

Ordinary tree geometry can still follow directly from the validated
parent-to-child relations. For example, one shared local constraint gives every
tree level the same vertical gap:

```haskell
Selected parentLinks <- select ParentOf
treeRanking <- asTree parentLinks treeNodes

Variable levelGap <- variable @Span
ensure $ levelGap .>=. by 72
ensure $ levelGap .<=. by 120

relation parentLinks $ do
  parent <- first parentLinks
  child <- second parentLinks
  ensure $ y child .==. y parent + levelGap
```

When the exact level itself must be used or displayed, the same checked tree can
instead provide it locally:

```haskell
node treeNodes $ do
  level <- rankOf treeRanking
  y (at 60 + levelGap * asScalar level)
```

A parent-to-child relation does not define the left-to-right order of siblings.
When that order matters, declare it as another relation, such as `Adjacent`,
and apply ordinary relation constraints. The baseline does not derive ordinal
positions from those relations:

```haskell
Selected siblingLinks <- select Adjacent
Variable siblingGap <- variable @Span
ensure $ siblingGap .>=. by 16
ensure $ siblingGap .<=. by 48

relation siblingLinks $ do
  previous <- first siblingLinks
  next <- second siblingLinks
  ensure $ left next .==. right previous + siblingGap
```

##### DAG validation and levels

A DAG is a directed acyclic graph. Here, "directed" means the Domain
relation has ordered source-to-target endpoints. Following those ordered edges
can never return to the starting node. A DAG may have several roots, several
leaves, and disconnected parts. Unlike a sequence, it does not have one correct
position for every node because unrelated nodes can appear in either order.

The baseline does not expose separate root or leaf selections. `rankOf` is zero
at a root and otherwise one plus the greatest level of its immediate
predecessors. This is the length of the longest path from any root, not an
arbitrary total ordering. It remains because exact shared DAG layers cannot in
general be recovered from one equality constraint per edge when paths have
different lengths.

```haskell
Selected dependencyLinks <- select DependsOn
dagRanking <- asDag dependencyLinks tasks

Variable levelGap <- variable @Span
ensure $ levelGap .>=. by 72
ensure $ levelGap .<=. by 128

node tasks $ do
  level <- rankOf dagRanking
  y (at 60 + levelGap * asScalar level)
```

If a visualization requires one particular ordering of otherwise unrelated DAG
nodes, that ordering must be an explicit relation or Render choice. The compiler
must not silently choose one and remove other valid layouts.

##### General graphs and layouts

When cycles, several connected parts, or no single hierarchy are valid, use the
original node and relation selections directly. No validation handle is needed.
Relations with ordered or symmetric endpoints are both supported.

An edge carries its relation kind and stable identity, not an arbitrary weight
or label. Model a semantically weighted edge as its own typed Domain location
with relations to its endpoints, or add a later typed relation-property API.
Do not encode weight by creating duplicate edges; duplicate same-kind endpoint
pairs are rejected.

```haskell
Selected connectionLinks <- select ConnectedTo

node vertices $ do
  ensure $ left vertices .>=. left canvas + shift 24
  ensure $ right vertices .<=. right canvas - by 24
  ensure $ top vertices .>=. top canvas + shift 24
  ensure $ bottom vertices .<=. bottom canvas - by 24
```

This bounds every vertex but deliberately does not generate constraints between
every unrelated pair. A visualization that must prevent overlap in a dynamic
general graph should choose a bounded grid, layered, or other prepared layout
template. `separatedBy` remains available for explicitly identified pairs.

Graph-layout helpers belong in a Render library and should consume the existing
node and relation selections; they are not another semantic relation system. A
helper may emit bounded affine constraints directly or offer a finite set of
prepared grid, layered, or other layout templates as explicit design choices.
General force-directed placement, Euclidean distance objectives, and
edge-crossing minimization are not affine constraints. They must not invoke a
hidden nonlinear fallback. If later supported, they must be explicit
preparation algorithms that return bounded candidate templates before affine
sampling.

The four cases created by an explicit `separatedBy` constraint are affine once
one is selected, but applying it to every possible pair would grow
quadratically and introduce many combinations. The public API does not generate
those pairs. Connector routes add further choices, so large graphs should
normally use a bounded template generator.

##### Validation over time

All `as*` checks run for every exposed frame where their Render rule matches.
Apply them only to frames whose matching Program step has completed a logical
relation update.
If an incomplete structure is intentionally shown, Render should use its node
and relation selections directly until it is complete instead of applying
`asSequence`, `asTree`, or `asDag`. Structural failures are therefore
source-level diagnostics, not unlucky random samples.

Sequence, tree, and DAG checks visit each node and edge only a constant number
of times. Calculate their `FixedInt` values once for each distinct exposed-frame
graph and reuse them across seeds. No baseline graph operation constructs the
`n * (n - 1) / 2` unordered pairs of `n` nodes.

#### Reusable values and finite decisions

Retain `bindContent`, `variable`, `choice`, `Choice`, and `global`. `bindContent`
exposes the payload display
text of each block in the current typed selection; it no longer depends on a
payload query binding. Variables and choices introduce
solver-backed values; `variable` and `choice` create fresh compiler identities.
Remove `variableFrom`: it only placed an existing expression in the `Variable`
result wrapper and created no solver value, identity, sharing, or constraint. Use
an ordinary `let` for fixed and derived expressions.

Remove `ChoiceDomain`, `choiceDomain`, and `choiceToken` from the authored facade.
They are solver and serialization metadata, not custom choice logic. The compiler
owns the alternatives and stable tokens for supported finite types, so authors can
write `choice @FontStyle` without defining an instance. `Choice value` stores the
resolved domain internally, allowing `caseOf` to avoid the public constraint:

```haskell
choice :: forall value. ... => Render (Variable (Choice value))
caseOf :: Choice value -> (value -> [VisualConstraint]) -> Render ()
```

The baseline does not provide reusable author-defined categorical values. Use
`oneOf` for custom constraint alternatives and `sometimes` for presence. If a
concrete later use case needs one category to drive several APIs, add an explicit
non-empty constructor such as `choiceOf first rest`; do not restore author-managed
solver tokens.

Remove `RandomSeed` from the authored facade. It belongs to solver and compiler
entry points: the compiler service receives integer seeds and converts them
internally. Domain, Program, and Render code use seeded operations such as `choice`,
`variable`, `sometimes`, and `fontChoice` without inspecting or branching directly
on the seed. Keep `RandomSeed` in the lower-level `Solver` API used by compiler code,
tests, and benchmarks.

Remove `bindInt`. It currently creates a name-based query variable whose first
matching integer fact supplies both a later join key and an optional layout
coefficient. Use typed relations for membership, association, and ordering; use
`rankOf` for structural layout. A future numeric payload or property accessor
must be typed and tied to its selected entity rather than restoring free
string-keyed facts or bindings.

Use `global name` only when separately declared rules deliberately need the
same stable solver value. Ordinary reuse within one rule should reuse the value
returned by the builder instead of managing a string name.

```haskell
let fixedGap = by 20
Variable slant <- choice @FontStyle
let sharedScale = global "render.shared-scale" :: Scalar

ensure (left second .==. right first + fixedGap)
ensure (width current .==. by 80 * sharedScale)
ensure (sharedScale .>=. num 0.8)
ensure (sharedScale .<=. num 1.2)
node current $ style @FontStyle slant
```

#### Layout, geometry, and box model

Retain the following typed interfaces. Unless a snippet says otherwise, it is a
fragment inside one `Render` declaration and names such as `card` and `label`
are already selected node handles. `variable @T` creates a fresh solver-backed
value of type `T`; a node setter consumes an authored value, while the same
overloaded helper applied to a `Selected` handle returns a `VisualExpr` that can
be related with `ensure`.

Every solver-backed numeric value must end up with finite lower and upper bounds
after all node, canvas, and authored constraints are combined. Intrinsic domains
supply some of these bounds (`Unit` supplies both; `Coord` and `Span` supply only
zero as a lower bound), but the compiler rejects a final unbounded region.

##### `Coord`

`Coord` is a non-negative absolute horizontal or vertical position in scalable
canvas units. Construct a fixed coordinate with `at`, or let the solver choose
one with `variable @Coord` and bound it with constraints.

```haskell
Variable columnX <- variable @Coord
node card $ left columnX
ensure $ columnX .>=. at 24
ensure $ columnX .<=. at 480
```

Adding a `Span` or `Offset` to a `Coord` produces another `Coord`; subtracting
two coordinates produces an `Offset`.

##### `Span`

`Span` is a non-negative length used for widths, heights, gaps, font sizes,
radii, stroke widths, padding, and margins. `by` constructs a fixed span.

```haskell
Variable cardWidth <- variable @Span
node card $ width cardWidth
ensure $ cardWidth .>=. by 120
ensure $ cardWidth .<=. by 280
```

`Span + Span` and `Span |+| Span` both preserve the non-negative domain;
subtracting spans produces a signed `Offset`.

##### `Offset`

`Offset` is a signed displacement. Construct a fixed value with `shift`; unlike
`Coord` and `Span`, negative values are valid.

```haskell
Variable gap <- variable @Offset
ensure $ gap .>=. shift (-24)
ensure $ gap .<=. shift 48
ensure $ left second .==. right first + gap
```

`asCoord` and `asSpan` reinterpret an offset and add the target domain's
non-negativity requirement. They do not silently take an absolute value.

```haskell
Variable originOffset <- variable @Offset
Variable extentOffset <- variable @Offset
node card $ do
  left (asCoord originOffset)
  width (asSpan extentOffset)
ensure $ originOffset .<=. shift 480
ensure $ extentOffset .<=. shift 240
```

##### `Scalar`

`Scalar` is unitless. It scales a `Span` or `Offset`. `asScalar` converts a
graph-derived `FixedInt` into a constant scalar expression; it does not turn the
integer into a sampled solver variable.

```haskell
Variable scale <- variable @Scalar
ensure $ scale .>=. num 0.75
ensure $ scale .<=. num 1.25
node card $ width (by 160 * scale)

node cells $ do
  position <- rankOf cellRanking
  ensure $ x cells .==. at 40 + by 72 * asScalar position
```

Both examples remain affine because one factor in each multiplication is
constant when numeric solving begins.

##### `VisualExpr`

`VisualExpr role` is a read-only affine expression obtained from selected node
geometry or styles. Authors do not construct it directly and cannot use it as a
declaration pin; they relate it to fixed values, solver variables, or other
selected expressions.

```haskell
ensure $ left label .==. right card + shift 12
ensure $ width label .<=. width card - by 24
```

The role parameter preserves distinctions such as `Coord`, `Span`, and `Unit`
while allowing expressions from several selected nodes to be combined.

##### `Free`

`Free` is an otherwise unbounded solver numeric domain. Because the target
solver requires a bounded design space, every authored `Free` variable must
receive finite lower and upper bounds before sampling.

```haskell
Variable score <- variable @Free
ensure $ score .>=. num (-1)
ensure $ score .<=. num 1
```

Prefer `Coord`, `Span`, `Unit`, or `Angle` when their intrinsic domain describes
the value; `Free` is not a substitute for a signed layout `Offset`.

##### `Unit`

`Unit` is a solver expression intrinsically bounded to the inclusive interval
zero to one. It is used by opacity, alpha, saturation, and lightness.

```haskell
Variable fade <- variable @Unit
ensure $ fade .>=. num 0.35
node label $ style @Opacity fade
```

##### `Angle`

`Angle` is the bounded angular domain used for an HSL hue. The solver and
materializer own canonical treatment of the equivalent zero- and 360-degree
boundary.

```haskell
Variable accentHue <- variable @Angle
ensure $ accentHue .>=. num 180
ensure $ accentHue .<=. num 260
node card $ style @Fill (Hsl accentHue (num 0.65) (num 0.52))
```

##### `Vec2`

`Vec2 a` groups horizontal and vertical values of the same type. Construct one
with `vec2`; `center` reads or sets a `Vec2` of coordinates, and `size` reads a
selected node's width and height as a `Vec2` of spans.

```haskell
node badge $ center (vec2 (at 180) (at 96))
ensure $ center badge .==. center card
ensure $ size badge .==. vec2 (by 120) (by 48)
```

Vector equality lowers component by component. Arithmetic is available only
where the component types already support it.

```haskell
Variable badgeX <- variable @Coord
Variable badgeY <- variable @Coord
node badge $ center (vec2 badgeX badgeY)
ensure $ badgeX .<=. at 640
ensure $ badgeY .<=. at 360
```

##### `Bounds`

`Bounds a` is the four-component container ordered as top, left, width, and
height. The `bounds` setter pins all four properties of the current node at
once.

```haskell
node card $ bounds (Bounds (num 32) (num 48) (num 240) (num 120))
```

Use the individual typed setters when components are solver variables; they
make the coordinate/span distinction visible and give clearer diagnostics.

##### `separatedBy`

`separatedBy gap first second` is a symmetric hard constraint requiring the two
axis-aligned node bounds to have at least `gap` between them on the left, right,
above, or below:

```haskell
separatedBy :: Span -> Selected first -> Selected second -> VisualConstraint

ensure $ separatedBy (by 12) first second
```

The compiler lowers this union to four exact affine cases. These are
compiler-created geometric cases, not four equally weighted authored choices;
their sampling follows the case-split rules in the proposed solver
architecture. A bounded solver-backed `Span` is also valid because it appears
linearly in every case.

##### Numeric literals and affine arithmetic

Retain `num`, `fromInteger`, `fromRational`, `(+)`, `(-)`, `(*)`, `(/)`, and
`(|+|)`. `num` constructs a literal in the type inferred by its use;
`fromInteger` and `fromRational` support ordinary overloaded numeric literals.
Prefer `at`, `by`, and `shift` at layout boundaries because they make the
intended domain explicit.

```haskell
ensure $ left label .==. at 20 + shift 8
ensure $ width second .==. width first + by 12
node card $ height ((by 96 |+| by 24) / num 2)

let fixedScale = 3 / 2 :: Scalar
node badge $ width (by 80 * fixedScale)
```

Only the type-correct combinations are available. The target affine compiler
also rejects a product of two solver-variable values or division by a
solver-variable denominator even if the Haskell expression is otherwise typed.

##### `Left` and `left`

`Left` is the overload class for `left`. Applied to a `Coord`, `left` pins the
current node; applied to a selected node, it returns `VisualExpr Coord`.

```haskell
node first $ left (at 24)
ensure $ left second .==. right first + shift 16
```

##### `Top` and `top`

`Top` provides the corresponding top-edge setter and selected-node accessor.

```haskell
node first $ top (at 32)
ensure $ top second .==. bottom first + shift 12
```

##### `Right` and `right`

`Right` pins or reads the right edge. Setting both horizontal edges lets the
solver derive width, subject to any additional width constraints.

```haskell
node card $ right (at 520)
ensure $ right label .<=. right card - by 16
```

##### `Bottom` and `bottom`

`Bottom` pins or reads the bottom edge. Setting both vertical edges similarly
determines height.

```haskell
node card $ bottom (at 320)
ensure $ bottom label .<=. bottom card - by 12
```

##### `Width` and `width`

`Width` accepts a `Span` as a declaration setter and returns `VisualExpr Span`
from a selected node.

```haskell
node card $ width (by 240)
ensure $ width label .<=. width card - by 32
```

##### `Height` and `height`

`Height` is the corresponding height setter and accessor.

```haskell
Variable rowHeight <- variable @Span
node row $ height rowHeight
ensure $ rowHeight .>=. by 32
ensure $ rowHeight .<=. by 96
ensure $ height label .<=. rowHeight
```

##### `X` and `x`

`X` and `x` address the horizontal centre coordinate.

```haskell
node badge $ x (at 200)
ensure $ x badge .==. x card
```

##### `Y` and `y`

`Y` and `y` address the vertical centre coordinate.

```haskell
Variable baselineY <- variable @Coord
node label $ y baselineY
ensure $ baselineY .<=. at 360
ensure $ y icon .==. baselineY
```

##### `Center` and `center`

`Center` combines the `X` and `Y` behavior. A `Vec2 Coord` sets both centre
pins; a selected node returns `Vec2 (VisualExpr Coord)`.

```haskell
node badge $ center (vec2 (at 200) (at 120))
ensure $ center badge .==. center card
```

##### `Insets`

`Insets` stores non-negative top, right, bottom, and left spans. `uniform`
sets every edge, `symmetric` accepts vertical then horizontal spans, and `edges`
accepts top, right, bottom, then left. `padding` sets internal spacing around
children/content; `margin` contributes external spacing when a parent contains
or hugs the node.

```haskell
Variable gutter <- variable @Span
ensure $ gutter .>=. by 8
ensure $ gutter .<=. by 24
node group $ do
  padding (symmetric (by 12) gutter)
  margin (edges (by 4) (by 8) (by 4) (by 8))
node badge $ padding (uniform (by 8))
```

##### `Axis`

`Axis` has `Horizontal`, `Vertical`, and `Both`. It selects which dimension a
`contentFit` declaration changes. It is a fixed declaration parameter, not a
solver-backed choice.

```haskell
node group $ contentFit Horizontal Contain
```

##### `ContentFit`

`ContentFit` has `Contain` and `Hug`. Both require children, including their
margins, to remain inside the parent's padded content box. `Hug` additionally
makes an ordinary generated parent's relevant edges touch extremal children;
`Contain` leaves extra space available. Retain the current default of `Hug` on
both axes. The retained `contentFit` setter accepts a fixed policy; a
solver-selected policy would require an explicit structural-alternative API.

```haskell
node group $ do
  contentFit Horizontal Contain
  contentFit Vertical Hug
```

`contentFit Both Hug` is the compact form when both axes use the same policy.

##### `Percent`

`Percent` is an abstract, validated parent-relative percentage from zero to 100. Construct it with `percent`. `xAt` and `yAt` place the current node's centre
within the parent content box; `widthOf` and `heightOf` size it relative to the
parent content dimensions.

```haskell
node card $ do
  xAt (percent 50)
  yAt (percent 40)
  widthOf (percent 60)
  heightOf (percent 30)
```

Percentages are fixed author inputs in the retained API, not solver variables.
Use a bounded `Coord` or `Span` variable when the result must vary. Multiplying
a variable percentage by a variable parent dimension would be bilinear and is
therefore outside the affine target.

##### `aspectRatio`

`aspectRatio horizontal vertical` constrains the root canvas to a finite,
positive ratio. It is canvas-only and both arguments are fixed `Double` values.

```haskell
aspectRatio 16 9
```

#### Style authoring and colour

Styles use a type application to identify the field and a field-specific input
type. The snippets below are independent `Render` fragments rather than
declarations intended to be concatenated.

##### `style`

`style @Field input` accepts a fixed field value, its matching solver `Choice`,
or the field's symbolic numeric or colour expression:

```haskell
style :: forall field input. ... => input -> Render ()

node title $ style @FontStyle FontStyleItalic

Variable selectedStyle <- choice @FontStyle
node explanation $ style @FontStyle selectedStyle
```

The compiler provides the supported field/input pairs; authors do not define the
conversion class. Passing `Choice FontStyle` to `style @FontFamily`, for example,
is a type error. A direct choice assignment makes the field always present, so
`styleOf` can read and constrain it. `styleCase` remains distinct: it maps a choice
to other field values and may omit the field in some branches. Keep the necessary
fixed-or-variable sum inside the style compiler; remove the public `StyleChoice`,
`FixedStyle`, `VariableStyle`, `styleFrom`, and `styleChoice` adapters.

##### `NodeStyle`

`NodeStyle` remains the opaque accumulated style plan for a node. Authors do
not construct it directly. Cluster its public operations as follows:

- `style @Field input` requires or overrides one field with a fixed value, matching
  categorical choice, or supported symbolic expression.
- `withoutStyle @Field` explicitly suppresses an inherited or automatically
  generated field.
- `styleCase @Field choice mapping` conditionally supplies a field for each
  category; `Nothing` suppresses it in that branch.
- `styleFamily name` assigns the semantic cascade family used by automatic
  styling of the node and descendants. This string is a style-family label,
  not a solver-choice identity.
- `styleOf @Field selected` reads the selected field as a symbolic expression
  for use in constraints.

```haskell
Variable slant <- choice @FontStyle
node label $ do
  styleFamily "explanation"
  style @FontStyle slant
  styleCase @Opacity slant $ \case
    FontStyleNormal  -> Just (num 1)
    FontStyleItalic  -> Just (num 0.90)
    FontStyleOblique -> Just (num 0.85)
  withoutStyle @Stroke

ensure $ styleOf @FontStyle label .==. slant
```

`styleOf` requires that the requested field is present in every branch. It
cannot read a field declared with `withoutStyle` or a conditional `styleCase`;
constrain the driving choice instead when presence itself is conditional.

##### `Opacity`

`Opacity` accepts `Unit` and affects the complete rendered node, including its
shape and text content. `styleOf @Opacity` returns `VisualExpr Unit`.

```haskell
Variable nodeOpacity <- variable @Unit
node label $ style @Opacity nodeOpacity
ensure $ nodeOpacity .>=. num 0.4
ensure $ styleOf @Opacity label .==. nodeOpacity
```

##### `FontSize`

`FontSize` accepts a `Span`. A fixed span pins the size; a bounded variable lets
the affine sampler vary it when used by `fitText`. Every fitted line using that
variable contributes its own fit constraints. Ordinary `content` uses a fixed
authored or theme-default size.

```haskell
Variable labelSize <- variable @Span
node label $ style @FontSize labelSize
ensure $ labelSize .>=. by 14
ensure $ labelSize .<=. by 28
ensure $ styleOf @FontSize label .==. labelSize
```

With `fitText`, these authored bounds delimit feasible single-line size
variation; they do not request automatic wrapping or maximum-size optimization.
If no `FontSize` is supplied, `fitText` creates a fresh variable using the
theme-defined fit range.

##### `Radius`

`Radius` accepts a non-negative `Span` for a node's corner radius and is
available through `styleOf @Radius` as `VisualExpr Span`.

```haskell
Variable cornerRadius <- variable @Span
node card $ style @Radius cornerRadius
ensure $ cornerRadius .>=. by 0
ensure $ cornerRadius .<=. by 24
```

##### `StrokeWidth`

`StrokeWidth` accepts a non-negative `Span`. It controls the rendered border
width when `BorderStyle` is not `BorderNone`.

```haskell
Variable borderWidth <- variable @Span
node card $ do
  style @StrokeWidth borderWidth
  style @BorderStyle BorderSolid
ensure $ borderWidth .>=. by 1
ensure $ borderWidth .<=. by 4
```

##### `Alpha`

`Alpha` accepts `Unit` and applies to the node's fill and stroke paints. It is
distinct from `Opacity`, which fades the complete node as one rendered group.

```haskell
Variable paintAlpha <- variable @Unit
node card $ style @Alpha paintAlpha
ensure $ paintAlpha .>=. num 0.5
ensure $ paintAlpha .<=. num 1
```

##### `Hsl`

`Hsl hue unit` stores hue, saturation, and lightness. Retain the `Hsl`
constructor and its `hue`, `saturation`, and `lightness` record accessors. In a
`Color`, hue is an `Angle` and the other components are `Unit` values.

```haskell
Variable hueValue <- variable @Angle
Variable saturationValue <- variable @Unit
let accent = Hsl hueValue saturationValue (num 0.52) :: Color
```

`sat` remains the compact saturation accessor, particularly for a colour read
from a selected style:

```haskell
ensure $ sat (styleOf @Fill card) .>=. num 0.55
ensure $ hue (styleOf @Fill card) .>=. num 180
ensure $ lightness (styleOf @Fill card) .<=. num 0.7
```

##### `Color`

`Color` remains the alias `Hsl Angle Unit`. It intentionally has no embedded
alpha component; use the separate `Alpha` style field for paint transparency.
Colour components may be fixed, solver-backed, or a mixture of both.

```haskell
let quietBlue = Hsl (num 215) (num 0.35) (num 0.62) :: Color
node card $ style @Fill quietBlue
```

##### `Fill`

`Fill` accepts `Color` directly. `styleOf @Fill` returns an `Hsl` whose
components are selected `VisualExpr` values.

```haskell
Variable fillHue <- variable @Angle
Variable fillLightness <- variable @Unit
node card $ style @Fill (Hsl fillHue (num 0.7) fillLightness)
ensure $ fillLightness .>=. num 0.35
ensure $ fillLightness .<=. num 0.65
```

##### `Stroke`

`Stroke` also accepts `Color` directly. It may be set, constrained through
`styleOf @Stroke`, or explicitly suppressed with `withoutStyle @Stroke`.

```haskell
node card $ do
  style @Stroke (Hsl (num 220) (num 0.55) (num 0.3))
  style @BorderStyle BorderSolid

ensure $ sat (styleOf @Stroke card) .>=. num 0.4
```

##### `BorderStyle`

`BorderStyle` is categorical, with `BorderNone`, `BorderSolid`,
`BorderDashed`, `BorderDotted`, and `BorderDouble`.

```haskell
Variable borderStyle <- choice @BorderStyle
node card $ style @BorderStyle borderStyle
ensure $ styleOf @BorderStyle card .==. borderStyle
```

`BorderNone` disables visible stroke rendering even if stroke colour and width
are otherwise available in the cascade. The current presentation renderer in
[VisualizationViewport.svelte](../../../src/lib/client/visualization/VisualizationViewport.svelte)
does not render `BorderDouble` differently from a solid border, so distinct
double-line rendering or removal remains an open target decision. Leaving both
as separately weighted authored choices while they render identically would
silently double the probability of the solid appearance.

##### `FontKind`

Add the catalog classification used to restrict font-family choices:

```haskell
data FontKind = Monospace | Proportional
```

`Proportional` means a catalogued non-monospace family. Kind is explicit catalog
metadata, not a guess based on the family name.

##### `FontFilter`

`FontFilter` is abstract. Initially `fontKind` constructs a kind filter and
`fontChoice` creates a fresh filtered authored choice, matching the builder
shape of the existing `choice` interface:

```haskell
fontKind :: FontKind -> FontFilter
fontChoice :: FontFilter -> Render (Variable (Choice FontFamily))
```

```haskell
Variable codeFont <- fontChoice (fontKind Monospace)
Variable explanationFont <- fontChoice (fontKind Proportional)
```

An empty filter produces a source-level diagnostic. Keep `FontFilter` abstract
so later constructors and composition helpers, such as serif classification or
required script coverage, can be added without changing `fontChoice`.

Filter results contain unique concrete catalog-family identities. Resolve
generic aliases before weighting candidates so an alias and its concrete target
cannot give one font twice the sampling probability. Reusing the returned
`Choice` shares the sampled family; separate `fontChoice` calls remain
independent authored decisions.

##### `FontFamily`

Retain the current fixed values `FontInter`, `FontSystem`, `FontMono`,
`FontSerif`, `FontSourceSans3`, `FontAtkinsonHyperlegibleNext`,
`FontSpaceGrotesk`, `FontSourceSerif4`, `FontLiterata`,
`FontJetBrainsMonoNL`, and `FontIBMPlexMono`. A sampled family normally comes
from `fontChoice` and is passed directly to `style`.

```haskell
node title $ style @FontFamily FontLiterata

Variable codeFont <- fontChoice (fontKind Monospace)
node codeLine $ style @FontFamily codeFont
ensure $ styleOf @FontFamily codeLine .==. codeFont
```

The initial filtered interface applies one family to a complete shaped text
node. It does not change fonts at fragment boundaries.

##### `FontWeight`

`FontWeight` has `FontWeightNormal`, `FontWeightBold`, `FontWeightBolder`,
`FontWeightLighter`, and `FontWeightNumber n`. The selectable numeric catalogue
uses 100 through 900 in steps of 100; fixed numeric inputs must be validated
against the supported font face.

```haskell
Variable weight <- choice @FontWeight
node label $ style @FontWeight weight
ensure $ styleOf @FontWeight label .==. weight
```

Each metric-affecting weight remains a discrete typography branch rather than a
continuously varying affine value. Resolve `FontWeightBolder` and
`FontWeightLighter` to concrete supported weights after the inherited parent
weight is known and before shaping the branch.

##### `FontStyle`

`FontStyle` has `FontStyleNormal`, `FontStyleItalic`, and `FontStyleOblique`.
It accepts either a fixed value or a finite choice.

```haskell
Variable slant <- choice @FontStyle
node explanation $ style @FontStyle slant
ensure $ styleOf @FontStyle explanation .==. slant
```

A style unavailable for the selected font invalidates that combined typography
branch; it must not silently synthesize a different face.

##### `TextAlign`

`TextAlign` has `TextAlignLeft`, `TextAlignCenter`, `TextAlignRight`, and the
currently retained `TextAlignJustify`. Alignment is categorical; left, centre,
and right supply an affine offset after the line has been shaped.

```haskell
Variable alignment <- choice @TextAlign
node label $ style @TextAlign alignment
ensure $ styleOf @TextAlign label .==. alignment
```

The current materializer in [Typography.hs](Visualization/Typography.hs) treats
every value other than left or right as centre, so `TextAlignJustify` is not
currently distinct. Its meaning without automatic wrapping remains an open
decision below. It must not remain as a separately weighted alias for centre,
because that would bias the authored alignment distribution.

##### `WhiteSpace` (removed)

Remove `WhiteSpace`, `WhiteSpaceNormal`, `WhiteSpaceNoWrap`, `WhiteSpacePre`,
and `WhiteSpacePreWrap` from the target facade. Every text node is one authored
line, so wrapping and whitespace policy are not selectable style branches.

##### `ZIndex` (removed)

Remove `ZIndex` from the target facade. Render order is derived implicitly from
the node hierarchy and declaration order for now, so authors cannot set a fixed
or solver-backed z-index.

#### Constraints and alternatives

Retain `ensure`, `encourage`, `VisualConstraint`, `VisualAlternative`,
`alternative`, `oneOf`, `caseOf`, `separatedBy`, `(.<=.)`, `(.>=.)`,
`(.==.)`, `(=|)`, `(=/)`, `(|=)`, and `(/=)`.

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
- `relate` operates only on slot locations. There is no general block relation:
  exact-block provenance remains represented by create, copy, apply, replace,
  use, and destroy events, while purely visual connections belong to Render.
- `relate` consumes and returns two `Slot`s containing their children. It
  records a compiler-owned relation between their stable owner identities and
  returns no public relation token or endpoint capability.
- `relate` is the Program event at which a new semantic association begins: it
  consumes the current endpoint slots and returns successor capabilities for the
  same persistent locations. It may occur after an earlier exposed frame and does not
  mutate a live `Slot` value in place.
- Render constraints derived from that association join the one fixed constraint
  system over the endpoint owners' overlapping lifetimes. They may therefore affect
  earlier-frame geometry even though the relation is not yet visible there.
- A relation remains active when either slot is unsealed, temporarily empty,
  resealed, or given a replacement occupant. It follows neither old nor new
  occupant `BlockId`: its endpoints remain the same persistent locations, so no
  retarget event is produced by a write.
- A relation ends automatically when either endpoint owner is destroyed. There is
  no public removal operation; its already-collected geometry remains scoped by the
  endpoint-owner lifetimes.
- Every relation kind fixes its source type, target type, and whether its
  endpoints are ordered or symmetric. Program rejects endpoints of the wrong
  owner type. Render preserves ordered source-to-target roles but gives no
  semantic meaning to the stable iteration order of a symmetric pair.
- Program rejects a second active relation of the same kind between the same
  endpoint pair. For a symmetric kind, the reversed pair is the same pair; for
  an ordered kind, the reversed pair is distinct.
- `asSequence`, `asTree`, and `asDag` reject symmetric relations before numeric
  solving.
- Relation structure may determine membership, adjacency, sequence position,
  or DAG level. It must not be used to invent numeric properties such as a
  sparse key, address, stored value, or edge weight.

## View and rendering

Project `relate` as `TraceRelate relationId kind leftOwnerId rightOwnerId`.
Derive its end from the first endpoint-owner destruction rather than recording a
public removal event. Render resolves each endpoint against the stable owner
geometry rather than the current occupant element. Consequently a rendered
connector stays anchored while an occupant exits, enters, or changes identity,
and it may remain visible while a slot is unsealed. Forward and reverse playback
derive the same interval from relation creation and endpoint lifetimes. Render
rules may choose how a declared relation kind is drawn, but they must not infer
semantic relations from block lineage, solver variable names, or proximity.

In each exposed frame, `select relationKind` projects the matching active
relations and their stable endpoints into `Relations`. `asSequence`, `asTree`,
and `asDag` verify that the supplied relation and node selections have the same
scope, validate the requested shape, and calculate its ranking. None replaces
its complete input selections: Render continues to map the original nodes and
relations. General graphs need no separate public handle.

## Compiler and runtime boundary

## Migration and compatibility

The classification and relation slices are intentionally breaking at the new
`Sverlin` facade. Replace atom tags such as `#value` with typed Domain `Kind`
declarations, attach them through `materialize` or `materializeWithKind`, and
select them directly. Replace structural `#index @: value` joins with declared
relations and derived graph values. Payload text needed for display is read
through `bindContent`, not captured by a query.

Remove `FactValue`, `Fact`, `Facts`, `emptyFacts`, `factAtom`, `factSymbol`,
`factInt`, `factsUnion`, `factsToList`, `Query`, `QueryInt`, `QueryField`,
`emptyQuery`, `queryAtom`, `queryInt`, `queryFacts`, `payload`, `PayloadQuery`,
`AnyPayload`, the public query-based `Select` class, `NodeBinding`, `(@:)`,
query `(<&>)`, query `fromLabel`, and `bindInt` from `Sverlin`. Replace
`NodeBinding` with the general `SelectionBinding`; the new purpose-specific
`Selectable` class supports typed block and relation kinds in the baseline.
Existing fact/query representations may remain temporarily behind the compiler
boundary as a migration mechanism, but generated and handwritten Sverlin
source cannot name them. Numeric payload filtering remains unavailable until a
typed entity-bound predicate has a demonstrated use case.

## Examples and tests

Add focused facade and compiler tests for:

- fixed-size `content` retaining its size in a larger box and deriving a hugging
  box when dimensions are otherwise free;
- `fitText` sampling across its complete feasible bounded size range rather
  than choosing the maximum, shared size variables obeying every line's fit
  constraint, and a source diagnostic when no permitted size or font fits;
- one typed block kind and one typed relation kind selected through the same
  `select` vocabulary across Program and Render, plus compile-time mismatches
  between kinds, pending values, node selections, and relation selections;
- the two library-provided `Node` forms, rejection of relation selections, and
  `self` remaining valid only inside a generated node body;
- `always` preserving inherited presence, `sometimes` returning ordinary symbolic
  handles with hidden presence provenance, transitive exclusion of dependent
  components, conjunction of several optional dependencies, and preservation of an
  unrelated component;
- independent seeded inclusion of repeated `sometimes $ frame @Step` occurrences,
  with frame choices kept outside the affine configuration count;
- `materializeWithKind` choosing among predeclared classifications from a
  payload without creating numeric or string-keyed facts;
- heterogeneous relations such as `ProbeAt Probe Cell`, including endpoint
  type errors, duplicate-edge rejection, typed context-local `first` and
  `second`, rejection outside their matching relation scope, affine endpoint
  constraints, creation after an earlier exposed frame, constraints applying across
  the owners' overlapping lifetimes without earlier relation visibility,
  persistence through unseal/reseal and occupant replacement, automatic end at
  owner destruction, and the same derived lifetime in reverse playback;
- rejection with source locations when relation-derived geometry conflicts with
  other constraints collected for an endpoint-owner lifetime;
- ordered `Next a b` remaining distinct from `Next b a`, symmetric
  `ConnectedTo a b` rejecting `ConnectedTo b a` as a duplicate, and an ordered
  graph helper rejecting a symmetric kind with a source-level diagnostic;
- empty and one-cell sequence validation, plus one non-empty array rendered as
  a hugging generated group with sampled centre-spacing and edge-gap layouts;
- rejection of every supplied relation outside the checked node selection,
  whether neither or only one endpoint is selected;
- sequence diagnostics for a missing edge, fork, cycle, and disconnected node;
- context-local sequence ranks used through both `asScalar` and `asText`, plus
  rejection outside the checked sequence's node scope;
- a linked list that uses `Next` for traversal while its node positions remain
  independently constrained;
- valid and invalid trees laid out through local parent-to-child constraints,
  with tree levels available through context-local `rankOf`;
- DAG longest-path levels through the same context-local `rankOf`, plus
  rejection of a directed cycle and mismatched node scopes;
- a cyclic relation selection rendered directly but rejected by `asDag`, with
  its nodes bounded through ordinary `node` mapping and no implicit all-pairs
  constraints;
- reuse of the original node and relation selections after every `as*` check,
  with no generic projections of those complete inputs, aggregate graph counts,
  callback-based relation mapping, separate traversal helpers, or general
  all-pairs generator;
- structural checks in successive exposed frames, including direct relation
  rendering while a sequence, tree, or DAG is incomplete; and
- removal of the public fact/query surface and `bindInt`, including migration
  of integer-variable joins to relations and confirmation that `Sverlin`
  exports no string-keyed classification or numeric-query constructor.

## Implementation order

For the classification and relation slices:

1. Add `Kind`, typed materialization, `SelectionBinding`, and typed block
   selection; lower them through the existing internal fact representation
   temporarily if that makes migration safer.
2. Add typed `RelationKind` declarations and the `relate` trace event, including
   endpoint validation, slot-capability transitions, and automatic lifetime
   derivation from endpoint owners.
3. Project active relation identities and endpoints to stable owner nodes in
   each exposed frame, and add the `RelationKind` case of `select`.
4. Add `Relations`, context-local typed `first` and `second`, and `FixedInt`;
   make the structural checks consume already-scoped relation and node
   selections directly.
5. Add the sequence, tree, and DAG checks and their context-local rankings.
6. Migrate all examples and fixtures from query atoms and integer joins to
   kinds and relations; then remove the complete public fact/query surface from
   `Sverlin`.
7. Add graph-layout template helpers only after direct `node`/`relation`
   rendering and the affine solver boundary are tested.

The existing `containers` dependency in
[compile.cabal](../../compile.cabal) is sufficient for the first implementation.
Use `Data.Graph` for connected-component, cycle, and topological-order checks,
with `Data.Map`/`Data.Set` for endpoint lookup. Sort stable owner identities
before assigning internal graph vertices so results and diagnostics do not
depend on map insertion order. Sequence and tree degree checks are small enough
to keep local. Do not add another graph package until a concrete layout-template
algorithm needs it; graph representation libraries do not themselves solve the
layout problem.

## Open decisions

### Remaining Domain classification and payload details

- Choose the declaration syntax that constructs typed `Kind` values and makes
  them available to Domain, Program, and Render with stable diagnostic and
  serialization identities. Free string keys and overloaded-label fallback are
  excluded regardless of the chosen syntax.
- Decide whether fixed-kind `materialize`, payload-derived
  `materializeWithKind`, and unclassified `commit` should remain three
  operations or become one operation taking an explicit classification plan.
  A combined operation must still distinguish one fixed `Kind`, a classifier
  choosing one declared kind, and deliberately no kind; it must not reintroduce
  facts or an untyped callback result.
- Define a typed, entity-bound accessor for numeric payload or property values
  when their magnitude must affect layout. It must remain distinct from
  `FixedInt`, which contains compiler-calculated graph data, and must not
  restore free name-based facts, predicates, or bindings. Add typed equality or
  range filtering only when a concrete Render use case requires it.

### Remaining relation details

- Choose the Domain declaration syntax that creates typed `RelationKind`
  values, records ordered or symmetric endpoint meaning, and makes the same
  declarations available to Program and Render. The endpoint types and
  behavior specified above are settled even though this construction syntax is
  not.
- If one relation kind later spans several independently rendered structures,
  add an explicit endpoint-based relation-selection operation before the
  `as*` check. It must preserve relation identity and endpoint roles; the check
  itself must not filter relations or return replacement selections. Keep this
  operation out of the baseline until a concrete multi-structure use case fixes
  its required selection semantics.
- Define how Render addresses the current occupant of a restored `Slot` from
  its stable owner node. The owner-to-occupant association is settled trace
  data, but the authored surface remains open: it may apply owner bounds to the
  occupant automatically or expose a typed owner/occupant traversal. It must
  let an array lay out `ElementCell` owners through `Adjacent` while rendering
  each contained value, without restoring query bindings or integer joins.
- Define the first bounded graph-template interface and how several candidate
  templates are weighted. Merely generating more equivalent templates must not
  increase one visual layout's sampling probability.
- Define the visual connector and anchor interface available inside a
  `relation` spatial scope. The `relation` mapping itself must remain valid with
  only affine endpoint constraints and no visible connector. A connector
  created in that scope must inherit its exact `relationId`, appear from
  relation initialization until either owner is destroyed in forward and
  reverse playback, and remain anchored to its stable owners while occupants
  change.
  Ordered endpoints do not automatically choose arrow direction, and symmetric
  endpoints have none. The names, path shapes, routing choices, marker styles,
  and connector IR remain open.

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
constant coefficients belonging to that branch. With `fitText`, font size is a bounded
continuous solver variable unless the author explicitly fixes it. Ordinary `content`
uses an authored or theme-default fixed size.

For a sampled font size `s`, node width `w`, node height `h`, and affine padding and
border expressions, a fitted line contributes constraints of the following form:

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

Resolve a `FontFilter` against explicit catalog metadata before generating these branches.
`fontKind Monospace` retains only fixed-pitch families and `fontKind Proportional` retains
only non-monospace families. A filtered font choice is still an authored random choice:
eligible families receive the normal authored-choice weights, and feasibility may remove
only families whose shaped text and affine constraints cannot work. Reusing the `Choice`
returned by one `fontChoice` call across several lines makes the family assignment shared
without sharing a sampled layout; each line still has its own geometry and shaping
constants. The catalog must not infer kind from a family name, and all selectable faces
exposed as one family must have a consistent kind. The current `FontFaceSpec` in
[FontCatalog.hs](Visualization/FontCatalog.hs) has no such classification, so this target
requires new catalog metadata rather than filtering the existing `FontFamily` constructor
names. Resolve generic family aliases before deduplicating and weighting candidates; an
alias and its concrete target must not give one font twice the sampling probability.

Font feasibility for `fitText` must be tested with the shaped text constraints before
selecting a branch. The compiler must not choose a font without considering its text,
discover that the line cannot fit above the minimum size, and fail when another font
would have worked.
For small choice spaces, shape and certify every eligible font branch. For larger spaces,
cache shaping results by font-resource hash, face and axis values, features, and source
line, then expose the branch-specific affine constraints to the discrete feasibility
solver. A selected font branch is therefore known to contain at least one valid
combination of font size and geometry.

There are no automatic wrapping branches. Ordinary `content` keeps its fixed size and a
normally hugging node grows around it. When external constraints impose a smaller box,
compilation reports that the line must be shortened, given a larger box, changed to
`fitText`, or split into separate text nodes. `fitText` may instead vary its bounded font
size or box geometry. Explicitly authored lines may still share font choices, font-size
variables, alignment constraints, and vertical gap variables, all without leaving one
convex affine region.

The existing typography implementation already emits affine inequalities of this shape
in [Typography.hs](Visualization/Typography.hs). Its current two-pass flow nevertheless
selects a fitted size, replaces it with a numeric literal, and pins the initially sampled
width, height, padding, and stroke before the final solve. The target flow must remove
those pins: shaping supplies constants and constraints, while the final sampler jointly
chooses font size and geometry. Final IR materialization scales the prepared glyph metrics
by the sampled size and retains a small documented safety margin for output rounding.

`fitText` means bounded size variation inside this feasible region; it does not mean
"choose the largest possible size." Maximum-fit typography is outside the baseline. It
could be added later as an explicit non-random policy that solves a linear boundary
objective, but it would not provide font-size diversity. An authored fixed-size policy
likewise creates a zero-dimensional font-size slice while leaving other geometry
available for sampling.

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

Relation checks, sequence positions, and tree or DAG levels are also prepared before
numeric solving. They are fixed consequences of the active trace graph, not random
branches, so recalculating them for a frame does not bias the layout distribution.
Only explicit layout choices or exact geometric case splits add solver configurations.

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
- Define the theme's default `fitText` font-size bounds and whether font-size diversity
  follows the joint geometric measure, explicit size bands, or a separately declared
  continuous prior.
- Decide whether `TextAlignJustify` is rejected or given explicit single-line semantics;
  automatic wrapping no longer supplies multi-line text for conventional justification.
- Decide whether `BorderDouble` gains distinct double-line rendering or is removed; the
  current presentation path renders it like `BorderSolid`.
- Define how bundled and future user-supplied fonts acquire validated `FontKind` metadata,
  including whether the compiler verifies the declaration against font metrics and how it
  diagnoses a family whose selectable faces disagree.
- Set shaping-cache and eligible-font limits from text-heavy application benchmarks. The
  cache key must include every input that can change glyph metrics.
- Replace the raw configuration-count enumeration cutoff with a benchmarked cost policy
  that accounts for variables, constraints, equality reduction, and feasibility work.
- Set and justify construction, sampling, and retry budgets from optimized application-
  shaped benchmarks, and preserve every attempted derived seed in solver provenance.
