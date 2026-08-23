{-# LANGUAGE OverloadedStrings #-}

-- | Output-target boundary for solved visualization packages.
--
-- Targets are pure transformations. Filesystem/process execution belongs to
-- the compile executable so future LaTeX/PDF targets can share this contract
-- without acquiring hidden randomness or ambient resource lookup.
module LinearTrace.Visualization.Target
  ( OutputTarget(..)
  , TargetRequest(..)
  , defaultTargetRequest
  , TargetDiagnosticSeverity(..)
  , TargetDiagnostic(..)
  , TargetArtifact(..)
  , TargetBundle(..)
  , TargetError(..)
  , outputTargetName
  , parseOutputTarget
  , compileTarget
  , targetManifestFor
  ) where

import           Data.Aeson                         (Value, object, (.=))
import           Data.Aeson.Encode.Pretty           (encodePretty)
import qualified Data.ByteString                    as BS
import qualified Data.ByteString.Lazy               as BL
import qualified LinearTrace.Visualization.IR       as IR
import qualified LinearTrace.Visualization.Resource as Resource
import           Prelude
import           System.FilePath                    (takeFileName, (</>))

data OutputTarget =
  IrJson
  deriving (Eq, Show)

newtype TargetRequest = TargetRequest
  { targetRequestOutputTarget :: OutputTarget
  } deriving (Eq, Show)

defaultTargetRequest :: OutputTarget -> TargetRequest
defaultTargetRequest = TargetRequest

data TargetDiagnosticSeverity
  = TargetDiagnosticInfo
  | TargetDiagnosticWarning
  deriving (Eq, Show)

data TargetDiagnostic = TargetDiagnostic
  { targetDiagnosticSeverity :: TargetDiagnosticSeverity
  , targetDiagnosticCode     :: String
  , targetDiagnosticMessage  :: String
  } deriving (Eq, Show)

data TargetArtifact = TargetArtifact
  { targetArtifactRelativePath :: FilePath
  , targetArtifactMediaType    :: String
  , targetArtifactSha256       :: IR.Sha256
  , targetArtifactBytes        :: BS.ByteString
  } deriving (Eq, Show)

data TargetBundle = TargetBundle
  { targetBundlePrimary     :: TargetArtifact
  , targetBundleAttachments :: [TargetArtifact]
  , targetBundleDiagnostics :: [TargetDiagnostic]
  , targetBundleProvenance  :: Resource.CompilationProvenance
  } deriving (Eq, Show)

newtype TargetError =
  TargetError String
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

compileTarget ::
     TargetRequest
  -> Resource.CompilationPackage
  -> Either TargetError TargetBundle
compileTarget request package =
  case targetRequestOutputTarget request of
    IrJson -> compileIrJson package

compileIrJson :: Resource.CompilationPackage -> Either TargetError TargetBundle
compileIrJson package =
  case Resource.compilationPackageVisualizations package of
    [] -> Left (TargetError "a compilation package has no visualizations")
    visualizations ->
      let encoded =
            BL.toStrict
              (case visualizations of
                 [visualization] -> encodePretty visualization
                 _               -> encodePretty visualizations)
          primary = artifact "visualization.json" "application/json" encoded
          attachments =
            map resourceArtifact (Resource.compilationPackageResources package)
       in Right
            TargetBundle
              { targetBundlePrimary = primary
              , targetBundleAttachments = attachments
              , targetBundleDiagnostics = []
              , targetBundleProvenance =
                  Resource.compilationPackageProvenance package
              }

resourceArtifact :: Resource.ResourceBlob -> TargetArtifact
resourceArtifact blob =
  let descriptor = Resource.resourceBlobDescriptor blob
      IR.ResourceId identifier = IR.resourceDescriptorId descriptor
   in TargetArtifact
        { targetArtifactRelativePath = "resources" </> identifier
        , targetArtifactMediaType = IR.resourceDescriptorMediaType descriptor
        , targetArtifactSha256 = IR.resourceDescriptorSha256 descriptor
        , targetArtifactBytes = Resource.resourceBlobBytes blob
        }

artifact :: FilePath -> String -> BS.ByteString -> TargetArtifact
artifact relativePath mediaType bytes =
  TargetArtifact
    { targetArtifactRelativePath = relativePath
    , targetArtifactMediaType = mediaType
    , targetArtifactSha256 = Resource.sha256Bytes bytes
    , targetArtifactBytes = bytes
    }

-- | Encode a manifest using the actual caller-selected primary filename.
targetManifestFor :: FilePath -> TargetBundle -> BL.ByteString
targetManifestFor primaryPath bundle =
  encodePretty
    (object
       [ "manifestVersion" .= (1 :: Int)
       , "primary"
           .= artifactManifest
                (takeFileName primaryPath)
                (targetBundlePrimary bundle)
       , "attachments"
           .= map
                (\attachment ->
                   artifactManifest
                     (targetArtifactRelativePath attachment)
                     attachment)
                (targetBundleAttachments bundle)
       , "diagnostics"
           .= map diagnosticManifest (targetBundleDiagnostics bundle)
       , "provenance" .= provenanceManifest (targetBundleProvenance bundle)
       ])

provenanceManifest :: Resource.CompilationProvenance -> Value
provenanceManifest provenance =
  object
    [ "packageVersion"
        .= Resource.compilationProvenancePackageVersion provenance
    , "textRunFormatVersion"
        .= Resource.compilationProvenanceTextRunFormatVersion provenance
    , "shapingEngine" .= Resource.compilationProvenanceShapingEngine provenance
    , "shapingEngineVersion"
        .= Resource.compilationProvenanceShapingEngineVersion provenance
    , "fontCatalogSha256"
        .= fmap
             shaValue
             (Resource.compilationProvenanceFontCatalogSha256 provenance)
    ]

diagnosticManifest :: TargetDiagnostic -> Value
diagnosticManifest diagnostic =
  object
    [ "severity" .= severityName (targetDiagnosticSeverity diagnostic)
    , "code" .= targetDiagnosticCode diagnostic
    , "message" .= targetDiagnosticMessage diagnostic
    ]
  where
    severityName severity =
      case severity of
        TargetDiagnosticInfo    -> "info" :: String
        TargetDiagnosticWarning -> "warning"

artifactManifest :: FilePath -> TargetArtifact -> Value
artifactManifest relativePath artifact' =
  object
    [ "relativePath" .= relativePath
    , "mediaType" .= targetArtifactMediaType artifact'
    , "sha256" .= shaValue (targetArtifactSha256 artifact')
    , "byteLength" .= BS.length (targetArtifactBytes artifact')
    ]

shaValue :: IR.Sha256 -> String
shaValue (IR.Sha256 value) = value
