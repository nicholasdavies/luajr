.onLoad = function(libname, pkgname)
{
    # Provide package dylib path to luajr for LuaJIT FFI
    luajr_locate_dylib(getLoadedDLLs()[["luajr"]][["path"]])
    # Provide path to luajrmodule
    luajr_locate_module(system.file("module", "luajr.lua", package = "luajr"))
    invisible()
}

.onUnload = function(libname, pkgname)
{
    # Close the shared Lua state
    lua_reset()
    invisible()
}
