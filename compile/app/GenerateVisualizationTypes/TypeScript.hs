module GenerateVisualizationTypes.TypeScript
  ( generateDeclarations
  ) where

import           Control.Monad
import           Data.List                         (intercalate, isInfixOf)
import           Data.Set                          (Set)
import qualified Data.Set                          as Set
import           Language.Haskell.TH
import           Language.Haskell.TH.Syntax        (lift)
import           LinearTrace.Visualization.Options (jsonConstructorName,
                                                    jsonFieldName)
import           Prelude

generateDeclarations :: Name -> Q Exp
generateDeclarations root = do
  namesSet <- collectTypes Set.empty root
  let names = Set.toList namesSet
  declarations <- traverse generateDeclaration names
  lift
    ([ "// THIS FILE IS GENERATED. Run: pnpm run generate:visualization-types"
     , ""
     ]
       ++ concat declarations)

collectTypes :: Set Name -> Name -> Q (Set Name)
collectTypes seen name
  | isBuiltin name || Set.member name seen = pure seen
  | otherwise = do
    info <- reify name
    let seen' = Set.insert name seen
    dependencies <- declarationTypes info
    foldM collectTypes seen' dependencies

declarationTypes :: Info -> Q [Name]
declarationTypes info =
  case info of
    TyConI (DataD _ _ _ _ constructors _) ->
      pure (concatMap constructorTypes constructors)
    TyConI (NewtypeD _ _ _ _ constructor _) ->
      pure (constructorTypes constructor)
    _ -> pure []

constructorTypes :: Con -> [Name]
constructorTypes constructor =
  case constructor of
    NormalC _ fields    -> concatMap (typeNames . snd) fields
    RecC _ fields       -> concatMap (typeNames . snd3) fields
    InfixC left _ right -> typeNames (snd left) ++ typeNames (snd right)
    ForallC _ _ nested  -> constructorTypes nested
    GadtC _ fields _    -> concatMap (typeNames . snd) fields
    RecGadtC _ fields _ -> concatMap (typeNames . snd3) fields
  where
    snd3 (_, _, value) = value

typeNames :: Type -> [Name]
typeNames type' =
  case type' of
    AppT left right      -> typeNames left ++ typeNames right
    SigT nested _        -> typeNames nested
    ParensT nested       -> typeNames nested
    InfixT left _ right  -> typeNames left ++ typeNames right
    UInfixT left _ right -> typeNames left ++ typeNames right
    ForallT _ _ nested   -> typeNames nested
    ConT name            -> [name | not (isBuiltin name)]
    _                    -> []

isBuiltin :: Name -> Bool
isBuiltin name =
  nameBase name
    `elem` [ "Bool"
           , "Char"
           , "Double"
           , "Float"
           , "Int"
           , "Integer"
           , "String"
           , "FilePath"
           , "Maybe"
           , "[]"
           , "List"
           ]

generateDeclaration :: Name -> Q [String]
generateDeclaration name = do
  info <- reify name
  pure (declarationText (nameBase name) info ++ [""])

declarationText :: String -> Info -> [String]
declarationText typeName info =
  case info of
    TyConI (NewtypeD _ _ _ _ (NormalC _ [(_, nested)]) _) ->
      ["export type " ++ typeName ++ " = " ++ tsType nested ++ ";"]
    TyConI (DataD _ _ _ _ constructors _) ->
      dataDeclaration typeName constructors
    TyConI (NewtypeD _ _ _ _ (RecC _ fields) _) ->
      interfaceDeclaration typeName fields
    _ -> []

dataDeclaration :: String -> [Con] -> [String]
dataDeclaration typeName constructors =
  case constructors of
    [RecC constructorName fields]
      | nameBase constructorName == typeName ->
        interfaceDeclaration typeName fields
      | otherwise ->
        [ "export type " ++ typeName ++ " ="
        , "  | " ++ constructorType (RecC constructorName fields)
        , ";"
        ]
    [NormalC constructorName []] ->
      [ "export type "
          ++ typeName
          ++ " = '"
          ++ jsonConstructorName (nameBase constructorName)
          ++ "';"
      ]
    _
      | all isNullaryConstructor constructors ->
        [ "export type "
            ++ typeName
            ++ " = "
            ++ intercalate
                 " | "
                 [ "'" ++ jsonConstructorName (nameBase name) ++ "'"
                 | NormalC name [] <- constructors
                 ]
            ++ ";"
        ]
    _ ->
      ["export type " ++ typeName ++ " ="]
        ++ intercalateLines "  | " (map constructorType constructors)
        ++ [";"]

interfaceDeclaration :: String -> [VarBangType] -> [String]
interfaceDeclaration typeName fields =
  ["export interface " ++ typeName ++ " {"]
    ++ map (("  " ++) . (\field -> fieldDeclaration field ++ ";")) fields
    ++ ["}"]

constructorType :: Con -> String
constructorType constructor =
  case constructor of
    NormalC name [] -> "{ kind: '" ++ jsonConstructorName (nameBase name) ++ "' }"
    RecC name fields -> objectType (jsonConstructorName (nameBase name)) fields
    NormalC name fields ->
      objectType
        (jsonConstructorName (nameBase name))
        (zipWith
           (\index (bang', type') ->
              (mkName ("contents" ++ show index), bang', type'))
           [0 :: Int ..]
           fields)
    ForallC _ _ nested -> constructorType nested
    InfixC {} -> "Record<string, never>"
    GadtC (name:_) fields _ ->
      objectType
        (jsonConstructorName (nameBase name))
        (zipWith
           (\index (bang', type') ->
              (mkName ("contents" ++ show index), bang', type'))
           [0 :: Int ..]
           fields)
    GadtC [] _ _ -> "Record<string, never>"
    RecGadtC (name:_) fields _ ->
      objectType (jsonConstructorName (nameBase name)) fields
    RecGadtC [] _ _ -> "Record<string, never>"

objectType :: String -> [VarBangType] -> String
objectType tag fields = "{ kind: '" ++ tag ++ "'" ++ fieldsText fields ++ " }"

fieldsText :: [VarBangType] -> String
fieldsText []     = ""
fieldsText fields = "; " ++ intercalate "; " (map fieldDeclaration fields)

fieldDeclaration :: VarBangType -> String
fieldDeclaration (name, _, type') =
  jsonFieldName (nameBase name)
    ++ (if isMaybe type'
          then "?"
          else "")
    ++ ": "
    ++ tsType (unwrapMaybe type')

isMaybe :: Type -> Bool
isMaybe type' =
  case type' of
    AppT (ConT name) _ -> nameBase name == "Maybe"
    _                  -> False

unwrapMaybe :: Type -> Type
unwrapMaybe type' =
  case type' of
    AppT (ConT name) nested
      | nameBase name == "Maybe" -> nested
    _ -> type'

tsType :: Type -> String
tsType type' =
  case type' of
    AppT (ConT name) nested
      | nameBase name `elem` ["[]", "List"] -> tsType nested ++ "[]"
      | nameBase name == "Maybe" -> tsType nested
    ConT name
      | nameBase name `elem` ["String", "FilePath"] -> "string"
      | nameBase name == "Bool" -> "boolean"
      | nameBase name `elem` ["Double", "Float", "Int", "Integer"] -> "number"
      | otherwise -> nameBase name
    AppT left right
      | isListConstructor left -> tsType right ++ "[]"
      | otherwise -> tsType left ++ "<" ++ tsType right ++ ">"
    SigT nested _ -> tsType nested
    ParensT nested -> tsType nested
    _ -> "unknown"

typeConstructorName :: Type -> String
typeConstructorName type' =
  case type' of
    ConT name      -> nameBase name
    AppT nested _  -> typeConstructorName nested
    SigT nested _  -> typeConstructorName nested
    ParensT nested -> typeConstructorName nested
    _              -> ""

isListConstructor :: Type -> Bool
isListConstructor type' =
  typeConstructorName type' `elem` ["[]", "List"]
    || "[]" `isInfixOf` pprint type'

intercalateLines :: String -> [String] -> [String]
intercalateLines _ [] = []
intercalateLines separator (first:rest) =
  (separator ++ first) : map (separator ++) rest

isNullaryConstructor :: Con -> Bool
isNullaryConstructor constructor =
  case constructor of
    NormalC _ [] -> True
    _            -> False
