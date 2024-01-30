#' Run Lua code in parallel
#'
#' Runs a Lua function multiple times, with function runs divided among
#' multiple threads.
#'
#' This function is experimental. Its interface and behaviour are likely to
#' change in subsequent versions of luajr.
#'
#' [lua_parallel()] works as follows. A number `threads` of new Lua states is
#' created with the standard Lua libraries and the `luajr` module opened in
#' each (i.e. as though the states were created using [lua_open()]). Then, a
#' thread is launched for each state. Within each thread, the code in `pre` is
#' run in the corresponding Lua state. Then, `func(i)` is called for each `i`
#' in `1:n`, with the calls spread across the states. Finally, the Lua states
#' are closed and the results are returned in a list.
#'
#' Instead of an integer, `threads` can be a list of Lua states, e.g. `NULL`
#' for the default Lua state or a state returned by [lua_open()]. This saves
#' the time needed to open the new states, which takes a few milliseconds.
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
#' There is overhead associated with creating new Lua states and with gathering
#' all the function results in an R list. It is advisable to check whether
#' running your Lua code in parallel actually gives a substantial speed
#' increase.
#'
#' @param func Lua expression evaluating to a function.
#' @param n Number of function executions.
#' @param threads Number of threads to create, or a list of existing Lua states
#'   (e.g. as created by [lua_open()]), all different, one for each thread.
#' @param pre Lua code block to run once for each thread at creation.
#' @return List of `n` values returned from the Lua function `func`.
#' @examples
#' lua_parallel("function(i) return i end", n = 4, threads = 2)
#' @export
lua_parallel = function(func, n, threads, pre = NA_character_) {
    if (is.double(threads)) threads = as.integer(threads);
    .Call(`_luajr_run_parallel`, func, as.integer(n), threads, pre)
}
