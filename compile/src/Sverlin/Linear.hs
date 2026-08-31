{-# LANGUAGE NoImplicitPrelude #-}

-- | Curated linear operations supplied qualified to authored source.
--
-- Keep this export list explicit.  In particular, multiplicity-changing
-- operations such as @move@, @dup2@, and @Ur@ must never cross this boundary.
module Sverlin.Linear
  ( (+)
  , (-)
  , (*)
  , (/)
  , quot
  , rem
  , (==)
  , (/=)
  , (<)
  , (<=)
  , (>)
  , (>=)
  , compare
  , not
  , (&&)
  , (||)
  , (++)
  ) where

import           Prelude.Linear
