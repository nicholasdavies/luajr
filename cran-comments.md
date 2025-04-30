This submission addresses issues raised by CRAN checks on the compiled code.
Previously, the bundled LuaJIT library had some calls to exit() and some calls
to standard C I/O on stdin, stdout, or stderr. In this submission I have 
redirected all of these calls. Calls to exit() now redirect to Rf_error() and 
calls to standard I/O now redirect to R_ReadConsole() and R_WriteConsoleEx() 
as appropriate.

## R CMD check results

0 errors \| 0 warnings \| 1 note

-   NOTE: GNU make is a SystemRequirements.

    This NOTE is carried over from previous submissions of luajr to CRAN.

    Justification: This package wraps the LuaJIT compiler, which requires GNU 
    make to build. The build system for LuaJIT is very complex, so it would be 
    prohibitively difficult to get around this requirement.
