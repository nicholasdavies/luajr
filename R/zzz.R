.onLoad = function(libname, pkgname)
{
    # Provide path to package dylib for LuaJIT FFI
    .Call(`_luajr_locate_dylib`, getLoadedDLLs()[["luajr"]][["path"]])
    # Provide path to luajr module
    .Call(`_luajr_locate_module`, system.file("module", "luajr.lua", package = "luajr"))
    invisible()
}

.onUnload = function(libname, pkgname)
{
    # Close the shared Lua state
    lua_reset()
    invisible()
}
