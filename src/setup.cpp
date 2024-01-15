#include "shared.h"
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "luajit_rolling.h"
}
#include <string>
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// Global definitions
lua_State* L0 = 0;

// Initializes the luajr package
// [[Rcpp::init]]
void luajr_init(DllInfo *dll)
{
    (void) dll;

    // Register API functions, so that they can be called from user C/C++ code
#define API_FUNCTION(return_type, func_name, ...) \
    R_RegisterCCallable("luajr", #func_name, reinterpret_cast<DL_FUNC>(func_name));
#include "../inst/include/luajr_funcs.h"
#undef API_FUNCTION
}

// Helper to make an external pointer handle
SEXP luajr_makepointer(void* ptr, int tag_code, void (*finalize)(SEXP))
{
    // TODO Use this to wrap the external pointer in a list
    // SEXP x = PROTECT(Rf_allocVector3(VECSXP, 1, NULL));
    // SEXP tag = PROTECT(Rf_ScalarInteger(tag_code));
    // SET_VECTOR_ELT(x, 0, R_MakeExternalPtr(ptr, tag, R_NilValue));
    // R_RegisterCFinalizerEx(VECTOR_ELT(x, 0), finalize, TRUE);
    // UNPROTECT(2);
    // return x;

    // TODO Use this to NOT wrap the external pointer in a list
    SEXP tag = PROTECT(Rf_ScalarInteger(tag_code));
    SEXP x = PROTECT(R_MakeExternalPtr(ptr, tag, R_NilValue));
    R_RegisterCFinalizerEx(x, finalize, TRUE);
    UNPROTECT(2);
    return x;
}

// Helper to get the pointer from an external pointer handle
void* luajr_getpointer(SEXP x, int tag_code)
{
    // TODO Use this to wrap the external pointer in a list
    // if (TYPEOF(x) == VECSXP && Rf_length(x) == 1)
    // {
    //     SEXP ptr = VECTOR_ELT(x, 0);
    //     if (TYPEOF(ptr) == EXTPTRSXP && Rf_asInteger(R_ExternalPtrTag(ptr)) == tag_code)
    //         return R_ExternalPtrAddr(ptr);
    // }
    // return 0;

    // TODO Use this to NOT wrap the external pointer in a list
    if (TYPEOF(x) == EXTPTRSXP && Rf_asInteger(R_ExternalPtrTag(x)) == tag_code)
        return R_ExternalPtrAddr(x);
    return 0;
}

void luajr_pcall(lua_State* L, int nargs, int nresults, const char* funcdesc)
{
    int err = lua_pcall(L, nargs, nresults, 0);
    if (err != 0)
    {
        std::string msg = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rf_error("Error while calling Lua function %s: %s", funcdesc, msg.c_str());
    }
}
