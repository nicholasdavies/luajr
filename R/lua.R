#' Run Lua code.
#'
#' Runs the specified Lua code.
#'
#' @param code Lua code block to run.
#' @param filename If non-\code{NULL}, name of file to run.
#' @param L \link[=lua_open]{Lua state} in which to run the code. \code{NULL}
#' (default) to use the default Lua state for \pkg{luajr}.
#' @return Lua value(s) returned by the code block converted to R object(s).
#' Only a subset of all Lua types can be converted to R objects at present.
#' If multiple values are returned, these are packaged in a \code{list}.
#' @examples
#' twelve = lua("return 3*4")
#' print(twelve)
#' @export
lua = function(code, filename = NULL, L = NULL)
{
    if (is.null(filename)) {
        ret = luajr_run(code, 0, L)
    } else {
        ret = luajr_run(filename, 1, L)
    }

    if (is.null(ret)) invisible() else ret
}
