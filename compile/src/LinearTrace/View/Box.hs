{-# LANGUAGE GADTs               #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Symbolic border boxes and solver-backed edge insets.
module LinearTrace.View.Box
  ( EdgeInsets(..)
  , InsetsExpr
  , ConcreteInsets
  , zeroInsets
  , uniformInsets
  , symmetricInsets
  , mapInsets
  , insetExprs
  , PaddingPlan
  , emptyPaddingPlan
  , requiredPadding
  , hasNodePadding
  , conditionalPadding
  , paddingForGeometry
  , NodeBox(..)
  , nodeBoxWithBounds
  , setNodePadding
  , setNodeConditionalPadding
  , setNodeMargin
  , mapNodeBoxExprs
  , nodeBoxConstraints
  , nodeBoxChoiceConstraints
  , materializeNodePadding
  , activeNodePaddingExpr
  , materializeNodeMargin
  , nodeBoxVariableBindings
  ) where

import           Data.Kind                   (Type)
import           Data.List                   (nub)
import qualified Data.Map.Strict             as Map
import           Data.Maybe                  (fromMaybe, mapMaybe)
import           LinearTrace.View.Primitives (Bounds (..), BoundsExpr,
                                              HasBounds (..), LayoutExpr)
import           Prelude
import qualified Solver                      as S

data EdgeInsets value = EdgeInsets
  { insetTop    :: value
  , insetRight  :: value
  , insetBottom :: value
  , insetLeft   :: value
  } deriving (Eq, Show)

type InsetsExpr = EdgeInsets LayoutExpr

type ConcreteInsets = EdgeInsets Double

zeroInsets :: S.SymbolicType ty => EdgeInsets (S.Expr ty)
zeroInsets = EdgeInsets (S.num 0) (S.num 0) (S.num 0) (S.num 0)

uniformInsets :: value -> EdgeInsets value
uniformInsets value = EdgeInsets value value value value

symmetricInsets :: value -> value -> EdgeInsets value
symmetricInsets vertical horizontal =
  EdgeInsets vertical horizontal vertical horizontal

mapInsets :: (a -> b) -> EdgeInsets a -> EdgeInsets b
mapInsets f insets =
  EdgeInsets
    { insetTop = f (insetTop insets)
    , insetRight = f (insetRight insets)
    , insetBottom = f (insetBottom insets)
    , insetLeft = f (insetLeft insets)
    }

insetExprs :: EdgeInsets value -> [value]
insetExprs insets =
  [insetTop insets, insetRight insets, insetBottom insets, insetLeft insets]

data PaddingPlan where
  PaddingUnset :: PaddingPlan
  PaddingRequired :: InsetsExpr -> PaddingPlan
  PaddingConditional
    :: S.ChoiceDomain value=> S.Choice value
    -> [(String, Maybe InsetsExpr)]
    -> PaddingPlan

emptyPaddingPlan :: PaddingPlan
emptyPaddingPlan = PaddingUnset

requiredPadding :: PaddingPlan -> Maybe InsetsExpr
requiredPadding plan =
  case plan of
    PaddingRequired value -> Just value
    _                     -> Nothing

hasNodePadding :: NodeBox -> Bool
hasNodePadding box =
  case nodeBoxPadding box of
    PaddingUnset -> False
    _            -> True

conditionalPadding ::
     forall value. S.ChoiceDomain value
  => S.Choice value
  -> (value -> Maybe InsetsExpr)
  -> PaddingPlan
conditionalPadding selected valueFor =
  PaddingConditional
    selected
    [(S.choiceToken value, valueFor value) | value <- S.choiceDomain]

paddingForGeometry :: PaddingPlan -> InsetsExpr
paddingForGeometry = fromMaybe zeroInsets . requiredPadding

data NodeBox = NodeBox
  { nodeBoxBounds  :: BoundsExpr
  , nodeBoxPadding :: PaddingPlan
  , nodeBoxMargin  :: InsetsExpr
  }

nodeBoxWithBounds :: BoundsExpr -> NodeBox
nodeBoxWithBounds bounds =
  NodeBox
    { nodeBoxBounds = bounds
    , nodeBoxPadding = emptyPaddingPlan
    , nodeBoxMargin = zeroInsets
    }

instance HasBounds NodeBox where
  top = top . nodeBoxBounds
  left = left . nodeBoxBounds
  width = width . nodeBoxBounds
  height = height . nodeBoxBounds

setNodePadding :: InsetsExpr -> NodeBox -> NodeBox
setNodePadding value box = box {nodeBoxPadding = PaddingRequired value}

setNodeConditionalPadding ::
     S.ChoiceDomain value
  => S.Choice value
  -> (value -> Maybe InsetsExpr)
  -> NodeBox
  -> NodeBox
setNodeConditionalPadding selected valueFor box =
  box {nodeBoxPadding = conditionalPadding selected valueFor}

setNodeMargin :: InsetsExpr -> NodeBox -> NodeBox
setNodeMargin value box = box {nodeBoxMargin = value}

mapNodeBoxExprs ::
     (forall (ty :: Type). S.Expr ty -> S.Expr ty) -> NodeBox -> NodeBox
mapNodeBoxExprs f box =
  box
    { nodeBoxBounds = fmap f (nodeBoxBounds box)
    , nodeBoxPadding = mapPaddingPlan f (nodeBoxPadding box)
    , nodeBoxMargin = mapInsets f (nodeBoxMargin box)
    }

mapPaddingPlan ::
     (forall (ty :: Type). S.Expr ty -> S.Expr ty) -> PaddingPlan -> PaddingPlan
mapPaddingPlan f plan =
  case plan of
    PaddingUnset -> PaddingUnset
    PaddingRequired value -> PaddingRequired (mapInsets f value)
    PaddingConditional selected alternatives ->
      PaddingConditional
        selected
        [(token, fmap (mapInsets f) value) | (token, value) <- alternatives]

nodeBoxConstraints :: NodeBox -> [S.Constraint]
nodeBoxConstraints box =
  concatMap nonNegative (insetExprs (nodeBoxMargin box))
    ++ concatMap
         (concatMap nonNegative . insetExprs)
         (paddingPlanValues (nodeBoxPadding box))
  where
    nonNegative expression = [S.num 0 S.@<=@ expression]

nodeBoxChoiceConstraints :: NodeBox -> [S.ChoiceConstraint]
nodeBoxChoiceConstraints box =
  case nodeBoxPadding box of
    PaddingConditional selected _ -> [S.freeChoice selected]
    _                             -> []

paddingPlanValues :: PaddingPlan -> [InsetsExpr]
paddingPlanValues plan =
  case plan of
    PaddingUnset                      -> []
    PaddingRequired value             -> [value]
    PaddingConditional _ alternatives -> mapMaybe snd alternatives

materializeNodePadding :: S.Solution -> NodeBox -> Either String ConcreteInsets
materializeNodePadding solution box = do
  selected <- activeNodePaddingExpr solution box
  traverseInsets solution selected

activeNodePaddingExpr :: S.Solution -> NodeBox -> Either String InsetsExpr
activeNodePaddingExpr solution box =
  fromMaybe zeroInsets <$> activePadding solution (nodeBoxPadding box)

activePadding :: S.Solution -> PaddingPlan -> Either String (Maybe InsetsExpr)
activePadding solution plan =
  case plan of
    PaddingUnset -> Right Nothing
    PaddingRequired value -> Right (Just value)
    PaddingConditional selected alternatives -> do
      chosen <-
        maybe
          (Left
             ("could not materialize padding choice " ++ S.choiceName selected))
          Right
          (S.evalChoice solution selected)
      maybe
        (Left
           ("padding choice "
              ++ S.choiceName selected
              ++ " has no branch for token "
              ++ S.choiceToken chosen))
        Right
        (lookup (S.choiceToken chosen) alternatives)

materializeNodeMargin :: S.Solution -> NodeBox -> Either String ConcreteInsets
materializeNodeMargin solution = traverseInsets solution . nodeBoxMargin

traverseInsets :: S.Solution -> InsetsExpr -> Either String ConcreteInsets
traverseInsets solution insets =
  EdgeInsets
    <$> solved "top" (insetTop insets)
    <*> solved "right" (insetRight insets)
    <*> solved "bottom" (insetBottom insets)
    <*> solved "left" (insetLeft insets)
  where
    solved edge expression =
      maybe
        (Left ("could not materialize " ++ edge ++ " inset"))
        Right
        (S.evalExpr solution expression)

nodeBoxVariableBindings ::
     S.Solution -> NodeBox -> Either String [(String, [String])]
nodeBoxVariableBindings solution box = do
  active <- activePadding solution (nodeBoxPadding box)
  let bindings =
        boundsBindings (nodeBoxBounds box)
          ++ insetBindings "padding" (fromMaybe zeroInsets active)
          ++ insetBindings "margin" (nodeBoxMargin box)
  pure
    [ (field, nub names)
    | (field, names) <- Map.toAscList (Map.fromListWith (++) bindings)
    , not (null names)
    ]
  where
    boundsBindings bounds =
      case bounds of
        Bounds topExpr leftExpr widthExpr heightExpr ->
          [ numericBinding "box.top" topExpr
          , numericBinding "box.left" leftExpr
          , numericBinding "box.width" widthExpr
          , numericBinding "box.height" heightExpr
          ]
    insetBindings prefix insets =
      [ numericBinding (prefix ++ ".top") (insetTop insets)
      , numericBinding (prefix ++ ".right") (insetRight insets)
      , numericBinding (prefix ++ ".bottom") (insetBottom insets)
      , numericBinding (prefix ++ ".left") (insetLeft insets)
      ]
    numericBinding name expression =
      (name, expressionVariableNames (S.exprView expression))

expressionVariableNames :: S.ExprView -> [String]
expressionVariableNames expression =
  case expression of
    S.ExprVar _ name   -> [name]
    S.ExprLit _        -> []
    S.ExprAdd lhs rhs  -> both lhs rhs
    S.ExprSub lhs rhs  -> both lhs rhs
    S.ExprMul lhs rhs  -> both lhs rhs
    S.ExprDiv lhs rhs  -> both lhs rhs
    S.ExprNeg inner    -> expressionVariableNames inner
    S.ExprAbs inner    -> expressionVariableNames inner
    S.ExprSignum inner -> expressionVariableNames inner
    S.ExprPow lhs rhs  -> both lhs rhs
    S.ExprMin lhs rhs  -> both lhs rhs
    S.ExprMax lhs rhs  -> both lhs rhs
  where
    both lhs rhs = expressionVariableNames lhs ++ expressionVariableNames rhs
