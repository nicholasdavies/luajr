#include "shared.h"
#include "registry_entry.h"
#include <string>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

// luajr Lua module API registry keys (registered by address)
int luajr_get_func_info = 0;

// luajr module functions to register
struct RegistryFunc { void* key; const char* name; };
static const RegistryFunc luajr_registry_funcs[] =
{
    { (void*)&luajr_get_func_info,  "get_func_info" },
    { 0, 0 }
};

// lua_CFunctions to expose to the luajr.lua
struct CFunctionEntry { const char* name; int (*fn)(lua_State*); };
static const CFunctionEntry luajr_cfuncs[] =
{
    { "tosexp",        luajr_tosexp_cf       },
    { "fromsexp",      luajr_fromsexp_cf     },
    { "rcall",         luajr_rcall_cf         },
    { "parallel_load", luajr_parallel_load_cf },
    { "thisstate",     luajr_thisstate_cf     }
};

// R version as array of three integers
static int luajr_R_version[3] = { 0, 0, 0 };

// Path to luajr dylib
static std::string luajr_dylib_path;

// Path to R shared library (for Windows only)
static std::string luajr_R_dll_path;

// Path to luajr module source
static std::string luajr_module_path;

// Bytecode for luajr module
static std::string luajr_module_bytecode;

// Path to R module source
static std::string luajr_R_module_path;

// Bytecode for R module
static std::string luajr_R_module_bytecode;

// Path to debugger.lua
static std::string luajr_debugger_path;

// Provide information to luajr on R version and paths
extern "C" SEXP luajr_register(SEXP Rver, SEXP dylib, SEXP dll, SEXP luajr_mod, SEXP R_mod, SEXP dbg_mod)
{
    CheckSEXPLen(Rver, INTSXP, 3);
    CheckSEXPLen(dylib, STRSXP, 1);
    CheckSEXPLen(dll, STRSXP, 1);
    CheckSEXPLen(luajr_mod, STRSXP, 1);
    CheckSEXPLen(R_mod, STRSXP, 1);
    CheckSEXPLen(dbg_mod, STRSXP, 1);

    luajr_R_version[0] = INTEGER(Rver)[0];
    luajr_R_version[1] = INTEGER(Rver)[1];
    luajr_R_version[2] = INTEGER(Rver)[2];
    luajr_dylib_path = CHAR(STRING_ELT(dylib, 0));
    luajr_R_dll_path = CHAR(STRING_ELT(dll, 0));
    luajr_module_path = CHAR(STRING_ELT(luajr_mod, 0));
    luajr_R_module_path = CHAR(STRING_ELT(R_mod, 0));
    luajr_debugger_path = CHAR(STRING_ELT(dbg_mod, 0));

    return R_NilValue;
}

// Destroy a Lua state pointed to by an R external pointer when it is no longer
// needed (i.e. at program exit or garbage collection of the R pointer).
static void finalize_lua_state(SEXP xptr)
{
    lua_State* L = reinterpret_cast<lua_State*>(R_ExternalPtrAddr(xptr));
    luajr_closeprofile(L);
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
        luajr_closeprofile(L0);
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

    // R MODULE

    // Get bytecode for R Lua module
    if (luajr_R_module_bytecode.empty())
    {
        // Call string.dump(luajr_R_module_source, true)
        lua_getglobal(l, "string");
        lua_getfield(l, -1, "dump");
        luajr_loadfile(l, luajr_R_module_path.c_str());
        lua_pushboolean(l, true);
        luajr_pcall(l, 2, 1, "string.dump() to precompile R Lua module", LUAJR_TOOLING_NONE);

        // Save results of string.dump
        size_t bytecode_len;
        const char* bytecode = lua_tolstring(l, -1, &bytecode_len);
        luajr_R_module_bytecode.assign(bytecode, bytecode_len);
        lua_pop(l, 2); // results of string.dump and "string"
    }

    // Load R module bytecode
    luajr_loadbuffer(l, luajr_R_module_bytecode.data(), luajr_R_module_bytecode.size(), "=R module");

    // Run script: takes as arguments the R version, Windows R DLL path, and R lib path.
    lua_pushinteger(l, luajr_R_version[0] * 10000 + luajr_R_version[1] * 100 + luajr_R_version[2]);
    lua_pushstring(l, luajr_dylib_path.c_str());
    lua_pushstring(l, luajr_R_dll_path.c_str());
    luajr_pcall(l, 3, 0, "R module from luajr_newstate()", LUAJR_TOOLING_NONE);

    // LUAJR MODULE

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

    // Load luajr module bytecode
    luajr_loadbuffer(l, luajr_module_bytecode.data(), luajr_module_bytecode.size(), "=luajr module");

    // Run script: takes as arguments the full path to the luajr dylib, the
    // path to debugger.lua, and a Lua table of CFunctions to install as
    // luajr.funcname.
    lua_pushstring(l, luajr_dylib_path.c_str());
    lua_pushstring(l, luajr_debugger_path.c_str());
    const int n_cfuncs = (int)(sizeof(luajr_cfuncs) / sizeof(*luajr_cfuncs));
    lua_createtable(l, 0, n_cfuncs);
    for (int i = 0; i < n_cfuncs; ++i)
    {
        lua_pushcfunction(l, luajr_cfuncs[i].fn);
        lua_setfield(l, -2, luajr_cfuncs[i].name);
    }
    luajr_pcall(l, 3, 0, "luajr module from luajr_newstate()", LUAJR_TOOLING_NONE);

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

// lua_CFunction: returns the calling Lua state as a lightuserdata. Used to
// expose lua_State* to FFI calls that need it for pcall-aware error handling.
extern "C" int luajr_thisstate_cf(lua_State* L)
{
    lua_pushlightuserdata(L, L);
    return 1;
}
