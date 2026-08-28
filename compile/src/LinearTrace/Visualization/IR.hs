{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

-- | Canonical, renderer-independent visualization IR.
--
-- This is the solved form of the visual DSL: style expressions and categorical
-- choices have concrete values, while variable references retain the link to
-- the CSP that produced each value. Renderers consume this model; they do not
-- solve it or make seeded choices of their own.
module LinearTrace.Visualization.IR
  ( VisualId(..)
  , RenderInstanceId(..)
  , ResourceId(..)
  , Sha256(..)
  , CspVariableId(..)
  , CspValue(..)
  , CspVariable(..)
  , HslColor(..)
  , LayoutRect(..)
  , EdgeInsets(..)
  , VisualBox(..)
  , CoordinateSystem(..)
  , ResourceKind(..)
  , ResourceDescriptor(..)
  , FindingSeverity(..)
  , FindingValue(..)
  , FindingEvidence(..)
  , VisualizationFinding(..)
  , TextDirection(..)
  , TextWhitespace(..)
  , TextWrapMode(..)
  , TextSourceRange(..)
  , FontAxis(..)
  , FontInstance(..)
  , TextLine(..)
  , TextLayout(..)
  , CodeTokenKind(..)
  , CodeToken(..)
  , CodeHighlightLine
  , VisualContent(..)
  , VisualStyle(..)
  , StyleVariableBinding(..)
  , VisualElement(..)
  , VisualInstance(..)
  , TimelineStep(..)
  , SamplingMode(..)
  , DecisionCoverage(..)
  , SamplingProvenance(..)
  , Visualization(..)
  , irJsonOptions
  ) where

import           Data.Aeson.TH
import           GHC.Generics                      (Generic)
import           LinearTrace.Visualization.Options (irJsonOptions)
import           Prelude

newtype VisualId =
  VisualId Int
  deriving (Eq, Ord, Show, Generic)

newtype RenderInstanceId =
  RenderInstanceId Int
  deriving (Eq, Ord, Show, Generic)

-- | Stable logical identifier for a content-addressed package resource.
newtype ResourceId =
  ResourceId String
  deriving (Eq, Ord, Show, Generic)

-- | Lower-case hexadecimal SHA-256 digest.
newtype Sha256 =
  Sha256 String
  deriving (Eq, Ord, Show, Generic)

newtype CspVariableId =
  CspVariableId String
  deriving (Eq, Ord, Show, Generic)

data CspValue
  = CspNumber
      { cspNumberValue :: Double
      }
  | CspCategory
      { cspCategoryValue :: String
      }
  deriving (Eq, Show, Generic)

data CspVariable = CspVariable
  { cspVariableId    :: CspVariableId
  , cspVariableValue :: CspValue
  } deriving (Eq, Show, Generic)

data HslColor = HslColor
  { hslHue        :: Double
  , hslSaturation :: Double
  , hslLightness  :: Double
  } deriving (Eq, Show, Generic)

-- | Axis-aligned box in canonical visualization layout units.
data LayoutRect = LayoutRect
  { layoutRectX      :: Double
  , layoutRectY      :: Double
  , layoutRectWidth  :: Double
  , layoutRectHeight :: Double
  } deriving (Eq, Show, Generic)

data EdgeInsets = EdgeInsets
  { insetsTop    :: Double
  , insetsRight  :: Double
  , insetsBottom :: Double
  , insetsLeft   :: Double
  } deriving (Eq, Show, Generic)

data VisualBox = VisualBox
  { boxBounds  :: LayoutRect
  , boxPadding :: EdgeInsets
  , boxMargin  :: EdgeInsets
  } deriving (Eq, Show, Generic)

-- | Explicit renderer-neutral logical coordinate convention. Values are SVG-like
-- user units and carry no CSS-pixel, DPI, or physical-size assumption.
data CoordinateSystem = CoordinateSystem
  { coordinateSystemName   :: String
  , coordinateSystemOrigin :: String
  , coordinateSystemYAxis  :: String
  } deriving (Eq, Show, Generic)

data ResourceKind
  = FontResource
  | TextRunResource
  | VectorResource
  deriving (Eq, Show, Generic)

-- | Public metadata for bytes carried beside an IR artifact.
data ResourceDescriptor = ResourceDescriptor
  { resourceDescriptorId         :: ResourceId
  , resourceDescriptorKind       :: ResourceKind
  , resourceDescriptorSha256     :: Sha256
  , resourceDescriptorMediaType  :: String
  , resourceDescriptorByteLength :: Int
  } deriving (Eq, Show, Generic)

data FindingSeverity
  = FindingInfo
  | FindingWarning
  deriving (Eq, Show, Generic)

data FindingValue
  = FindingNumber
      { findingNumberValue :: Double
      }
  | FindingText
      { findingTextValue :: String
      }
  | FindingBoolean
      { findingBooleanValue :: Bool
      }
  deriving (Eq, Show, Generic)

data FindingEvidence = FindingEvidence
  { findingEvidenceKey   :: String
  , findingEvidenceValue :: FindingValue
  , findingEvidenceUnit  :: Maybe String
  } deriving (Eq, Show, Generic)

-- | Deterministic compiler finding retained with successful IR.
data VisualizationFinding = VisualizationFinding
  { visualizationFindingId          :: String
  , visualizationFindingSeverity    :: FindingSeverity
  , visualizationFindingCode        :: String
  , visualizationFindingMessage     :: String
  , visualizationFindingElementIds  :: [VisualId]
  , visualizationFindingStepIndices :: [Int]
  , visualizationFindingEvidence    :: [FindingEvidence]
  } deriving (Eq, Show, Generic)

data TextDirection
  = TextLeftToRight
  | TextRightToLeft
  deriving (Eq, Show, Generic)

data TextWhitespace
  = TextCollapseWhitespace
  | TextPreserveWhitespace
  deriving (Eq, Show, Generic)

data TextWrapMode
  = TextNoAutomaticWrap
  | TextPreferSingleLine
      { textWrapMaximumAutomaticBreaks :: Int
      }
  deriving (Eq, Show, Generic)

-- | Half-open UTF-8 byte range in the semantic source text.
data TextSourceRange = TextSourceRange
  { textSourceRangeStart :: Int
  , textSourceRangeEnd   :: Int
  } deriving (Eq, Show, Generic)

data FontAxis = FontAxis
  { fontAxisTag   :: String
  , fontAxisValue :: Double
  } deriving (Eq, Show, Generic)

-- | Exact managed font instance used for shaping and target rendering.
data FontInstance = FontInstance
  { fontInstanceFamily     :: String
  , fontInstanceResourceId :: ResourceId
  , fontInstanceWeight     :: Int
  , fontInstanceStyle      :: String
  , fontInstanceAxes       :: [FontAxis]
  , fontInstanceFeatures   :: [String]
  } deriving (Eq, Show, Generic)

-- | One compiler-selected visual line with an explicit baseline.
data TextLine = TextLine
  { textLineSourceRange :: TextSourceRange
  , textLineDisplayText :: String
  , textLineOriginX     :: Double
  , textLineBaselineY   :: Double
  , textLineAdvance     :: Double
  , textLineInkBounds   :: LayoutRect
  } deriving (Eq, Show, Generic)

data TextLayout = TextLayout
  { textLayoutSource          :: String
  , textLayoutWhitespace      :: TextWhitespace
  , textLayoutWrapMode        :: TextWrapMode
  , textLayoutFont            :: FontInstance
  , textLayoutFontSize        :: Double
  , textLayoutPreferredSize   :: Double
  , textLayoutLineHeight      :: Double
  , textLayoutDirection       :: TextDirection
  , textLayoutScript          :: String
  , textLayoutLanguage        :: String
  , textLayoutAlignment       :: String
  , textLayoutContentBox      :: LayoutRect
  , textLayoutLines           :: [TextLine]
  , textLayoutTextRunResource :: ResourceId
  } deriving (Eq, Show, Generic)

-- | Renderer-neutral semantic roles emitted by compiler-owned highlighting.
data CodeTokenKind
  = CodeNormal
  | CodeKeyword
  | CodeType
  | CodeNumber
  | CodeString
  | CodeComment
  | CodeFunction
  | CodeVariable
  | CodeOperator
  | CodeError
  deriving (Eq, Show, Generic)

data CodeToken = CodeToken
  { codeTokenSourceRange :: TextSourceRange
  , codeTokenText        :: String
  , codeTokenKind        :: CodeTokenKind
  } deriving (Eq, Show, Generic)

type CodeHighlightLine = [CodeToken]

data VisualContent
  = PlainTextContent
      { plainTextLayout :: TextLayout
      }
  | CodeTextContent
      { codeTextLayout         :: TextLayout
      , codeTextLanguage       :: Maybe String
      , codeTextHighlightLines :: [CodeHighlightLine]
      }
  | LegacyTextContent
      { legacyTextSource :: String
      }
  deriving (Eq, Show, Generic)

-- | Concrete semantic and surface style. Geometry belongs to 'VisualBox'.
data VisualStyle = VisualStyle
  { visualOpacity     :: Maybe Double
  , visualZIndex      :: Maybe Double
  , visualFontSize    :: Maybe Double
  , visualRadius      :: Maybe Double
  , visualStrokeWidth :: Maybe Double
  , visualAlpha       :: Maybe Double
  , visualFill        :: Maybe HslColor
  , visualStroke      :: Maybe HslColor
  , visualFontFamily  :: Maybe String
  , visualFontWeight  :: Maybe String
  , visualFontStyle   :: Maybe String
  , visualTextAlign   :: Maybe String
  , visualBorderStyle :: Maybe String
  , visualWhiteSpace  :: Maybe String
  } deriving (Eq, Show, Generic)

-- TODO check if there is some unnecessary redundancy here -- if a new
-- style attribute is added, does this have to be updated too?

-- | Sparse traceback from a concrete style field to the CSP variables that
-- contributed to it. Literal-only fields do not need an entry.
data StyleVariableBinding = StyleVariableBinding
  { bindingField     :: String
  , bindingVariables :: [CspVariableId]
  } deriving (Eq, Show, Generic)

data VisualElement = VisualElement
  { elementId             :: VisualId
  , elementRole           :: String
  , elementBox            :: VisualBox
  , elementChildren       :: [VisualId]
  , elementContent        :: Maybe VisualContent
  , elementStyle          :: VisualStyle
  , elementStyleVariables :: [StyleVariableBinding]
  } deriving (Eq, Show, Generic)

data VisualInstance = VisualInstance
  { instanceId                 :: RenderInstanceId
  , instanceElementId          :: VisualId
  , instanceOriginElementId    :: Maybe VisualId
  , instanceCodeEmphasisRanges :: Maybe [TextSourceRange]
  } deriving (Eq, Show, Generic)

data TimelineStep = TimelineStep
  { stepLabel     :: String
  , stepInstances :: [VisualInstance]
  } deriving (Eq, Show, Generic)

-- | Measure from which the solver proposed this visualization.
data SamplingMode
  = BalancedChoices
  | GeometricMeasure
  | LegacyOptimizer
  deriving (Eq, Show, Generic)

-- | How completely the finite decision space was represented.
data DecisionCoverage
  = ExactEnumeration
  | MipConditioning
  | LegacyCoverage
  deriving (Eq, Show, Generic)

-- | Solver provenance needed to interpret comparisons between generated
-- visualizations without retaining solver implementation state.
data SamplingProvenance = SamplingProvenance
  { samplingMode     :: SamplingMode
  , samplingCoverage :: DecisionCoverage
  } deriving (Eq, Show, Generic)

data Visualization = Visualization
  { visualizationIrVersion   :: Int
  , visualizationSeed        :: Int
  , visualizationSourcePath  :: FilePath
  , visualizationSampling    :: Maybe SamplingProvenance
  , visualizationCoordinates :: CoordinateSystem
  , visualizationRoot        :: VisualId
  , visualizationResources   :: [ResourceDescriptor]
  , visualizationFindings    :: [VisualizationFinding]
  , visualizationVariables   :: [CspVariable]
  , visualizationElements    :: [VisualElement]
  , visualizationSteps       :: [TimelineStep]
  } deriving (Eq, Show, Generic)

$(deriveJSON irJsonOptions ''VisualId)

$(deriveJSON irJsonOptions ''RenderInstanceId)

$(deriveJSON irJsonOptions ''ResourceId)

$(deriveJSON irJsonOptions ''Sha256)

$(deriveJSON irJsonOptions ''CspVariableId)

$(deriveJSON irJsonOptions ''CspValue)

$(deriveJSON irJsonOptions ''CspVariable)

$(deriveJSON irJsonOptions ''HslColor)

$(deriveJSON irJsonOptions ''LayoutRect)

$(deriveJSON irJsonOptions ''CoordinateSystem)

$(deriveJSON irJsonOptions ''ResourceKind)

$(deriveJSON irJsonOptions ''ResourceDescriptor)

$(deriveJSON irJsonOptions ''FindingSeverity)

$(deriveJSON irJsonOptions ''FindingValue)

$(deriveJSON irJsonOptions ''FindingEvidence)

$(deriveJSON irJsonOptions ''VisualizationFinding)

$(deriveJSON irJsonOptions ''TextDirection)

$(deriveJSON irJsonOptions ''TextWhitespace)

$(deriveJSON irJsonOptions ''TextWrapMode)

$(deriveJSON irJsonOptions ''TextSourceRange)

$(deriveJSON irJsonOptions ''FontAxis)

$(deriveJSON irJsonOptions ''FontInstance)

$(deriveJSON irJsonOptions ''TextLine)

$(deriveJSON irJsonOptions ''TextLayout)

$(deriveJSON irJsonOptions ''CodeTokenKind)

$(deriveJSON irJsonOptions ''CodeToken)

$(deriveJSON irJsonOptions ''VisualContent)

$(deriveJSON irJsonOptions ''EdgeInsets)

$(deriveJSON irJsonOptions ''VisualBox)

$(deriveJSON irJsonOptions ''VisualStyle)

$(deriveJSON irJsonOptions ''StyleVariableBinding)

$(deriveJSON irJsonOptions ''VisualElement)

$(deriveJSON irJsonOptions ''VisualInstance)

$(deriveJSON irJsonOptions ''TimelineStep)

$(deriveJSON irJsonOptions ''SamplingMode)

$(deriveJSON irJsonOptions ''DecisionCoverage)

$(deriveJSON irJsonOptions ''SamplingProvenance)

$(deriveJSON irJsonOptions ''Visualization)
