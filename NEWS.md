# luajr (development version)

-   Removed a compiler flag, `-Wformat`, that was causing errors with some 
    standard R environments, most notably the `rocker/r-base` Docker 
    environment. This fixes issue 
    [#1](https://github.com/nicholasdavies/luajr/issues/1). Thanks @jonocarroll 
    for reporting and helping to fix `luajr`'s first official bug! :-)

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
