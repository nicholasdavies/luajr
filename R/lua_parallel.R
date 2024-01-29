#' Run Lua code in parallel
#'
#' Runs a Lua function multiple times, with function runs divided among
#' multiple threads.
#'
#' This function is experimental. Its interface and behaviour are likely to
#' change in subsequent versions of luajr.
#'
#' First, `threads` new states are created with the standard Lua libraries
#' opened in each. Then, a thread is launched for each state. Within each
#' thread, the code in `pre` is run in the corresponding Lua state.
#' Then, `func(i)` is called for each `i` in `1:n`, with the calls spread
#' across the states. Finally, the Lua states are closed and the results are
#' returned in a list.
#'
#' Note that `func` has to be thread-safe. All pure Lua code and built-in Lua
#' library functions are thread-safe, except for certain functions in the
#' built-in **os** and **io** libraries (search for "thread safe" in the
#' [Lua 5.2 reference manual](https://www.lua.org/manual/5.2/manual.html)).
#' Additionally, use of luajr reference types is **not** thread-safe because
#' these use R to allocate and manage memory, and R is not thread-safe.
#'
#' This means that you cannot safely use `luajr.logical_r`, `luajr.integer_r`,
#' `luajr.numeric_r`, `luajr.character_r`, or other reference types within
#' `func`. `luajr.list` and `luajr.dataframe` are fine, provided the list
#' entries / dataframe columns are value types.
#'
#' @param func Lua expression evaluating to a function.
#' @param n Number of function executions.
#' @param threads Number of threads.
#' @param pre Lua code block to run once for each thread at creation.
#' @return List of `n` values returned from the Lua function `func`.
#' @examples
#' lua_parallel("function(i) return i end", n = 4, threads = 2)
#' @export
lua_parallel = function(func, n, threads, pre = NA_character_) {
    .Call(`_luajr_run_parallel`, func, as.integer(n), as.integer(threads), pre)
}
