-- | Canonical metadata for the bundled font families available to Render.
module Sverlin.Internal.Render.Font
  ( FontKind(..)
  , FontFamily(..)
  , allFontFamilies
  , fontFamiliesForKind
  , fontFamilyToken
  , fontFamilyFromToken
  ) where

import           Prelude

data FontKind
  = Monospace
  | Proportional
  deriving (Eq, Show)

data FontFamily
  = FontInter
  | FontSourceSans3
  | FontAtkinsonHyperlegibleNext
  | FontSpaceGrotesk
  | FontSourceSerif4
  | FontLiterata
  | FontJetBrainsMonoNL
  | FontIBMPlexMono
  deriving (Eq, Show)

-- | All concrete bundled families in their stable choice order.
allFontFamilies :: [FontFamily]
allFontFamilies =
  [ FontInter
  , FontSourceSans3
  , FontAtkinsonHyperlegibleNext
  , FontSpaceGrotesk
  , FontSourceSerif4
  , FontLiterata
  , FontJetBrainsMonoNL
  , FontIBMPlexMono
  ]

fontFamiliesForKind :: FontKind -> [FontFamily]
fontFamiliesForKind kind = filter ((== kind) . fontFamilyKind) allFontFamilies

fontFamilyKind :: FontFamily -> FontKind
fontFamilyKind family =
  case family of
    FontInter                    -> Proportional
    FontSourceSans3              -> Proportional
    FontAtkinsonHyperlegibleNext -> Proportional
    FontSpaceGrotesk             -> Proportional
    FontSourceSerif4             -> Proportional
    FontLiterata                 -> Proportional
    FontJetBrainsMonoNL          -> Monospace
    FontIBMPlexMono              -> Monospace

fontFamilyToken :: FontFamily -> String
fontFamilyToken family =
  case family of
    FontInter                    -> "Inter"
    FontSourceSans3              -> "Source Sans 3"
    FontAtkinsonHyperlegibleNext -> "Atkinson Hyperlegible Next"
    FontSpaceGrotesk             -> "Space Grotesk"
    FontSourceSerif4             -> "Source Serif 4"
    FontLiterata                 -> "Literata"
    FontJetBrainsMonoNL          -> "JetBrains Mono NL"
    FontIBMPlexMono              -> "IBM Plex Mono"

fontFamilyFromToken :: String -> Maybe FontFamily
fontFamilyFromToken token = lookup token tokenFamilies
  where
    tokenFamilies =
      [(fontFamilyToken family, family) | family <- allFontFamilies]
