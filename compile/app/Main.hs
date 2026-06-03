{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- {-# LANGUAGE Arrows #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}

module Main where

-- import Control.Monad.State
import Control.Monad.Free ( Free(..), liftF )
import Data.Typeable 
import GHC.TypeLits ( KnownNat, Nat, natVal )
import Control.Monad ( join )
import qualified Data.Map as Map
import Data.Map (Map)

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
newtype MemAddress a = MemAddress Int deriving (Eq, Ord, Show)

data Value a where
  Value    :: (CType a) => a -> Value a

instance Show (Value a) where
  show (Value a) = show a

data Variable a where
  Variable :: (CType a) => a -> MemAddress a -> Variable a

data Op r where
  Add :: (CTypeNumeric a) => Value a -> Value a -> Op a
  Sub :: (CTypeNumeric a) => Value a -> Value a -> Op a
  Mul :: (CTypeNumeric a) => Value a -> Value a -> Op a
  Gt  :: (CTypeNumeric a) => Value a -> Value a -> Op TInt
  Lt  :: (CTypeNumeric a) => Value a -> Value a -> Op TInt
  Eq  :: (CTypeNumeric a) => Value a -> Value a -> Op TInt

instance Show (Op r) where
  show op =
    case op of
      Add (Value a) (Value b) -> show a ++ " + " ++ show b
      Sub (Value a) (Value b) -> show a ++ " - " ++ show b
      Mul (Value a) (Value b) -> show a ++ " * " ++ show b
      Gt  (Value a) (Value b) -> show a ++ " > " ++ show b
      Lt  (Value a) (Value b) -> show a ++ " < " ++ show b
      Eq  (Value a) (Value b) -> show a ++ " == " ++ show b

data Instr next where
  Literal :: (CType a) => Value a    -> (Value a -> next) -> Instr next
  Read    :: (CType a) => MemAddress a -> (Value a -> next) -> Instr next
  Write   :: (CType a) => MemAddress a ->  Value a -> next  -> Instr next
  Compute :: (CType r) => Op r       -> (Value r -> next) -> Instr next
  Branch  ::              Value TInt -> next     -> next  -> Instr next

instance Functor Instr where
  fmap f instr =
    case instr of
      Literal value k                -> Literal value (f . k)
      Read    addr k                 -> Read addr (f . k)
      Write   addr value next        -> Write addr value (f next)
      Compute op k                   -> Compute op (f . k)
      Branch  cond thenNext elseNext -> Branch cond (f thenNext) (f elseNext)

type Program a = Free Instr a

literal  :: (CType a) => Value a -> Program (Value a)
literal value = liftF (Literal value id)

readVar  :: (CType a) => MemAddress a -> Program (Value a)
readVar addr = liftF (Read addr id)

writeVar :: (CType a) => MemAddress a -> Value a -> Program ()
writeVar addr value = liftF (Write addr value ())

compute  :: (CType r) => Op r -> Program (Value r)
compute op = liftF (Compute op id)

branch   :: Value TInt -> Program () -> Program () -> Program ()
branch cond thenProg elseProg =
  join (liftF (Branch cond thenProg elseProg))

type NodeId = Int

data TraceAction where
  TraceLiteral :: Value a -> TraceAction
  TraceRead    :: MemAddress a -> Value a -> TraceAction
  TraceWrite   :: MemAddress a -> Value a -> Maybe (Value a) -> TraceAction
  TraceCompute :: Op r -> Value r -> TraceAction
  TraceBranch  :: Bool -> TraceAction

data TraceNode = TraceNode
  { traceNodeId :: NodeId
  , traceAction :: TraceAction
  }

instance Show TraceNode where
  show (TraceNode nid action) =
    "Node " ++ show nid ++ ": " ++ case action of
      TraceLiteral value -> "Literal " ++ show value
      TraceRead addr value -> "Read from " ++ show addr ++ ": " ++ show value
      TraceWrite addr newValue oldValue ->
        "Write to " ++ show addr ++ ": " ++ show newValue ++
        case oldValue of
          Nothing -> " (no previous value)"
          Just v  -> " (previous value: " ++ show v ++ ")"
      TraceCompute op result -> "Compute " ++ show op ++ ": " ++ show result
      TraceBranch cond -> "Branch on condition: " ++ show cond

data TraceGraph = TraceGraph
  { traceNodes :: [TraceNode]
  , traceEdges :: [(NodeId, NodeId)]
  }

data AnyValue where
  AnyValue :: (CType a) => Value a -> AnyValue

castAnyValue :: CType a => AnyValue -> Maybe (Value a)
castAnyValue (AnyValue value) = cast value

data ExecState = ExecState
  { store      :: Map Int AnyValue
  , nextNodeId :: NodeId
  , prevNodeId :: Maybe NodeId
  , graph      :: TraceGraph
  }

addrKey :: MemAddress a -> Int
addrKey (MemAddress i) = i

storeInsert :: CType a => MemAddress a -> Value a -> ExecState -> ExecState
storeInsert addr value st =
  st { store = Map.insert (addrKey addr) (AnyValue value) (store st) }

storeLookup :: CType a => MemAddress a -> ExecState -> Maybe (Value a)
storeLookup addr st = do
  anyValue <- Map.lookup (addrKey addr) (store st)
  castAnyValue anyValue

addTraceNode :: TraceAction -> ExecState -> (NodeId, ExecState)
addTraceNode action st =
  let nid = nextNodeId st

      node = TraceNode
          { traceNodeId = nid
          , traceAction = action
          }

      newEdge = case prevNodeId st of
          Nothing   -> []
          Just prev -> [(prev, nid)]

      oldGraph = graph st

      newGraph = oldGraph
          { traceNodes = traceNodes oldGraph ++ [node]
          , traceEdges = traceEdges oldGraph ++ newEdge
          }

      st' = st
          { nextNodeId = nid + 1
          , prevNodeId = Just nid
          , graph = newGraph
          }

  in (nid, st')

evalOp :: Op a -> Either String (Value a)
evalOp (Add (Value a) (Value b)) = Right $ Value (a + b)
evalOp (Sub (Value a) (Value b)) = Right $ Value (a - b)
evalOp (Mul (Value a) (Value b)) = Right $ Value (a * b)
evalOp (Gt  (Value a) (Value b)) = Right $ Value (if a > b then TInt 1 else TInt 0)
evalOp (Lt  (Value a) (Value b)) = Right $ Value (if a < b then TInt 1 else TInt 0)
evalOp (Eq  (Value a) (Value b)) = Right $ Value (if a == b then TInt 1 else TInt 0)
  
runProgram :: Program a -> ExecState -> Either String (a, ExecState)
runProgram (Pure a) st = Right (a, st)

runProgram (Free (Literal value next)) st =
    let (_, st') = addTraceNode (TraceLiteral value) st
    in runProgram (next value) st'

runProgram (Free (Read var next)) st = case storeLookup var st of
    Nothing -> Left ("Unknown variable: " ++ show var)
    Just value ->
      let (_, st') = addTraceNode (TraceRead var value) st
      in runProgram (next value) st'

runProgram (Free (Write var value next)) st =
    let oldValue = storeLookup var st
        (_, st1) = addTraceNode (TraceWrite var value oldValue) st
        st2 = storeInsert var value st1
    in runProgram next st2

runProgram (Free (Compute op next)) st =
    case evalOp op of
        Left err -> Left err
        Right value ->
            let (_, st') = addTraceNode (TraceCompute op value) st
            in runProgram (next value) st'

runProgram (Free (Branch (Value (TInt c)) thenProg elseProg)) st =
    case c of
        0 ->
            let (_, st') = addTraceNode (TraceBranch False) st
            in runProgram elseProg st'
        _ ->
            let (_, st') = addTraceNode (TraceBranch True) st
            in runProgram thenProg st'

-- Program

_xAddr :: MemAddress TInt
_xAddr = MemAddress 0
_yAddr :: MemAddress TInt
_yAddr = MemAddress 1
_zAddr :: MemAddress TInt
_zAddr = MemAddress 2
_resultAddr :: MemAddress TInt
_resultAddr = MemAddress 3

example :: Program ()
example = do
  writeVar _xAddr (Value $ TInt 7)

  x <- readVar _xAddr
  y <- compute $ Add x (Value $ TInt 5)
  writeVar _yAddr y

  cond <- compute $ Gt y (Value $ TInt 10)

  branch cond
    (do
      y1 <- readVar _yAddr 
      z  <- compute $ Mul y1 (Value $ TInt 2)
      writeVar _zAddr z)
    (do
      y1 <- readVar _yAddr
      z  <- compute $ Sub y1 (Value $ TInt 2)
      writeVar _zAddr z)

  z0 <- readVar _zAddr
  result <- compute $ Add z0 (Value $ TInt 0)
  writeVar _resultAddr result


main :: IO ()
main = do
  putStr "Result: "
  let initialState = ExecState
        { store = Map.empty
        , nextNodeId = 0
        , prevNodeId = Nothing
        , graph = TraceGraph [] []
        }
  let result = runProgram example initialState
  -- print full trace graph
  case result of
    Left err -> putStrLn ("Error: " ++ err)
    Right ((), finalState) -> do
      putStrLn "Execution completed successfully."
      putStrLn "Trace graph:"
      mapM_ print (traceNodes (graph finalState))
      putStrLn "Edges:"
      mapM_ print (traceEdges (graph finalState))
  

