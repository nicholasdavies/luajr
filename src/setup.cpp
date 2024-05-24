#include "shared.h"
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "luajit_build.h"
}
#include <string>
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

extern "C" int R_ReadConsole(const char *, unsigned char *, int, int);

// Global definitions
lua_State* L0 = 0;

// Initializes the luajr package
static const R_CallMethodDef CallEntries[] =
{
    { "_luajr_locate_dylib",    (DL_FUNC)&luajr_locate_dylib,   1 },
    { "_luajr_locate_module",   (DL_FUNC)&luajr_locate_module,  1 },
    { "_luajr_open",            (DL_FUNC)&luajr_open,           0 },
    { "_luajr_reset",           (DL_FUNC)&luajr_reset,          0 },
    { "_luajr_run_code",        (DL_FUNC)&luajr_run_code,       2 },
    { "_luajr_run_file",        (DL_FUNC)&luajr_run_file,       2 },
    { "_luajr_func_create",     (DL_FUNC)&luajr_func_create,    2 },
    { "_luajr_func_call",       (DL_FUNC)&luajr_func_call,      4 },
    { "_luajr_run_parallel",    (DL_FUNC)&luajr_run_parallel,   4 },
    { "_luajr_readline",        (DL_FUNC)&luajr_readline,       1 },
    { NULL, NULL, 0 }
};

// Initializes the luajr package
extern "C" void R_init_luajr(DllInfo *dll)
{
    // Register luajr API functions that can be called from package/user R code
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);

    // Register Lua, LuaJIT, and luajr API functions that can be called from user C/C++ code
#define API_FUNCTION(return_type, func_name, ...) \
    R_RegisterCCallable("luajr", #func_name, reinterpret_cast<DL_FUNC>(func_name));
#include "../inst/include/luajr_funcs.h"
#undef API_FUNCTION
}

// Helper to make an external pointer handle
extern "C" SEXP luajr_makepointer(void* ptr, int tag_code, void (*finalize)(SEXP))
{
    // TODO Use this to wrap the external pointer in a list
    // SEXP x = PROTECT(Rf_allocVector(VECSXP, 1));
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
extern "C" void* luajr_getpointer(SEXP x, int tag_code)
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

// Like lua_pcall, but produce an R error if the function call fails
extern "C" void luajr_pcall(lua_State* L, int nargs, int nresults, const char* funcdesc)
{
    int err = lua_pcall(L, nargs, nresults, 0);
    if (err != 0)
    {
        std::string msg = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rf_error("Error while calling Lua function %s: %s", funcdesc, msg.c_str());
    }
}

// Replacement for R's readline for lua_shell: this one adds lines to the history
extern "C" SEXP luajr_readline(SEXP prompt)
{
    CheckSEXPLen(prompt, STRSXP, 1);

    const size_t bufsize = 4096;
    std::string buffer(bufsize, '\0');

    if (!R_ReadConsole(CHAR(STRING_ELT(prompt, 0)), (unsigned char*)buffer.data(), bufsize, 1))
        return R_BlankScalarString;

    SEXP retval = PROTECT(Rf_allocVector(STRSXP, 1));
    SET_STRING_ELT(retval, 0, Rf_mkCharLen(buffer.data(), std::strlen(buffer.data()) - 1)); // -1 to cut the newline
    UNPROTECT(1);
    return retval;
}
