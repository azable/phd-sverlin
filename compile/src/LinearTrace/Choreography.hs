{-# LANGUAGE LinearTypes         #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Public choreography DSL facade.
module LinearTrace.Choreography
  ( -- * Defined here: choreography and view graph facade
    -- | Direct choreography builder API. Core lifecycle helpers return pending
    -- block obligations; materialization attaches visual facts and checkpoints
    -- attach materialized events to view output.
    Choreography
  , VisualTraceGraph
  , ViewGraph
  , buildViewGraph
  , solveViewGraphWithSeed
  , viewGraphStats
  , runChoreography
  , runChoreographyWith
  , create
  , copy
  , use
  , apply1
  , apply2
  , replace
  , materialize
  , materializeWithTags
  , commit
  , destroy
  , checkpoint
  , -- * Re-exported or aliased from LinearTrace.Core
    -- | Core linear handles, payload/fact vocabulary, event-token aliases,
    -- traceable payload classes, and linear functor operators used directly by
    -- the DSL.
    Block
  , SlotHandle
  , Payload
  , FactValue(..)
  , Fact(..)
  , Facts(..)
  , emptyFacts
  , factAtom
  , factSymbol
  , factInt
  , factsUnion
  , factsToList
  , PayloadView(..)
  , Traceable
  , LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , LOperator(..)
  , CoreOperator(..)
  , LinearPayload(..)
  , applyLinear1
  , applyLinear1Into
  , applyLinear2
  , applyLinear2Into
  , Applicable1(..)
  , Applicable2(..)
  , Pending
  , OneUse(..)
  , Create(..)
  , Observe(..)
  , Use(..)
  , Copy(..)
  , Replace(..)
  , Apply1(..)
  , Apply2(..)
  , Destroy(..)
  , Seal(..)
  , Unseal(..)
  , (<$>)
  , (<*>)
  , -- * Re-exported from LinearTrace.Core
    -- | Query syntax and query-derived facts used to match trace blocks and
    -- generated nodes.
    Query
  , QueryInt
  , emptyQuery
  , queryAtom
  , queryInt
  , queryFacts
  , -- * Re-exported from LinearTrace.Choreography.Match
    -- | Compiled query/patch/constraint rules consumed by the view graph
    -- builder.
    MatchSpec
  , -- * Re-exported from LinearTrace.Choreography.Node
    -- | Shared choreography handles, selections, recipes, variables, and DSL
    -- values.
    TraceQuery
  , Selected
  , Variable(..)
  , Bound(..)
  , NodeBinding(..)
  , AnyPayload
  , VisualizationBuilder
  , Coord
  , Span
  , Offset
  , Scalar
  , NodeRecipe
  , ContentValue
  , text
  , -- * Re-exported from LinearTrace.Choreography.Node
    -- | Selection, content, grouping, rendering, and query composition helpers.
    Node
  , Select
  , select
  , QueryAppend
  , visualize
  , content
  , payload
  , node
  , render
  , (<&>)
  , -- * Re-exported from LinearTrace.Choreography.Style
    -- | Type-applied style assignment and selected-style access.
    StyleChoice(..)
  , style
  , styleOf
  , sat
  , -- * Re-exported from LinearTrace.View.Style
    -- | Style field marker types and concrete style choice domains from the
    -- view layer.
    NodeStyle
  , Opacity
  , ZIndex
  , Padding
  , FontSize
  , Radius
  , StrokeWidth
  , Alpha
  , Fill
  , Stroke
  , BorderStyle(..)
  , FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , WhiteSpace(..)
  , -- * Re-exported from LinearTrace.View.Primitives
    -- | Solver-backed view primitive domains and compound values.
    Bounds(..)
  , Hsl(..)
  , Free
  , Unit
  , Angle
  , Color
  , -- * Re-exported from Solver
    -- | Solver-facing random seed and vector constructor used by the public DSL.
    RandomSeed(..)
  , Vec2(..)
  , vec2
  , -- * Re-exported from GHC.OverloadedLabels
    -- | Overloaded label entrypoint used by the query/tag DSL.
    fromLabel
  , -- * Defined here: layout, variables, and constraints
    -- | Choreography-level constructors, overloaded layout accessors, and
    -- visual relation operators.
    Left
  , Top
  , Right
  , Bottom
  , Width
  , Height
  , X
  , Y
  , Center(..)
  , asUnit
  , asCoord
  , asSpan
  , at
  , queryIndex
  , bottom
  , bounds
  , by
  , bindContent
  , bindInt
  , ensure
  , variable
  , variableFrom
  , choice
  , encourage
  , global
  , height
  , left
  , num
  , fromInteger
  , fromRational
  , right
  , shift
  , size
  , top
  , width
  , x
  , y
  , (+)
  , (-)
  , (*)
  , (/)
  , (@:)
  , (.<=.)
  , (.>=.)
  , (.==.)
  , (=|)
  , (=/)
  , (|+|)
  , (|=)
  , (/=)
  ) where

import           GHC.OverloadedLabels                (IsLabel (fromLabel))
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
                                                      Padding, Radius, Stroke,
                                                      StrokeWidth,
                                                      TextAlign (..),
                                                      WhiteSpace (..), ZIndex)
import           Solver                              (RandomSeed (..),
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
