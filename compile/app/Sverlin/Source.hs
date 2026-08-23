-- | The deliberately small source-to-Haskell boundary for the evolving
-- Sverlin language. Version zero is a body-only Haskell authoring profile.
module Sverlin.Source
  ( SourceUnit(..)
  , GeneratedSource(..)
  , elaborateSource
  ) where

data SourceUnit = SourceUnit
  { sourceDisplayPath :: FilePath
  , sourceBody        :: String
  }

data GeneratedSource = GeneratedSource
  { generatedModuleName :: String
  , generatedModuleText :: String
  }

elaborateSource :: SourceUnit -> GeneratedSource
elaborateSource source =
  GeneratedSource
    { generatedModuleName = "Sverlin.Generated"
    , generatedModuleText =
        unlines fixedHeader
          ++ linePragma 1 (sourceDisplayPath source)
          ++ ensureTrailingNewline (sourceBody source)
          ++ linePragma 1 "<sverlin-generated-footer>"
          ++ unlines generatedFooter
    }

fixedHeader :: [String]
fixedHeader =
  [ "{-# LANGUAGE ConstraintKinds #-}"
  , "{-# LANGUAGE DataKinds #-}"
  , "{-# LANGUAGE FlexibleContexts #-}"
  , "{-# LANGUAGE FlexibleInstances #-}"
  , "{-# LANGUAGE GADTs #-}"
  , "{-# LANGUAGE LinearTypes #-}"
  , "{-# LANGUAGE NoImplicitPrelude #-}"
  , "{-# LANGUAGE OverloadedLabels #-}"
  , "{-# LANGUAGE OverloadedStrings #-}"
  , "{-# LANGUAGE RebindableSyntax #-}"
  , "{-# LANGUAGE TypeApplications #-}"
  , "{-# LANGUAGE TypeFamilies #-}"
  , "{-# LANGUAGE UndecidableInstances #-}"
  , "{-# LANGUAGE UndecidableSuperClasses #-}"
  , ""
  , "module Sverlin.Generated (_sverlinResult) where"
  , ""
  , "import Control.Functor.Linear hiding (ask, (<$>), (<&>), (<*>))"
  , "import LinearTrace.Choreography"
  , "import Prelude.Linear hiding (fromInteger, fromRational, (*), (+), (-), (/), (/=), (<>), (==))"
  , "import qualified Prelude.Linear as Linear"
  , ""
  , "_sverlinSourceBoundary :: ()"
  , "_sverlinSourceBoundary = ()"
  , ""
  ]

generatedFooter :: [String]
generatedFooter =
  [ "_sverlinResult :: VisualTraceGraph"
  , "_sverlinResult ="
  , "  runChoreographyWithGenerativeStyles (visualize visualization) program"
  ]

linePragma :: Int -> FilePath -> String
linePragma line path = "{-# LINE " ++ show line ++ " " ++ show path ++ " #-}\n"

ensureTrailingNewline :: String -> String
ensureTrailingNewline body =
  case reverse body of
    '\n':_ -> body
    _      -> body ++ "\n"
