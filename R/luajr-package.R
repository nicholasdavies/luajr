## usethis namespace: start
#' @useDynLib luajr, .registration = TRUE
## usethis namespace: end
NULL

# To instruct inline/Rcpp packages how to depend on luajr
inlineCxxPlugin = function(...)
{
    Rcpp::Rcpp.plugin.maker(
        include.after = "#include <luajr_api.h>\n#include <luajr_funcdef.h>",
        package = "luajr")(...)
}

#' luajr: LuaJIT Scripting
#'
#' 'luajr' provides an interface to [LuaJIT](https://luajit.org), a
#' just-in-time compiler for the [Lua scripting language](https://www.lua.org).
#' It allows users to run Lua code from R.
#'
#' @section The R API:
#' * [lua()]: run Lua code
#' * [lua_func()]: make a Lua function callable from R
#' * [lua_shell()]: run an interactive Lua shell
#' * [lua_open()]: create a new Lua state
#' * [lua_reset()]: reset the default Lua state
#' * [lua_parallel()]: run Lua code in parallel
#'
#' @section Further reading:
#' For an introduction to 'luajr', see `vignette("luajr")`
"_PACKAGE"
