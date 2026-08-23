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
  , CspVariableId(..)
  , CspValue(..)
  , CspVariable(..)
  , CanvasSpec(..)
  , HslColor(..)
  , VisualStyle(..)
  , StyleVariableBinding(..)
  , VisualElementKind(..)
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

data CanvasSpec = CanvasSpec
  { canvasWidth  :: Double
  , canvasHeight :: Double
  } deriving (Eq, Show, Generic)

data HslColor = HslColor
  { hslHue        :: Double
  , hslSaturation :: Double
  , hslLightness  :: Double
  } deriving (Eq, Show, Generic)

-- | Concrete counterpart of 'NodeStyle'. Bounds always exist; every other
-- field is present only when its required or conditional style plan resolves
-- active for this solution.
data VisualStyle = VisualStyle
  { visualTop         :: Double
  , visualLeft        :: Double
  , visualWidth       :: Double
  , visualHeight      :: Double
  , visualOpacity     :: Maybe Double
  , visualZIndex      :: Maybe Double
  , visualPadding     :: Maybe Double
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

-- | Sparse traceback from a concrete style field to the CSP variables that
-- contributed to it. Literal-only fields do not need an entry.
data StyleVariableBinding = StyleVariableBinding
  { bindingField     :: String
  , bindingVariables :: [CspVariableId]
  } deriving (Eq, Show, Generic)

data VisualElementKind
  = ElementLeaf
  | ElementGroup
      { elementGroupChildren :: [VisualId]
      }
  deriving (Eq, Show, Generic)

data VisualElement = VisualElement
  { elementId             :: VisualId
  , elementRole           :: String
  , elementKind           :: VisualElementKind
  , elementContent        :: Maybe String
  , elementStyle          :: VisualStyle
  , elementStyleVariables :: [StyleVariableBinding]
  } deriving (Eq, Show, Generic)

data VisualInstance = VisualInstance
  { instanceId              :: RenderInstanceId
  , instanceElementId       :: VisualId
  , instanceOriginElementId :: Maybe VisualId
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
  { visualizationSeed       :: Int
  , visualizationSourcePath :: FilePath
  , visualizationSampling   :: Maybe SamplingProvenance
  , visualizationCanvas     :: CanvasSpec
  , visualizationVariables  :: [CspVariable]
  , visualizationElements   :: [VisualElement]
  , visualizationSteps      :: [TimelineStep]
  } deriving (Eq, Show, Generic)

$(deriveJSON irJsonOptions ''VisualId)

$(deriveJSON irJsonOptions ''RenderInstanceId)

$(deriveJSON irJsonOptions ''CspVariableId)

$(deriveJSON irJsonOptions ''CspValue)

$(deriveJSON irJsonOptions ''CspVariable)

$(deriveJSON irJsonOptions ''HslColor)

$(deriveJSON irJsonOptions ''CanvasSpec)

$(deriveJSON irJsonOptions ''VisualStyle)

$(deriveJSON irJsonOptions ''StyleVariableBinding)

$(deriveJSON irJsonOptions ''VisualElementKind)

$(deriveJSON irJsonOptions ''VisualElement)

$(deriveJSON irJsonOptions ''VisualInstance)

$(deriveJSON irJsonOptions ''TimelineStep)

$(deriveJSON irJsonOptions ''SamplingMode)

$(deriveJSON irJsonOptions ''DecisionCoverage)

$(deriveJSON irJsonOptions ''SamplingProvenance)

$(deriveJSON irJsonOptions ''Visualization)
