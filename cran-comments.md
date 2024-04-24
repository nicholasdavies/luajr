This submission is to comply with a request from CRAN to remove uses of 
`Rf_allocVector3` from the package code and use `Rf_allocVector` instead.
The deadline given was 2024-05-06.

## R CMD check results

0 errors \| 0 warnings \| 1 note

-   NOTE: GNU make is a SystemRequirements.

    This NOTE is carried over from previous submissions of luajr to CRAN.

    Justification: This package wraps the LuaJIT compiler, which requires GNU 
    make to build. The build system for LuaJIT is very complex, so it would be 
    prohibitively difficult to get around this requirement.
