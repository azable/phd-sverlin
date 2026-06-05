{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- {-# LANGUAGE Arrows #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FunctionalDependencies #-}

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
newtype TInt                = TInt Int        deriving (Show, Eq, Ord, Num, Real, Enum, Integral, Typeable)
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

-- One argument operations

data Op1 (name :: Symbol) a b where
  Op1 :: Op1 name a b

op1
  :: forall (name :: Symbol) a b.
     ( KnownSymbol name
     , CType a
     , CType b
     , EvalOp1 name a b
     )
  => Proxy name
  -> Ref a
  -> TraceM (Ref b)
op1 _ rhs =
  let op = Op1 @name @a @b
      result = evalOp1 @name @a @b (valueOf rhs)
  in TCompute1 op rhs ==> result

class EvalOp1 (name :: Symbol) a b where
  evalOp1 :: a -> b

-- Two argument operations
data Op2 (name :: Symbol) a b c where
  Op2 :: Op2 name a b c

op2
  :: forall (name :: Symbol) a b c.
     ( KnownSymbol name
     , CType a
     , CType b
     , CType c
     , EvalOp2 name a b c
     )
  => Ref a
  -> Ref b
  -> TraceM (Ref c)
op2 lhs rhs =
  let op = Op2 @name @a @b @c
      result = evalOp2 (Proxy @name) (valueOf lhs) (valueOf rhs)
  in TCompute2 op lhs rhs ==> result

class EvalOp2 (name :: Symbol) a b c | name a b -> c where
  evalOp2 :: Proxy name -> a -> b -> c

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

-- (.+.) :: (CTypeNumeric a) => Ref a -> Ref a -> TraceM (Ref a)
-- (.+.) = op2 @"+"

-- (.-.) :: (CTypeNumeric a) => Ref a -> Ref a -> TraceM (Ref a)
-- (.-.) = op2 @"-"

-- (.*.) :: (CTypeNumeric a) => Ref a -> Ref a -> TraceM (Ref a)
-- (.*.) = op2 @"*"

-- (./.) :: (CTypeNumeric a, CTypeNumeric b, CTypeNumeric c) => Ref a -> Ref b -> TraceM (Ref c)
-- (./.) = op2 @"/"

instance (CTypeNumeric a) => EvalOp2 "+" a a a where
  evalOp2 _ x y = x + y

instance (CTypeNumeric a) => EvalOp2 "-" a a a where
  evalOp2 _ x y = x - y

instance (CTypeNumeric a) => EvalOp2 "*" a a a where
  evalOp2 _ x y = x * y

instance EvalOp2 "/" TInt TInt TInt where
  evalOp2 _ x y = x `quot` y

instance EvalOp2 "/" TInt TDouble TDouble where
  evalOp2 _ (TInt x) (TDouble y) = TDouble (fromIntegral x / y)

instance EvalOp2 "/" TDouble TInt TDouble where
  evalOp2 _ (TDouble x) (TInt y) = TDouble (x / fromIntegral y)


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
  x <- literal (42 :: TInt)
  y <- literal (10 :: TInt)
  z <- op2 @"/" x y
  writeVar "z" z

--------------------------------------------------------------------------------

instance Show (TraceOp a) where
  show event = case event of
    TLiteral val -> "Literal " ++ show val
    TRead varId sourceRef -> "Read " ++ varId ++ " from " ++ show sourceRef
    TWrite varId targetRef -> "Write " ++ show targetRef ++ " to " ++ varId
    TCompute1 op rhs -> show op ++ " " ++ show rhs
    TCompute2 op lhs rhs -> show lhs ++ " " ++ show op ++ " " ++ show rhs

instance KnownSymbol name => Show (Op1 name a b) where
  show _ = symbolVal (Proxy @name)

instance KnownSymbol name => Show (Op2 name a b c) where
  show _ = symbolVal (Proxy @name)

instance Show (Ref a) where
  show (Ref nid _) = "[Node " ++ show nid ++ "]"

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
