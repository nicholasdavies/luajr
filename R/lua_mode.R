#' Debugger, profiler, and JIT options
#'
#' Run Lua code with the debugger or profiler activated, and control whether
#' the LuaJIT just-in-time compiler is on.
#'
#' # Details
#'
#' This function is experimental. Its interface and behaviour may change in
#' subsequent versions of luajr.
#'
#' [lua_mode()] works in one of three ways, depending on which parameters are
#' provided.
#'
#' When called with no arguments, [lua_mode()] returns the current `debug`,
#' `profile`, and `jit` settings.
#'
#' When called without an `expr` argument, but with at least one of `debug`,
#' `profile`, or `jit`, the specified settings apply for any subsequent
#' executions of Lua code until the next call to [lua_mode()].
#'
#' When called with an `expr` argument, the specified settings for `debug`,
#' `profile`, and `jit` are applied temporarily just for the evaluation of
#' `expr` in the calling frame.
#'
#' Note that if you provide some but not all of the `debug`, `profile`, and
#' `jit` arguments, the "missing" settings are retained at their current
#' values, not reset to some default or "off" state. In other words, you can
#' temporarily change one setting without affecting the others.
#'
#' # The debugger
#'
#' The `debug` setting allows you to run Lua code in debug mode, using Scott
#' Lembcke's [`debugger.lua`](https://github.com/slembcke/debugger.lua).
#'
#' Use `debug = "step"` (or `TRUE` or "on") to step through each line of the
#' code; use `debug = "error"` to trigger the debugger on any Lua error; and
#' turn off the debugger with `debug = "off"` (or `FALSE`).
#'
#' To trigger the debugger from a specific place within your Lua code, you can
#' also call `luajr.dbg()` from your Lua code. Within Lua, you can also use
#' `luajr.dbg(CONDITION)` to trigger debugging only if `CONDITION` evaluates to
#' `false` or `nil`. (In this way, `luajr.dbg(CONDITION)` is sort of like an
#' `assert(CONDITION)` call that triggers the debugger when the assert fails.)
#'
#' `debugger.lua` is more fully documented at its
#' [github repo page](https://github.com/slembcke/debugger.lua), but briefly,
#' you enter commands of one character at the `debugger.lua>` prompt. Use
#' `n` to step to the next line, `q` to quit, and `h` to show a help page with
#' all the rest of the commands.
#'
#' # The profiler
#'
#' The `profile` setting allows you to profile your Lua code run, generating
#' information useful for optimising its execution speed.
#'
#' Use `profile = "on"` (or `TRUE`) to turn on the profiler with default
#' settings (namely, profile at the line level and sample at 1-millisecond
#' intervals).
#'
#' Instead of `"on"`, you can pass a string containing any of these options:
#'
#' * `f`: enable profiling to the function level.
#' * `l`: enable profiling to the line level.
#' * `i<integer>`: set the sampling interval, in milliseconds (default: 1ms).
#'
#' For example, the default options correspond to the string `"li1"`.
#'
#' You must use [lua_profile()] to recover the generated profiling data.
#'
#' # JIT options
#'
#' The `jit` setting allows you to turn LuaJIT's just-in-time compiler off
#' (with `jit = "off"` or `FALSE`). The default is for the JIT compiler to be
#' `"on"` (alias `TRUE`).
#'
#' Lua code will generally run more slowly with the JIT off, although there
#' have been issues reported with LuaJIT running more slowly with the JIT on
#' for processors using ARM64 architecture, which includes Apple Silicon CPUs.
#'
#' @param expr An expression to run with the associated settings. If `expr` is
#' present, the settings apply only while `expr` is being evaluated. If `expr`
#' is missing, the settings apply until they are changed by another call to
#' [lua_mode()].
#' @param debug Control the debugger: `"step"` / `"on"` / `TRUE` to step
#' through each line; `"error"` to trigger the debugger on a Lua error;
#' `"off"` / `FALSE` to switch the debugger off.
#' @param profile Control the profiler: `"on"` / `TRUE` to use the profiler's
#' default settings; a specially formatted string (see below) to control the
#' profiler's precision and sampling interval; `"off"` / `FALSE` to switch the
#' profiler off.
#' @param jit Control LuaJIT's just-in-time compiler: `"on"` / `TRUE` to use
#' the JIT, `"off"` / `FALSE` to use the LuaJIT interpreter only.
#'
#' @return When called with no arguments, returns the current settings. When
#' called with `expr`, calls the value returned by `expr`. Otherwise, returns
#' nothing.
#'
#' @seealso [lua_profile()] for extracting the generated profiling data.
#'
#' @examples
#' \dontrun{
#' # Debugger in "one-shot" mode
#' lua_mode(debug = "on",
#'     sum <- lua("
#'         local s = 0
#'         for i = 1,10 do
#'             s = s + i
#'         end
#'         return s
#'     ")
#' )
#'
#' # Profiler in "switch on / switch off" mode
#' lua_mode(profile = TRUE)
#' pointless_computation = lua_func(
#' "function()
#'     local s = startval
#'     for i = 1,10^8 do
#'         s = math.sin(s)
#'         s = math.exp(s^2)
#'         s = s + 1
#'     end
#'     return s
#' end")
#' lua("startval = 100")
#' pointless_computation()
#' lua_mode(profile = FALSE)
#' lua_profile()
#'
#' # Turn off JIT and turn it on again
#' lua_mode(jit = "off")
#' lua_mode(jit = "on")
#' }
#' @export
lua_mode = function(expr, debug, profile, jit)
{
    ms = function(x) if (missing(x)) "" else x

    if (missing(expr) && missing(debug) && missing(profile) && missing(jit)) {
        return (.Call(`_luajr_get_mode`))
    } else if (missing(expr)) {
        .Call(`_luajr_set_mode`, ms(debug), ms(profile), ms(jit))
        return (invisible())
    } else {
        saved = .Call(`_luajr_get_mode`)
        .Call(`_luajr_set_mode`, ms(debug), ms(profile), ms(jit))
        ret = tryCatch(eval(expr, -2),
            finally = .Call(`_luajr_set_mode`, saved[["debug"]], saved[["profile"]], saved[["jit"]]))
        if (is.null(ret)) return (invisible())
        return (ret)
    }
}

#' Get profiling data
#'
#' After running Lua code with the profiler active (using [lua_mode()]), use
#' this function to get the profiling data that has been collected.
#'
#' This function is experimental. Its interface and behaviour may change in
#' subsequent versions of luajr.
#'
#' @param flush If `TRUE`, clears the internal profile data buffer (default);
#' if `FALSE`, doesn't. (Set to `FALSE` if you want to 'peek' at the profiling
#' data collected so far, but you want to collect more data to add to this
#' later.)
#'
#' @return An object of class `"luajr_profile"`.
#'
#' @seealso [lua_mode()] for generating the profiling data.
#'
#' @examples
#' \dontrun{
#' lua_mode(profile = TRUE)
#' pointless_computation = lua_func(
#' "function()
#'     local s = startval
#'     for i = 1,10^8 do
#'         s = math.sin(s)
#'         s = math.exp(s^2)
#'         s = s + 1
#'     end
#'     return s
#' end")
#' lua("startval = 100")
#' pointless_computation()
#' lua_mode(profile = FALSE)
#'
#' prof = lua_profile()
#' }
#' @export
lua_profile = function(flush = TRUE)
{
    pd = .Call(`_luajr_profile_data`, flush)
    if (is.list(pd)) {
        if (length(pd) == 0) {
            return (structure(integer(0), class = "luajr_profile"))
        }
        return (structure(unlist(lapply(pd, function(x) {
            samples = x[[3]] # integer vector
            if (length(samples)) {
                names(samples) = paste(x[[1]], x[[2]], sep = "/") # lua_State / trace
            }
            return (samples)
        })), class = "luajr_profile"))
    }
    return (invisible())
}
