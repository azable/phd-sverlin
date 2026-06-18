{-# LANGUAGE TypeFamilies #-}

module LinearTrace
  ( -- * Core public API data
    TraceGraph
  , TraceBuilder
  , Traceable(..)
  , Block
  , Slot
  , Payload
  , type Actions
  , Member
  , EventChoice(..)
  , RecordedEvent(..)
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
  , type Inspect
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
  , observe
  , inspect
  , use
  , copy
  , replace
  , compute
  , destroy
  , seal
  , unseal
  , decide
  , -- * Auditing operations
    OneUse
  , Evidence
  , EvidenceList(Done, (:~))
  , Created(..)
  , Observed(..)
  , Inspected(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Computed(..)
  , Destroyed(..)
  , Sealed(..)
  , Unsealed(..)
  , Decided(..)
  , explain
  , (<$>)
  , (<*>)
  , -- * Graph building, rendering and compilation
    Audit(..)
  , AuditStep(..)
  , PayloadView(..)
  , PrintEvent(..)
  , buildGraph
  , printGraph
  , printTrace
  , printVisualization
  , printVisualizationCSPSolution
  , printSolvedVisualization
  , compileSolvedVisualization
  , printCompiledVisualizationJSON
  , writeCompiledVisualizationJSON
  ) where

import           LinearTrace.Compile
import           LinearTrace.Core
import           LinearTrace.Print
import           Prelude             hiding ((<$>), (<*>))
