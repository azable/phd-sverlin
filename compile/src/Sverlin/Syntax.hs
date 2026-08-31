{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE KindSignatures         #-}
{-# LANGUAGE LinearTypes            #-}
{-# LANGUAGE NoImplicitPrelude      #-}
{-# LANGUAGE UndecidableInstances   #-}

-- | Multiplicity-aware hooks used by the generated source's
-- @RebindableSyntax@ profile.
--
-- The authored facade does not export the class.  Its instances are owned by
-- the compiler so authored code cannot change a builder's binding policy.
module Sverlin.Syntax
  ( Rebind(..)
  , (>>=)
  , (>>)
  , pure
  , return
  , fail
  ) where

import           Data.Kind (Type)
import           GHC.Exts  (Multiplicity (Many, One))
import qualified Prelude   as P

class Rebind (multiplicity :: Multiplicity) (builder :: Type -> Type)
  | builder -> multiplicity
  where
  rebind ::
       builder value
       %multiplicity -> (value %multiplicity -> builder result)
       %multiplicity -> builder result
  repure :: value %multiplicity -> builder value
  refail :: P.String -> builder value

-- Kept private: unrestricted builders may discard any statement result,
-- while a linear builder may sequence only an action returning unit.
class Rebind multiplicity builder =>
      RebindThen multiplicity builder value
  where
  rebindThen ::
       builder value
       %multiplicity -> builder result
       %multiplicity -> builder result

instance Rebind 'Many builder => RebindThen 'Many builder value where
  rebindThen first second = rebind first (P.const second)

instance Rebind 'One builder => RebindThen 'One builder () where
  rebindThen first second = rebind first (\() -> second)

infixl 1 >>=
(>>=) ::
     Rebind multiplicity builder
  => builder value
     %multiplicity -> (value %multiplicity -> builder result)
     %multiplicity -> builder result
(>>=) = rebind

infixl 1 >>
(>>) ::
     RebindThen multiplicity builder value
  => builder value
     %multiplicity -> builder result
     %multiplicity -> builder result
(>>) = rebindThen

pure :: Rebind multiplicity builder => value %multiplicity -> builder value
pure = repure

return :: Rebind multiplicity builder => value %multiplicity -> builder value
return = repure

fail :: Rebind multiplicity builder => P.String -> builder value
fail = refail
