-- | Content-addressed resources carried beside solved visualization IR.
module LinearTrace.Visualization.Resource
  ( ResourceBlob(..)
  , CompilationProvenance(..)
  , CompilationPackage(..)
  , emptyCompilationPackage
  , resourceBlob
  , deduplicateResourceBlobs
  , sha256Bytes
  ) where

import qualified Crypto.Hash.SHA256           as SHA256
import qualified Data.ByteString              as BS
import           Data.Char                    (toLower)
import           Data.List                    (intercalate)
import qualified Data.Map.Strict              as Map
import qualified LinearTrace.Visualization.IR as IR
import           Numeric                      (showHex)
import           Prelude

-- | Bytes whose public descriptor is embedded in the visualization IR.
data ResourceBlob = ResourceBlob
  { resourceBlobDescriptor :: IR.ResourceDescriptor
  , resourceBlobBytes      :: BS.ByteString
  } deriving (Eq, Show)

-- | Toolchain details needed to interpret deterministic text layout.
data CompilationProvenance = CompilationProvenance
  { compilationProvenancePackageVersion       :: Int
  , compilationProvenanceTextRunFormatVersion :: Int
  , compilationProvenanceShapingEngine        :: String
  , compilationProvenanceShapingEngineVersion :: String
  , compilationProvenanceFontCatalogSha256    :: Maybe IR.Sha256
  } deriving (Eq, Show)

-- | Solved IR plus every byte resource required by output targets.
data CompilationPackage = CompilationPackage
  { compilationPackageVisualizations :: [IR.Visualization]
  , compilationPackageResources      :: [ResourceBlob]
  , compilationPackageProvenance     :: CompilationProvenance
  } deriving (Eq, Show)

emptyCompilationPackage :: [IR.Visualization] -> CompilationPackage
emptyCompilationPackage visualizations =
  CompilationPackage
    { compilationPackageVisualizations = visualizations
    , compilationPackageResources = []
    , compilationPackageProvenance =
        CompilationProvenance
          { compilationProvenancePackageVersion = 1
          , compilationProvenanceTextRunFormatVersion = 2
          , compilationProvenanceShapingEngine = "none"
          , compilationProvenanceShapingEngineVersion = "none"
          , compilationProvenanceFontCatalogSha256 = Nothing
          }
    }

resourceBlob :: IR.ResourceKind -> String -> BS.ByteString -> ResourceBlob
resourceBlob kind mediaType bytes =
  let digest = sha256Bytes bytes
      identifier =
        case digest of
          IR.Sha256 value -> IR.ResourceId ("sha256-" ++ value)
   in ResourceBlob
        { resourceBlobDescriptor =
            IR.ResourceDescriptor
              { IR.resourceDescriptorId = identifier
              , IR.resourceDescriptorKind = kind
              , IR.resourceDescriptorSha256 = digest
              , IR.resourceDescriptorMediaType = mediaType
              , IR.resourceDescriptorByteLength = BS.length bytes
              }
        , resourceBlobBytes = bytes
        }

deduplicateResourceBlobs :: [ResourceBlob] -> [ResourceBlob]
deduplicateResourceBlobs = Map.elems . Map.fromList . map keyed
  where
    keyed resource =
      (IR.resourceDescriptorId (resourceBlobDescriptor resource), resource)

sha256Bytes :: BS.ByteString -> IR.Sha256
sha256Bytes = IR.Sha256 . bytesToHex . SHA256.hash

bytesToHex :: BS.ByteString -> String
bytesToHex = intercalate "" . map byteHex . BS.unpack
  where
    byteHex byte =
      case map toLower (showHex byte "") of
        [digit] -> ['0', digit]
        digits  -> digits
