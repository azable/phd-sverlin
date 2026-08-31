-- | Narrow host boundary between generated source and the compiler executable.
-- Authored source imports only 'Sverlin'; the generated footer packages its
-- three declarations with 'sverlinProgram'.
module Sverlin.Compiler
  ( SverlinProgram
  , sverlinProgram
  ) where

import           Sverlin.Internal.Compiler (SverlinProgram, sverlinProgram)
