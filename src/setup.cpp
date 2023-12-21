#include "shared.h"
#include <R.h>
#include <Rinternals.h>
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
