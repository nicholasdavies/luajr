## usethis namespace: start
#' @importFrom Rcpp sourceCpp
#' @useDynLib luajr, .registration = TRUE
## usethis namespace: end
NULL

# To instruct inline/Rcpp packages how to depend on luajr
inlineCxxPlugin = function(...)
{
    Rcpp::Rcpp.plugin.maker(
        include.after = "#include <luajr_api.h>\n#include <luajr_funcdef.hpp>",
        package = "luajr")(...)
}

#' luajr: Use LuaJIT Scripting with R
#'
#' 'luajr' provides an interface to Mike Pall's LuaJIT (<https://luajit.org>),
#' a just-in-time compiler for the Lua scripting language
#' (<https://www.lua.org>). It allows users to run Lua code from R.
#'
#' @section The R API:
#' * [lua()]
#' * [lua_func()]
#' * [lua_shell()]
#' * [lua_open()]
#'
#' @section Other information:
#' * [using luajr from C++]
#' * [using luajr from Lua]
#'
#' For Introduction, see \code{vignette("intro", package = "luajr")}
#'
#' @docType package
#' @name luajr
NULL
