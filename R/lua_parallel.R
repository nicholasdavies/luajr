#' Run Lua code in parallel
#'
#' Description here
#'
#' @export
lua_parallel = function(func, n, threads, pre) {
    .Call(`_luajr_run_parallel`, func, n, threads, pre)
}
