.onLoad = function(libname, pkgname)
{
    # Provide path to package dylib for LuaJIT FFI
    .Call(`_luajr_locate_dylib`, getLoadedDLLs()[["luajr"]][["path"]])
    # Provide path to luajr module
    .Call(`_luajr_locate_module`, system.file("Lua", "luajr.lua", package = "luajr"))
    # Provide path to debugger.lua
    .Call(`_luajr_locate_debugger`, system.file("Lua", "debugger.lua", package = "luajr"))
    invisible()
}

.onUnload = function(libname, pkgname)
{
    # Close the shared Lua state
    lua_reset()
    invisible()
}
