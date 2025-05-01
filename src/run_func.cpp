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

// Run the specified Lua code.
extern "C" SEXP luajr_run_code(SEXP code, SEXP Lx)
{
    CheckSEXPLen(code, STRSXP, 1);

    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Run code, counting number of returned values
    int top0 = lua_gettop(L);
    luajr_dostring(L, CHAR(STRING_ELT(code, 0)), LUAJR_TOOLING_ALL);
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
    luajr_dofile(L, CHAR(STRING_ELT(filename, 0)), LUAJR_TOOLING_ALL);
    int top1 = lua_gettop(L);

    // Return results
    return luajr_return(L, top1 - top0);
}

// Create a Lua function
extern "C" SEXP luajr_func_create(SEXP func, SEXP Lx)
{
    if (TYPEOF(func) == EXTPTRSXP)
    {
        // Get registry entry
        RegistryEntry* re = reinterpret_cast<RegistryEntry*>(luajr_getpointer(func, LUAJR_REGFUNC_CODE));

        // Check this was a valid registry entry to func
        if (re)
        {
            // Make sure func has same state as Lx
            if (!re->CheckState(luajr_getstate(Lx)))
                Rf_error("lua_func expects func to have been created in Lua state L.");
            return func;
        }
    }
    else if (TYPEOF(func) == STRSXP && Rf_length(func) == 1)
    {
        // Get Lua state
        lua_State* L = luajr_getstate(Lx);

        // Run code, counting number of returned values
        std::string cmd = "return ";
        cmd += CHAR(STRING_ELT(func, 0));
        int top0 = lua_gettop(L);
        luajr_dostring(L, cmd.c_str(), LUAJR_TOOLING_ALL);
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
        return luajr_makepointer(re, LUAJR_REGFUNC_CODE, RegistryEntry::Finalize);
    }

    Rf_error("lua_func expects func to be an external pointer to a Lua function, or a character string.");
}

// Call a Lua function
extern "C" SEXP luajr_func_call(SEXP fx, SEXP alist, SEXP acode, SEXP Lx)
{
    CheckSEXP(alist, VECSXP);
    CheckSEXPLen(acode, STRSXP, 1);

    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Assemble function call
    int top0 = lua_gettop(L);
    luajr_pushfunc(fx);
    luajr_pass(L, alist, CHAR(STRING_ELT(acode, 0)));

    // Call function
    luajr_pcall(L, Rf_length(alist), LUA_MULTRET, "user function from luajr_func_call()", LUAJR_TOOLING_ALL);
    int top1 = lua_gettop(L);

    // Return results
    return luajr_return(L, top1 - top0);
}

// Get a luajr function on the stack of the lua_State associated with the luajr function
extern "C" void luajr_pushfunc(SEXP fx)
{
    // Get registry entry
    RegistryEntry* re = reinterpret_cast<RegistryEntry*>(luajr_getpointer(fx, LUAJR_REGFUNC_CODE));

    // Check args
    if (!re)
        Rf_error("luajr_pushfunc expects a valid registry entry.");

    // Get function on stack
    re->Get();
}
