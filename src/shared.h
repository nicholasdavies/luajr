// R headers
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// Forward declarations
struct lua_State;
struct workers_t;

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
int luajr_thisstate(lua_State* L); // Not in public API (lua_CFunction)

// Move values between R and Lua (push_to.cpp)
void luajr_pushsexp(lua_State* L, SEXP x, unsigned char as);
SEXP luajr_tosexp(lua_State* L, int index);
void luajr_pass(lua_State* L, SEXP args, SEXP acode);
SEXP luajr_return(lua_State* L, int nret);
void luajr_xpush(lua_State* L, int index, lua_State* to);
int luajr_Rcall(lua_State* L); // Not in public API

// Run Lua code and functions (run_func.cpp)
SEXP luajr_run_code(SEXP code, SEXP Lx);
SEXP luajr_run_file(SEXP filename, SEXP Lx);
SEXP luajr_func_create(SEXP func, SEXP Lx);
SEXP luajr_func_call(SEXP fx, SEXP alist, SEXP acode, SEXP Lx);
SEXP luajr_func_call0(SEXP fx, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_func_call1(SEXP fx, SEXP a1, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_func_call2(SEXP fx, SEXP a1, SEXP a2, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_func_call3(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_func_call4(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_func_call5(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_func_call6(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_func_call7(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP a7, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_func_call8(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP a7, SEXP a8, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_func_info(SEXP fx); // Not in public API
void luajr_pushfunc(SEXP fx);

// Load and access Lua modules (module.cpp)
SEXP luajr_module_load(SEXP filename, SEXP Lx);
SEXP luajr_module_get(SEXP module, SEXP keys, SEXP typecheck);
SEXP luajr_module_set(SEXP module, SEXP keys, SEXP as, SEXP value);

// Run Lua code in parallel (parallel.cpp)
int luajr_parallel_ncores(); // Not in public API
void luajr_parallel_newworkers(lua_State* L, workers_t* w); // Not in public API
void luajr_parallel_closeworkers(workers_t* w); // Not in public API
int luajr_parallel_load(lua_State* L); // Not in public API
void luajr_parallel_srun(lua_State* L, workers_t* w); // Not in public API
void luajr_parallel_prun(lua_State* L, workers_t* w); // Not in public API
void luajr_parallel_pfor(lua_State* L, workers_t* w, int i0, int i1); // Not in public API

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
void luajr_error(lua_State* L, const char* fmt, ...) __attribute__((noreturn));

// Access to Lua C API (lua_internal.cpp)
SEXP luajr_lua_gettop(SEXP Lx); // Not in public API

// LuaJIT internal helpers (local/lj_luajr.c -> luajit/src/lj_luajr.c)
void luajr_push_sexp_cdata(lua_State* L, void* x); // Not in public API
void luajr_push_vector_cdata(lua_State* L, int sxp_type, void* p, void* s, double n, double c); // Not in public API
ptrdiff_t luajr_get_sexp_cdata(lua_State* L, int index, void** out_s); // Not in public API
void luajr_push_environment_cdata(lua_State* L, void* s); // Not in public API
void luajr_push_function_cdata(lua_State* L, void* s); // Not in public API
void luajr_table_sizes(lua_State* L, int index, uint32_t* asize, uint32_t* hsize); // Not in public API
int luajr_get_pointer_cdata(lua_State* L, int index, void** out_p); // Not in public API
int luajr_state_in_pcall(lua_State* L); // Not in public API

} // end of extern "C"

// Argcode values: type in bits 0-4, modifiers in bits 5-7.
namespace AC {
    enum {
        value       = 0,
        sexp        = 1,
        symbol      = 2,
        pairlist    = 3,
        function    = 4,
        environment = 5,
        language    = 6,
        logical     = 7,
        integer     = 8,
        numeric     = 9,
        complex     = 10,
        character   = 11,
        list        = 12,
        expression  = 13,
        raw         = 14,
        pointer     = 15,
        type_mask   = 31,
        native      = 32,
        reference   = 64,
        strict      = 128
    };
}

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
