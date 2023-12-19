# Package cache
cache_env = new.env(parent = emptyenv())
cache_env$luajr.lua = NULL

.onLoad <- function(libname, pkgname) {
    cache_env$luajr.lua = paste0(
        readLines(system.file("lua", "luajr.lua", package = "luajr", mustWork = TRUE)),
        collapse = "\n")
    cache_env$luajr.lua = gsub("@luajr_dylib_path@",
        getLoadedDLLs()[["luajr"]][["path"]],
        cache_env$luajr.lua)
    invisible()
}

.onUnload <- function(libname, pkgname) {
    # TODO close shared Lua state, see finalize_lua_state in R_api.cpp
    invisible()
}
