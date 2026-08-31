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
  , "{-# LANGUAGE MultiParamTypeClasses #-}"
  , "{-# LANGUAGE NoImplicitPrelude #-}"
  , "{-# LANGUAGE OverloadedStrings #-}"
  , "{-# LANGUAGE RebindableSyntax #-}"
  , "{-# LANGUAGE ScopedTypeVariables #-}"
  , "{-# LANGUAGE TypeApplications #-}"
  , "{-# LANGUAGE TypeFamilies #-}"
  , "{-# LANGUAGE TypeFamilyDependencies #-}"
  , "{-# LANGUAGE TypeOperators #-}"
  , "{-# LANGUAGE UndecidableInstances #-}"
  , "{-# LANGUAGE UndecidableSuperClasses #-}"
  , ""
  , "module Sverlin.Generated (_sverlinResult) where"
  , ""
  , "import Prelude hiding (fail, pure, return, ($), (>>), (>>=))"
  , "import Data.String (fromString)"
  , "import Prelude.Linear (($))"
  , "import Sverlin"
  , "import Sverlin.Compiler (SverlinProgram)"
  , "import qualified Sverlin.Compiler as Compiler (sverlinProgram)"
  , "import qualified Sverlin.Linear as Linear"
  , ""
  , "_sverlinSourceBoundary :: ()"
  , "_sverlinSourceBoundary = ()"
  , ""
  , "ifThenElse :: Bool -> value -> value -> value"
  , "ifThenElse True yes _ = yes"
  , "ifThenElse False _ no = no"
  , ""
  ]

generatedFooter :: [String]
generatedFooter =
  [ "_sverlinResult :: SverlinProgram"
  , "_sverlinResult ="
  , "  Compiler.sverlinProgram domain program render"
  ]

linePragma :: Int -> FilePath -> String
linePragma line path = "{-# LINE " ++ show line ++ " " ++ show path ++ " #-}\n"

ensureTrailingNewline :: String -> String
ensureTrailingNewline body =
  case reverse body of
    '\n':_ -> body
    _      -> body ++ "\n"
