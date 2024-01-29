#' Create a new Lua state
#'
#' Creates a new, empty Lua state and returns an external pointer wrapping that
#' state.
#'
#' All Lua code is executed within a given Lua state. A Lua state is similar to
#' the global environment in R, in that it is where all variables and functions
#' are defined. \pkg{luajr} automatically maintains a "default" Lua state, so
#' most users of \pkg{luajr} will not need to use [lua_open()].
#'
#' However, if for whatever reason you want to maintain multiple different Lua
#' states at a time, each with their own independent global variables and
#' functions, [lua_open()] can be used to create a new Lua state which can then
#' be passed to [lua()], [lua_func()] and [lua_shell()] via the `L` parameter.
#' These functions will then operate within that Lua state instead of the
#' default one. The default Lua state can be specified explicitly with
#' `L = NULL`.
#'
#' Note that there is currently no way (provided by \pkg{luajr}) of saving a
#' Lua state to disk so that the state can be restarted later. Also, there is
#' no `lua_close` in \pkg{luajr} because Lua states are closed automatically
#' when they are garbage collected in R.
#'
#' @return External pointer wrapping the newly created Lua state.
#' @examples
#' L1 <- lua_open()
#' lua("a = 2")
#' lua("a = 4", L = L1)
#' lua("print(a)") # 2
#' lua("print(a)", L = L1) # 4
#' @export
lua_open = function() {
    .Call(`_luajr_open`)
}

#' Reset the default Lua state
#'
#' Clears out all variables from the default Lua state, freeing up the
#' associated memory.
#'
#' This resets the default [Lua state][lua_open] only. To reset a non-default
#' Lua state `L` returned by [lua_open()], just do `L <- lua_open()` again. The
#' memory previously used will be cleaned up at the next garbage collection.
#'
#' @return None.
#' @examples
#' lua("a = 2")
#' lua_reset()
#' lua("print(a)") # nil
#' @export
lua_reset = function() {
    invisible(.Call(`_luajr_reset`))
}
