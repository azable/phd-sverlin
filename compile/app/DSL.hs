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
  , G(..)
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
import           NodeBase
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

type Builder = GBuilder Desc

type Node tag = N tag

data VarNode ty where
  VarNode :: Node (KVar ty) %1 -> Node (KValue ty) %1 -> VarNode ty

declare :: String -> Value ty %1 -> Builder (VarNode ty)
declare name initial = do
  Created valueNode createValue <- create initial
  Created varNode createVar <- create (Var name)
  explain DDeclareVar (createVar :~ createValue :~ PaidDebt)
  return (VarNode varNode valueNode)

readVar :: VarNode ty %1 -> Builder (VarNode ty, Node (KValue ty))
readVar (VarNode var held) = do
  Observed var' observeVar <- observe var
  Copied held' copyNode copyHeld <- copy held
  explain DReadVar (observeVar :~ copyHeld :~ PaidDebt)
  return (VarNode var' held', copyNode)

writeVar :: VarNode ty %1 -> Node (KValue ty) %1 -> Builder (VarNode ty)
writeVar (VarNode var oldHeld) newValue = do
  Observed var' observeVar <- observe var
  Replaced newHeld replaceHeld <- replace oldHeld newValue
  explain DWriteVar (observeVar :~ replaceHeld :~ PaidDebt)
  return (VarNode var' newHeld)

discardVar :: VarNode ty %1 -> Builder ()
discardVar (VarNode var held) = do
  Destroyed destroyVar <- destroy var
  Destroyed destroyHeld <- destroy held
  explain DDiscardVar (destroyVar :~ destroyHeld :~ PaidDebt)

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
  explain DEval (useLhs :~ useOp :~ useRhs :~ computeOut :~ PaidDebt)
  return outNode

literal :: Value ty %1 -> Builder (Node (KValue ty))
literal val = do
  Created node literalO <- create val
  explain DLiteral (literalO :~ PaidDebt)
  return node

operator :: Op lhs rhs out %1 -> Builder (Node (KOp lhs rhs out))
operator op = do
  Created node opO <- create op
  explain DOperator (opO :~ PaidDebt)
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

example :: Builder ()
example = do
  x0 <- declare "x" (I32 10)
  (x1, a) <- readVar x0
  b <- literal (I32 20)
  c <- a .+. b
  x2 <- writeVar x1 c
  (x3, n5) <- readVar x2
  discardVar x3
  Destroyed n5O <- destroy n5
  explain DDiscardValue (n5O :~ PaidDebt)

run :: Builder () -> G Desc
run = buildGraph

padRight :: Int -> String -> String
padRight n s = s ++ replicate (n - P.length s) ' '

padRightF :: String -> String
padRightF = padRight 8

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
