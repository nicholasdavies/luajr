#include "shared.h"
#include "../inst/include/registry.h"
#include <Rcpp.h>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "luajit_rolling.h"
}

// Global definitions
lua_State* L0 = 0;
SEXP RObjRetSymbol = NULL;

// Initializes the luajr package
// [[Rcpp::init]]
void luajr_init(DllInfo *dll)
{
    (void) dll;

    // Cache lookup for symbol robj_ret
    if (RObjRetSymbol == NULL)
        RObjRetSymbol = Rf_install("robj_ret");

    // Register API functions, so that they can be called from user C/C++ code
#define API_FUNCTION(return_type, func_name, ...) \
    R_RegisterCCallable("luajr", #func_name, reinterpret_cast<DL_FUNC>(func_name));
#include "../inst/include/luajr_funcs.h"
#undef API_FUNCTION
}

void R_pass_to_Lua(lua_State* L, SEXP args, const char* acode)
{
    unsigned int acode_length = std::strlen(acode);
    if (acode_length == 0)
        Rcpp::stop("Length of args code is zero.");
    for (int i = 0; i < Rf_length(args); ++i)
        luajr_pushsexp(L, VECTOR_ELT(args, i), acode[i % acode_length]);
}

SEXP Lua_return_to_R(lua_State* L, int nret)
{
    // No return value: return NULL
    if (nret == 0)
    {
        return R_NilValue;
    }
    else if (nret == 1)
    {
        // One return value: convert to SEXP, pop, and return
        SEXP retval = luajr_tosexp(L, -1);
        lua_pop(L, 1);
        return retval;
    }
    else
    {
        // Multiple return values: return as list
        SEXP retlist = PROTECT(Rf_allocVector3(VECSXP, nret, NULL));

        // Add elements to table (popping from top of stack)
        for (int i = 0; i < nret; ++i)
        {
            SEXP v = PROTECT(luajr_tosexp(L, -nret + i));
            SET_VECTOR_ELT(retlist, i, v);
        }

        lua_pop(L, nret);
        UNPROTECT(1 + nret);
        return retlist;
    }
}

// Create a registry entry.
RegistryEntry::RegistryEntry(lua_State* L)
 : l(L)
{ }

// Delete the registry entry.
RegistryEntry::~RegistryEntry()
{
    lua_pushlightuserdata(l, (void*)this);  // push registry handle to stack
    lua_pushnil(l);                         // push nil to stack
    lua_settable(l, LUA_REGISTRYINDEX);     // set registry entry to nil
}

// Register the value at the top of the stack. Pops the value from the stack.
void RegistryEntry::Register()
{
    lua_pushlightuserdata(l, (void*)this);  // push registry handle to stack
    lua_insert(l, -2);                      // move registry handle below value on stack
    lua_settable(l, LUA_REGISTRYINDEX);     // set value in registry
}

// Put the registered value at the top of the stack.
void RegistryEntry::Get()
{
    lua_pushlightuserdata(l, (void*)this);  // push registry handle to stack
    lua_gettable(l, LUA_REGISTRYINDEX);     // get entry on stack
}

