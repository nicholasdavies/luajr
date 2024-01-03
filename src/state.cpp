#include "shared.h"
#include <string>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "luajit_rolling.h"
}
#include "luajr_module.h"
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

static std::string luajr_dylib_path;

// Provide luajr dylib path from R to luajr
// [[Rcpp::export]]
void luajr_locate_dylib(const char* path)
{
    luajr_dylib_path = path;
}

const int LUAJR_STATE_CODE = 0x7CA57A7E;

// Helper function to create a fresh Lua state with the required libraries
// and with the JIT compiler loaded.
lua_State* new_lua_state()
{
    // Create new state and open standard libraries; also enables JIT compiler
    lua_State* l = luaL_newstate();
    luaL_openlibs(l);

    // Run precompiled luajr Lua module pre-loading code in src/luajr_module.h,
    // which is in turn generated from local/luajr.lua; this script takes one
    // argument, the full path to the luajr dylib.
    if (luaL_loadbuffer(l, reinterpret_cast<const char*>(luaJIT_BC_luajr), luaJIT_BC_luajr_SIZE, "luajr Lua module"))
        Rf_error("Could not preload luajr Lua module.");

    lua_pushstring(l, luajr_dylib_path.c_str());
    lua_pcall(l, 1, 0, 0);

    return l;
}

// Destroy a Lua state pointed to by an R external pointer when it is no longer
// needed (i.e. at program exit or garbage collection of the R pointer).
void finalize_lua_state(SEXP xptr)
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
//' no `lua_close` in \pkg{luajr} because when the R object returned by
//' [lua_open()] is garbage collected, the Lua state is closed then.
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
SEXP luajr_open()
{
    return MakePointer(new_lua_state(), LUAJR_STATE_CODE, finalize_lua_state);
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
void luajr_reset()
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
lua_State* luajr_getstate(SEXP Lx)
{
    if (Lx == R_NilValue)
    {
        if (L0 == 0)
            L0 = new_lua_state();
        return L0;
    }
    else
    {
        lua_State* l = reinterpret_cast<lua_State*>(GetPointer(Lx, LUAJR_STATE_CODE));
        if (l)
            return l;
    }

    Rf_error("Lua state should be NULL or a value returned from lua_open.");
    return L0;
}
