#include "shared.h"
#include <string>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "luajit_rolling.h"
}
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include "luajr_module.h"

// luajr Lua module API registry keys
int luajr_construct_ref = 0;
int luajr_construct_vec = 0;
int luajr_construct_list = 0;
int luajr_return_info = 0;
int luajr_return_copy = 0;

// Path to luajr dylib
static std::string luajr_dylib_path;

// Provide luajr dylib path from R to luajr
// [[Rcpp::export]]
void luajr_locate_dylib(const char* path)
{
    luajr_dylib_path = path;
}

// For luajr_open and luajr_getstate's use of external pointers
static const int LUAJR_STATE_CODE = 0x7CA57A7E;

// Helper function to create a fresh Lua state with the required libraries
// and with the JIT compiler loaded.
extern "C" lua_State* luajr_newstate()
{
    // Create new state and open standard libraries; also enables JIT compiler
    lua_State* l = luaL_newstate();
    luaL_openlibs(l);

    // Load precompiled luajr Lua module pre-loading code in src/luajr_module.h,
    // which is in turn generated from local/luajr.lua
    if (luaL_loadbuffer(l, reinterpret_cast<const char*>(luaJIT_BC_luajr), luaJIT_BC_luajr_SIZE, "luajr Lua module"))
        Rf_error("Could not preload luajr Lua module.");

    // Run script: takes as argument the full path to the luajr dylib.
    lua_pushstring(l, luajr_dylib_path.c_str());
    luajr_pcall(l, 1, 0, "(luajr Lua module from luajr_newstate())");

    // Get luajr module
    luaL_loadstring(l, "luajr = require 'luajr'");
    luajr_pcall(l, 0, 0, "(require luajr module)");

    // Save a few key luajr functions to the registry
    lua_getglobal(l, "luajr");

    lua_pushlightuserdata(l, (void*)&luajr_construct_ref);
    lua_getfield(l, -2, "construct_ref");
    lua_rawset(l, LUA_REGISTRYINDEX);

    lua_pushlightuserdata(l, (void*)&luajr_construct_vec);
    lua_getfield(l, -2, "construct_vec");
    lua_rawset(l, LUA_REGISTRYINDEX);

    lua_pushlightuserdata(l, (void*)&luajr_construct_list);
    lua_getfield(l, -2, "construct_list");
    lua_rawset(l, LUA_REGISTRYINDEX);

    lua_pushlightuserdata(l, (void*)&luajr_return_info);
    lua_getfield(l, -2, "return_info");
    lua_rawset(l, LUA_REGISTRYINDEX);

    lua_pushlightuserdata(l, (void*)&luajr_return_copy);
    lua_getfield(l, -2, "return_copy");
    lua_rawset(l, LUA_REGISTRYINDEX);

    lua_pop(l, 1); // luajr

    return l;
}

// Destroy a Lua state pointed to by an R external pointer when it is no longer
// needed (i.e. at program exit or garbage collection of the R pointer).
static void finalize_lua_state(SEXP xptr)
{
    lua_close(reinterpret_cast<lua_State*>(R_ExternalPtrAddr(xptr)));
    R_ClearExternalPtr(xptr);
}

//' Create a new Lua state
//'
//' Creates a new, empty Lua state and returns an external pointer wrapping that
//' state.
//'
//' All Lua code is executed within a given Lua state. A Lua state is similar to
//' the global environment in R, in that it is where all variables and functions
//' are defined. \pkg{luajr} automatically maintains a "default" Lua state, so
//' most users of \pkg{luajr} will not need to use [lua_open()].
//'
//' However, if for whatever reason you want to maintain multiple different Lua
//' states at a time, each with their own independent global variables and
//' functions, [lua_open()] can be used to create a new Lua state which can then
//' be passed to [lua()], [lua_func()] and [lua_shell()] via the `L` parameter.
//' These functions will then operate within that Lua state instead of the
//' default one. The default Lua state can be specified explicitly with
//' `L = NULL`.
//'
//' Note that there is currently no way (provided by \pkg{luajr}) of saving a
//' Lua state to disk so that the state can be restarted later. Also, there is
//' no `lua_close` in \pkg{luajr} because Lua states are closed automatically
//' when they are garbage collected in R.
//'
//' @usage L <- lua_open()
//'
//' @return External pointer wrapping the newly created Lua state.
//' @examples
//' L1 <- lua_open()
//' lua("a = 2")
//' lua("a = 4", L = L1)
//' lua("print(a)")
//' lua("print(a)", L = L1)
//' @export lua_open
// [[Rcpp::export(lua_open)]]
extern "C" SEXP luajr_open()
{
    return luajr_makepointer(luajr_newstate(), LUAJR_STATE_CODE, finalize_lua_state);
}

//' Reset the default Lua state
//'
//' Clears out all variables from the default Lua state, freeing up the
//' associated memory.
//'
//' This resets the default [Lua state][lua_open] only. To reset a non-default
//' Lua state `L` returned by [lua_open()], just do `L <- lua_open()` again. The
//' memory previously used will be cleaned up at the next garbage collection.
//'
//' @examples
//' lua("a = 2")
//' lua_reset()
//' lua("print(a)") # nil
//' @export lua_reset
// [[Rcpp::export(lua_reset)]]
void luajr_reset() // I only omit the extern "C" from here to get around an Rcpp bug -- this is still extern "C".
{
    if (L0)
    {
        lua_close(L0);
        L0 = 0;
    }
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
