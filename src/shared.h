// R headers
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// Forward declarations
struct lua_State;

// The shared global Lua state
extern lua_State* L0;

// luajr Lua module API registry keys
extern int luajr_get_func_info;

// We declare all functions to have C linkage to avoid name mangling and allow
// the use of the package functions from C code. This file (shared.h) is only
// included when building the R package, i.e. from C++, so no #ifdef __cplusplus
// wrapper is needed here.
extern "C" {

// Declare luajr API functions in src/shared.h, inst/include/luajr.h, and inst/include/luajr_funcs.h.

// Lua state related functions (state.cpp)
SEXP luajr_set_info(SEXP Rver, SEXP dylib, SEXP R_lib, SEXP luajr_mod, SEXP R_mod, SEXP dbg_mod); // Not in public API
SEXP luajr_open();
SEXP luajr_reset();
lua_State* luajr_newstate();
lua_State* luajr_getstate(SEXP Lx);

// Move values between R and Lua (push_to.cpp)
void luajr_pushsexp(lua_State* L, SEXP x, char as);
SEXP luajr_tosexp(lua_State* L, int index);
void luajr_pass(lua_State* L, SEXP args, const char* acode);
SEXP luajr_return(lua_State* L, int nret);

// Run Lua code and functions (run_func.cpp)
SEXP luajr_run_code(SEXP code, SEXP Lx);
SEXP luajr_run_file(SEXP filename, SEXP Lx);
SEXP luajr_func_create(SEXP func, SEXP Lx);
SEXP luajr_func_call(SEXP fx, SEXP alist, SEXP acode, SEXP Lx);
SEXP luajr_func_call0(SEXP fx, SEXP acode, SEXP Lx);
SEXP luajr_func_call1(SEXP fx, SEXP a1, SEXP acode, SEXP Lx);
SEXP luajr_func_call2(SEXP fx, SEXP a1, SEXP a2, SEXP acode, SEXP Lx);
SEXP luajr_func_call3(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP acode, SEXP Lx);
SEXP luajr_func_call4(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP acode, SEXP Lx);
SEXP luajr_func_call5(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP acode, SEXP Lx);
SEXP luajr_func_call6(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP acode, SEXP Lx);
SEXP luajr_func_call7(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP a7, SEXP acode, SEXP Lx);
SEXP luajr_func_call8(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP a7, SEXP a8, SEXP acode, SEXP Lx);
SEXP luajr_func_info(SEXP fx);  // Not in public API
void luajr_pushfunc(SEXP fx);
int luajr_wrap_function(lua_State* L);  // lua_CFunction; not in public API

// Load and access Lua modules (module.cpp)
SEXP luajr_module_load(SEXP filename, SEXP Lx);
SEXP luajr_module_get(SEXP module, SEXP keys, SEXP typecheck);
SEXP luajr_module_set(SEXP module, SEXP keys, SEXP as, SEXP value);

// Run Lua code in parallel (parallel.cpp)
SEXP luajr_run_parallel(SEXP func, SEXP n, SEXP threads, SEXP pre);

// Load and call Lua code, and control tooling (tools.cpp)
void luajr_loadstring(lua_State* L, const char* str);
void luajr_dostring(lua_State* L, const char* str, int tooling);
void luajr_loadfile(lua_State* L, const char* filename);
void luajr_dofile(lua_State* L, const char* filename, int tooling);
void luajr_loadbuffer(lua_State *L, const char *buff, unsigned int sz, const char *name);
int luajr_pcall(lua_State* L, int nargs, int nresults, const char* what, int tooling);
SEXP luajr_set_mode(SEXP debug, SEXP profile, SEXP jit);
SEXP luajr_get_mode();
int luajr_debug_mode();
int luajr_profile_mode();
void luajr_profile_collect(lua_State* L);
SEXP luajr_profile_data(SEXP flush);
void luajr_tooling_cleanup(lua_State* L); // Not in public API

// Miscellaneous functions (setup.cpp)
SEXP luajr_makepointer(void* ptr, int tag_code, void (*finalize)(SEXP));
void* luajr_getpointer(SEXP x, int tag_code);
int luajr_handle_lua_error(lua_State* L, int err, const char* what, char* buf); // Not in public API
SEXP luajr_readline(SEXP prompt);   // Not in public API
void luajr_pop_stop(lua_State* L, int n, const char* fmt, ...); // Not in public API

// Access to Lua C API (lua_internal.cpp)
SEXP luajr_lua_gettop(SEXP Lx); // Not in public API

} // end of extern "C"

// External pointer code tags, for use with luajr_makepointer and luajr_getpointer
enum
{
    // For luajr_func_create, luajr_pushfunc, and luajr_tosexp with functions
    LUAJR_REGFUNC_CODE = 0x7CA12E6F,

    // For luajr_open and luajr_getstate's use of external pointers
    LUAJR_STATE_CODE = 0x7CA57A7E,

    // For luajr_module
    LUAJR_MODULE_CODE = 0x7CA1110D
};


#define CheckSEXP(x, type)         if (TYPEOF(x) != type)                        { Rf_error("%s expects %s to be of type %s", __func__, #x, Rf_type2char(type)); }
#define CheckSEXPLen(x, type, len) if (TYPEOF(x) != type || Rf_length(x) != len) { Rf_error("%s expects %s to be of length %d and type %s", __func__, #x, len, Rf_type2char(type)); }

#include "../inst/include/luajr_const.h"
