{-# LANGUAGE TypeFamilies #-}

module LinearTrace
  ( -- * Core public API data
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
    LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , -- * Action vocabulary
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
