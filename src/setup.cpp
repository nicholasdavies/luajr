#include "shared.h"
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "luajit_build.h"
}
#include <string>
#include <csignal>
#include <cstdarg>

extern "C" int R_ReadConsole(const char*, unsigned char*, int, int);

// Global definitions
lua_State* L0 = 0;

// Initializes the luajr package
static const R_CallMethodDef CallEntries[] =
{
    { "_luajr_register",   (DL_FUNC)&luajr_register,   6 },
    { "_luajr_open",       (DL_FUNC)&luajr_open,       0 },
    { "_luajr_reset",      (DL_FUNC)&luajr_reset,      0 },
    { "_luajr_runcode",    (DL_FUNC)&luajr_runcode,    2 },
    { "_luajr_runfile",    (DL_FUNC)&luajr_runfile,    2 },
    { "_luajr_fcreate",    (DL_FUNC)&luajr_fcreate,    2 },
    { "_luajr_fcall",      (DL_FUNC)&luajr_fcall,      4 },
    { "_luajr_fcall0",     (DL_FUNC)&luajr_fcall0,     3 },
    { "_luajr_fcall1",     (DL_FUNC)&luajr_fcall1,     4 },
    { "_luajr_fcall2",     (DL_FUNC)&luajr_fcall2,     5 },
    { "_luajr_fcall3",     (DL_FUNC)&luajr_fcall3,     6 },
    { "_luajr_fcall4",     (DL_FUNC)&luajr_fcall4,     7 },
    { "_luajr_fcall5",     (DL_FUNC)&luajr_fcall5,     8 },
    { "_luajr_fcall6",     (DL_FUNC)&luajr_fcall6,     9 },
    { "_luajr_fcall7",     (DL_FUNC)&luajr_fcall7,     10 },
    { "_luajr_fcall8",     (DL_FUNC)&luajr_fcall8,     11 },
    { "_luajr_finfo",      (DL_FUNC)&luajr_finfo,      1 },
    { "_luajr_loadmodule", (DL_FUNC)&luajr_loadmodule, 2 },
    { "_luajr_moduleget",  (DL_FUNC)&luajr_moduleget,  3 },
    { "_luajr_moduleset",  (DL_FUNC)&luajr_moduleset,  4 },
    { "_luajr_getprofile", (DL_FUNC)&luajr_getprofile, 1 },
    { "_luajr_setmode",    (DL_FUNC)&luajr_setmode,    3 },
    { "_luajr_getmode",    (DL_FUNC)&luajr_getmode,    0 },
    { "_luajr_readline",   (DL_FUNC)&luajr_readline,   1 },
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

// Error handling: translate 'err' from Lua error code to string
static const char* luajr_lua_errtype(int err)
{
    switch (err)
    {
        case LUA_OK:
            return "No";
        case LUA_ERRRUN:
            return "Runtime";
        case LUA_ERRSYNTAX:
            return "Syntax";
        case LUA_ERRMEM:
            return "Memory allocation";
        case LUA_ERRERR:
            return "Error handler";
        case LUA_ERRFILE:
            return "File";
        default:
            return "Unknown";
    }
}

// Raise an error from luajr code. If L is non-null and currently inside a
// lua_pcall, errors via luaL_error so Lua can clean up its stack frames.
// Otherwise errors via Rf_error.
extern "C" void luajr_error(lua_State* L, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    if (L && luajr_internal_inpcall(L))
    {
        lua_pushvfstring(L, fmt, args);
        va_end(args);
        lua_error(L);
        __builtin_unreachable();
    }
    else
    {
        char buf[1024];
        vsnprintf(buf, sizeof(buf), fmt, args);
        va_end(args);
        Rf_error("%s", buf);
    }
}

#define do_error(hide, ...) \
    do { \
        if (buf)       { snprintf(buf, 1024, __VA_ARGS__); return hide ? 2 : 1; } \
        else if (hide) { Rf_errorcall(R_NilValue, __VA_ARGS__); } \
        else           { Rf_error(__VA_ARGS__); } \
    } while (0)

// Raise an R error for Lua error 'err', which can be 0 for no error
// The error object must be at the top of the stack
extern "C" int luajr_handleerror(lua_State* L, int err, const char* what, char* buf)
{
    if (err != 0)
    {
        const char* errtype = luajr_lua_errtype(err);
        const char* msg_p = lua_tostring(L, -1);
        if (!what)
            what = "(unknown)";

        if (msg_p)
        {
            std::string msg = msg_p;
            lua_pop(L, 1);
            // Special exit if user has triggered 'quit' from debugger.lua.
            // If the error message changes here, need to also change corresponding
            // check in lua_shell.
            if (msg.find("~!#DBGEXIT#!~") != std::string::npos)
                do_error(true, "Quit debugger.");
            do_error(false, "%s error in %s: %s", errtype, what, msg.c_str());
        }
        else
        {
            const char* type = lua_typename(L, lua_type(L, -1));
            lua_pop(L, 1);
            do_error(false, "%s error in %s: (error object is a %s value)", errtype, what, type);
        }
    }
    return 0;
}

// Replacement for R's readline for lua_shell: this one adds lines to the history
extern "C" SEXP luajr_readline(SEXP prompt)
{
    CheckSEXPLen(prompt, STRSXP, 1);

    // R does not allow reading lines of more than 1024 characters (including terminating \n\0).
    const size_t bufsize = 1024;
    std::string buffer(bufsize, '\0');

    if (!R_ReadConsole(CHAR(STRING_ELT(prompt, 0)), (unsigned char*)buffer.data(), bufsize, 1))
        return R_BlankScalarString;

    SEXP retval = PROTECT(Rf_allocVector(STRSXP, 1));
    SET_STRING_ELT(retval, 0, Rf_mkCharLen(buffer.data(), std::strlen(buffer.data()) - 1)); // -1 to cut the newline
    UNPROTECT(1);
    return retval;
}

// Pop n items from the Lua stack, then throw an error via luajr_error.
extern "C" void luajr_popstop(lua_State* L, int n, const char* fmt, ...)
{
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    lua_pop(L, n);
    luajr_error(L, "%s", buf);
}
