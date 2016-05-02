{-# LANGUAGE LambdaCase #-}

module Eval.TypeCheck
( TypeCheckError
, typeCheck )
where

import Control.Monad
import Control.Monad.State
import Control.Monad.Except
import Data.Map ((!), Map)
import qualified Data.Map as Map
import Data.List
import Data.Maybe

import AST.Types
import AST.Print

import qualified Eval.Types as EvalTypes
import qualified Eval.Builtins as Builtins

typeCheck :: Program -> Either TypeCheckError ()
typeCheck p = runExcept $ evalStateT (programType p) (Map.empty)

type TCM = StateT VarSet (Except TypeCheckError)
type VarSet = Map String VarInfo

-- (readonly, type)
type VarInfo = (Bool, Type)

data TypeCheckError
    = TCReturnOutside
    | TCInvalidBind
    | TCNotAFunction Type
    | TCUndefinedVar String
    | TCReadonlyVar String
    | TCInvalidType Type Type
    | TCInvalidCall [Type] [Type]
    | TypeCheckErrorIn Stmt TypeCheckError
    | TypeCheckErrorInE Expr TypeCheckError

instance Show TypeCheckError where
    show TCReturnOutside = "return outside of a function"
    show TCInvalidBind = "cannot bind value to function without arguments"
    show (TCNotAFunction actual) = "not a function type: " ++ showType actual
    show (TCUndefinedVar name) = "undefined identifier '" ++ name ++ "'"
    show (TCReadonlyVar name) = "invalid operation on readonly identifier '" ++ name ++ "'"
    show (TCInvalidType expected actual) = intercalate "\n"
        [ "invalid type"
        , "expected: " ++ showType expected
        , "  actual: " ++ showType actual ]
    show (TCInvalidCall fargs args) = intercalate "\n"
        [ "invalid function call"
        , "expected arguments: " ++ intercalate ", " (map showType fargs)
        , "  actual arguments: " ++ intercalate ", " (map showType args) ]
    show (TypeCheckErrorIn stmt err) = concat 
        [ show err
        , "\nin:\n"
        , printAST stmt ]
    show (TypeCheckErrorInE expr err) = concat
        [ show err
        , "\nin:\n"
        , printAST expr ]

showType :: Type -> String
showType TInt = "Int"
showType TBool = "Bool"
showType TString = "String"
showType (TFunc [x]) = "Void -> " ++ showType' x
showType (TFunc l) = intercalate " -> " $ map showType' l

showType' :: Type -> String
showType' x@(TFunc _) = "(" ++ showType x ++ ")"
showType' x = showType x

-- Program

programType :: Program -> TCM ()
programType (Program main fs) = do
    mapM_ addBuiltinFunc Builtins.builtins
    mapM_ addFunc fs
    mapM_ functionType fs
    stmtType main
    where
    addFunc (Function name args retT _) = 
        setVar name (TFunc ts) True
        where
        ts = map (\(TypedVar _ t) -> t) args ++ [retT]

addBuiltinFunc :: EvalTypes.Builtin -> TCM ()
addBuiltinFunc f = setVar n t True
    where
    n = EvalTypes.name f
    t = EvalTypes.fType f 

-- Function

functionType :: Function -> TCM ()
functionType (Function name args retT stmt) =
    let argst = map (\(TypedVar _ t) -> t) args in do
    localTypes $ do
        allReadonly
        mapM_ (\(TypedVar n t) -> setVar n t True) args
        setReturnType retT
        stmtType stmt 
    setVar name (TFunc $ argst ++ [retT]) True

-- Statements

stmtType :: Stmt -> TCM ()
stmtType (SList l) = forM_ l stmtType
stmtType s = catchError (stmtType' s) (throwError . TypeCheckErrorIn s)

stmtType' :: Stmt -> TCM ()
stmtType' (SList _) = undefined

stmtType' (SVar name optT e) = do
    eT <- exprType e
    when (isJust optT) (expectType (fromJust optT) eT)
    setVar name eT False

stmtType' (SLet name optT e) = do
    eT <- exprType e
    when (isJust optT) (expectType (fromJust optT) eT)
    setVar name eT True

stmtType' (SExpr e) = void $ exprType e

stmtType' (SIf e trueS falseS) = localTypes $ do
    exprType e >>= expectType TBool
    stmtType trueS
    when (isJust falseS) (stmtType $ fromJust falseS)

stmtType' (SWhile e stmt) = localTypes $ do
    exprType e >>= expectType TBool
    stmtType stmt

stmtType' (SFor n r stmt) = localTypes $ do
    rangeType r
    setVar n TInt True
    stmtType stmt

stmtType' (SReturn e) = do
    eT <- exprType e
    returnType >>= \case
        Just rT -> expectType rT eT
        Nothing -> throwError TCReturnOutside

stmtType' (SAssign _ n e) = do
    expectRWVar n
    vT <- exprType $ EVar n 
    exprType e >>= expectType vT

stmtType' (SInc n) = do
    expectRWVar n
    fromJust <$> varType n >>= expectType TInt

stmtType' (SDec n) = do
    expectRWVar n
    fromJust <$> varType n >>= expectType TInt

stmtType' (SPrint es) = mapM_ (\e -> exprType e >>= expectType TString) es 

-- Range

rangeType :: Range -> TCM ()
rangeType (RExclusive e1 e2) = void $ exprType e1 >> exprType e2
rangeType (RInclusive e1 e2) = void $ exprType e1 >> exprType e2

-- Expressions

exprType :: Expr -> TCM Type
exprType e = catchError (exprType' e) (throwError . TypeCheckErrorInE e)

exprType' :: Expr -> TCM Type

exprType' (EBool _) = return TBool
exprType' (EInt _) = return TInt
exprType' (EString _) = return TString

exprType' (EVar name) = do
    expectVar name
    fromJust <$> varType name

exprType' (EBinOp EMul e1 e2) = binOpType e1 e2 TInt 
exprType' (EBinOp EDiv e1 e2) = binOpType e1 e2 TInt
exprType' (EBinOp EMod e1 e2) = binOpType e1 e2 TInt 
exprType' (EBinOp EAdd e1 e2) = binOpType e1 e2 TInt 
exprType' (EBinOp ESub e1 e2) = binOpType e1 e2 TInt 
exprType' (EBinOp ELess e1 e2) = binOpType e1 e2 TInt >> return TBool
exprType' (EBinOp ELessE e1 e2) = binOpType e1 e2 TInt >> return TBool
exprType' (EBinOp EGreater e1 e2) = binOpType e1 e2 TInt >> return TBool
exprType' (EBinOp EGreaterE e1 e2) = binOpType e1 e2 TInt >> return TBool
exprType' (EBinOp EEq e1 e2) = binOpType e1 e2 TInt >> return TBool
exprType' (EBinOp ENeq e1 e2) = binOpType e1 e2 TInt >> return TBool
exprType' (EBinOp EAnd e1 e2) = binOpType e1 e2 TBool
exprType' (EBinOp EOr e1 e2) = binOpType e1 e2 TBool

exprType' (EBinOp EBind f arg) = do
    ft <- exprType f
    argt <- exprType arg
    case ft of
        TFunc (farg:args) -> do 
            expectType farg argt
            return $ TFunc args
        TFunc [] -> throwError TCInvalidBind
        _ -> throwError $ TCNotAFunction ft 

exprType' (ECall f args) = do 
    ft <- exprType f
    argst <- mapM exprType args
    case ft of
        TFunc fargst ->
            if init fargst /= argst then
                throwError $ TCInvalidCall (init fargst) argst
            else 
                return $ last fargst
        _ -> throwError $ TCNotAFunction ft

exprType' (ELambda args retT stmt) = localTypes $ do
    let argst = map (\(TypedVar _ t) -> t) args
    modify $ Map.map (\(_, n) -> (True, n)) 
    mapM_ (\(TypedVar n t) -> setVar n t True) args
    setReturnType retT
    stmtType stmt
    return $ TFunc $ argst ++ [retT]

-- Helpers

-- lhs -> rhs -> expected type for lhs & rhs
binOpType :: Expr -> Expr -> Type -> TCM Type
binOpType e1 e2 t = do
    t1 <- exprType e1
    expectType t t1
    t2 <- exprType e2
    expectType t t2
    return t

expectType :: Type -> Type -> TCM ()
expectType expected actual =
    when (expected /= actual) (throwError $ TCInvalidType expected actual)

expectVar :: String -> TCM ()
expectVar name =
    varExist name >>= flip unless (throwError $ TCUndefinedVar name)

expectRWVar :: String -> TCM ()
expectRWVar name = do 
    expectVar name
    varReadonly name >>= flip when (throwError $ TCReadonlyVar name)

returnType :: TCM (Maybe Type)
returnType = varType returnTypeID

setReturnType :: Type -> TCM ()
setReturnType t = setVar returnTypeID t True

returnTypeID :: String
returnTypeID = "##return_type"

varExist :: String -> TCM Bool
varExist v = do
    st <- get
    return $ Map.member v st

varReadonly :: String -> TCM Bool
varReadonly v = do
    st <- get
    return $ fst $ st ! v 

varType :: String -> TCM (Maybe Type)
varType v = do
    st <- get
    return $ snd <$> Map.lookup v st

setVar :: String -> Type -> Bool -> TCM ()
setVar n t readonly = modify $ Map.alter (\_ -> Just (readonly, t)) n

localTypes :: TCM a -> TCM a
localTypes m = get >>= \st -> m <* put st

allReadonly :: TCM ()
allReadonly = modify $ Map.map (\(_, n) -> (True, n)) 