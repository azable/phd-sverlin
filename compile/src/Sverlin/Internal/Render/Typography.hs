-- | Whole-line typography preparation for the new Render compiler.
--
-- A prepared line is shaped once at the font's units-per-em scale.  Its
-- metrics are constants in the affine solve; the sampled font size remains a
-- normal numeric variable.  Fragment ranges are metadata over that same shape,
-- never separately shaped strings.
module Sverlin.Internal.Render.Typography
  ( FragmentRange(..)
  , PreparedLine
  , prepareLine
  , preparedLineWidthEm
  , preparedLineHeightEm
  , preparedLineResources
  , materializeLine
  , activeFragmentClusters
  , typographyCompilationProvenance
  ) where

import qualified Data.Binary.Put                       as Binary
import qualified Data.ByteString                       as BS
import qualified Data.ByteString.Lazy                  as BL
import           Data.Int                              (Int32)
import           Data.List                             (nub, sort)
import qualified Data.Map.Strict                       as Map
import           Data.Set                              (Set)
import qualified Data.Set                              as Set
import qualified Data.Text                             as Text
import qualified Data.Text.Encoding                    as Text
import qualified LinearTrace.Visualization.FontCatalog as Font
import qualified LinearTrace.Visualization.HarfBuzz    as HB
import qualified LinearTrace.Visualization.IR          as IR
import qualified LinearTrace.Visualization.Resource    as Resource
import           Prelude

data FragmentRange = FragmentRange
  { fragmentSourceRange :: IR.TextSourceRange
  , fragmentStepNames   :: [String]
  } deriving (Eq, Show)

data LineMetrics = LineMetrics
  { metricAdvance :: Double
  , metricMinX    :: Double
  , metricMaxX    :: Double
  , metricMinY    :: Double
  , metricMaxY    :: Double
  }

data PreparedLine = PreparedLine
  { preparedSource       :: String
  , preparedFragments    :: [FragmentRange]
  , preparedResolution   :: Font.FontResolution
  , preparedShape        :: HB.ShapedText
  , preparedMetrics      :: LineMetrics
  , preparedLineHeightEm :: Double
  , preparedTextRun      :: Resource.ResourceBlob
  }

prepareLine ::
     String
  -> Int
  -> String
  -> String
  -> [FragmentRange]
  -> IO (Either String PreparedLine)
prepareLine family weight style source fragments = do
  resolved <- Font.resolveFont Font.bundledFontCatalog family weight style
  case resolved of
    Left err -> pure (Left err)
    Right resolution -> do
      let face = Font.fontResolutionFace resolution
          bytes = Resource.resourceBlobBytes (Font.fontFaceResource face)
          options =
            HB.defaultShapeOptions
              { HB.shapeOptionWeight = Font.fontFaceWeight face
              , HB.shapeOptionDisableLigatures =
                  not (null (Font.fontFaceFeatures face))
              }
      shapedResult <- HB.shapeText bytes options source
      pure $ do
        shaped <- shapedResult
        let missing =
              [ HB.shapedGlyphCluster glyph
              | glyph <- HB.shapedTextGlyphs shaped
              , HB.shapedGlyphId glyph == 0
              ]
        if null missing
          then let metrics = lineMetrics shaped
                   line =
                     PreparedLine
                       { preparedSource = source
                       , preparedFragments = fragments
                       , preparedResolution = resolution
                       , preparedShape = shaped
                       , preparedMetrics = metrics
                       , preparedLineHeightEm = lineHeightEm shaped metrics
                       , preparedTextRun = textRunResource source shaped
                       }
                in Right line
          else Left
                 ("managed font is missing glyphs at UTF-8 byte clusters "
                    ++ show missing)

preparedLineWidthEm :: PreparedLine -> Double
preparedLineWidthEm line =
  (metricMaxX metrics - metricMinX metrics) / unitsPerEm line
  where
    metrics = preparedMetrics line

preparedLineResources :: PreparedLine -> [Resource.ResourceBlob]
preparedLineResources line =
  [ Font.fontFaceResource (Font.fontResolutionFace (preparedResolution line))
  , preparedTextRun line
  ]

typographyCompilationProvenance :: Resource.CompilationProvenance
typographyCompilationProvenance =
  Resource.CompilationProvenance
    { Resource.compilationProvenancePackageVersion = 1
    , Resource.compilationProvenanceTextRunFormatVersion = 2
    , Resource.compilationProvenanceShapingEngine = "harfbuzz"
    , Resource.compilationProvenanceShapingEngineVersion = HB.harfBuzzVersion
    , Resource.compilationProvenanceFontCatalogSha256 =
        Just Font.bundledFontCatalogSha256
    }

materializeLine ::
     Double
  -> Double
  -> String
  -> IR.LayoutRect
  -> PreparedLine
  -> (IR.VisualContent, IR.TextLayout)
materializeLine fontSize preferredSize alignment contentBox prepared =
  (IR.PlainTextContent layout, layout)
  where
    shaped = preparedShape prepared
    metrics = preparedMetrics prepared
    scale = fontSize / unitsPerEm prepared
    lineWidth = (metricMaxX metrics - metricMinX metrics) * scale
    targetLeft =
      case alignment of
        "left" -> IR.layoutRectX contentBox
        "right" ->
          IR.layoutRectX contentBox + IR.layoutRectWidth contentBox - lineWidth
        _ ->
          IR.layoutRectX contentBox
            + (IR.layoutRectWidth contentBox - lineWidth) / 2
    originX = targetLeft - metricMinX metrics * scale
    blockHeight = preparedLineHeightEm prepared * fontSize
    nominalHeight =
      fromIntegral
        (HB.shapedTextAscender shaped - HB.shapedTextDescender shaped)
    leading =
      max
        0
        (preparedLineHeightEm prepared * unitsPerEm prepared - nominalHeight)
    nominalTop = fromIntegral (HB.shapedTextAscender shaped) + leading / 2
    topUnits = max nominalTop (metricMaxY metrics)
    baseline =
      IR.layoutRectY contentBox
        + (IR.layoutRectHeight contentBox - blockHeight) / 2
        + topUnits * scale
    inkTop = baseline - metricMaxY metrics * scale
    inkHeight = (metricMaxY metrics - metricMinY metrics) * scale
    sourceRange =
      IR.TextSourceRange
        0
        (BS.length (Text.encodeUtf8 (Text.pack (preparedSource prepared))))
    textLine =
      IR.TextLine
        { IR.textLineSourceRange = sourceRange
        , IR.textLineDisplayText = preparedSource prepared
        , IR.textLineOriginX = roundLayout originX
        , IR.textLineBaselineY = roundLayout baseline
        , IR.textLineAdvance = roundLayout (metricAdvance metrics * scale)
        , IR.textLineInkBounds =
            IR.LayoutRect
              { IR.layoutRectX = roundLayout targetLeft
              , IR.layoutRectY = roundLayout inkTop
              , IR.layoutRectWidth = roundLayout lineWidth
              , IR.layoutRectHeight = roundLayout inkHeight
              }
        }
    face = Font.fontResolutionFace (preparedResolution prepared)
    fontResource = Font.fontFaceResource face
    fontDescriptor = Resource.resourceBlobDescriptor fontResource
    runDescriptor = Resource.resourceBlobDescriptor (preparedTextRun prepared)
    font =
      IR.FontInstance
        { IR.fontInstanceFamily = Font.fontFaceFamily face
        , IR.fontInstanceResourceId = IR.resourceDescriptorId fontDescriptor
        , IR.fontInstanceWeight = Font.fontFaceWeight face
        , IR.fontInstanceStyle = Font.fontFaceStyle face
        , IR.fontInstanceAxes = Font.fontFaceAxes face
        , IR.fontInstanceFeatures = Font.fontFaceFeatures face
        }
    layout =
      IR.TextLayout
        { IR.textLayoutSource = preparedSource prepared
        , IR.textLayoutWhitespace = IR.TextPreserveWhitespace
        , IR.textLayoutWrapMode = IR.TextNoAutomaticWrap
        , IR.textLayoutFont = font
        , IR.textLayoutFontSize = roundLayout fontSize
        , IR.textLayoutPreferredSize = roundLayout preferredSize
        , IR.textLayoutLineHeight = roundLayout blockHeight
        , IR.textLayoutDirection =
            if HB.shapedTextRightToLeft shaped
              then IR.TextRightToLeft
              else IR.TextLeftToRight
        , IR.textLayoutScript = HB.shapedTextScript shaped
        , IR.textLayoutLanguage = "und"
        , IR.textLayoutAlignment = normalizedAlignment
        , IR.textLayoutContentBox = contentBox
        , IR.textLayoutLines = [textLine]
        , IR.textLayoutTextRunResource = IR.resourceDescriptorId runDescriptor
        }
    normalizedAlignment =
      case alignment of
        "left"  -> "left"
        "right" -> "right"
        _       -> "center"

activeFragmentClusters ::
     Set String -> Double -> IR.TextLayout -> PreparedLine -> [IR.GlyphCluster]
activeFragmentClusters activeSteps fontSize layout prepared =
  [ IR.GlyphCluster
    { IR.glyphClusterLineIndex = 0
    , IR.glyphClusterSourceRange = sourceRange
    , IR.glyphClusterInkBounds = bounds
    }
  | (clusterStart, sourceRange, bounds) <-
      clusterBounds prepared fontSize layout
  , any (fragmentMatches clusterStart sourceRange) (preparedFragments prepared)
  ]
  where
    fragmentMatches _ clusterRange fragment =
      rangesOverlap clusterRange (fragmentSourceRange fragment)
        && any (`Set.member` activeSteps) (fragmentStepNames fragment)

rangesOverlap :: IR.TextSourceRange -> IR.TextSourceRange -> Bool
rangesOverlap first second =
  IR.textSourceRangeStart first < IR.textSourceRangeEnd second
    && IR.textSourceRangeStart second < IR.textSourceRangeEnd first

clusterBounds ::
     PreparedLine
  -> Double
  -> IR.TextLayout
  -> [(Int, IR.TextSourceRange, IR.LayoutRect)]
clusterBounds prepared fontSize layout =
  [ (start, rangeFor start, roundBounds bounds)
  | (start, bounds) <- Map.toAscList accumulated
  ]
  where
    shaped = preparedShape prepared
    glyphs = HB.shapedTextGlyphs shaped
    sourceLength =
      BS.length (Text.encodeUtf8 (Text.pack (preparedSource prepared)))
    starts =
      sort (nub [fromIntegral (HB.shapedGlyphCluster glyph) | glyph <- glyphs])
    rangeFor start =
      IR.TextSourceRange
        start
        (case dropWhile (<= start) starts of
           next:_ -> min sourceLength next
           []     -> sourceLength)
    line =
      case IR.textLayoutLines layout of
        first:_ -> first
        [] ->
          IR.TextLine
            (IR.TextSourceRange 0 sourceLength)
            (preparedSource prepared)
            0
            0
            0
            (IR.LayoutRect 0 0 0 0)
    scale = fontSize / unitsPerEm prepared
    (_, _, accumulated) = foldl addGlyph (0, 0, Map.empty) glyphs
    addGlyph (penX, penY, boundsByCluster) glyph =
      let x0 =
            IR.textLineOriginX line
              + (penX
                   + fromIntegral (HB.shapedGlyphXOffset glyph)
                   + fromIntegral (HB.shapedGlyphXBearing glyph))
                  * scale
          yBearing =
            penY
              + fromIntegral (HB.shapedGlyphYOffset glyph)
              + fromIntegral (HB.shapedGlyphYBearing glyph)
          x1 = x0 + fromIntegral (HB.shapedGlyphWidth glyph) * scale
          yOther = yBearing + fromIntegral (HB.shapedGlyphHeight glyph)
          y0 = IR.textLineBaselineY line - max yBearing yOther * scale
          y1 = IR.textLineBaselineY line - min yBearing yOther * scale
          cluster = fromIntegral (HB.shapedGlyphCluster glyph)
          nextBounds =
            Map.insertWith mergeBounds cluster (x0, x1, y0, y1) boundsByCluster
       in ( penX + fromIntegral (HB.shapedGlyphXAdvance glyph)
          , penY + fromIntegral (HB.shapedGlyphYAdvance glyph)
          , nextBounds)
    mergeBounds (x0, x1, y0, y1) (a0, a1, b0, b1) =
      (min x0 a0, max x1 a1, min y0 b0, max y1 b1)
    roundBounds (x0, x1, y0, y1) =
      IR.LayoutRect
        { IR.layoutRectX = roundLayout (min x0 x1)
        , IR.layoutRectY = roundLayout (min y0 y1)
        , IR.layoutRectWidth = roundLayout (abs (x1 - x0))
        , IR.layoutRectHeight = roundLayout (abs (y1 - y0))
        }

lineMetrics :: HB.ShapedText -> LineMetrics
lineMetrics shaped =
  let (penX, penY, bounds) =
        foldl addGlyph (0, 0, Nothing) (HB.shapedTextGlyphs shaped)
      (minX, maxX, minY, maxY) =
        case bounds of
          Nothing -> (min 0 penX, max 0 penX, min 0 penY, max 0 penY)
          Just (x0, x1, y0, y1) ->
            (min x0 (min 0 penX), max x1 (max 0 penX), min y0 0, max y1 0)
   in LineMetrics (abs penX) minX maxX minY maxY
  where
    addGlyph (penX, penY, bounds) glyph =
      let x0 =
            penX
              + fromIntegral (HB.shapedGlyphXOffset glyph)
              + fromIntegral (HB.shapedGlyphXBearing glyph)
          y0 =
            penY
              + fromIntegral (HB.shapedGlyphYOffset glyph)
              + fromIntegral (HB.shapedGlyphYBearing glyph)
          x1 = x0 + fromIntegral (HB.shapedGlyphWidth glyph)
          y1 = y0 + fromIntegral (HB.shapedGlyphHeight glyph)
          current = (min x0 x1, max x0 x1, min y0 y1, max y0 y1)
       in ( penX + fromIntegral (HB.shapedGlyphXAdvance glyph)
          , penY + fromIntegral (HB.shapedGlyphYAdvance glyph)
          , Just (maybe current (merge current) bounds))
    merge (x0, x1, y0, y1) (a0, a1, b0, b1) =
      (min x0 a0, max x1 a1, min y0 b0, max y1 b1)

lineHeightEm :: HB.ShapedText -> LineMetrics -> Double
lineHeightEm shaped metrics = max nominal ink
  where
    upem = fromIntegral (max 1 (HB.shapedTextUnitsPerEm shaped))
    nominal =
      max
        1.2
        (fromIntegral
           (HB.shapedTextAscender shaped
              - HB.shapedTextDescender shaped
              + HB.shapedTextLineGap shaped)
           / upem)
    ink = (metricMaxY metrics - metricMinY metrics) / upem

unitsPerEm :: PreparedLine -> Double
unitsPerEm = fromIntegral . max 1 . HB.shapedTextUnitsPerEm . preparedShape

textRunResource :: String -> HB.ShapedText -> Resource.ResourceBlob
textRunResource source shaped =
  Resource.resourceBlob
    IR.TextRunResource
    "application/vnd.sverlin.text-run-v2"
    (BL.toStrict (Binary.runPut putRun))
  where
    putRun = do
      Binary.putByteString (BS.pack [0x53, 0x56, 0x54, 0x52])
      Binary.putWord16be 2
      Binary.putWord32be (HB.shapedTextUnitsPerEm shaped)
      Binary.putInt32be (HB.shapedTextAscender shaped)
      Binary.putInt32be (HB.shapedTextDescender shaped)
      Binary.putInt32be (HB.shapedTextLineGap shaped)
      Binary.putWord32be 1
      Binary.putWord32be 0
      Binary.putWord32be
        (fromIntegral (BS.length (Text.encodeUtf8 (Text.pack source))))
      let glyphs = HB.shapedTextGlyphs shaped
      Binary.putWord32be (fromIntegral (length glyphs))
      mapM_ putGlyph glyphs
      Binary.putWord32be 0
    putGlyph glyph = do
      Binary.putWord32be (HB.shapedGlyphId glyph)
      Binary.putWord32be (HB.shapedGlyphCluster glyph)
      putInt32 (HB.shapedGlyphXAdvance glyph)
      putInt32 (HB.shapedGlyphYAdvance glyph)
      putInt32 (HB.shapedGlyphXOffset glyph)
      putInt32 (HB.shapedGlyphYOffset glyph)
      putInt32 (HB.shapedGlyphXBearing glyph)
      putInt32 (HB.shapedGlyphYBearing glyph)
      putInt32 (HB.shapedGlyphWidth glyph)
      putInt32 (HB.shapedGlyphHeight glyph)
    putInt32 :: Int32 -> Binary.Put
    putInt32 = Binary.putInt32be

roundLayout :: Double -> Double
roundLayout value = fromIntegral (round (value * 1000) :: Int) / 1000
