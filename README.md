# lua-sudoku
**A Lua module for solving Sudoku and Killer puzzles**

Method: create a file that is piped to Knuth's own implementation of his Dancing Links algorithm and postprocess the output.  

`sudoku.lua` is licensed under the MIT license.

`dance.c` is as far as I can see in the public domain. It is a trivial
modification of Knuth's program [https://www-cs-faculty.stanford.edu/~knuth/programs/dance.w], obtained by making the maximum label length settable in a `@d` statement, defining it to by 7 rather than 3, and compiling the CWeb code using `ctangle` from a standard TeX distribution.
