## usethis namespace: start
#' @useDynLib luajr, .registration = TRUE
## usethis namespace: end
NULL

# To instruct inline/Rcpp packages how to depend on luajr
inlineCxxPlugin = function(...)
{
    Rcpp::Rcpp.plugin.maker(
        include.after = "#include <luajr.h>\n#include <luajr_funcdef.h>",
        package = "luajr")(...)
}

#' luajr: LuaJIT Scripting
#'
#' @section The R API:
#'
#' You can use these functions to run Lua code from R:
#'
#' * [lua()]: run Lua code from a string or file
#' * [lua_func()]: make a Lua function callable from R
#' * [lua_shell()]: run an interactive Lua shell
#' * [lua_module()], [lua_import()]: load Lua modules
#' * [lua_open()]: create a new Lua state
#' * [lua_reset()]: reset the default Lua state
#' * [lua_mode()], [lua_profile()]: debugger, profiler, and JIT options
#'
#' @section The Lua API:
#'
#' In your Lua code, you can use the \code{luajr} module and the \code{R}
#' module to interact with R functions, values, and types.
#'
#' The \code{luajr} module offers higher-level access to R functions and types,
#' similar to the convenience API offered by \pkg{Rcpp} or \pkg{cpp11} for use
#' in C++. See `vignette("luajr-module")` for more details.
#'
#' The \code{R} module offers lower-level access to R functions and types,
#' similar to R's built-in C API. See `vignette("R-module")` for more details.
#'
#' @section Further reading:
#'
#' For an introduction to \pkg{luajr}, see `vignette("luajr")`.
#'
#' For a guide to writing Lua modules for use from your R package or project,
#' see `vignette("modules")`.
#'
#' @keywords internal
"_PACKAGE"
