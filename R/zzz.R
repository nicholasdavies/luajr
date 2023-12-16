.onLoad <- function(libname, pkgname) {
    # TODO set luajr_dynlib_path or equivalent
    invisible()
}

.onUnload <- function(libname, pkgname) {
    # TODO close shared Lua state, see finalize_lua_state in R_api.cpp
    invisible()
}
