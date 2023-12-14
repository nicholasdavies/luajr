#include "shared.h"
#include "../inst/include/registry.h"

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

void R_pass_to_Lua(lua_State* L, Rcpp::List args, const char* acode)
{
    unsigned int acode_length = std::strlen(acode);
    if (acode_length == 0)
        Rcpp::stop("Length of args code is zero.");
    for (int i = 0; i < args.size(); ++i)
        luajr_pushsexp(L, args[i], acode[i % acode_length]);
}

SEXP Lua_return_to_R(lua_State* L, int nret)
{
    // No return value: return NULL
    if (nret == 0)
    {
        return R_NilValue;
    }

    // Multiple return values: collapse into one table
    if (nret > 1)
    {
        // Creates a new table at the top of the stack with space for nret array elements.
        lua_createtable(L, nret, 0);

        // Move table underneath returned values
        lua_insert(L, -nret - 1);

        // Add elements to table (popping from top of stack)
        for (int i = nret; i > 0; --i)
            lua_rawseti(L, -nret - 1, i);
    }

    // One return value: convert to SEXP, pop, and return
    SEXP retval = luajr_tosexp(L, -1);
    lua_pop(L, 1);
    return retval;
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

