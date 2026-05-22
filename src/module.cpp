// module.cpp: Functions for loading, reading from, and writing to Lua modules

#include "shared.h"
#include "registry_entry.h"
#include <string>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

extern "C" SEXP luajr_loadmodule(SEXP filename, SEXP Lx)
{
    CheckSEXPLen(filename, STRSXP, 1);

    // Get Lua state
    lua_State* L = luajr_getstate(Lx);

    // Run code, counting number of returned values
    int top0 = lua_gettop(L);
    luajr_dofile(L, CHAR(STRING_ELT(filename, 0)), LUAJR_TOOLING_ALL);
    int nret = lua_gettop(L) - top0;

    // Check return value
    if (nret != 1)
        luajr_popstop(L, nret, "lua_module expects the module to return one value, not %d.", nret);
    if (lua_type(L, -1) != LUA_TTABLE)
        luajr_popstop(L, 1, "lua_func expects the module to return a table, not a %s.", lua_typename(L, lua_type(L, -1)));

    // Create the registry entry with the value on the top of the stack
    RegistryEntry* re = new RegistryEntry(L);

    // Send back external pointer to the registry entry
    return luajr_makepointer(re, LUAJR_MODULE_CODE, RegistryEntry::Finalize);
}

static int lua_gettable_wrap(lua_State* L)
{
    lua_gettable(L, -2);
    return 1;
}

static int lua_settable_wrap(lua_State* L)
{
    lua_settable(L, -3);
    return 1;
}

extern "C" SEXP luajr_moduleget(SEXP module, SEXP keys, SEXP typecheck)
{
    CheckSEXP(keys, VECSXP);
    size_t klen = Rf_length(keys);

    // Get registry entry
    RegistryEntry* re = reinterpret_cast<RegistryEntry*>(luajr_getpointer(module, LUAJR_MODULE_CODE));

    // Check args
    if (!re)
        Rf_error("luajr_moduleget expects a valid registry entry.");

    // Get module table on stack
    re->Get();

    // No index: return entire module as table.
    lua_State* L = re->GetState();
    if (klen == 0)
        return luajr_return(L, 1);

    // Iterate through keys
    for (size_t k = 0; k < klen; ++k)
    {
        // Put safe getter below table
        lua_pushcfunction(L, lua_gettable_wrap);
        lua_insert(L, -2);

        // Get key on stack
        luajr_pushsexp(L, VECTOR_ELT(keys, k), AC::value | AC::native);

        // Now have on stack: getter, table, keys[k]
        // Get table[keys[k]], catching any error
        if (lua_pcall(L, 2, 1, 0) != LUA_OK)
            luajr_popstop(L, 1, "Could not get index %zu: %s.", k + 1, lua_tostring(L, -1));
    }

    // Check type, if requested
    if (typecheck != R_NilValue) {
        if (strcmp(lua_typename(L, lua_type(L, -1)), CHAR(STRING_ELT(typecheck, 0)))) {
            if (lua_type(L, -1) == LUA_TNIL) {
                luajr_popstop(L, 1, "Error: value in module is nil or undefined.");
            } else {
                luajr_popstop(L, 1, "Type error: expecting value to be %s, not %s",
                    CHAR(STRING_ELT(typecheck, 0)), lua_typename(L, lua_type(L, -1)));
            }
        }
    }

    return luajr_return(L, 1);
}

extern "C" SEXP luajr_moduleset(SEXP module, SEXP keys, SEXP as, SEXP value)
{
    CheckSEXP(keys, VECSXP);
    size_t klen = Rf_length(keys);
    if (klen < 1)
        Rf_error("Must provide at least one index to set value.");
    CheckSEXPLen(as, RAWSXP, 1);

    // Get registry entry
    RegistryEntry* re = reinterpret_cast<RegistryEntry*>(luajr_getpointer(module, LUAJR_MODULE_CODE));

    // Check args
    if (!re)
        Rf_error("luajr_moduleset expects a valid registry entry.");

    // First, ensure we are not trying to overwrite a top-level module function.
    // Put module table and first key on stack to check type.
    lua_State* L = re->GetState();
    re->Get();
    luajr_pushsexp(L, VECTOR_ELT(keys, 0), AC::value | AC::native);
    lua_gettable(L, -2);
    if (lua_type(L, -1) == LUA_TFUNCTION)
        luajr_popstop(L, 2, "Cannot overwrite a top-level module function.");
    lua_pop(L, 1); // Pop module table

    // Module table remains on stack.
    // Iterate through keys (not including final key)
    for (size_t k = 0; k < klen - 1; ++k)
    {
        // Put safe getter below table
        lua_pushcfunction(L, lua_gettable_wrap);
        lua_insert(L, -2);

        // Get key on stack
        luajr_pushsexp(L, VECTOR_ELT(keys, k), AC::value | AC::native);

        // Now have on stack: getter, table, keys[k]
        // Get table[keys[k]], catching any error
        if (lua_pcall(L, 2, 1, 0) != LUA_OK)
            luajr_popstop(L, 1, "Could not get index %zu: %s.", k + 1, lua_tostring(L, -1));
    }

    // Put safe setter below table
    lua_pushcfunction(L, lua_settable_wrap);
    lua_insert(L, -2);

    // Get final key on stack, then value
    luajr_pushsexp(L, VECTOR_ELT(keys, klen - 1), AC::value | AC::native);
    luajr_pushsexp(L, value, RAW(as)[0]);

    // Now have on stack: setter, table, final key, value
    // Set table[final key] = value, catching any error
    if (lua_pcall(L, 3, 1, 0) != LUA_OK)
        luajr_popstop(L, 1, "Could not set index: %s.", lua_tostring(L, -1));

    return R_NilValue;
}
