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
  , SourceMetadata(..)
  , CanvasSpec(..)
  , HslColor(..)
  , VisualStyle(..)
  , StyleVariableTrace(..)
  , VisualElementKind(..)
  , VisualElement(..)
  , InstanceOrigin(..)
  , VisualInstance(..)
  , VisualizationFrame(..)
  , VisualizationPackage(..)
  , irJsonOptions
  ) where

import           Data.Aeson.TH
import           GHC.Generics                      (Generic)
import           LinearTrace.Visualization.Options (irJsonOptions)
import           Prelude

newtype VisualId = VisualId String
  deriving (Eq, Ord, Show, Generic)

newtype RenderInstanceId = RenderInstanceId String
  deriving (Eq, Ord, Show, Generic)

newtype CspVariableId = CspVariableId String
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
  { cspVariableId     :: CspVariableId
  , cspVariableValue  :: CspValue
  } deriving (Eq, Show, Generic)

data SourceMetadata = SourceMetadata
  { sourcePath            :: FilePath
  , sourceCompilerVersion :: String
  } deriving (Eq, Show, Generic)

data CanvasSpec = CanvasSpec
  { canvasWidth      :: Double
  , canvasHeight     :: Double
  , canvasBackground :: Maybe HslColor
  } deriving (Eq, Show, Generic)

data HslColor = HslColor
  { hslHue        :: Double
  , hslSaturation :: Double
  , hslLightness  :: Double
  } deriving (Eq, Show, Generic)

-- | Concrete counterpart of 'NodeStyle'. Optionality mirrors the DSL: bounds
-- always exist, while every other field is present only when authored.
data VisualStyle = VisualStyle
  { visualTop          :: Double
  , visualLeft         :: Double
  , visualWidth        :: Double
  , visualHeight       :: Double
  , visualOpacity      :: Maybe Double
  , visualZIndex       :: Maybe Double
  , visualPadding      :: Maybe Double
  , visualFontSize     :: Maybe Double
  , visualRadius       :: Maybe Double
  , visualStrokeWidth  :: Maybe Double
  , visualAlpha        :: Maybe Double
  , visualFill         :: Maybe HslColor
  , visualStroke       :: Maybe HslColor
  , visualFontFamily   :: Maybe String
  , visualFontWeight   :: Maybe String
  , visualFontStyle    :: Maybe String
  , visualTextAlign    :: Maybe String
  , visualBorderStyle  :: Maybe String
  , visualWhiteSpace   :: Maybe String
  } deriving (Eq, Show, Generic)

-- | CSP variables that contributed to each concrete style value. Keeping this
-- parallel to 'VisualStyle' makes traceback explicit without wrapping every
-- value in metadata-heavy objects.
data StyleVariableTrace = StyleVariableTrace
  { traceTop          :: [CspVariableId]
  , traceLeft         :: [CspVariableId]
  , traceWidth        :: [CspVariableId]
  , traceHeight       :: [CspVariableId]
  , traceOpacity      :: [CspVariableId]
  , traceZIndex       :: [CspVariableId]
  , tracePadding      :: [CspVariableId]
  , traceFontSize     :: [CspVariableId]
  , traceRadius       :: [CspVariableId]
  , traceStrokeWidth  :: [CspVariableId]
  , traceAlpha        :: [CspVariableId]
  , traceFill         :: [CspVariableId]
  , traceStroke       :: [CspVariableId]
  , traceFontFamily   :: [CspVariableId]
  , traceFontWeight   :: [CspVariableId]
  , traceFontStyle    :: [CspVariableId]
  , traceTextAlign    :: [CspVariableId]
  , traceBorderStyle  :: [CspVariableId]
  , traceWhiteSpace   :: [CspVariableId]
  } deriving (Eq, Show, Generic)

data VisualElementKind
  = ElementTrace
  | ElementGroup
      { elementGroupChildren :: [VisualId]
      }
  deriving (Eq, Show, Generic)

data VisualElement = VisualElement
  { elementId        :: VisualId
  , elementNodeId    :: Int
  , elementNodeKey   :: String
  , elementRole      :: String
  , elementKind      :: VisualElementKind
  , elementContent   :: Maybe String
  , elementStyle     :: VisualStyle
  , elementVariables :: StyleVariableTrace
  } deriving (Eq, Show, Generic)

data InstanceOrigin = InstanceOrigin
  { originInstanceId :: RenderInstanceId
  , originElementId  :: VisualId
  } deriving (Eq, Show, Generic)

data VisualInstance = VisualInstance
  { instanceId        :: RenderInstanceId
  , instanceElementId :: VisualId
  , instanceOrigin    :: Maybe InstanceOrigin
  } deriving (Eq, Show, Generic)

-- | A complete scene snapshot. Elements live once in the package registry, so
-- frames remain small and directly seekable without replaying a patch history.
data VisualizationFrame = VisualizationFrame
  { frameDurationMs :: Int
  , frameInstances  :: [VisualInstance]
  } deriving (Eq, Show, Generic)

data VisualizationPackage = VisualizationPackage
  { packageSchemaVersion :: Int
  , packageSeed          :: Int
  , packageSource        :: SourceMetadata
  , packageCanvas        :: CanvasSpec
  , packageVariables     :: [CspVariable]
  , packageElements      :: [VisualElement]
  , packageFrames        :: [VisualizationFrame]
  } deriving (Eq, Show, Generic)

$(deriveJSON irJsonOptions ''VisualId)
$(deriveJSON irJsonOptions ''RenderInstanceId)
$(deriveJSON irJsonOptions ''CspVariableId)
$(deriveJSON irJsonOptions ''CspValue)
$(deriveJSON irJsonOptions ''CspVariable)
$(deriveJSON irJsonOptions ''SourceMetadata)
$(deriveJSON irJsonOptions ''HslColor)
$(deriveJSON irJsonOptions ''CanvasSpec)
$(deriveJSON irJsonOptions ''VisualStyle)
$(deriveJSON irJsonOptions ''StyleVariableTrace)
$(deriveJSON irJsonOptions ''VisualElementKind)
$(deriveJSON irJsonOptions ''VisualElement)
$(deriveJSON irJsonOptions ''InstanceOrigin)
$(deriveJSON irJsonOptions ''VisualInstance)
$(deriveJSON irJsonOptions ''VisualizationFrame)
$(deriveJSON irJsonOptions ''VisualizationPackage)
