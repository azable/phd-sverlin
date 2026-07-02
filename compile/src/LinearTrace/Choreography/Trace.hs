{-# LANGUAGE LinearTypes         #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Choreography trace helpers that add query-tag ergonomics over the core
-- trace builder.
module LinearTrace.Choreography.Trace
  ( Choreography
  , SlotHandle
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
  ) where

import           LinearTrace.Core (Block, Payload, Pending, Query, TraceBuilder,
                                   Traceable, queryFacts)
import qualified LinearTrace.Core as C
import qualified Prelude          as P

type Choreography a = TraceBuilder a

type SlotHandle = C.Slot

create ::
     forall tag. Traceable tag
  => Payload tag
     %1 -> Choreography (C.Create tag)
create = C.create

use ::
     forall tag. Traceable tag
  => Block tag
     %1 -> Choreography (C.Use tag)
use = C.use

copy ::
     forall tag. Traceable tag
  => Block tag
     %1 -> Choreography (C.Copy tag)
copy = C.copy

apply1 ::
     forall op arg.
     ( C.Applicable1 op arg
     , Traceable op
     , Traceable arg
     , Traceable (C.Apply1Result op arg)
     )
  => Block op
     %1 -> Block arg
     %1 -> Choreography (C.Apply1 op arg)
apply1 = C.apply1

apply2 ::
     forall op lhs rhs.
     ( C.Applicable2 op lhs rhs
     , Traceable op
     , Traceable lhs
     , Traceable rhs
     , Traceable (C.Apply2Result op lhs rhs)
     )
  => Block op
     %1 -> Block lhs
     %1 -> Block rhs
     %1 -> Choreography (C.Apply2 op lhs rhs)
apply2 = C.apply2

replace ::
     forall tag. Traceable tag
  => Block tag
     %1 -> Pending tag
     %1 -> Choreography (C.Replace tag)
replace = C.replace

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

commit ::
     forall tag. Traceable tag
  => Pending tag
     %1 -> Choreography (Block tag)
commit = C.commit

destroy ::
     forall tag. Traceable tag
  => Block tag
     %1 -> Choreography (C.Destroy tag)
destroy = C.destroy

checkpoint :: P.String -> Choreography ()
checkpoint = C.checkpoint
