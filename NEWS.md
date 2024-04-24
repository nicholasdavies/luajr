# luajr (development version)

-   Replaced calls to Rf_allocVector3 with calls to Rf_allocVector, as the 
    former is apparently not part of the API allowed in CRAN packages, as 
    requested by CRAN.

-   Added support for passing the R type "raw" to Lua, as a string potentially
    with embedded nulls, and for returning strings with embedded nulls from 
    Lua, which become "raw"s in R.
    
-   @TimTaylor improved the R version of the "logistic map" example and 
    benchmark in the main luajr vignette, so that now the Lua version is only 
    10x faster than the R version, not 2,500x faster. This fixes issue 
    [#2](https://github.com/nicholasdavies/luajr/issues/2). Thanks Tim!

-   Removed a compiler flag, `-Wformat`, that was causing errors with some 
    standard R environments, most notably the `rocker/r-base` Docker 
    environment. This fixes issue 
    [#1](https://github.com/nicholasdavies/luajr/issues/1). Thanks @jonocarroll 
    for reporting and helping to fix luajr's first official bug! :-)

# luajr 0.1.6

-   This version makes further changes to DESCRIPTION and LICENSE requested
    by CRAN.

# luajr 0.1.5

-   This version updates the package DESCRIPTION and CITATION to better reflect
    Mike Pall's role as author of the embedded LuaJIT compiler.

# luajr 0.1.4

-   Added luajr.NULL, to allow working with NULL in Lua.
-   Fixed some problems for CRAN.

# luajr 0.1.3

-   Added a vignette describing the `luajr` Lua module.
-   Added `lua_parallel()` for basic multithreading.
-   Fixed compilation warnings about enums on some platforms.

# luajr 0.1.2

-   luajr is now on [CRAN](https://CRAN.R-project.org/package=luajr)!
