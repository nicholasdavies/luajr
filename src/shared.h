// Forward declarations
struct lua_State;
struct SEXPREC;
typedef SEXPREC* SEXP;

// The shared global Lua state
extern lua_State* L0;

// luajr Lua module API registry keys
extern int luajr_construct_ref;
extern int luajr_construct_vec;
extern int luajr_construct_list;
extern int luajr_construct_null;
extern int luajr_return_info;
extern int luajr_return_copy;

// We declare all functions to have C linkage to avoid name mangling and allow
// the use of the package functions from C code. This file (shared.h) is only
// included when building the R package, i.e. from C++, so no #ifdef __cplusplus
// wrapper is needed here.
extern "C" {

// Declare luajr API functions in src/shared.h, inst/include/luajr.h, and inst/include/luajr_funcs.h.

// Lua state related functions (state.cpp)
SEXP luajr_locate_dylib(SEXP path);     // Not in public API
SEXP luajr_locate_module(SEXP path);    // Not in public API
SEXP luajr_locate_debugger(SEXP path);  // Not in public API
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
SEXP luajr_func_create(SEXP code, SEXP Lx);
SEXP luajr_func_call(SEXP fx, SEXP alist, SEXP acode, SEXP Lx);
void luajr_pushfunc(SEXP fx);

// Run Lua code in parallel (parallel.cpp)
SEXP luajr_run_parallel(SEXP func, SEXP n, SEXP threads, SEXP pre);

// Debugger, profiler, and JIT options (tools.cpp)
void luajr_pcall(lua_State* L, int nargs, int nresults, const char* what, int tooling);
SEXP luajr_profile_data(SEXP flush);
SEXP luajr_set_mode(SEXP debug, SEXP profile, SEXP jit);
SEXP luajr_get_mode();

// Miscellaneous functions (setup.cpp)
SEXP luajr_makepointer(void* ptr, int tag_code, void (*finalize)(SEXP));
void* luajr_getpointer(SEXP x, int tag_code);
void luajr_loadstring(lua_State* L, const char* str);
void luajr_dostring(lua_State* L, const char* str, int tooling);
void luajr_loadfile(lua_State* L, const char* filename);
void luajr_dofile(lua_State* L, const char* filename, int tooling);
void luajr_loadbuffer(lua_State *L, const char *buff, unsigned int sz, const char *name);
int luajr_handle_lua_error(lua_State* L, int err, const char* what, char* buf); // Not in public API
SEXP luajr_readline(SEXP prompt);   // Not in public API

// Access to Lua C API (lua_internal.cpp)
SEXP luajr_lua_gettop(SEXP Lx);     // Not in public API

} // end of extern "C"

// Type codes, for use with the Lua FFI
enum
{
    LOGICAL_T = 0, INTEGER_T = 1, NUMERIC_T = 2, CHARACTER_T = 3,
    REFERENCE_T = 0, VECTOR_T = 4, LIST_T = 8, NULL_T = 16,
};

#define CheckSEXP(x, type)         if (TYPEOF(x) != type)                        { Rf_error("%s expects %s to be of type %s", __func__, #x, Rf_type2char(type)); }
#define CheckSEXPLen(x, type, len) if (TYPEOF(x) != type || Rf_length(x) != len) { Rf_error("%s expects %s to be of length %d and type %s", __func__, #x, len, Rf_type2char(type)); }

#include "../inst/include/luajr_const.h"
