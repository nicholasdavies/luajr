// Exported workhorse functions for lua() and lua_func()
// Functions here are not part of the C API, because they are relatively
// inseparable from the R package and its functions.

#include "shared.h"
#include "registry_entry.h"
#include <string>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

// Run the specified Lua code.
extern "C" SEXP luajr_runcode(SEXP code, SEXP Lx)
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
extern "C" SEXP luajr_runfile(SEXP filename, SEXP Lx)
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
extern "C" SEXP luajr_fcreate(SEXP func, SEXP Lx)
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
            luajr_popstop(L, nret, "lua_func expects `func' to evaluate to one value, not %d.", nret);
        if (lua_type(L, -1) != LUA_TFUNCTION)
            luajr_popstop(L, 1, "lua_func expects `func' to evaluate to a function, not a %s.", lua_typename(L, lua_type(L, -1)));

        // Create the registry entry with the value on the top of the stack
        RegistryEntry* re = new RegistryEntry(L);

        // Send back external pointer to the registry entry
        return luajr_makepointer(re, LUAJR_REGFUNC_CODE, RegistryEntry::Finalize);
    }

    Rf_error("lua_func expects func to be an external pointer to a Lua function, or a character string.");
}

// Call a Lua function
extern "C" SEXP luajr_fcall(SEXP fx, SEXP alist, SEXP acode, SEXP Lx)
{
    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Assemble function call
    int top0 = lua_gettop(L);
    luajr_pushfunc(fx);
    luajr_pass(L, alist, acode);

    // Call function
    luajr_pcall(L, Rf_length(alist), LUA_MULTRET, "user function from luajr_fcall()", LUAJR_TOOLING_ALL);
    int top1 = lua_gettop(L);

    // Return results
    return luajr_return(L, top1 - top0);
}

// Specialized call functions for 0-8 arguments, avoiding list() construction.
// Validation and recycling of argcode is done in R (lua_func).
#define FUNC_CALL_BEGIN \
    const unsigned char* ac = RAW(acode); (void)ac; \
    lua_State* L = luajr_getstate(Lx); \
    int top0 = lua_gettop(L); \
    luajr_pushfunc(fx);

// N = number of user args
#define FUNC_CALL_END(N) \
    luajr_pcall(L, N, LUA_MULTRET, "user function from luajr_fcall()", LUAJR_TOOLING_ALL); \
    int top1 = lua_gettop(L); \
    return luajr_return(L, top1 - top0);

extern "C" SEXP luajr_fcall0(SEXP fx, SEXP acode, SEXP Lx)
{
    FUNC_CALL_BEGIN
    FUNC_CALL_END(0)
}

extern "C" SEXP luajr_fcall1(SEXP fx, SEXP a1, SEXP acode, SEXP Lx)
{
    FUNC_CALL_BEGIN
    luajr_pushsexp(L, a1, ac[0]);
    FUNC_CALL_END(1)
}

extern "C" SEXP luajr_fcall2(SEXP fx, SEXP a1, SEXP a2, SEXP acode, SEXP Lx)
{
    FUNC_CALL_BEGIN
    luajr_pushsexp(L, a1, ac[0]);
    luajr_pushsexp(L, a2, ac[1]);
    FUNC_CALL_END(2)
}

extern "C" SEXP luajr_fcall3(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP acode, SEXP Lx)
{
    FUNC_CALL_BEGIN
    luajr_pushsexp(L, a1, ac[0]);
    luajr_pushsexp(L, a2, ac[1]);
    luajr_pushsexp(L, a3, ac[2]);
    FUNC_CALL_END(3)
}

extern "C" SEXP luajr_fcall4(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP acode, SEXP Lx)
{
    FUNC_CALL_BEGIN
    luajr_pushsexp(L, a1, ac[0]);
    luajr_pushsexp(L, a2, ac[1]);
    luajr_pushsexp(L, a3, ac[2]);
    luajr_pushsexp(L, a4, ac[3]);
    FUNC_CALL_END(4)
}

extern "C" SEXP luajr_fcall5(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP acode, SEXP Lx)
{
    FUNC_CALL_BEGIN
    luajr_pushsexp(L, a1, ac[0]);
    luajr_pushsexp(L, a2, ac[1]);
    luajr_pushsexp(L, a3, ac[2]);
    luajr_pushsexp(L, a4, ac[3]);
    luajr_pushsexp(L, a5, ac[4]);
    FUNC_CALL_END(5)
}

extern "C" SEXP luajr_fcall6(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP acode, SEXP Lx)
{
    FUNC_CALL_BEGIN
    luajr_pushsexp(L, a1, ac[0]);
    luajr_pushsexp(L, a2, ac[1]);
    luajr_pushsexp(L, a3, ac[2]);
    luajr_pushsexp(L, a4, ac[3]);
    luajr_pushsexp(L, a5, ac[4]);
    luajr_pushsexp(L, a6, ac[5]);
    FUNC_CALL_END(6)
}

extern "C" SEXP luajr_fcall7(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP a7, SEXP acode, SEXP Lx)
{
    FUNC_CALL_BEGIN
    luajr_pushsexp(L, a1, ac[0]);
    luajr_pushsexp(L, a2, ac[1]);
    luajr_pushsexp(L, a3, ac[2]);
    luajr_pushsexp(L, a4, ac[3]);
    luajr_pushsexp(L, a5, ac[4]);
    luajr_pushsexp(L, a6, ac[5]);
    luajr_pushsexp(L, a7, ac[6]);
    FUNC_CALL_END(7)
}

extern "C" SEXP luajr_fcall8(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP a7, SEXP a8, SEXP acode, SEXP Lx)
{
    FUNC_CALL_BEGIN
    luajr_pushsexp(L, a1, ac[0]);
    luajr_pushsexp(L, a2, ac[1]);
    luajr_pushsexp(L, a3, ac[2]);
    luajr_pushsexp(L, a4, ac[3]);
    luajr_pushsexp(L, a5, ac[4]);
    luajr_pushsexp(L, a6, ac[5]);
    luajr_pushsexp(L, a7, ac[6]);
    luajr_pushsexp(L, a8, ac[7]);
    FUNC_CALL_END(8)
}

// Get the number of parameters, vararg status, and argument names of a Lua function
extern "C" SEXP luajr_finfo(SEXP fx)
{
    RegistryEntry* re = reinterpret_cast<RegistryEntry*>(luajr_getpointer(fx, LUAJR_REGFUNC_CODE));
    if (!re)
        Rf_error("luajr_finfo expects a valid registry entry.");

    lua_State* L = re->GetState();

    // Call luajr.get_func_info(f) via registry
    lua_pushlightuserdata(L, (void*)&luajr_get_func_info);
    lua_rawget(L, LUA_REGISTRYINDEX);
    re->Get();  // push function as argument
    luajr_pcall(L, 1, LUA_MULTRET, "luajr.get_func_info()", LUAJR_TOOLING_NONE);

    return luajr_return(L, 3);
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
