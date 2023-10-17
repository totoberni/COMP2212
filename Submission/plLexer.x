{ 
module PlLexer where 
}

%wrapper "posn" 

$digit = 0-9     
-- digits 
$alpha = [a-zA-Z]    
-- alphabetic characters

tokens :-
    "//".*\n          ;
    "//".*            ;
    -- Handle line breaks (Requires for multi-line functions)
    (\n|\r)+                { \p -> (\s -> TokenBreak p) }
    -- Handle Ignored Characters
    $white+           ;
    -- Special case
    "#{"[a-zA-Z0-9_\'\ \(\)\"\.]*"}"         { \p -> (\s -> TokenHaskell p (take (length s - 3) (tail (tail s)))) }
    -- Handle Base Value Types
    $digit+           { \p -> (\s -> TokenInt p (read s)) }
    false             { \p -> (\s -> TokenBool p False)}
    true              { \p -> (\s -> TokenBool p True)}
    -- Handle operators that contain other operators (Have to be performed first in order to match them properly)
    ".""."+           { \p -> (\s -> TokenRangeDot p) }
    "<="              { \p -> (\s -> TokenComparisonLessEq p) }
    ">="              { \p -> (\s -> TokenComparisonGreaterEq p) }
    "=="              { \p -> (\s -> TokenComparisonEq p) }
    "!="              { \p -> (\s -> TokenComparisonNotEq p) }
    "&&"              { \p -> (\s -> TokenBooleanAnd p) }
    "||"              { \p -> (\s -> TokenBooleanOr p) }
    "=>"              { \p -> (\s -> TokenArrow p) }
    "~="              { \p -> (\s -> TokenAssert p) }
    -- Handle language keywords
    "in"              { \p -> (\s -> TokenIn p) }
    "switch"          { \p -> (\s -> TokenSwitch p) }
    "else"            { \p -> (\s -> TokenElse p) }
    "blank"           { \p -> (\s -> TokenBlank p) }
    "case"            { \p -> (\s -> TokenCase p) }
    "proc"            { \p -> (\s -> TokenProc p) }
    -- Handle operators
    "="               { \p -> (\s -> TokenEquals p) }
    -- Handle mathematical operators
    "+"               { \p -> (\s -> TokenAdd p) }
    "-"               { \p -> (\s -> TokenSubtract p) }
    "*"               { \p -> (\s -> TokenMultiply p) }
    "/"               { \p -> (\s -> TokenDivide p) }
    -- Handle boolean operators
    "!"               { \p -> (\s -> TokenBooleanNot p) }
    -- Handle comparison operators
    "<"               { \p -> (\s -> TokenComparisonLess p) }
    ">"               { \p -> (\s -> TokenComparisonGreater p) }
    -- Handle bitwise operators
    "&"               { \p -> (\s -> TokenBitwiseAnd p) }
    "|"               { \p -> (\s -> TokenBitwiseOr p) }
    "~"               { \p -> (\s -> TokenBitwiseNot p) }
    "^"               { \p -> (\s -> TokenBitwiseXor p) }
    "%"               { \p -> (\s -> TokenModulus p) }
    -- Handle symbols
    "$"               { \p -> (\s -> TokenDollar p) }
    "."               { \p -> (\s -> TokenDot p) }
    ";"               { \p -> (\s -> TokenSemiColon p) }
    ":"               { \p -> (\s -> TokenColon p) }
    ","               { \p -> (\s -> TokenComma p) }
    -- Handle parenthesisation
    "("               { \p -> (\s -> TokenBracketOpen p) }
    ")"               { \p -> (\s -> TokenBracketClose p) }
    "{"               { \p -> (\s -> TokenCurlyBracketOpen p) }
    "}"               { \p -> (\s -> TokenCurlyBracketClose p) }
    "["               { \p -> (\s -> TokenSquareBracketOpen p) }
    "]"               { \p -> (\s -> TokenSquareBracketClose p) }
    -- Consider anything else a variable/function name
    [a-zA-Z0-9_\']+   { \p -> (\s -> TokenVar p s)}
{

-- Each action has type :: AlexPosn -> String -> Token 
-- The token type: 
data Token = 
    -- New line (Special type that handles multiline operations)
    TokenBreak AlexPosn |
    -- Haskell Code
    TokenHaskell AlexPosn String |
    -- Value Types
    TokenInt AlexPosn Int |
    TokenBool AlexPosn Bool |
    TokenVar AlexPosn String |
    TokenString AlexPosn String |
    -- Assertion
    TokenAssert AlexPosn |
    -- Language Keywords
    TokenIn AlexPosn |
    TokenSwitch AlexPosn |
    TokenCase AlexPosn |
    TokenElse AlexPosn |
    TokenBlank AlexPosn |
    TokenProc AlexPosn |
    -- Operators
    TokenEquals AlexPosn |
    TokenArrow AlexPosn |
    -- Mathematical Operators
    TokenAdd AlexPosn |
    TokenSubtract AlexPosn |
    TokenMultiply AlexPosn |
    TokenDivide AlexPosn |
    TokenModulus AlexPosn |
    -- Boolean Operators
    TokenBooleanAnd AlexPosn |
    TokenBooleanOr AlexPosn |
    TokenBooleanNot AlexPosn |
    -- Comparison Operators
    TokenComparisonLess AlexPosn |
    TokenComparisonLessEq AlexPosn |
    TokenComparisonGreater AlexPosn |
    TokenComparisonGreaterEq AlexPosn |
    TokenComparisonEq AlexPosn |
    TokenComparisonNotEq AlexPosn |
    -- Bitwise Operators
    TokenBitwiseAnd AlexPosn |
    TokenBitwiseOr AlexPosn |
    TokenBitwiseNot AlexPosn |
    TokenBitwiseXor AlexPosn |
    -- Symbols
    TokenDollar AlexPosn |
    TokenRangeDot AlexPosn |
    TokenDot AlexPosn |
    TokenColon AlexPosn |
    TokenSemiColon AlexPosn |
    TokenComma AlexPosn |
    -- Parathesisation
    TokenBracketOpen AlexPosn |
    TokenBracketClose AlexPosn |
    TokenCurlyBracketOpen AlexPosn |
    TokenCurlyBracketClose AlexPosn |
    TokenSquareBracketOpen AlexPosn |
    TokenSquareBracketClose AlexPosn
        deriving (Eq,Show) 
}
