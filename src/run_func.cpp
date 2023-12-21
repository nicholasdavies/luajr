// Exported workhorse functions for lua_run() and lua_func()

#include "shared.h"
#include "registry_entry.h"
#include <Rcpp.h>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

// Run the specified Lua code or file.
// If mode == 0, run code. If mode == 1, run file.
// Behaviour is undefined for any other mode.
// [[Rcpp::export]]
SEXP luajr_run(const char* code, int mode, SEXP Lxp)
{
    // Get Lua state
    lua_State* L = luajr_getstate(Lxp);

    // Run code, counting number of returned values
    int top0 = lua_gettop(L);
    int r;
    if (mode == 0)
        r = luaL_dostring(L, code);
    else
        r = luaL_dofile(L, code);
    if (r)
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rcpp::stop(err);
    }
    int top1 = lua_gettop(L);

    // Return results
    return Lua_return_to_R(L, top1 - top0);
}

// [[Rcpp::export]]
SEXP luajr_func_create(const char* code, SEXP Lxp)
{
    // Get Lua state
    lua_State* L = luajr_getstate(Lxp);

    // Run code, counting number of returned values
    std::string cmd = "return ";
    cmd += code;
    int top0 = lua_gettop(L);
    if (luaL_dostring(L, cmd.c_str()))
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rcpp::stop(err);
    }
    int top1 = lua_gettop(L);
    int nret = top1 - top0;

    // Handle mistakes
    if (nret != 1)
        Rcpp::stop("lua_func expects `code' to evaluate to one value, not %d.", nret);
    if (lua_type(L, -1) != LUA_TFUNCTION)
        Rcpp::stop("lua_func expects `code' to evaluate to a function, not a %s.", lua_typename(L, lua_type(L, -1)));

    // Send back a registry entry
    RegistryEntry* re = new RegistryEntry(L);
    re->Register();
    return Rcpp::XPtr<RegistryEntry>(re, true);
}

// [[Rcpp::export]]
SEXP luajr_func_call(Rcpp::XPtr<RegistryEntry> fptr, Rcpp::List alist, const char* acode, SEXP Lxp)
{
    // Get Lua state
    lua_State* L = luajr_getstate(Lxp);

    // Assemble function call
    int top0 = lua_gettop(L);
    fptr->Get();
    R_pass_to_Lua(L, alist, acode);

    // Call function
    if (lua_pcall(L, alist.size(), LUA_MULTRET, 0))
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rcpp::stop(err.c_str());
    }
    int top1 = lua_gettop(L);

    // Return results
    return Lua_return_to_R(L, top1 - top0);
}
