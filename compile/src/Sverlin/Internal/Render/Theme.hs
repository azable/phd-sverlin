-- | Private, seeded defaults for visual fields that an author leaves open.
--
-- Surface profiles are selected during materialization because they do not
-- change affine geometry.  Typography choices remain solver decisions because
-- the selected concrete face changes the text measurements.
module Sverlin.Internal.Render.Theme
  ( LeafProfile(..)
  , automaticFontFamilies
  , automaticFontFamilyChoice
  , automaticFontWeightChoice
  , automaticFontWeights
  , leafProfileFor
  , leafProfileToken
  ) where

import           Data.Char                    (digitToInt)
import qualified Data.Text                    as Text
import qualified Data.Text.Encoding           as Text
import           Prelude
import qualified Sverlin.Internal.Render.Font as Font
import qualified Sverlin.Output.IR            as IR
import qualified Sverlin.Output.Resource      as Resource

data LeafProfile
  = LeafTransparent
  | LeafOutline
  | LeafFlat
  | LeafSoftCard
  | LeafPill
  deriving (Eq, Show)

automaticFontFamilyChoice :: String
automaticFontFamilyChoice = "render.theme.typography.font-family"

automaticFontWeightChoice :: String
automaticFontWeightChoice = "render.theme.typography.font-weight"

-- Keep this list to unique concrete catalog families.  Generic aliases would
-- otherwise give the same bundled face more than one chance of being chosen.
automaticFontFamilies :: [String]
automaticFontFamilies = map Font.fontFamilyToken Font.allFontFamilies

automaticFontWeights :: [String]
automaticFontWeights = ["400", "500", "600"]

leafProfileFor :: Int -> String -> LeafProfile
leafProfileFor seed family =
  profiles !! seededIndex seed ("leaf-profile:" ++ family) (length profiles)
  where
    profiles = [LeafTransparent, LeafOutline, LeafFlat, LeafSoftCard, LeafPill]

leafProfileToken :: LeafProfile -> String
leafProfileToken profile =
  case profile of
    LeafTransparent -> "transparent"
    LeafOutline     -> "outline"
    LeafFlat        -> "flat"
    LeafSoftCard    -> "soft-card"
    LeafPill        -> "pill"

seededIndex :: Int -> String -> Int -> Int
seededIndex seed key count = foldl' accumulate 0 digest
  where
    IR.Sha256 digest =
      Resource.sha256Bytes
        (Text.encodeUtf8 (Text.pack (show seed ++ ":" ++ key)))
    accumulate current digit =
      (current * 16 + digitToInt digit) `mod` max 1 count
