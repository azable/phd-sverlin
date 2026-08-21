-- | Output-target boundary for solved visualization IR.
--
-- Future renderers belong here as pure transformations of the already-solved
-- package. They must not introduce a second source of randomness.
module LinearTrace.Visualization.Target
  ( OutputTarget(..)
  , outputTargetName
  , parseOutputTarget
  , compileTarget
  ) where

import           Data.Aeson.Encode.Pretty     (encodePretty)
import qualified Data.ByteString.Lazy         as BL
import qualified LinearTrace.Visualization.IR as IR
import           Prelude

data OutputTarget =
  IrJson
  deriving (Eq, Show)

outputTargetName :: OutputTarget -> String
outputTargetName target =
  case target of
    IrJson -> "ir-json"

parseOutputTarget :: String -> Either String OutputTarget
parseOutputTarget name =
  case name of
    "ir-json" -> Right IrJson
    _ -> Left ("unknown output target " ++ show name ++ "; expected ir-json")

compileTarget :: OutputTarget -> IR.VisualizationPackage -> BL.ByteString
compileTarget target visualization =
  case target of
    IrJson -> encodePretty visualization
