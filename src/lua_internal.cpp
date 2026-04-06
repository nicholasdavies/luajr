#include "shared.h"
#include <string>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

// Access to Lua C API

extern "C" SEXP luajr_lua_gettop(SEXP Lx)
{
    return Rf_ScalarInteger(lua_gettop(luajr_getstate(Lx)));
}
