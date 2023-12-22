// Exported workhorse functions for lua_run() and lua_func()

#include "shared.h"
#include "registry_entry.h"
#include <R.h>
#include <Rinternals.h>
#include <string>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

const int LUAJR_REGFUNC_CODE = 0x7CA12E6F;

// Destroy a registry entry pointed to by an R external pointer when it is no
// longer needed (i.e. at program exit or garbage collection of the R pointer).
void finalize_registry_entry(SEXP xptr)
{
    delete reinterpret_cast<RegistryEntry*>(R_ExternalPtrAddr(xptr));
    R_ClearExternalPtr(xptr);
}

// Run the specified Lua code or file.
// If mode == 0, run code. If mode == 1, run file.
// Behaviour is undefined for any other mode.
// [[Rcpp::export]]
SEXP luajr_run(const char* code, int mode, SEXP Lx)
{
    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

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
        Rf_error("%s", err.c_str());
    }
    int top1 = lua_gettop(L);

    // Return results
    return Lua_return_to_R(L, top1 - top0);
}

// [[Rcpp::export]]
SEXP luajr_func_create(const char* code, SEXP Lx)
{
    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Run code, counting number of returned values
    std::string cmd = "return ";
    cmd += code;
    int top0 = lua_gettop(L);
    if (luaL_dostring(L, cmd.c_str()))
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rf_error("%s", err.c_str());
    }
    int top1 = lua_gettop(L);
    int nret = top1 - top0;

    // Handle mistakes
    if (nret != 1)
        Rf_error("lua_func expects `code' to evaluate to one value, not %d.", nret);
    if (lua_type(L, -1) != LUA_TFUNCTION)
        Rf_error("lua_func expects `code' to evaluate to a function, not a %s.", lua_typename(L, lua_type(L, -1)));

    // Create the registry entry
    RegistryEntry* re = new RegistryEntry(L);
    re->Register();

    // Send back external pointer to the registry entry
    return MakePointer(re, LUAJR_REGFUNC_CODE, finalize_registry_entry);
}

// [[Rcpp::export]]
SEXP luajr_func_call(SEXP fx, SEXP alist, const char* acode, SEXP Lx)
{
    // Get registry entry
    RegistryEntry* re = reinterpret_cast<RegistryEntry*>(GetPointer(fx, LUAJR_REGFUNC_CODE));

    // Check args
    if (!re)
        Rf_error("luajr_func_call expects a valid registry entry.");
    if (TYPEOF(alist) != VECSXP)
        Rf_error("luajr_func_call expects alist to be a list.");

    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Assemble function call
    int top0 = lua_gettop(L);
    re->Get();
    R_pass_to_Lua(L, alist, acode);

    // Call function
    if (lua_pcall(L, Rf_length(alist), LUA_MULTRET, 0))
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rf_error(err.c_str());
    }
    int top1 = lua_gettop(L);

    // Return results
    return Lua_return_to_R(L, top1 - top0);
}
