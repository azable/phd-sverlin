{-# LANGUAGE AllowAmbiguousTypes     #-}
{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE FunctionalDependencies  #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE NoImplicitPrelude       #-}
{-# LANGUAGE TypeApplications        #-}
{-# LANGUAGE TypeFamilies            #-}
{-# LANGUAGE UndecidableSuperClasses #-}

-- |
-- Module      : Sverlin
-- Description : Complete authored API for body-only Sverlin programs.
--
-- A source declares a seeded 'Domain', consumes it through one linear
-- 'Program', and independently describes its views with 'Render'.  This is the
-- only module imported into authored source; compiler support and solver types
-- remain behind the generated-source boundary.
module Sverlin
  ( -- * Builders and do notation
    -- | Seeded, constructive initialization whose result crosses linearly into Program.
    Domain
  , -- | Linear semantic program that records resource lifetimes and typed steps.
    Program
  , -- | Declarative visual-rule builder compiled after the semantic trace is known.
    Render
  , -- | Bind according to the builder's compiler-owned multiplicity.
    (>>=)
  , -- | Sequence according to the builder's compiler-owned multiplicity.
    (>>)
  , -- | Lift a value using the current builder's multiplicity.
    pure
  , -- | Compatibility spelling used by RebindableSyntax.
    return
  , -- | Turn a failed pattern match into a builder diagnostic.
    fail
  , -- * Domain vocabulary
    -- | Typed classification assigned when a pending value is materialized.
    Kind
  , -- | Define a Kind using a type-applied stable identity marker.
    kind
  , -- | Register one Kind before it is used.
    declareKind
  , -- | Typed semantic relation between stable Slot owners.
    RelationKind
  , -- | Define a relation whose source and target roles are distinct.
    orderedRelation
  , -- | Define a same-typed relation for which reversing endpoints is equivalent.
    symmetricRelation
  , -- | Register one RelationKind before it is used.
    declareRelation
  , -- | Register a type-level list of step marker types.
    declareSteps
  , -- * Scenario generation
    -- | Ordinary seeded generator used only while Domain constructs input.
    Generator
  , -- | Sample a Domain generator or create a Render numeric variable, selected by context.
    variable
  , -- | Sample an inclusive uniform integer range.
    between
  , -- | Choose uniformly from a statically non-empty list of values.
    elementOf
  , -- | Choose among generators using positive integer weights.
    weighted
  , -- | Generate an ordinary list with a uniformly sampled bounded length.
    listOf
  , -- | Produce a uniform permutation of an ordinary list.
    shuffle
  , -- * Payloads and operators
    -- | Author-defined trace marker with one trusted linear payload representation.
    Traceable(Payload)
  , -- | Trusted linear unit payload.
    LUnit(..)
  , -- | Trusted linear Boolean payload.
    LBool(..)
  , -- | Trusted linear integer payload.
    LInt(..)
  , -- | Trusted linear floating-point payload.
    LDouble(..)
  , -- | Trusted linear string payload.
    LString(..)
  , -- | Stateless typed operator payload.
    LOperator(..)
  , -- | Author-defined unary payload operation.
    Applicable1(Apply1Result, applyPayload1)
  , -- | Author-defined binary payload operation.
    Applicable2(Apply2Result, applyPayload2)
  , -- * Linear lifecycle
    -- | Sole live capability for one materialized semantic value.
    Block
  , -- | Unfinished value that must be materialized exactly once.
    Pending
  , -- | Stable owner capability retaining one hidden occupant.
    Slot
  , -- | Result wrapper produced by create.
    Create(..)
  , -- | Result wrapper exposing a terminally consumed payload.
    Use(..)
  , -- | Result wrapper containing the original Block and a pending fork.
    Copy(..)
  , -- | Result wrapper containing a pending replacement.
    Replace(..)
  , -- | Result wrapper containing a unary-operation output.
    Apply1(..)
  , -- | Result wrapper containing a binary-operation output.
    Apply2(..)
  , -- | Result wrapper confirming terminal destruction.
    Destroy(..)
  , -- | Result wrapper containing the owner and its occupied Slot.
    Seal(..)
  , -- | Result wrapper recovering the owner and current occupant.
    Unseal(..)
  , -- | Result wrapper reissuing both related Slot capabilities.
    Relate(..)
  , -- | Begin one payload lifetime as a pending value.
    create
  , -- | Assign one declared Kind to a pending value.
    materialize
  , -- | Hide a value inside one stable owner Slot.
    seal
  , -- | Add a persistent relation between two Slot owners.
    relate
  , -- | Fork a live Block while preserving its original capability.
    copy
  , -- | Terminally consume a Block and expose its linear payload.
    use
  , -- | Consume an operator and argument to produce one pending result.
    apply1
  , -- | Consume an operator and two arguments to produce one pending result.
    apply2
  , -- | End a Block and attach a pending successor to its lineage.
    replace
  , -- | End a Block without a successor.
    destroy
  , -- | Recover a Slot owner and its current occupant.
    unseal
  , -- | Record a typed, nestable step around one Program action.
    step
  , -- * Presence and frames
    -- | Include every component produced by an action.
    always
  , -- | Give components produced by an action one scoped include/omit choice.
    sometimes
  , -- | Expose all runtime occurrences of one declared typed step.
    frame
  , -- * Selections, hierarchy, and relations
    -- | Typed set of semantic matches or a generated visual node handle.
    Selected
  , -- | Typed set of active semantic relation matches.
    Relations
  , -- | Marker type for an authored generated node.
    GeneratedNode
  , -- | Marker type for the persistent canvas root.
    CanvasNode
  , -- | Select a Kind or RelationKind using closed compiler dispatch.
    select
  , -- | Map a selection or create a generated node using closed compiler dispatch.
    node
  , -- | Return the current generated-node handle.
    self
  , -- | Persistent canvas geometry handle.
    canvas
  , -- | Restrict member selections through one ordered membership relation.
    within
  , -- | Evaluate a visual rule once per active relation occurrence.
    relation
  , -- | Return the source endpoint inside the matching relation scope.
    first
  , -- | Return the target endpoint inside the matching relation scope.
    second
  , -- * Validated structure and arrangements
    -- | Validated structural rank associated with a node selection.
    Ranking
  , -- | Compiler-fixed integer available inside the matching node scope.
    FixedInt
  , -- | Validate one selected relation graph as a complete sequence.
    asSequence
  , -- | Validate one selected relation graph as a rooted tree.
    asTree
  , -- | Validate one selected relation graph as a directed acyclic graph.
    asDag
  , -- | Read sequence position, tree depth, or DAG level in the current node.
    rankOf
  , -- | Convert a FixedInt into a fixed affine scalar.
    asScalar
  , -- | Convert a FixedInt into decimal text.
    asText
  , -- | Read the current selected numeric payload as a fixed affine scalar.
    payloadScalar
  , -- | Prepared deterministic layout template.
    Arrangement(..)
  , -- | Apply one prepared arrangement to a node selection.
    arrange
  , -- * Text
    -- | Whole-line text builder with optional typed fragment ranges.
    TextBuilder
  , -- | Completed single-line text value.
    ContentValue
  , -- | Construct literal single-line text.
    text
  , -- | Append literal text to a TextBuilder.
    literal
  , -- | Append text associated with one typed step.
    fragment
  , -- | Append text associated with any of several typed steps.
    fragmentMany
  , -- | Read the current selected payload's display text.
    bindContent
  , -- | Shape one fixed-size, non-wrapping line.
    content
  , -- | Shape one non-wrapping line at a feasible size shared by its node-mapping lineage.
    fitText
  , -- * Connectors
    -- | Typed endpoint and placement for a straight connector.
    ConnectorAnchor
  , -- | Supported connector attachment positions.
    AnchorPlacement(..)
  , -- | Create a connector endpoint from a mapped node.
    anchor
  , -- | Supported connector endpoint markers.
    Marker(..)
  , -- | Draw a straight connector without adding layout constraints.
    connector
  , -- | Set the connector's starting marker.
    startMarker
  , -- | Set the connector's ending marker.
    endMarker
  , -- * Solver-backed values and choices
    -- | Abstract finite categorical value selected by Render.
    Choice
  , -- | Create one finite built-in categorical choice.
    choice
  , -- | Apply Render actions for every value of an existing Choice.
    caseOf
  , -- | Typed horizontal or vertical position.
    Coord
  , -- | Non-negative size or distance.
    Span
  , -- | Signed positional difference.
    Offset
  , -- | Unitless affine numeric value.
    Scalar
  , -- | Bounded value from zero through one.
    Unit
  , -- | Bounded cyclic angle value.
    Angle
  , -- | Opaque typed affine expression.
    VisualExpr
  , -- | Two-dimensional value with matching component types.
    Vec2(..)
  , -- | Construct a two-dimensional value.
    vec2
  , -- | Construct a fixed coordinate.
    at
  , -- | Construct a fixed span.
    by
  , -- | Construct a fixed signed offset.
    shift
  , -- | Construct a fixed value inferred from its numeric role.
    num
  , -- | Add compatible affine values component-wise.
    (.+.)
  , -- | Subtract compatible affine values component-wise.
    (.-.)
  , -- | Multiply when at least one factor is fixed before solving.
    (.*.)
  , -- | Divide by a fixed non-zero scalar.
    (./.)
  , -- * Geometry and box model
    -- | Read or set a node's left edge using closed dispatch.
    left
  , -- | Read or set a node's top edge using closed dispatch.
    top
  , -- | Read or set a node's right edge using closed dispatch.
    right
  , -- | Read or set a node's bottom edge using closed dispatch.
    bottom
  , -- | Read or set a node's width using closed dispatch.
    width
  , -- | Read or set a node's height using closed dispatch.
    height
  , -- | Read or set a node's horizontal centre using closed dispatch.
    x
  , -- | Read or set a node's vertical centre using closed dispatch.
    y
  , -- | Read or set both centre coordinates.
    center
  , -- | Read both node spans; use 'width' and 'height' to set them.
    size
  , -- | Four typed edge inset expressions.
    Insets
  , -- | Use one inset on all four edges.
    uniform
  , -- | Use separate vertical and horizontal insets.
    symmetric
  , -- | Set top, right, bottom, and left insets explicitly.
    edges
  , -- | Set the current node's inner padding.
    padding
  , -- | Set the current node's outer margin.
    margin
  , -- | Axis selected by content-fitting operations.
    Axis(..)
  , -- | Whether an axis hugs children or only contains them.
    ContentFit(..)
  , -- | Set content fitting for one or both axes.
    contentFit
  , -- | Valid parent-relative percentage.
    Percent
  , -- | Construct a percentage from zero through one hundred.
    percent
  , -- | Pin horizontal centre to a parent percentage.
    xAt
  , -- | Pin vertical centre to a parent percentage.
    yAt
  , -- | Pin width to a parent percentage.
    widthOf
  , -- | Pin height to a parent percentage.
    heightOf
  , -- | Relate current width and height by a positive ratio.
    aspectRatio
  , -- | Require two mapped rectangles not to overlap by at least a gap.
    separatedBy
  , -- * Styles and colour
    -- | Set one supported style field; connectors accept opacity and stroke fields only.
    style
  , -- | Remove one inherited style field.
    withoutStyle
  , -- | Read one final style field as a symbolic value.
    styleOf
  , -- | Whole-node opacity field marker.
    Opacity
  , -- | Text size field marker.
    FontSize
  , -- | Corner radius field marker.
    Radius
  , -- | Border or connector width field marker.
    StrokeWidth
  , -- | Paint alpha field marker.
    Alpha
  , -- | Hue, saturation, and lightness value.
    Hsl(..)
  , -- | HSL colour with typed angle and unit components.
    Color
  , -- | Fill paint field marker.
    Fill
  , -- | Stroke paint field marker.
    Stroke
  , -- | Supported distinct border rendering styles.
    BorderStyle(..)
  , -- | Font catalogue classification.
    FontKind(..)
  , -- | Abstract font catalogue filter.
    FontFilter
  , -- | Filter concrete fonts by catalogue classification.
    fontKind
  , -- | Create a unique concrete font-family Choice matching a filter.
    fontChoice
  , -- | Concrete bundled font families.
    FontFamily(..)
  , -- | Canonical fixed and numeric font-weight forms.
    FontWeight(..)
  , -- | Available real font face styles.
    FontStyle(..)
  , -- | Single-line horizontal text alignment.
    TextAlign(..)
  , -- * Constraints and alternatives
    -- | Opaque exact visual constraint.
    VisualConstraint
  , -- | Add a required constraint to the current scope.
    ensure
  , -- | Require the left affine value not to exceed the right.
    (.<=.)
  , -- | Require the left affine value not to be below the right.
    (.>=.)
  , -- | Require two compatible affine values to be equal.
    (.==.)
  , -- | Labelled authored Render alternative.
    VisualAlternative
  , -- | Associate one label with a complete Render action.
    alternative
  , -- | Select exactly one non-empty authored alternative.
    oneOf
  ) where

import           Data.Kind                 (Constraint)
import           Data.Type.Equality        (type (~))
import           Data.Typeable             (Typeable)
import           Prelude                   (Bool (..))
import qualified Sverlin.Internal.Render   as Render
import           Sverlin.Internal.Render   hiding (ChoiceDomain)
import qualified Sverlin.Internal.Semantic as Semantic
import           Sverlin.Internal.Semantic hiding (variable)
import           Sverlin.Syntax            (fail, pure, return, (>>), (>>=))

data VariableMode
  = DomainMode
  | RenderMode

type family VariableModeOf identity where
  VariableModeOf (VisualExpr value) = 'RenderMode
  VariableModeOf identity = 'DomainMode

type family VariableCompatibility (mode :: VariableMode) identity result :: Constraint where
  VariableCompatibility 'RenderMode identity (Render value) = (identity ~ value)
  VariableCompatibility mode identity result = ()

class VariableCompatibility mode identity result =>
      Variable mode identity result
  where
  variableValue :: result

variable ::
     forall identity result. Variable (VariableModeOf identity) identity result
  => result
variable = variableValue @(VariableModeOf identity) @identity @result

instance Typeable identity =>
         Variable 'DomainMode identity (Generator value -> Domain value) where
  variableValue = Semantic.variable @identity

instance RenderVariable value => Variable 'RenderMode value (Render value) where
  variableValue = freshVariable @value

class Select selector result | selector -> result where
  selectValue :: selector -> Render result

select :: Select selector result => selector -> Render result
select = selectValue

instance Select (Kind tag) (Selected tag) where
  selectValue handle = selectKind (kindIdentity handle)

instance Select (RelationKind source target) (Relations source target) where
  selectValue handle =
    selectRelation
      (relationIdentity handle)
      (case relationDirection handle of
         OrderedRelation   -> True
         SymmetricRelation -> False)

choice ::
     forall value. Render.ChoiceDomain value
  => Render (Choice value)
choice = freshChoice @value
