{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Compiler-owned text preparation, constraints, and IR materialization.
--
-- Text is shaped after aesthetic choices are sampled and before the final
-- geometry solve. The initial solution supplies a known-feasible geometry for
-- deterministic line/size quality selection; the final solve receives hard
-- content-box constraints and pinned aesthetic choices.
module LinearTrace.Visualization.Typography
  ( PreparedTypography
  , TypographyOutput(..)
  , prepareTypography
  , preparedTypographyGraph
  , preparedTypographyChoices
  , preparedTypographyNeedsResolve
  , materializeTypography
  , typographyCompilationProvenance
  ) where

import           Control.Monad                           (foldM)
import qualified Data.Binary.Put                         as Binary
import qualified Data.ByteString                         as BS
import qualified Data.ByteString.Lazy                    as BL
import           Data.Char                               (isSpace)
import           Data.Int                                (Int32)
import           Data.List                               (find, minimumBy,
                                                          sortOn)
import           Data.Map.Strict                         (Map)
import qualified Data.Map.Strict                         as Map
import           Data.Maybe                              (catMaybes, fromMaybe,
                                                          listToMaybe)
import qualified Data.Text                               as Text
import qualified Data.Text.Encoding                      as Text
import qualified LinearTrace.View.Graph                  as V
import qualified LinearTrace.View.Primitives             as VP
import qualified LinearTrace.View.Style                  as VS
import qualified LinearTrace.Visualization.CodeHighlight as CodeHighlight
import qualified LinearTrace.Visualization.FontCatalog   as Font
import qualified LinearTrace.Visualization.HarfBuzz      as HB
import qualified LinearTrace.Visualization.IR            as IR
import qualified LinearTrace.Visualization.Resource      as Resource
import           Prelude
import qualified Solver                                  as S
import           Text.Read                               (readMaybe)

data PreparedTypography = PreparedTypography
  { preparedTypographyGraph        :: V.ViewGraph
  , preparedTypographyChoices      :: Map String String
  , preparedTypographyDrafts       :: Map Int TextDraft
  , preparedTypographyNeedsResolve :: Bool
  }

data TypographyOutput = TypographyOutput
  { typographyOutputContents  :: Map Int IR.VisualContent
  , typographyOutputResources :: [Resource.ResourceBlob]
  , typographyOutputFindings  :: [IR.VisualizationFinding]
  }

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

data SizeMode
  = FixedSize VP.LayoutExpr
  | FittedSize String Double

data SizePolicy
  = FixedSizePolicy Double VP.LayoutExpr
  | CappedFitPolicy Double (Maybe VP.LayoutExpr)
  | MaximumFitPolicy
  | OccupancyFitPolicy Double

data TextDraft = TextDraft
  { draftVisualId          :: Int
  , draftSource            :: String
  , draftWhitespace        :: IR.TextWhitespace
  , draftWrapMode          :: IR.TextWrapMode
  , draftFontResolution    :: Font.FontResolution
  , draftFontFeatures      :: [String]
  , draftPreferredSize     :: Double
  , draftSizeMode          :: SizeMode
  , draftLineHeightEm      :: Double
  , draftLines             :: [PreparedLine]
  , draftInsertedBreaks    :: Int
  , draftTextAlign         :: String
  , draftPaddingExpression :: VP.LayoutExpr
  , draftStrokeExpression  :: VP.LayoutExpr
  , draftWidthValue        :: Double
  , draftHeightValue       :: Double
  , draftPaddingValue      :: Double
  , draftStrokeValue       :: Double
  , draftSizeCap           :: Maybe (VP.LayoutExpr, Double)
  , draftContentFlavor     :: ContentFlavor
  }

data ContentFlavor
  = PlainTextFlavor
  | CodeTextFlavor (Maybe String)

data PreparedLine = PreparedLine
  { preparedLineRange        :: IR.TextSourceRange
  , preparedLineDisplay      :: String
  , preparedLineShape        :: HB.ShapedText
  , preparedLineAdvanceUnits :: Double
  , preparedLineMinXUnits    :: Double
  , preparedLineMaxXUnits    :: Double
  , preparedLineMinYUnits    :: Double
  , preparedLineMaxYUnits    :: Double
  }

data SourceLine = SourceLine
  { sourceLineRange   :: IR.TextSourceRange
  , sourceLineDisplay :: String
  } deriving (Eq, Show)

data ShapedCandidate = ShapedCandidate
  { candidateLines          :: [PreparedLine]
  , candidateInsertedBreaks :: Int
  , candidateMaximumSize    :: Double
  , candidateLineHeightEm   :: Double
  }

data DraftChoice = DraftChoice
  { choiceDraft        :: TextDraft
  , choiceSelectedSize :: Double
  }

prepareTypography ::
     S.Solution -> V.ViewGraph -> IO (Either String PreparedTypography)
prepareTypography initialSolution graph = do
  prepared <- traverseEitherIO (prepareNode initialSolution) (V.viewNodes graph)
  pure $ do
    maybeChoices <- prepared
    let choices = catMaybes maybeChoices
        fittedSizes =
          Map.fromListWith
            min
            [ (family, choiceSelectedSize choice)
            | choice <- choices
            , FittedSize family _ <- [draftSizeMode (choiceDraft choice)]
            ]
        drafts = map (applySharedSize fittedSizes . choiceDraft) choices
        draftMap = Map.fromList [(draftVisualId draft, draft) | draft <- drafts]
        (updatedNodes, constraints) =
          unzip (map (applyDraft draftMap) (V.viewNodes graph))
        updatedGraph =
          graph
            { V.viewNodes = updatedNodes
            , V.viewConstraints = V.viewConstraints graph ++ concat constraints
            }
    pure
      PreparedTypography
        { preparedTypographyGraph = updatedGraph
        , preparedTypographyChoices = S.solutionChoices initialSolution
        , preparedTypographyDrafts = draftMap
        , preparedTypographyNeedsResolve = not (Map.null draftMap)
        }

prepareNode ::
     S.Solution -> V.ViewNode -> IO (Either String (Maybe DraftChoice))
prepareNode solution wrapped =
  case wrapped of
    V.ViewNode node ->
      case V.nodeContent node of
        V.ContentEmpty -> pure (Right Nothing)
        V.ContentText source ->
          prepareTextNode PlainTextFlavor False Nothing solution node source
        V.ContentFitText source ->
          prepareTextNode PlainTextFlavor True Nothing solution node source
        V.ContentCode code ->
          prepareTextNode
            (CodeTextFlavor (V.codeContentLanguage code))
            False
            (Just
               (case V.codeContentWrapMode code of
                  V.CodeNoWrap   -> "pre"
                  V.CodeSoftWrap -> "code-wrap"))
            solution
            node
            (V.codeContentSource code)

prepareTextNode ::
     ContentFlavor
  -> Bool
  -> Maybe String
  -> S.Solution
  -> V.Node tag
  -> String
  -> IO (Either String (Maybe DraftChoice))
prepareTextNode flavor explicitFit whiteSpaceOverride solution node source = do
  let style = V.nodeStyle node
  case resolvedTextStyle explicitFit solution style of
    Left err -> pure (Left (nodePrefix node ++ err))
    Right initialResolved -> do
      let resolved =
            initialResolved
              { resolvedWhiteSpace =
                  fromMaybe
                    (resolvedWhiteSpace initialResolved)
                    whiteSpaceOverride
              }
      fontResult <-
        Font.resolveFont
          Font.bundledFontCatalog
          (resolvedFamily resolved)
          (resolvedWeight resolved)
          (resolvedFontStyle resolved)
      case fontResult of
        Left err -> pure (Left (nodePrefix node ++ err))
        Right fontResolution ->
          prepareTextDraft solution node resolved fontResolution flavor source

data ResolvedTextStyle = ResolvedTextStyle
  { resolvedFamily          :: String
  , resolvedWeight          :: Int
  , resolvedFontStyle       :: String
  , resolvedSizePolicy      :: SizePolicy
  , resolvedPadding         :: Double
  , resolvedStrokeWidth     :: Double
  , resolvedTextAlign       :: String
  , resolvedWhiteSpace      :: String
  , resolvedPaddingExpr     :: VP.LayoutExpr
  , resolvedStrokeWidthExpr :: VP.LayoutExpr
  }

resolvedTextStyle ::
     Bool -> S.Solution -> VS.NodeStyle -> Either String ResolvedTextStyle
resolvedTextStyle explicitFit solution style = do
  family <- resolvedOr @VS.FontFamily "Inter"
  weightToken <- resolvedOr @VS.FontWeight "normal"
  fontStyle <- resolvedOr @VS.FontStyle "normal"
  fontSizeValue <- VS.materializeStyleField @VS.FontSize solution style
  occupancyValue <- VS.materializeStyleField @VS.TextOccupancy solution style
  paddingValue <- resolvedOr @VS.Padding 0
  strokeValue <- resolvedOr @VS.StrokeWidth 0
  borderStyle <- resolvedOr @VS.BorderStyle "solid"
  textAlign <- resolvedOr @VS.TextAlign "center"
  whiteSpace <- resolvedOr @VS.WhiteSpace "normal"
  let sizeExpression = VS.getStyleField @VS.FontSize style
      sizePolicy
        | explicitFit =
          case fontSizeValue of
            Just value -> CappedFitPolicy value sizeExpression
            Nothing    -> MaximumFitPolicy
        | VS.hasStyleField @VS.FontSize style =
          case fontSizeValue of
            Just value ->
              FixedSizePolicy value (fromMaybe (S.num value) sizeExpression)
            Nothing -> FixedSizePolicy 14 (S.num 14)
        | Just occupancy <- occupancyValue = OccupancyFitPolicy occupancy
        | otherwise = CappedFitPolicy 14 Nothing
      paddingExpression =
        fromMaybe (S.num paddingValue) (VS.getStyleField @VS.Padding style)
      visibleStroke =
        if borderStyle == "none"
          then 0
          else strokeValue
      strokeExpression =
        if borderStyle == "none"
          then S.num 0
          else fromMaybe
                 (S.num visibleStroke)
                 (VS.getStyleField @VS.StrokeWidth style)
  pure
    ResolvedTextStyle
      { resolvedFamily = family
      , resolvedWeight = parseFontWeight weightToken
      , resolvedFontStyle = fontStyle
      , resolvedSizePolicy = sizePolicy
      , resolvedPadding = paddingValue
      , resolvedStrokeWidth = visibleStroke
      , resolvedTextAlign = textAlign
      , resolvedWhiteSpace = whiteSpace
      , resolvedPaddingExpr = paddingExpression
      , resolvedStrokeWidthExpr = strokeExpression
      }
  where
    resolvedOr ::
         forall field. VS.StyleField field
      => VS.ResolvedStyleValue field
      -> Either String (VS.ResolvedStyleValue field)
    resolvedOr fallback =
      fromMaybe fallback <$> VS.materializeStyleField @field solution style

prepareTextDraft ::
     S.Solution
  -> V.Node tag
  -> ResolvedTextStyle
  -> Font.FontResolution
  -> ContentFlavor
  -> String
  -> IO (Either String (Maybe DraftChoice))
prepareTextDraft solution node resolved fontResolution flavor source = do
  let face = Font.fontResolutionFace fontResolution
      fontBytes = Resource.resourceBlobBytes (Font.fontFaceResource face)
      shapeOptions =
        HB.defaultShapeOptions
          { HB.shapeOptionWeight = Font.fontFaceWeight face
          , HB.shapeOptionDisableLigatures = not (null fontFeatures)
          }
      fontFeatures = effectiveFontFeatures flavor face
      sourceCandidates = lineCandidates (resolvedWhiteSpace resolved) source
  probeResult <- HB.shapeText fontBytes shapeOptions "Hg"
  case probeResult of
    Left err -> pure (Left (nodePrefix node ++ err))
    Right probe -> do
      shaped <-
        traverseEitherIO
          (shapeCandidate fontBytes shapeOptions probe)
          sourceCandidates
      pure $ do
        candidates <- shaped
        let bounds = VS.nodeStyleBounds (V.nodeStyle node)
        widthValue <- evaluate "width" solution (VP.width bounds)
        heightValue <- evaluate "height" solution (VP.height bounds)
        let inset = resolvedPadding resolved + resolvedStrokeWidth resolved
            availableWidth = max 0 (widthValue - 2 * inset)
            availableHeight = max 0 (heightValue - 2 * inset)
            sizedCandidates =
              map (withMaximumSize availableWidth availableHeight) candidates
        selected <-
          selectCandidate (resolvedSizePolicy resolved) sizedCandidates
        let fittedFamily =
              familyFitKey
                node
                resolved
                fontResolution
                (sizePolicyKey (resolvedSizePolicy resolved))
            sizeMode =
              case resolvedSizePolicy resolved of
                FixedSizePolicy _ expression -> FixedSize expression
                _ -> FittedSize fittedFamily (choiceSelectedSize selected)
            sizeCap =
              case resolvedSizePolicy resolved of
                CappedFitPolicy value (Just expression) ->
                  Just (expression, value)
                _ -> Nothing
            chosen = choiceDraft selected
            draft =
              chosen
                { draftVisualId = V.viewRefInt (V.nodeRef node)
                , draftSource = source
                , draftWhitespace =
                    compileWhitespace (resolvedWhiteSpace resolved)
                , draftWrapMode = compileWrapMode (resolvedWhiteSpace resolved)
                , draftFontResolution = fontResolution
                , draftFontFeatures = fontFeatures
                , draftSizeMode = sizeMode
                , draftTextAlign = resolvedTextAlign resolved
                , draftPaddingExpression = resolvedPaddingExpr resolved
                , draftStrokeExpression = resolvedStrokeWidthExpr resolved
                , draftWidthValue = widthValue
                , draftHeightValue = heightValue
                , draftPaddingValue = resolvedPadding resolved
                , draftStrokeValue = resolvedStrokeWidth resolved
                , draftSizeCap = sizeCap
                , draftContentFlavor = flavor
                }
        pure (Just selected {choiceDraft = draft})

shapeCandidate ::
     BS.ByteString
  -> HB.ShapeOptions
  -> HB.ShapedText
  -> ([SourceLine], Int)
  -> IO (Either String ShapedCandidate)
shapeCandidate fontBytes options probe (lines', insertedBreaks) = do
  results <- traverseEitherIO (shapeLine fontBytes options probe) lines'
  pure $ do
    preparedLines <- results
    pure
      ShapedCandidate
        { candidateLines = preparedLines
        , candidateInsertedBreaks = insertedBreaks
        , candidateMaximumSize = 0
        , candidateLineHeightEm = lineHeightEm probe
        }

shapeLine ::
     BS.ByteString
  -> HB.ShapeOptions
  -> HB.ShapedText
  -> SourceLine
  -> IO (Either String PreparedLine)
shapeLine fontBytes options probe sourceLine = do
  shapedResult <-
    if null (sourceLineDisplay sourceLine)
      then pure (Right probe {HB.shapedTextGlyphs = []})
      else HB.shapeText fontBytes options (sourceLineDisplay sourceLine)
  pure $ do
    shaped <- shapedResult
    let missing =
          [ HB.shapedGlyphCluster glyph
          | glyph <- HB.shapedTextGlyphs shaped
          , HB.shapedGlyphId glyph == 0
          ]
    if not (null missing)
      then Left
             ("managed font is missing glyphs at UTF-8 byte clusters "
                ++ show missing)
      else let metrics = lineMetrics shaped
            in Right
                 PreparedLine
                   { preparedLineRange = sourceLineRange sourceLine
                   , preparedLineDisplay = sourceLineDisplay sourceLine
                   , preparedLineShape = shaped
                   , preparedLineAdvanceUnits = metricAdvance metrics
                   , preparedLineMinXUnits = metricMinX metrics
                   , preparedLineMaxXUnits = metricMaxX metrics
                   , preparedLineMinYUnits = metricMinY metrics
                   , preparedLineMaxYUnits = metricMaxY metrics
                   }

data LineMetric = LineMetric
  { metricAdvance :: Double
  , metricMinX    :: Double
  , metricMaxX    :: Double
  , metricMinY    :: Double
  , metricMaxY    :: Double
  }

data VerticalBlockMetric = VerticalBlockMetric
  { verticalBlockTopUnits    :: Double
  , verticalBlockBottomUnits :: Double
  }

lineMetrics :: HB.ShapedText -> LineMetric
lineMetrics shaped =
  let (penX, penY, bounds) =
        foldl advanceGlyph (0, 0, Nothing) (HB.shapedTextGlyphs shaped)
      (minX, maxX, minY, maxY) =
        case bounds of
          Nothing -> (min 0 penX, max 0 penX, min 0 penY, max 0 penY)
          Just (x0, x1, y0, y1) ->
            (min x0 (min 0 penX), max x1 (max 0 penX), min y0 0, max y1 0)
   in LineMetric
        { metricAdvance = abs penX
        , metricMinX = minX
        , metricMaxX = maxX
        , metricMinY = minY
        , metricMaxY = maxY
        }
  where
    advanceGlyph (penX, penY, bounds) glyph =
      let glyphX =
            penX
              + fromIntegral (HB.shapedGlyphXOffset glyph)
              + fromIntegral (HB.shapedGlyphXBearing glyph)
          glyphY =
            penY
              + fromIntegral (HB.shapedGlyphYOffset glyph)
              + fromIntegral (HB.shapedGlyphYBearing glyph)
          glyphEndX = glyphX + fromIntegral (HB.shapedGlyphWidth glyph)
          glyphEndY = glyphY + fromIntegral (HB.shapedGlyphHeight glyph)
          glyphBounds =
            ( min glyphX glyphEndX
            , max glyphX glyphEndX
            , min glyphY glyphEndY
            , max glyphY glyphEndY)
          nextBounds = Just (mergeBounds glyphBounds bounds)
       in ( penX + fromIntegral (HB.shapedGlyphXAdvance glyph)
          , penY + fromIntegral (HB.shapedGlyphYAdvance glyph)
          , nextBounds)
    mergeBounds current Nothing = current
    mergeBounds (x0, x1, y0, y1) (Just (a0, a1, b0, b1)) =
      (min x0 a0, max x1 a1, min y0 b0, max y1 b1)

lineHeightEm :: HB.ShapedText -> Double
lineHeightEm shaped =
  let upem = fromIntegral (max 1 (HB.shapedTextUnitsPerEm shaped))
      fontHeight =
        fromIntegral
          (HB.shapedTextAscender shaped
             - HB.shapedTextDescender shaped
             + HB.shapedTextLineGap shaped)
          / upem
   in max 1.2 fontHeight

verticalBlockMetric :: Double -> [PreparedLine] -> VerticalBlockMetric
verticalBlockMetric lineHeightEm' lines' =
  case listToMaybe lines' of
    Nothing -> VerticalBlockMetric 0 0
    Just firstLine ->
      let shaped = preparedLineShape firstLine
          upem = fromIntegral (max 1 (HB.shapedTextUnitsPerEm shaped))
          lineHeightUnits = lineHeightEm' * upem
          ascender = fromIntegral (HB.shapedTextAscender shaped)
          descender = fromIntegral (HB.shapedTextDescender shaped)
          halfLeading = max 0 ((lineHeightUnits - (ascender - descender)) / 2)
          nominalMaximumY = ascender + halfLeading
          nominalMinimumY = descender - halfLeading
          lineBounds =
            [ ( fromIntegral index * lineHeightUnits
                  - max nominalMaximumY (preparedLineMaxYUnits line)
              , fromIntegral index * lineHeightUnits
                  - min nominalMinimumY (preparedLineMinYUnits line))
            | (index, line) <- zip [0 :: Int ..] lines'
            ]
       in VerticalBlockMetric
            { verticalBlockTopUnits = minimum (map fst lineBounds)
            , verticalBlockBottomUnits = maximum (map snd lineBounds)
            }

verticalBlockHeightUnits :: VerticalBlockMetric -> Double
verticalBlockHeightUnits metric =
  verticalBlockBottomUnits metric - verticalBlockTopUnits metric

withMaximumSize :: Double -> Double -> ShapedCandidate -> ShapedCandidate
withMaximumSize availableWidth availableHeight candidate =
  candidate {candidateMaximumSize = maximumSize}
  where
    lines' = candidateLines candidate
    upem =
      fromIntegral
        (max
           1
           (maybe
              1
              (HB.shapedTextUnitsPerEm . preparedLineShape)
              (listToMaybe lines')))
    maximumWidthEm =
      maximum
        (0
           : [ (preparedLineMaxXUnits line - preparedLineMinXUnits line) / upem
             | line <- lines'
             ])
        * metricSafetyFactor
    requiredHeightEm =
      verticalBlockHeightUnits
        (verticalBlockMetric (candidateLineHeightEm candidate) lines')
        / upem
        * metricSafetyFactor
    widthSize =
      if maximumWidthEm <= 0
        then availableHeight
        else availableWidth / maximumWidthEm
    heightSize =
      if requiredHeightEm <= 0
        then availableWidth
        else availableHeight / requiredHeightEm
    maximumSize = min widthSize heightSize

metricSafetyFactor :: Double
metricSafetyFactor = 1.005

selectCandidate :: SizePolicy -> [ShapedCandidate] -> Either String DraftChoice
selectCandidate policy candidates =
  case firstUsableTier of
    Nothing ->
      Left
        ("text has no feasible compiler-selected layout at "
           ++ requiredSizeDescription policy
           ++ "; enlarge its bounds, reduce padding, or choose a shorter label")
    Just tier ->
      let best = minimumBy candidateOrdering tier
          maximumSize = candidateMaximumSize best
          selectedSize = selectedSizeFor policy maximumSize
          preferredSize = preferredSizeFor policy selectedSize
          emptyDraft =
            TextDraft
              { draftVisualId = 0
              , draftSource = ""
              , draftWhitespace = IR.TextCollapseWhitespace
              , draftWrapMode = IR.TextNoAutomaticWrap
              , draftFontResolution =
                  error "font resolution is installed after candidate selection"
              , draftFontFeatures = []
              , draftPreferredSize = preferredSize
              , draftSizeMode = FittedSize "" selectedSize
              , draftLineHeightEm = candidateLineHeightEm best
              , draftLines = candidateLines best
              , draftInsertedBreaks = candidateInsertedBreaks best
              , draftTextAlign = "center"
              , draftPaddingExpression = S.num 0
              , draftStrokeExpression = S.num 0
              , draftWidthValue = 0
              , draftHeightValue = 0
              , draftPaddingValue = 0
              , draftStrokeValue = 0
              , draftSizeCap = Nothing
              , draftContentFlavor = PlainTextFlavor
              }
       in Right
            DraftChoice
              {choiceDraft = emptyDraft, choiceSelectedSize = selectedSize}
  where
    eligible candidate =
      candidateMaximumSize candidate + fitTolerance
        >= minimumRequiredSize policy
    tiers =
      [ filter
        (\candidate -> candidateInsertedBreaks candidate == breakCount)
        candidates
      | breakCount <-
          [0 .. maximum (0 : map candidateInsertedBreaks candidates)]
      ]
    firstUsableTier = find (any eligible) (map (filter eligible) tiers)
    candidateOrdering left right =
      compare
        ( negate (candidateMaximumSize left)
        , lineBalanceScore (candidateLines left)
        , map preparedLineDisplay (candidateLines left))
        ( negate (candidateMaximumSize right)
        , lineBalanceScore (candidateLines right)
        , map preparedLineDisplay (candidateLines right))

minimumRequiredSize :: SizePolicy -> Double
minimumRequiredSize policy =
  case policy of
    FixedSizePolicy value _ -> value
    CappedFitPolicy cap _   -> min cap minimumFittedSize
    _                       -> minimumFittedSize

requiredSizeDescription :: SizePolicy -> String
requiredSizeDescription policy =
  case policy of
    FixedSizePolicy value _ -> show value ++ "px"
    CappedFitPolicy cap _   -> show (min cap minimumFittedSize) ++ "px"
    _                       -> show minimumFittedSize ++ "px"

selectedSizeFor :: SizePolicy -> Double -> Double
selectedSizeFor policy maximumSize =
  case policy of
    FixedSizePolicy value _ -> value
    CappedFitPolicy cap _ -> quantizeSize (min cap maximumSize)
    MaximumFitPolicy -> quantizeSize maximumSize
    OccupancyFitPolicy occupancy ->
      quantizeSize
        (min maximumSize (max minimumFittedSize (occupancy * maximumSize)))

preferredSizeFor :: SizePolicy -> Double -> Double
preferredSizeFor policy selectedSize =
  case policy of
    FixedSizePolicy value _ -> value
    CappedFitPolicy cap _   -> cap
    MaximumFitPolicy        -> selectedSize
    OccupancyFitPolicy _    -> selectedSize

sizePolicyKey :: SizePolicy -> String
sizePolicyKey policy =
  case policy of
    FixedSizePolicy value _      -> "fixed:" ++ show value
    CappedFitPolicy cap _        -> "capped:" ++ show cap
    MaximumFitPolicy             -> "maximum"
    OccupancyFitPolicy occupancy -> "occupancy:" ++ show occupancy

minimumFittedSize :: Double
minimumFittedSize = 12

fitTolerance :: Double
fitTolerance = 0.01

quantizeSize :: Double -> Double
quantizeSize value
  | value >= minimumFittedSize =
    max minimumFittedSize (fromIntegral (floor (value * 4 + 1e-9) :: Int) / 4)
  | otherwise = value

lineBalanceScore :: [PreparedLine] -> Double
lineBalanceScore lines' =
  case map preparedLineAdvanceUnits lines' of
    []     -> 0
    values -> maximum values - minimum values

applySharedSize :: Map String Double -> TextDraft -> TextDraft
applySharedSize fittedSizes draft =
  case draftSizeMode draft of
    FixedSize _ -> draft
    FittedSize family fallback ->
      draft
        { draftSizeMode =
            FittedSize family (Map.findWithDefault fallback family fittedSizes)
        }

applyDraft :: Map Int TextDraft -> V.ViewNode -> (V.ViewNode, [S.Constraint])
applyDraft drafts wrapped =
  case wrapped of
    V.ViewNode node ->
      case Map.lookup (V.viewRefInt (V.nodeRef node)) drafts of
        Nothing -> (wrapped, [])
        Just draft ->
          let style =
                case draftSizeMode draft of
                  FixedSize _ -> V.nodeStyle node
                  FittedSize _ selected ->
                    VS.setStyleField @VS.FontSize
                      (S.num selected)
                      (V.nodeStyle node)
              updated = V.ViewNode node {V.nodeStyle = style}
           in ( updated
              , textConstraints node draft ++ typographyInputPins node draft)

typographyInputPins :: V.Node tag -> TextDraft -> [S.Constraint]
typographyInputPins node draft =
  [ VP.width node S.@==@ S.num (draftWidthValue draft)
  , VP.height node S.@==@ S.num (draftHeightValue draft)
  , draftPaddingExpression draft S.@==@ S.num (draftPaddingValue draft)
  , draftStrokeExpression draft S.@==@ S.num (draftStrokeValue draft)
  ]
    ++ case draftSizeMode draft of
         FixedSize expression ->
           [expression S.@==@ S.num (draftPreferredSize draft)]
         FittedSize _ _ ->
           case draftSizeCap draft of
             Just (expression, value) -> [expression S.@==@ S.num value]
             Nothing                  -> []

textConstraints :: V.Node tag -> TextDraft -> [S.Constraint]
textConstraints node draft =
  [requiredWidth S.@<=@ VP.width node, requiredHeight S.@<=@ VP.height node]
  where
    sizeExpression =
      case draftSizeMode draft of
        FixedSize expression -> expression
        FittedSize _ size    -> S.num size
    inset = draftPaddingExpression draft S.@+@ draftStrokeExpression draft
    upem =
      fromIntegral
        (max
           1
           (maybe
              1
              (HB.shapedTextUnitsPerEm . preparedLineShape)
              (listToMaybe (draftLines draft))))
    maximumWidthEm =
      maximum
        (0
           : [ (preparedLineMaxXUnits line - preparedLineMinXUnits line) / upem
             | line <- draftLines draft
             ])
        * metricSafetyFactor
    heightEm =
      verticalBlockHeightUnits
        (verticalBlockMetric (draftLineHeightEm draft) (draftLines draft))
        / upem
        * metricSafetyFactor
    requiredWidth =
      inset S.@*@ S.num 2 S.@+@ sizeExpression S.@*@ S.num maximumWidthEm
    requiredHeight =
      inset S.@*@ S.num 2 S.@+@ sizeExpression S.@*@ S.num heightEm

materializeTypography ::
     S.Solution -> PreparedTypography -> Either String TypographyOutput
materializeTypography solution prepared = do
  materialized <-
    traverse
      (materializeDraft solution (preparedTypographyGraph prepared))
      (Map.elems (preparedTypographyDrafts prepared))
  let contents =
        Map.fromList
          [ (draftVisualId draft, content)
          | (draft, content, _, _) <- materialized
          ]
      resources =
        deduplicateResources
          [ resource
          | (_, _, draftResources, _) <- materialized
          , resource <- draftResources
          ]
      findings =
        concat [findingsForDraft | (_, _, _, findingsForDraft) <- materialized]
  pure
    TypographyOutput
      { typographyOutputContents = contents
      , typographyOutputResources = resources
      , typographyOutputFindings = findings
      }

materializeDraft ::
     S.Solution
  -> V.ViewGraph
  -> TextDraft
  -> Either
       String
       ( TextDraft
       , IR.VisualContent
       , [Resource.ResourceBlob]
       , [IR.VisualizationFinding])
materializeDraft solution graph draft = do
  style <- lookupNodeStyle (draftVisualId draft) (V.viewNodes graph)
  let VP.Bounds topExpr leftExpr widthExpr heightExpr = VS.nodeStyleBounds style
  topValue <- evaluate "top" solution topExpr
  leftValue <- evaluate "left" solution leftExpr
  widthValue <- evaluate "width" solution widthExpr
  heightValue <- evaluate "height" solution heightExpr
  padding <- resolvedScalar @VS.Padding solution style 0
  strokeWidth <- resolvedScalar @VS.StrokeWidth solution style 0
  borderStyle <- resolvedChoice @VS.BorderStyle solution style "solid"
  fontSize <-
    case draftSizeMode draft of
      FixedSize expression  -> evaluate "fontSize" solution expression
      FittedSize _ selected -> Right selected
  highlightLines <- materializeHighlightLines draft
  let visibleStroke =
        if borderStyle == "none"
          then 0
          else strokeWidth
      inset = padding + visibleStroke
      contentBox =
        IR.LayoutRect
          { IR.layoutRectX = roundLayout (leftValue + inset)
          , IR.layoutRectY = roundLayout (topValue + inset)
          , IR.layoutRectWidth = roundLayout (max 0 (widthValue - 2 * inset))
          , IR.layoutRectHeight = roundLayout (max 0 (heightValue - 2 * inset))
          }
      fontFace = Font.fontResolutionFace (draftFontResolution draft)
      fontResource = Font.fontFaceResource fontFace
      fontDescriptor = Resource.resourceBlobDescriptor fontResource
      textRunResource =
        Resource.resourceBlob
          IR.TextRunResource
          "application/vnd.sverlin.text-run-v2"
          (encodeTextRun draft highlightLines)
      textRunDescriptor = Resource.resourceBlobDescriptor textRunResource
      lines' = materializeLines contentBox fontSize draft
      firstShape = preparedLineShape <$> listToMaybe (draftLines draft)
      direction =
        case firstShape of
          Just shaped
            | HB.shapedTextRightToLeft shaped -> IR.TextRightToLeft
          _ -> IR.TextLeftToRight
      script = maybe "Zyyy" HB.shapedTextScript firstShape
      fontInstance =
        IR.FontInstance
          { IR.fontInstanceFamily = Font.fontFaceFamily fontFace
          , IR.fontInstanceResourceId = IR.resourceDescriptorId fontDescriptor
          , IR.fontInstanceWeight = Font.fontFaceWeight fontFace
          , IR.fontInstanceStyle = Font.fontFaceStyle fontFace
          , IR.fontInstanceAxes = Font.fontFaceAxes fontFace
          , IR.fontInstanceFeatures = draftFontFeatures draft
          }
      layout =
        IR.TextLayout
          { IR.textLayoutSource = draftSource draft
          , IR.textLayoutWhitespace = draftWhitespace draft
          , IR.textLayoutWrapMode = draftWrapMode draft
          , IR.textLayoutFont = fontInstance
          , IR.textLayoutFontSize = roundLayout fontSize
          , IR.textLayoutPreferredSize = roundLayout (draftPreferredSize draft)
          , IR.textLayoutLineHeight =
              roundLayout (draftLineHeightEm draft * fontSize)
          , IR.textLayoutDirection = direction
          , IR.textLayoutScript = script
          , IR.textLayoutLanguage = "und"
          , IR.textLayoutAlignment = draftTextAlign draft
          , IR.textLayoutContentBox = contentBox
          , IR.textLayoutLines = lines'
          , IR.textLayoutTextRunResource =
              IR.resourceDescriptorId textRunDescriptor
          }
      findings = draftFindings fontSize draft
      content =
        case draftContentFlavor draft of
          PlainTextFlavor -> IR.PlainTextContent layout
          CodeTextFlavor language ->
            IR.CodeTextContent layout language highlightLines
  pure (draft, content, [fontResource, textRunResource], findings)

materializeHighlightLines :: TextDraft -> Either String [IR.CodeHighlightLine]
materializeHighlightLines draft =
  case draftContentFlavor draft of
    PlainTextFlavor -> Right []
    CodeTextFlavor Nothing -> Right (map normalLine (draftLines draft))
    CodeTextFlavor (Just language) ->
      CodeHighlight.highlightCodeLines
        language
        (draftSource draft)
        [ (preparedLineRange line, preparedLineDisplay line)
        | line <- draftLines draft
        ]
  where
    normalLine line =
      [ IR.CodeToken
        { IR.codeTokenSourceRange = preparedLineRange line
        , IR.codeTokenText = preparedLineDisplay line
        , IR.codeTokenKind = IR.CodeNormal
        }
      | not (null (preparedLineDisplay line))
      ]

materializeLines :: IR.LayoutRect -> Double -> TextDraft -> [IR.TextLine]
materializeLines contentBox fontSize draft =
  zipWith materializeLine [0 :: Int ..] (draftLines draft)
  where
    lineHeight = draftLineHeightEm draft * fontSize
    firstShape = preparedLineShape <$> listToMaybe (draftLines draft)
    upem = fromIntegral (max 1 (maybe 1 HB.shapedTextUnitsPerEm firstShape))
    scale = fontSize / upem
    blockMetric =
      verticalBlockMetric (draftLineHeightEm draft) (draftLines draft)
    blockTop = verticalBlockTopUnits blockMetric * scale
    blockHeight = verticalBlockHeightUnits blockMetric * scale
    firstBaseline =
      IR.layoutRectY contentBox
        + (IR.layoutRectHeight contentBox - blockHeight) / 2
        - blockTop
    materializeLine index line =
      let lineWidth =
            (preparedLineMaxXUnits line - preparedLineMinXUnits line) * scale
          targetLeft =
            case draftTextAlign draft of
              "left" -> IR.layoutRectX contentBox
              "right" ->
                IR.layoutRectX contentBox
                  + IR.layoutRectWidth contentBox
                  - lineWidth
              _ ->
                IR.layoutRectX contentBox
                  + (IR.layoutRectWidth contentBox - lineWidth) / 2
          originX = targetLeft - preparedLineMinXUnits line * scale
          baseline = firstBaseline + fromIntegral index * lineHeight
          inkTop = baseline - preparedLineMaxYUnits line * scale
          inkHeight =
            (preparedLineMaxYUnits line - preparedLineMinYUnits line) * scale
       in IR.TextLine
            { IR.textLineSourceRange = preparedLineRange line
            , IR.textLineDisplayText = preparedLineDisplay line
            , IR.textLineOriginX = roundLayout originX
            , IR.textLineBaselineY = roundLayout baseline
            , IR.textLineAdvance =
                roundLayout (preparedLineAdvanceUnits line * scale)
            , IR.textLineInkBounds =
                IR.LayoutRect
                  { IR.layoutRectX = roundLayout targetLeft
                  , IR.layoutRectY = roundLayout inkTop
                  , IR.layoutRectWidth = roundLayout lineWidth
                  , IR.layoutRectHeight = roundLayout inkHeight
                  }
            }

draftFindings :: Double -> TextDraft -> [IR.VisualizationFinding]
draftFindings fontSize draft =
  sizeFinding ++ smallFinding ++ wrapFinding ++ weightFinding
  where
    visualId = IR.VisualId (draftVisualId draft)
    base code message evidence =
      IR.VisualizationFinding
        { IR.visualizationFindingId =
            "typography." ++ code ++ "." ++ show (draftVisualId draft)
        , IR.visualizationFindingSeverity = IR.FindingWarning
        , IR.visualizationFindingCode = "typography." ++ code
        , IR.visualizationFindingMessage = message
        , IR.visualizationFindingElementIds = [visualId]
        , IR.visualizationFindingStepIndices = []
        , IR.visualizationFindingEvidence = evidence
        }
    numberEvidence key value unit =
      IR.FindingEvidence key (IR.FindingNumber (roundLayout value)) (Just unit)
    sizeFinding =
      [ base
        "size-reduced"
        "Text was made smaller to retain the compiler-selected line layout."
        [ numberEvidence "preferredSize" (draftPreferredSize draft) "px"
        , numberEvidence "selectedSize" fontSize "px"
        ]
      | fontSize + fitTolerance < draftPreferredSize draft
      ]
    smallFinding =
      [ base
        "small-physical-size"
        "Text is at the minimum managed font size and may be hard to read."
        [numberEvidence "selectedSize" fontSize "px"]
      | fontSize <= minimumFittedSize + fitTolerance
      ]
    wrapFinding =
      [ base
        "fallback-wrap"
        "The compiler inserted line breaks after single-line fitting was exhausted."
        [ IR.FindingEvidence
            "insertedBreaks"
            (IR.FindingNumber (fromIntegral (draftInsertedBreaks draft)))
            Nothing
        ]
      | draftInsertedBreaks draft > 0
      ]
    resolution = draftFontResolution draft
    weightFinding =
      [ base
        "weight-substituted"
        "The nearest deterministic static font face was used for this weight."
        [ IR.FindingEvidence
            "requestedWeight"
            (IR.FindingNumber
               (fromIntegral (Font.fontResolutionRequestedWeight resolution)))
            Nothing
        , IR.FindingEvidence
            "selectedWeight"
            (IR.FindingNumber
               (fromIntegral
                  (Font.fontFaceWeight (Font.fontResolutionFace resolution))))
            Nothing
        ]
      | Font.fontResolutionWeightSubstituted resolution
      ]

encodeTextRun :: TextDraft -> [IR.CodeHighlightLine] -> BS.ByteString
encodeTextRun draft highlightLines =
  BL.toStrict
    (Binary.runPut $ do
       Binary.putByteString (BS.pack [0x53, 0x56, 0x54, 0x52])
       Binary.putWord16be 2
       let firstShape = preparedLineShape <$> listToMaybe (draftLines draft)
       Binary.putWord32be (maybe 0 HB.shapedTextUnitsPerEm firstShape)
       Binary.putInt32be (maybe 0 HB.shapedTextAscender firstShape)
       Binary.putInt32be (maybe 0 HB.shapedTextDescender firstShape)
       Binary.putInt32be (maybe 0 HB.shapedTextLineGap firstShape)
       Binary.putWord32be (fromIntegral (length (draftLines draft)))
       mapM_ (uncurry putLine) (zip (draftLines draft) paddedHighlights))
  where
    paddedHighlights =
      take (length (draftLines draft)) (highlightLines ++ repeat [])
    putLine line highlighting = do
      Binary.putWord32be
        (fromIntegral (IR.textSourceRangeStart (preparedLineRange line)))
      Binary.putWord32be
        (fromIntegral (IR.textSourceRangeEnd (preparedLineRange line)))
      let glyphs = HB.shapedTextGlyphs (preparedLineShape line)
      Binary.putWord32be (fromIntegral (length glyphs))
      mapM_ putGlyph glyphs
      Binary.putWord32be (fromIntegral (length highlighting))
      mapM_ putToken highlighting
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
    putToken token = do
      Binary.putWord32be
        (fromIntegral (IR.textSourceRangeStart (IR.codeTokenSourceRange token)))
      Binary.putWord32be
        (fromIntegral (IR.textSourceRangeEnd (IR.codeTokenSourceRange token)))
      Binary.putWord8 (codeTokenTag (IR.codeTokenKind token))
    codeTokenTag kind =
      case kind of
        IR.CodeNormal   -> 0
        IR.CodeKeyword  -> 1
        IR.CodeType     -> 2
        IR.CodeNumber   -> 3
        IR.CodeString   -> 4
        IR.CodeComment  -> 5
        IR.CodeFunction -> 6
        IR.CodeVariable -> 7
        IR.CodeOperator -> 8
        IR.CodeError    -> 9

deduplicateResources :: [Resource.ResourceBlob] -> [Resource.ResourceBlob]
deduplicateResources = Map.elems . Map.fromList . map keyed
  where
    keyed resource =
      ( IR.resourceDescriptorId (Resource.resourceBlobDescriptor resource)
      , resource)

lineCandidates :: String -> String -> [([SourceLine], Int)]
lineCandidates whiteSpace source
  | whiteSpace == "code-wrap" = preservedWrapCandidates source
  | preservesWhitespace whiteSpace = [(preservedLines source, 0)]
  | whiteSpace == "nowrap" = [(collapsedSingleLine source, 0)]
  | otherwise = collapsedCandidates source

preservesWhitespace :: String -> Bool
preservesWhitespace whiteSpace =
  whiteSpace == "pre" || whiteSpace == "pre-wrap" || whiteSpace == "code-wrap"

preservedWrapCandidates :: String -> [([SourceLine], Int)]
preservedWrapCandidates source =
  (base, 0)
    : concat
        [ take
          maximumPartitionCandidates
          (sortOn
             candidateScore
             [ (applyPreservedBreaks base breaks, breakCount)
             | breaks <- chooseBreaks breakCount opportunities
             ])
        | breakCount <- [1 .. 2]
        ]
  where
    base = preservedLines source
    opportunities = preservedBreakOpportunities base
    candidateScore (lines', insertedBreaks) =
      ( insertedBreaks
      , maximum (0 : map (length . sourceLineDisplay) lines')
      , lineBalance (map (length . sourceLineDisplay) lines')
      , map sourceLineDisplay lines')
    lineBalance []     = 0
    lineBalance widths = maximum widths - minimum widths

data PreservedBreak = PreservedBreak
  { preservedBreakLine     :: Int
  , preservedBreakPosition :: Int
  } deriving (Eq, Ord, Show)

preservedBreakOpportunities :: [SourceLine] -> [PreservedBreak]
preservedBreakOpportunities lines' =
  [ PreservedBreak lineIndex position
  | (lineIndex, line) <- breakableLines
  , position <- representativePositions (preservedBreakPositions line)
  ]
  where
    breakableLines =
      take
        maximumBreakablePhysicalLines
        (sortOn
           (\(lineIndex, line) ->
              (negate (length (sourceLineDisplay line)), lineIndex))
           (zip [0 :: Int ..] lines'))

maximumBreakablePhysicalLines :: Int
maximumBreakablePhysicalLines = 4

maximumBreakPositionsPerLine :: Int
maximumBreakPositionsPerLine = 24

representativePositions :: [Int] -> [Int]
representativePositions positions
  | length positions <= maximumBreakPositionsPerLine = positions
  | otherwise =
    Map.keys
      (Map.fromList
         [ (positions !! sampleIndex index, ())
         | index <- [0 .. maximumBreakPositionsPerLine - 1]
         ])
  where
    lastIndex = length positions - 1
    sampleIndex index =
      round
        (fromIntegral index
           * fromIntegral lastIndex
           / fromIntegral (maximumBreakPositionsPerLine - 1) :: Double)

applyPreservedBreaks :: [SourceLine] -> [PreservedBreak] -> [SourceLine]
applyPreservedBreaks lines' breaks =
  concat
    [ case Map.lookup lineIndex breakMap of
      Nothing        -> [line]
      Just positions -> splitPreservedLine line (sortOn id positions)
    | (lineIndex, line) <- zip [0 :: Int ..] lines'
    ]
  where
    breakMap =
      Map.fromListWith
        (++)
        [ (preservedBreakLine break', [preservedBreakPosition break'])
        | break' <- breaks
        ]

preservedBreakPositions :: SourceLine -> [Int]
preservedBreakPositions line =
  case preferred of
    [] -> allPositions
    _  -> preferred
  where
    value = sourceLineDisplay line
    allPositions = [1 .. length value - 1]
    preferred = [index | index <- allPositions, isSpace (value !! index)]

splitPreservedLine :: SourceLine -> [Int] -> [SourceLine]
splitPreservedLine line breaks =
  [ let prefix = take start value
        display = take (end - start) (drop start value)
        byteStart =
          IR.textSourceRangeStart (sourceLineRange line) + utf8Length prefix
   in SourceLine
        (IR.TextSourceRange byteStart (byteStart + utf8Length display))
        display
  | (start, end) <- zip bounds (drop 1 bounds)
  ]
  where
    value = sourceLineDisplay line
    bounds = 0 : breaks ++ [length value]

collapsedSingleLine :: String -> [SourceLine]
collapsedSingleLine source =
  case tokenizeCollapsed source of
    []     -> [SourceLine (IR.TextSourceRange 0 0) ""]
    tokens -> [sourceLineFromTokens tokens]

collapsedCandidates :: String -> [([SourceLine], Int)]
collapsedCandidates source =
  case tokenizeCollapsed source of
    [] -> [([SourceLine (IR.TextSourceRange 0 0) ""], 0)]
    tokens ->
      concat
        [ candidatesForLineCount tokens lineCount
        | lineCount <- [1 .. min 3 (length tokens)]
        ]

data TextToken = TextToken
  { tokenValue :: String
  , tokenStart :: Int
  , tokenEnd   :: Int
  } deriving (Eq, Show)

tokenizeCollapsed :: String -> [TextToken]
tokenizeCollapsed = go 0
  where
    go _ [] = []
    go byteOffset input =
      let (spacing, afterSpacing) = span isSpace input
          wordStart = byteOffset + utf8Length spacing
          (value, rest) = break isSpace afterSpacing
          wordEnd = wordStart + utf8Length value
       in if null value
            then []
            else TextToken value wordStart wordEnd : go wordEnd rest

candidatesForLineCount :: [TextToken] -> Int -> [([SourceLine], Int)]
candidatesForLineCount tokens lineCount =
  map (\breaks -> (partitionTokens tokens breaks, lineCount - 1)) selectedBreaks
  where
    positions = [1 .. length tokens - 1]
    allBreaks = chooseBreaks (lineCount - 1) positions
    selectedBreaks =
      take
        maximumPartitionCandidates
        (map
           fst
           (sortOn
              snd
              [(breaks, partitionScore tokens breaks) | breaks <- allBreaks]))

maximumPartitionCandidates :: Int
maximumPartitionCandidates = 12

chooseBreaks :: Int -> [a] -> [[a]]
chooseBreaks count positions
  | count <= 0 = [[]]
  | otherwise =
    case positions of
      [] -> []
      position:rest ->
        map (position :) (chooseBreaks (count - 1) rest)
          ++ chooseBreaks count rest

partitionScore :: [TextToken] -> [Int] -> (Int, Int, [Int])
partitionScore tokens breaks =
  let widths = map (length . sourceLineDisplay) (partitionTokens tokens breaks)
   in ( maximum (0 : widths)
      , case widths of
          [] -> 0
          _  -> maximum widths - minimum widths
      , breaks)

partitionTokens :: [TextToken] -> [Int] -> [SourceLine]
partitionTokens tokens breaks =
  [ sourceLineFromTokens (take (end - start) (drop start tokens))
  | (start, end) <- zip bounds (drop 1 bounds)
  ]
  where
    bounds = 0 : breaks ++ [length tokens]

sourceLineFromTokens :: [TextToken] -> SourceLine
sourceLineFromTokens tokens =
  case tokens of
    [] -> SourceLine (IR.TextSourceRange 0 0) ""
    first:rest ->
      let lastToken = last (first : rest)
       in SourceLine
            { sourceLineRange =
                IR.TextSourceRange (tokenStart first) (tokenEnd lastToken)
            , sourceLineDisplay = unwords (map tokenValue (first : rest))
            }

preservedLines :: String -> [SourceLine]
preservedLines = go 0
  where
    go offset input =
      let (line, rest) = break (== '\n') input
          lineEnd = offset + utf8Length line
          current = SourceLine (IR.TextSourceRange offset lineEnd) line
       in case rest of
            []      -> [current]
            _:after -> current : go (lineEnd + 1) after

compileWhitespace :: String -> IR.TextWhitespace
compileWhitespace whiteSpace
  | preservesWhitespace whiteSpace = IR.TextPreserveWhitespace
  | otherwise = IR.TextCollapseWhitespace

compileWrapMode :: String -> IR.TextWrapMode
compileWrapMode whiteSpace
  | whiteSpace == "normal" || whiteSpace == "code-wrap" =
    IR.TextPreferSingleLine 2
  | otherwise = IR.TextNoAutomaticWrap

effectiveFontFeatures :: ContentFlavor -> Font.FontFace -> [String]
effectiveFontFeatures flavor face =
  foldl addFeature (Font.fontFaceFeatures face) contentFeatures
  where
    contentFeatures =
      case flavor of
        PlainTextFlavor  -> []
        CodeTextFlavor _ -> ["liga=0", "calt=0"]
    addFeature existing feature
      | feature `elem` existing = existing
      | otherwise = existing ++ [feature]

familyFitKey ::
     V.Node tag -> ResolvedTextStyle -> Font.FontResolution -> String -> String
familyFitKey node resolved resolution sizePolicy =
  let explicitFamily =
        fromMaybe
          (V.viewLabelKind (V.nodeLabel node))
          (VS.nodeStyleFamily (V.nodeStyle node))
      face = Font.fontResolutionFace resolution
   in intercalateKey
        [ explicitFamily
        , Font.fontFaceFamily face
        , Font.fontFaceStyle face
        , show (Font.fontFaceWeight face)
        , sizePolicy
        , resolvedTextAlign resolved
        ]

intercalateKey :: [String] -> String
intercalateKey = foldr1 (\left right -> left ++ "\NUL" ++ right)

parseFontWeight :: String -> Int
parseFontWeight token =
  case token of
    "normal"  -> 400
    "bold"    -> 700
    "bolder"  -> 700
    "lighter" -> 300
    _         -> min 900 (max 100 (fromMaybe 400 (readMaybe token)))

evaluate :: String -> S.Solution -> VP.LayoutExpr -> Either String Double
evaluate label solution expression =
  case S.evalExpr solution expression of
    Just value -> Right value
    Nothing ->
      Left
        ("could not evaluate typography "
           ++ label
           ++ "; its expression references an unsolved variable")

resolvedScalar ::
     forall field. (VS.StyleField field, VS.ResolvedStyleValue field ~ Double)
  => S.Solution
  -> VS.NodeStyle
  -> Double
  -> Either String Double
resolvedScalar solution style fallback =
  fromMaybe fallback <$> VS.materializeStyleField @field solution style

resolvedChoice ::
     forall field. (VS.StyleField field, VS.ResolvedStyleValue field ~ String)
  => S.Solution
  -> VS.NodeStyle
  -> String
  -> Either String String
resolvedChoice solution style fallback =
  fromMaybe fallback <$> VS.materializeStyleField @field solution style

lookupNode :: Int -> [V.ViewNode] -> Either String V.ViewNode
lookupNode identifier nodes =
  case filter hasIdentifier nodes of
    [node] -> Right node
    [] -> Left ("typography references unknown visual node " ++ show identifier)
    _ -> Left ("typography found duplicate visual node " ++ show identifier)
  where
    hasIdentifier wrapped =
      case wrapped of
        V.ViewNode node -> V.viewRefInt (V.nodeRef node) == identifier

lookupNodeStyle :: Int -> [V.ViewNode] -> Either String VS.NodeStyle
lookupNodeStyle identifier nodes = do
  wrapped <- lookupNode identifier nodes
  case wrapped of
    V.ViewNode node -> Right (V.nodeStyle node)

nodePrefix :: V.Node tag -> String
nodePrefix node = "text node " ++ show (V.viewRefInt (V.nodeRef node)) ++ ": "

utf8Length :: String -> Int
utf8Length = BS.length . Text.encodeUtf8 . Text.pack

traverseEitherIO :: (a -> IO (Either String b)) -> [a] -> IO (Either String [b])
traverseEitherIO action = foldM step (Right [])
  where
    step result value =
      case result of
        Left err -> pure (Left err)
        Right values -> do
          next <- action value
          pure ((\item -> values ++ [item]) <$> next)

roundLayout :: Double -> Double
roundLayout value =
  let rounded = fromIntegral (round (value * 1000) :: Integer) / 1000
   in if abs rounded < 0.0005
        then 0
        else rounded
