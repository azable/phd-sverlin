{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE TypeApplications    #-}

-- | Automatic, family-coherent styles for body-only Sverlin programs.
-- Authored required and forbidden fields take precedence; this module only
-- installs plans for fields that remain unspecified after matching and access.
module LinearTrace.View.StyleProfile
  ( applyGenerativeStyleProfiles
  ) where

import           LinearTrace.View.Graph
import           LinearTrace.View.Primitives
import qualified LinearTrace.View.Style      as Style
import           Prelude
import qualified Solver                      as S

data LeafProfile
  = LeafTransparent
  | LeafOutline
  | LeafFlat
  | LeafSoftCard
  | LeafPill
  deriving (Eq, Show)

instance S.ChoiceDomain LeafProfile where
  choiceDomain =
    [LeafTransparent, LeafOutline, LeafFlat, LeafSoftCard, LeafPill]
  choiceToken profile =
    case profile of
      LeafTransparent -> "transparent"
      LeafOutline     -> "outline"
      LeafFlat        -> "flat"
      LeafSoftCard    -> "soft-card"
      LeafPill        -> "pill"

data AutomaticFontFace
  = AutomaticInter
  | AutomaticSourceSans3
  | AutomaticAtkinson
  | AutomaticSpaceGrotesk
  | AutomaticSourceSerif4
  | AutomaticLiterata
  | AutomaticJetBrainsMono
  | AutomaticIBMPlexMono
  deriving (Eq, Show)

instance S.ChoiceDomain AutomaticFontFace where
  choiceDomain =
    [ AutomaticInter
    , AutomaticSourceSans3
    , AutomaticAtkinson
    , AutomaticSpaceGrotesk
    , AutomaticSourceSerif4
    , AutomaticLiterata
    , AutomaticJetBrainsMono
    , AutomaticIBMPlexMono
    ]
  choiceToken face =
    case face of
      AutomaticInter         -> "inter"
      AutomaticSourceSans3   -> "source-sans-3"
      AutomaticAtkinson      -> "atkinson-hyperlegible-next"
      AutomaticSpaceGrotesk  -> "space-grotesk"
      AutomaticSourceSerif4  -> "source-serif-4"
      AutomaticLiterata      -> "literata"
      AutomaticJetBrainsMono -> "jetbrains-mono-nl"
      AutomaticIBMPlexMono   -> "ibm-plex-mono"

data AutomaticFontWeight
  = AutomaticWeight400
  | AutomaticWeight500
  | AutomaticWeight600
  deriving (Eq, Show)

instance S.ChoiceDomain AutomaticFontWeight where
  choiceDomain = [AutomaticWeight400, AutomaticWeight500, AutomaticWeight600]
  choiceToken weight =
    case weight of
      AutomaticWeight400 -> "400"
      AutomaticWeight500 -> "500"
      AutomaticWeight600 -> "600"

data GroupProfile
  = GroupInvisible
  | GroupSquareOutline
  | GroupRoundedOutline
  | GroupSoftPanel
  deriving (Eq, Show)

instance S.ChoiceDomain GroupProfile where
  choiceDomain =
    [GroupInvisible, GroupSquareOutline, GroupRoundedOutline, GroupSoftPanel]
  choiceToken profile =
    case profile of
      GroupInvisible      -> "invisible"
      GroupSquareOutline  -> "square-outline"
      GroupRoundedOutline -> "rounded-outline"
      GroupSoftPanel      -> "soft-panel"

applyGenerativeStyleProfiles :: [ViewNode] -> [ViewNode]
applyGenerativeStyleProfiles = map applyProfile

applyProfile :: ViewNode -> ViewNode
applyProfile wrapped =
  case wrapped of
    ViewNode node ->
      let family = styleFamilyKey node
          (style', constraints) =
            case nodeStructure node of
              LeafNode         -> leafStyle family (nodeStyle node)
              CompoundNode _ _ -> groupStyle family (nodeStyle node)
       in ViewNode
            node
              { nodeStyle = style'
              , nodeConstraints = constraints ++ nodeConstraints node
              }

styleFamilyKey :: Node tag -> String
styleFamilyKey node =
  stableKey
    (case Style.nodeStyleFamily (nodeStyle node) of
       Just explicit -> structurePrefix node ++ ":explicit:" ++ explicit
       Nothing ->
         case nodeOrigin node of
           TraceOrigin _ -> "leaf:payload:" ++ viewLabelKind (nodeLabel node)
           GeneratedOrigin meta -> "group:generated:" ++ generatedKey meta)

structurePrefix :: Node tag -> String
structurePrefix node =
  case nodeStructure node of
    LeafNode         -> "leaf"
    CompoundNode _ _ -> "group"

leafStyle :: String -> Style.NodeStyle -> (Style.NodeStyle, [S.Constraint])
leafStyle family style0 =
  ( style10
  , concat
      [ constraintsWhenMissing @Style.Fill style0 (fillConstraints fill)
      , constraintsWhenMissing @Style.Stroke style0 (strokeConstraints stroke)
      , constraintsWhenMissing @Style.Radius
          style0
          [S.within softRadius (S.Range 6 16)]
      ])
  where
    base = "view.style.family." ++ family ++ ".leaf"
    profile = S.choice (base ++ ".profile")
    fontFace = S.choice "view.style.typography.font-face"
    occupancy = S.choice "view.style.typography.occupancy"
    fontWeight = S.choice (base ++ ".font-weight")
    fill = familyFill base
    stroke = familyStroke base
    softRadius = S.var (base ++ ".soft-card.radius") :: LayoutExpr
    style1 = conditionalWhenMissing @Style.Fill profile (leafFill fill) style0
    style2 =
      conditionalWhenMissing @Style.Stroke profile (leafStroke stroke) style1
    style3 =
      conditionalWhenMissing @Style.StrokeWidth profile leafStrokeWidth style2
    style4 =
      conditionalWhenMissing @Style.BorderStyle profile leafBorderStyle style3
    style5 = conditionalWhenMissing @Style.Padding profile leafPadding style4
    style6 =
      conditionalWhenMissing @Style.Radius
        profile
        (leafRadius softRadius style0)
        style5
    style7 =
      conditionalWhenMissing @Style.FontFamily
        fontFace
        automaticFontFamily
        style6
    style8
      | Style.hasStyleField @Style.FontSize style0 = style7
      | otherwise =
        conditionalWhenMissing @Style.TextOccupancy
          occupancy
          (Just . S.num . Style.textOccupancyRatio)
          style7
    style9 =
      conditionalWhenMissing @Style.FontWeight
        fontWeight
        automaticFontWeight
        style8
    style10 =
      conditionalWhenMissing @Style.TextAlign profile leafTextAlign style9

groupStyle :: String -> Style.NodeStyle -> (Style.NodeStyle, [S.Constraint])
groupStyle family style0 =
  ( style6
  , constraintsWhenMissing @Style.Fill style0 (fillConstraints fill)
      ++ constraintsWhenMissing @Style.Stroke style0 (strokeConstraints stroke))
  where
    base = "view.style.family." ++ family ++ ".group"
    profile = S.choice (base ++ ".profile")
    fill = familyFill base
    stroke = familyStroke base
    style1 = conditionalWhenMissing @Style.Fill profile (groupFill fill) style0
    style2 =
      conditionalWhenMissing @Style.Stroke profile (groupStroke stroke) style1
    style3 =
      conditionalWhenMissing @Style.StrokeWidth profile groupStrokeWidth style2
    style4 =
      conditionalWhenMissing @Style.BorderStyle profile groupBorderStyle style3
    style5 = conditionalWhenMissing @Style.Radius profile groupRadius style4
    style6 = conditionalWhenMissing @Style.ZIndex profile groupZIndex style5

conditionalWhenMissing ::
     forall field value. (Style.StyleField field, S.ChoiceDomain value)
  => S.Choice value
  -> (value -> Maybe (Style.StyleValue field))
  -> Style.NodeStyle
  -> Style.NodeStyle
conditionalWhenMissing selected valueFor style'
  | Style.hasStyleField @field style' = style'
  | otherwise = Style.setConditionalStyleField @field selected valueFor style'

constraintsWhenMissing ::
     forall field. Style.StyleField field
  => Style.NodeStyle
  -> [S.Constraint]
  -> [S.Constraint]
constraintsWhenMissing style' constraints
  | Style.hasStyleField @field style' = []
  | otherwise = constraints

familyFill :: String -> ColorExpr
familyFill base =
  Hsl
    (S.var (base ++ ".fill.hue"))
    (S.var (base ++ ".fill.saturation"))
    (S.var (base ++ ".fill.lightness"))

familyStroke :: String -> ColorExpr
familyStroke base =
  Hsl
    (S.var (base ++ ".fill.hue"))
    (S.var (base ++ ".stroke.saturation"))
    (S.var (base ++ ".stroke.lightness"))

fillConstraints :: ColorExpr -> [S.Constraint]
fillConstraints color =
  [ S.within (saturation color) (S.Range 0.25 0.65)
  , S.within (lightness color) (S.Range 0.84 0.96)
  ]

strokeConstraints :: ColorExpr -> [S.Constraint]
strokeConstraints color =
  [ S.within (saturation color) (S.Range 0.35 0.75)
  , S.within (lightness color) (S.Range 0.25 0.5)
  ]

leafFill :: ColorExpr -> LeafProfile -> Maybe ColorExpr
leafFill color profile =
  case profile of
    LeafFlat     -> Just color
    LeafSoftCard -> Just color
    LeafPill     -> Just color
    _            -> Nothing

leafStroke :: ColorExpr -> LeafProfile -> Maybe ColorExpr
leafStroke color profile =
  case profile of
    LeafOutline -> Just color
    _           -> Nothing

leafStrokeWidth :: LeafProfile -> Maybe LayoutExpr
leafStrokeWidth profile =
  case profile of
    LeafOutline -> Just (S.num 1.5)
    _           -> Nothing

leafBorderStyle :: LeafProfile -> Maybe (S.ChoiceValue Style.BorderStyle)
leafBorderStyle profile =
  case profile of
    LeafOutline -> Just (S.Fixed Style.BorderSolid)
    _           -> Nothing

leafPadding :: LeafProfile -> Maybe LayoutExpr
leafPadding profile =
  case profile of
    LeafOutline  -> Just (S.num 4)
    LeafFlat     -> Just (S.num 4)
    LeafSoftCard -> Just (S.num 6)
    LeafPill     -> Just (S.num 6)
    _            -> Nothing

leafRadius :: LayoutExpr -> Style.NodeStyle -> LeafProfile -> Maybe LayoutExpr
leafRadius softRadius style' profile =
  case profile of
    LeafSoftCard -> Just softRadius
    LeafPill     -> Just (height style' S.@/@ S.num 2)
    _            -> Nothing

automaticFontFamily ::
     AutomaticFontFace -> Maybe (S.ChoiceValue Style.FontFamily)
automaticFontFamily face =
  Just
    (S.Fixed
       (case face of
          AutomaticInter         -> Style.FontInter
          AutomaticSourceSans3   -> Style.FontSourceSans3
          AutomaticAtkinson      -> Style.FontAtkinsonHyperlegibleNext
          AutomaticSpaceGrotesk  -> Style.FontSpaceGrotesk
          AutomaticSourceSerif4  -> Style.FontSourceSerif4
          AutomaticLiterata      -> Style.FontLiterata
          AutomaticJetBrainsMono -> Style.FontJetBrainsMonoNL
          AutomaticIBMPlexMono   -> Style.FontIBMPlexMono))

automaticFontWeight ::
     AutomaticFontWeight -> Maybe (S.ChoiceValue Style.FontWeight)
automaticFontWeight weight =
  Just
    (S.Fixed
       (Style.FontWeightNumber
          (case weight of
             AutomaticWeight400 -> 400
             AutomaticWeight500 -> 500
             AutomaticWeight600 -> 600)))

leafTextAlign :: LeafProfile -> Maybe (S.ChoiceValue Style.TextAlign)
leafTextAlign profile =
  Just
    (S.Fixed
       (case profile of
          LeafTransparent -> Style.TextAlignLeft
          _               -> Style.TextAlignCenter))

groupFill :: ColorExpr -> GroupProfile -> Maybe ColorExpr
groupFill color profile =
  case profile of
    GroupSoftPanel -> Just color
    _              -> Nothing

groupStroke :: ColorExpr -> GroupProfile -> Maybe ColorExpr
groupStroke color profile =
  case profile of
    GroupSquareOutline  -> Just color
    GroupRoundedOutline -> Just color
    _                   -> Nothing

groupStrokeWidth :: GroupProfile -> Maybe LayoutExpr
groupStrokeWidth profile =
  case profile of
    GroupSquareOutline  -> Just (S.num 1.5)
    GroupRoundedOutline -> Just (S.num 1.5)
    _                   -> Nothing

groupBorderStyle :: GroupProfile -> Maybe (S.ChoiceValue Style.BorderStyle)
groupBorderStyle profile =
  case profile of
    GroupSquareOutline  -> Just (S.Fixed Style.BorderSolid)
    GroupRoundedOutline -> Just (S.Fixed Style.BorderSolid)
    _                   -> Nothing

groupRadius :: GroupProfile -> Maybe LayoutExpr
groupRadius profile =
  case profile of
    GroupRoundedOutline -> Just (S.num 10)
    GroupSoftPanel      -> Just (S.num 10)
    _                   -> Nothing

groupZIndex :: GroupProfile -> Maybe FreeExpr
groupZIndex profile =
  case profile of
    GroupInvisible -> Nothing
    _              -> Just (S.num (-1))
