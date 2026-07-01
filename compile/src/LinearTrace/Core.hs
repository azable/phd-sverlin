{-# LANGUAGE TypeFamilies #-}

-- | Stable facade for the linear trace core. It re-exports the direct trace
-- builder API from 'LinearTrace.Core.Internal' while hiding internal graph state
-- constructors that only event projection and diagnostics should need.
module LinearTrace.Core
  ( -- * Core public API data
    -- | Direct trace graph and payload vocabulary. Choreography depends on
    -- this layer for typed payload handles and trace lifecycle operations.
    TraceGraph
  , TraceGraphWith
  , TraceBuilder
  , TraceBuilderWith
  , Block
  , Slot
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
  , payloadText
  , Traceable
  , -- * Trusted linear payloads
    -- | Built-in payload wrappers used by examples/tests and by the
    -- choreography DSL's public payload vocabulary.
    LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , -- * Action vocabulary
    -- | Type-level action tags recorded by the core builder. Event projection
    -- and printing consume these constructors through 'LinearTrace.Core.Events'
    -- and 'LinearTrace.Print'.
    ActionKind(..)
  , Action
  , type Create
  , type Observe
  , type Use
  , type Copy
  , type Replace
  , type Compute
  , type Destroy
  , type Seal
  , type Unseal
  , type Decide
  , -- * Primitive operations
    -- | Linear lifecycle operations. These produce explain tokens and build
    -- the core graph; choreography wraps them with higher-level view coupling.
    create
  , createTagged
  , observe
  , use
  , copy
  , copyTagged
  , replace
  , compute
  , computeTagged
  , computeTaggedWith
  , destroy
  , seal
  , unseal
  , decide
  , -- * ExplainToken operations
    -- | Audit-token combinators used to assemble graph steps. Direct callers
    -- may use them; most view code consumes the event projection instead.
    OneUse(..)
  , ExplainToken
  , ExplainTokens(..)
  , Created(..)
  , Observed(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Computed(..)
  , Destroyed(..)
  , Sealed(..)
  , Unsealed(..)
  , Decided(..)
  , (<$>)
  , (<*>)
  , -- * Graph building
    -- | Final core graph builders. 'LinearTrace.Choreography' uses the same
    -- core state but attaches view output alongside it.
    explainWith
  , discard
  , buildGraph
  ) where

import           LinearTrace.Core.Internal
import           Prelude                   ()
