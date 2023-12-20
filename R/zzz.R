# Package cache
cache_env = new.env(parent = emptyenv())
cache_env$luajr.lua = NULL

.onLoad = function(libname, pkgname)
{
    # Load "luajr" Lua module source code into cache_env$luajr.lua
    cache_env$luajr.lua = paste0(
        readLines(system.file("lua", "luajr.lua", package = "luajr", mustWork = TRUE)),
        collapse = "\n")
    # Replace "@luajr_dylib_path@" with the path to the luajr package dylib
    cache_env$luajr.lua = gsub("@luajr_dylib_path@",
        getLoadedDLLs()[["luajr"]][["path"]],
        cache_env$luajr.lua)
    invisible()
}

.onUnload = function(libname, pkgname)
{
    # Close the shared Lua state
    luajr_reset()
    invisible()
}
