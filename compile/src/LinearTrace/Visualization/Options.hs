{-# LANGUAGE OverloadedStrings #-}

-- | Shared JSON naming and sum-encoding options for the visualization IR.
module LinearTrace.Visualization.Options
  ( irJsonOptions
  , jsonConstructorName
  , jsonFieldName
  ) where

import           Data.Aeson
import           Data.Char  (isAsciiUpper)
import           Data.List  (stripPrefix)
import           Data.Maybe (listToMaybe, mapMaybe)
import           Prelude

irJsonOptions :: Options
irJsonOptions =
  defaultOptions
    { fieldLabelModifier = jsonFieldName
    , constructorTagModifier = jsonConstructorName
    , sumEncoding = TaggedObject "kind" "contents"
    , omitNothingFields = True
    , unwrapUnaryRecords = True
    }

-- | Record fields are prefixed with their record name in Haskell. Removing the
-- first camel-case word gives the wire name without maintaining a second field
-- map beside the IR.
jsonFieldName :: String -> String
jsonFieldName name =
  case lookup name exceptions of
    Just wireName -> wireName
    Nothing ->
      case dropWhile (not . isAsciiUpper) name of
        []     -> name
        suffix -> lowerFirst suffix
  where
    exceptions =
      [ ("cspNumberValue", "value")
      , ("cspCategoryValue", "value")
      , ("cspVariableId", "id")
      , ("cspVariableValue", "value")
      , ("elementGroupChildren", "children")
      ]

jsonConstructorName :: String -> String
jsonConstructorName name =
  lowerFirst . maybe name id . listToMaybe . mapMaybe (`stripPrefix` name)
    $ ["Variable", "Csp", "Element"]

lowerFirst :: String -> String
lowerFirst text =
  case text of
    []         -> []
    first:rest -> toLowerAscii first : rest

toLowerAscii :: Char -> Char
toLowerAscii char =
  if isAsciiUpper char
    then toEnum (fromEnum char + (fromEnum 'a' - fromEnum 'A'))
    else char
