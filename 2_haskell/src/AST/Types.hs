module AST.Types
( Program (..)
, Function (..)
, Expr (..)
, BinOp (..)
, Stmt (..)
, Tuple (..)
, TupleTerm (..)
, Range (..)
, TypedVar (..)
, Type (..)
, TypeSkeleton (..)
, AssignOp (..)
) where

data Program
    = Program Stmt [Function]
    deriving (Eq, Show)

data Function
    = Function String [TypedVar] Type Stmt
    deriving (Eq, Show)

data Expr
    = EVar String
    | EBool Bool
    | EString String
    | EInt Integer
    | ETuple [Expr]
    | EBinOp BinOp Expr Expr
    | ECall Expr [Expr]
    | ELambda [TypedVar] Type Stmt
    deriving (Eq, Show)

data BinOp
    = EMul | EDiv | EMod
    | EAdd | ESub
    | ELess | ELessE | EGreater | EGreaterE | EEq | ENeq
    | EAnd
    | EOr
    | EBind 
    deriving (Eq, Show)

data Stmt
    = SList [Stmt]
    | SVar String (Maybe Type) Expr
    | SLet String (Maybe Type) Expr
    | SVarTuple Tuple (Maybe Type) Expr
    | SLetTuple Tuple (Maybe Type) Expr
    | SFunction Function
    | SExpr Expr
    | SIf Expr Stmt (Maybe Stmt)
    | SWhile Expr Stmt
    | SFor String Range Stmt
    | SReturn Expr
    | SAssign AssignOp String Expr
    | STupleAssign Tuple Expr
    | SInc String
    | SDec String
    | SPrint [Expr]
    deriving (Eq, Show)

data Tuple
    = Tuple [TupleTerm]
    deriving (Eq, Show)

data TupleTerm
    = TupleTermTuple Tuple
    | TupleTermVar String
    deriving (Eq, Show)

data Range
    = RExclusive Expr Expr
    | RInclusive Expr Expr 
    deriving (Eq, Show)

data TypedVar = TypedVar {
    argName :: String,
    argType :: Type
} deriving (Eq, Show)

data Type
    = TInt
    | TBool
    | TString
    | TTuple [Type]
    | TFunc [Type] 
    deriving (Eq, Show)

data TypeSkeleton
    = TSTuple [TypeSkeleton]
    | TSTerm
    deriving (Eq, Show)

data AssignOp
    = SEq
    | SAdd
    | SSub
    | SMul
    | SDiv
    | SMod 
    deriving (Eq, Show)
