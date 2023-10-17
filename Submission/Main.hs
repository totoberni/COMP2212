module Main (main) where

import Control.Applicative
import Control.Exception
import Data.String
import Debug.Trace
import System.Directory
import System.Environment
import System.IO
import PlLexer
import PlParser
import PlInterpreter
import PiTypeChecker

main :: IO()
main = do
    args <- getArgs
    result <- evalCode (args!!0)
    output_proper (lines result)
    where
        output_proper [] = return ()
        output_proper (x:xs) = do
            putStrLn x
            output_proper xs

parseCode :: String -> IO([Token])
parseCode fileName = do
    fileText <- readFile fileName
    return (alexScanTokens fileText)

parseRawCode :: String -> IO(Exp)
parseRawCode fileText = do
    --putStrLn (show $ alexScanTokens fileText)
    return (parseCalc (alexScanTokens fileText))

evalCode :: String -> IO(String)
evalCode fileName = do
    fileText <- readFile fileName
    evalRawCode fileText (get_path fileName "")

runProgram :: Int -> IO(String)
runProgram program = do
    result <- evalCode ("programs/problem" ++ show program ++ "/pr" ++ show program ++ ".tsl")
    writeFile "./execution_output.txt" result
    return result

evalRawCode :: String -> String -> IO(String)
evalRawCode code dir = do
    --putStrLn (show $ alexScanTokens code)
    --putStrLn (show (parseCalc (alexScanTokens code)))
    -- evaluted_output <- evaluate_exp (parseCalc (alexScanTokens code)) dir
    -- putStrLn (show $ evaluted_output)
    case runTypeChecker (parseCalc (alexScanTokens code)) of
        Nothing -> do
            output_text <- output_formatted_exp (parseCalc (alexScanTokens code)) dir
            return output_text
        Just msg -> do
            hPutStrLn stderr "TYPE CHECKER FAILED"
            hPutStrLn stderr msg
            output_text <- output_formatted_exp (parseCalc (alexScanTokens code)) dir
            return output_text

typeRawCode :: String -> IO(String)
typeRawCode code = return (show (getExpType (parseCalc (alexScanTokens code))))

standardChecks = do
    all <- getDirectoryContents "./checks"
    --map checkStaticAssertions all
    checkFiles "./checks" all
    return all

checkFiles :: String -> [String] -> IO()
checkFiles a [] = return ()
checkFiles a (x:xs)
    | length x < 3 || last x /= 'l' || last (init x) /= 's' || last (init (init x)) /= 'p' = do
        checkFiles a xs
        return ()
    | otherwise = do
        isNotDirectory <- (doesFileExist (a ++ "/" ++ x))
        doTask isNotDirectory
    where
        doTask :: Bool -> IO()
        doTask b
            | b = do
                putStrLn ("Checking " ++ a ++ "/" ++ x)
                checkStaticAssertions (a ++ "/" ++ x)
                checkRuntimeAssertions (a ++ "/" ++ x)
                checkFiles a xs
                return ()
            | otherwise = do
                all <- getDirectoryContents (a ++ "/" ++ x) 
                checkFiles (a ++ "/" ++ x) all
                checkFiles a xs
                return ()

checkStaticAssertions :: String -> IO()
checkStaticAssertions fileName = do
    fileText <- readFile fileName
    let tokens = alexScanTokens fileText
    --putStrLn (show tokens)
    let parsed = parseCalc tokens
    --putStrLn (show parsed)
    printResult (runTypeChecker parsed)
    where
        printResult :: Maybe String -> IO()
        printResult (Nothing) = do
            putStrLn ("File: " ++ fileName ++ ": PASSED TYPE CHECKER")
        printResult (Just x) = do
            putStrLn ("File: " ++ fileName ++ ": --FAILED TYPE CHECKER: " ++ x ++ " --")

checkTypeChecker :: String -> IO()
checkTypeChecker fileName = do
    fileText <- readFile fileName
    let tokens = alexScanTokens fileText
    let parsed = parseCalc tokens
    evaluated <- evaluate_exp parsed (get_path fileName "")
    printResult evaluated
    where
        printResult :: Exp -> IO()
        printResult (InternalAssertionFailed message _ _) = do
            putStrLn ("File: " ++ fileName ++ ": --ASSERTION FAILED-- (" ++ message ++ ")")
        printResult (ValError message) = do
            putStrLn ("File: " ++ fileName ++ ": --ASSERTION FAILED-- (" ++ message ++ ")")
        printResult result = do
            putStrLn ("File: " ++ fileName ++ ": PASSED. Result: '" ++ (show result) ++ "'")

checkRuntimeAssertions :: String -> IO()
checkRuntimeAssertions fileName = do
    fileText <- readFile fileName
    let tokens = alexScanTokens fileText
    let parsed = parseCalc tokens
    evaluated <- evaluate_exp parsed (get_path fileName "")
    printResult evaluated
    where
        printResult :: Exp -> IO()
        printResult (InternalAssertionFailed message _ _) = do
            putStrLn ("File: " ++ fileName ++ ": --ASSERTION FAILED-- (" ++ message ++ ")")
        printResult (ValError message) = do
            putStrLn ("File: " ++ fileName ++ ": --ASSERTION FAILED-- (" ++ message ++ ")")
        printResult result = do
            putStrLn ("File: " ++ fileName ++ ": PASSED. Result: '" ++ (show result) ++ "'")

get_path :: String -> String -> String
get_path [] x = ""
get_path (y:ys) x
    | y == '/' = (reverse x) ++ "/" ++ (get_path ys [])
    | otherwise = get_path (ys) (y:x)

exploreAssertions :: Exp -> Bool
exploreAssertions (OpMemberAccess left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpArgumentTree left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpArgumentLeaf x) = exploreAssertions x
exploreAssertions (OpInvokation x) = exploreAssertions x
exploreAssertions (OpInvokationArgs left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpIndex left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpSwitch x) = exploreAssertions x
exploreAssertions (OpSwitchAcross x y z) = (exploreAssertions y) && (exploreAssertions z)
exploreAssertions (TileBuilderAcross x y z) = (exploreAssertions y) && (exploreAssertions z)
exploreAssertions (OpSwitchCase x y z) = (exploreAssertions x) && (exploreAssertions y) && (exploreAssertions z)
exploreAssertions (OpSwitchElse x) = exploreAssertions x
exploreAssertions (OpMultiply left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpDivide left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpAdd left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpSubtract left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpCompLess left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpCompLessEqual left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpCompGreater left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpCompGreaterEqual left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpCompEqual left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpCompNotEqual left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpLogicalAnd left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpLogicalXor left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpLogicalOr left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpLogicalNot x) = exploreAssertions x
exploreAssertions (OpScopeEntry x) = exploreAssertions x
exploreAssertions (OpComparativeAnd left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpComparativeOr left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpComparativeNot x) = exploreAssertions x
exploreAssertions (OpRange left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpAssign left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpRepeat x) = exploreAssertions x
exploreAssertions (OpSequence left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpAssertion left right) = (exploreAssertions left) && (exploreAssertions right)
exploreAssertions (OpCreateFunction left right) = (exploreAssertions right)
--exploreAssertions (HaskellAssertion left right) | trace right True = left == (read right)
exploreAssertions (HaskellAssertion left right) = left == (read right)
exploreAssertions (KeywordIn x) = exploreAssertions x
exploreAssertions (TileBuilder a) = True
exploreAssertions (Identifier _) = True
exploreAssertions (ValNum _) = True
exploreAssertions (ValBool _) = True
exploreAssertions (ValString _) = True
exploreAssertions missing = error ("Missing static assertion explore: " ++ show missing)
