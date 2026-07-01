{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Query and payload-pattern implementation for choreography. The public DSL
-- re-exports the safe query vocabulary; 'LinearTrace.Choreography.Match' uses
-- this module to match core event blocks and generated view groups.
module LinearTrace.Choreography.Query
  ( -- * Query terms
    -- | Fact/tag query representation and constructors. Choreography users see
    -- these through the DSL facade and overloaded labels.
    Query(..)
  , QueryTerm(..)
  , QueryValue(..)
  , QueryInt(..)
  , QueryBindings
  , emptyQuery
  , queryAtom
  , queryInt
  , queryAppend
  , queryKey
  , queryFacts
  , queryMatches
  , queryMatchesTags
  , queryIntConst
  , queryIntVar
  , queryIntAdd
  , queryBindingValue
  , bindQueryInt
  , -- * Match bindings
    -- | Variable bindings produced by query matching. Match rules consume
    -- these to build node patches and selection endpoints.
    MatchBinding(..)
  , MatchBindings
  , MatchContext(..)
  , matchBinding
  , matchBindingValue
  , queryMatchBindings
  , -- * Payload patterns
    -- | Type-directed payload filters used by match rules to refine core event
    -- blocks before view nodes are produced.
    PayloadPattern
  , payloadPatternMatches
  , anyPayloadPattern
  , payloadBindingPattern
  , payloadBoolPattern
  , payloadIntPattern
  , payloadDoublePattern
  , payloadStringPattern
  , payloadUnitPattern
  , -- * Key helpers
    -- | Stable names and keys shared by query matching and view node identity.
    labelName
  , safeKey
  ) where

import           Data.Proxy             (Proxy (..))
import           Data.Type.Equality     (type (~))
import           GHC.OverloadedLabels   (IsLabel (..))
import           GHC.TypeLits           (KnownSymbol, symbolVal)
import qualified LinearTrace.Core       as C
import qualified LinearTrace.View.Types as V
import           Prelude                (Bool (..), Maybe (..), otherwise)
import qualified Prelude                as P

data QueryInt
  = QueryIntConst P.Int
  | QueryIntVar P.String
  | QueryIntAdd QueryInt P.Int
  deriving (P.Eq, P.Ord, P.Show)

data QueryValue
  = QueryAtom
  | QueryIntValue QueryInt
  deriving (P.Eq, P.Ord, P.Show)

data QueryTerm =
  QueryTerm P.String QueryValue
  deriving (P.Eq, P.Ord, P.Show)

newtype Query =
  Query [QueryTerm]
  deriving (P.Eq, P.Ord, P.Show)

type QueryBindings = [(P.String, P.Int)]

emptyQuery :: Query
emptyQuery = Query []

queryAtom :: P.String -> Query
queryAtom name = Query [QueryTerm name QueryAtom]

queryInt :: P.String -> QueryInt -> Query
queryInt name value = Query [QueryTerm name (QueryIntValue value)]

queryIntConst :: P.Int -> QueryInt
queryIntConst = QueryIntConst

queryIntVar :: P.String -> QueryInt
queryIntVar = QueryIntVar

queryIntAdd :: QueryInt -> P.Int -> QueryInt
queryIntAdd = QueryIntAdd

queryAppend :: Query -> Query -> Query
queryAppend lhs rhs =
  case lhs of
    Query leftTerms ->
      case rhs of
        Query rightTerms -> Query (canonicalTerms (leftTerms P.++ rightTerms))

labelName :: KnownSymbol name => Proxy name -> P.String
labelName proxy = dotName (symbolVal proxy)

dotName :: P.String -> P.String
dotName name =
  case name of
    []        -> []
    char:rest -> dotChar char : dotName rest

dotChar :: P.Char -> P.Char
dotChar char =
  case char P.== '_' of
    P.True  -> '.'
    P.False -> char

instance KnownSymbol name => IsLabel name Query where
  fromLabel = queryAtom (labelName (Proxy @name))

instance KnownSymbol name => IsLabel name (P.Int -> Query) where
  fromLabel value = queryInt (labelName (Proxy @name)) (queryIntConst value)

instance KnownSymbol name => IsLabel name (QueryInt -> Query) where
  fromLabel = queryInt (labelName (Proxy @name))

queryKey :: Query -> P.String
queryKey query =
  case query of
    Query terms -> joinPath ("q" : P.map queryTermKey (canonicalTerms terms))

queryFacts :: Query -> C.Facts
queryFacts query =
  case query of
    Query terms -> C.Facts (P.map queryTermToFact (canonicalTerms terms))

queryTermKey :: QueryTerm -> P.String
queryTermKey term =
  case term of
    QueryTerm name value ->
      case value of
        QueryAtom             -> safeKey name
        QueryIntValue intTerm -> safeKey name P.++ "-" P.++ queryIntKey intTerm

queryIntKey :: QueryInt -> P.String
queryIntKey intPattern =
  case intPattern of
    QueryIntConst value     -> P.show value
    QueryIntVar name        -> "$" P.++ safeKey name
    QueryIntAdd base offset -> queryIntKey base P.++ "+" P.++ P.show offset

queryMatches :: Query -> C.Facts -> Maybe QueryBindings
queryMatches query facts =
  case query of
    Query terms -> matchQueryTerms (canonicalTerms terms) facts []

queryMatchesTags :: Query -> V.ViewTags -> Maybe QueryBindings
queryMatchesTags query tags = queryMatches query (viewTagsFacts tags)

queryBindingValue :: QueryBindings -> P.Int -> P.Int
queryBindingValue bindings fallback =
  case bindings of
    []               -> fallback
    (_name, value):_ -> value

data MatchBinding =
  MatchBinding P.String P.String
  deriving (P.Eq, P.Show)

type MatchBindings = [MatchBinding]

data MatchContext tag = MatchContext
  { matchContextIndex    :: P.Int
  , matchContextPayload  :: C.Payload tag
  , matchContextLabel    :: C.PayloadView
  , matchContextBindings :: MatchBindings
  }

matchBinding :: P.String -> P.String -> MatchBinding
matchBinding = MatchBinding

matchBindingValue :: P.String -> MatchBindings -> Maybe P.String
matchBindingValue name bindings =
  case bindings of
    [] -> Nothing
    MatchBinding bindingName bindingValue:rest ->
      case matchBindingValue name rest of
        Just later -> Just later
        Nothing
          | name P.== bindingName -> Just bindingValue
          | otherwise -> Nothing

queryMatchBindings :: QueryBindings -> MatchBindings
queryMatchBindings bindings =
  case bindings of
    [] -> []
    (name, value):rest ->
      MatchBinding name (P.show value) : queryMatchBindings rest

newtype PayloadPattern tag =
  PayloadPattern (C.Payload tag -> Maybe MatchBindings)

payloadPatternMatches ::
     PayloadPattern tag -> C.Payload tag -> Maybe MatchBindings
payloadPatternMatches payloadPattern payload =
  case payloadPattern of
    PayloadPattern matchPayload -> matchPayload payload

anyPayloadPattern :: PayloadPattern tag
anyPayloadPattern = PayloadPattern (\_payload -> Just [])

payloadBindingPattern :: C.Traceable tag => P.String -> PayloadPattern tag
payloadBindingPattern name =
  PayloadPattern (\payload -> Just [MatchBinding name (C.payloadText payload)])

payloadBoolPattern ::
     (C.Payload tag ~ C.LBool tag) => P.Bool -> PayloadPattern tag
payloadBoolPattern expected = PayloadPattern matchPayload
  where
    matchPayload (C.LBool actual)
      | actual P.== expected = Just []
      | otherwise = Nothing

payloadIntPattern :: (C.Payload tag ~ C.LInt tag) => P.Int -> PayloadPattern tag
payloadIntPattern expected = PayloadPattern matchPayload
  where
    matchPayload (C.LInt actual)
      | actual P.== expected = Just []
      | otherwise = Nothing

payloadDoublePattern ::
     (C.Payload tag ~ C.LDouble tag) => P.Double -> PayloadPattern tag
payloadDoublePattern expected = PayloadPattern matchPayload
  where
    matchPayload (C.LDouble actual)
      | actual P.== expected = Just []
      | otherwise = Nothing

payloadStringPattern ::
     (C.Payload tag ~ C.LString tag) => P.String -> PayloadPattern tag
payloadStringPattern expected = PayloadPattern matchPayload
  where
    matchPayload (C.LString actual)
      | actual P.== expected = Just []
      | otherwise = Nothing

payloadUnitPattern :: (C.Payload tag ~ C.LUnit tag) => () -> PayloadPattern tag
payloadUnitPattern () = PayloadPattern matchPayload
  where
    matchPayload C.LUnit = Just []

matchQueryTerms ::
     [QueryTerm] -> C.Facts -> QueryBindings -> Maybe QueryBindings
matchQueryTerms terms facts bindings =
  case terms of
    [] -> Just bindings
    term:rest ->
      case matchQueryTerm term (C.factsToList facts) bindings of
        Nothing           -> Nothing
        Just nextBindings -> matchQueryTerms rest facts nextBindings

matchQueryTerm :: QueryTerm -> [C.Fact] -> QueryBindings -> Maybe QueryBindings
matchQueryTerm term facts bindings =
  firstJust (P.map (\fact -> matchQueryFact term fact bindings) facts)

matchQueryFact :: QueryTerm -> C.Fact -> QueryBindings -> Maybe QueryBindings
matchQueryFact term fact bindings =
  case term of
    QueryTerm expectedName expectedValue ->
      case fact of
        C.Fact actualName actualValue
          | expectedName P.== actualName ->
            matchQueryValue expectedValue actualValue bindings
        _ -> Nothing

matchQueryValue ::
     QueryValue -> C.FactValue -> QueryBindings -> Maybe QueryBindings
matchQueryValue expected actual bindings =
  case expected of
    QueryAtom ->
      case actual of
        C.FactAtom -> Just bindings
        _          -> Nothing
    QueryIntValue expectedInt ->
      case actual of
        C.FactInt actualInt -> matchQueryInt expectedInt actualInt bindings
        _                   -> Nothing

matchQueryInt :: QueryInt -> P.Int -> QueryBindings -> Maybe QueryBindings
matchQueryInt intPattern actual bindings =
  case intPattern of
    QueryIntConst expected
      | expected P.== actual -> Just bindings
      | otherwise -> Nothing
    QueryIntVar name -> bindQueryInt name actual bindings
    QueryIntAdd base offset -> matchQueryInt base (actual P.- offset) bindings

bindQueryInt :: P.String -> P.Int -> QueryBindings -> Maybe QueryBindings
bindQueryInt name value bindings =
  case lookupQueryBinding name bindings of
    Nothing -> Just (bindings P.++ [(name, value)])
    Just existing
      | existing P.== value -> Just bindings
      | otherwise -> Nothing

lookupQueryBinding :: P.String -> QueryBindings -> Maybe P.Int
lookupQueryBinding name bindings =
  case bindings of
    [] -> Nothing
    (bindingName, bindingValue):rest
      | name P.== bindingName -> Just bindingValue
      | otherwise -> lookupQueryBinding name rest

firstJust :: [Maybe a] -> Maybe a
firstJust values =
  case values of
    []           -> Nothing
    Nothing:rest -> firstJust rest
    Just value:_ -> Just value

queryTermToFact :: QueryTerm -> C.Fact
queryTermToFact term =
  case term of
    QueryTerm name value ->
      case value of
        QueryAtom -> C.factAtom name
        QueryIntValue intValue ->
          case queryIntConcrete intValue of
            Nothing ->
              P.error ("Cannot materialize non-concrete query term #" P.++ name)
            Just actualValue -> C.factInt name actualValue

queryIntConcrete :: QueryInt -> Maybe P.Int
queryIntConcrete value =
  case value of
    QueryIntConst actualValue -> Just actualValue
    QueryIntVar _ -> Nothing
    QueryIntAdd base offset ->
      case queryIntConcrete base of
        Nothing          -> Nothing
        Just actualValue -> Just (actualValue P.+ offset)

viewTagsFacts :: V.ViewTags -> C.Facts
viewTagsFacts tags = C.Facts (P.map viewTagFact (V.viewTagsToList tags))

viewTagFact :: (P.String, V.ViewTagValue) -> C.Fact
viewTagFact tag =
  case tag of
    (name, value) ->
      case value of
        V.ViewTagAtom    -> C.factAtom name
        V.ViewTagInt int -> C.factInt name int

canonicalTerms :: [QueryTerm] -> [QueryTerm]
canonicalTerms terms = dedupeTerms (sortTerms terms)

sortTerms :: [QueryTerm] -> [QueryTerm]
sortTerms terms =
  case terms of
    [] -> []
    term:rest ->
      sortTerms [x | x <- rest, x P.<= term]
        P.++ [term]
        P.++ sortTerms [x | x <- rest, x P.> term]

dedupeTerms :: [QueryTerm] -> [QueryTerm]
dedupeTerms terms =
  case terms of
    [] -> []
    term:rest
      {- HLINT ignore "Use if" -}
     ->
      case term `P.elem` rest of
        True  -> dedupeTerms rest
        False -> term : dedupeTerms rest

safeKey :: P.String -> P.String
safeKey value =
  case value of
    [] -> []
    ch:rest ->
      let safeChar
            {- HLINT ignore "Use if" -}
           =
            case isSafeKeyChar ch of
              True  -> ch
              False -> '_'
       in safeChar : safeKey rest

isSafeKeyChar :: P.Char -> P.Bool
isSafeKeyChar ch = ch `P.elem` safeKeyChars

safeKeyChars :: [P.Char]
safeKeyChars = ['a' .. 'z'] P.++ ['A' .. 'Z'] P.++ ['0' .. '9'] P.++ "_-"

joinPath :: [P.String] -> P.String
joinPath parts =
  case parts of
    []        -> ""
    [part]    -> part
    part:rest -> part P.++ "." P.++ joinPath rest
