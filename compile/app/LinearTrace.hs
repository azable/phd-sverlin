{-# LANGUAGE TypeFamilies #-}

module LinearTrace
  ( G
  , GBuilder
  , N
  , Payload
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
  , Owed
  , OwedList(PaidDebt, (:~))
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
  , PrintDesc(..)
  , buildGraph
  , printGraph
  , printTrace
  ) where

import           LinearTrace.Core
import           LinearTrace.Print
import           Prelude           hiding ((<$>), (<*>))
