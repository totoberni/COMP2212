module PiTypeChecker (getExpType, runTypeChecker) where

import Control.Applicative
import Control.Exception
import Data.Maybe
import Data.List
import Debug.Trace
import System.Directory
import System.Environment
import System.IO
import PlLexer
import PlParser

-- TODO

-- ===================
-- Type
-- ===================


isInvalidType :: Type -> Bool
isInvalidType (InvalidType _) = True
isInvalidType _ = False

-- ===================
-- Type Environment
-- ===================

type TypeEnvironment = [(String, Type)]

data TypeCheckResult =
    TypeValid
    | TypeFree
    | TypeInvalid
    deriving (Show, Read, Eq)


runTypeChecker :: Exp -> Maybe String
runTypeChecker exp = case type_loop (exp, [], []) of (ValType e, _, _) -> isValidType e
    where
        isValidType :: Type -> Maybe String
        isValidType (InvalidType x) = Just x
        isValidType _ = Nothing

getExpType :: Exp -> Type
getExpType exp = case type_loop (exp, [], []) of (ValType e, _, _) -> e

type_loop :: (Exp, TypeEnvironment, [(Exp, Int)]) -> (Exp, TypeEnvironment, [(Exp, Int)])
type_loop inp
    | is_terminated inp = inp
    | otherwise = type_loop (getExpressionType inp)

lookupType :: TypeEnvironment -> String -> Type
lookupType [] varName = InvalidType ("The identifier with name " ++ varName ++ " does not exist.")
lookupType ((xName, xType):xs) varName
    | varName == xName = xType
    | otherwise = lookupType xs varName

checkType :: TypeEnvironment -> String -> Type -> TypeCheckResult
checkType [] varName desired = TypeFree
checkType ((xName, xType):xs) varName desired
    | varName == xName && xType == desired = TypeValid
    | varName == xName && xType /= desired = TypeInvalid
    | otherwise = checkType xs varName desired

compType :: Type -> Type -> Bool
compType AnyType x = True
compType x AnyType = True
compType (Line x) (Line y) = compType x y
compType (RepeatingLine x) (RepeatingLine y) = compType x y
compType x y = x == y

isLine :: Type -> Bool
isLine (Line x) = True
isLine (RepeatingLine x) = True
isLine _ = False

is_terminated :: (Exp, TypeEnvironment, [(Exp, Int)]) -> Bool
-- Error
is_terminated (ValType (InvalidType x), _, _) = True
-- Still need to do stuff
is_terminated (_, _, k:ks) = False
-- Terminated values
is_terminated (ValType _, _, _) = True
-- Other stuff
is_terminated _ = False

get_n :: [[Exp]] -> Int -> Maybe Exp
get_n ((y:ys):xs) 0 = Just y
get_n ((y:ys):xs) n = get_n (ys:xs) (n-1)
get_n ([]:xs) n = get_n xs n
get_n [] n = Nothing

process_line_builder_type :: Type -> Type
process_line_builder_type (Line (Line x)) = Line (Line x)
process_line_builder_type (Line x) = Line (Line x)
process_line_builder_type x = Line (Line x)

magically_fix_builder_type :: Type -> Type
magically_fix_builder_type (Line (Line (Line (Line x)))) = Line (Line x)
magically_fix_builder_type x = x

-- ===================
-- Expression Type Calculator
-- ===================

getExpressionType :: (Exp, TypeEnvironment, [(Exp, Int)]) -> (Exp, TypeEnvironment, [(Exp, Int)])

-----------------
-- Sequence
-----------------

getExpressionType (OpSequence l r, env, ks) = (l, env, (OpSequence l r, 0):ks)
getExpressionType (ValType typeLeft, env, (OpSequence l r, 0):ks) = (r, env, (OpSequence l r, 1):ks)
getExpressionType (ValType typeRight, env, (OpSequence l r, 1):ks) = (ValType typeRight, env, ks)

-----------------
-- Variables
-----------------

getExpressionType (Identifier name, env, ks) = (ValType (lookupType env name), env, ks)

-----------------
-- Scope Entry
-----------------

getExpressionType (OpScopeEntry exp, env, ks) = (exp, env, ks)

-----------------
-- Assignation
-----------------

getExpressionType (OpAssign (Identifier id) r, env, ks) = (r, env, (OpAssign (Identifier id) r, 0):ks)
getExpressionType (ValType t, env, (OpAssign (Identifier id) r, 0):ks)
    | (checkType env id t) == TypeFree = (ValType t, (id, t):env, ks)
    | (checkType env id t) == TypeValid = (ValType t, env, ks)
    | otherwise = (ValType (InvalidType ("The variable " ++ id ++ " has type " ++ show (lookupType env id) ++ " but you are trying to assign something of type " ++ show t ++ " to it.")), env, [])

-----------------
-- Functions
-----------------

getExpressionType (KeywordIn exp, env, ks) = (exp, env, (ValType (Function [Numeric] (Line (Line Numeric))), 0):ks)
getExpressionType (OpInvokationArgs (Identifier "length") right, env, ks) = (right, env, (ValType (Function [Line AnyType] Numeric), 0):ks)

-- Allow the input parameters to be of any type
getExpressionType (OpCreateFunction args selector, env, ks) = (selector, (make_arg_list args) ++ env, (OpCreateFunction args selector, 0):ks)
    where
        make_arg_list :: Exp -> [(String, Type)]
        make_arg_list (OpArgIdTree (Identifier x) y) = (x, AnyType):(make_arg_list y)
        make_arg_list (OpArgIdLeaf (Identifier x)) = [(x, AnyType)]
getExpressionType (ValType x, env, (OpCreateFunction args selector, 0):ks) = (ValType (Function (make_arg_list (determine_argument_count args)) x), env, ks)
    where
        determine_argument_count :: Exp -> Int
        determine_argument_count (OpArgIdTree x y) = 1 + (determine_argument_count y)
        determine_argument_count (OpArgIdLeaf x) = 1
        make_arg_list :: Int -> [Type]
        make_arg_list 0 = []
        make_arg_list n = AnyType : (make_arg_list (n - 1))

-----------------
-- Compile Arguments
-----------------

getExpressionType (OpArgumentTree current next, env, (ValType (Function args returnType), 0):ks)
    = (current, env, (OpArgumentTree current next, 0):(ValType (Function args returnType), 0):ks)
getExpressionType (ValType argType, env, (OpArgumentTree current next, 0):(ValType (Function args returnType), 0):ks)
    | length args == 0 = (ValType (InvalidType "Invalid number of parameters passed to an argument."), env, [])
    | not (compType argType (args!!0)) = (ValType (InvalidType ("Invalid argument type passed, expected: " ++ (show (args!!0)) ++ ", found: " ++ (show argType))), env, [])
    | otherwise = (next, env, (ValType (Function (tail args) returnType), 0):ks)

getExpressionType (OpArgumentLeaf current, env, (ValType (Function args returnType), 0):ks)
    = (current, env, (OpArgumentLeaf current, 0):(ValType (Function args returnType), 0):ks)
getExpressionType (ValType argType, env, (OpArgumentLeaf current, 0):(ValType (Function args returnType), 0):ks)
    | length args == 0 = (ValType (InvalidType "Invalid number of parameters passed to an argument."), env, [])
    | not (compType argType (args!!0)) = (ValType (InvalidType ("Invalid argument type passed, expected: " ++ (show (args!!0)) ++ ", found: " ++ (show argType))), env, [])
    | otherwise = (ValType returnType, env, ks)

-----------------
-- Index
-----------------

getExpressionType (OpIndex l r, env, ks) = (l, env, (OpIndex l r, 0):ks)
getExpressionType (ValType (Line x), env, (OpIndex l r, 0):ks) = (r, env, (OpIndex (ValType (Line x)) r, 1):ks)
getExpressionType (ValType (RepeatingLine x), env, (OpIndex l r, 0):ks) = (r, env, (OpIndex (ValType (RepeatingLine x)) r, 1):ks)

getExpressionType (OpArgumentTree current next, env, (OpIndex (ValType x) r, 1):ks)
    = (current, env, (OpArgumentTree current next, 0):(OpIndex (ValType x) r, 1):ks)
getExpressionType (ValType argType, env, (OpArgumentTree current next, 0):(OpIndex (ValType x) r, 1):ks)
    | argType /= Numeric && not (isLine argType) = (ValType (InvalidType ("Invalid argument type passed, expected: line or number, found: " ++ (show argType))), env, [])
    | otherwise = (next, env, (OpIndex (ValType x) r, 1):ks)

getExpressionType (OpArgumentLeaf current, env, (OpIndex (ValType x) r, 1):ks)
    = (current, env, (OpArgumentLeaf current, 0):(OpIndex (ValType x) r, 1):ks)
getExpressionType (ValType argType, env, (OpArgumentLeaf current, 0):(OpIndex (ValType x) r, 1):ks)
    | argType /= Numeric && not (isLine argType) = (ValType (InvalidType ("Invalid argument type passed, expected: line or number, found: " ++ (show argType))), env, [])
    | otherwise = (ValType argType, env, ks)

getExpressionType (ValType Numeric, env, (OpIndex (ValType (Line x)) r, 1):ks) = (ValType x, env, ks)
getExpressionType (ValType (Line _), env, (OpIndex (ValType (Line x)) r, 1):ks) = (ValType (Line x), env, ks)
getExpressionType (ValType (RepeatingLine _), env, (OpIndex (ValType (Line x)) r, 1):ks) = (ValType (RepeatingLine x), env, ks)
getExpressionType (ValType Numeric, env, (OpIndex (ValType (RepeatingLine x)) r, 1):ks) = (ValType x, env, ks)
getExpressionType (ValType (Line _), env, (OpIndex (ValType (RepeatingLine x)) r, 1):ks) = (ValType (RepeatingLine x), env, ks)
getExpressionType (ValType (RepeatingLine _), env, (OpIndex (ValType (RepeatingLine x)) r, 1):ks) = (ValType (RepeatingLine x), env, ks)

-----------------
-- Switch
-----------------

getExpressionType (OpSwitch exp, env, ks) = (exp, env, (ValType AnyType, 0):(OpSwitch exp, 0):ks)

-- Check the predicate
getExpressionType (OpSwitchCase pred result next, env, (ValType returnType, 0):(OpSwitch exp, 0):ks) = (pred, env, (OpSwitchCase pred result next, 0):(ValType returnType, 0):(OpSwitch exp, 1):ks)
-- Predicate has valid type
getExpressionType (ValType Bool, env, (OpSwitchCase pred result next, 0):(ValType returnType, 0):(OpSwitch exp, 1):ks) = (result, env, (OpSwitchCase pred result next, 1):(ValType returnType, 0):(OpSwitch exp, 1):ks)
-- Check the return type
getExpressionType (ValType x, env, (OpSwitchCase pred result next, 1):(ValType returnType, 0):(OpSwitch exp, 1):ks)
    | compType x returnType = (next, env, (ValType x, 0):(OpSwitch exp, 0):ks)
    | otherwise = (ValType (InvalidType "Switch statement has cases with different return types"), env, [])

-- Check the return type
getExpressionType (OpSwitchElse result, env, (ValType returnType, 0):(OpSwitch exp, 0):ks) = (result, env, (OpSwitchElse result, 0):(ValType returnType, 0):(OpSwitch exp, 1):ks)
getExpressionType (ValType x, env, (OpSwitchElse result, 0):(ValType returnType, 0):(OpSwitch exp, 1):ks)
    | compType x returnType = (ValType x, env, ks)
    | otherwise = (ValType (InvalidType "Switch statement has cases with different return types"), env, [])

getExpressionType (ValType t, env, (ValType returnType, 0):(OpSwitch exp, 0):ks) = (ValType t, env, ks)

-----------------
-- Switch Across
-----------------

-- Check the source
getExpressionType (OpSwitchAcross n selector source, env, ks) = (source, env, (OpSwitchAcross n selector source, 0):ks)
getExpressionType (ValType (Line x), env, (OpSwitchAcross n selector source, 0):ks) = (OpSwitch selector, (n, x):env, (OpSwitchAcross n selector source, 1):ks)
getExpressionType (ValType (RepeatingLine x), env, (OpSwitchAcross n selector source, 0):ks) = (OpSwitch selector, (n, x):env, (OpSwitchAcross n selector source, 2):ks)
getExpressionType (ValType x, env, (OpSwitchAcross n selector source, 1):ks) = (ValType (Line x), env, ks)
getExpressionType (ValType x, env, (OpSwitchAcross n selector source, 2):ks) = (ValType (RepeatingLine x), env, ks)

-----------------
-- Tile Builder Across
-----------------
-- Same as switch across except it converts 4D arrays into 2D ones

-- Check the source
getExpressionType (TileBuilderAcross n selector source, env, ks) = (source, env, (TileBuilderAcross n selector source, 0):ks)
getExpressionType (ValType (Line x), env, (TileBuilderAcross n selector source, 0):ks) = (selector, (n, x):env, (TileBuilderAcross n selector source, 1):ks)
getExpressionType (ValType (RepeatingLine x), env, (TileBuilderAcross n selector source, 0):ks) = (selector, (n, x):env, (TileBuilderAcross n selector source, 1):ks)

-- Check the selector
getExpressionType (ValType x, env, (TileBuilderAcross n selector source, 1):ks) = (ValType (magically_fix_builder_type (Line x)), env, ks)

-----------------
-- Tile Builder
-----------------

getExpressionType (TileBuilder row, env, ks) = (TileBuilderGrid (convertToGrid row), env, ks)
    where
        convertToGrid :: TileBuilderRow -> [[Exp]]
        convertToGrid exp = transpose (convertToGrid_a exp)
        -- Convert the tile builder argument tree into a 2D array for easier handling
        convertToGrid_a :: TileBuilderRow -> [[Exp]]
        convertToGrid_a (TBRowLast line) = [convertToLine line]
        convertToGrid_a (TBRow line next) = (convertToLine line) : (convertToGrid_a next)
        convertToLine :: TileBuilderLine -> [Exp]
        convertToLine (TBLineLast exp) = [exp]
        convertToLine (TBLine exp next) = exp : (convertToLine next)

-- Chcek the types of each element in the built tile
getExpressionType (TileBuilderGrid grid, env, ks) = (grid!!0!!0, env, (TileBuilderGrid grid, 0):ks)
-- First element determines the tile builders type
getExpressionType (ValType identifiedType, env, (TileBuilderGrid grid, 0):ks)
    -- Only 1 element
    | get_n grid 1 == Nothing = (ValType (process_line_builder_type identifiedType), env, ks)
    -- Put the type that we want onto the stack
    -- in a very dodgy looking manner
    | otherwise = (fromJust $ get_n grid 1, env, (ValType identifiedType, 0):(TileBuilderGrid grid, 1):ks)

getExpressionType (ValType identifiedType, env, (ValType expectedType, 0):(TileBuilderGrid grid, n):ks)
    -- Bad typing!!!!
    | not (compType identifiedType expectedType) = (ValType (InvalidType ("Invalid typing across TileBuilder, expected " ++ show expectedType ++ ", but got " ++ show identifiedType)), env, [])
    -- Shrink the typespace if necessary
    | get_n grid (n+1) == Nothing = (ValType (process_line_builder_type identifiedType), env, ks)
    | otherwise = (fromJust $ get_n grid (n+1), env, (ValType expectedType, 0):(TileBuilderGrid grid, (n+1)):ks)

-----------------
-- List Types
-----------------

getExpressionType (OpRange l r, env, ks) = (l, env, (OpRange l r, 0):ks)
getExpressionType (ValType Numeric, env, (OpRange l r, 0):ks) = (r, env, (OpRange ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpRange l r, 1):ks) = (ValType (Line Numeric), env, ks)

getExpressionType (OpRepeat l, env, ks) = (l, env, (OpRepeat l, 0):ks)
getExpressionType (ValType Numeric, env, (OpRepeat l, 0):ks) = (ValType (RepeatingLine Numeric), env, ks)
getExpressionType (ValType Bool, env, (OpRepeat l, 0):ks) = (ValType (RepeatingLine Bool), env, ks)
getExpressionType (ValType (Line internalType), env, (OpRepeat l, 0):ks) = (ValType (RepeatingLine internalType), env, ks)
getExpressionType (ValType (RepeatingLine internalType), env, (OpRepeat l, 0):ks) = (ValType (RepeatingLine internalType), env, ks)

-----------------
-- Mathematic Types
-----------------

getExpressionType (OpAdd l r, env, ks) = (l, env, (OpAdd l r, 0):ks)
getExpressionType (ValType AnyType, env, (OpAdd l r, 0):ks) = (r, env, (OpAdd ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpAdd l r, 0):ks) = (r, env, (OpAdd ValNull r, 1):ks)
getExpressionType (ValType AnyType, env, (OpAdd l r, 1):ks) = (ValType Numeric, env, ks)
getExpressionType (ValType Numeric, env, (OpAdd l r, 1):ks) = (ValType Numeric, env, ks)

getExpressionType (OpSubtract l r, env, ks) = (l, env, (OpSubtract l r, 0):ks)
getExpressionType (ValType AnyType, env, (OpSubtract l r, 0):ks) = (r, env, (OpSubtract ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpSubtract l r, 0):ks) = (r, env, (OpSubtract ValNull r, 1):ks)
getExpressionType (ValType AnyType, env, (OpSubtract l r, 1):ks) = (ValType Numeric, env, ks)
getExpressionType (ValType Numeric, env, (OpSubtract l r, 1):ks) = (ValType Numeric, env, ks)

getExpressionType (OpMultiply l r, env, ks) = (l, env, (OpMultiply l r, 0):ks)
getExpressionType (ValType AnyType, env, (OpMultiply l r, 0):ks) = (r, env, (OpMultiply ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpMultiply l r, 0):ks) = (r, env, (OpMultiply ValNull r, 1):ks)
getExpressionType (ValType AnyType, env, (OpMultiply l r, 1):ks) = (ValType Numeric, env, ks)
getExpressionType (ValType Numeric, env, (OpMultiply l r, 1):ks) = (ValType Numeric, env, ks)

getExpressionType (OpDivide l r, env, ks) = (l, env, (OpDivide l r, 0):ks)
getExpressionType (ValType AnyType, env, (OpDivide l r, 0):ks) = (r, env, (OpDivide ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpDivide l r, 0):ks) = (r, env, (OpDivide ValNull r, 1):ks)
getExpressionType (ValType AnyType, env, (OpDivide l r, 1):ks) = (ValType Numeric, env, ks)
getExpressionType (ValType Numeric, env, (OpDivide l r, 1):ks) = (ValType Numeric, env, ks)

getExpressionType (OpModulus l r, env, ks) = (l, env, (OpModulus l r, 0):ks)
getExpressionType (ValType AnyType, env, (OpModulus l r, 0):ks) = (r, env, (OpModulus ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpModulus l r, 0):ks) = (r, env, (OpModulus ValNull r, 1):ks)
getExpressionType (ValType AnyType, env, (OpModulus l r, 1):ks) = (ValType Numeric, env, ks)
getExpressionType (ValType Numeric, env, (OpModulus l r, 1):ks) = (ValType Numeric, env, ks)

getExpressionType (OpLogicalAnd l r, env, ks) = (l, env, (OpLogicalAnd l r, 0):ks)
getExpressionType (ValType AnyType, env, (OpLogicalAnd l r, 0):ks) = (r, env, (OpLogicalAnd ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpLogicalAnd l r, 0):ks) = (r, env, (OpLogicalAnd ValNull r, 1):ks)
getExpressionType (ValType AnyType, env, (OpLogicalAnd l r, 1):ks) = (ValType Numeric, env, ks)
getExpressionType (ValType Numeric, env, (OpLogicalAnd l r, 1):ks) = (ValType Numeric, env, ks)

getExpressionType (OpLogicalXor l r, env, ks) = (l, env, (OpLogicalXor l r, 0):ks)
getExpressionType (ValType AnyType, env, (OpLogicalXor l r, 0):ks) = (r, env, (OpLogicalXor ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpLogicalXor l r, 0):ks) = (r, env, (OpLogicalXor ValNull r, 1):ks)
getExpressionType (ValType AnyType, env, (OpLogicalXor l r, 1):ks) = (ValType Numeric, env, ks)
getExpressionType (ValType Numeric, env, (OpLogicalXor l r, 1):ks) = (ValType Numeric, env, ks)

getExpressionType (OpLogicalOr l r, env, ks) = (l, env, (OpLogicalOr l r, 0):ks)
getExpressionType (ValType AnyType, env, (OpLogicalOr l r, 0):ks) = (r, env, (OpLogicalOr ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpLogicalOr l r, 0):ks) = (r, env, (OpLogicalOr ValNull r, 1):ks)
getExpressionType (ValType AnyType, env, (OpLogicalOr l r, 1):ks) = (ValType Numeric, env, ks)
getExpressionType (ValType Numeric, env, (OpLogicalOr l r, 1):ks) = (ValType Numeric, env, ks)

getExpressionType (OpLogicalNot l, env, ks) = (l, env, (OpLogicalNot l, 0):ks)
getExpressionType (ValType Numeric, env, (OpLogicalNot l, 0):ks) = (ValType Numeric, env, ks)
getExpressionType (ValType AnyType, env, (OpLogicalNot l, 0):ks) = (ValType Numeric, env, ks)

-----------------
-- Numerical Comparisons
-----------------

getExpressionType (OpCompLess l r, env, ks) = (l, env, (OpCompLess l r, 0):ks)
getExpressionType (ValType Numeric, env, (OpCompLess l r, 0):ks) = (r, env, (OpCompLess ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpCompLess l r, 1):ks) = (ValType Bool, env, ks)

getExpressionType (OpCompLessEqual l r, env, ks) = (l, env, (OpCompLessEqual l r, 0):ks)
getExpressionType (ValType Numeric, env, (OpCompLessEqual l r, 0):ks) = (r, env, (OpCompLessEqual ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpCompLessEqual l r, 1):ks) = (ValType Bool, env, ks)

getExpressionType (OpCompGreater l r, env, ks) = (l, env, (OpCompGreater l r, 0):ks)
getExpressionType (ValType Numeric, env, (OpCompGreater l r, 0):ks) = (r, env, (OpCompGreater ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpCompGreater l r, 1):ks) = (ValType Bool, env, ks)

getExpressionType (OpCompGreaterEqual l r, env, ks) = (l, env, (OpCompGreaterEqual l r, 0):ks)
getExpressionType (ValType Numeric, env, (OpCompGreaterEqual l r, 0):ks) = (r, env, (OpCompGreaterEqual ValNull r, 1):ks)
getExpressionType (ValType Numeric, env, (OpCompGreaterEqual l r, 1):ks) = (ValType Bool, env, ks)

-----------------
-- Boolean Comparisons
-----------------

getExpressionType (OpComparativeAnd l r, env, ks) = (l, env, (OpComparativeAnd l r, 0):ks)
getExpressionType (ValType Bool, env, (OpComparativeAnd l r, 0):ks) = (r, env, (OpComparativeAnd ValNull r, 1):ks)
getExpressionType (ValType Bool, env, (OpComparativeAnd l r, 1):ks) = (ValType Bool, env, ks)

getExpressionType (OpComparativeOr l r, env, ks) = (l, env, (OpComparativeOr l r, 0):ks)
getExpressionType (ValType Bool, env, (OpComparativeOr l r, 0):ks) = (r, env, (OpComparativeOr ValNull r, 1):ks)
getExpressionType (ValType Bool, env, (OpComparativeOr l r, 1):ks) = (ValType Bool, env, ks)

getExpressionType (OpComparativeNot l, env, ks) = (l, env, (OpComparativeNot l, 0):ks)
getExpressionType (ValType Bool, env, (OpComparativeNot l, 0):ks) = (ValType Bool, env, ks)
getExpressionType (ValType Numeric, env, (OpComparativeNot l, 0):ks) = (ValType Bool, env, ks)

-----------------
-- Generic Comparisons
-----------------

getExpressionType (OpCompEqual l r, env, ks) = (l, env, (OpCompEqual l r, 0):ks)
getExpressionType (ValType typeL, env, (OpCompEqual l r, 0):ks) = (r, env, (OpCompEqual (ValType typeL) r, 1):ks)
getExpressionType (ValType typeR, env, (OpCompEqual (ValType typeL) r, 1):ks)
    | compType typeL typeR = (ValType Bool, env, ks)
    | otherwise = (ValType (InvalidType "Invalid type == must have the same type on the left and right"), env, ks)

getExpressionType (OpCompNotEqual l r, env, ks) = (l, env, (OpCompNotEqual l r, 0):ks)
getExpressionType (ValType typeL, env, (OpCompNotEqual l r, 0):ks) = (r, env, (OpCompNotEqual (ValType typeL) r, 1):ks)
getExpressionType (ValType typeR, env, (OpCompNotEqual (ValType typeL) r, 1):ks)
    | compType typeL typeR = (ValType Bool, env, ks)
    | otherwise = (ValType (InvalidType "Invalid type != must have the same type on the left and right"), env, ks)

getExpressionType (OpAssertion l r, env, ks) = (l, env, (OpAssertion l r, 0):ks)
getExpressionType (ValType typeL, env, (OpAssertion l r, 0):ks) = (r, env, (OpAssertion (ValType typeL) r, 1):ks)
getExpressionType (ValType typeR, env, (OpAssertion (ValType typeL) r, 1):ks)
    | compType typeL typeR = (ValType Bool, env, ks)
    | otherwise = (ValType (InvalidType ("Invalid type ~= must have the same type on the left and right. Left: " ++ show typeL ++ ", Right: " ++ show typeR)), env, ks)

-----------------
-- Base Type
-----------------

getExpressionType (ValNum x, env, ks) = (ValType Numeric, env, ks)
getExpressionType (ValBool x, env, ks) = (ValType Bool, env, ks)
getExpressionType (ValString x, env, ks) = (ValType String, env, ks)

-- Explicitly don't check this
getExpressionType (HaskellAssertion l r, env, ks) = (ValType Bool, env, ks)

getExpressionType (exp, env, k:ks) = (ValType (InvalidType ("The expression " ++ (show exp) ++ " (stack:) " ++ (show k) ++ " has invalid type.")), env, [])
getExpressionType (exp, env, []) = (ValType (InvalidType ("The expression " ++ (show exp) ++ " has invalid type.")), env, [])

-- OpMemberAccess Exp Exp
-- OpArgumentTree Exp Exp
-- OpArgumentLeaf Exp
-- OpInvokation Exp
-- OpInvokationArgs Exp Exp
-- OpIndex Exp Exp
-- OpSwitch Exp
-- OpSwitchAcross String Exp Exp
-- OpSwitchCase Exp Exp Exp
-- OpSwitchElse Exp
-- OpMultiply Exp Exp                  -- COMPLETED
-- OpDivide Exp Exp                  -- COMPLETED
-- OpAdd Exp Exp                  -- COMPLETED
-- OpSubtract Exp Exp                  -- COMPLETED
-- OpCompLess Exp Exp                  -- COMPLETED
-- OpCompLessEqual Exp Exp                  -- COMPLETED
-- OpCompGreater Exp Exp                  -- COMPLETED
-- OpCompGreaterEqual Exp Exp                  -- COMPLETED
-- OpCompEqual Exp Exp                  -- COMPLETED
-- OpCompNotEqual Exp Exp                  -- COMPLETED
-- OpLogicalAnd Exp Exp                  -- COMPLETED
-- OpLogicalXor Exp Exp                  -- COMPLETED
-- OpLogicalOr Exp Exp                  -- COMPLETED
-- OpLogicalNot Exp                  -- COMPLETED
-- OpComparativeAnd Exp Exp                  -- COMPLETED
-- OpComparativeOr Exp Exp                  -- COMPLETED
-- OpComparativeNot Exp                  -- COMPLETED
-- OpRange Exp Exp                  -- COMPLETED
-- OpAssign Exp Exp                  -- COMPLETED
-- OpRepeat Exp                  -- COMPLETED
-- OpSequence Exp Exp                  -- COMPLETED
-- OpAssertion Exp Exp                  -- COMPLETED
-- HaskellAssertion Exp String
-- KeywordIn Exp
-- Identifier String                  -- COMPLETED
-- ValNum Int                  -- COMPLETED
-- ValBool Bool                  -- COMPLETED
-- ValString String                  -- COMPLETED
-- TileBuilder TileBuilderRow
