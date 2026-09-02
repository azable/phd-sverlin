-- | Pinned compiler-managed font faces.
--
-- Catalog entries separate the public family token from the exact face bytes.
-- Future project-uploaded fonts can implement the same resolution contract
-- after validation without changing text layout or target APIs.
module Sverlin.Internal.Render.Typography.FontCatalog
  ( FontCatalog
  , FontFace(..)
  , FontResolution(..)
  , bundledFontCatalog
  , bundledFontCatalogSha256
  , resolveFont
  , validateBundledFontCatalog
  ) where

import           Control.Exception            (IOException, try)
import qualified Data.ByteString              as BS
import qualified Data.ByteString.Char8        as BS8
import           Data.List                    (intercalate, nub, sort)
import           Paths_compile                (getDataFileName)
import           Prelude
import qualified Sverlin.Internal.Render.Font as Font
import qualified Sverlin.Output.IR            as IR
import qualified Sverlin.Output.Resource      as Resource

newtype FontCatalog = FontCatalog
  { fontCatalogFaces :: [FontFaceSpec]
  }

data FontFaceSpec = FontFaceSpec
  { faceSpecFamily         :: Font.FontFamily
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

newtype FontResolution = FontResolution
  { fontResolutionFace :: FontFace
  } deriving (Eq, Show)

bundledFontCatalog :: FontCatalog
bundledFontCatalog = FontCatalog bundledFaces

bundledFontCatalogSha256 :: IR.Sha256
bundledFontCatalogSha256 =
  Resource.sha256Bytes (BS8.pack (unlines (map manifestLine bundledFaces)))
  where
    manifestLine spec =
      intercalate
        "\t"
        [ Font.fontFamilyToken (faceSpecFamily spec)
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
  case styleFaces of
    [] ->
      pure
        (Left
           ("managed font family "
              ++ show requestedFamily
              ++ " does not provide style "
              ++ show normalizedStyle))
    _ ->
      case matchingFaces of
        [] ->
          pure
            (Left
               ("managed font family "
                  ++ show requestedFamily
                  ++ " with style "
                  ++ show normalizedStyle
                  ++ " does not provide weight "
                  ++ show requestedWeight))
        spec:_ -> loadResolution spec
  where
    family = managedFamily requestedFamily
    normalizedStyle = normalizeStyle requestedStyle
    styleFaces =
      filter
        (\spec ->
           Just (faceSpecFamily spec) == family
             && faceSpecStyle spec == normalizedStyle)
        (fontCatalogFaces catalog)
    matchingFaces =
      filter
        (\spec ->
           requestedWeight >= faceSpecMinimumWeight spec
             && requestedWeight <= faceSpecMaximumWeight spec)
        styleFaces
    loadResolution spec = do
      loaded <- loadFace spec requestedWeight
      pure (fmap FontResolution loaded)

validateBundledFontCatalog :: IO (Either String ())
validateBundledFontCatalog =
  case metadataValidation of
    Left err -> pure (Left err)
    Right () -> do
      results <- traverse (`loadFace` 400) bundledFaces
      pure (sequence_ results)
  where
    catalogFamilies = nub (map faceSpecFamily bundledFaces)
    catalogTokens = map Font.fontFamilyToken catalogFamilies
    tokens = map Font.fontFamilyToken Font.allFontFamilies
    metadataValidation
      | sort catalogTokens /= sort tokens =
        Left
          "the bundled font catalog does not cover exactly the Render families"
      | length tokens /= length (nub tokens) =
        Left "the bundled font catalog contains duplicate public family tokens"
      | otherwise = Right ()

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
                   { fontFaceFamily = Font.fontFamilyToken (faceSpecFamily spec)
                   , fontFaceStyle = faceSpecStyle spec
                   , fontFaceWeight = selectedWeight
                   , fontFaceAxes = axes
                   , fontFaceFeatures = faceSpecFeatures spec
                   , fontFaceResource =
                       Resource.resourceBlob IR.FontResource "font/ttf" bytes
                   }

managedFamily :: String -> Maybe Font.FontFamily
managedFamily family =
  case family of
    "system-ui" -> Just Font.FontSourceSans3
    "monospace" -> Just Font.FontJetBrainsMonoNL
    "serif"     -> Just Font.FontSourceSerif4
    _           -> Font.fontFamilyFromToken family

normalizeStyle :: String -> String
normalizeStyle style =
  case style of
    "italic" -> "italic"
    "normal" -> "normal"
    _        -> style

shaText :: IR.Sha256 -> String
shaText (IR.Sha256 value) = value

variableFace ::
     Font.FontFamily -> String -> FilePath -> String -> [String] -> FontFaceSpec
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

staticFace ::
     Font.FontFamily -> String -> Int -> FilePath -> String -> FontFaceSpec
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
      Font.FontInter
      "normal"
      "fonts/inter/Inter-Variable.ttf"
      "29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"
      []
  , variableFace
      Font.FontInter
      "italic"
      "fonts/inter/Inter-Italic-Variable.ttf"
      "acd98e64795781b2058f07b18475e0ecee2a0fe2b42a49e2f9e37d0d6bf66ce6"
      []
  , variableFace
      Font.FontSourceSans3
      "normal"
      "fonts/source-sans-3/SourceSans3-Variable.ttf"
      "042fe2cc0b933e328410d7acbd0aa6a1873dca5aef81875f4bc214b08825c7b9"
      []
  , variableFace
      Font.FontSourceSans3
      "italic"
      "fonts/source-sans-3/SourceSans3-Italic-Variable.ttf"
      "39e3ab05ccd7cb94907c31005bb5bec1d5432f0b096a2b782976e217a540eb6c"
      []
  , variableFace
      Font.FontAtkinsonHyperlegibleNext
      "normal"
      "fonts/atkinson-hyperlegible-next/AtkinsonHyperlegibleNext-Variable.ttf"
      "5a455d1cfa099b601ab70751bb9673e8fe1854dc4500c80e1a220d0d75e31745"
      []
  , variableFace
      Font.FontAtkinsonHyperlegibleNext
      "italic"
      "fonts/atkinson-hyperlegible-next/AtkinsonHyperlegibleNext-Italic-Variable.ttf"
      "ce9cffed32742ad2d9238c561a93220385e5934cdc02b8eb4097a50efa957dc6"
      []
  , variableFace
      Font.FontSpaceGrotesk
      "normal"
      "fonts/space-grotesk/SpaceGrotesk-Variable.ttf"
      "acad6de1fc93436f5c0f1f4137751ef04f1aea3063e7036535970ffcfbd79f72"
      []
  , variableFace
      Font.FontSourceSerif4
      "normal"
      "fonts/source-serif-4/SourceSerif4-Variable.ttf"
      "97b2d4da6e3cb494b5a1e66ae176914d852ccabef49e0c02c0df25f3e39aca0b"
      []
  , variableFace
      Font.FontSourceSerif4
      "italic"
      "fonts/source-serif-4/SourceSerif4-Italic-Variable.ttf"
      "15fbc7e4679489a501998c3669272637a6646388ef7e4bd77eebb5bf967a1f42"
      []
  , variableFace
      Font.FontLiterata
      "normal"
      "fonts/literata/Literata-Variable.ttf"
      "b41138c9373112f32abb589cc22e8674b06ed4048b0c513be922bdd26f274440"
      []
  , variableFace
      Font.FontLiterata
      "italic"
      "fonts/literata/Literata-Italic-Variable.ttf"
      "d483dfaeba9cbf4ce71d32a52ee65df82f7e35b15fff8d1011cdb242d1fcd465"
      []
  , variableFace
      Font.FontJetBrainsMonoNL
      "normal"
      "fonts/jetbrains-mono-nl/JetBrainsMono-Variable.ttf"
      "48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"
      ["liga=0", "calt=0"]
  , variableFace
      Font.FontJetBrainsMonoNL
      "italic"
      "fonts/jetbrains-mono-nl/JetBrainsMono-Italic-Variable.ttf"
      "85ae2a5cd3f56baf1ce1c21a851322c58e3d8fbe8e8ad4a4d090a820dd7fe558"
      ["liga=0", "calt=0"]
  , staticFace
      Font.FontIBMPlexMono
      "normal"
      400
      "fonts/ibm-plex-mono/IBMPlexMono-Regular.ttf"
      "6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46"
  , staticFace
      Font.FontIBMPlexMono
      "normal"
      700
      "fonts/ibm-plex-mono/IBMPlexMono-Bold.ttf"
      "ac27abd6450a64dd94467580a02fe6235156d5b92f2926ebbc8e7489df64e0be"
  , staticFace
      Font.FontIBMPlexMono
      "italic"
      400
      "fonts/ibm-plex-mono/IBMPlexMono-Italic.ttf"
      "3362fc791b0652193328b862c1c5f23a789bc7288b1617fa63302f88689a2a34"
  , staticFace
      Font.FontIBMPlexMono
      "italic"
      700
      "fonts/ibm-plex-mono/IBMPlexMono-BoldItalic.ttf"
      "af4e05a761e98c1adf064c48a6352c9bec1a6ad70982cd2a544149323391f98e"
  ]
