// Exported workhorse functions for lua_run() and lua_func()
// Functions here are not part of the C API, because they are relatively
// inseparable from the R package and its functions.

#include "shared.h"
#include "registry_entry.h"
#include <string>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
}
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// For luajr_func_create and luajr_func_call's use of external pointers
static const int LUAJR_REGFUNC_CODE = 0x7CA12E6F;

// Destroy a registry entry pointed to by an R external pointer when it is no
// longer needed (i.e. at program exit or garbage collection of the R pointer).
static void finalize_registry_entry(SEXP xptr)
{
    delete reinterpret_cast<RegistryEntry*>(R_ExternalPtrAddr(xptr));
    R_ClearExternalPtr(xptr);
}

// Run the specified Lua code.
extern "C" SEXP luajr_run_code(SEXP code, SEXP Lx)
{
    CheckSEXPLen(code, STRSXP, 1);

    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Run code, counting number of returned values
    int top0 = lua_gettop(L);
    if (luaL_dostring(L, CHAR(STRING_ELT(code, 0))))
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rf_error("%s", err.c_str());
    }
    int top1 = lua_gettop(L);

    // Return results
    return luajr_return(L, top1 - top0);
}

// Run the specified Lua file.
extern "C" SEXP luajr_run_file(SEXP filename, SEXP Lx)
{
    CheckSEXPLen(filename, STRSXP, 1);

    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Run code, counting number of returned values
    int top0 = lua_gettop(L);
    if (luaL_dofile(L, CHAR(STRING_ELT(filename, 0))))
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rf_error("%s", err.c_str());
    }
    int top1 = lua_gettop(L);

    // Return results
    return luajr_return(L, top1 - top0);
}

// Create a Lua function
extern "C" SEXP luajr_func_create(SEXP code, SEXP Lx)
{
    CheckSEXPLen(code, STRSXP, 1);

    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Run code, counting number of returned values
    std::string cmd = "return ";
    cmd += CHAR(STRING_ELT(code, 0));
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
        Rf_error("lua_func expects `func' to evaluate to one value, not %d.", nret);
    if (lua_type(L, -1) != LUA_TFUNCTION)
        Rf_error("lua_func expects `func' to evaluate to a function, not a %s.", lua_typename(L, lua_type(L, -1)));

    // Create the registry entry with the value on the top of the stack
    RegistryEntry* re = new RegistryEntry(L);

    // Send back external pointer to the registry entry
    return luajr_makepointer(re, LUAJR_REGFUNC_CODE, finalize_registry_entry);
}

// Call a Lua function
extern "C" SEXP luajr_func_call(SEXP fx, SEXP alist, SEXP acode, SEXP Lx)
{
    // Get registry entry
    RegistryEntry* re = reinterpret_cast<RegistryEntry*>(luajr_getpointer(fx, LUAJR_REGFUNC_CODE));

    // Check args
    if (!re)
        Rf_error("luajr_func_call expects a valid registry entry.");
    CheckSEXP(alist, VECSXP);
    CheckSEXPLen(acode, STRSXP, 1);

    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Assemble function call
    int top0 = lua_gettop(L);
    re->Get();
    luajr_pass(L, alist, CHAR(STRING_ELT(acode, 0)));

    // Call function
    luajr_pcall(L, Rf_length(alist), LUA_MULTRET, "(user function from luajr_func_call())");
    int top1 = lua_gettop(L);

    // Return results
    return luajr_return(L, top1 - top0);
}
