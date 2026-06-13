{-# LANGUAGE TypeFamilies #-}

module LinearTrace
  ( TraceGraph
  , TraceBuilder
  , Node
  , Payload
  , -- * Trusted linear payloads
    LUnit(..)
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
  , -- * Primitive operations
    create
  , observe
  , use
  , copy
  , replace
  , compute
  , destroy
  , -- * Auditing operations
    OneUse
  , Evidence
  , EvidenceList(Done, (:~))
  , Created(..)
  , Observed(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Computed(..)
  , Destroyed(..)
  , explain
  , (<$>)
  , (<*>)
  , -- * Graph building and rendering
    TracePayload(..)
  , PayloadView(..)
  , PrintEvent(..)
  , buildGraph
  , printGraph
  , printTrace
  ) where

import           LinearTrace.Core
import           LinearTrace.Print
import           Prelude           hiding ((<$>), (<*>))
