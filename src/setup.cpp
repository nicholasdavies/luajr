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

// Helper to make an external pointer handle
SEXP MakePointer(void* ptr, int tag_code, void (*finalize)(SEXP))
{
    // SEXP x = PROTECT(Rf_allocVector3(VECSXP, 1, NULL));
    // SEXP tag = PROTECT(Rf_ScalarInteger(tag_code));
    // ((SEXP*)DATAPTR(x))[0] = R_MakeExternalPtr(ptr, tag, R_NilValue);
    // R_RegisterCFinalizerEx(((SEXP*)DATAPTR(x))[0], finalize, TRUE);
    // UNPROTECT(2);
    // return x;

    SEXP tag = PROTECT(Rf_ScalarInteger(tag_code));
    SEXP x = PROTECT(R_MakeExternalPtr(ptr, tag, R_NilValue));
    R_RegisterCFinalizerEx(x, finalize, TRUE);
    UNPROTECT(2);
    return x;
}

// Helper to get the pointer from an external pointer handle
void* GetPointer(SEXP x, int tag_code)
{
    // if (TYPEOF(x) == VECSXP && Rf_length(x) == 1)
    // {
    //     SEXP ptr = ((SEXP*)DATAPTR(x))[0];
    //     if (TYPEOF(ptr) == EXTPTRSXP && Rf_asInteger(R_ExternalPtrTag(ptr)) == tag_code)
    //         return R_ExternalPtrAddr(ptr);
    // }
    // return 0;

    if (TYPEOF(x) == EXTPTRSXP && Rf_asInteger(R_ExternalPtrTag(x)) == tag_code)
        return R_ExternalPtrAddr(x);
    return 0;
}
