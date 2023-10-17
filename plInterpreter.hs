module PlInterpreter (evaluate_exp, output_exp, output_formatted_exp, output_exp_pure) where

import Control.Applicative
import Control.Exception
import Data.Bits
import Data.List
import Debug.Trace
import System.Directory
import System.Environment
import System.IO
import PlLexer
import PlParser

-- TODO:
-- Handle infinity correctly in conditional checks
-- Write standard library functions
-- Implement some of the syntactic sugar that we want

-- This represents something
-- I think its anything that has to defer its execution in order to evaluate something
-- else.
-- We only need to store the previous environment in places that it can be modified, so that
-- we can restore scope when traversing back up the tree again.
data Frame = 
    -- Simple operators
    ModulusLeft Exp
    | ModulusRight Exp
    | MultiplyLeft Exp
    | MultiplyRight Exp
    | DivideLeft Exp
    | DivideRight Exp
    | AddLeft Exp
    | AddRight Exp
    | SubtractLeft Exp
    | SubtractRight Exp
    | CompLessLeft Exp
    | CompLessRight Exp
    | CompLessEqualLeft Exp
    | CompLessEqualRight Exp
    | CompGreaterLeft Exp
    | CompGreaterRight Exp
    | CompGreaterEqualLeft Exp
    | CompGreaterEqualRight Exp
    | CompEqualLeft Exp
    | CompEqualRight Exp
    | CompNotEqualLeft Exp
    | CompNotEqualRight Exp
    | LogicalAndLeft Exp
    | LogicalAndRight Exp
    | LogicalXorLeft Exp
    | LogicalXorRight Exp
    | LogicalOrLeft Exp
    | LogicalOrRight Exp
    | LogicalNot
    | ComparativeAndLeft Exp
    | ComparativeAndRight Exp
    | ComparativeOrLeft Exp
    | ComparativeOrRight Exp
    | ComparativeNot
    | SequenceLeft Exp
    | CreateFunctionArgs Exp
    -- Invokation
    | InvokationLeft [Exp]
    | InvokationRight Exp
    -- Assertion
    | AssertionLeft Exp
    | AssertionRight Exp
    -- Basic Switch
    | SwitchCasePredicate Exp Exp
    -- Switch across
    | SwitchAcross String Exp
    -- Scope
    | LocalScope Environment
    -- Assigning
    | AssignLeft Exp
    | AssignRight Exp
    -- Range
    | RangeLeft Exp
    | RangeRight Int
    -- Index
    | IndexLeft Exp
    | IndexRight Exp
    -- Modifier for index that makes it look into the next deepest element
    | ModifierIndexDepth
    -- Repeat
    | Repeat
    | RepeatIfLine
    | RepeatLine Exp
    -- In
    | In
    -- Argument Identifiers Evaluation
    | ArgIdNodeLeft [Exp] Exp
    | ArgIdNodeRight [Exp]
    | ArgIdLeafLeft [Exp]
    -- Argument Evaluation
    | ArgNodeLeft [Exp] Exp
    | ArgNodeRight [Exp]
    | ArgLeafLeft [Exp]
    -- Tile builder
    | TileBuilderFrame [[Exp]] [[Exp]]
    | TileBuilderLineFrame [Exp] [Exp]
    | TileBuilderAcrossFrame
    -- Concat Lookup
    | LookupConcatLeft Exp [[Exp]]
    | LookupConcatRight Exp [[Exp]]
    -- Select compilation
    | SelectPreCompilation Exp
    | SelectCompilation Exp [Exp] [Exp]
    | SelectCompilationRepeating Exp [Exp] [Exp]
    -- Stack error
    | StackError String
    -- Iterate over array
    | IteratorRepeatLine [Exp] [Exp]
    deriving (Show, Read, Eq) 

-- The stack of frames that we need to evaluate
-- The top-most frame is the frame that we are trying
-- to evaluate overall.
type Kontinuation = [ Frame ]

-- ==========================
-- Environment
-- ==========================

environment_lookup :: String -> Environment -> Environment -> Exp
environment_lookup id ((varName, VarExpression exp):env) fullEnv
    | id == varName = exp
    | otherwise = environment_lookup id env fullEnv
environment_lookup id [] fullEnv = ValError ("Could not locate the variable with identifier " ++ id ++ ".\n==============\nThe currently recognised variables are:\n==============\n" ++ (show fullEnv))

concat_environments :: Environment -> Environment -> Environment
concat_environments high low = high ++ low

-- ==========================
-- 'In' Functions
-- ==========================

read_input :: String -> Exp -> IO Exp
read_input dir (ValNum num) = read_input dir (ValString ("tile" ++ show (round num) ++ ".tl"))
read_input dir (ValString fileName) = do
    pass <- doesFileExist (fileName)
    fileText <- if (pass)
    then readFile (fileName)
    else readFile (dir ++ "/" ++ fileName)
    return (ValLine (build_input fileText 0 (replicate (get_width fileText) (ValLine []))))
    where
        get_width :: String -> Int
        get_width [] = 0
        get_width (x:xs)
            | x == '\n' = 0
            | x == '\r' = 0
            | otherwise = 1 + get_width xs
    
read_input dir _ = return (ValError "Invalid argument passed to in, it must be given an expression of either a numerical type or string type.")

build_input :: String -> Int -> [Exp]  -> [Exp]
build_input [] current built_grid = [case x of ValLine exps -> ValLine (reverse exps) | x <- built_grid]
build_input (x:xs) current built_grid
    | x == '\n' = build_input xs 0 built_grid
    | x == '\r' = build_input xs current built_grid
    | otherwise = build_input xs (current + 1) [do_thing (y == current) (built_grid !! y) x | y <- [0..(length built_grid) - 1]]
    where
        do_thing :: Bool -> Exp -> Char -> Exp
        do_thing False exp x = exp
        do_thing True (ValLine exps) '0' = ValLine ((ValNum 0) : exps)
        do_thing True (ValLine exps) '1' = ValLine ((ValNum 1) : exps)

-- ==========================
-- Evaluation Engine
-- ==========================
-- The example for the challenge 5 solutions performs the CEK interpretation by looking
-- at the parent nodes in the evaluator, however we will instead look at the children nodes
-- since it avoids unnecessary steps when the children nodes are already fully resolved.
-- Rather than explore the left and then the right, just to find out that they are resolved,
-- we can instantly see that they are resolved and evaluate them directly.
-- EDIT: Actually I just realised why we don't do it like that, its because if we do it like that
-- then we need to traverse back up the tree once we have a terminated expression. This seems fine,
-- however if we don't have a terminated expression then we will travel back up the tree just
-- to go down the same branch again which will create an infinite loop, causing the interpreter
-- to hang. This method of bottom-up evaluation is much simpler to implement.

-- Holds a reference to the parent expression in the 4th slot

type EvalState = (Exp, Environment, Kontinuation)

output_exp :: Exp -> String -> IO String
output_exp exp directory
    -- | trace ( "Debug: '" ++ (show (evaluate_exp exp)) ++ "'") True = expression_out (evaluate_exp exp)
    = do
        evaluated <- (evaluate_exp exp directory)
        writeFile (directory ++ "/output.txt") (grid_out evaluated)
        return (expression_out evaluated)

output_formatted_exp :: Exp -> String -> IO String
output_formatted_exp exp directory
    -- | trace ( "Debug: '" ++ (show (evaluate_exp exp)) ++ "'") True = expression_out (evaluate_exp exp)
    = do
        evaluated <- (evaluate_exp exp directory)
        return (grid_out evaluated)

output_exp_pure :: Exp -> String
output_exp_pure exp
    -- | trace ( "Debug: '" ++ (show (evaluate_exp exp)) ++ "'") True = expression_out (evaluate_exp exp)
    = expression_out (eval_loop (exp, [], []))

-- Evaluate the expression
evaluate_exp :: Exp -> String -> IO Exp
evaluate_exp exp directory = do
    writeFile "./debug_output.txt" (("Debug output for expression: ") ++ (show exp) ++ "\n\n")
    eval_loop_io (exp, [], []) directory

-- Loop through the evaluation until we can no longer go any further
eval_loop_io :: EvalState -> String -> IO Exp
eval_loop_io state@(exp, env, k) directory
    | is_terminated state = return exp
    -- | trace ("==============================\nCURRENT: " ++ (show exp) ++ ";\nABOVE: " ++ (show k) ++ ";\nENVIRONMENT: " ++ (show env) ++ "\nKONTINUATION: " ++ (show k)) True = eval_loop (eval_step state)
    | otherwise = do
        next_step <- io_eval_step state directory
        -- appendFile "./debug_output.txt" ((show next_step) ++ "\n\n")
        eval_loop_io (next_step) directory

-- Eval_loop that isnt allowed to perform IO operations
eval_loop :: EvalState -> Exp
eval_loop state@(exp, env, k)
    -- | trace ("Eval loop called with parent exp: " ++ show parent_exp) False = error "nope"
    | is_terminated state = exp
    -- | trace ("==============================\nCURRENT: " ++ (show exp) ++ ";\nABOVE: " ++ (show k) ++ ";\nENVIRONMENT: " ++ (show env) ++ "\nKONTINUATION: " ++ (show k)) True = eval_loop (eval_step state)
    | otherwise = eval_loop (eval_step state)

-- Check to see if the evaluation is terminated
is_terminated :: EvalState -> Bool
-- Failure
is_terminated (ValError _, _, _) = True
is_terminated (InternalAssertionFailed _ _ _, _, _) = True
-- We can traverse back up the tree
is_terminated (_, _, k:ks) = False
-- We are at the root of the tree, check if we can continue
is_terminated (ValNum _, _, _) = True
is_terminated (InternalAssertionSuccess _, _, _) = True
is_terminated (ValBool _, _, _) = True
is_terminated (ValInfinity, _, _) = True
is_terminated (ValString _, _, _) = True
is_terminated (ValLine _, _, _) = True
is_terminated (ValRepeatingLine _, _, _) = True
-- is_terminated (TileGenerator _ _ _, _, _) = True
is_terminated _ = False

considered_true :: EvalState -> Bool
considered_true exp = truthy_lookup evaluated_expression
    where
        evaluated_expression = eval_loop exp
        truthy_lookup :: Exp -> Bool
        truthy_lookup (ValBool True) = True
        truthy_lookup (ValNum num)
            | num /= 0 = True
            | otherwise = False
        truthy_lookup ValInfinity = True
        truthy_lookup _ = False

----------------------------
-- String conversion
----------------------------

-- Converts a terminated expression into a string
-- that we can print as output.
expression_out :: Exp -> String
expression_out (ValNum x) = show x
expression_out (ValInfinity) = "#INF"
expression_out (ValBool x) = show x
expression_out (ValString x) = x
expression_out (ValError msg) = "RUNTIME EXCEPTION: " ++ msg
expression_out (ValLine []) = "[]"
expression_out (ValLine (x:[])) = "[" ++ (expression_out x) ++ "]"
expression_out (ValLine (x:xs)) = "[" ++ (expression_out x) ++ ", " ++ (tail (expression_out (ValLine xs)))
expression_out (ValRepeatingLine xs) = "$(" ++ (expression_out (ValLine xs)) ++ ")"
expression_out (InternalAssertionSuccess exp) = "Assertion Succeeded. Check output.txt for more info."
expression_out (InternalAssertionFailed message left right)
    | length(message) <= 1000 = message
    | otherwise = "Internal assertion failed (Output too long). Please see output.txt for more info."
expression_out thing = show thing

grid_out :: Exp -> String
grid_out (ValNum x) = show (round x)
grid_out (InternalAssertionSuccess value) = grid_out value
grid_out (InternalAssertionFailed value left right) = "Actual:\n" ++ (grid_out left) ++ "\n\nExpected:\n" ++ (grid_out right)
grid_out (ValLine []) = ""
grid_out (ValLine xs)
    | length (concat [concat x ++ "\n" | x <- transpose ([[grid_out y | y <- ys] | (ValLine ys) <- xs])]) == 0 = expression_out (ValLine xs)
    | otherwise = init (concat [concat x ++ "\n" | x <- transpose ([[grid_out y | y <- ys] | (ValLine ys) <- xs])])
grid_out whatever_else = expression_out whatever_else

-- =========================
-- IO Evaluation Steps
-- =========================

-- Perform a single step of evaluation
io_eval_step :: EvalState -> String -> IO EvalState

io_eval_step (ArgumentList compiled_args, environment, In:ks) directory
    = do
        input_expression <- read_input directory (compiled_args!!0)
        return (input_expression, environment, ks)

io_eval_step (OpPrint exp, environment, ks) directory
    = do
        putStrLn (show exp)
        return (exp, environment, ks)

io_eval_step state directory = return (eval_step state)

-- Perform a single step of evaluation
eval_step :: EvalState -> EvalState

-- =========================
-- Pure Evaluation Steps
-- =========================

-- We completed evaluation of an expression inside an argument tree
eval_step (Identifier id, environment, (ArgIdNodeLeft args next):ks) = (next, environment, (ArgIdNodeRight ((Identifier id):args)):ks)
eval_step (Identifier id, environment, (ArgIdLeafLeft args):ks) = (ArgumentList (reverse ((Identifier id):args)), environment, ks)

----------------------------
-- Keyword In Argument Evaluation
----------------------------

eval_step (KeywordIn args, environment, ks) = (args, environment, In:ks)

----------------------------
-- Tile Builder
----------------------------

eval_step (TileBuilder tileBuilderRow, environment, ks)
    | length (convertToGrid tileBuilderRow) == 0 = (ValError "Tilebuilder built with 0 arguments.", environment, ks)
    -- Begin processing the first expression
    -- First we need to solve the current line, then we solve the rest
    | otherwise = ((convertToGrid tileBuilderRow)!!0!!0, environment, (TileBuilderLineFrame (tail ((convertToGrid tileBuilderRow)!!0)) []):(TileBuilderFrame (tail (convertToGrid tileBuilderRow)) []):ks)
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

eval_step (TileBuilderGrid grid, environment, ks) = (ValLine (map (\x -> ValLine x) grid), environment, ks)

-- Note: Completion of arugments is at the bottom is it depends on expression termination

----------------------------
-- Tile Builder Across
----------------------------

eval_step (TileBuilderAcross id func source, environment, ks)
    = (source, environment, (SwitchAcross id func):(TileBuilderAcrossFrame):ks)

----------------------------
-- Switch Across
----------------------------
-- This is secretly just a selector function in syntactic sugar disguise

eval_step (OpSwitchAcross varName selector source, environment, ks)
    -- This is a lot cleaner than the enumerator solution
    = (source, environment, (SwitchAcross varName selector):ks)

----------------------------
-- Range
----------------------------

eval_step (OpRange left right, environment, ks) = (left, environment, (RangeLeft right):ks)
eval_step (ValNum x, environment, (RangeLeft right):ks) = (right, environment, (RangeRight (round x)):ks)
eval_step (ValNum upper, environment, (RangeRight lower):ks) = (ValLineRange lower (round upper), environment, ks)

----------------------------
-- Index
----------------------------
-- Perform the correct resolution of the various line modification functions

-- left[right], perform right first
eval_step (OpIndex left right, environment, ks) = (right, environment, (IndexRight left):ks)
eval_step (ValNum x, environment, (IndexRight left):ks) = (left, environment, (IndexLeft (ValNum x)):ks)

eval_step (ArgumentList args, environment, (IndexRight left):ks) = (left, environment, (create_stack args) ++ ks)
    where
        create_stack :: [Exp] -> [Frame]
        create_stack [] = []
        create_stack ((ValNum x):xs) = (IndexLeft (ValNum x)) : (create_stack xs)
        create_stack ((line@(ValLine _)):xs) = (IndexLeft line) : (create_stack xs)
        create_stack ((line@(ValRepeatingLine _)):xs) = (IndexLeft line) : (create_stack xs)
        create_stack ((line@(ValLineRange _ _)):xs) = (IndexLeft line) : (create_stack xs)
        create_stack ((line@(ValLineSelect _ _)):xs) = (IndexLeft line) : (create_stack xs)
        create_stack ((line@(ValLineRangeRepeating _ _)):xs) = (IndexLeft line) : (create_stack xs)
        create_stack x = [StackError ("Attempting to perform indexing over an expression that cannot be used as an index. " ++ show x)]

-- Handle looking up with the different possible line types

-- -----------------
-- Modifier indexing
-- -----------------

-- Apply the index to every element of the source array (element in exps)
eval_step (ValLine exps, environment, ModifierIndexDepth:(IndexLeft indexer):ks)
    = (ValLineSelect (ValFunction ["_value"] (OpIndex (Identifier "_value") (ArgumentList [indexer])) environment) (ValLine exps), environment, ks)

eval_step (ValRepeatingLine exps, environment, ModifierIndexDepth:(IndexLeft indexer):ks)
    = (ValLineSelect (ValFunction ["_value"] (OpIndex (Identifier "_value") (ArgumentList [indexer])) environment) (ValRepeatingLine exps), environment, ks)

eval_step (source@(ValLineSelect _ _), environment, ModifierIndexDepth:(IndexLeft indexer):ks)
    = (ValLineSelect (ValFunction ["_value"] (OpIndex (Identifier "_value") (ArgumentList [indexer])) environment) source, environment, ks)

eval_step (source@(ValLineRange _ _), environment, ModifierIndexDepth:(IndexLeft indexer):ks)
    = (ValLineSelect (ValFunction ["_value"] (OpIndex (Identifier "_value") (ArgumentList [indexer])) environment) source, environment, ks)

eval_step (source@(ValLineRangeRepeating _ _), environment, ModifierIndexDepth:(IndexLeft indexer):ks)
    = (ValLineSelect (ValFunction ["_value"] (OpIndex (Identifier "_value") (ArgumentList [indexer])) environment) source, environment, ks)

-- -----------------
-- Regular Number indexing
-- -----------------

-- Regular line lookup
eval_step (ValLine exps, environment, (IndexLeft (ValNum x)):ks)
    | x <= 0 || x > fromIntegral (length exps) = (ValError ("Index out of bounds exception. Attempting to access index " ++ show x ++ " on an array with only " ++ show (length exps) ++ " elements."), environment, ks)
    | otherwise = (exps!!((round x) - 1), environment, ks)

-- Repeated line lookup: Mod the requested index
eval_step (ValRepeatingLine exps, environment, (IndexLeft (ValNum x)):ks)
    = (exps!!((mod (round x - 1) (length exps))), environment, RepeatIfLine:ks)

-- Select function lookup, evaluate the selector source and then lookup on that
-- Evaluate the source first, and then apply the selector function afterwards
-- ((func: x => ...) : (x in source))[1]
-- func(source[1])
eval_step (ValLineSelect selector@(ValFunction [arg_name] function env) source, environment, (IndexLeft (ValNum x)):ks)
    = (source, environment, (IndexLeft (ValNum x)):(ArgLeafLeft []):(InvokationRight selector):ks)

-- Range lookup: Ensure valid range access
eval_step (ValLineRange lower upper, environment, (IndexLeft (ValNum x)):ks)
    | x <= 0 || x > fromIntegral (upper - lower + 1) = (ValError ("Index out of bounds exception. Attempting to access index " ++ show x ++ " on an array with only " ++ show (upper - lower + 1) ++ " elements."), environment, ks)
    | otherwise = (ValNum (x + (fromIntegral lower) - 1), environment, ks)

-- Repeated Range lookup: Ensure valid range access
eval_step (ValLineRangeRepeating lower upper, environment, (IndexLeft (ValNum x)):ks)
    = (ValNum (fromIntegral ((mod (round x - 1) (upper - lower + 1)) + lower)), environment, RepeatIfLine:ks)

-- -----------------
-- Regular Line-Based indexing
-- -----------------

eval_step (ValLine line, environment, (IndexLeft (indexer)):ks)
    = (ValLineSelect (ValFunction ["_index"] (OpIndex (ValLine line) (Identifier "_index")) environment) indexer, environment, ModifierIndexDepth:ks)

eval_step (source@(ValRepeatingLine _), environment, (IndexLeft (indexer)):ks)
    = (ValLineSelect (ValFunction ["_index"] (OpIndex source (Identifier "_index")) environment) indexer, environment,  ModifierIndexDepth:ks)

eval_step (source@(ValLineSelect _ _), environment, (IndexLeft (indexer)):ks)
    = (ValLineSelect (ValFunction ["_index"] (OpIndex source (Identifier "_index")) environment) indexer, environment,  ModifierIndexDepth:ks)

eval_step (source@(ValLineRange _ _), environment, (IndexLeft (indexer)):ks)
    = (ValLineSelect (ValFunction ["_index"] (OpIndex source (Identifier "_index")) environment) indexer, environment,  ModifierIndexDepth:ks)

eval_step (source@(ValLineRangeRepeating _ _), environment, (IndexLeft (indexer)):ks)
    = (ValLineSelect (ValFunction ["_index"] (OpIndex source (Identifier "_index")) environment) indexer, environment,  ModifierIndexDepth:ks)

-- Reached the end of indexing, remove the index modifier
eval_step (exp, environment, ModifierIndexDepth:ks) = (exp, environment, ks)

----------------------------
-- Repeat
----------------------------

eval_step (OpRepeat value, environment, ks) = (value, environment, (Repeat):ks)
-- All of the things that we are allowed to repeat
eval_step (ValNum val, environment, Repeat:ks) = (ValRepeatingLine [(ValNum val)], environment, ks)
eval_step (ValInfinity, environment, Repeat:ks) = (ValRepeatingLine [(ValInfinity)], environment, ks)
eval_step (ValLine expressions, environment, Repeat:ks) = (ValRepeatingLine expressions, environment, ks)
eval_step (ValLineRange lower upper, environment, Repeat:ks) = (ValLineRangeRepeating lower upper, environment, ks)
-- $($(exp)) has no additional affect
eval_step (ValRepeatingLine expressions, environment, Repeat:ks) = (ValRepeatingLine expressions, environment, ks)
eval_step (ValLineRangeRepeating lower upper, environment, Repeat:ks) = (ValLineRangeRepeating lower upper, environment, ks)
-- For select, just apply the repeat function to the source and then rebuild the select
eval_step (ValLineSelect function source, environment, Repeat:ks) = (source, environment, (Repeat):(RepeatLine function):ks)
eval_step (exp, environment, (RepeatLine function):ks) = (ValLineSelect function exp, environment, ks)

----------------------------
-- Switch
----------------------------

-- We don't actually need to know if we are currently evaluating a switch,
-- so we can ignore it from the kontinuation
eval_step (OpSwitch exp, environment, ks) = (exp, environment, ks)
eval_step (OpSwitchCase pred left right, environment, ks) = (pred, environment, (SwitchCasePredicate left right) : ks)
eval_step (OpSwitchElse exp, environment, ks) = (exp, environment, ks)

eval_step (ValNum val, environment, (SwitchCasePredicate left right):ks)
    -- Explore the left branch, drop the predicate since we have consumed it
    -- and drop the right branch.
    | val > 0 = (left, environment, ks)
    -- Explore the right branch
    -- We can drop the case predicate, since we no longer need it
    | otherwise = (right, environment, ks)

----------------------------
-- Function Creation
----------------------------

eval_step (OpCreateFunction args exp, environment, ks) = (args, environment, (CreateFunctionArgs exp):ks)

eval_step (ArgumentList args, environment, (CreateFunctionArgs exp):ks)
    = (ValFunction (to_string args) exp environment, environment, ks)
    -- = (ValError (show (ValFunction (to_string args) exp environment)), environment, ks)
    where
        to_string :: [Exp] -> [String]
        to_string [] = []
        to_string ((Identifier id):xs) = id : (to_string xs)

----------------------------
-- Modulus
----------------------------
-- The type checker should verify that this is in-fact possible

-- Traverse the left branch
eval_step (OpModulus left right, environment, ks) = (left, environment, (ModulusLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (ModulusLeft right):ks) = (right, environment, (ModulusRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (ModulusRight (ValNum left)):ks) = (ValNum (fromIntegral (mod (round left) (round right))), environment, ks)

----------------------------
-- Multiplication
----------------------------
-- The type checker should verify that this is in-fact possible

-- Traverse the left branch
eval_step (OpMultiply left right, environment, ks) = (left, environment, (MultiplyLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (MultiplyLeft right):ks) = (right, environment, (MultiplyRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (MultiplyRight (ValNum left)):ks) = (ValNum (left * right), environment, ks)

----------------------------
-- Division
----------------------------
-- The type checker should verify that this is in-fact possible

-- Traverse the left branch
eval_step (OpDivide left right, environment, ks) = (left, environment, (DivideLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (DivideLeft right):ks) = (right, environment, (DivideRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (DivideRight (ValNum left)):ks) = (ValNum (left / right), environment, ks)

----------------------------
-- Addition
----------------------------
-- The type checker should verify that this is in-fact possible

-- Traverse the left branch
eval_step (OpAdd left right, environment, ks) = (left, environment, (AddLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (AddLeft right):ks) = (right, environment, (AddRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (AddRight (ValNum left)):ks) = (ValNum (left + right), environment, ks)

----------------------------
-- Subtraction
----------------------------
-- The type checker should verify that this is in-fact possible

-- Traverse the left branch
eval_step (OpSubtract left right, environment, ks) = (left, environment, (SubtractLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (SubtractLeft right):ks) = (right, environment, (SubtractRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (SubtractRight (ValNum left)):ks) = (ValNum (left - right), environment, ks)

----------------------------
-- Compare Less Than
----------------------------

-- Traverse the left branch
eval_step (OpCompLess left right, environment, ks) = (left, environment, (CompLessLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (CompLessLeft right):ks) = (right, environment, (CompLessRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (CompLessRight (ValNum left)):ks)
    | left < right = (ValNum 1, environment, ks)
    | otherwise = (ValNum 0, environment, ks)

----------------------------
-- Compare Less Than or Equal to
----------------------------

-- Traverse the left branch
eval_step (OpCompLessEqual left right, environment, ks) = (left, environment, (CompLessEqualLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (CompLessEqualLeft right):ks) = (right, environment, (CompLessEqualRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (CompLessEqualRight (ValNum left)):ks)
    | left <= right = (ValNum 1, environment, ks)
    | otherwise = (ValNum 0, environment, ks)

----------------------------
-- Compare Greater Than
----------------------------

-- Traverse the left branch
eval_step (OpCompGreater left right, environment, ks) = (left, environment, (CompGreaterLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (CompGreaterLeft right):ks) = (right, environment, (CompGreaterRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (CompGreaterRight (ValNum left)):ks)
    | left > right = (ValNum 1, environment, ks)
    | otherwise = (ValNum 0, environment, ks)

----------------------------
-- Compare Greater Than or Equal to
----------------------------

-- Traverse the left branch
eval_step (OpCompGreaterEqual left right, environment, ks) = (left, environment, (CompGreaterEqualLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (CompGreaterEqualLeft right):ks) = (right, environment, (CompGreaterEqualRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (CompGreaterEqualRight (ValNum left)):ks)
    | left >= right = (ValNum 1, environment, ks)
    | otherwise = (ValNum 0, environment, ks)

----------------------------
-- Compare Equal to
----------------------------

-- Traverse the left branch
eval_step (OpCompEqual left right, environment, ks) = (left, environment, (CompEqualLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (CompEqualLeft right):ks) = (right, environment, (CompEqualRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (CompEqualRight (ValNum left)):ks)
    | left == right = (ValNum 1, environment, ks)
    | otherwise = (ValNum 0, environment, ks)

----------------------------
-- Compare Not Equal to
----------------------------

-- Traverse the left branch
eval_step (OpCompNotEqual left right, environment, ks) = (left, environment, (CompNotEqualLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (CompNotEqualLeft right):ks) = (right, environment, (CompNotEqualRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (CompNotEqualRight (ValNum left)):ks)
    | left /= right = (ValNum 1, environment, ks)
    | otherwise = (ValNum 0, environment, ks)

----------------------------
-- Logical And
----------------------------
-- Expects an integer, if given a float then it will round the float
-- (Direction of rounding is unspecified) and then use the rounded number
-- to perform the bitwise operation.
-- We should type check to ensure that only ints are given here

-- Traverse the left branch
eval_step (OpLogicalAnd left right, environment, ks) = (left, environment, (LogicalAndLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (LogicalAndLeft right):ks) = (right, environment, (LogicalAndRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (LogicalAndRight (ValNum left)):ks) = (ValNum (fromIntegral ((round_up left) .&. (round_up right))), environment, ks)
    where
        round_up :: Float -> Int
        round_up x = (round x)

----------------------------
-- Logical Xor
----------------------------
-- Expects an integer, if given a float then it will round the float
-- (Direction of rounding is unspecified) and then use the rounded number
-- to perform the bitwise operation.
-- We should type check to ensure that only ints are given here

-- Traverse the left branch
eval_step (OpLogicalXor left right, environment, ks) = (left, environment, (LogicalXorLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (LogicalXorLeft right):ks) = (right, environment, (LogicalXorRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (LogicalXorRight (ValNum left)):ks) = (ValNum (fromIntegral (xor (round_up left) (round_up right))), environment, ks)
    where
        round_up :: Float -> Int
        round_up x = (round x)

----------------------------
-- Logical Or
----------------------------
-- Expects an integer, if given a float then it will round the float
-- (Direction of rounding is unspecified) and then use the rounded number
-- to perform the bitwise operation.
-- We should type check to ensure that only ints are given here

-- Traverse the left branch
eval_step (OpLogicalOr left right, environment, ks) = (left, environment, (LogicalOrLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (LogicalOrLeft right):ks) = (right, environment, (LogicalOrRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (LogicalOrRight (ValNum left)):ks) = (ValNum (fromIntegral ((round_up left) .|. (round_up right))), environment, ks)
    where
        round_up :: Float -> Int
        round_up x = (round x)

----------------------------
-- Logical Not
----------------------------
-- Expects an integer, if given a float then it will round the float
-- (Direction of rounding is unspecified) and then use the rounded number
-- to perform the bitwise operation.
-- We should type check to ensure that only ints are given here

-- Traverse the left branch
eval_step (OpLogicalNot child, environment, ks) = (child, environment, LogicalNot:ks)
-- Evaluate the expression
eval_step (ValNum val, environment, LogicalNot:ks) = (ValNum (fromIntegral (complement (round_up val))), environment, ks)
    where
        round_up :: Float -> Int
        round_up x = (round x)

----------------------------
-- Comparative And
----------------------------

-- Traverse the left branch
eval_step (OpComparativeAnd left right, environment, ks) = (left, environment, (ComparativeAndLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (ComparativeAndLeft right):ks) = (right, environment, (ComparativeAndRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (ComparativeAndRight (ValNum left)):ks)
    | left > 0 && right > 0 = (ValNum right, environment, ks)
    | otherwise = (ValNum 0, environment, ks)

----------------------------
-- Comparative Or
----------------------------

-- Traverse the left branch
eval_step (OpComparativeOr left right, environment, ks) = (left, environment, (ComparativeOrLeft right):ks)
-- Traverse the right branch
eval_step (ValNum left, environment, (ComparativeOrLeft right):ks)
    -- Short circuit and travel upwards immediately
    | left > 0 = (ValNum left, environment, ks)
    -- Otherwise continue
    | otherwise = (right, environment, (ComparativeOrRight (ValNum left)):ks)
-- Evaluate the expression
eval_step (ValNum right, environment, (ComparativeOrRight (ValNum left)):ks)
    | right > 0 = (ValNum right, environment, ks)
    | otherwise = (ValNum 0, environment, ks)

----------------------------
-- Comparative Not
----------------------------

eval_step (OpComparativeNot child, environment, ks) = (child, environment, (ComparativeNot):ks)
eval_step (ValNum val, environment, ComparativeNot:ks)
    | val > 0 = (ValNum 0, environment, ks)
    | otherwise = (ValNum 1, environment, ks)

----------------------------
-- Assign
----------------------------
-- Determine what we want to assign to
-- !! MUST BE HIGHER THAN IDENTIFIER LOOKUP !!

eval_step (OpAssign left right, environment, ks) = (left, environment, (AssignLeft right):ks)
eval_step (Identifier id, environment, (AssignLeft right):ks) = (right, environment, (AssignRight (Identifier id)):ks)

-- All of the things we are allowed to assign
-- Return the assigned value
eval_step (ValNum num, environment, (AssignRight (Identifier identifier)):ks) = (ValNum num, (identifier, VarExpression (ValNum num)):environment, ks)
-- We are also allowed to assign functions to variables, so that we can call on them
eval_step (ValFunction args body env, environment, (AssignRight (Identifier identifier)):ks) = (ValFunction args body env, (identifier, VarExpression (ValFunction args body env)):environment, ks)
eval_step (val@(ValLine args), environment, (AssignRight (Identifier identifier)):ks) = (val, (identifier, VarExpression val):environment, ks)
eval_step (val@(ValRepeatingLine args), environment, (AssignRight (Identifier identifier)):ks) = (val, (identifier, VarExpression val):environment, ks)
eval_step (val@(ValLineSelect _ _), environment, (AssignRight (Identifier identifier)):ks) = (val, (identifier, VarExpression val):environment, ks)
eval_step (val@(ValLineRange _ _), environment, (AssignRight (Identifier identifier)):ks) = (val, (identifier, VarExpression val):environment, ks)
eval_step (val@(ValLineRangeRepeating _ _), environment, (AssignRight (Identifier identifier)):ks) = (val, (identifier, VarExpression val):environment, ks)
eval_step (val@(ValBuiltTiles _ _ _), environment, (AssignRight (Identifier identifier)):ks) = (val, (identifier, VarExpression val):environment, ks)

----------------------------
-- Sequence
----------------------------

eval_step (OpSequence left right, environment, ks) =  (left, environment, (SequenceLeft right):ks)

----------------------------
-- Local Scope Entry
----------------------------
-- When entering a local scope, we need to know the state of the
-- environment before.
-- Note that the current implementation may give rise to some strange
-- behaviours, notably we can access variables that are in the
-- parent environment but assigning to a defined variable will only
-- affect the local scope and the value of the variable will reset
-- afterwards.
-- This needs to be last as it should be the last pattern match

-- Step into the local scope
eval_step (OpScopeEntry exp, environment, ks) = (exp, environment, (LocalScope environment):ks)

----------------------------
-- ValBool Conversion
----------------------------
-- Internally, we deal with numbers.

eval_step (ValBool True, environment, ks) = (ValNum 1.0, environment, ks)
eval_step (ValBool False, environment, ks) = (ValNum 0.0, environment, ks)

----------------------------
-- Function Calls
----------------------------
-- !! MUST BE HIGHER THAN IDENTIFIER LOOKUP !!

-- Step 1: Resolve the arguments
eval_step (OpInvokationArgs left args, environment, ks) = (args, environment, (InvokationRight left):ks)
eval_step (ArgumentList args, environment, (InvokationRight left):ks) = (left, environment, (InvokationLeft args):ks)

-- Step 2: Call the function

-- Call function by internal names
eval_step ((Identifier "debug"), environment, (InvokationLeft [exp]):ks) = (ValError ("DEBUG: " ++ show exp), environment, ks)

eval_step ((Identifier "print"), environment, (InvokationLeft [exp]):ks) = (OpPrint exp, environment, ks)

eval_step ((Identifier "length"), environment, (InvokationLeft [(ValLine line)]):ks) = (ValNum (fromIntegral (length line)), environment, ks)
eval_step ((Identifier "length"), environment, (InvokationLeft [(ValLineRange lower upper)]):ks) = (ValNum (fromIntegral (upper - lower + 1)), environment, ks)
eval_step ((Identifier "length"), environment, (InvokationLeft [(ValLineRangeRepeating lower upper)]):ks) = (ValInfinity, environment, ks)
-- For the selector, just take a look at the source
eval_step ((Identifier "length"), environment, (InvokationLeft [(ValLineSelect _ source)]):ks) = ((Identifier "length"), environment, (InvokationLeft [source]):ks)
eval_step ((Identifier "length"), environment, (InvokationLeft [exp]):ks) = (ValError ("Invalid arguments to length function. Arguments: " ++ show exp), environment, ks)

----------------------------
-- Identifier Lookup
----------------------------
-- Needs to be after assign for cases where we want to store to the identifier
-- rather than access it

eval_step (Identifier name, environment, ks) = (environment_lookup name environment environment, environment, ks)

----------------------------
-- Function stored in identifier calls
----------------------------

-- Direct function invokation
eval_step (ValFunction params body env, environment, (InvokationLeft args):ks)
    -- Modify the environment and save the state that we were in before
    -- Add all the params of the function into the environment with the associated arg as the value
    -- Add an environment restore command to the kontinuation
    = (body, (zip params (map (\x -> VarExpression x) args)) ++ env ++ environment, (LocalScope environment):ks)

eval_step (_, environment, (InvokationLeft args):ks) = (ValError ("Attempting to invoke an expression that is not a function."), environment, ks)


----------------------------
-- Assert (IO)
----------------------------
-- Determine what we want to assign to

eval_step (OpAssertion left right, environment, ks) = (left, environment, (AssertionLeft right):ks)

----------------------------
-- Haskell Assertion (Ignore)
----------------------------

eval_step (HaskellAssertion expression expected, environment, stack) = (ValNum 0, environment, stack)

-- ==========================
-- Operations that depend on termination
-- ==========================

-- Local scope step out
-- Step out of the local scope now that we cannot perform any more execution
eval_step (exp, environment, (LocalScope oldEnvironment):ks) = (exp, oldEnvironment, ks)

-- Sequence step out
eval_step (exp, environment, (SequenceLeft right):ks) = (right, environment, ks)

-- Select resolution
eval_step (resolved_source, environment, (SwitchAcross varName selector):ks)
    = (ValLineSelect (ValFunction [varName] selector environment) resolved_source, environment, ks)


-- Repeat if its a line
eval_step (exp@(ValLine _), environment, RepeatIfLine:ks) = (exp, environment, Repeat:ks)
eval_step (exp@(ValLineSelect _ _), environment, RepeatIfLine:ks) = (exp, environment, Repeat:ks)
eval_step (exp@(ValLineRange _ _), environment, RepeatIfLine:ks) = (exp, environment, Repeat:ks)
eval_step (exp, environment, RepeatIfLine:ks) = (exp, environment, ks)

----------------------------
-- Argument Identifiers Evaluation
----------------------------

-- Evaluate arguments
-- When we reach an argument node and aren't inside an argument node, then
-- start evaluating the argumentlist with a default of empty.
-- Once we complete expression evaluation, add it to the argument list

-- We are already inside an argument tree and moving to the next node
eval_step (OpArgIdTree current next, environment, (ArgIdNodeRight args):ks) = (current, environment, (ArgIdNodeLeft args next):ks)

-- We are starting an argument tree
eval_step (OpArgIdTree current next, environment, ks) = (current, environment, (ArgIdNodeLeft [] next):ks)

-- We have completed evlauation of our argument tree
eval_step (OpArgIdLeaf current, environment, (ArgIdNodeRight args):ks) = (current, environment, (ArgIdLeafLeft args):ks)

-- We completed evaluation of an expression inside an argument tree
eval_step (exp, environment, (ArgIdNodeLeft args next):ks) = (next, environment, (ArgIdNodeRight (exp:args)):ks)
eval_step (exp, environment, (ArgIdLeafLeft args):ks) = (ArgumentList (reverse (exp:args)), environment, ks)

-- We only have a single argument
eval_step (OpArgIdLeaf current, environment, ks) = (current, environment, (ArgIdLeafLeft []):ks)


----------------------------
-- Argument Evaluation
----------------------------

-- Evaluate arguments
-- When we reach an argument node and aren't inside an argument node, then
-- start evaluating the argumentlist with a default of empty.
-- Once we complete expression evaluation, add it to the argument list

-- We are already inside an argument tree and moving to the next node
eval_step (OpArgumentTree current next, environment, (ArgNodeRight args):ks) = (current, environment, (ArgNodeLeft args next):ks)

-- We are starting an argument tree
eval_step (OpArgumentTree current next, environment, ks) = (current, environment, (ArgNodeLeft [] next):ks)
-- We completed evaluation of an expression inside an argument tree
eval_step (exp, environment, (ArgNodeLeft args next):ks) = (next, environment, (ArgNodeRight (exp:args)):ks)

-- We have completed evlauation of our argument tree
eval_step (OpArgumentLeaf current, environment, (ArgNodeRight args):ks) = (current, environment, (ArgLeafLeft args):ks)
eval_step (exp, environment, (ArgLeafLeft args):ks) = (ArgumentList (reverse (exp:args)), environment, ks)

-- We only have a single argument
eval_step (OpArgumentLeaf current, environment, ks) = (current, environment, (ArgLeafLeft []):ks)

----------------------------
-- Return Value Completion
----------------------------
-- !! MUST BE HIGHER THAN ASSERTIONS !!

-- We are only allowed to do this if we need it to be done, as this can be super expensive
-- Our kontinuation needs to either be empty, or contain an assertion as these are the only 2 cases
-- where we would want to fully resolve a line.
-- If we aren't in those states, then there is an evaluation error and we are missing a pattern match somewhere.

eval_step (ValLineRange lower upper, environment, []) = (ValLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, [])
eval_step (ValLineRangeRepeating lower upper, environment, []) = (ValRepeatingLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, [])
eval_step (ValLineSelect func target, environment, []) = (target, environment, (SelectPreCompilation func):[])

eval_step (ValLineRange lower upper, environment, (SelectPreCompilation f1):ks) = (ValLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, (SelectPreCompilation f1):ks)
eval_step (ValLineRangeRepeating lower upper, environment, (SelectPreCompilation f1):ks) = (ValRepeatingLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, (SelectPreCompilation f1):ks)
eval_step (ValLineSelect func target, environment, (SelectPreCompilation f1):ks) = (target, environment, (SelectPreCompilation func):(SelectPreCompilation f1):ks)

eval_step (ValLineRange lower upper, environment, (a@(SelectCompilation _ _ _)):ks) = (ValLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, a:ks)
eval_step (ValLineRangeRepeating lower upper, environment, (a@(SelectCompilation _ _ _)):ks) = (ValRepeatingLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, a:ks)
eval_step (ValLineSelect func target, environment, (a@(SelectCompilation _ _ _)):ks) = (target, environment, (SelectPreCompilation func):a:ks)

eval_step (ValLineRange lower upper, environment, (a@(SelectCompilationRepeating _ _ _)):ks) = (ValLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, a:ks)
eval_step (ValLineRangeRepeating lower upper, environment, (a@(SelectCompilationRepeating _ _ _)):ks) = (ValRepeatingLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, a:ks)
eval_step (ValLineSelect func target, environment, (a@(SelectCompilationRepeating _ _ _)):ks) = (target, environment, (SelectPreCompilation func):a:ks)

eval_step (ValLineRange lower upper, environment, (a@(TileBuilderLineFrame _ _)):ks) = (ValLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, a:ks)
eval_step (ValLineRangeRepeating lower upper, environment, (a@(TileBuilderLineFrame _ _)):ks) = (ValRepeatingLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, a:ks)
eval_step (ValLineSelect func target, environment, (a@(TileBuilderLineFrame _ _)):ks) = (target, environment, (SelectPreCompilation func):a:ks)

eval_step (ValLineRange lower upper, environment, (a@(TileBuilderAcrossFrame)):ks) = (ValLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, a:ks)
eval_step (ValLineRangeRepeating lower upper, environment, (a@(TileBuilderAcrossFrame)):ks) = (ValRepeatingLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, a:ks)
eval_step (ValLineSelect func target, environment, (a@(TileBuilderAcrossFrame)):ks) = (target, environment, (SelectPreCompilation func):a:ks)

eval_step (ValLineRange lower upper, environment, (AssertionLeft right):ks) = (ValLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, (AssertionLeft right):ks)
eval_step (ValLineRangeRepeating lower upper, environment, (AssertionLeft right):ks) = (ValRepeatingLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, (AssertionLeft right):ks)
eval_step (ValLineSelect func target, environment, (AssertionLeft right):ks) = (target, environment, (SelectPreCompilation func):(AssertionLeft right):ks)

eval_step (ValLineRange lower upper, environment, (AssertionRight left):ks) = (ValLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, (AssertionRight left):ks)
eval_step (ValLineRangeRepeating lower upper, environment, (AssertionRight left):ks) = (ValRepeatingLine (map (\x -> (ValNum (fromIntegral x))) [lower..upper]), environment, (AssertionRight left):ks)
eval_step (ValLineSelect func target, environment, (AssertionRight left):ks) = (target, environment, (SelectPreCompilation func):(AssertionRight left):ks)

-- If ValLineSelect gets returned from the program, then convert it into a normal list.
eval_step (ValLine [], environment, (SelectPreCompilation func):ks) = (ValLine [], environment, ks)
eval_step (ValLine (x:xs), environment, (SelectPreCompilation (ValFunction [argName] func env)):ks) = (func, (argName, VarExpression x):(env ++ environment), (LocalScope environment):(SelectCompilation (ValFunction [argName] func env) xs []):ks)
eval_step (ValRepeatingLine [], environment, (SelectPreCompilation func):ks) = (ValRepeatingLine [], environment, ks)
eval_step (ValRepeatingLine (x:xs), environment, (SelectPreCompilation (ValFunction [argName] func env)):ks) = (func, (argName, VarExpression x):(env ++ environment), (LocalScope environment):(SelectCompilationRepeating (ValFunction [argName] func env) xs []):ks)

--eval_step (exp, environment, (SelectPreCompilation func):ks) = (exp, environment, ks)

eval_step (exp, environment, (SelectCompilation func [] current):ks) = (ValLine (reverse (exp:current)), environment, ks)
eval_step (exp, environment, (SelectCompilation (ValFunction [argName] func env) (x:xs) current):ks) = (func, (argName, VarExpression x):(env ++ environment), (LocalScope environment):(SelectCompilation (ValFunction [argName] func env) xs (exp:current)):ks)

eval_step (exp, environment, (SelectCompilationRepeating func [] current):ks) = (ValRepeatingLine (reverse (exp:current)), environment, ks)
eval_step (exp, environment, (SelectCompilationRepeating (ValFunction [argName] func env) (x:xs) current):ks) = (func, (argName, VarExpression x):(env ++ environment), (LocalScope environment):(SelectCompilationRepeating (ValFunction [argName] func env) xs (exp:current)):ks)

----------------------------
-- Tile Builder
-- Note: Outputs need to be compiled as if they are a return value to be used in a line builder,
-- line builders are not lazy and will instantly resolve any lazy lines inside of them.
----------------------------

-- Fully completed the tile builder evaluation
-- Since we have compiled exps into output form, we know they will either be ValLine or ValRepeatingLine, or a non-line expression
eval_step (exp, environment, (TileBuilderLineFrame [] current):(TileBuilderFrame [] built):ks)
    -- = error (show (compile_tile_builder (reverse ((reverse (exp:current)):built))))
    = (TileBuilderGrid (compile_tile_builder (reverse ((reverse (exp:current)):built))), environment, ks)
        
-- Completed this line, but have more lines to process
eval_step (exp, environment, (TileBuilderLineFrame [] current):(TileBuilderFrame (x:xs) built):ks) = (x!!0, environment, (TileBuilderLineFrame (tail x) []):(TileBuilderFrame xs ((reverse (exp:current)):built)):ks)
-- This line is not completed, move to the next element
eval_step (exp, environment, (TileBuilderLineFrame (x:xs) current):ks) = (x, environment, (TileBuilderLineFrame (xs) (exp:current)):ks)

-- Convert into a tile builder
eval_step (exp, environment, (TileBuilderAcrossFrame):ks) = (TileBuilderGrid (compile_tile_builder (get_grid_from_lines exp)), environment, ks)
    where
        get_grid_from_lines :: Exp -> [[Exp]]
        get_grid_from_lines (ValLine exps) = map get_array_from_line exps
        get_grid_from_lines (ValNum y) = [[ValNum y]]
        get_array_from_line :: Exp -> [Exp]
        get_array_from_line (ValLine exps) = exps
        get_array_from_line (ValNum x) = [ValNum x]
        get_array_from_line exp = error ("Fatal error, unexpected input to get_array_from_line : " ++ (show exp))

----------------------------
-- Assertions
----------------------------

eval_step (left, environment, (AssertionLeft right):ks) = (right, environment, (AssertionRight left):ks)
eval_step (right, environment, (AssertionRight left):ks)
    -- Pass the assertion
    | expression_out right == expression_out left = (InternalAssertionSuccess left, environment, ks)
    -- Terminate the execution
    | otherwise = (InternalAssertionFailed ("Assertion failed, expected: " ++ expression_out right ++ ", actual: " ++ expression_out left) left right, [], [])

----------------------------
-- Evaluation Error
----------------------------

eval_step (exp, environment, (StackError msg):ks) = (ValError msg, environment, ks)

eval_step state@(statement, environment, stack)
    -- This is a hack, I'm sorry
    | is_terminated state = state
    | otherwise = (ValError ("Evaluation error, could not evaluate the expression '" ++ (show statement) ++ "', stack: " ++ (show stack)), [], [])

-- ==========================
-- OpMemberAccess Exp Exp
-- OpArgumentTree Exp Exp
-- OpArgumentLeaf Exp
-- OpInvokation Exp
-- OpInvokationArgs Exp Exp
-- OpIndex Exp Exp                  -- COMPLETED (Needs multi-dimensional support)
-- OpSwitch Exp                  -- COMPLETED
-- OpSwitchAcross String Exp Exp                  -- COMPLETED
-- OpSwitchCase Exp Exp Exp                  -- COMPLETED
-- OpSwitchElse Exp                  -- COMPLETED
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
-- OpAssertion Exp Exp
-- HaskellAssertion Exp String
-- KeywordIn Exp
-- Identifier String                  -- COMPLETED
-- ValNum Int
-- ValBool Bool
-- ValString String
-- TileBuilder TileBuilderRow
-- ==========================

-- Compile the tile builder.
-- Deal with grids being inside the tile builder elements.
-- Not that while at each step, we reduce the dimensions of the input, the dimensions
-- of the output stay the same which allows us to reduce 4D arrays into 2D arrays via
-- grid concatenation.
compile_tile_builder :: [[Exp]] -> [[Exp]]
compile_tile_builder (line:lines) = (compile_tile_line line) ++ (compile_tile_builder lines)
compile_tile_builder [] = []
-- Compile a line of the tile builder
compile_tile_line :: [Exp] -> [[Exp]]
compile_tile_line (x:xs) = make (compile_tile_expression x) (compile_tile_line xs)
    where
        make :: [[Exp]] -> [[Exp]] -> [[Exp]]
        make (a:as) (b:bs) = (a ++ b) : (make as bs)
        make (a:as) [] = (a) : (make as [])
        make [] [] = []
compile_tile_line [] = []
-- Compile a single element of the tile builder
compile_tile_expression :: Exp -> [[Exp]]
-- Convert from a 4D array into a 2D array by concatenating tiles together
-- TODO: Allow for repeating lines to be inserted into this
compile_tile_expression (ValLine exps) = foldl compile_line [] exps
-- Non-line building
compile_tile_expression exp = [[exp]]
compile_line :: [[Exp]] -> Exp -> [[Exp]]
-- Add the line to the grid
-- TODO: Allow for repeating elements
compile_line current (ValLine exps) = current ++ [exps]
-- For some reason we are building with a 1D array.
compile_line current exp = ([exp]):current
