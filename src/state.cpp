#include "shared.h"
#include "registry_entry.h"
#include <string>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// luajr Lua module API registry keys (registered by address)
int luajr_construct_ref = 0;
int luajr_construct_vec = 0;
int luajr_construct_list = 0;
int luajr_construct_null = 0;
int luajr_return_info = 0;
int luajr_return_copy = 0;

// luajr module functions to register
struct RegistryFunc { void* key; const char* name; };
static const RegistryFunc luajr_registry_funcs[] =
{
    { (void*)&luajr_construct_ref,  "construct_ref" },
    { (void*)&luajr_construct_vec,  "construct_vec" },
    { (void*)&luajr_construct_list, "construct_list" },
    { (void*)&luajr_construct_null, "construct_null" },
    { (void*)&luajr_return_info,    "return_info" },
    { (void*)&luajr_return_copy,    "return_copy" },
    { 0, 0 }
};

// Path to luajr dylib
static std::string luajr_dylib_path;

// Path to luajr module source
static std::string luajr_module_path;

// Bytecode for luajr module
static std::string luajr_module_bytecode;

// Path to debugger.lua
static std::string luajr_debugger_path;

// Provide path to luajr dylib
extern "C" SEXP luajr_locate_dylib(SEXP path)
{
    CheckSEXPLen(path, STRSXP, 1);
    luajr_dylib_path = CHAR(STRING_ELT(path, 0));
    return R_NilValue;
}

// Provide path to luajr module source
extern "C" SEXP luajr_locate_module(SEXP path)
{
    CheckSEXPLen(path, STRSXP, 1);
    luajr_module_path = CHAR(STRING_ELT(path, 0));
    return R_NilValue;
}

// Provide path to luajr module source
extern "C" SEXP luajr_locate_debugger(SEXP path)
{
    CheckSEXPLen(path, STRSXP, 1);
    luajr_debugger_path = CHAR(STRING_ELT(path, 0));
    return R_NilValue;
}

// Destroy a Lua state pointed to by an R external pointer when it is no longer
// needed (i.e. at program exit or garbage collection of the R pointer).
static void finalize_lua_state(SEXP xptr)
{
    lua_State* L = reinterpret_cast<lua_State*>(R_ExternalPtrAddr(xptr));
    RegistryEntry::DisarmAll(L);
    lua_close(L);
    R_ClearExternalPtr(xptr);
}

// Create a new Lua state
extern "C" SEXP luajr_open()
{
    return luajr_makepointer(luajr_newstate(), LUAJR_STATE_CODE, finalize_lua_state);
}

// Reset the default Lua state
extern "C" SEXP luajr_reset()
{
    if (L0)
    {
        RegistryEntry::DisarmAll(L0);
        lua_close(L0);
        L0 = 0;
    }
    return R_NilValue;
}

// Helper function to create a fresh Lua state with the required libraries
// and with the JIT compiler loaded.
extern "C" lua_State* luajr_newstate()
{
    // Create new state and open standard libraries; also enables JIT compiler
    lua_State* l = luaL_newstate();
    luaL_openlibs(l);

    // Get bytecode for luajr Lua module
    if (luajr_module_bytecode.empty())
    {
        // Call string.dump(luajr_module_source, true)
        lua_getglobal(l, "string");
        lua_getfield(l, -1, "dump");
        luajr_loadfile(l, luajr_module_path.c_str());
        lua_pushboolean(l, true);
        luajr_pcall(l, 2, 1, "string.dump() to precompile luajr Lua module", LUAJR_TOOLING_NONE);

        // Save results of string.dump
        size_t bytecode_len;
        const char* bytecode = lua_tolstring(l, -1, &bytecode_len);
        luajr_module_bytecode.assign(bytecode, bytecode_len);
        lua_pop(l, 2); // results of string.dump and "string"
    }

    // Load luajr bytecode
    luajr_loadbuffer(l, luajr_module_bytecode.data(), luajr_module_bytecode.size(), "luajr Lua module");

    // Run script: takes as arguments the full path to the luajr dylib and the
    // path to debugger.lua.
    lua_pushstring(l, luajr_dylib_path.c_str());
    lua_pushstring(l, luajr_debugger_path.c_str());
    luajr_pcall(l, 2, 0, "luajr Lua module from luajr_newstate()", LUAJR_TOOLING_NONE);

    // Open luajr module
    luajr_dostring(l, "luajr = require 'luajr'", LUAJR_TOOLING_NONE);

    // Save a few key luajr functions to the registry
    lua_getglobal(l, "luajr");

    for (unsigned int i = 0; luajr_registry_funcs[i].key != 0; ++i)
    {
        // Push key, get function from luajr module, register
        lua_pushlightuserdata(l, luajr_registry_funcs[i].key);
        lua_getfield(l, -2, luajr_registry_funcs[i].name);
        lua_rawset(l, LUA_REGISTRYINDEX);
    }

    lua_pop(l, 1); // luajr

    // Create luajrx table in registry
    lua_newtable(l);
    lua_setfield(l, LUA_REGISTRYINDEX, "luajrx");

    return l;
}

// Helper function to interpret the Lua state handle Lx as either a reference
// to the default luajr state (Lx == NULL) or to a Lua state opened with
// luajr::lua_open, and to return the corresponding lua_State*.
extern "C" lua_State* luajr_getstate(SEXP Lx)
{
    if (Lx == R_NilValue)
    {
        if (L0 == 0)
            L0 = luajr_newstate();
        return L0;
    }
    else
    {
        lua_State* l = reinterpret_cast<lua_State*>(luajr_getpointer(Lx, LUAJR_STATE_CODE));
        if (l)
            return l;
    }

    Rf_error("Lua state should be NULL or a value returned from lua_open.");
    return L0;
}
