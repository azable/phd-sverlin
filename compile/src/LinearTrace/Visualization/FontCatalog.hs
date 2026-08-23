-- | Pinned compiler-managed font faces.
--
-- Catalog entries separate the public family token from the exact face bytes.
-- Future project-uploaded fonts can implement the same resolution contract
-- after validation without changing text layout or target APIs.
module LinearTrace.Visualization.FontCatalog
  ( FontCatalog
  , FontFace(..)
  , FontResolution(..)
  , bundledFontCatalog
  , bundledFontCatalogSha256
  , presetFontFamilies
  , resolveFont
  , validateBundledFontCatalog
  ) where

import           Control.Exception                  (IOException, try)
import qualified Data.ByteString                    as BS
import qualified Data.ByteString.Char8              as BS8
import           Data.List                          (intercalate, minimumBy)
import           Data.Ord                           (comparing)
import qualified LinearTrace.Visualization.IR       as IR
import qualified LinearTrace.Visualization.Resource as Resource
import           Paths_compile                      (getDataFileName)
import           Prelude

newtype FontCatalog = FontCatalog
  { fontCatalogFaces :: [FontFaceSpec]
  }

data FontFaceSpec = FontFaceSpec
  { faceSpecFamily         :: String
  , faceSpecStyle          :: String
  , faceSpecMinimumWeight  :: Int
  , faceSpecMaximumWeight  :: Int
  , faceSpecSelectedWeight :: Maybe Int
  , faceSpecPath           :: FilePath
  , faceSpecSha256         :: IR.Sha256
  , faceSpecFeatures       :: [String]
  }

data FontFace = FontFace
  { fontFaceFamily   :: String
  , fontFaceStyle    :: String
  , fontFaceWeight   :: Int
  , fontFaceAxes     :: [IR.FontAxis]
  , fontFaceFeatures :: [String]
  , fontFaceResource :: Resource.ResourceBlob
  } deriving (Eq, Show)

data FontResolution = FontResolution
  { fontResolutionFace              :: FontFace
  , fontResolutionRequestedFamily   :: String
  , fontResolutionRequestedWeight   :: Int
  , fontResolutionRequestedStyle    :: String
  , fontResolutionWeightSubstituted :: Bool
  } deriving (Eq, Show)

presetFontFamilies :: [String]
presetFontFamilies =
  [ "Inter"
  , "Source Sans 3"
  , "Atkinson Hyperlegible Next"
  , "Space Grotesk"
  , "Source Serif 4"
  , "Literata"
  , "JetBrains Mono NL"
  , "IBM Plex Mono"
  ]

bundledFontCatalog :: FontCatalog
bundledFontCatalog = FontCatalog bundledFaces

bundledFontCatalogSha256 :: IR.Sha256
bundledFontCatalogSha256 =
  Resource.sha256Bytes (BS8.pack (unlines (map manifestLine bundledFaces)))
  where
    manifestLine spec =
      intercalate
        "\t"
        [ faceSpecFamily spec
        , faceSpecStyle spec
        , show (faceSpecMinimumWeight spec)
        , show (faceSpecMaximumWeight spec)
        , maybe "variable" show (faceSpecSelectedWeight spec)
        , faceSpecPath spec
        , shaText (faceSpecSha256 spec)
        , intercalate "," (faceSpecFeatures spec)
        ]

resolveFont ::
     FontCatalog -> String -> Int -> String -> IO (Either String FontResolution)
resolveFont catalog requestedFamily requestedWeight requestedStyle =
  case matchingFaces of
    [] ->
      pure
        (Left
           ("managed font family "
              ++ show requestedFamily
              ++ " does not provide style "
              ++ show normalizedStyle))
    _ -> loadResolution (minimumBy (comparing weightDistance) matchingFaces)
  where
    family = managedFamily requestedFamily
    normalizedStyle = normalizeStyle requestedStyle
    matchingFaces =
      filter
        (\spec ->
           faceSpecFamily spec == family
             && faceSpecStyle spec == normalizedStyle)
        (fontCatalogFaces catalog)
    weightDistance spec
      | requestedWeight < faceSpecMinimumWeight spec =
        faceSpecMinimumWeight spec - requestedWeight
      | requestedWeight > faceSpecMaximumWeight spec =
        requestedWeight - faceSpecMaximumWeight spec
      | otherwise = 0
    loadResolution spec = do
      loaded <- loadFace spec requestedWeight
      pure
        (fmap
           (\face ->
              FontResolution
                { fontResolutionFace = face
                , fontResolutionRequestedFamily = requestedFamily
                , fontResolutionRequestedWeight = requestedWeight
                , fontResolutionRequestedStyle = requestedStyle
                , fontResolutionWeightSubstituted =
                    fontFaceWeight face /= requestedWeight
                })
           loaded)

validateBundledFontCatalog :: IO (Either String ())
validateBundledFontCatalog = do
  results <- traverse (`loadFace` 400) bundledFaces
  pure (sequence_ results)

loadFace :: FontFaceSpec -> Int -> IO (Either String FontFace)
loadFace spec requestedWeight = do
  path <- getDataFileName (faceSpecPath spec)
  bytesResult <- try (BS.readFile path) :: IO (Either IOException BS.ByteString)
  pure $ do
    bytes <-
      case bytesResult of
        Left err ->
          Left ("could not read managed font " ++ show path ++ ": " ++ show err)
        Right value -> Right value
    let actualSha = Resource.sha256Bytes bytes
    if actualSha /= faceSpecSha256 spec
      then Left
             ("managed font hash mismatch for "
                ++ show path
                ++ ": expected "
                ++ shaText (faceSpecSha256 spec)
                ++ ", received "
                ++ shaText actualSha)
      else let selectedWeight =
                 case faceSpecSelectedWeight spec of
                   Just fixed -> fixed
                   Nothing ->
                     min
                       (faceSpecMaximumWeight spec)
                       (max (faceSpecMinimumWeight spec) requestedWeight)
               axes =
                 case faceSpecSelectedWeight spec of
                   Nothing -> [IR.FontAxis "wght" (fromIntegral selectedWeight)]
                   Just _  -> []
            in Right
                 FontFace
                   { fontFaceFamily = faceSpecFamily spec
                   , fontFaceStyle = faceSpecStyle spec
                   , fontFaceWeight = selectedWeight
                   , fontFaceAxes = axes
                   , fontFaceFeatures = faceSpecFeatures spec
                   , fontFaceResource =
                       Resource.resourceBlob IR.FontResource "font/ttf" bytes
                   }

managedFamily :: String -> String
managedFamily family =
  case family of
    "system-ui" -> "Source Sans 3"
    "monospace" -> "JetBrains Mono NL"
    "serif"     -> "Source Serif 4"
    _           -> family

normalizeStyle :: String -> String
normalizeStyle style =
  case style of
    "italic"  -> "italic"
    "oblique" -> "italic"
    _         -> "normal"

shaText :: IR.Sha256 -> String
shaText (IR.Sha256 value) = value

variableFace ::
     String -> String -> FilePath -> String -> [String] -> FontFaceSpec
variableFace family style path digest features =
  FontFaceSpec
    { faceSpecFamily = family
    , faceSpecStyle = style
    , faceSpecMinimumWeight = 100
    , faceSpecMaximumWeight = 900
    , faceSpecSelectedWeight = Nothing
    , faceSpecPath = path
    , faceSpecSha256 = IR.Sha256 digest
    , faceSpecFeatures = features
    }

staticFace :: String -> String -> Int -> FilePath -> String -> FontFaceSpec
staticFace family style weight path digest =
  FontFaceSpec
    { faceSpecFamily = family
    , faceSpecStyle = style
    , faceSpecMinimumWeight = weight
    , faceSpecMaximumWeight = weight
    , faceSpecSelectedWeight = Just weight
    , faceSpecPath = path
    , faceSpecSha256 = IR.Sha256 digest
    , faceSpecFeatures = []
    }

bundledFaces :: [FontFaceSpec]
bundledFaces =
  [ variableFace
      "Inter"
      "normal"
      "fonts/inter/Inter-Variable.ttf"
      "29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"
      []
  , variableFace
      "Inter"
      "italic"
      "fonts/inter/Inter-Italic-Variable.ttf"
      "acd98e64795781b2058f07b18475e0ecee2a0fe2b42a49e2f9e37d0d6bf66ce6"
      []
  , variableFace
      "Source Sans 3"
      "normal"
      "fonts/source-sans-3/SourceSans3-Variable.ttf"
      "042fe2cc0b933e328410d7acbd0aa6a1873dca5aef81875f4bc214b08825c7b9"
      []
  , variableFace
      "Source Sans 3"
      "italic"
      "fonts/source-sans-3/SourceSans3-Italic-Variable.ttf"
      "39e3ab05ccd7cb94907c31005bb5bec1d5432f0b096a2b782976e217a540eb6c"
      []
  , variableFace
      "Atkinson Hyperlegible Next"
      "normal"
      "fonts/atkinson-hyperlegible-next/AtkinsonHyperlegibleNext-Variable.ttf"
      "5a455d1cfa099b601ab70751bb9673e8fe1854dc4500c80e1a220d0d75e31745"
      []
  , variableFace
      "Atkinson Hyperlegible Next"
      "italic"
      "fonts/atkinson-hyperlegible-next/AtkinsonHyperlegibleNext-Italic-Variable.ttf"
      "ce9cffed32742ad2d9238c561a93220385e5934cdc02b8eb4097a50efa957dc6"
      []
  , variableFace
      "Space Grotesk"
      "normal"
      "fonts/space-grotesk/SpaceGrotesk-Variable.ttf"
      "acad6de1fc93436f5c0f1f4137751ef04f1aea3063e7036535970ffcfbd79f72"
      []
  , variableFace
      "Source Serif 4"
      "normal"
      "fonts/source-serif-4/SourceSerif4-Variable.ttf"
      "97b2d4da6e3cb494b5a1e66ae176914d852ccabef49e0c02c0df25f3e39aca0b"
      []
  , variableFace
      "Source Serif 4"
      "italic"
      "fonts/source-serif-4/SourceSerif4-Italic-Variable.ttf"
      "15fbc7e4679489a501998c3669272637a6646388ef7e4bd77eebb5bf967a1f42"
      []
  , variableFace
      "Literata"
      "normal"
      "fonts/literata/Literata-Variable.ttf"
      "b41138c9373112f32abb589cc22e8674b06ed4048b0c513be922bdd26f274440"
      []
  , variableFace
      "Literata"
      "italic"
      "fonts/literata/Literata-Italic-Variable.ttf"
      "d483dfaeba9cbf4ce71d32a52ee65df82f7e35b15fff8d1011cdb242d1fcd465"
      []
  , variableFace
      "JetBrains Mono NL"
      "normal"
      "fonts/jetbrains-mono-nl/JetBrainsMono-Variable.ttf"
      "48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"
      ["liga=0", "calt=0"]
  , variableFace
      "JetBrains Mono NL"
      "italic"
      "fonts/jetbrains-mono-nl/JetBrainsMono-Italic-Variable.ttf"
      "85ae2a5cd3f56baf1ce1c21a851322c58e3d8fbe8e8ad4a4d090a820dd7fe558"
      ["liga=0", "calt=0"]
  , staticFace
      "IBM Plex Mono"
      "normal"
      400
      "fonts/ibm-plex-mono/IBMPlexMono-Regular.ttf"
      "6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46"
  , staticFace
      "IBM Plex Mono"
      "normal"
      700
      "fonts/ibm-plex-mono/IBMPlexMono-Bold.ttf"
      "ac27abd6450a64dd94467580a02fe6235156d5b92f2926ebbc8e7489df64e0be"
  , staticFace
      "IBM Plex Mono"
      "italic"
      400
      "fonts/ibm-plex-mono/IBMPlexMono-Italic.ttf"
      "3362fc791b0652193328b862c1c5f23a789bc7288b1617fa63302f88689a2a34"
  , staticFace
      "IBM Plex Mono"
      "italic"
      700
      "fonts/ibm-plex-mono/IBMPlexMono-BoldItalic.ttf"
      "af4e05a761e98c1adf064c48a6352c9bec1a6ad70982cd2a544149323391f98e"
  ]
