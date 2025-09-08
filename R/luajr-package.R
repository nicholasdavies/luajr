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
#' * [lua()]: run Lua code
#' * [lua_func()]: make a Lua function callable from R
#' * [lua_shell()]: run an interactive Lua shell
#' * [lua_module()], [lua_import()]: load Lua modules
#' * [lua_open()]: create a new Lua state
#' * [lua_reset()]: reset the default Lua state
#' * [lua_parallel()]: run Lua code in parallel
#' * [lua_mode()], [lua_profile()]: debugger, profiler, and JIT options
#'
#' @section Further reading:
#' For an introduction to 'luajr', see `vignette("luajr")`
#'
#' @keywords internal
"_PACKAGE"
