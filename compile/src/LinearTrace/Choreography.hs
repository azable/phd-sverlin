{-# LANGUAGE LinearTypes         #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Module      : LinearTrace.Choreography
-- Description : Complete public contract for the Sverlin choreography DSL.
-- Stability   : experimental
-- Portability : GHC with linear types
--
-- This facade is the only supported import for authored Sverlin programs. It
-- deliberately combines the linear trace language, semantic queries, visual
-- node hierarchy, styles, layout expressions, and constraints into one public
-- vocabulary. Modules beneath @LinearTrace.Choreography@ are implementation
-- details unless this module re-exports their names.
--
-- = Execution and ownership model
--
-- A 'Choreography' first constructs an immutable semantic trace. Linear
-- lifecycle operations return 'Pending' obligations; each obligation must be
-- resolved exactly once by materializing, committing, destroying, or otherwise
-- consuming it through the corresponding lifecycle API. Visual rules are
-- separately compiled into a 'MatchSpec' and applied to materialized trace
-- blocks when 'buildViewGraph' runs.
--
-- = Visual hierarchy and inheritance
--
-- 'node' is the single hierarchy primitive. A generated node may contain trace
-- selections, generated nodes, or whole query selections. Every child is
-- constrained to its parent's content box. Parent style fields cascade to
-- descendants unless a descendant explicitly overrides or removes the field.
-- Generated groups are ordinary nodes: their layout handles, padding, margin,
-- content, styles, and constraints use the same API as leaf nodes.
--
-- = Geometry and text
--
-- Layout expressions are affine and typed as coordinates, spans, offsets, or
-- unitless scalars. Percentage pins are resolved against the parent content
-- box. 'fitText' makes font size a solver decision capped by the authored font
-- size, so text fills available node space without trial-and-error resizing.
--
-- = Documentation contract
--
-- Every explicit export below carries its canonical behavioral summary. The
-- repository's @scripts/dsl-api-index.mjs@ validates this invariant and combines
-- the descriptions with GHC-inferred signatures in the machine-readable/Markdown
-- API index supplied to the AI authoring system.
-- Add or change an export and its description together; never document private
-- implementation names as public DSL affordances.
module LinearTrace.Choreography
  ( -- * Program and graph execution #execution#
    -- | Linear program builder that records semantic trace events.
    Choreography
  , -- | Trace plus compiled visual rules, ready to become a solver graph.
    VisualTraceGraph
  , -- | Solver-ready visual graph containing nodes, choices, and constraints.
    ViewGraph
  , -- | Compile a completed visual trace into its solver-ready graph.
    buildViewGraph
  , -- | Solve one graph deterministically from one random seed.
    solveViewGraphWithSeed
  , -- | Solve the same graph independently for every supplied seed.
    solveViewGraphWithSeeds
  , -- | Re-solve while pinning values supplied by an earlier solution.
    solveViewGraphWithPinnedSolution
  , -- | Return graph size statistics for diagnostics and benchmarks.
    viewGraphStats
  , -- | Run a trace program without authored visual matching rules.
    runChoreography
  , -- | Run a trace program with an explicit visual rule specification.
    runChoreographyWith
  , -- | Run with explicit rules plus conservative automatic style defaults.
    runChoreographyWithGenerativeStyles
  , -- * Linear resources and lifecycle #lifecycle#
    -- | Stable handle to a materialized semantic block in the trace.
    Block
  , -- | Alias for the core trace slot handle used by low-level integrations.
    SlotHandle
  , -- | Typed payload stored by a trace block.
    Payload
  , -- | Start the lifecycle of a new payload and return its pending obligation.
    create
  , -- | Duplicate an eligible block, returning the original and pending copy.
    copy
  , -- | Consume a block for one linear observation/use operation.
    use
  , -- | Apply one registered unary operator to a consumed input.
    apply1
  , -- | Apply one registered binary operator to two consumed inputs.
    apply2
  , -- | Replace a consumed block with a pending replacement payload.
    replace
  , -- | Materialize a pending value with facts derived from a 'Query'.
    materialize
  , -- | Materialize with base facts and additional facts derived from payload.
    materializeWithTags
  , -- | Materialize a pending value without adding semantic facts.
    commit
  , -- | Consume a live block and record its removal from the semantic trace.
    destroy
  , -- | Attach a materialized event to the visible trace checkpoint sequence.
    checkpoint
  , -- * Facts and semantic queries #facts#
    -- | Primitive semantic fact values: atoms, symbols, and integers.
    FactValue(..)
  , -- | Named semantic fact attached to a materialized block.
    Fact(..)
  , -- | Ordered collection of semantic facts used by matching queries.
    Facts(..)
  , -- | A fact collection containing no facts.
    emptyFacts
  , -- | Construct an atom-valued fact.
    factAtom
  , -- | Construct a symbol-valued fact.
    factSymbol
  , -- | Construct an integer-valued fact.
    factInt
  , -- | Combine fact collections for materialization or matching.
    factsUnion
  , -- | Expose facts as an ordered list for external integrations.
    factsToList
  , -- | Renderable, non-linear snapshot of a typed payload.
    PayloadView(..)
  , -- | Payload class whose values can participate in a linear trace.
    Traceable
  , -- | Semantic fact query used both for tagging and block selection.
    Query
  , -- | Integer captured from a matching query for use in layout expressions.
    QueryInt
  , -- | Query that imposes no semantic predicates.
    emptyQuery
  , -- | Query predicate requiring a named atom fact.
    queryAtom
  , -- | Query predicate requiring a named integer fact and exposing its value.
    queryInt
  , -- | Convert a query into facts suitable for materialization.
    queryFacts
  , -- * Built-in payload and operator vocabulary #payloads#
    -- | Linear unit payload.
    LUnit(..)
  , -- | Linear Boolean payload.
    LBool(..)
  , -- | Linear integer payload.
    LInt(..)
  , -- | Linear floating-point payload.
    LDouble(..)
  , -- | Linear string payload.
    LString(..)
  , -- | Named linear operator carried in the semantic trace.
    LOperator(..)
  , -- | Class defining display and persistence behavior for operator payloads.
    CoreOperator(..)
  , -- | Class for safely unpacking and rebuilding linear payload wrappers.
    LinearPayload(..)
  , -- | Apply a unary linear operator and return its pending result.
    applyLinear1
  , -- | Apply a unary operator into an explicitly supplied output payload.
    applyLinear1Into
  , -- | Apply a binary linear operator and return its pending result.
    applyLinear2
  , -- | Apply a binary operator into an explicitly supplied output payload.
    applyLinear2Into
  , -- | Typeclass for payloads accepted by unary operators.
    Applicable1(..)
  , -- | Typeclass for payloads accepted by binary operators.
    Applicable2(..)
  , -- * Lifecycle result wrappers #results#
    -- | Unresolved lifecycle output that linear code must consume exactly once.
    Pending
  , -- | Result of consuming one materialized block.
    OneUse(..)
  , -- | Result wrapper produced by creation.
    Create(..)
  , -- | Result wrapper produced by non-consuming observation.
    Observe(..)
  , -- | Result wrapper produced by one-use consumption.
    Use(..)
  , -- | Result wrapper produced by copying.
    Copy(..)
  , -- | Result wrapper produced by replacement.
    Replace(..)
  , -- | Result wrapper produced by unary application.
    Apply1(..)
  , -- | Result wrapper produced by binary application.
    Apply2(..)
  , -- | Result wrapper produced by destruction.
    Destroy(..)
  , -- | Result wrapper produced when sealing an exposed payload.
    Seal(..)
  , -- | Result wrapper produced when unsealing a payload.
    Unseal(..)
  , -- | Linear functor mapping for composing lifecycle results.
    (<$>)
  , -- | Linear applicative application for composing lifecycle results.
    (<*>)
  , -- * Visualization rules and selections #selection#
    -- | Compiled collection of selections, node declarations, edits, and rules.
    MatchSpec
  , -- | Typed query whose matches can be bound as visual trace nodes.
    TraceQuery
  , -- | Reference to one declared visual node or the canvas.
    Selected
  , -- | Solver-backed reusable value introduced inside visual rules.
    Variable(..)
  , -- | Value captured from the current query match.
    Bound(..)
  , -- | Explicit node handle returned by generated-parent declarations.
    NodeBinding(..)
  , -- | Existential payload marker for heterogeneous trace selections.
    AnyPayload
  , -- | Linear builder that accumulates visual declarations and constraints.
    VisualizationBuilder
  , -- | Select trace payloads matching a semantic query.
    select
  , -- | Overloaded selection class for typed and heterogeneous payload queries.
    Select
  , -- | Append compatible query predicates or visual query fragments.
    QueryAppend
  , -- | Compile a completed visualization builder into a reusable rule spec.
    visualize
  , -- | Append query fragments with the visual-query composition operator.
    (<&>)
  , -- * Node hierarchy and content #nodes#
    -- | Overloaded hierarchy primitive for leaves, generated parents, and binds.
    Node
  , -- | Assign fixed textual content to the current node.
    content
  , -- | Assign text whose font size is solved to fill the current node, subject to caps.
    fitText
  , -- | Assign source-code content to the current node.
    codeContent
  , -- | Enable soft wrapping for the enclosed code-content recipe.
    codeWrap
  , -- | Apply language-aware syntax highlighting to the enclosed code recipe.
    highlightCode
  , -- | Half-open source range measured in character offsets.
    CodeRange
  , -- | Construct a half-open source range from start and end offsets.
    codeRange
  , -- | Emphasize source ranges while the named checkpoint is visible.
    emphasizeCode
  , -- | Use the selected trace payload's display text as node content.
    payload
  , -- | Declare a trace node or create a generated parent around child declarations.
    node
  , -- | Bind the current generated parent from inside its node body.
    self
  , -- | Root canvas selection; it participates in ordinary layout constraints.
    canvas
  , -- | Construct literal textual content.
    text
  , -- | Content expression accepted by text and code content functions.
    ContentValue
  , -- * Reusable values and finite decisions #variables#
    -- | Bind the current query's captured integer for later reuse.
    bindInt
  , -- | Bind the current query's payload display text for later reuse.
    bindContent
  , -- | Create a fresh named solver value using its type's intrinsic domain.
    variable
  , -- | Wrap an existing DSL value for reuse through the 'Variable' pattern.
    variableFrom
  , -- | Create a named finite categorical choice from a non-empty domain.
    choice
  , -- | Values that can inhabit a finite solver choice.
    ChoiceDomain(..)
  , -- | Solver-backed finite categorical decision.
    Choice
  , -- | Deterministic random seed used for solver initialization.
    RandomSeed(..)
  , -- * Typed layout values and geometry #layout#
    -- | Absolute horizontal or vertical position.
    Coord
  , -- | Non-negative width or height.
    Span
  , -- | Signed displacement between positions.
    Offset
  , -- | Unitless numeric expression.
    Scalar
  , -- | Overloaded left-edge accessor or assignment.
    Left
  , -- | Overloaded top-edge accessor or assignment.
    Top
  , -- | Overloaded right-edge accessor or assignment.
    Right
  , -- | Overloaded bottom-edge accessor or assignment.
    Bottom
  , -- | Overloaded width accessor or assignment.
    Width
  , -- | Overloaded height accessor or assignment.
    Height
  , -- | Overloaded horizontal-center accessor or assignment.
    X
  , -- | Overloaded vertical-center accessor or assignment.
    Y
  , -- | Set or read both center coordinates as a typed vector.
    Center(..)
  , -- | Read the horizontal center of a selected node.
    x
  , -- | Read the vertical center of a selected node.
    y
  , -- | Read the left edge of a selected node.
    left
  , -- | Read the top edge of a selected node.
    top
  , -- | Read the right edge of a selected node.
    right
  , -- | Read the bottom edge of a selected node.
    bottom
  , -- | Read the width of a selected node.
    width
  , -- | Read the height of a selected node.
    height
  , -- | Read width and height together as a typed vector.
    size
  , -- | Constrain all four bounds of the current node at once.
    bounds
  , -- | Two-dimensional value used for centers, sizes, and vector arithmetic.
    Vec2(..)
  , -- | Construct a two-dimensional value from its components.
    vec2
  , -- | Construct an absolute pixel coordinate.
    at
  , -- | Construct a non-negative pixel span.
    by
  , -- | Construct a signed pixel displacement.
    shift
  , -- | Read an integer captured by a zero-based query binding index.
    queryIndex
  , -- | Interpret a captured query integer as a unitless scalar.
    asUnit
  , -- | Reinterpret a signed offset as a coordinate expression.
    asCoord
  , -- | Reinterpret a signed offset as a span expression.
    asSpan
  , -- | Construct a solver numeric literal in an inferred typed domain.
    num
  , -- | Overloaded integer literal conversion for DSL numeric values.
    fromInteger
  , -- | Overloaded rational literal conversion for DSL numeric values.
    fromRational
  , -- | Add compatible typed layout values.
    (+)
  , -- | Subtract compatible typed layout values.
    (-)
  , -- | Scale a layout value or multiply compatible scalar values.
    (*)
  , -- | Divide a layout value by a scalar expression.
    (/)
  , -- | Add two non-negative spans while preserving the span domain.
    (|+|)
  , -- * Hierarchical box model #box-model#
    -- | Four edge values ordered as top, right, bottom, and left.
    Insets
  , -- | Construct equal insets on every edge.
    uniform
  , -- | Construct vertical and horizontal inset pairs.
    symmetric
  , -- | Construct independent top, right, bottom, and left insets.
    edges
  , -- | Set the current node's internal child/content insets.
    padding
  , -- | Set the current node's external edge spacing.
    margin
  , -- | Layout axis used by content-fit rules.
    Axis(..)
  , -- | Policy controlling how a parent fits around its children.
    ContentFit(..)
  , -- | Set the current node's child-fitting policy.
    contentFit
  , -- | Percentage in the inclusive 0 to 100 parent-relative domain.
    Percent
  , -- | Construct a validated parent-relative percentage.
    percent
  , -- | Pin the current node's horizontal center within its parent content box.
    xAt
  , -- | Pin the current node's vertical center within its parent content box.
    yAt
  , -- | Set width as a percentage of the parent content width.
    widthOf
  , -- | Set height as a percentage of the parent content height.
    heightOf
  , -- * Style authoring and cascade #styles#
    -- | Type-directed style assignment, including fixed and finite-choice values.
    StyleChoice(..)
  , -- | Set or override one style field on the current node.
    style
  , -- | Explicitly remove an inherited or automatic style field.
    withoutStyle
  , -- | Select a style value from a named finite decision.
    styleCase
  , -- | Set a semantic family shared by automatic descendant styling.
    styleFamily
  , -- | Read a selected node's style field as a constraint expression.
    styleOf
  , -- | Convert colour saturation to a unitless scalar expression.
    sat
  , -- | Complete accumulated style plan for a node.
    NodeStyle
  , -- | Opacity style field in the unit interval.
    Opacity
  , -- | Z-order style field.
    ZIndex
  , -- | Font-size style field in pixels; with 'fitText' it acts as a cap.
    FontSize
  , -- | Corner-radius style field.
    Radius
  , -- | Border/stroke-width style field.
    StrokeWidth
  , -- | Colour alpha-channel style field.
    Alpha
  , -- | Fill-colour style field.
    Fill
  , -- | Stroke-colour style field.
    Stroke
  , -- | Finite border-line styles.
    BorderStyle(..)
  , -- | Finite font-family choices.
    FontFamily(..)
  , -- | Finite font-weight choices.
    FontWeight(..)
  , -- | Finite font-style choices.
    FontStyle(..)
  , -- | Finite text-alignment choices.
    TextAlign(..)
  , -- | Finite whitespace/wrapping choices.
    WhiteSpace(..)
  , -- * Visual constraints and alternatives #constraints#
    -- | Add a hard constraint that every valid solution must satisfy.
    ensure
  , -- | Add a soft relation that improves ranking without invalidating solutions.
    encourage
  , -- | Named branch containing the constraints for one finite visual alternative.
    VisualAlternative
  , -- | Construct one named visual alternative branch.
    alternative
  , -- | Require exactly one named alternative from a non-empty set.
    oneOf
  , -- | Apply branch-specific visual rules for a finite choice.
    caseOf
  , -- | Attach a query, binding, or selection to a visual rule body.
    (@:)
  , -- | Less-than-or-equal relation for compatible numeric expressions.
    (.<=.)
  , -- | Greater-than-or-equal relation for compatible numeric expressions.
    (.>=.)
  , -- | Equality relation for compatible numeric expressions.
    (.==.)
  , -- | Directed affine bridge: left plus gap equals right.
    (=|)
  , -- | Start a symmetric-distance bridge whose magnitude is supplied by '(=/)'.
    (=/)
  , -- | Complete a directed affine bridge begun by '(=|)'.
    (|=)
  , -- | Complete a symmetric-distance bridge, or require categorical inequality.
    (/=)
  , -- * Primitive solver values and colour #primitives#
    -- | Four-component bounds value.
    Bounds(..)
  , -- | Hue, saturation, and lightness colour expression.
    Hsl(..)
  , -- | Unbounded numeric solver domain marker.
    Free
  , -- | Unit-interval numeric solver domain marker.
    Unit
  , -- | Angular numeric solver domain marker.
    Angle
  , -- | Colour expression used by fill and stroke styles.
    Color
  , -- | Refer to a stable named global solver variable.
    global
  , -- | Overloaded-label entry point used by semantic query syntax.
    fromLabel
  ) where

import           GHC.OverloadedLabels                (IsLabel (fromLabel))
import           LinearTrace.Choreography.Box
import           LinearTrace.Choreography.Constraint
import           LinearTrace.Choreography.Graph
import           LinearTrace.Choreography.Layout
import           LinearTrace.Choreography.Match      (MatchSpec)
import           LinearTrace.Choreography.Node
import           LinearTrace.Choreography.Style
import           LinearTrace.Choreography.Variable
import           LinearTrace.Core                    hiding (materialize)
import qualified LinearTrace.Core                    as C
import           LinearTrace.View.Primitives         (Angle, Bounds (..), Color,
                                                      Free, Hsl (..), Unit)
import           LinearTrace.View.Style              (Alpha, BorderStyle (..),
                                                      Fill, FontFamily (..),
                                                      FontSize, FontStyle (..),
                                                      FontWeight (..),
                                                      NodeStyle, Opacity,
                                                      Radius, Stroke,
                                                      StrokeWidth,
                                                      TextAlign (..),
                                                      WhiteSpace (..), ZIndex)
import           Solver                              (Choice, ChoiceDomain (..),
                                                      RandomSeed (..),
                                                      Vec2 (..), vec2)

type Choreography a = TraceBuilder a

type SlotHandle = Slot

materialize ::
     forall tag. Traceable tag
  => Query
  -> Pending tag
     %1 -> Choreography (Block tag)
materialize query = C.materializeTagged (queryFacts query)

materializeWithTags ::
     forall tag. Traceable tag
  => Query
  -> (Payload tag -> Query)
  -> Pending tag
     %1 -> Choreography (Block tag)
materializeWithTags query selectQuery =
  C.materializeTaggedWith (queryFacts query) selectFacts
  where
    selectFacts outputPayload = queryFacts (selectQuery outputPayload)
