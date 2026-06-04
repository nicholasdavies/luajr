# luajr 0.3.1

-   Bug fixes: potential memory bugs unearthed by Address Sanitizer and UB 
    Sanitizer; correct loading R API entry points in R.lua on Fedora.

# luajr 0.3.0

-   Overhauled the args code system in lua_func() for richer capabilities. This 
    breaks compatibility with previous versions of luajr.
    
-   Added new vignettes on benchmarks and the R.lua module and reorganised
    vignettes.
    
-   Overhauled representation of atomic vectors and lists within luajr. There 
    is no longer a separate type for vectors passed by reference (but passing 
    by reference is still supported).
    
-   Removed `lua_parallel()`, replacing it with a new parallel processing 
    system that runs entirely within Lua.

-   Added native support for R functions, environments, and generic SEXP 
    variables in Lua.

-   Added a new 'R' module which can be used in Lua code to access R's API.

-   luajr is now officially compatible (and tested) with R versions 4.0.0 and 
    up.
    
-   Improved efficiency of calls into Lua functions from R.

-   Fixed some bugs in running long Lua strings and when passing / returning 
    certain LuaJIT cdata types.

# luajr 0.2.2

-   Updated LuaJIT to incorporate a key bugfix that would otherwise lead to
    severe performance regressions on ARM64 (including recent Mac computers).

# luajr 0.2.1

-   luajr's profiler has been overhauled to capture more complete profiling 
    data in a data.frame. As a result, the format of the object returned by 
    lua_profile() has changed.

-   luajr now supports long vectors (i.e. vectors with 2^31 elements or more).
    You should pass these into Lua using the `'r'` arg code for efficiency. 
    Further details may be found in `vignette("objects")`. This addresses issue 
    [#5](https://github.com/nicholasdavies/luajr/issues/5). Thanks to 
    @waynelapierre for asking about long vectors!

# luajr 0.2.0

-   Added support for Lua modules using `lua_module()` and `lua_import()`. This 
    simplifies the process of adding Lua code to your R package, which is now
    explained in a new vignette. This addresses issue 
    [#4](https://github.com/nicholasdavies/luajr/issues/4). Thanks to 
    @al-obrien for asking about this!
    
-   Added a speed comparison for luajr / Lua versus Rcpp / C++.

-   `lua_func()` can now accept an external pointer to a Lua function. 

# luajr 0.1.9

-   Added debugging and profiling for Lua code. The debugger is Scott Lembcke's
    debugger.lua, and the profiler is LuaJIT's built-in sampling profiler. Also
    added the option of turning off JIT compilation. This is all accessed 
    through a new function, `lua_mode()`.

-   Added further code to ensure that LuaJIT never calls `exit()` directly and
    never tries to read from or write to standard input or output streams, 
    instead redirecting this to the R console.

# luajr 0.1.8

-   The Lua "io" library is now capable of getting input from the R console
    (e.g. with `io.read()`) -- previously, trying this would cause R to hang
    (at least from RStudio).
    
-   The Lua `os.exit()` function now ends Lua execution without crashing 
    RStudio.

-   `lua_shell()` now stores commands in the R console history.

-   The luajr build process now skips making libluajit.so and the luajit 
    executable, as these are not needed for luajr.
    
-   Corrected an oversight in the documentation for `lua_shell()`; this fixes
    issue [#3](https://github.com/nicholasdavies/luajr/issues/3). Thanks to
    @SugarRayLua for bringing my attention to this!

-   Addressed some further issues turned up by CRAN checks.

# luajr 0.1.7

-   Added support for passing the R type "raw" to Lua, as a string potentially
    with embedded nulls, and for returning strings with embedded nulls from 
    Lua, which become "raw"s in R.
    
-   Replaced calls to `Rf_allocVector3` with calls to `Rf_allocVector`, as the 
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

-   Added `luajr.NULL`, to allow working with NULL in Lua.
-   Fixed some problems for CRAN.

# luajr 0.1.3

-   Added a vignette describing the `luajr` Lua module.
-   Added `lua_parallel()` for basic multithreading.
-   Fixed compilation warnings about enums on some platforms.

# luajr 0.1.2

-   luajr is now on [CRAN](https://CRAN.R-project.org/package=luajr)!
