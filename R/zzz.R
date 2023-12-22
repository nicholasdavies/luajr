.onLoad = function(libname, pkgname)
{
    # Provide package dylib path to luajr for LuaJIT FFI
    luajr_locate_dylib(getLoadedDLLs()[["luajr"]][["path"]])
    invisible()
}

.onUnload = function(libname, pkgname)
{
    # Close the shared Lua state
    lua_reset()
    invisible()
}
