{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE GADTs            #-}
{-# LANGUAGE LinearTypes      #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeFamilies     #-}

module DSL
  ( CType(..)
  , Value(..)
  , Op(..)
  , Var(..)
  , Desc(..)
  , G
  , Node
  , VarNode
  , run
  , example
  , declare
  , readVar
  , writeVar
  , discardVar
  , e
  , literal
  , operator
  , (.+.)
  , (.*.)
  ) where

import           Control.Functor.Linear hiding ((<$>), (<*>))
import           LinearTrace
import qualified Prelude                as P
import           Prelude.Linear

data CType
  = CTInt
  | CTDouble

data KValue (ty :: CType)

data Value ty where
  I32 :: Int %1 -> Value 'CTInt
  F64 :: Double %1 -> Value 'CTDouble

data KOp (lhs :: CType) (rhs :: CType) (out :: CType)

data Op lhs rhs out where
  AddI :: Op 'CTInt 'CTInt 'CTInt
  MulI :: Op 'CTInt 'CTInt 'CTInt
  AddD :: Op 'CTDouble 'CTDouble 'CTDouble
  MulD :: Op 'CTDouble 'CTDouble 'CTDouble

data KVar (ty :: CType)

data Var ty where
  Var :: String -> Var ty

type instance Payload (KValue ty) = Value ty

type instance Payload (KOp lhs rhs out) = Op lhs rhs out

type instance Payload (KVar ty) = Var ty

data Desc acts where
  DLiteral :: Desc '[ Create (KValue ty)]
  DOperator :: Desc '[ Create (KOp lhs rhs out)]
  DDeclareVar :: Desc '[ Create (KVar ty), Create (KValue ty)]
  DReadVar :: Desc '[ Observe (KVar ty), Copy (KValue ty)]
  DWriteVar :: Desc '[ Observe (KVar ty), Replace (KValue ty)]
  DEval
    :: Desc
         '[ Use (KValue lhs)
          , Use (KOp lhs rhs out)
          , Use (KValue rhs)
          , Compute (KValue out)
          ]
  DDiscardVar :: Desc '[ Destroy (KVar ty), Destroy (KValue ty)]
  DDiscardValue :: Desc '[ Destroy (KValue ty)]

type Builder ty = GBuilder Desc ty

type Node tag = N tag

data VarNode ty where
  VarNode :: Node (KVar ty) %1 -> Node (KValue ty) %1 -> VarNode ty

declare :: String -> Value ty %1 -> Builder (VarNode ty)
declare name initial = do
  Created valueNode createValue <- create initial
  Created varNode createVar <- create (Var name)
  DDeclareVar `explain` (createVar :~ createValue :~ PaidDebt)
  return (VarNode varNode valueNode)

readVar :: VarNode ty %1 -> Builder (VarNode ty, Node (KValue ty))
readVar (VarNode var held) = do
  Observed var' observeVar <- observe var
  Copied held' copyNode copyHeld <- copy held
  DReadVar `explain` (observeVar :~ copyHeld :~ PaidDebt)
  return (VarNode var' held', copyNode)

writeVar :: VarNode ty %1 -> Node (KValue ty) %1 -> Builder (VarNode ty)
writeVar (VarNode var oldHeld) newValue = do
  Observed var' observeVar <- observe var
  Replaced newHeld replaceHeld <- replace oldHeld newValue
  DWriteVar `explain` (observeVar :~ replaceHeld :~ PaidDebt)
  return (VarNode var' newHeld)

discardVar :: VarNode ty %1 -> Builder ()
discardVar (VarNode var held) = do
  Destroyed destroyVar <- destroy var
  Destroyed destroyHeld <- destroy held
  DDiscardVar `explain` (destroyVar :~ destroyHeld :~ PaidDebt)

eval :: Value lhs %1 -> Op lhs rhs out %1 -> Value rhs %1 -> Value out
eval (I32 x) AddI (I32 y) = I32 (x + y)
eval (I32 x) MulI (I32 y) = I32 (x * y)
eval (F64 x) AddD (F64 y) = F64 (x + y)
eval (F64 x) MulD (F64 y) = F64 (x * y)

e :: Node (KValue lhs)
     %1 -> Node (KOp lhs rhs out)
     %1 -> Node (KValue rhs)
     %1 -> Builder (Node (KValue out))
e lhsNode opNode rhsNode = do
  Used lhs useLhs <- use lhsNode
  Used op useOp <- use opNode
  Used rhs useRhs <- use rhsNode
  Computed outNode computeOut <- compute (eval <$> lhs <*> op <*> rhs)
  DEval `explain` (useLhs :~ useOp :~ useRhs :~ computeOut :~ PaidDebt)
  return outNode

literal :: Value ty %1 -> Builder (Node (KValue ty))
literal val = do
  Created node createVal <- create val
  DLiteral `explain` (createVal :~ PaidDebt)
  return node

operator :: Op lhs rhs out %1 -> Builder (Node (KOp lhs rhs out))
operator op = do
  Created node createOp <- create op
  DOperator `explain` (createOp :~ PaidDebt)
  return node

(.+.) ::
     Node (KValue 'CTInt)
     %1 -> Node (KValue 'CTInt)
     %1 -> Builder (Node (KValue 'CTInt))
(.+.) a b = do
  add <- operator AddI
  e a add b

(.*.) ::
     Node (KValue 'CTInt)
     %1 -> Node (KValue 'CTInt)
     %1 -> Builder (Node (KValue 'CTInt))
(.*.) a b = do
  mul <- operator MulI
  e a mul b

data FibState where
  FibState :: VarNode 'CTInt %1 -> VarNode 'CTInt %1 -> FibState

iterateLinear :: Int -> (state %1 -> Builder state) -> state %1 -> Builder state
iterateLinear n step state'
  | n P.<= 0 = return state'
  | P.otherwise = do
    state'' <- step state'
    iterateLinear (n P.- 1) step state''

fibStep :: FibState %1 -> Builder FibState
fibStep (FibState a0 b0) = do
  (a1, aValue) <- readVar a0
  (b1, bForA) <- readVar b0
  (b2, bForSum) <- readVar b1
  next <- aValue .+. bForSum
  a2 <- writeVar a1 bForA
  b3 <- writeVar b2 next
  return (FibState a2 b3)

example :: Builder ()
example = do
  a0 <- declare "a" (I32 0)
  b0 <- declare "b" (I32 1)
  final <- iterateLinear 5 fibStep (FibState a0 b0)
  case final of
    FibState aN bN -> do
      discardVar aN
      discardVar bN

run :: Builder () -> G Desc
run = buildGraph

padRight :: Int -> String -> String
padRight n s = s ++ replicate (n - P.length s) ' '

padRightF :: String -> String
padRightF = padRight 5

instance P.Show (Value ty) where
  show (I32 i) = padRightF "Val" ++ P.show i
  show (F64 f) = padRightF "Val" ++ P.show f

instance P.Show (Op lhs rhs out) where
  show AddI = padRightF "Op" ++ "AddI"
  show MulI = padRightF "Op" ++ "MulI"
  show AddD = padRightF "Op" ++ "AddD"
  show MulD = padRightF "Op" ++ "MulD"

instance P.Show (Var ty) where
  show (Var name) = padRightF "Var" ++ name

instance ShowDesc Desc where
  showDesc DLiteral      = "Literal"
  showDesc DOperator     = "Operator"
  showDesc DDeclareVar   = "DeclareVar"
  showDesc DReadVar      = "ReadVar"
  showDesc DWriteVar     = "WriteVar"
  showDesc DEval         = "Eval"
  showDesc DDiscardVar   = "DiscardVar"
  showDesc DDiscardValue = "DiscardValue"
