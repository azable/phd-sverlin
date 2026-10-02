{-# LANGUAGE AllowAmbiguousTypes        #-}
{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE FunctionalDependencies     #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE PatternSynonyms            #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# LANGUAGE UndecidableSuperClasses    #-}

-- | The single declarative Render plan used by the authored facade.
--
-- This module deliberately contains the small symbolic vocabulary as well as
-- the plan builder.  Expansion against a semantic trace and lowering to the
-- solver live elsewhere; authored code sees only the abstract handles that
-- 'Sverlin' re-exports.
module Sverlin.Internal.Render
  ( -- * Plan and builder
    Render
  , RenderPlan(..)
  , RenderDiagnostic(..)
  , buildRenderPlan
  , renderPure
  , renderBind
  , renderFail
  , -- * Selection and hierarchy
    Selected
  , Relations
  , GeneratedNode
  , CanvasNode
  , selectKind
  , selectRelation
  , Node(..)
  , self
  , canvas
  , within
  , relation
  , first
  , second
  , -- * Presence and frames
    always
  , sometimes
  , frame
  , -- * Structure
    Ranking
  , FixedInt
  , asSequence
  , asTree
  , asDag
  , rankOf
  , asScalar
  , asText
  , payloadScalar
  , Arrangement(..)
  , arrange
  , -- * Text
    TextBuilder
  , ContentValue
  , text
  , literal
  , fragment
  , FragmentSteps
  , fragmentMany
  , bindContent
  , content
  , -- * Connectors
    ConnectorAnchor(ConnectorAnchor)
  , AnchorPlacement(..)
  , anchor
  , Marker(..)
  , connector
  , startMarker
  , endMarker
  , -- * Numeric values
    RenderVariable
  , freshVariable
  , Coord
  , Span
  , Offset
  , Scalar
  , Unit
  , Angle
  , VisualExpr
  , Vec2(..)
  , vec2
  , at
  , by
  , shift
  , NumExpr(..)
  , (.+.)
  , (.-.)
  , (.*.)
  , (./.)
  , -- * Geometry
    LeftValue(..)
  , TopValue(..)
  , RightValue(..)
  , BottomValue(..)
  , WidthValue(..)
  , HeightValue(..)
  , XValue(..)
  , YValue(..)
  , CenterValue(..)
  , SizeValue(..)
  , Insets
  , uniform
  , symmetric
  , edges
  , padding
  , margin
  , Axis(..)
  , ContentFit(..)
  , contentFit
  , Percent
  , percent
  , xAt
  , yAt
  , widthOf
  , heightOf
  , aspectRatio
  , separatedBy
  , -- * Choices and constraints
    Choice
  , ChoiceDomain
  , freshChoice
  , caseOf
  , VisualConstraint(NumericConstraint, VectorConstraint, SeparationConstraint)
  , ensure
  , (.<=.)
  , (.>=.)
  , (.==.)
  , VisualAlternative
  , alternative
  , oneOf
  , -- * Style
    StyleInput
  , style
  , StyleFieldRead
  , styleOf
  , withoutStyle
  , Opacity
  , FontSize
  , Radius
  , StrokeWidth
  , Alpha
  , Hsl(..)
  , Color
  , Fill
  , Stroke
  , BorderStyle(..)
  , FontKind(..)
  , FontFilter
  , fontKind
  , fontChoice
  , FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , -- * Compiler-facing plan records
    SelectionDeclaration(..)
  , RelationSelectionDeclaration(..)
  , NodeDeclaration(..)
  , NodeTarget(..)
  , Scope(..)
  , PresenceGuard(..)
  , FrameDeclaration(..)
  , RankingDeclaration(..)
  , RankingKind(..)
  , ArrangementDeclaration(..)
  , ConstraintDeclaration(..)
  , NumericExpr(..)
  , NumericRole(..)
  , Comparison(..)
  , NodeReference(..)
  , GeometryAttribute(..)
  , GeometryAssignment(..)
  , InsetsExpr(..)
  , FitDeclaration(..)
  , ContentDeclaration(..)
  , TextPiece(..)
  , TextSource(..)
  , StyleDeclaration(..)
  , StyleFieldName(..)
  , StyleAssignment(..)
  , ChoiceDeclaration(..)
  , ChoiceReference(..)
  , ConnectorDeclaration(..)
  , SelectionId(..)
  , RelationSelectionId(..)
  , NodeDeclarationId(..)
  , RankingId(..)
  , ChoiceId(..)
  , PresenceId(..)
  , ConnectorId(..)
  , PresencePolicy(..)
  , MembershipScope(..)
  , BuilderTarget(..)
  , ArrangementKind(..)
  , InsetsDeclaration(..)
  , InsetsKind(..)
  ) where

import           Control.Monad                (when)
import           Control.Monad.State.Strict   (MonadState, StateT (..),
                                               evalStateT, gets, modify')
import           Data.Kind                    (Constraint, Type)
import           Data.Maybe                   (isJust)
import           Data.Proxy                   (Proxy (..))
import           Data.String                  (IsString (..))
import           Data.Typeable                (Typeable, typeRep)
import           GHC.Exts                     (Multiplicity (Many))
import           Prelude                      hiding (fail)
import           Sverlin.Internal.Render.Font (FontFamily (..), FontKind (..),
                                               allFontFamilies,
                                               fontFamiliesForKind,
                                               fontFamilyToken)
import qualified Sverlin.Syntax               as Syntax

--------------------------------------------------------------------------------
-- Builder state and stable references
--------------------------------------------------------------------------------
newtype RenderDiagnostic = RenderDiagnostic
  { renderDiagnosticMessage :: String
  } deriving stock (Eq, Show)

newtype SelectionId =
  SelectionId Int
  deriving stock (Eq, Ord, Show)

newtype RelationSelectionId =
  RelationSelectionId Int
  deriving stock (Eq, Ord, Show)

newtype NodeDeclarationId =
  NodeDeclarationId Int
  deriving stock (Eq, Ord, Show)

newtype RankingId =
  RankingId Int
  deriving stock (Eq, Ord, Show)

newtype ChoiceId =
  ChoiceId Int
  deriving stock (Eq, Ord, Show)

newtype PresenceId =
  PresenceId Int
  deriving stock (Eq, Ord, Show)

newtype ConnectorId =
  ConnectorId Int
  deriving stock (Eq, Ord, Show)

data PresenceGuard
  = PresenceDecision PresenceId
  | ChoiceDecision ChoiceId String
  | StyleChoiceDecision NodeReference StyleFieldName String
  deriving stock (Eq, Ord, Show)

data PresencePolicy
  = ExplicitAlways
  | ExplicitSometimes PresenceId
  deriving stock (Eq, Show)

data MembershipScope = MembershipScope
  { membershipRelation  :: RelationSelectionId
  , membershipSelection :: SelectionId
  } deriving stock (Eq, Show)

data Scope = Scope
  { scopeParentNode  :: Maybe NodeDeclarationId
  , scopeCurrentNode :: Maybe NodeDeclarationId
  , scopeRelation    :: Maybe RelationSelectionId
  , scopeMemberships :: [MembershipScope]
  , scopeGuards      :: [PresenceGuard]
  } deriving stock (Eq, Show)

rootScope :: Scope
rootScope =
  Scope
    { scopeParentNode = Nothing
    , scopeCurrentNode = Nothing
    , scopeRelation = Nothing
    , scopeMemberships = []
    , scopeGuards = []
    }

data BuilderTarget
  = NodeBuilderTarget NodeReference
  | ConnectorBuilderTarget ConnectorId
  deriving stock (Eq, Show)

data RenderState = RenderState
  { renderNextId             :: Int
  , renderScope              :: Scope
  , renderPresencePolicy     :: Maybe PresencePolicy
  , renderBuilderTarget      :: BuilderTarget
  , renderPresences          :: [(PresenceId, Scope)]
  , renderSelections         :: [SelectionDeclaration]
  , renderRelationSelections :: [RelationSelectionDeclaration]
  , renderNodes              :: [NodeDeclaration]
  , renderFrames             :: [FrameDeclaration]
  , renderRankings           :: [RankingDeclaration]
  , renderArrangements       :: [ArrangementDeclaration]
  , renderConstraints        :: [ConstraintDeclaration]
  , renderGeometry           :: [GeometryAssignment]
  , renderInsets             :: [InsetsDeclaration]
  , renderFits               :: [FitDeclaration]
  , renderContents           :: [ContentDeclaration]
  , renderStyles             :: [StyleDeclaration]
  , renderChoices            :: [ChoiceDeclaration]
  , renderConnectors         :: [ConnectorDeclaration]
  }

initialRenderState :: RenderState
initialRenderState =
  RenderState
    { renderNextId = 0
    , renderScope = rootScope
    , renderPresencePolicy = Nothing
    , renderBuilderTarget = NodeBuilderTarget CanvasReference
    , renderPresences = []
    , renderSelections = []
    , renderRelationSelections = []
    , renderNodes = []
    , renderFrames = []
    , renderRankings = []
    , renderArrangements = []
    , renderConstraints = []
    , renderGeometry = []
    , renderInsets = []
    , renderFits = []
    , renderContents = []
    , renderStyles = []
    , renderChoices = []
    , renderConnectors = []
    }

data RenderPlan = RenderPlan
  { planPresences          :: [(PresenceId, Scope)]
  , planSelections         :: [SelectionDeclaration]
  , planRelationSelections :: [RelationSelectionDeclaration]
  , planNodes              :: [NodeDeclaration]
  , planFrames             :: [FrameDeclaration]
  , planRankings           :: [RankingDeclaration]
  , planArrangements       :: [ArrangementDeclaration]
  , planConstraints        :: [ConstraintDeclaration]
  , planGeometry           :: [GeometryAssignment]
  , planInsets             :: [InsetsDeclaration]
  , planFits               :: [FitDeclaration]
  , planContents           :: [ContentDeclaration]
  , planStyles             :: [StyleDeclaration]
  , planChoices            :: [ChoiceDeclaration]
  , planConnectors         :: [ConnectorDeclaration]
  } deriving stock (Show)

newtype Render value = Render
  { unRender :: StateT RenderState (Either RenderDiagnostic) value
  } deriving newtype (Functor, Applicative, Monad, MonadState RenderState)

instance Syntax.Rebind 'Many Render where
  rebind = renderBind
  repure = renderPure
  refail = renderFail

renderPure :: value -> Render value
renderPure = pure

renderBind :: Render value -> (value -> Render result) -> Render result
renderBind = (>>=)

renderFail :: String -> Render value
renderFail message = Render (StateT (const (Left (RenderDiagnostic message))))

buildRenderPlan :: Render () -> Either RenderDiagnostic RenderPlan
buildRenderPlan action = do
  final <- exec action initialRenderState
  pure
    RenderPlan
      { planPresences = reverse (renderPresences final)
      , planSelections = reverse (renderSelections final)
      , planRelationSelections = reverse (renderRelationSelections final)
      , planNodes = reverse (renderNodes final)
      , planFrames = reverse (renderFrames final)
      , planRankings = reverse (renderRankings final)
      , planArrangements = reverse (renderArrangements final)
      , planConstraints = reverse (renderConstraints final)
      , planGeometry = reverse (renderGeometry final)
      , planInsets = reverse (renderInsets final)
      , planFits = reverse (renderFits final)
      , planContents = reverse (renderContents final)
      , planStyles = reverse (renderStyles final)
      , planChoices = reverse (renderChoices final)
      , planConnectors = reverse (renderConnectors final)
      }
  where
    exec builder = evalStateT (unRender (builder >> gets id))

freshId :: Render Int
freshId = do
  identifier <- gets renderNextId
  modify' $ \state -> state {renderNextId = identifier + 1}
  pure identifier

withStateField ::
     (RenderState -> field)
  -> (field -> RenderState -> RenderState)
  -> field
  -> Render value
  -> Render value
withStateField getField setField replacement action = do
  previous <- gets getField
  modify' (setField replacement)
  result <- action
  modify' (setField previous)
  pure result

withScope :: Scope -> Render value -> Render value
withScope =
  withStateField renderScope (\value state -> state {renderScope = value})

withPolicy :: Maybe PresencePolicy -> Render value -> Render value
withPolicy =
  withStateField
    renderPresencePolicy
    (\value state -> state {renderPresencePolicy = value})

withTarget :: BuilderTarget -> Render value -> Render value
withTarget =
  withStateField
    renderBuilderTarget
    (\value state -> state {renderBuilderTarget = value})

currentScope :: Render Scope
currentScope = gets renderScope

unionGuards :: [PresenceGuard] -> [PresenceGuard] -> [PresenceGuard]
unionGuards = foldl addGuard
  where
    addGuard guards guard
      | guard `elem` guards = guards
      | otherwise = guards ++ [guard]

scopeWithGuards :: [PresenceGuard] -> Scope -> Scope
scopeWithGuards guards scope =
  scope {scopeGuards = unionGuards (scopeGuards scope) guards}

withDependencyGuards :: [PresenceGuard] -> Render value -> Render value
withDependencyGuards guards action = do
  scope <- currentScope
  withScope (scopeWithGuards guards scope) action

-- | Attach a consumed handle's guards to the declaration being built.  A
-- dependency may only become visible after part of a node body has already
-- run, so promotion also updates declarations previously emitted by that
-- component.  Guards already present in the lexical scope (for example a
-- 'caseOf' branch) remain local to that scope rather than making the whole
-- component conditional on one branch.
scopeForDependencies :: [PresenceGuard] -> Render Scope
scopeForDependencies guards = do
  scope <- currentScope
  target <- gets renderBuilderTarget
  let inherited = scopeGuards scope
      promoted = filter (`notElem` inherited) guards
  if null promoted
    then pure (scopeWithGuards guards scope)
    else do
      case target of
        NodeBuilderTarget _ ->
          case scopeCurrentNode scope of
            Nothing -> pure ()
            Just identifier -> do
              state <- gets id
              when (isDirectNodeScope identifier scope state)
                $ modify' (promoteNodeComponent identifier promoted)
        ConnectorBuilderTarget identifier -> do
          state <- gets id
          when (isDirectConnectorScope identifier scope state)
            $ modify' (promoteConnectorComponent identifier promoted)
      scopeWithGuards guards <$> currentScope

isDirectNodeScope :: NodeDeclarationId -> Scope -> RenderState -> Bool
isDirectNodeScope identifier scope state =
  case [ declarationScope
         {scopeParentNode = Just identifier, scopeCurrentNode = Just identifier}
       | declaration <- renderNodes state
       , nodeDeclarationId declaration == identifier
       , let declarationScope = nodeDeclarationScope declaration
       ] of
    [componentScope] -> sameScope componentScope scope
    _                -> False

isDirectConnectorScope :: ConnectorId -> Scope -> RenderState -> Bool
isDirectConnectorScope identifier scope state =
  case [ connectorDeclarationScope declaration
       | declaration <- renderConnectors state
       , connectorDeclarationId declaration == identifier
       ] of
    [componentScope] -> sameScope componentScope scope
    _                -> False

sameScope :: Scope -> Scope -> Bool
sameScope leftScope rightScope =
  leftScope {scopeGuards = []} == rightScope {scopeGuards = []}
    && sameGuards (scopeGuards leftScope) (scopeGuards rightScope)
  where
    sameGuards leftGuards rightGuards =
      all (`elem` rightGuards) leftGuards && all (`elem` leftGuards) rightGuards

promoteNodeComponent ::
     NodeDeclarationId -> [PresenceGuard] -> RenderState -> RenderState
promoteNodeComponent root guards state =
  state
    { renderScope = promoteScope (renderScope state)
    , renderPresences =
        map
          (\(identifier, scope) -> (identifier, promoteScope scope))
          (renderPresences state)
    , renderSelections =
        map
          (\declaration ->
             declaration
               { selectionDeclarationScope =
                   promoteScope (selectionDeclarationScope declaration)
               })
          (renderSelections state)
    , renderRelationSelections =
        map
          (\declaration ->
             declaration
               { relationSelectionDeclarationScope =
                   promoteScope (relationSelectionDeclarationScope declaration)
               })
          (renderRelationSelections state)
    , renderNodes = map promoteNode (renderNodes state)
    , renderFrames =
        map
          (\declaration ->
             declaration {frameScope = promoteScope (frameScope declaration)})
          (renderFrames state)
    , renderRankings =
        map
          (\declaration ->
             declaration
               { rankingDeclarationScope =
                   promoteScope (rankingDeclarationScope declaration)
               })
          (renderRankings state)
    , renderArrangements =
        map
          (\declaration ->
             declaration
               { arrangementDeclarationScope =
                   promoteScope (arrangementDeclarationScope declaration)
               })
          (renderArrangements state)
    , renderConstraints =
        map
          (\declaration ->
             declaration
               { constraintDeclarationScope =
                   promoteScope (constraintDeclarationScope declaration)
               })
          (renderConstraints state)
    , renderGeometry =
        map
          (\declaration ->
             declaration
               { geometryAssignmentScope =
                   promoteScope (geometryAssignmentScope declaration)
               })
          (renderGeometry state)
    , renderInsets =
        map
          (\declaration ->
             declaration
               { insetsDeclarationScope =
                   promoteScope (insetsDeclarationScope declaration)
               })
          (renderInsets state)
    , renderFits =
        map
          (\declaration ->
             declaration
               { fitDeclarationScope =
                   promoteScope (fitDeclarationScope declaration)
               })
          (renderFits state)
    , renderContents =
        map
          (\declaration ->
             declaration
               { contentDeclarationScope =
                   promoteScope (contentDeclarationScope declaration)
               })
          (renderContents state)
    , renderStyles =
        map
          (\declaration ->
             declaration
               { styleDeclarationScope =
                   promoteScope (styleDeclarationScope declaration)
               })
          (renderStyles state)
    , renderChoices =
        map
          (\declaration ->
             declaration
               { choiceDeclarationScope =
                   promoteScope (choiceDeclarationScope declaration)
               })
          (renderChoices state)
    , renderConnectors =
        map
          (\declaration ->
             declaration
               { connectorDeclarationScope =
                   promoteScope (connectorDeclarationScope declaration)
               })
          (renderConnectors state)
    }
  where
    componentNodes = nodeDescendants [root]
    nodeDescendants identifiers =
      let children =
            [ nodeDeclarationId declaration
            | declaration <- renderNodes state
            , scopeCurrentNode (nodeDeclarationScope declaration)
                `elem` map Just identifiers
            ]
          expanded = foldl addIdentifier identifiers children
       in if length expanded == length identifiers
            then identifiers
            else nodeDescendants expanded
    addIdentifier identifiers identifier
      | identifier `elem` identifiers = identifiers
      | otherwise = identifiers ++ [identifier]
    belongsToComponent scope =
      case scopeCurrentNode scope of
        Just identifier -> identifier `elem` componentNodes
        Nothing         -> False
    promoteScope scope
      | belongsToComponent scope = scopeWithGuards guards scope
      | otherwise = scope
    promoteNode declaration
      | nodeDeclarationId declaration `elem` componentNodes
          || belongsToComponent (nodeDeclarationScope declaration) =
        declaration
          { nodeDeclarationScope =
              scopeWithGuards guards (nodeDeclarationScope declaration)
          }
      | otherwise = declaration

promoteConnectorComponent ::
     ConnectorId -> [PresenceGuard] -> RenderState -> RenderState
promoteConnectorComponent identifier guards state =
  state
    { renderScope = scopeWithGuards guards (renderScope state)
    , renderStyles = map promoteStyle (renderStyles state)
    , renderConnectors = map promoteConnector (renderConnectors state)
    }
  where
    promoteStyle declaration
      | styleDeclarationTarget declaration == ConnectorBuilderTarget identifier =
        declaration
          { styleDeclarationScope =
              scopeWithGuards guards (styleDeclarationScope declaration)
          }
      | otherwise = declaration
    promoteConnector declaration
      | connectorDeclarationId declaration == identifier =
        declaration
          { connectorDeclarationScope =
              scopeWithGuards guards (connectorDeclarationScope declaration)
          }
      | otherwise = declaration

--------------------------------------------------------------------------------
-- Selections, nodes, relations, and structural views
--------------------------------------------------------------------------------
data Selected tag = Selected
  { selectedReference :: NodeReference
  , selectedGuardSet  :: [PresenceGuard]
  } deriving stock (Show)

data Relations source target = Relations
  { relationsSelectionId :: RelationSelectionId
  , relationsKindKey     :: String
  , relationsOrdered     :: Bool
  , relationsGuardSet    :: [PresenceGuard]
  } deriving stock (Show)

data GeneratedNode

data CanvasNode

data SelectionDeclaration = SelectionDeclaration
  { selectionDeclarationId      :: SelectionId
  , selectionDeclarationKindKey :: String
  , selectionDeclarationScope   :: Scope
  } deriving stock (Show)

data RelationSelectionDeclaration = RelationSelectionDeclaration
  { relationSelectionDeclarationId      :: RelationSelectionId
  , relationSelectionDeclarationKindKey :: String
  , relationSelectionDeclarationOrdered :: Bool
  , relationSelectionDeclarationScope   :: Scope
  } deriving stock (Show)

data NodeTarget
  = GeneratedNodeTarget
  | SelectedNodeTarget SelectionId
  | RelationEndpointTarget RelationSelectionId Bool
  deriving stock (Eq, Show)

data NodeDeclaration = NodeDeclaration
  { nodeDeclarationId     :: NodeDeclarationId
  , nodeDeclarationTarget :: NodeTarget
  , nodeDeclarationScope  :: Scope
  } deriving stock (Show)

data NodeReference
  = CanvasReference
  | SelectionReference SelectionId
  | GeneratedReference NodeDeclarationId
  | EndpointReference RelationSelectionId Bool
  deriving stock (Eq, Ord, Show)

selectKind :: String -> Render (Selected tag)
selectKind key = do
  identifier <- SelectionId <$> freshId
  scope <- currentScope
  modify' $ \state ->
    state
      { renderSelections =
          SelectionDeclaration identifier key scope : renderSelections state
      }
  pure (Selected (SelectionReference identifier) (scopeGuards scope))

selectRelation :: String -> Bool -> Render (Relations source target)
selectRelation key ordered = do
  identifier <- RelationSelectionId <$> freshId
  scope <- currentScope
  modify' $ \state ->
    state
      { renderRelationSelections =
          RelationSelectionDeclaration identifier key ordered scope
            : renderRelationSelections state
      }
  pure (Relations identifier key ordered (scopeGuards scope))

class Node input result | input -> result where
  node :: input -> result

instance Node (Selected tag) (Render () -> Render ()) where
  node selected body =
    withDependencyGuards (selectedGuardSet selected) $ do
      _ <- declareNode (targetForReference (selectedReference selected)) body
      pure ()

instance Node (Render ()) (Render (Selected GeneratedNode)) where
  node body = do
    identifier <- declareNode GeneratedNodeTarget body
    declarations <- gets renderNodes
    case [ scopeGuards (nodeDeclarationScope declaration)
         | declaration <- declarations
         , nodeDeclarationId declaration == identifier
         ] of
      [guards] -> pure (Selected (GeneratedReference identifier) guards)
      _        -> renderFail "generated node declaration is missing"

declareNode :: NodeTarget -> Render () -> Render NodeDeclarationId
declareNode target body = do
  identifier <- NodeDeclarationId <$> freshId
  outer <- currentScope
  let declaration = NodeDeclaration identifier target outer
      inner =
        outer
          { scopeParentNode = Just identifier
          , scopeCurrentNode = Just identifier
          }
      reference =
        case target of
          GeneratedNodeTarget -> GeneratedReference identifier
          SelectedNodeTarget selection -> SelectionReference selection
          RelationEndpointTarget links isFirst ->
            EndpointReference links isFirst
  modify' $ \state -> state {renderNodes = declaration : renderNodes state}
  withScope inner (withTarget (NodeBuilderTarget reference) body)
  pure identifier

targetForReference :: NodeReference -> NodeTarget
targetForReference reference =
  case reference of
    CanvasReference -> error "the canvas cannot be emitted as a child node"
    SelectionReference identifier -> SelectedNodeTarget identifier
    GeneratedReference _ -> error "a generated node handle cannot be remapped"
    EndpointReference links isFirst -> RelationEndpointTarget links isFirst

self :: Render (Selected GeneratedNode)
self = do
  scope <- currentScope
  case scopeCurrentNode scope of
    Nothing -> renderFail "self is only available inside a node body"
    Just identifier -> do
      declarations <- gets renderNodes
      case [ target
           | NodeDeclaration current target _ <- declarations
           , current == identifier
           ] of
        GeneratedNodeTarget:_ ->
          pure (Selected (GeneratedReference identifier) (scopeGuards scope))
        _ -> renderFail "self is only available inside a generated-node body"

canvas :: Selected CanvasNode
canvas = Selected CanvasReference []

within ::
     Relations owner member -> Selected owner -> Render value -> Render value
within links owners body = do
  outer <- currentScope
  selection <- selectionIdFor "within owner" owners
  let dependencyGuards =
        unionGuards (relationsGuardSet links) (selectedGuardSet owners)
      inner =
        (scopeWithGuards dependencyGuards outer)
          { scopeMemberships =
              MembershipScope (relationsSelectionId links) selection
                : scopeMemberships outer
          }
  withScope inner body

relation :: Relations source target -> Render () -> Render ()
relation links body = do
  outer <- currentScope
  let inner =
        (scopeWithGuards (relationsGuardSet links) outer)
          {scopeRelation = Just (relationsSelectionId links)}
  withScope inner body

first :: Relations source target -> Render (Selected source)
first = relationEndpoint True

second :: Relations source target -> Render (Selected target)
second = relationEndpoint False

relationEndpoint :: Bool -> Relations source target -> Render (Selected node)
relationEndpoint isFirst links = do
  scope <- currentScope
  if scopeRelation scope == Just (relationsSelectionId links)
    then pure
           (Selected
              (EndpointReference (relationsSelectionId links) isFirst)
              (scopeGuards scope))
    else renderFail
           "relation endpoints are only available inside their matching relation scope"

selectionIdFor :: String -> Selected tag -> Render SelectionId
selectionIdFor operation selected =
  case selectedReference selected of
    SelectionReference identifier -> pure identifier
    _ -> renderFail (operation ++ " requires a semantic selection")

data Ranking node =
  Ranking RankingId SelectionId [PresenceGuard]
  deriving stock (Show)

data RankingKind
  = SequenceRanking
  | TreeRanking
  | DagRanking
  deriving stock (Eq, Show)

data RankingDeclaration = RankingDeclaration
  { rankingDeclarationId        :: RankingId
  , rankingDeclarationKind      :: RankingKind
  , rankingDeclarationRelations :: RelationSelectionId
  , rankingDeclarationNodes     :: SelectionId
  , rankingDeclarationScope     :: Scope
  } deriving stock (Show)

data FixedInt =
  FixedInt RankingId NodeDeclarationId [PresenceGuard]
  deriving stock (Show)

asSequence :: Relations node node -> Selected node -> Render (Ranking node)
asSequence = declareRanking SequenceRanking

asTree :: Relations node node -> Selected node -> Render (Ranking node)
asTree = declareRanking TreeRanking

asDag :: Relations node node -> Selected node -> Render (Ranking node)
asDag = declareRanking DagRanking

declareRanking ::
     RankingKind
  -> Relations node node
  -> Selected node
  -> Render (Ranking node)
declareRanking kind links nodes = do
  identifier <- RankingId <$> freshId
  nodeSelection <- selectionIdFor "structural validation" nodes
  let guards = unionGuards (relationsGuardSet links) (selectedGuardSet nodes)
  scope <- scopeForDependencies guards
  modify' $ \state ->
    state
      { renderRankings =
          RankingDeclaration
            identifier
            kind
            (relationsSelectionId links)
            nodeSelection
            scope
            : renderRankings state
      }
  pure (Ranking identifier nodeSelection (scopeGuards scope))

rankOf :: Ranking node -> Render FixedInt
rankOf (Ranking ranking selection guards) = do
  scope <- currentScope
  case scopeCurrentNode scope of
    Nothing -> renderFail "rankOf is only available inside a matching node body"
    Just nodeIdentifier -> do
      targets <- gets renderNodes
      case [ target
           | NodeDeclaration identifier target _ <- targets
           , identifier == nodeIdentifier
           ] of
        SelectedNodeTarget current:_
          | current == selection ->
            pure
              (FixedInt
                 ranking
                 nodeIdentifier
                 (unionGuards guards (scopeGuards scope)))
        _ ->
          renderFail
            "rankOf must be used inside the ranking's selected node mapping"

data Arrangement node
  = ArrangeGrid Int (Vec2 Span)
  | ArrangeLayered (Relations node node) (Vec2 Span)
  | ArrangeRadial (Relations node node) (Vec2 Span)
  | ArrangeTree (Relations node node) (Vec2 Span)

data ArrangementDeclaration = ArrangementDeclaration
  { arrangementDeclarationKind      :: ArrangementKind
  , arrangementDeclarationRelations :: Maybe RelationSelectionId
  , arrangementDeclarationGapX      :: NumericExpr
  , arrangementDeclarationGapY      :: NumericExpr
  , arrangementDeclarationNodes     :: SelectionId
  , arrangementDeclarationScope     :: Scope
  } deriving stock (Show)

data ArrangementKind
  = GridArrangement Int
  | LayeredArrangement
  | RadialArrangement
  | TreeArrangement
  deriving stock (Show)

arrange :: Arrangement node -> Selected node -> Render ()
arrange arrangement nodes = do
  selection <- selectionIdFor "arrange" nodes
  let (kind, links, relationGuards, Vec2 gapX gapY) =
        case arrangement of
          ArrangeGrid columns gap -> (GridArrangement columns, Nothing, [], gap)
          ArrangeLayered relations' gap ->
            ( LayeredArrangement
            , Just (relationsSelectionId relations')
            , relationsGuardSet relations'
            , gap)
          ArrangeRadial relations' gap ->
            ( RadialArrangement
            , Just (relationsSelectionId relations')
            , relationsGuardSet relations'
            , gap)
          ArrangeTree relations' gap ->
            ( TreeArrangement
            , Just (relationsSelectionId relations')
            , relationsGuardSet relations'
            , gap)
      dependencyGuards = unionGuards relationGuards (selectedGuardSet nodes)
      gapGuards = unionGuards (visualExprGuards gapX) (visualExprGuards gapY)
      guards = unionGuards dependencyGuards gapGuards
  scope <- scopeForDependencies guards
  if case kind of
       GridArrangement columns -> columns <= 0
       _                       -> False
    then renderFail "ArrangeGrid requires a positive column count"
    else modify' $ \state ->
           state
             { renderArrangements =
                 ArrangementDeclaration
                   kind
                   links
                   (visualExpr gapX)
                   (visualExpr gapY)
                   selection
                   scope
                   : renderArrangements state
             }

--------------------------------------------------------------------------------
-- Presence and typed frames
--------------------------------------------------------------------------------
always :: Render value -> Render value
always = withPolicy (Just ExplicitAlways)

sometimes :: Render value -> Render value
sometimes body = do
  identifier <- PresenceId <$> freshId
  outer <- currentScope
  modify' $ \state ->
    state {renderPresences = (identifier, outer) : renderPresences state}
  let inner = scopeWithGuards [PresenceDecision identifier] outer
  withPolicy (Just (ExplicitSometimes identifier)) (withScope inner body)

data FrameDeclaration = FrameDeclaration
  { frameStepIdentity :: String
  , frameAlways       :: Bool
  , framePresence     :: Maybe PresenceId
  , frameScope        :: Scope
  } deriving stock (Show)

frame ::
     forall name. Typeable name
  => Render ()
frame = do
  scope <- currentScope
  if isJust (scopeParentNode scope) || isJust (scopeRelation scope)
    then renderFail "frame is only valid at the root of Render"
    else do
      policy <- gets renderPresencePolicy
      case policy of
        Nothing -> renderFail "frame must be wrapped in always or sometimes"
        Just ExplicitAlways -> addFrame True Nothing scope
        Just (ExplicitSometimes presence) ->
          addFrame False (Just presence) scope
  where
    addFrame required presence scope =
      modify' $ \state ->
        state
          { renderFrames =
              FrameDeclaration
                (show (typeRep (Proxy @name)))
                required
                presence
                scope
                : renderFrames state
          }

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------
data TextSource
  = LiteralText String
  | CurrentPayloadText NodeDeclarationId
  | RankingText RankingId NodeDeclarationId
  deriving stock (Eq, Show)

data TextPiece = TextPiece
  { textPieceSource :: TextSource
  , textPieceSteps  :: [String]
  } deriving stock (Eq, Show)

data TextBuilder value =
  TextBuilder value [TextPiece] [PresenceGuard]
  deriving stock (Show)

type ContentValue = TextBuilder ()

instance Functor TextBuilder where
  fmap transform (TextBuilder value pieces guards) =
    TextBuilder (transform value) pieces guards

instance Applicative TextBuilder where
  pure value = TextBuilder value [] []
  TextBuilder function leftPieces leftGuards <*> TextBuilder value rightPieces rightGuards =
    TextBuilder
      (function value)
      (leftPieces ++ rightPieces)
      (unionGuards leftGuards rightGuards)

instance Monad TextBuilder where
  TextBuilder value leftPieces leftGuards >>= continue =
    case continue value of
      TextBuilder result rightPieces rightGuards ->
        TextBuilder
          result
          (leftPieces ++ rightPieces)
          (unionGuards leftGuards rightGuards)

instance Syntax.Rebind 'Many TextBuilder where
  rebind = (>>=)
  repure = pure
  refail message = error ("TextBuilder pattern match failed: " ++ message)

instance Semigroup ContentValue where
  TextBuilder () leftPieces leftGuards <> TextBuilder () rightPieces rightGuards =
    TextBuilder
      ()
      (leftPieces ++ rightPieces)
      (unionGuards leftGuards rightGuards)

instance Monoid ContentValue where
  mempty = TextBuilder () [] []

instance IsString ContentValue where
  fromString = text

text :: String -> ContentValue
text = literal

literal :: String -> TextBuilder ()
literal value = TextBuilder () [TextPiece (LiteralText value) []] []

fragment ::
     forall step. Typeable step
  => String
  -> TextBuilder ()
fragment value =
  TextBuilder
    ()
    [TextPiece (LiteralText value) [show (typeRep (Proxy @step))]]
    []

class FragmentSteps (steps :: [Type]) where
  fragmentStepNames :: Proxy steps -> [String]

instance FragmentSteps '[] where
  fragmentStepNames _ = []

instance (Typeable step, FragmentSteps rest) => FragmentSteps (step : rest) where
  fragmentStepNames _ =
    show (typeRep (Proxy @step)) : fragmentStepNames (Proxy @rest)

fragmentMany ::
     forall steps. FragmentSteps steps
  => String
  -> TextBuilder ()
fragmentMany value =
  case fragmentStepNames (Proxy @steps) of
    []    -> error "fragmentMany requires at least one step type"
    names -> TextBuilder () [TextPiece (LiteralText value) (dedupe names)] []

bindContent :: Render ContentValue
bindContent = do
  scope <- currentScope
  case scopeCurrentNode scope of
    Nothing -> renderFail "bindContent is only available inside a node body"
    Just identifier ->
      pure
        (TextBuilder
           ()
           [TextPiece (CurrentPayloadText identifier) []]
           (scopeGuards scope))

asText :: FixedInt -> ContentValue
asText (FixedInt ranking nodeIdentifier guards) =
  TextBuilder () [TextPiece (RankingText ranking nodeIdentifier) []] guards

data ContentDeclaration = ContentDeclaration
  { contentDeclarationNode   :: NodeReference
  , contentDeclarationPieces :: [TextPiece]
  , contentDeclarationScope  :: Scope
  } deriving stock (Show)

content :: ContentValue -> Render ()
content (TextBuilder () pieces guards) = do
  target <- gets renderBuilderTarget
  scope <- scopeForDependencies guards
  case target of
    ConnectorBuilderTarget _ -> renderFail "connectors cannot contain text"
    NodeBuilderTarget reference -> do
      existing <- gets renderContents
      let sameVisualMapping declaration =
            contentDeclarationNode declaration == reference
              && scopeCurrentNode (contentDeclarationScope declaration)
                   == scopeCurrentNode scope
      if any sameVisualMapping existing
        then renderFail "one node may declare content exactly once"
        else modify' $ \state ->
               state
                 { renderContents =
                     ContentDeclaration reference pieces scope
                       : renderContents state
                 }

dedupe :: Eq value => [value] -> [value]
dedupe =
  foldl
    (\values value ->
       if value `elem` values
         then values
         else values ++ [value])
    []

--------------------------------------------------------------------------------
-- Numeric expression language
--------------------------------------------------------------------------------
data CoordRole

data SpanRole

data OffsetRole

data ScalarRole

data UnitRole

data AngleRole

data VisualExpr valueRole = VisualExpr
  { visualExpr       :: NumericExpr
  , visualExprGuards :: [PresenceGuard]
  } deriving stock (Eq, Show)

type Coord = VisualExpr CoordRole

type Span = VisualExpr SpanRole

type Offset = VisualExpr OffsetRole

type Scalar = VisualExpr ScalarRole

type Unit = VisualExpr UnitRole

type Angle = VisualExpr AngleRole

data Vec2 value =
  Vec2 value value
  deriving stock (Eq, Show)

vec2 :: value -> value -> Vec2 value
vec2 = Vec2

data NumericRole
  = CoordNumeric
  | SpanNumeric
  | OffsetNumeric
  | ScalarNumeric
  | UnitNumeric
  | AngleNumeric
  deriving stock (Eq, Show)

data GeometryAttribute
  = GeometryLeft
  | GeometryTop
  | GeometryRight
  | GeometryBottom
  | GeometryWidth
  | GeometryHeight
  | GeometryX
  | GeometryY
  deriving stock (Eq, Show)

data StyleFieldName
  = OpacityField
  | FontSizeField
  | RadiusField
  | StrokeWidthField
  | AlphaField
  | FillHueField
  | FillSaturationField
  | FillLightnessField
  | StrokeHueField
  | StrokeSaturationField
  | StrokeLightnessField
  | BorderStyleField
  | FontFamilyField
  | FontWeightField
  | FontStyleField
  | TextAlignField
  deriving stock (Eq, Ord, Show)

data NumericExpr
  = NumericConstant Double
  | NumericVariable Int NumericRole
  | NumericNode NodeReference GeometryAttribute
  | NumericRank RankingId NodeDeclarationId
  | NumericPayload NodeReference
  | NumericStyleValue NodeReference StyleFieldName
  | NumericParent NodeReference GeometryAttribute Double
  | NumericAdd NumericExpr NumericExpr
  | NumericSubtract NumericExpr NumericExpr
  | NumericMultiply NumericExpr NumericExpr
  | NumericDivide NumericExpr NumericExpr
  deriving stock (Eq, Show)

class RenderVariable value where
  renderVariableRole :: Proxy value -> NumericRole
  buildRenderVariable :: NumericExpr -> value

instance RenderVariable Coord where
  renderVariableRole _ = CoordNumeric
  buildRenderVariable expression = VisualExpr expression []

instance RenderVariable Span where
  renderVariableRole _ = SpanNumeric
  buildRenderVariable expression = VisualExpr expression []

instance RenderVariable Offset where
  renderVariableRole _ = OffsetNumeric
  buildRenderVariable expression = VisualExpr expression []

instance RenderVariable Scalar where
  renderVariableRole _ = ScalarNumeric
  buildRenderVariable expression = VisualExpr expression []

instance RenderVariable Unit where
  renderVariableRole _ = UnitNumeric
  buildRenderVariable expression = VisualExpr expression []

instance RenderVariable Angle where
  renderVariableRole _ = AngleNumeric
  buildRenderVariable expression = VisualExpr expression []

freshVariable ::
     forall value. RenderVariable value
  => Render value
freshVariable = do
  identifier <- freshId
  pure
    (buildRenderVariable
       (NumericVariable identifier (renderVariableRole (Proxy @value))))

at :: Double -> Coord
at value
  | not (finiteNumeric value) = error "at requires a finite coordinate"
  | value < 0 = error "at requires a non-negative coordinate"
  | otherwise = VisualExpr (NumericConstant value) []

by :: Double -> Span
by value
  | not (finiteNumeric value) = error "by requires a finite span"
  | value < 0 = error "by requires a non-negative span"
  | otherwise = VisualExpr (NumericConstant value) []

shift :: Double -> Offset
shift value
  | not (finiteNumeric value) = error "shift requires a finite offset"
  | otherwise = VisualExpr (NumericConstant value) []

class NumExpr value where
  num :: Double -> value

instance NumExpr Scalar where
  num value
    | not (finiteNumeric value) = error "num requires a finite scalar"
    | otherwise = VisualExpr (NumericConstant value) []

instance NumExpr Unit where
  num value
    | not (finiteNumeric value) || value < 0 || value > 1 =
      error "num requires a Unit from zero through one"
    | otherwise = VisualExpr (NumericConstant value) []

instance NumExpr Angle where
  num value
    | not (finiteNumeric value) || value < 0 || value > 360 =
      error "num requires an Angle from zero through 360"
    | otherwise = VisualExpr (NumericConstant value) []

finiteNumeric :: Double -> Bool
finiteNumeric value = not (isNaN value || isInfinite value)

class AddValue left right result | left right -> result where
  (.+.) :: left -> right -> result

class SubtractValue left right result | left right -> result where
  (.-.) :: left -> right -> result

type family MultiplyCompatibility left right result :: Constraint where
  MultiplyCompatibility (VisualExpr SpanRole) right result = ( right ~ VisualExpr
                                                                 ScalarRole
                                                             , result ~ VisualExpr
                                                                 SpanRole)
  MultiplyCompatibility (VisualExpr OffsetRole) right result = ( right ~ VisualExpr
                                                                   ScalarRole
                                                               , result ~ VisualExpr
                                                                   OffsetRole)
  MultiplyCompatibility (VisualExpr UnitRole) right result = ( right ~ VisualExpr
                                                                 ScalarRole
                                                             , result ~ VisualExpr
                                                                 UnitRole)
  MultiplyCompatibility (VisualExpr AngleRole) right result = ( right ~ VisualExpr
                                                                  ScalarRole
                                                              , result ~ VisualExpr
                                                                  AngleRole)
  MultiplyCompatibility left right result = ()

class MultiplyCompatibility left right result =>
      MultiplyValue left right result
  | left right -> result
  where
  (.*.) :: left -> right -> result

class DivideValue left right result | left -> right result where
  (./.) :: left -> right -> result

infixl 6 .+., .-.
infixl 7 .*., ./.
addExpr :: VisualExpr left -> VisualExpr right -> VisualExpr result
addExpr (VisualExpr lhs leftGuards) (VisualExpr rhs rightGuards) =
  VisualExpr (NumericAdd lhs rhs) (unionGuards leftGuards rightGuards)

subtractExpr :: VisualExpr left -> VisualExpr right -> VisualExpr result
subtractExpr (VisualExpr lhs leftGuards) (VisualExpr rhs rightGuards) =
  VisualExpr (NumericSubtract lhs rhs) (unionGuards leftGuards rightGuards)

multiplyExpr :: VisualExpr left -> VisualExpr right -> VisualExpr result
multiplyExpr (VisualExpr lhs leftGuards) (VisualExpr rhs rightGuards) =
  VisualExpr (NumericMultiply lhs rhs) (unionGuards leftGuards rightGuards)

divideExpr :: VisualExpr left -> VisualExpr right -> VisualExpr result
divideExpr (VisualExpr lhs leftGuards) (VisualExpr rhs rightGuards) =
  VisualExpr (NumericDivide lhs rhs) (unionGuards leftGuards rightGuards)

instance AddValue Coord Span Coord where
  (.+.) = addExpr

instance AddValue Coord Offset Coord where
  (.+.) = addExpr

instance AddValue Span Coord Coord where
  (.+.) = addExpr

instance AddValue Offset Coord Coord where
  (.+.) = addExpr

instance AddValue Span Span Span where
  (.+.) = addExpr

instance AddValue Offset Offset Offset where
  (.+.) = addExpr

instance AddValue Scalar Scalar Scalar where
  (.+.) = addExpr

instance AddValue Unit Unit Unit where
  (.+.) = addExpr

instance AddValue Angle Angle Angle where
  (.+.) = addExpr

instance AddValue value value value =>
         AddValue (Vec2 value) (Vec2 value) (Vec2 value) where
  Vec2 leftX leftY .+. Vec2 rightX rightY =
    Vec2 (leftX .+. rightX) (leftY .+. rightY)

instance SubtractValue Coord Span Coord where
  (.-.) = subtractExpr

instance SubtractValue Coord Offset Coord where
  (.-.) = subtractExpr

instance SubtractValue Coord Coord Offset where
  (.-.) = subtractExpr

instance SubtractValue Span Span Offset where
  (.-.) = subtractExpr

instance SubtractValue Offset Offset Offset where
  (.-.) = subtractExpr

instance SubtractValue Scalar Scalar Scalar where
  (.-.) = subtractExpr

instance SubtractValue Unit Unit Unit where
  (.-.) = subtractExpr

instance SubtractValue Angle Angle Angle where
  (.-.) = subtractExpr

instance SubtractValue left right result =>
         SubtractValue (Vec2 left) (Vec2 right) (Vec2 result) where
  Vec2 leftX leftY .-. Vec2 rightX rightY =
    Vec2 (leftX .-. rightX) (leftY .-. rightY)

instance MultiplyValue Span Scalar Span where
  (.*.) = multiplyExpr

instance MultiplyValue Scalar Span Span where
  (.*.) = multiplyExpr

instance MultiplyValue Offset Scalar Offset where
  (.*.) = multiplyExpr

instance MultiplyValue Scalar Offset Offset where
  (.*.) = multiplyExpr

instance MultiplyValue Scalar Scalar Scalar where
  (.*.) = multiplyExpr

instance MultiplyValue Unit Scalar Unit where
  (.*.) = multiplyExpr

instance MultiplyValue Scalar Unit Unit where
  (.*.) = multiplyExpr

instance MultiplyValue Angle Scalar Angle where
  (.*.) = multiplyExpr

instance MultiplyValue Scalar Angle Angle where
  (.*.) = multiplyExpr

instance DivideValue Span Scalar Span where
  (./.) = divideExpr

instance DivideValue Offset Scalar Offset where
  (./.) = divideExpr

instance DivideValue Scalar Scalar Scalar where
  (./.) = divideExpr

instance DivideValue Unit Scalar Unit where
  (./.) = divideExpr

instance DivideValue Angle Scalar Angle where
  (./.) = divideExpr

asScalar :: FixedInt -> Scalar
asScalar (FixedInt ranking nodeIdentifier guards) =
  VisualExpr (NumericRank ranking nodeIdentifier) guards

payloadScalar :: Selected tag -> Render Scalar
payloadScalar selected =
  pure
    (VisualExpr
       (NumericPayload (selectedReference selected))
       (selectedGuardSet selected))

--------------------------------------------------------------------------------
-- Geometry and box model
--------------------------------------------------------------------------------
nodeNumeric :: Selected tag -> GeometryAttribute -> VisualExpr valueRole
nodeNumeric selected attribute =
  VisualExpr
    (NumericNode (selectedReference selected) attribute)
    (selectedGuardSet selected)

data GeometryAssignment = GeometryAssignment
  { geometryAssignmentTarget    :: NodeReference
  , geometryAssignmentAttribute :: GeometryAttribute
  , geometryAssignmentValue     :: NumericExpr
  , geometryAssignmentScope     :: Scope
  } deriving stock (Show)

setGeometry :: GeometryAttribute -> VisualExpr valueRole -> Render ()
setGeometry attribute (VisualExpr value guards) = do
  target <- gets renderBuilderTarget
  scope <- scopeForDependencies guards
  case target of
    ConnectorBuilderTarget _ ->
      renderFail "connector geometry is derived from its endpoints"
    NodeBuilderTarget reference ->
      modify' $ \state ->
        state
          { renderGeometry =
              GeometryAssignment reference attribute value scope
                : renderGeometry state
          }

class LeftValue input output | input -> output where
  left :: input -> output

class TopValue input output | input -> output where
  top :: input -> output

class RightValue input output | input -> output where
  right :: input -> output

class BottomValue input output | input -> output where
  bottom :: input -> output

class WidthValue input output | input -> output where
  width :: input -> output

class HeightValue input output | input -> output where
  height :: input -> output

class XValue input output | input -> output where
  x :: input -> output

class YValue input output | input -> output where
  y :: input -> output

class CenterValue input output | input -> output where
  center :: input -> output

class SizeValue input output | input -> output where
  size :: input -> output

instance LeftValue (Selected tag) Coord where
  left selected = nodeNumeric selected GeometryLeft

instance LeftValue Coord (Render ()) where
  left = setGeometry GeometryLeft

instance TopValue (Selected tag) Coord where
  top selected = nodeNumeric selected GeometryTop

instance TopValue Coord (Render ()) where
  top = setGeometry GeometryTop

instance RightValue (Selected tag) Coord where
  right selected = nodeNumeric selected GeometryRight

instance RightValue Coord (Render ()) where
  right = setGeometry GeometryRight

instance BottomValue (Selected tag) Coord where
  bottom selected = nodeNumeric selected GeometryBottom

instance BottomValue Coord (Render ()) where
  bottom = setGeometry GeometryBottom

instance WidthValue (Selected tag) Span where
  width selected = nodeNumeric selected GeometryWidth

instance WidthValue Span (Render ()) where
  width = setGeometry GeometryWidth

instance HeightValue (Selected tag) Span where
  height selected = nodeNumeric selected GeometryHeight

instance HeightValue Span (Render ()) where
  height = setGeometry GeometryHeight

instance XValue (Selected tag) Coord where
  x selected = nodeNumeric selected GeometryX

instance XValue Coord (Render ()) where
  x = setGeometry GeometryX

instance YValue (Selected tag) Coord where
  y selected = nodeNumeric selected GeometryY

instance YValue Coord (Render ()) where
  y = setGeometry GeometryY

instance CenterValue (Selected tag) (Vec2 Coord) where
  center selected = Vec2 (x selected) (y selected)

instance CenterValue (Vec2 Coord) (Render ()) where
  center (Vec2 xValue yValue) = x xValue >> y yValue

instance SizeValue (Selected tag) (Vec2 Span) where
  size selected = Vec2 (width selected) (height selected)

data Insets =
  Insets Span Span Span Span
  deriving stock (Eq, Show)

uniform :: Span -> Insets
uniform value = Insets value value value value

symmetric :: Span -> Span -> Insets
symmetric vertical horizontal = Insets vertical horizontal vertical horizontal

edges :: Span -> Span -> Span -> Span -> Insets
edges = Insets

data InsetsExpr =
  InsetsExpr NumericExpr NumericExpr NumericExpr NumericExpr
  deriving stock (Show)

data InsetsKind
  = PaddingInsets
  | MarginInsets
  deriving stock (Show)

data InsetsDeclaration = InsetsDeclaration
  { insetsDeclarationNode  :: NodeReference
  , insetsDeclarationKind  :: InsetsKind
  , insetsDeclarationValue :: InsetsExpr
  , insetsDeclarationScope :: Scope
  } deriving stock (Show)

padding :: Insets -> Render ()
padding = setInsets PaddingInsets

margin :: Insets -> Render ()
margin = setInsets MarginInsets

setInsets :: InsetsKind -> Insets -> Render ()
setInsets kind (Insets topValue rightValue bottomValue leftValue) = do
  target <- gets renderBuilderTarget
  let guards =
        foldl
          unionGuards
          []
          [ visualExprGuards topValue
          , visualExprGuards rightValue
          , visualExprGuards bottomValue
          , visualExprGuards leftValue
          ]
  scope <- scopeForDependencies guards
  case target of
    ConnectorBuilderTarget _ ->
      renderFail "connectors do not have padding or margin"
    NodeBuilderTarget reference ->
      modify' $ \state ->
        state
          { renderInsets =
              InsetsDeclaration
                reference
                kind
                (InsetsExpr
                   (visualExpr topValue)
                   (visualExpr rightValue)
                   (visualExpr bottomValue)
                   (visualExpr leftValue))
                scope
                : renderInsets state
          }

data Axis
  = Horizontal
  | Vertical
  | Both
  deriving stock (Eq, Show)

data ContentFit
  = Hug
  | Contain
  deriving stock (Eq, Show)

data FitDeclaration = FitDeclaration
  { fitDeclarationNode  :: NodeReference
  , fitDeclarationAxis  :: Axis
  , fitDeclarationValue :: ContentFit
  , fitDeclarationScope :: Scope
  } deriving stock (Show)

contentFit :: Axis -> ContentFit -> Render ()
contentFit axis fit = do
  target <- gets renderBuilderTarget
  scope <- currentScope
  case target of
    ConnectorBuilderTarget _ -> renderFail "connectors do not contain children"
    NodeBuilderTarget reference ->
      modify' $ \state ->
        state
          { renderFits =
              FitDeclaration reference axis fit scope : renderFits state
          }

newtype Percent =
  Percent Double
  deriving stock (Eq, Show)

percent :: Double -> Percent
percent value
  | not (finiteNumeric value) || value < 0 || value > 100 =
    error "percent requires a finite value from zero through 100"
  | otherwise = Percent value

data ParentPin
  = ParentX Percent
  | ParentY Percent
  | ParentWidth Percent
  | ParentHeight Percent
  deriving stock (Show)

data GeometryAssignmentValue
  = DirectGeometry NumericExpr
  | ParentGeometry ParentPin
  deriving stock (Show)

xAt :: Percent -> Render ()
xAt = setParentPin GeometryX . ParentX

yAt :: Percent -> Render ()
yAt = setParentPin GeometryY . ParentY

widthOf :: Percent -> Render ()
widthOf = setParentPin GeometryWidth . ParentWidth

heightOf :: Percent -> Render ()
heightOf = setParentPin GeometryHeight . ParentHeight

setParentPin :: GeometryAttribute -> ParentPin -> Render ()
setParentPin attribute pin = do
  target <- gets renderBuilderTarget
  scope <- currentScope
  case target of
    ConnectorBuilderTarget _ ->
      renderFail "connectors cannot use parent-relative geometry"
    NodeBuilderTarget reference ->
      let encoded =
            case pin of
              ParentX (Percent value) ->
                NumericParent reference GeometryX (value / 100)
              ParentY (Percent value) ->
                NumericParent reference GeometryY (value / 100)
              ParentWidth (Percent value) ->
                NumericParent reference GeometryWidth (value / 100)
              ParentHeight (Percent value) ->
                NumericParent reference GeometryHeight (value / 100)
       in modify' $ \state ->
            state
              { renderGeometry =
                  GeometryAssignment reference attribute encoded scope
                    : renderGeometry state
              }

aspectRatio :: Double -> Double -> Render ()
aspectRatio horizontal vertical
  | not (finiteNumeric horizontal && finiteNumeric vertical)
      || horizontal <= 0
      || vertical <= 0 =
    renderFail "aspectRatio requires finite positive values"
  | otherwise = do
    target <- gets renderBuilderTarget
    case target of
      ConnectorBuilderTarget _ -> renderFail "connectors have no aspect ratio"
      NodeBuilderTarget reference ->
        ensure
          (NumericConstraint
             EqualTo
             (NumericNode reference GeometryWidth)
             (NumericMultiply
                (NumericNode reference GeometryHeight)
                (NumericConstant (horizontal / vertical))))

--------------------------------------------------------------------------------
-- Constraints and authored alternatives
--------------------------------------------------------------------------------
data Comparison
  = LessOrEqual
  | GreaterOrEqual
  | EqualTo
  deriving stock (Eq, Show)

data VisualConstraint =
  GuardedVisualConstraint [PresenceGuard] VisualConstraintValue
  deriving stock (Show)

data VisualConstraintValue
  = NumericConstraintValue Comparison NumericExpr NumericExpr
  | VectorConstraintValue Comparison [NumericExpr] [NumericExpr]
  | SeparationConstraintValue NumericExpr NodeReference NodeReference
  deriving stock (Show)

pattern NumericConstraint :: Comparison -> NumericExpr -> NumericExpr -> VisualConstraint
pattern NumericConstraint comparison leftValue rightValue <- GuardedVisualConstraint _ (NumericConstraintValue comparison leftValue rightValue)
  where NumericConstraint comparison leftValue rightValue =
          GuardedVisualConstraint
            []
            (NumericConstraintValue comparison leftValue rightValue)

pattern VectorConstraint :: Comparison -> [NumericExpr] -> [NumericExpr] -> VisualConstraint
pattern VectorConstraint comparison leftValues rightValues <- GuardedVisualConstraint _ (VectorConstraintValue comparison leftValues rightValues)
  where VectorConstraint comparison leftValues rightValues =
          GuardedVisualConstraint
            []
            (VectorConstraintValue comparison leftValues rightValues)

pattern SeparationConstraint :: NumericExpr -> NodeReference -> NodeReference -> VisualConstraint
pattern SeparationConstraint gap firstReference secondReference <- GuardedVisualConstraint _ (SeparationConstraintValue gap firstReference secondReference)
  where SeparationConstraint gap firstReference secondReference =
          GuardedVisualConstraint
            []
            (SeparationConstraintValue gap firstReference secondReference)

{-# COMPLETE NumericConstraint, VectorConstraint, SeparationConstraint #-}
data ConstraintDeclaration = ConstraintDeclaration
  { constraintDeclarationValue :: VisualConstraint
  , constraintDeclarationScope :: Scope
  } deriving stock (Show)

class CompareValues left right | left -> right, right -> left where
  compareValues :: Comparison -> left -> right -> VisualConstraint

instance CompareValues (VisualExpr valueRole) (VisualExpr valueRole) where
  compareValues comparison (VisualExpr leftValue leftGuards) (VisualExpr rightValue rightGuards) =
    GuardedVisualConstraint
      (unionGuards leftGuards rightGuards)
      (NumericConstraintValue comparison leftValue rightValue)

instance CompareValues
           (Vec2 (VisualExpr valueRole))
           (Vec2 (VisualExpr valueRole)) where
  compareValues comparison (Vec2 leftX leftY) (Vec2 rightX rightY) =
    GuardedVisualConstraint
      (foldl
         unionGuards
         []
         [ visualExprGuards leftX
         , visualExprGuards leftY
         , visualExprGuards rightX
         , visualExprGuards rightY
         ])
      (VectorConstraintValue
         comparison
         [visualExpr leftX, visualExpr leftY]
         [visualExpr rightX, visualExpr rightY])

(.<=.) :: CompareValues left right => left -> right -> VisualConstraint
(.<=.) = compareValues LessOrEqual

(.>=.) :: CompareValues left right => left -> right -> VisualConstraint
(.>=.) = compareValues GreaterOrEqual

(.==.) :: CompareValues left right => left -> right -> VisualConstraint
(.==.) = compareValues EqualTo

infix 4 .<=., .>=., .==.
ensure :: VisualConstraint -> Render ()
ensure value@(GuardedVisualConstraint guards _) = do
  scope <- scopeForDependencies guards
  modify' $ \state ->
    state
      { renderConstraints =
          ConstraintDeclaration value scope : renderConstraints state
      }

separatedBy :: Span -> Selected first -> Selected second -> VisualConstraint
separatedBy gap firstNode secondNode =
  GuardedVisualConstraint
    (foldl
       unionGuards
       []
       [ visualExprGuards gap
       , selectedGuardSet firstNode
       , selectedGuardSet secondNode
       ])
    (SeparationConstraintValue
       (visualExpr gap)
       (selectedReference firstNode)
       (selectedReference secondNode))

data VisualAlternative =
  VisualAlternative String (Render ())

alternative :: String -> Render () -> VisualAlternative
alternative = VisualAlternative

oneOf :: String -> VisualAlternative -> [VisualAlternative] -> Render ()
oneOf name firstAlternative remaining = do
  identifier <- ChoiceId <$> freshId
  let alternatives = firstAlternative : remaining
      tokens = [token | VisualAlternative token _ <- alternatives]
  if length tokens /= length (dedupe tokens)
    then renderFail
           ("oneOf " ++ show name ++ " contains duplicate alternative labels")
    else do
      scope <- currentScope
      modify' $ \state ->
        state
          { renderChoices =
              ChoiceDeclaration identifier name tokens scope
                : renderChoices state
          }
      mapM_ (runAlternative identifier) alternatives
  where
    runAlternative identifier (VisualAlternative token action) = do
      outer <- currentScope
      withScope
        (outer
           { scopeGuards =
               scopeGuards outer ++ [ChoiceDecision identifier token]
           })
        action

--------------------------------------------------------------------------------
-- Finite categorical choices
--------------------------------------------------------------------------------
data ChoiceReference
  = DeclaredChoice ChoiceId
  | StyleChoice NodeReference StyleFieldName
  deriving stock (Eq, Show)

data Choice value =
  Choice ChoiceReference [(value, String)] [PresenceGuard]
  deriving stock (Show)

class ChoiceDomain value where
  choiceValues :: [(value, String)]

data ChoiceDeclaration = ChoiceDeclaration
  { choiceDeclarationId     :: ChoiceId
  , choiceDeclarationName   :: String
  , choiceDeclarationTokens :: [String]
  , choiceDeclarationScope  :: Scope
  } deriving stock (Show)

freshChoice ::
     forall value. ChoiceDomain value
  => Render (Choice value)
freshChoice = declareChoice "choice" (choiceValues @value)

declareChoice :: String -> [(value, String)] -> Render (Choice value)
declareChoice label values = do
  identifier <- ChoiceId <$> freshId
  scope <- currentScope
  let tokens = map snd values
  modify' $ \state ->
    state
      { renderChoices =
          ChoiceDeclaration
            identifier
            (label ++ "." ++ showIdentifier identifier)
            tokens
            scope
            : renderChoices state
      }
  pure (Choice (DeclaredChoice identifier) values (scopeGuards scope))
  where
    showIdentifier (ChoiceId value) = show value

caseOf :: Choice value -> (value -> Render ()) -> Render ()
caseOf (Choice reference values guards) branch = mapM_ run values
  where
    run (value, token) = do
      outer <- currentScope
      let guard =
            case reference of
              DeclaredChoice identifier -> ChoiceDecision identifier token
              StyleChoice nodeReference field ->
                StyleChoiceDecision nodeReference field token
      withScope (scopeWithGuards (guards ++ [guard]) outer) (branch value)

--------------------------------------------------------------------------------
-- Styles and colours
--------------------------------------------------------------------------------
data Opacity

data FontSize

data Radius

data StrokeWidth

data Alpha

data Fill

data Stroke

data Hsl hue component where
  Hsl
    :: { hue :: Angle
       , saturation :: Unit
       , lightness :: Unit}
    -> Hsl Angle Unit

deriving stock instance Eq (Hsl hue component)

deriving stock instance Show (Hsl hue component)

type Color = Hsl Angle Unit

data BorderStyle
  = BorderNone
  | BorderSolid
  | BorderDashed
  | BorderDotted
  deriving stock (Eq, Show)

newtype FontFilter =
  FontFilter FontKind
  deriving stock (Eq, Show)

fontKind :: FontKind -> FontFilter
fontKind = FontFilter

data FontWeight
  = FontWeightNormal
  | FontWeightBold
  | FontWeightBolder
  | FontWeightLighter
  | FontWeightNumber Int
  deriving stock (Eq, Show)

data FontStyle
  = FontStyleNormal
  | FontStyleItalic
  deriving stock (Eq, Show)

data TextAlign
  = TextAlignLeft
  | TextAlignCenter
  | TextAlignRight
  deriving stock (Eq, Show)

instance ChoiceDomain BorderStyle where
  choiceValues =
    [ (BorderNone, "none")
    , (BorderSolid, "solid")
    , (BorderDashed, "dashed")
    , (BorderDotted, "dotted")
    ]

instance ChoiceDomain FontWeight where
  choiceValues =
    [(FontWeightNumber value, show value) | value <- [100,200 .. 900]]

instance ChoiceDomain FontStyle where
  choiceValues = [(FontStyleNormal, "normal"), (FontStyleItalic, "italic")]

instance ChoiceDomain TextAlign where
  choiceValues =
    [ (TextAlignLeft, "left")
    , (TextAlignCenter, "center")
    , (TextAlignRight, "right")
    ]

fontChoice :: FontFilter -> Render (Choice FontFamily)
fontChoice (FontFilter kind) = declareChoice "font-family" values
  where
    families = fontFamiliesForKind kind
    values = [(family, fontFamilyToken family) | family <- families]

data StyleAssignment
  = NumericStyle NumericExpr
  | ColorStyle NumericExpr NumericExpr NumericExpr
  | FixedStyle String
  | ChoiceStyle ChoiceReference
  | RemovedStyle
  deriving stock (Show)

data StyleDeclaration = StyleDeclaration
  { styleDeclarationTarget :: BuilderTarget
  , styleDeclarationField  :: StyleFieldName
  , styleDeclarationValue  :: StyleAssignment
  , styleDeclarationScope  :: Scope
  } deriving stock (Show)

type family StyleCompatibility field input :: Constraint where
  StyleCompatibility Opacity input = (input ~ Unit)
  StyleCompatibility FontSize input = (input ~ Span)
  StyleCompatibility Radius input = (input ~ Span)
  StyleCompatibility StrokeWidth input = (input ~ Span)
  StyleCompatibility Alpha input = (input ~ Unit)
  StyleCompatibility Fill input = (input ~ Color)
  StyleCompatibility Stroke input = (input ~ Color)
  StyleCompatibility field input = ()

class StyleCompatibility field input =>
      StyleInput field input
  where
  styleInput :: input -> (StyleFieldName, StyleAssignment, [PresenceGuard])

style ::
     forall field input. StyleInput field input
  => input
  -> Render ()
style input = do
  target <- gets renderBuilderTarget
  let (field, value, guards) = styleInput @field input
  validateStyleTarget target field
  scope <- scopeForDependencies guards
  modify' $ \state ->
    state
      { renderStyles =
          StyleDeclaration target field value scope : renderStyles state
      }

instance StyleInput Opacity Unit where
  styleInput value =
    (OpacityField, NumericStyle (visualExpr value), visualExprGuards value)

instance StyleInput FontSize Span where
  styleInput value =
    (FontSizeField, NumericStyle (visualExpr value), visualExprGuards value)

instance StyleInput Radius Span where
  styleInput value =
    (RadiusField, NumericStyle (visualExpr value), visualExprGuards value)

instance StyleInput StrokeWidth Span where
  styleInput value =
    (StrokeWidthField, NumericStyle (visualExpr value), visualExprGuards value)

instance StyleInput Alpha Unit where
  styleInput value =
    (AlphaField, NumericStyle (visualExpr value), visualExprGuards value)

instance StyleInput Fill Color where
  styleInput (Hsl hueValue saturationValue lightnessValue) =
    ( FillHueField
    , ColorStyle
        (visualExpr hueValue)
        (visualExpr saturationValue)
        (visualExpr lightnessValue)
    , foldl
        unionGuards
        []
        [ visualExprGuards hueValue
        , visualExprGuards saturationValue
        , visualExprGuards lightnessValue
        ])

instance StyleInput Stroke Color where
  styleInput (Hsl hueValue saturationValue lightnessValue) =
    ( StrokeHueField
    , ColorStyle
        (visualExpr hueValue)
        (visualExpr saturationValue)
        (visualExpr lightnessValue)
    , foldl
        unionGuards
        []
        [ visualExprGuards hueValue
        , visualExprGuards saturationValue
        , visualExprGuards lightnessValue
        ])

instance StyleInput BorderStyle BorderStyle where
  styleInput value = (BorderStyleField, FixedStyle (borderToken value), [])

instance StyleInput BorderStyle (Choice BorderStyle) where
  styleInput (Choice reference _ guards) =
    (BorderStyleField, ChoiceStyle reference, guards)

instance StyleInput FontFamily FontFamily where
  styleInput value = (FontFamilyField, FixedStyle (fontFamilyToken value), [])

instance StyleInput FontFamily (Choice FontFamily) where
  styleInput (Choice reference _ guards) =
    (FontFamilyField, ChoiceStyle reference, guards)

instance StyleInput FontWeight FontWeight where
  styleInput value = (FontWeightField, FixedStyle (fontWeightToken value), [])

instance StyleInput FontWeight (Choice FontWeight) where
  styleInput (Choice reference _ guards) =
    (FontWeightField, ChoiceStyle reference, guards)

instance StyleInput FontStyle FontStyle where
  styleInput value = (FontStyleField, FixedStyle (fontStyleToken value), [])

instance StyleInput FontStyle (Choice FontStyle) where
  styleInput (Choice reference _ guards) =
    (FontStyleField, ChoiceStyle reference, guards)

instance StyleInput TextAlign TextAlign where
  styleInput value = (TextAlignField, FixedStyle (textAlignToken value), [])

instance StyleInput TextAlign (Choice TextAlign) where
  styleInput (Choice reference _ guards) =
    (TextAlignField, ChoiceStyle reference, guards)

borderToken :: BorderStyle -> String
borderToken value =
  case value of
    BorderNone   -> "none"
    BorderSolid  -> "solid"
    BorderDashed -> "dashed"
    BorderDotted -> "dotted"

fontWeightToken :: FontWeight -> String
fontWeightToken value =
  case value of
    FontWeightNormal -> "400"
    FontWeightBold -> "700"
    FontWeightBolder -> "bolder"
    FontWeightLighter -> "lighter"
    FontWeightNumber weight
      | weight >= 100 && weight <= 900 && weight `mod` 100 == 0 -> show weight
      | otherwise ->
        error
          "FontWeightNumber requires a supported hundred from 100 through 900"

fontStyleToken :: FontStyle -> String
fontStyleToken value =
  case value of
    FontStyleNormal -> "normal"
    FontStyleItalic -> "italic"

textAlignToken :: TextAlign -> String
textAlignToken value =
  case value of
    TextAlignLeft   -> "left"
    TextAlignCenter -> "center"
    TextAlignRight  -> "right"

class StyleFieldRead field where
  type StyleReadResult field
  styleFieldReadName :: Proxy field -> StyleFieldName
  styleReadValue :: NodeReference -> [PresenceGuard] -> StyleReadResult field

styleOf ::
     forall field node. StyleFieldRead field
  => Selected node
  -> StyleReadResult field
styleOf selected =
  styleReadValue @field (selectedReference selected) (selectedGuardSet selected)

instance StyleFieldRead Opacity where
  type StyleReadResult Opacity = Unit
  styleFieldReadName _ = OpacityField
  styleReadValue reference =
    VisualExpr (NumericStyleValue reference OpacityField)

instance StyleFieldRead FontSize where
  type StyleReadResult FontSize = Span
  styleFieldReadName _ = FontSizeField
  styleReadValue reference =
    VisualExpr (NumericStyleValue reference FontSizeField)

instance StyleFieldRead Radius where
  type StyleReadResult Radius = Span
  styleFieldReadName _ = RadiusField
  styleReadValue reference =
    VisualExpr (NumericStyleValue reference RadiusField)

instance StyleFieldRead StrokeWidth where
  type StyleReadResult StrokeWidth = Span
  styleFieldReadName _ = StrokeWidthField
  styleReadValue reference =
    VisualExpr (NumericStyleValue reference StrokeWidthField)

instance StyleFieldRead Alpha where
  type StyleReadResult Alpha = Unit
  styleFieldReadName _ = AlphaField
  styleReadValue reference = VisualExpr (NumericStyleValue reference AlphaField)

instance StyleFieldRead Fill where
  type StyleReadResult Fill = Hsl Angle Unit
  styleFieldReadName _ = FillHueField
  styleReadValue reference guards =
    Hsl
      (VisualExpr (NumericStyleValue reference FillHueField) guards)
      (VisualExpr (NumericStyleValue reference FillSaturationField) guards)
      (VisualExpr (NumericStyleValue reference FillLightnessField) guards)

instance StyleFieldRead Stroke where
  type StyleReadResult Stroke = Hsl Angle Unit
  styleFieldReadName _ = StrokeHueField
  styleReadValue reference guards =
    Hsl
      (VisualExpr (NumericStyleValue reference StrokeHueField) guards)
      (VisualExpr (NumericStyleValue reference StrokeSaturationField) guards)
      (VisualExpr (NumericStyleValue reference StrokeLightnessField) guards)

instance StyleFieldRead BorderStyle where
  type StyleReadResult BorderStyle = Choice BorderStyle
  styleFieldReadName _ = BorderStyleField
  styleReadValue reference =
    Choice (StyleChoice reference BorderStyleField) (choiceValues @BorderStyle)

instance StyleFieldRead FontFamily where
  type StyleReadResult FontFamily = Choice FontFamily
  styleFieldReadName _ = FontFamilyField
  styleReadValue reference =
    Choice
      (StyleChoice reference FontFamilyField)
      [(family, fontFamilyToken family) | family <- allFontFamilies]

instance StyleFieldRead FontWeight where
  type StyleReadResult FontWeight = Choice FontWeight
  styleFieldReadName _ = FontWeightField
  styleReadValue reference =
    Choice (StyleChoice reference FontWeightField) (choiceValues @FontWeight)

instance StyleFieldRead FontStyle where
  type StyleReadResult FontStyle = Choice FontStyle
  styleFieldReadName _ = FontStyleField
  styleReadValue reference =
    Choice (StyleChoice reference FontStyleField) (choiceValues @FontStyle)

instance StyleFieldRead TextAlign where
  type StyleReadResult TextAlign = Choice TextAlign
  styleFieldReadName _ = TextAlignField
  styleReadValue reference =
    Choice (StyleChoice reference TextAlignField) (choiceValues @TextAlign)

withoutStyle ::
     forall field. StyleFieldRead field
  => Render ()
withoutStyle = do
  target <- gets renderBuilderTarget
  let field = styleFieldReadName (Proxy @field)
  validateStyleTarget target field
  scope <- currentScope
  modify' $ \state ->
    state
      { renderStyles =
          StyleDeclaration target field RemovedStyle scope : renderStyles state
      }

validateStyleTarget :: BuilderTarget -> StyleFieldName -> Render ()
validateStyleTarget target field =
  case target of
    NodeBuilderTarget _ -> pure ()
    ConnectorBuilderTarget _
      | field `elem` [OpacityField, StrokeWidthField, StrokeHueField] -> pure ()
      | otherwise ->
        renderFail
          "connectors support only Opacity, StrokeWidth, and Stroke styles"

--------------------------------------------------------------------------------
-- Connectors
--------------------------------------------------------------------------------
data AnchorPlacement
  = AtCenter
  | AtBoundary
  | AtTop
  | AtRight
  | AtBottom
  | AtLeft
  deriving stock (Eq, Show)

data ConnectorAnchor =
  GuardedConnectorAnchor AnchorPlacement NodeReference [PresenceGuard]
  deriving stock (Eq, Show)

pattern ConnectorAnchor :: AnchorPlacement -> NodeReference -> ConnectorAnchor
pattern ConnectorAnchor placement reference <- GuardedConnectorAnchor placement reference _
  where ConnectorAnchor placement reference =
          GuardedConnectorAnchor placement reference []

{-# COMPLETE ConnectorAnchor #-}
anchor :: AnchorPlacement -> Selected node -> ConnectorAnchor
anchor placement selected =
  GuardedConnectorAnchor
    placement
    (selectedReference selected)
    (selectedGuardSet selected)

data Marker
  = NoMarker
  | ArrowMarker
  | CircleMarker
  | DiamondMarker
  deriving stock (Eq, Show)

data ConnectorDeclaration = ConnectorDeclaration
  { connectorDeclarationId          :: ConnectorId
  , connectorDeclarationStart       :: ConnectorAnchor
  , connectorDeclarationEnd         :: ConnectorAnchor
  , connectorDeclarationScope       :: Scope
  , connectorDeclarationStartMarker :: Marker
  , connectorDeclarationEndMarker   :: Marker
  } deriving stock (Show)

connector :: ConnectorAnchor -> ConnectorAnchor -> Render () -> Render ()
connector start end body = do
  identifier <- ConnectorId <$> freshId
  current <- currentScope
  let startGuards =
        case start of
          GuardedConnectorAnchor _ _ guards -> guards
      endGuards =
        case end of
          GuardedConnectorAnchor _ _ guards -> guards
      scope = scopeWithGuards (unionGuards startGuards endGuards) current
  modify' $ \state ->
    state
      { renderConnectors =
          ConnectorDeclaration identifier start end scope NoMarker NoMarker
            : renderConnectors state
      }
  withScope scope (withTarget (ConnectorBuilderTarget identifier) body)

startMarker :: Marker -> Render ()
startMarker = setMarker True

endMarker :: Marker -> Render ()
endMarker = setMarker False

setMarker :: Bool -> Marker -> Render ()
setMarker isStart marker = do
  target <- gets renderBuilderTarget
  case target of
    NodeBuilderTarget _ ->
      renderFail "connector markers are only valid inside connector"
    ConnectorBuilderTarget identifier ->
      modify' $ \state ->
        state
          {renderConnectors = map (update identifier) (renderConnectors state)}
  where
    update identifier declaration
      | connectorDeclarationId declaration /= identifier = declaration
      | isStart = declaration {connectorDeclarationStartMarker = marker}
      | otherwise = declaration {connectorDeclarationEndMarker = marker}
