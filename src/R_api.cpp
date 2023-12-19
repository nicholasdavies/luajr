// Functions designed to be called from R code (or constituents thereof).

#include "shared.h"
#include "../inst/include/registry.h"
#include <Rcpp.h>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

const int LUAJR_STATE_CODE = 0x7CA57A7E;

// Helper function to create a fresh Lua state with the required libraries
// and with the JIT compiler loaded.
lua_State* new_lua_state()
{
    // "lua" (see TODO below)
    lua_State* l = luaL_newstate();
    luaL_openlibs(l); // also enables the JIT compiler

    // TODO this needs optimizing:
    // luajr::lua_open() [from R] takes:
    // # 161 µs for lua + rcpp
    // # 148 µs for lua + r
    // # 145 µs for lua + as char
    // # 64 µs for lua only
    // the point: would be good to serialize the luajr lua module if poss
    // A good solution to this would be to use the luajit standalone:
    // https://luajit.org/running.html
    // i.e. luajit -b luajr.lua luajr.raw
    // then luajr.raw can be loaded with luaL_dofile() in the usual way.
    // note use the installed version of the luajit standalone as the one
    // inside this package isn't working for this task.
    // Note, can pass args to a file using
    // local params = {...}
    // params[1] -- first parameter, if any.
    // params[2] -- second parameter, if any.
    // #params   -- number of parameters.

    // "rcpp"
    Rcpp::Environment package_env = Rcpp::Environment::namespace_env("luajr");
    Rcpp::Environment cache_env(package_env["cache_env"]);
    const char* code = Rcpp::as<const char*>(cache_env["luajr.lua"]);
    luaL_dostring(l, code);

    // "r"
    // SEXP luajrNS = PROTECT(R_FindNamespace(Rf_mkString("luajr")));
    // if (luajrNS == R_UnboundValue)
    //     Rcpp::stop("missing luajr namespace: this should not happen");
    //
    // SEXP cache_env = PROTECT(Rf_findVarInFrame3(luajrNS, Rf_install("cache_env"), TRUE));
    // if (cache_env == R_UnboundValue)
    //     Rcpp::stop("missing cache_env in luajr namespace: this should not happen");
    //
    // // If cache_env is a promise, evaluate it
    // if (TYPEOF(cache_env) == PROMSXP)
    // {
    //     //PROTECT(cache_env);
    //     cache_env = Rf_eval(cache_env, R_GlobalEnv);
    //     //UNPROTECT(1);
    // }
    //
    // SEXP code = Rf_findVar(Rf_install("luajr.lua"), cache_env);
    // if (code == R_UnboundValue)
    //     Rcpp::stop("missing code in cache_env namespace: this should not happen");
    //
    // luaL_dostring(l, CHAR(STRING_ELT(code, 0)));
    // UNPROTECT(1);

    // "as char"
    // const char* code = "local ffi = require('ffi')\n\nffi.cdef[[\nint AllocRDataMatrix(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);\nint AllocRDataFrame(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);\n]]\nlocal luajr_internal = ffi.load(\"/Library/Frameworks/R.framework/Versions/4.3-x86_64/Resources/library/luajr/libs/luajr.so\")\n\nlocal luajr = {}\n\nfunction luajr.DataMatrix(nrow, ncol, names)\n    data = ffi.new(\"double*[?]\", ncol)\n    cnames = ffi.new(\"const char*[?]\", ncol, names)\n    id = luajr_internal.AllocRDataMatrix(nrow, ncol, cnames, data)\n    m = { __robj_ret_i = id }\n    for i = 1, #names do\n        m[names[i]] = data[i-1]\n    end\n    return m\nend\n\nfunction luajr.DataFrame(nrow, ncol, names)\n    data = ffi.new(\"double*[?]\", ncol)\n    cnames = ffi.new(\"const char*[?]\", ncol, names)\n    id = luajr_internal.AllocRDataFrame(nrow, ncol, cnames, data)\n    df = { __robj_ret_i = id }\n    for i = 1, #names do\n        df[names[i]] = data[i-1]\n    end\n    return df\nend\n\npackage.preload.luajr = function() return luajr end";
    // luaL_dostring(l, code);

    return l;
}

// Destroy a Lua state pointed to by an R external pointer when it is no longer
// needed (i.e. at program exit or garbage collection of the R pointer).
void finalize_lua_state(SEXP Lxp)
{
    lua_close(reinterpret_cast<lua_State*>(R_ExternalPtrAddr(Lxp)));
    R_ClearExternalPtr(Lxp);
}

//' Create a new Lua state.
//'
//' Creates a new, empty Lua state and returns an external pointer wrapping that
//' state.
//'
//' All Lua code is executed within a given Lua state. A Lua state is similar to
//' the global environment in R, in that it is where all variables and functions
//' are defined. \pkg{luajr} automatically maintains a "default" Lua state, so
//' most users of \pkg{luajr} will not need to use \code{\link{lua_open}}.
//'
//' However, if for whatever reason you want to maintain multiple different Lua
//' states at a time, each with their own independent global variables and
//' functions, \code{\link{lua_open}} can be used to create a new Lua state
//' which can then be passed to \code{\link{lua}}, \code{\link{lua_func}} and
//' \code{\link{lua_shell}} via the \code{L} parameter. These functions will
//' then operate within that Lua state instead of the default one. The default
//' Lua state can be specified explicitly with \code{L = NULL}.
//'
//' Note that there is currently no way (provided by \pkg{luajr}) of saving a
//' Lua state to disk so that the state can be restarted later. Also, there is
//' no \code{lua_close} in \pkg{luajr} because when the R object returned by
//' \code{\link{lua_open}} is garbage collected, the Lua state is closed then.
//'
//' @return External pointer wrapping the Lua state.
//' @examples
//' L1 = lua_open()
//' lua("a = 2")
//' lua("a = 4", L = L1)
//' lua("print(a)")
//' lua("print(a)", L = L1)
//' @export lua_open
// [[Rcpp::export(lua_open)]]
SEXP luajr_open()
{
    SEXP Lxp = R_MakeExternalPtr(new_lua_state(), Rf_ScalarInteger(LUAJR_STATE_CODE), R_NilValue);
    R_RegisterCFinalizerEx(Lxp, finalize_lua_state, TRUE);
    return Lxp;
}

// Helper function to interpret the Lua state handle Lxp as either a reference
// to the default luajr state (Lxp == NULL) or to a Lua state started with
// lua_open and to return the corresponding lua_State*.
lua_State* luajr_getstate(SEXP Lxp)
{
    if (Lxp == R_NilValue) {
        if (L0 == 0)
            L0 = new_lua_state();
        return L0;
    } else if (TYPEOF(Lxp) == EXTPTRSXP && Rf_asInteger(R_ExternalPtrTag(Lxp)) == LUAJR_STATE_CODE) {
        return reinterpret_cast<lua_State*>(R_ExternalPtrAddr(Lxp));
    }

    Rcpp::stop("Lua state should be NULL or a value returned from lua_open.");
    return L0;
}

// Run the specified Lua code or file.
// If mode == 0, run code. If mode == 1, run file.
// Behaviour is undefined for any other mode.
// [[Rcpp::export]]
SEXP luajr_run(const char* code, int mode, SEXP Lxp)
{
    // Get Lua state
    lua_State* L = luajr_getstate(Lxp);

    // Run code, counting number of returned values
    int top0 = lua_gettop(L);
    int r;
    if (mode == 0)
        r = luaL_dostring(L, code);
    else
        r = luaL_dofile(L, code);
    if (r)
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rcpp::stop(err);
    }
    int top1 = lua_gettop(L);

    // Return results
    return Lua_return_to_R(L, top1 - top0);
}

// [[Rcpp::export]]
SEXP luajr_func_create(const char* code, SEXP Lxp)
{
    // Get Lua state
    lua_State* L = luajr_getstate(Lxp);

    // Run code, counting number of returned values
    std::string cmd = "return ";
    cmd += code;
    int top0 = lua_gettop(L);
    if (luaL_dostring(L, cmd.c_str()))
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rcpp::stop(err);
    }
    int top1 = lua_gettop(L);
    int nret = top1 - top0;

    // Handle mistakes
    if (nret != 1)
        Rcpp::stop("luafunc_internal expects `code' to evaluate to one value, not %d.", nret);
    if (lua_type(L, -1) != LUA_TFUNCTION)
        Rcpp::stop("luafunc_internal expects `code' to evaluate to a function, not a %s.", lua_typename(L, lua_type(L, -1)));

    // Send back a registry entry
    RegistryEntry* re = new RegistryEntry(L);
    re->Register();
    return Rcpp::XPtr<RegistryEntry>(re, true);
}

// [[Rcpp::export]]
SEXP luajr_func_call(Rcpp::XPtr<RegistryEntry> fptr, Rcpp::List alist, const char* acode, SEXP Lxp)
{
    // Get Lua state
    lua_State* L = luajr_getstate(Lxp);

    // Assemble function call
    int top0 = lua_gettop(L);
    fptr->Get();
    R_pass_to_Lua(L, alist, acode);

    // Call function
    if (lua_pcall(L, alist.size(), LUA_MULTRET, 0))
    {
        std::string err = lua_tostring(L, -1);
        lua_pop(L, 1);
        Rcpp::stop(err.c_str());
    }
    int top1 = lua_gettop(L);

    // Return results
    return Lua_return_to_R(L, top1 - top0);
}
