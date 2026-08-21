{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Universal symbolic style catalogue. Each field defined here owns its
-- symbolic value, solved value, constraints, traversal, and materialization.
module LinearTrace.View.Style
  ( -- * Defined here: choice values
    -- | CSS-like fixed style tokens. Each value type has a solver
    -- 'ChoiceDomain' instance, so solver choices and CSS materialization share
    -- one domain/token definition.
    FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , -- * Defined here: field markers
    -- | Type-level names for supported optional node-style fields.
    Opacity
  , ZIndex
  , Padding
  , FontSize
  , Radius
  , StrokeWidth
  , Alpha
  , Fill
  , Stroke
  , -- * Style model
    NodeStyle
  , nodeStyleWithBounds
  , nodeStyleBounds
  , StyleField(..)
  , StyleValueVars(..)
  , getStyleField
  , setStyleField
  , requireStyleField
  , materializeStyleField
  , -- * Traversal and lowering
    mapNodeStyleExprs
  , mapNodeStyleExprLeaves
  , nodeStyleConstraints
  , nodeStyleChoiceConstraints
  , styleVariableBindings
  , -- * Re-exported from Solver
    -- | Categorical field values use the solver's fixed-or-variable choice
    -- wrapper directly.
    ChoiceValue(..)
  ) where

import           Data.Kind                   (Type)
import           Data.List                   (nub)
import qualified Data.Map.Strict             as Map
import           Data.Maybe                  (mapMaybe)
import           Data.Proxy                  (Proxy (..))
import           Data.Type.Equality          ((:~:) (..))
import           Data.Typeable               (Typeable, eqT)
import           LinearTrace.View.Primitives
import           Prelude
import           Solver                      hiding (num)

--------------------------------------------------------------------------------
-- Scalar fields
--------------------------------------------------------------------------------
data Opacity

data ZIndex

data Padding

data FontSize

data Radius

data StrokeWidth

data Alpha

instance StyleField Opacity where
  type StyleValue Opacity = UnitExpr
  type ResolvedStyleValue Opacity = Double
  styleFieldName _ = "opacity"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ = scalarConstraints (Just unitRange) noConstraints
  materializeStyleValue = materializeScalar

instance StyleField ZIndex where
  type StyleValue ZIndex = FreeExpr
  type ResolvedStyleValue ZIndex = Double
  styleFieldName _ = "zIndex"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range (-10) 10)) noConstraints
  materializeStyleValue = materializeScalar

instance StyleField Padding where
  type StyleValue Padding = LayoutExpr
  type ResolvedStyleValue Padding = Double
  styleFieldName _ = "padding"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 0 24)) nonNegativeConstraints
  materializeStyleValue = materializeScalar

instance StyleField FontSize where
  type StyleValue FontSize = LayoutExpr
  type ResolvedStyleValue FontSize = Double
  styleFieldName _ = "fontSize"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 8 48)) nonNegativeConstraints
  materializeStyleValue = materializeScalar

instance StyleField Radius where
  type StyleValue Radius = LayoutExpr
  type ResolvedStyleValue Radius = Double
  styleFieldName _ = "radius"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 0 32)) nonNegativeConstraints
  materializeStyleValue = materializeScalar

instance StyleField StrokeWidth where
  type StyleValue StrokeWidth = LayoutExpr
  type ResolvedStyleValue StrokeWidth = Double
  styleFieldName _ = "strokeWidth"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 0 8)) nonNegativeConstraints
  materializeStyleValue = materializeScalar

instance StyleField Alpha where
  type StyleValue Alpha = UnitExpr
  type ResolvedStyleValue Alpha = Double
  styleFieldName _ = "alpha"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ = scalarConstraints (Just unitRange) noConstraints
  materializeStyleValue = materializeScalar

--------------------------------------------------------------------------------
-- Colour fields
--------------------------------------------------------------------------------
data Fill

data Stroke

instance StyleField Fill where
  type StyleValue Fill = ColorExpr
  type ResolvedStyleValue Fill = ConcreteHsl
  styleFieldName _ = "fill"
  generatedStyleValue = colorValue
  mapStyleValueExprs = mapColorExprs
  styleValueExprLeaves = colorLeaves
  styleValueConstraints _ = colorConstraints
  materializeStyleValue _ = materializeColor

instance StyleField Stroke where
  type StyleValue Stroke = ColorExpr
  type ResolvedStyleValue Stroke = ConcreteHsl
  styleFieldName _ = "stroke"
  generatedStyleValue = colorValue
  mapStyleValueExprs = mapColorExprs
  styleValueExprLeaves = colorLeaves
  styleValueConstraints _ = colorConstraints
  materializeStyleValue _ = materializeColor

--------------------------------------------------------------------------------
-- Choice fields
--------------------------------------------------------------------------------
data FontFamily
  = FontInter
  | FontSystem
  | FontMono
  | FontSerif
  deriving (Eq, Show)

instance ChoiceDomain FontFamily where
  choiceDomain = [FontInter, FontSystem, FontMono, FontSerif]
  choiceToken value =
    case value of
      FontInter  -> "Inter"
      FontSystem -> "system-ui"
      FontMono   -> "monospace"
      FontSerif  -> "serif"

instance StyleField FontFamily where
  type StyleValue FontFamily = ChoiceValue FontFamily
  type ResolvedStyleValue FontFamily = String
  styleFieldName _ = "fontFamily"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoiceNames _ = choiceNames
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data FontWeight
  = FontWeightNormal
  | FontWeightBold
  | FontWeightBolder
  | FontWeightLighter
  | FontWeightNumber Int
  deriving (Eq, Show)

instance ChoiceDomain FontWeight where
  choiceDomain =
    [FontWeightNormal, FontWeightBold, FontWeightBolder, FontWeightLighter]
      ++ map FontWeightNumber [100,200 .. 900]
  choiceToken value =
    case value of
      FontWeightNormal   -> "normal"
      FontWeightBold     -> "bold"
      FontWeightBolder   -> "bolder"
      FontWeightLighter  -> "lighter"
      FontWeightNumber n -> show n

instance StyleField FontWeight where
  type StyleValue FontWeight = ChoiceValue FontWeight
  type ResolvedStyleValue FontWeight = String
  styleFieldName _ = "fontWeight"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoiceNames _ = choiceNames
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data FontStyle
  = FontStyleNormal
  | FontStyleItalic
  | FontStyleOblique
  deriving (Eq, Show)

instance ChoiceDomain FontStyle where
  choiceDomain = [FontStyleNormal, FontStyleItalic, FontStyleOblique]
  choiceToken value =
    case value of
      FontStyleNormal  -> "normal"
      FontStyleItalic  -> "italic"
      FontStyleOblique -> "oblique"

instance StyleField FontStyle where
  type StyleValue FontStyle = ChoiceValue FontStyle
  type ResolvedStyleValue FontStyle = String
  styleFieldName _ = "fontStyle"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoiceNames _ = choiceNames
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data TextAlign
  = TextAlignLeft
  | TextAlignCenter
  | TextAlignRight
  | TextAlignJustify
  deriving (Eq, Show)

instance ChoiceDomain TextAlign where
  choiceDomain =
    [TextAlignLeft, TextAlignCenter, TextAlignRight, TextAlignJustify]
  choiceToken value =
    case value of
      TextAlignLeft    -> "left"
      TextAlignCenter  -> "center"
      TextAlignRight   -> "right"
      TextAlignJustify -> "justify"

instance StyleField TextAlign where
  type StyleValue TextAlign = ChoiceValue TextAlign
  type ResolvedStyleValue TextAlign = String
  styleFieldName _ = "textAlign"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoiceNames _ = choiceNames
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data BorderStyle
  = BorderNone
  | BorderSolid
  | BorderDashed
  | BorderDotted
  | BorderDouble
  deriving (Eq, Show)

instance ChoiceDomain BorderStyle where
  choiceDomain =
    [BorderNone, BorderSolid, BorderDashed, BorderDotted, BorderDouble]
  choiceToken value =
    case value of
      BorderNone   -> "none"
      BorderSolid  -> "solid"
      BorderDashed -> "dashed"
      BorderDotted -> "dotted"
      BorderDouble -> "double"

instance StyleField BorderStyle where
  type StyleValue BorderStyle = ChoiceValue BorderStyle
  type ResolvedStyleValue BorderStyle = String
  styleFieldName _ = "borderStyle"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoiceNames _ = choiceNames
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data WhiteSpace
  = WhiteSpaceNormal
  | WhiteSpaceNoWrap
  | WhiteSpacePre
  | WhiteSpacePreWrap
  deriving (Eq, Show)

instance ChoiceDomain WhiteSpace where
  choiceDomain =
    [WhiteSpaceNormal, WhiteSpaceNoWrap, WhiteSpacePre, WhiteSpacePreWrap]
  choiceToken value =
    case value of
      WhiteSpaceNormal  -> "normal"
      WhiteSpaceNoWrap  -> "nowrap"
      WhiteSpacePre     -> "pre"
      WhiteSpacePreWrap -> "pre-wrap"

instance StyleField WhiteSpace where
  type StyleValue WhiteSpace = ChoiceValue WhiteSpace
  type ResolvedStyleValue WhiteSpace = String
  styleFieldName _ = "whiteSpace"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoiceNames _ = choiceNames
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

--------------------------------------------------------------------------------
-- Symbolic style model
--------------------------------------------------------------------------------

data StyleValueVars = StyleValueVars
  { styleExprVar :: forall (ty :: Type). SymbolicType ty =>
                                           [String] -> String -> Expr ty
  , styleChoiceVar :: forall value. ChoiceDomain value => String -> Choice value
  }

data StyleExprLeaf where
  StyleExprLeaf :: String -> Expr (ty :: Type) -> StyleExprLeaf

class Typeable field => StyleField (field :: Type) where
  type StyleValue field
  type ResolvedStyleValue field
  styleFieldName :: Proxy field -> String
  generatedStyleValue :: Proxy field -> StyleValueVars -> StyleValue field
  mapStyleValueExprs ::
       (forall (ty :: Type). Expr ty -> Expr ty)
    -> StyleValue field
    -> StyleValue field
  styleValueExprLeaves :: Proxy field -> StyleValue field -> [StyleExprLeaf]
  styleValueChoiceNames :: Proxy field -> StyleValue field -> [String]
  styleValueChoiceNames _ _ = []
  styleValueConstraints :: Proxy field -> StyleValue field -> [Constraint]
  styleValueConstraints _ _ = []
  styleValueChoices :: Proxy field -> StyleValue field -> [ChoiceConstraint]
  styleValueChoices _ _ = []
  materializeStyleValue ::
       Proxy field
    -> Solution
    -> StyleValue field
    -> Either String (ResolvedStyleValue field)

data AnyStyleField where
  AnyStyleField
    :: StyleField field => Proxy field -> StyleValue field -> AnyStyleField

anyStyleFieldName :: AnyStyleField -> String
anyStyleFieldName field =
  case field of
    AnyStyleField proxy _ -> styleFieldName proxy

data NodeStyle = NodeStyle
  { nodeStyleBounds :: BoundsExpr
  , nodeStyleFields :: [AnyStyleField]
  }

nodeStyleWithBounds :: BoundsExpr -> NodeStyle
nodeStyleWithBounds bounds =
  NodeStyle {nodeStyleBounds = bounds, nodeStyleFields = []}

instance HasBounds NodeStyle where
  top = top . nodeStyleBounds
  left = left . nodeStyleBounds
  width = width . nodeStyleBounds
  height = height . nodeStyleBounds

getStyleField ::
     forall field. StyleField field
  => NodeStyle
  -> Maybe (StyleValue field)
getStyleField style' = go (nodeStyleFields style')
  where
    go fields =
      case fields of
        [] -> Nothing
        AnyStyleField (_ :: Proxy other) value:rest ->
          case eqT @field @other of
            Just Refl -> Just value
            Nothing   -> go rest

setStyleField ::
     forall field. StyleField field
  => StyleValue field
  -> NodeStyle
  -> NodeStyle
setStyleField value style' =
  style'
    { nodeStyleFields =
        replaceByName
          anyStyleFieldName
          (AnyStyleField (Proxy :: Proxy field) value)
          (nodeStyleFields style')
    }

requireStyleField ::
     forall field. StyleField field
  => StyleValueVars
  -> NodeStyle
  -> NodeStyle
requireStyleField vars style' =
  case getStyleField @field style' of
    Just _ -> style'
    Nothing ->
      setStyleField @field (generatedStyleValue (Proxy @field) vars) style'

materializeStyleField ::
     forall field. StyleField field
  => Solution
  -> NodeStyle
  -> Either String (Maybe (ResolvedStyleValue field))
materializeStyleField solution style' =
  traverse
    (materializeStyleValue (Proxy @field) solution)
    (getStyleField @field style')

replaceByName :: (a -> String) -> a -> [a] -> [a]
replaceByName getName newValue = go
  where
    target = getName newValue
    go xs =
      case xs of
        [] -> [newValue]
        x:rest
          | getName x == target -> newValue : rest
          | otherwise -> x : go rest

--------------------------------------------------------------------------------
-- Traversal, constraints, and provenance
--------------------------------------------------------------------------------

mapNodeStyleExprs ::
     (forall (ty :: Type). Expr ty -> Expr ty) -> NodeStyle -> NodeStyle
mapNodeStyleExprs f style' =
  NodeStyle
    { nodeStyleBounds = fmap f (nodeStyleBounds style')
    , nodeStyleFields = map (mapAnyStyleFieldExprs f) (nodeStyleFields style')
    }

mapAnyStyleFieldExprs ::
     (forall (ty :: Type). Expr ty -> Expr ty) -> AnyStyleField -> AnyStyleField
mapAnyStyleFieldExprs f field =
  case field of
    AnyStyleField (proxy :: Proxy field) value ->
      AnyStyleField proxy (mapStyleValueExprs @field f value)

nodeStyleExprLeaves :: NodeStyle -> [StyleExprLeaf]
nodeStyleExprLeaves style' =
  [ StyleExprLeaf "top" (top style')
  , StyleExprLeaf "left" (left style')
  , StyleExprLeaf "width" (width style')
  , StyleExprLeaf "height" (height style')
  ]
    ++ concatMap anyStyleFieldExprLeaves (nodeStyleFields style')

anyStyleFieldExprLeaves :: AnyStyleField -> [StyleExprLeaf]
anyStyleFieldExprLeaves field =
  case field of
    AnyStyleField proxy value -> styleValueExprLeaves proxy value

mapNodeStyleExprLeaves ::
     (forall (ty :: Type). String -> Expr ty -> a) -> NodeStyle -> [a]
mapNodeStyleExprLeaves f style' = map go (nodeStyleExprLeaves style')
  where
    go leaf =
      case leaf of
        StyleExprLeaf name expr -> f name expr

nodeStyleConstraints :: NodeStyle -> [Constraint]
nodeStyleConstraints style' =
  concatMap anyStyleFieldConstraints (nodeStyleFields style')

anyStyleFieldConstraints :: AnyStyleField -> [Constraint]
anyStyleFieldConstraints field =
  case field of
    AnyStyleField proxy value -> styleValueConstraints proxy value

nodeStyleChoiceConstraints :: NodeStyle -> [ChoiceConstraint]
nodeStyleChoiceConstraints style' =
  concatMap anyStyleFieldChoices (nodeStyleFields style')

anyStyleFieldChoices :: AnyStyleField -> [ChoiceConstraint]
anyStyleFieldChoices field =
  case field of
    AnyStyleField proxy value -> styleValueChoices proxy value

styleVariableBindings :: NodeStyle -> [(String, [String])]
styleVariableBindings style' =
  [ (field, nub variables)
  | (field, variables) <- Map.toAscList grouped
  , not (null variables)
  ]
  where
    grouped =
      Map.fromListWith (++)
        (mapNodeStyleExprLeaves numericBinding style'
           ++ mapMaybe choiceBinding (nodeStyleFields style'))
    numericBinding name expr =
      (rootField name, expressionVariableNames (exprView expr))
    choiceBinding field =
      case field of
        AnyStyleField proxy value ->
          let variables = styleValueChoiceNames proxy value
           in if null variables
                then Nothing
                else Just (styleFieldName proxy, variables)

rootField :: String -> String
rootField = takeWhile (/= '.')

expressionVariableNames :: ExprView -> [String]
expressionVariableNames expression =
  case expression of
    ExprVar _ name   -> [name]
    ExprLit _        -> []
    ExprAdd lhs rhs  -> both lhs rhs
    ExprSub lhs rhs  -> both lhs rhs
    ExprMul lhs rhs  -> both lhs rhs
    ExprDiv lhs rhs  -> both lhs rhs
    ExprNeg inner    -> expressionVariableNames inner
    ExprAbs inner    -> expressionVariableNames inner
    ExprSignum inner -> expressionVariableNames inner
    ExprPow lhs rhs  -> both lhs rhs
    ExprMin lhs rhs  -> both lhs rhs
    ExprMax lhs rhs  -> both lhs rhs
  where
    both lhs rhs = expressionVariableNames lhs ++ expressionVariableNames rhs

--------------------------------------------------------------------------------
-- Reusable field implementations
--------------------------------------------------------------------------------

scalarValue ::
     forall field (ty :: Type). (StyleField field, SymbolicType ty)
  => Proxy field
  -> StyleValueVars
  -> Expr ty
scalarValue proxy vars = styleExprVar vars [] (styleFieldName proxy)

scalarLeaves ::
     forall field (ty :: Type). StyleField field
  => Proxy field
  -> Expr ty
  -> [StyleExprLeaf]
scalarLeaves proxy expr = [StyleExprLeaf (styleFieldName proxy) expr]

scalarConstraints ::
     forall (ty :: Type). SymbolicType ty
  => Maybe Range
  -> (Expr ty -> [Constraint])
  -> Expr ty
  -> [Constraint]
scalarConstraints range extra expr =
  case range of
    Just range' -> within expr range' : extra expr
    Nothing     -> extra expr

materializeScalar ::
     forall field (ty :: Type). StyleField field
  => Proxy field
  -> Solution
  -> Expr ty
  -> Either String Double
materializeScalar proxy solution =
  requireSolvedExpr solution (styleFieldName proxy)

noConstraints :: forall (ty :: Type). Expr ty -> [Constraint]
noConstraints _ = []

nonNegativeConstraints ::
     forall (ty :: Type). SymbolicType ty
  => Expr ty
  -> [Constraint]
nonNegativeConstraints expr = [num 0 @<=@ expr]

colorValue :: StyleField field => Proxy field -> StyleValueVars -> ColorExpr
colorValue proxy vars =
  Hsl
    (styleExprVar vars [styleFieldName proxy] "hue")
    (styleExprVar vars [styleFieldName proxy] "saturation")
    (styleExprVar vars [styleFieldName proxy] "lightness")

colorLeaves :: StyleField field => Proxy field -> ColorExpr -> [StyleExprLeaf]
colorLeaves proxy hsl =
  [ StyleExprLeaf (styleFieldName proxy ++ ".hue") (hue hsl)
  , StyleExprLeaf (styleFieldName proxy ++ ".saturation") (saturation hsl)
  , StyleExprLeaf (styleFieldName proxy ++ ".lightness") (lightness hsl)
  ]

mapColorExprs ::
     (forall (ty :: Type). Expr ty -> Expr ty) -> ColorExpr -> ColorExpr
mapColorExprs f hsl = Hsl (f (hue hsl)) (f (saturation hsl)) (f (lightness hsl))

colorConstraints :: ColorExpr -> [Constraint]
colorConstraints hsl =
  [ within (hue hsl) angleRange
  , within (saturation hsl) unitRange
  , within (lightness hsl) unitRange
  ]

materializeColor :: Solution -> ColorExpr -> Either String ConcreteHsl
materializeColor solution hsl =
  Hsl
    <$> requireSolvedExpr solution "hue" (hue hsl)
    <*> requireSolvedExpr solution "saturation" (saturation hsl)
    <*> requireSolvedExpr solution "lightness" (lightness hsl)

choiceValue ::
     forall value field. (StyleField field, ChoiceDomain value)
  => Proxy field
  -> StyleValueVars
  -> ChoiceValue value
choiceValue proxy vars = Variable (styleChoiceVar vars (styleFieldName proxy))

choiceChoices :: ChoiceValue value -> [ChoiceConstraint]
choiceChoices value =
  case value of
    Fixed _           -> []
    Variable selected -> [freeChoice selected]

choiceNames :: ChoiceValue value -> [String]
choiceNames value =
  case value of
    Fixed _           -> []
    Variable selected -> [choiceName selected]

materializeChoice ::
     ChoiceDomain value
  => Proxy field
  -> Solution
  -> ChoiceValue value
  -> Either String String
materializeChoice _ solution value =
  choiceToken
    <$> case value of
          Fixed fixed -> Right fixed
          Variable selected ->
            maybe
              (Left
                 "could not materialize a style choice from the solver solution")
              Right
              (evalChoice solution selected)

mapChoiceValue :: ChoiceValue value -> ChoiceValue value
mapChoiceValue = id

requireSolvedExpr :: Solution -> String -> Expr ty -> Either String Double
requireSolvedExpr solution label expr =
  case evalExpr solution expr of
    Just value -> Right value
    Nothing ->
      Left
        ("could not materialize "
           ++ label
           ++ " from the solver solution; the expression probably references a \
             \variable that was not included in any constraint")
