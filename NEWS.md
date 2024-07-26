# luajr (development version)

# luajr 0.1.8

-   The Lua "io" library is now capable of getting input from the R console
    (e.g. with io.read()) -- previously, trying this would cause R to hang
    (at least from RStudio).
    
-   The Lua os.exit() function now ends Lua execution without crashing RStudio.

-   lua_shell() now stores commands in the R console history.

-   The luajr build process now skips making libluajit.so and the luajit 
    executable, as these are not needed for luajr.
    
-   Corrected an oversight in the documentation for lua_shell(); this fixes
    issue [#3](https://github.com/nicholasdavies/luajr/issues/3). Thanks to
    @SugarRayLua for bringing my attention to this!

-   Addressed some further issues turned up by CRAN checks.

# luajr 0.1.7

-   Added support for passing the R type "raw" to Lua, as a string potentially
    with embedded nulls, and for returning strings with embedded nulls from 
    Lua, which become "raw"s in R.
    
-   Replaced calls to Rf_allocVector3 with calls to Rf_allocVector, as the 
    former is apparently not part of the API allowed in CRAN packages, as 
    requested by CRAN.

-   @TimTaylor improved the R version of the "logistic map" example and 
    benchmark in the main luajr vignette, so that now the R version is only 
    10x slower than the Lua version, not 2,500x slower. This fixes issue 
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
