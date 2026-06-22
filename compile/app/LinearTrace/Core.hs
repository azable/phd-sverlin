{-# LANGUAGE TypeFamilies #-}

module LinearTrace.Core
  ( -- * Core public API data
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
  , Traceable(..)
  , -- * Trusted linear payloads
    LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , -- * Action vocabulary
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
    create
  , createTagged
  , observe
  , use
  , copy
  , replace
  , compute
  , computeTagged
  , destroy
  , seal
  , unseal
  , decide
  , -- * ExplainToken operations
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
    explainWith
  , discard
  , buildGraph
  ) where

import           LinearTrace.Core.Internal
import           Prelude                   ()
