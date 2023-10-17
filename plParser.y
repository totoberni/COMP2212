
{ 
module PlParser where 
import PlLexer
}

%name parseCalc 
%tokentype { Token } 
%error { parseError }

%token 
    -- Handle line breaks (Requires for multi-line functions)
    "\n"              { TokenBreak _ }         -- COMPLETED
    -- Handle Base Value Types
    "int"             { TokenInt _ $$ }         -- COMPLETED
    "bool"            { TokenBool _ $$ }         -- COMPLETED
    "string"          { TokenString _ $$ }         -- COMPLETED
    -- Static assertion special token
    "#{}"             { TokenHaskell _ $$ }         -- COMPLETED
    -- Handle operators that contain other operators (Have to be performed first in order to match them properly)
    ".."              { TokenRangeDot _ }         -- COMPLETED
    "<="              { TokenComparisonLessEq _ }         -- COMPLETED
    ">="              { TokenComparisonGreaterEq _ }         -- COMPLETED
    "=="              { TokenComparisonEq _ }         -- COMPLETED
    "!="              { TokenComparisonNotEq _ }         -- COMPLETED
    "&&"              { TokenBooleanAnd _ }         -- COMPLETED
    "||"              { TokenBooleanOr _ }         -- COMPLETED
    "=>"              { TokenArrow _ }         -- COMPLETED (Switch)
    "~="              { TokenAssert _ }         -- COMPLETED
    -- Handle language keywords
    "in"              { TokenIn _ }         -- COMPLETED
    "switch"          { TokenSwitch _ }         -- COMPLETED
    "else"            { TokenElse _ }         -- COMPLETED
    "blank"           { TokenBlank _ }
    "case"            { TokenCase _ }         -- COMPLETED
    "proc"            { TokenProc _ }         -- COMPLETED
    -- Handle operators
    "="               { TokenEquals _ }         -- COMPLETED
    -- Handle mathematical operators
    "+"               { TokenAdd _ }         -- COMPLETED
    "-"               { TokenSubtract _ }         -- COMPLETED
    "*"               { TokenMultiply _ }         -- COMPLETED
    "/"               { TokenDivide _ }         -- COMPLETED
    -- Handle boolean operators
    "!"               { TokenBooleanNot _ }         -- COMPLETED
    -- Handle comparison operators
    "<"               { TokenComparisonLess _ }         -- COMPLETED
    ">"               { TokenComparisonGreater _ }         -- COMPLETED
    -- Handle bitwise operators
    "&"               { TokenBitwiseAnd _ }         -- COMPLETED
    "|"               { TokenBitwiseOr _ }         -- COMPLETED
    "~"               { TokenBitwiseNot _ }         -- COMPLETED
    "^"               { TokenBitwiseXor _ }         -- COMPLETED
    "%"               { TokenModulus _ }         -- COMPLETED
    -- Handle symbols
    "$"               { TokenDollar _ }         -- COMPLETED
    "."               { TokenDot _ }         -- COMPLETED
    ";"               { TokenSemiColon _ }         -- COMPLETED
    ":"               { TokenColon _ }         -- COMPLETED
    ","               { TokenComma _ }         -- COMPLETED (Arguments)
    -- Handle parenthesisation
    "("               { TokenBracketOpen _ }         -- COMPLETED
    ")"               { TokenBracketClose _ }         -- COMPLETED
    "{"               { TokenCurlyBracketOpen _ }         -- COMPLETED (Switch)
    "}"               { TokenCurlyBracketClose _ }         -- COMPLETED (Switch)
    "["               { TokenSquareBracketOpen _ }         -- COMPLETED
    "]"               { TokenSquareBracketClose _ }         -- COMPLETED
    -- Consider anything else a variable/function name
    "identifier"             { TokenVar _ $$ }         -- COMPLETED

%left "%" "*" "/" "+" "-" "&" "^" "|" "&&" "||" ">" "<" ">=" "<=" "==" "!=" ".." "~=" "\n" ";"
%right "="

%%

-- ===============================
-- Root Expressions
-- ===============================
-- This is the root of the parse tree.
-- We shouldn't be able to reach this point again
-- from a non-root node because otherwise we get
-- ambiguity.

Program :
    MultiLineExpression { $1 }
    | MultiLineExpression ";" { $1 }
    | MultiLineExpression LineBreaks { $1 }

MultiLineExpression :
    ExpressionOrCreateFunction { $1 }
    | LineBreaks ExpressionOrCreateFunction { $2 }
    -- Add in the ability to have multiple expressions
    | MultiLineExpression LineBreaks ExpressionOrCreateFunction  { OpSequence $1 $3 }
    | MultiLineExpression ";" ExpressionOrCreateFunction  { OpSequence $1 $3 }
    -- Allow them to just end in a ";"
    --| MultiLineExpression ";" { $1 }
    --| MultiLineExpression LineBreaks { $1 }

ExpressionOrCreateFunction :
    Expression { $1 }
    | CreateFunction { $1 }

Expression :
    UnaryExpression { $1 }
    | ValueExpression { $1 }
    | SwitchExpression { $1 }
    | MultiplicativeExpression { $1 }
    | AdditiveExpression { $1 }
    | BooleanComparisonExpression { $1 }
    | EqualityExpression { $1 }
    | LogicalAndExpression { $1 }
    | LogicalXorExpression { $1 }
    | LogicalOrExpression { $1 }
    | ComparativeAndExpression { $1 }
    | ComparativeOrExpression { $1 }
    | RangeExpression { $1 }
    | AssignmentExpression { $1 }
    | KeywordExpression { $1 }
    | AssertionExpression { $1 }
    | TileBuilderExpression { $1 }
    | IndexedExpression { $1 }
    | RepeatExpression { $1 }

-- ===============================
-- Assertion Expressions
-- ===============================
-- Assertion is a very special operator in the way that it works.
-- Anything to the right of the assertion until the end of the link will be read as a haskell
-- code for verification purposes

AssertionExpression :
    AssignmentOrLowerExpression "~=" "#{}" { HaskellAssertion $1 $3 }
    | AssignmentOrLowerExpression "~=" AssignmentOrLowerExpression { OpAssertion $1 $3 }

-- ===============================
-- Assignment Expressions
-- ===============================

AssignmentExpression :
    AssignmentOrLowerExpression "=" AssignmentOrLowerExpression { OpAssign $1 $3 }

AssignmentOrLowerExpression :
    AssignmentExpression { $1 }
    | RangeOrLowerExpression { $1 }

-- ===============================
-- Range Expressions
-- ===============================
-- Represents the x..y syntax.
-- This will be some expression..some expression
-- !x..y will be Not(x)..y
-- x..y() will be x..Func(y)
-- a+b..y will be Plus(a, b)..y
-- a&&b..7+a().b() should be (a && b) .. (7 + ((a().b)()))
-- a = 1..4 should be a = (1..4)

RangeExpression :
    RangeOrLowerExpression ".." RangeOrLowerExpression { OpRange $1 $3 }

RangeOrLowerExpression :
    RangeExpression { $1 }
    | ComparativeOrOrLowerExpression { $1 }

-- ===============================
-- Comparative Or Expressions
-- ===============================

ComparativeOrExpression :
    ComparativeOrOrLowerExpression "||" ComparativeOrOrLowerExpression { OpComparativeOr $1 $3 }

ComparativeOrOrLowerExpression :
    ComparativeOrExpression { $1 }
    | ComparativeAndOrLowerExpression { $1 }


-- ===============================
-- Comparative And Expressions
-- ===============================
-- a && b && c should be (a && b) && c (The order doesnt really matter)

ComparativeAndExpression :
    ComparativeAndOrLowerExpression "&&" ComparativeAndOrLowerExpression { OpComparativeAnd $1 $3 }

ComparativeAndOrLowerExpression :
    ComparativeAndExpression { $1 }
    | EqualityOrLowerExpression { $1 }

-- ===============================
-- Equality Expressions
-- ===============================
-- 5 == 8 == true should be (5 == 8) == true

EqualityExpression :
    EqualityOrLowerExpression "==" EqualityOrLowerExpression { OpCompEqual $1 $3 }
    | EqualityOrLowerExpression "!=" EqualityOrLowerExpression { OpCompNotEqual $1 $3 }

EqualityOrLowerExpression :
    EqualityExpression { $1 }
    | BooleanComparisonOrLowerExpression { $1 }

-- ===============================
-- Boolean Comparison Expressions
-- ===============================

BooleanComparisonExpression :
    BooleanComparisonOrLowerExpression "<" BooleanComparisonOrLowerExpression { OpCompLess $1 $3 }
    | BooleanComparisonOrLowerExpression ">" BooleanComparisonOrLowerExpression { OpCompGreater $1 $3 }
    | BooleanComparisonOrLowerExpression "<=" BooleanComparisonOrLowerExpression { OpCompLessEqual $1 $3 }
    | BooleanComparisonOrLowerExpression ">=" BooleanComparisonOrLowerExpression { OpCompGreaterEqual $1 $3 }

BooleanComparisonOrLowerExpression :
    BooleanComparisonExpression { $1 }
    | LogicalOrOrLowerExpression { $1 }

-- ===============================
-- Logical Or Expressions
-- ===============================

LogicalOrExpression :
    LogicalOrOrLowerExpression "|" LogicalOrOrLowerExpression { OpLogicalOr $1 $3 }

LogicalOrOrLowerExpression :
    LogicalOrExpression { $1 }
    | LogicalXorOrLowerExpression { $1 }

-- ===============================
-- Logical Xor Expressions
-- ===============================

LogicalXorExpression :
    LogicalXorOrLowerExpression "^" LogicalXorOrLowerExpression { OpLogicalXor $1 $3 }

LogicalXorOrLowerExpression :
    LogicalXorExpression { $1 }
    | LogicalAndOrLowerExpression { $1 }

-- ===============================
-- Logical And Expressions
-- ===============================

LogicalAndExpression :
    LogicalAndOrLowerExpression "&" LogicalAndOrLowerExpression { OpLogicalAnd $1 $3 }

LogicalAndOrLowerExpression :
    LogicalAndExpression { $1 }
    | AddOrLowerExpression { $1 }

-- ===============================
-- Additive Expressions
-- ===============================
-- 4 + 3 * 2 should be 4+(3*2)

AdditiveExpression :
    AddOrLowerExpression "+" AddOrLowerExpression { OpAdd $1 $3 }
    | AddOrLowerExpression "-" AddOrLowerExpression { OpSubtract $1 $3 }

AddOrLowerExpression :
    AdditiveExpression { $1 }
    | MultOrLowerExpression { $1 }

-- ===============================
-- Multiplicative Expressions
-- ===============================
-- !4 * 6 should be (!4) * 6
-- !3 * 6 * 7 should be ((!3) * 6) * 7
-- !a.b * c.d should be (!(a.b)) * (c.d)
-- This means that * is higher in the tree than everything below

MultiplicativeExpression :
    MultOrLowerExpression "*" MultOrLowerExpression { OpMultiply $1 $3 }
    | MultOrLowerExpression "/" MultOrLowerExpression { OpDivide $1 $3 }
    | MultOrLowerExpression "%" MultOrLowerExpression { OpModulus $1 $3 }

MultOrLowerExpression :
    MultiplicativeExpression { $1 }
    | KeywordExpressionOrLower { $1 }

-- ===============================
-- Language Keywords
-- ===============================
-- $a.b = $(a.b)
-- $a() = $(a())
-- $a * b = ($a) * b
-- $(a * b) = $(a * b)

KeywordExpression :
    "in" "(" FunctionArguments ")" { KeywordIn $3 }

KeywordExpressionOrLower :
    KeywordExpression { $1 }
    | TileBuilderExpression { $1 }
    | SwitchExpressionOrLower { $1 }

-- ===============================
-- Tile Builder Expression
-- ===============================
-- The most cursed part of this language, the dreaded tile builder
-- What makes the tile builder so cursed is the multitude of ways that
-- the tile builder can take form on.
-- The switch tile builder is handled by the switch loops

TileBuilderExpression :
    "{" OptionalLineBreak TileBuilderRow OptionalLineBreak "}"                  { TileBuilder $3 }

TileBuilderRow :
    TileBuilderLine ";" OptionalLineBreak TileBuilderRow      { TBRow $1 $4 }
    | TileBuilderLine ";"                   { TBRowLast $1 }

TileBuilderLine :
    Expression "," TileBuilderLine           { TBLine $1 $3 }
    | Expression                            { TBLineLast $1 }

-- ===============================
-- Switch Expressions
-- ===============================
-- Switch {}
-- This should never have ambiguity since it cannot be anything else
-- due to the strict syntax

SwitchExpression :
    "switch" OptionalLineBreak "{" SwitchArguments OptionalLineBreak "}" { OpSwitch $4 }
    | "switch" OptionalLineBreak "{" SwitchArguments OptionalLineBreak "}" ":" "(" "identifier" "in" Expression ")" { OpSwitchAcross $9 $4 $11 }
    | "switch" OptionalLineBreak "{" OptionalLineBreak Expression OptionalLineBreak "}" ":" "(" "identifier" "in" Expression ")" { OpSwitchAcross $10 $5 $12 }
    | "{" OptionalLineBreak Expression OptionalLineBreak "}" ":" "(" "identifier" "in" Expression ")" { TileBuilderAcross $8 $3 $10 }

SwitchArguments :
    OptionalLineBreak "case" RangeOrLowerExpression "=>" Expression SwitchArguments { OpSwitchCase $3 $5 $6 }
    | OptionalLineBreak "else" "=>" Expression { OpSwitchElse $4 }

SwitchExpressionOrLower :
    SwitchExpression { $1 }
    | UnaryOrLowerExpression { $1 }

-- ===============================
-- Unary Expressions
-- ===============================
-- These will appear higher in the tree than
-- primary expressions

UnaryExpression :
    "!" UnaryOrLowerExpression {OpComparativeNot $2}
    | "~" UnaryOrLowerExpression {OpLogicalNot $2}

UnaryOrLowerExpression :
    IndexOrLowerExpression { $1 }
    | UnaryExpression { $1 }

-- ===============================
-- Indexed Expressions
-- ===============================

-- An expression that has been accessed at a specific index
IndexedExpression :
    IndexOrLowerExpression "[" FunctionArguments "]" { OpIndex $1 $3 }
    -- Add in special handling for exp[1..5]
    -- | ValueExpression RangeExpression { OpIndex $1 $2 }

IndexOrLowerExpression :
    IndexedExpression { $1 }
    | RepeatOrLowerExpression { $1 }

-- ===============================
-- Repeat Operator
-- ===============================
-- Lower in the tree than indexing, so that indexing will
-- always be above it and it can be used in the form
-- $([1..5])[100]

RepeatExpression :
    "$" "(" Expression ")" { OpRepeat $3 }

RepeatOrLowerExpression :
    RepeatExpression { $1 }
    | ValueExpression { $1 }

-- ===============================
-- Primary Expressions
-- ===============================

-- An expression that contains any value
-- An expression that may contain variables
-- An identifier that is a variable holder
-- An object returned from a function that is a variable holder
-- The result of an indexer that may be an object containing variables
-- An object from a bracketted expression
ValueExpression :
    -- a.b
    TerminalExpression { $1 }
    -- a.b.c
    | ValueExpression "." IdentifierExpression { OpMemberAccess $1 $3 }
    | InvokedExpression { $1 }
    -- Anything with lower precedence can be wrapped in brackets
    -- Since this is at the very bottom, this allows us to bracket anywhere by
    -- just definining it here
    -- It just works:tm:
    | "(" Expression ")" { $2 }
    -- Allow for array style expressions just working
    | "[" Expression "]" { $2 }
    -- For contained multi-line expressions enter a new scope
    -- so that defined variables go out of scope afterwards
    | "(" ")" "=>" "{" MultiLineExpression OptionalLineBreak "}" { OpScopeEntry $5 }

-- An expression that may be called like a function
-- An object stored in a variable may have functions
-- Functions cannot return callable functions
-- Indexer cannot return functions
-- Anything wrapped in brackets cannot be a callable function
FunctionExpression :
    IdentifierExpression { $1 }
    | ValueExpression "." IdentifierExpression { OpMemberAccess $1 $3 }

-- An expression that is a raw terminating value
TerminalExpression :
    IdentifierExpression { $1 }
    | "int" { ValNum (fromIntegral $1) }
    | "bool" { ValBool $1 }
    | "string" { ValString $1 }    -- Why do we have this, identifier is the same as string? -- Because string is wrapped in "" but identifier isnt

-- An identifier for a function/variable name
IdentifierExpression :
    "identifier" { Identifier $1 }

-- Invoke an expression that looks like a function
InvokedExpression :
    -- An expression that ends with () should be an invokation
    FunctionExpression "(" ")" { OpInvokation $1 }
    -- Expression with arguments
    | FunctionExpression "(" FunctionArguments ")" { OpInvokationArgs $1 $3 }

-- Allow creation of a function
CreateFunction :
    "proc" IdentifierExpression "(" FunctionArgumentIdentifiers ")" OptionalLineBreak "{" MultiLineExpression OptionalLineBreak "}" { OpAssign $2 (OpCreateFunction $4 $8) }

-- ===============================
-- = NON-OPERATOR STRUCTURE ZONE =
-- ===============================

-- Represents the arguments to a function
FunctionArguments :
    Expression                           { OpArgumentLeaf $1 }
    | Expression "," FunctionArguments   { OpArgumentTree $1 $3 }

OptionalLineBreak :
    LineBreaks                          { [] }
    | {- empty -}                       { [] }

LineBreaks :
    "\n" LineBreaks                     { [] }
    | "\n"                              { [] }

FunctionArgumentIdentifiers :
    IdentifierExpression                           { OpArgIdLeaf $1 }
    | IdentifierExpression "," FunctionArgumentIdentifiers   { OpArgIdTree $1 $3 }

-- =========================================
-- = MATHEMATICAL OPERATOR PRECEDENCE ZONE =
-- =========================================

{ 
parseError :: [Token] -> a
parseError [] = error "Unknown parse error"
parseError (x:xs) = error (show x)

data Exp =
    -- A.b
    -- Must contain an Identifier node as the second slot.
    -- Will evaluate the left node and then access the variable
    -- in the left expressions environment.
    OpMemberAccess Exp Exp
    -- An argument tree.
    -- The left node is the expression, the right node is either an
    -- argument tree with more expressions, or an argument leaf with
    -- the final expression.
    | OpArgumentTree Exp Exp
    -- The final expression in an argument tree.
    | OpArgumentLeaf Exp
    | OpArgIdTree Exp Exp
    | OpArgIdLeaf Exp
    -- Evaluate the contained expression and invoke the function returned
    -- by that expression.
    | OpInvokation Exp
    -- Evalute the contained left expression and invoke the function returned
    -- by that expression with the arguments provided in the second
    -- expression.
    | OpInvokationArgs Exp Exp
    -- Access the index of a given left node expression. Left node should be of
    -- type Line<T> or RepeatingLine<T>
    -- The right node represents the index that we want to access.
    -- This can either be an integer to access a specific value (Returns T),
    -- a line to access multiple values (Returns Line<T>), or a repeating line
    -- to access multiple values repeatedly (Returns RepeatingLine<T>).
    | OpIndex Exp Exp
    -- A switch expression which can be used to branch the code conditionally.
    -- Can only contain either an OpSwitchCase or an OpSwitchElse.
    -- Will execute the first OpSwitchElse where the predeciate matches,
    -- or will execute the OpSwitchElse if no predicates match.
    | OpSwitch Exp
    -- Performs a switch expression across every element in some provided list.
    -- Stores the string which represents the name of the variable that each
    -- value in the list will be bound to.
    | OpSwitchAcross String Exp Exp
    | OpSwitchCase Exp Exp Exp
    | OpSwitchElse Exp
    | OpMultiply Exp Exp
    | OpDivide Exp Exp
    | OpAdd Exp Exp
    | OpSubtract Exp Exp
    | OpModulus Exp Exp
    | OpCompLess Exp Exp
    | OpCompLessEqual Exp Exp
    | OpCompGreater Exp Exp
    | OpCompGreaterEqual Exp Exp
    | OpCompEqual Exp Exp
    | OpCompNotEqual Exp Exp
    | OpLogicalAnd Exp Exp
    | OpLogicalXor Exp Exp
    | OpLogicalOr Exp Exp
    | OpLogicalNot Exp
    | OpComparativeAnd Exp Exp
    | OpComparativeOr Exp Exp
    | OpComparativeNot Exp
    | OpRange Exp Exp
    | OpAssign Exp Exp
    | OpRepeat Exp
    | OpScopeEntry Exp
    | OpSequence Exp Exp
    | OpAssertion Exp Exp
    | HaskellAssertion Exp String
    | KeywordIn Exp
    | Identifier String
    | TileBuilder TileBuilderRow
    | TileBuilderAcross String Exp Exp
    | OpCreateFunction Exp Exp
    | OpPrint Exp
    -- ==================
    -- =  Value Types   =
    -- ==================
    | ValNum Float
    | ValBool Bool          -- Todo: Remove bool, internally we just use integer evauation. This is enforced by the type checker.
    | ValString String
    | ValInfinity
    -- An evaluation error occurred
    | ValError String
    -- A list of arguments to be passed to a function
    | ArgumentList [Exp]
    | TileBuilderGrid [[Exp]]
    -- Called when an internal assertion fails
    | InternalAssertionFailed String Exp Exp
    | InternalAssertionSuccess Exp
    -- ==================
    -- =   Line Types   =
    -- ==================
    -- Represents a line
    | ValLine [Exp]
    -- Represents an repeating line
    | ValRepeatingLine [Exp]
    -- Represents a function applied across every element in a line
    | ValLineSelect Exp Exp
    -- Line generator
    | ValLineRange Int Int
    | ValLineRangeRepeating Int Int
    -- Built tiles
    -- Tile widths, Tile heights, Tile Sources
    | ValBuiltTiles [Int] [Int] [[Exp]]
    -- ==================
    -- = Function Types =
    -- ==================
    -- Takes in a string of the arguments it binds and the expression to run
    -- on those bound arguments
    | ValFunction [String] Exp Environment
    -- ==================
    -- = Type Types =
    -- ==================
    | ValType Type
    | ValNull
    deriving (Show, Read, Eq) 

data Type =
    Numeric
    | Void
    | Bool
    | String
    | Line Type
    | RepeatingLine Type
    | Function [Type] Type
    | InvalidType String
    | AnyType
    deriving (Show, Read, Eq) 

-- Our environments are a little more complicated than
-- just simple variable bindings as they can contain
-- bindings themselves.
type Environment = [(String, EnvironmentVariable)]

data EnvironmentVariable = 
    VarExpression Exp
    deriving (Show, Read, Eq) 

data ArrayLength = 
    Finite Int
    | Infinite
    deriving (Show, Read, Eq) 

-- REMEMBER: Rows are horizontal and not vertical!
data TileBuilderRow =
    TBRow TileBuilderLine TileBuilderRow
    | TBRowLast TileBuilderLine
    deriving (Show, Read, Eq) 

data TileBuilderLine =
    TBLine Exp TileBuilderLine
    | TBLineLast Exp
    deriving (Show, Read, Eq) 

}
