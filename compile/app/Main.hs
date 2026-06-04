{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- {-# LANGUAGE Arrows #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeApplications #-}

module Main where

import Control.Monad.State
import Data.Typeable 
import GHC.TypeLits ( KnownNat, Nat, natVal, Symbol, KnownSymbol, symbolVal )
import qualified Data.Map as Map
import Data.Map (Map)
import Control.Monad

--------------------------------------------------------------------------------
-- Typed C value classes

class (Show a, Typeable a) => CType a where
  getTypeName :: a -> String
  getSize     :: a -> Int

class (CType a, Ord a, Num a) => CTypeNumeric a

-- Types
newtype TInt                = TInt Int        deriving (Show, Eq, Ord, Num, Real, Typeable)
newtype TDouble             = TDouble Double  deriving (Show, Eq, Ord, Num, Real, Typeable)
newtype TArray (n :: Nat) a = TArray [a]      deriving (Show, Eq, Typeable)

instance CTypeNumeric TInt
instance CTypeNumeric TDouble

instance CType TInt where
  getTypeName _ = "int"
  getSize _ = 4

instance CType TDouble where
  getTypeName _ = "double"
  getSize _ = 8

instance (KnownNat n, CType a) => CType (TArray n a) where
  getTypeName _ = getTypeName (undefined :: a)
      ++ "["
      ++ show (natVal (Proxy @n))
      ++ "]"

  getSize _ =
    fromInteger (natVal (Proxy @n)) * getSize (undefined :: a)

-- Run-time variable and value representations

type Ident = String
type NodeId = Int

data Ref a where
  Ref :: (CType a) => NodeId -> a -> Ref a

data TraceNode where
  TraceNode :: (CType a) => NodeId -> TraceOp a -> a -> TraceNode

data AnyRef where
  AnyRef :: (CType a) => Ref a -> AnyRef

data ExecState = ExecState
  { store      :: Map Ident AnyRef
  , nextId     :: NodeId
  , nodes      :: [TraceNode]
  }

type TraceM a = State ExecState a

infixl 0 ==>
(==>) :: (CType a) => TraceOp a -> a -> TraceM (Ref a)
(==>) event value = do
  st <- get

  let nid = nextId st
      node = TraceNode nid event value

  put st
    { nextId = nid + 1
    , nodes = nodes st ++ [node]
    }

  pure (Ref nid value)

data Op1 (name :: Symbol) a b where
  Op1 :: forall name a b. (CType a, CType b) => (a -> b) -> Op1 name a b

evalUnaryOp :: Op1 name a b -> a -> b
evalUnaryOp (Op1 f) = f

op1 :: forall (name :: Symbol) a b. (KnownSymbol name, CType a, CType b) 
    => Proxy name -> (a -> b) -> Ref a -> TraceM (Ref b)
op1 _ f operand =
  let op = Op1 @name f
  in TCompute1 op operand ==> f (valueOf operand)

data Op2 (name :: Symbol) a b c where
  Op2 :: forall name a b c. (CType a, CType b, CType c) => (a -> b -> c) -> Op2 name a b c

evalBinaryOp :: Op2 name a b c -> a -> b -> c
evalBinaryOp (Op2 f) = f

op2 :: forall (name :: Symbol) a b c. (KnownSymbol name, CType a, CType b, CType c)
    => Proxy name -> (a -> b -> c) -> Ref a -> Ref b -> TraceM (Ref c)
op2 _ f lhs rhs =
  let op = Op2 @name f
  in TCompute2 op lhs rhs ==> f (valueOf lhs) (valueOf rhs)

data TraceOp a where
  TLiteral  :: (CType a) => a -> TraceOp a
  TRead     :: (CType a) => Ident -> Ref a -> TraceOp a
  TWrite    :: (CType a) => Ident -> Ref a -> TraceOp a
  TCompute1 :: (KnownSymbol name, CType a, CType b) => Op1 name a b -> Ref a -> TraceOp b
  TCompute2 :: (KnownSymbol name, CType a, CType b, CType c) => Op2 name a b c -> Ref a -> Ref b -> TraceOp c

valueOf :: Ref a -> a
valueOf (Ref _ val) = val

literal :: (CType a) => a -> TraceM (Ref a)
literal value = TLiteral value ==> value

readVar :: (CType a) => Ident -> TraceM (Ref a)
readVar varId = do
  st <- get
  case Map.lookup varId (store st) of
    Just (AnyRef ref) ->
      case cast ref of
        Just typedRef -> TRead varId typedRef ==> valueOf typedRef
        Nothing -> error $ "Type mismatch when reading variable " ++ varId
    Nothing -> error $ "Variable not found: " ++ varId

writeVar :: (CType a) => Ident -> Ref a -> TraceM ()
writeVar varId (Ref sourceId sourceValue) = do
  writeRef <- TWrite varId (Ref sourceId sourceValue) ==> sourceValue
  modify $ \st ->
    st { store = Map.insert varId (AnyRef writeRef) (store st) }

(.+.) :: (CTypeNumeric a) => Ref a -> Ref a -> TraceM (Ref a)
(.+.) = op2 (Proxy @"+") (+)

(.-.) :: (CTypeNumeric a) => Ref a -> Ref a -> TraceM (Ref a)
(.-.) = op2 (Proxy @"-") (-)

(.*.) :: (CTypeNumeric a) => Ref a -> Ref a -> TraceM (Ref a)
(.*.) = op2 (Proxy @"*") (*)

(.>.) :: (CTypeNumeric a) => Ref a -> Ref a -> TraceM (Ref TInt)
(.>.) = op2 (Proxy @">") (\lhs rhs -> if lhs > rhs then 1 else 0)

(.<.) :: (CTypeNumeric a) => Ref a -> Ref a -> TraceM (Ref TInt)
(.<.) = op2 (Proxy @"<") (\lhs rhs -> if lhs < rhs then 1 else 0)

(.!.) :: (CTypeNumeric a) => Ref a -> TraceM (Ref TInt)
(.!.) = op1 (Proxy @"!") (\rhs -> if rhs == 0 then 1 else 0)

(.&&.) :: Ref TInt -> Ref TInt -> TraceM (Ref TInt)
(.&&.) = op2 (Proxy @"&&") (\lhs rhs -> if lhs /= 0 && rhs /= 0 then 1 else 0)

(.||.) :: Ref TInt -> Ref TInt -> TraceM (Ref TInt)
(.||.) = op2 (Proxy @"||") (\lhs rhs -> if lhs /= 0 || rhs /= 0 then 1 else 0)

_if :: TraceM (Ref TInt) -> TraceM () -> TraceM () -> TraceM ()
_if cond trueBranch falseBranch = do
  eCond <- cond
  if valueOf eCond /= 0
    then trueBranch
    else falseBranch

_while :: TraceM (Ref TInt) -> TraceM () -> TraceM ()
_while cond body = do
  eCond <- cond
  when (valueOf eCond /= 0) $ do
    body
    _while cond body

_for :: TraceM () -> TraceM (Ref TInt) -> TraceM () -> TraceM () -> TraceM ()
_for initial cond update body = do
  initial
  _while cond $ do
    body
    update

-- Program

example :: TraceM ()
example = do
  x <- literal (5 :: TInt)
  y <- literal (10 :: TInt)
  z <- x .+. y
  writeVar "z" z

--------------------------------------------------------------------------------

instance Show (TraceOp a) where
  show event = case event of
    TLiteral val -> "Literal " ++ show val
    TRead varId (Ref sourceId _) -> "Read " ++ varId ++ " from Node " ++ show sourceId
    TWrite varId (Ref sourceId _) -> "Write " ++ varId ++ " from Node " ++ show sourceId
    TCompute1 op rhs -> show op ++ "[Node " ++ showNodeId rhs ++ "]"
    TCompute2 op lhs rhs -> "[Node " ++ showNodeId lhs ++ "] " ++ show op ++ " [Node " ++ showNodeId rhs ++ "]"

instance KnownSymbol name => Show (Op1 name a b) where
  show _ = symbolVal (Proxy @name)

instance KnownSymbol name => Show (Op2 name a b c) where
  show _ = symbolVal (Proxy @name)

showNodeId :: Ref a -> String
showNodeId (Ref nid _) = show nid
    
instance Show TraceNode where
  show (TraceNode nid event value) =
    "Node " ++ show nid ++ ": " ++ show event ++ " => " ++ show value


main :: IO ()
main = do
  putStr "Result: "
  let initialState = ExecState
        { store = Map.empty
        , nextId = 0
        , nodes = []
        }
  let (_, finalState) = runState example initialState
  -- print list of trace nodes
  putStrLn "Trace Nodes:"
  mapM_ print (nodes finalState)
