{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE NoImplicitPrelude    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Visual constraint and relation operators for choreography.
module LinearTrace.Choreography.Constraint
  ( ensure
  , CategoryTerm(..)
  , encourage
  , VisualAlternative
  , alternative
  , oneOf
  , caseOf
  , ValueTerm(..)
  , VisualConstraint(..)
  , (.<=.)
  , (.>=.)
  , (.==.)
  , (=|)
  , (|=)
  , (=/)
  , (/=)
  ) where

import           LinearTrace.Choreography.Match (CategoryEndpoint,
                                                 CategoryRelation (..),
                                                 ConstraintStrength (..),
                                                 LayoutRelation (..), MatchSpec,
                                                 NodeSelection, ValueExpr,
                                                 emptyMatchSpec,
                                                 matchCategoryRelation,
                                                 matchFiniteDecision,
                                                 matchSpecAppend,
                                                 matchValueDirectedBridge,
                                                 matchValueRelation,
                                                 matchValueSymmetricBridge,
                                                 rawCategoryEndpoint,
                                                 rawValueExpr,
                                                 selectionCategoryEndpoint)
import           LinearTrace.Choreography.Node  (Coord, Offset, Scalar,
                                                 Selected (..), Selection (..),
                                                 SelectionCategory (..), Span,
                                                 VisualExpr (..),
                                                 VisualizationBuilder,
                                                 coordConstraints, coordExpr,
                                                 emitVisualizationBuilder,
                                                 nodeSelection,
                                                 offsetConstraints, offsetExpr,
                                                 scalarConstraints, scalarExpr,
                                                 spanConstraints, spanExpr)
import           LinearTrace.View.Access        (CategoryAccess)
import           LinearTrace.View.Primitives    (Hsl (..))
import qualified Prelude                        as P
import qualified Solver                         as S
import           Solver                         (Vec2 (..))

data VisualConstraint where
  VisualValueRelation
    :: ValueTerm -> LayoutRelation -> ValueTerm -> VisualConstraint
  VisualCategoryRelation
    :: S.ChoiceDomain value=> CategoryTerm value
    -> CategoryRelation
    -> CategoryTerm value
    -> VisualConstraint
  VisualDirectedBridge
    :: ValueTerm -> ValueTerm -> ValueTerm -> VisualConstraint
  VisualSymmetricBridge
    :: ValueTerm -> ValueTerm -> ValueTerm -> VisualConstraint

data VisualAlternative =
  VisualAlternative P.String [VisualConstraint]

data ValueTerm =
  ValueTerm MatchSpec [ValueExpr]

data CategoryTerm value =
  CategoryTerm MatchSpec [CategoryEndpoint value]

class ConstraintValue value where
  valueTerm :: value -> ValueTerm

rawValueTerm :: S.Component -> ValueTerm
rawValueTerm component = ValueTerm emptyMatchSpec [rawValueExpr component]

rawExprValueTerm ::
     S.SymbolicType ty => S.Expr ty -> [S.Constraint] -> ValueTerm
rawExprValueTerm expr constraints = rawValueTerm (S.component expr constraints)

rawCategoryTerm ::
     S.ChoiceDomain value => S.ChoiceValue value -> CategoryTerm value
rawCategoryTerm value = CategoryTerm emptyMatchSpec [rawCategoryEndpoint value]

selectedCategoryTerm ::
     Selected tag -> CategoryAccess value -> CategoryTerm value
selectedCategoryTerm selected access =
  CategoryTerm
    (selectedSpec selected)
    [selectionCategoryEndpoint (selectedNodeSelection selected) access]

categoryTermSpec :: CategoryTerm value -> MatchSpec
categoryTermSpec term =
  case term of
    CategoryTerm spec _ -> spec

categoryTermEndpoints :: CategoryTerm value -> [CategoryEndpoint value]
categoryTermEndpoints term =
  case term of
    CategoryTerm _ endpoints -> endpoints

fixedCategoryTerm :: S.ChoiceDomain value => value -> CategoryTerm value
fixedCategoryTerm = rawCategoryTerm P.. S.Fixed

variableCategoryTerm ::
     S.ChoiceDomain value => S.Choice value -> CategoryTerm value
variableCategoryTerm value = rawCategoryTerm (S.Variable value)

selectedCategoryValueTerm :: SelectionCategory value tag -> CategoryTerm value
selectedCategoryValueTerm selected =
  case selected of
    SelectionCategory selection access -> selectedCategoryTerm selection access

appendValueTerm :: ValueTerm -> ValueTerm -> ValueTerm
appendValueTerm lhs rhs =
  case lhs of
    ValueTerm lhsSpec lhsEndpoints ->
      case rhs of
        ValueTerm rhsSpec rhsEndpoints ->
          ValueTerm
            (lhsSpec `matchSpecAppend` rhsSpec)
            (lhsEndpoints P.++ rhsEndpoints)

instance ConstraintValue Coord where
  valueTerm value = rawExprValueTerm (coordExpr value) (coordConstraints value)

instance ConstraintValue Span where
  valueTerm value = rawExprValueTerm (spanExpr value) (spanConstraints value)

instance ConstraintValue Scalar where
  valueTerm value =
    rawExprValueTerm (scalarExpr value) (scalarConstraints value)

instance ConstraintValue Offset where
  valueTerm value =
    rawExprValueTerm (offsetExpr value) (offsetConstraints value)

instance S.SymbolicType ty => ConstraintValue (S.Expr ty) where
  valueTerm expr = rawExprValueTerm expr []

instance ConstraintValue (VisualExpr value) where
  valueTerm selected =
    case selected of
      VisualExpr expression -> ValueTerm emptyMatchSpec [expression]

instance ConstraintValue x => ConstraintValue (Vec2 x) where
  valueTerm value =
    case value of
      Vec2 valueX valueY -> valueTerm valueX `appendValueTerm` valueTerm valueY

instance (ConstraintValue hue, ConstraintValue unit) =>
         ConstraintValue (Hsl hue unit) where
  valueTerm value =
    valueTerm (hue value)
      `appendValueTerm` valueTerm (saturation value)
      `appendValueTerm` valueTerm (lightness value)

selectedSpec :: Selected tag -> MatchSpec
selectedSpec selected =
  case selected of
    SelectedHandle (Selection _) -> emptyMatchSpec

selectedNodeSelection :: Selected tag -> NodeSelection
selectedNodeSelection selected =
  case selected of
    SelectedHandle (Selection handle) -> nodeSelection handle

class RelateValues lhs rhs where
  relateValues :: LayoutRelation -> lhs -> rhs -> VisualConstraint

instance {-# OVERLAPPABLE #-} (ConstraintValue lhs, ConstraintValue rhs) =>
         RelateValues lhs rhs where
  relateValues relation lhs rhs =
    VisualValueRelation (valueTerm lhs) relation (valueTerm rhs)

relateCategories ::
     S.ChoiceDomain value
  => LayoutRelation
  -> CategoryTerm value
  -> CategoryTerm value
  -> VisualConstraint
relateCategories relation lhs rhs =
  case relation of
    LayoutEqual -> VisualCategoryRelation lhs CategoryEqual rhs
    LayoutLessOrEqual ->
      P.error "Categorical values do not support ordered relations."

instance S.ChoiceDomain value => RelateValues (S.Choice value) value where
  relateValues relation lhs rhs =
    relateCategories relation (variableCategoryTerm lhs) (fixedCategoryTerm rhs)

instance S.ChoiceDomain value => RelateValues (S.Choice value) (S.Choice value) where
  relateValues relation lhs rhs =
    relateCategories
      relation
      (variableCategoryTerm lhs)
      (variableCategoryTerm rhs)

instance S.ChoiceDomain value =>
         RelateValues (SelectionCategory value tag) value where
  relateValues relation lhs rhs =
    relateCategories
      relation
      (selectedCategoryValueTerm lhs)
      (fixedCategoryTerm rhs)

instance S.ChoiceDomain value =>
         RelateValues (SelectionCategory value tag) (S.Choice value) where
  relateValues relation lhs rhs =
    relateCategories
      relation
      (selectedCategoryValueTerm lhs)
      (variableCategoryTerm rhs)

instance S.ChoiceDomain value =>
         RelateValues
           (SelectionCategory value lhsTag)
           (SelectionCategory value rhsTag) where
  relateValues relation lhs rhs =
    relateCategories
      relation
      (selectedCategoryValueTerm lhs)
      (selectedCategoryValueTerm rhs)

data DirectedBridge =
  DirectedBridge ValueTerm ValueTerm

class OpenDirectedBridge lhs gap where
  openDirectedBridge :: lhs -> gap -> DirectedBridge

instance {-# OVERLAPPABLE #-} (ConstraintValue lhs, ConstraintValue gap) =>
         OpenDirectedBridge lhs gap where
  openDirectedBridge lhs gap = DirectedBridge (valueTerm lhs) (valueTerm gap)

class CloseDirectedBridge bridge rhs where
  closeDirectedBridge :: bridge -> rhs -> VisualConstraint

instance {-# OVERLAPPABLE #-} ConstraintValue rhs =>
         CloseDirectedBridge DirectedBridge rhs where
  closeDirectedBridge bridge rhs =
    case bridge of
      DirectedBridge lhs gap -> VisualDirectedBridge lhs gap (valueTerm rhs)

data SymmetricBridge =
  SymmetricBridge ValueTerm ValueTerm

class OpenSymmetricBridge lhs delta where
  openSymmetricBridge :: lhs -> delta -> SymmetricBridge

instance {-# OVERLAPPABLE #-} (ConstraintValue lhs, ConstraintValue delta) =>
         OpenSymmetricBridge lhs delta where
  openSymmetricBridge lhs delta =
    SymmetricBridge (valueTerm lhs) (valueTerm delta)

class CloseSymmetricBridge bridge rhs where
  closeSymmetricBridge :: bridge -> rhs -> VisualConstraint

instance {-# OVERLAPPABLE #-} ConstraintValue rhs =>
         CloseSymmetricBridge SymmetricBridge rhs where
  closeSymmetricBridge bridge rhs =
    case bridge of
      SymmetricBridge lhs delta ->
        VisualSymmetricBridge lhs delta (valueTerm rhs)

class NotEqualOrClose lhs rhs where
  notEqualOrClose :: lhs -> rhs -> VisualConstraint

instance {-# OVERLAPPABLE #-} CloseSymmetricBridge bridge rhs =>
         NotEqualOrClose bridge rhs where
  notEqualOrClose = closeSymmetricBridge

differentCategories ::
     S.ChoiceDomain value
  => CategoryTerm value
  -> CategoryTerm value
  -> VisualConstraint
differentCategories lhs = VisualCategoryRelation lhs CategoryDifferent

instance S.ChoiceDomain value => NotEqualOrClose (S.Choice value) value where
  notEqualOrClose lhs rhs =
    differentCategories (variableCategoryTerm lhs) (fixedCategoryTerm rhs)

instance S.ChoiceDomain value =>
         NotEqualOrClose (S.Choice value) (S.Choice value) where
  notEqualOrClose lhs rhs =
    differentCategories (variableCategoryTerm lhs) (variableCategoryTerm rhs)

instance S.ChoiceDomain value =>
         NotEqualOrClose (SelectionCategory value tag) value where
  notEqualOrClose lhs rhs =
    differentCategories (selectedCategoryValueTerm lhs) (fixedCategoryTerm rhs)

instance S.ChoiceDomain value =>
         NotEqualOrClose (SelectionCategory value tag) (S.Choice value) where
  notEqualOrClose lhs rhs =
    differentCategories
      (selectedCategoryValueTerm lhs)
      (variableCategoryTerm rhs)

instance S.ChoiceDomain value =>
         NotEqualOrClose
           (SelectionCategory value lhsTag)
           (SelectionCategory value rhsTag) where
  notEqualOrClose lhs rhs =
    differentCategories
      (selectedCategoryValueTerm lhs)
      (selectedCategoryValueTerm rhs)

infixl 4 .<=.
infixl 4 .>=.
infixl 4 .==.
infixl 4 =|
infixl 4 |=
infixl 4 =/
infixl 4 /=
(.<=.) :: RelateValues lhs rhs => lhs -> rhs -> VisualConstraint
(.<=.) = relateValues LayoutLessOrEqual

(.>=.) :: RelateValues rhs lhs => lhs -> rhs -> VisualConstraint
lhs .>=. rhs = relateValues LayoutLessOrEqual rhs lhs

(.==.) :: RelateValues lhs rhs => lhs -> rhs -> VisualConstraint
(.==.) = relateValues LayoutEqual

(=|) :: OpenDirectedBridge lhs gap => lhs -> gap -> DirectedBridge
lhs =| rhs = openDirectedBridge lhs rhs

(|=) :: CloseDirectedBridge bridge rhs => bridge -> rhs -> VisualConstraint
lhs |= rhs = closeDirectedBridge lhs rhs

(=/) :: OpenSymmetricBridge lhs delta => lhs -> delta -> SymmetricBridge
lhs =/ delta = openSymmetricBridge lhs delta

(/=) :: NotEqualOrClose lhs rhs => lhs -> rhs -> VisualConstraint
lhs /= rhs = notEqualOrClose lhs rhs

ensure :: VisualConstraint -> VisualizationBuilder ()
ensure = emitConstraint EnsureConstraint

encourage :: VisualConstraint -> VisualizationBuilder ()
encourage = emitConstraint EncourageConstraint

-- | Label one branch of a finite visual decision. Branch constraints remain
-- hard; use ordinary global constraints for the minimum semantic contract.
alternative :: P.String -> [VisualConstraint] -> VisualAlternative
alternative = VisualAlternative

-- | Require exactly one labelled visual alternative. The first alternative is
-- separate so an empty decision cannot be represented.
oneOf ::
     P.String
  -> VisualAlternative
  -> [VisualAlternative]
  -> VisualizationBuilder ()
oneOf name first rest =
  emitVisualizationBuilder
    ()
    (matchFiniteDecision name (P.map compileAlternative (first : rest)))
  where
    compileAlternative (VisualAlternative token constraints) =
      ( token
      , P.foldl
          matchSpecAppend
          emptyMatchSpec
          (P.map (visualConstraintSpec EnsureConstraint) constraints))

-- | Define an exhaustive visual case for an existing typed finite choice.
caseOf ::
     forall value. S.ChoiceDomain value
  => S.Choice value
  -> (value -> [VisualConstraint])
  -> VisualizationBuilder ()
caseOf selected constraintsFor =
  case P.map makeAlternative (S.choiceDomain :: [value]) of
    [] -> P.error "A visual choice domain must contain at least one value."
    first:rest -> oneOf (S.choiceName selected) first rest
  where
    makeAlternative value =
      alternative (S.choiceToken value) (constraintsFor value)

emitConstraint ::
     ConstraintStrength -> VisualConstraint -> VisualizationBuilder ()
emitConstraint strength constraint =
  emitVisualizationBuilder () (visualConstraintSpec strength constraint)

visualConstraintSpec :: ConstraintStrength -> VisualConstraint -> MatchSpec
visualConstraintSpec strength constraint =
  case constraint of
    VisualValueRelation lhs relation rhs ->
      valueTermSpec lhs
        `matchSpecAppend` valueTermSpec rhs
        `matchSpecAppend` matchValueRelation
                            strength
                            (valueTermEndpoints lhs)
                            relation
                            (valueTermEndpoints rhs)
    VisualCategoryRelation lhs relation rhs ->
      categoryTermSpec lhs
        `matchSpecAppend` categoryTermSpec rhs
        `matchSpecAppend` matchCategoryRelation
                            strength
                            (categoryTermEndpoints lhs)
                            relation
                            (categoryTermEndpoints rhs)
    VisualDirectedBridge lhs gap rhs ->
      valueTermSpec lhs
        `matchSpecAppend` valueTermSpec gap
        `matchSpecAppend` valueTermSpec rhs
        `matchSpecAppend` matchValueDirectedBridge
                            strength
                            (valueTermEndpoints lhs)
                            (valueTermEndpoints gap)
                            (valueTermEndpoints rhs)
    VisualSymmetricBridge lhs delta rhs ->
      valueTermSpec lhs
        `matchSpecAppend` valueTermSpec delta
        `matchSpecAppend` valueTermSpec rhs
        `matchSpecAppend` matchValueSymmetricBridge
                            strength
                            (valueTermEndpoints lhs)
                            (valueTermEndpoints delta)
                            (valueTermEndpoints rhs)

valueTermSpec :: ValueTerm -> MatchSpec
valueTermSpec term =
  case term of
    ValueTerm spec _ -> spec

valueTermEndpoints :: ValueTerm -> [ValueExpr]
valueTermEndpoints term =
  case term of
    ValueTerm _ endpoints -> endpoints
