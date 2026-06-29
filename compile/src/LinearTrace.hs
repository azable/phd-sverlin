{-# LANGUAGE TypeFamilies #-}

-- | Public convenience facade for users that want the core trace DSL plus
-- printing and JSON compilation from one import. This module only re-exports
-- stable APIs from 'LinearTrace.Core', 'LinearTrace.Print', and
-- 'LinearTrace.Compile'; lower-level view/choreography internals stay behind
-- their own modules.
module LinearTrace
  ( -- * Core public API data
    -- | Core graph, payload, fact, and typeclass vocabulary re-exported from
    -- 'LinearTrace.Core'. Use these when building a trace directly.
    TraceGraph
  , TraceGraphWith
  , TraceBuilder
  , TraceBuilderWith
  , Traceable(..)
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
  , -- * Trusted linear payloads
    -- | Small trusted payload wrappers supplied by the core layer for example
    -- and test programs. User payload types can also provide their own
    -- 'Payload' instances.
    LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , -- * Action vocabulary
    -- | Linear action tags and operations from the core trace builder. These
    -- are the only constructors the direct core API needs to record lifecycle
    -- events.
    Action
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
    -- | Audit-token utilities from 'LinearTrace.Core'. These are mostly useful
    -- to direct core callers; choreography users normally stay at the
    -- 'LinearTrace.Choreography' layer.
    OneUse
  , ExplainToken
  , ExplainTokens(Done, (:~))
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
  , explainWith
  , discard
  , (<$>)
  , (<*>)
  , -- * Graph building, rendering and compilation
    -- | Output-facing helpers from 'LinearTrace.Print' and
    -- 'LinearTrace.Compile'. The visualization compiler depends on a solved
    -- view graph supplied by the choreography/view pipeline.
    PayloadView(..)
  , buildGraph
  , printGraph
  , printTrace
  , printSolutionByStep
  , compileSolved
  , printCompiledJSON
  , writeCompiledJSON
  ) where

import           LinearTrace.Compile
import           LinearTrace.Core
import           LinearTrace.Print
import           Prelude             hiding ((<$>), (<*>))
