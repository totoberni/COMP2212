# Programming Language Concepts coursework
This repo is a clone of a private repository available here: https://github.com/PowerfulBacon/PLC-Coursework <br>
The coursework was developed by **three students** and their merit marks were distributed as follows:

### Jake Mortlock - 40% 
### Alberto Berni - 30%
### Augustas Mirinas - 30%

# Tile Scripting Language

See issues for a list of the things that are TODO but not currently being worked on.
Assign yourself to an issue if you are working on it.

## Running

It is highly recommended that you download the haskell plugins for visual studio.
The ones I am using are:
- Haskell by Haskell
- Haskell Syntax Highlighting by Justus Adam
- Haskell-linter by Cody Hoover

You also need GHCI installed.

Navigate to the directory that Main.hs is stored in and run ghci.

```
PS C:\Users\#####\Uni\Year 2 Semester 1\Programming Language Concepts\Coursework> ghci
GHCi, version 9.4.4: https://www.haskell.org/ghc/  :? for help
ghci>
```

Run :l Main.hs

```
[1 of 5] Compiling PlLexer          ( PlLexer.hs, interpreted )
[2 of 5] Compiling PlParser         ( PlParser.hs, interpreted )
[3 of 5] Compiling PlInterpreter    ( PlInterpreter.hs, interpreted )
[4 of 5] Compiling Main             ( Main.hs, interpreted )
Ok, four modules loaded.
ghci>
```

## Commands

**evalCode fileName**: Evaluate the code inside of a file name.
Example:
```
ghci> evalCode "programs/problem1/pr1.tsl"

[TokenVar (AlexPn 0 1 1) "tile1",TokenEquals (AlexPn 6 1 7),TokenIn (AlexPn 8 1 9),TokenBracketOpen (AlexPn 10 1 11),TokenInt (AlexPn 11 1 12) 1,TokenBracketClose (AlexPn 12 1 13),TokenBreak (AlexPn 13 1 14),TokenVar (AlexPn 14 2 1) "tile2",TokenEquals (AlexPn 20 2 7),TokenIn (AlexPn 22 2 9),TokenBracketOpen (AlexPn 24 2 11),TokenInt (AlexPn 25 2 12) 2,TokenBracketClose (AlexPn 26 2 13),TokenBreak (AlexPn 27 2 14),TokenBracketOpen (AlexPn 48 5 1),TokenDollar (AlexPn 49 5 2),TokenBracketOpen (AlexPn 50 5 3),TokenCurlyBracketOpen (AlexPn 51 5 4),TokenVar (AlexPn 54 6 9) "tile1",TokenComma (AlexPn 59 6 14),TokenVar (AlexPn 61 6 16) "tile2",TokenSemiColon (AlexPn 66 6 21),TokenVar (AlexPn 69 7 9) "tile2",TokenComma (AlexPn 74 7 14),TokenVar (AlexPn 76 7 16) "tile1",TokenSemiColon (AlexPn 81 7 21),TokenBreak (AlexPn 82 7 22),TokenCurlyBracketClose (AlexPn 83 8 1),TokenBracketClose (AlexPn 84 8 2),TokenBracketClose (AlexPn 85 8 3),TokenSquareBracketOpen (AlexPn 86 8 4),TokenInt (AlexPn 87 8 5) 1,TokenRangeDot (AlexPn 88 8 6),TokenInt (AlexPn 90 8 8) 64,TokenComma (AlexPn 92 8 10),TokenInt (AlexPn 94 8 12) 1,TokenRangeDot (AlexPn 95 8 13),TokenInt (AlexPn 97 8 15) 64,TokenSquareBracketClose (AlexPn 99 8 17),TokenBreak (AlexPn 100 8 18)]
OpSequence (OpSequence (OpAssign (Identifier "tile1") (KeywordIn (OpArgumentLeaf (ValNum 1.0)))) (OpAssign (Identifier "tile2") (KeywordIn (OpArgumentLeaf (ValNum 2.0))))) (OpIndex (OpRepeat (TileBuilder (TBRow (TBLine (Identifier "tile1") (TBLineLast (Identifier "tile2"))) (TBRowLast (TBLine (Identifier "tile2") (TBLineLast (Identifier "tile1"))))))) (OpArgumentTree (OpRange (ValNum 1.0) (ValNum 64.0)) (OpArgumentLeaf (OpRange (ValNum 1.0) (ValNum 64.0)))))
ValError "Attempting to perform indexing over an expression that cannot be used as an index. [ValLineRange 1 64,ValLineRange 1 64]"
"RUNTIME EXCEPTION: Attempting to perform indexing over an expression that cannot be used as an index. [ValLineRange 1 64,ValLineRange 1 64]"
```

**evalRawCode code directory**: Evaluate code directly. The directory parameter is used to determine where to source the .tl files from when the in() expression is present.
```
ghci> evalRawCode "switch { x + 5 } : (x in [1..10])" ""

[TokenSwitch (AlexPn 0 1 1),TokenCurlyBracketOpen (AlexPn 7 1 8),TokenVar (AlexPn 9 1 10) "x",TokenAdd (AlexPn 11 1 12),TokenInt (AlexPn 13 1 14) 5,TokenCurlyBracketClose (AlexPn 15 1 16),TokenColon (AlexPn 17 1 18),TokenBracketOpen (AlexPn 19 1 20),TokenVar (AlexPn 20 1 21) "x",TokenIn (AlexPn 22 1 23),TokenSquareBracketOpen (AlexPn 25 1 26),TokenInt (AlexPn 26 1 27) 1,TokenRangeDot (AlexPn 27 1 28),TokenInt (AlexPn 29 1 30) 10,TokenSquareBracketClose (AlexPn 31 1 32),TokenBracketClose (AlexPn 32 1 33)]
OpSwitchAcross "x" (OpAdd (Identifier "x") (ValNum 5.0)) (OpRange (ValNum 1.0) (ValNum 10.0))
ValLine [ValNum 6.0,ValNum 7.0,ValNum 8.0,ValNum 9.0,ValNum 10.0,ValNum 11.0,ValNum 12.0,ValNum 13.0,ValNum 14.0,ValNum 15.0]
"[6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0]"
```

**standardChecks**: Execute the built in unit tests.
```
ghci> standardChecks

... (Only a snippet as an example)
Checking ./checks/range_expression.psl
File: ./checks/range_expression.psl: PASSED
File: ./checks/range_expression.psl: PASSED. Result: 'ValNum 0.0'
Checking ./checks/multi_dimensional_array_tests.psl
File: ./checks/multi_dimensional_array_tests.psl: PASSED
File: ./checks/multi_dimensional_array_tests.psl: --ASSERTION FAILED-- (Attempting to perform indexing over an expression that cannot be used as an index. [ValLineRange 1 5])
```

## Integrated Testing

The language supports integrated unit testing with the `~=` operator. Any files placed inside the `checks` directory will be treated as a unit test and executed when `standardChecks` is executed.

## Interpreter

- The interpreter should never crash or throw haskell errors. If there is an error, it should use the ValError type which gets printed to the console but will not crash execution. If the interpreter can crash inside of haskell, then standardChecks may be unable to completed.

The interpreter will print an output of its evaluation to `debug_output.txt`. You can use this to look at how the tree is being modified during execution. Most operations reduce the tree, however some line operations may cause it to grow slightly due to lazy execution.

## Compiling the parser and lexer

To compile the lexer run
`alex plLexer.x`

To compile the parser run
`happy plParser.y -info`
This will write debug info into the file named `nfo`.
