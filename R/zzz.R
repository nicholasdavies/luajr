.onLoad = function(libname, pkgname)
{
    .Call(`_luajr_register`,
        # R version as size-3 integer vector
        getRversion()[[1, 1:3]],
        # Path to package dylib for LuaJIT FFI
        getLoadedDLLs()[["luajr"]][["path"]],
        # Path to R shared library (only used on Windows).
        if (.Platform$OS.type == "windows") file.path(R.home("bin"), "R.dll") else "",
        # Path to luajr module
        system.file("Lua", "luajr.lua", package = "luajr"),
        # Path to R module
        system.file("Lua", "R.lua", package = "luajr"),
        # Path to debugger.lua
        system.file("Lua", "debugger.lua", package = "luajr")
    )
    invisible()
}

.onUnload = function(libname, pkgname)
{
    # Close the shared Lua state
    lua_reset()
    invisible()
}
