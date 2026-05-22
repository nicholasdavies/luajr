// R headers
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include <cstdint>

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
SEXP luajr_register(SEXP Rver, SEXP dylib, SEXP R_lib, SEXP luajr_mod, SEXP R_mod, SEXP dbg_mod); // Not in public API
SEXP luajr_open();
SEXP luajr_reset();
lua_State* luajr_newstate();
lua_State* luajr_getstate(SEXP Lx);
int luajr_thisstate_cf(lua_State* L); // Not in public API (lua_CFunction)

// Move values between R and Lua (push_to.cpp)
void luajr_pushsexp(lua_State* L, SEXP x, unsigned char as);
SEXP luajr_tosexp(lua_State* L, int index);
void luajr_pass(lua_State* L, SEXP args, SEXP acode);
SEXP luajr_return(lua_State* L, int nret);
void luajr_xpush(lua_State* L, int index, lua_State* to);
int luajr_rcall_cf(lua_State* L); // Not in public API (lua_CFunction)
int luajr_tosexp_cf(lua_State* L); // Not in public API (lua_CFunction)
int luajr_fromsexp_cf(lua_State* L); // Not in public API (lua_CFunction)

// Run Lua code and functions (run_func.cpp)
SEXP luajr_runcode(SEXP code, SEXP Lx);
SEXP luajr_runfile(SEXP filename, SEXP Lx);
SEXP luajr_fcreate(SEXP func, SEXP Lx);
SEXP luajr_fcall(SEXP fx, SEXP alist, SEXP acode, SEXP Lx);
SEXP luajr_fcall0(SEXP fx, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_fcall1(SEXP fx, SEXP a1, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_fcall2(SEXP fx, SEXP a1, SEXP a2, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_fcall3(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_fcall4(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_fcall5(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_fcall6(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_fcall7(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP a7, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_fcall8(SEXP fx, SEXP a1, SEXP a2, SEXP a3, SEXP a4, SEXP a5, SEXP a6, SEXP a7, SEXP a8, SEXP acode, SEXP Lx); // Not in public API
SEXP luajr_finfo(SEXP fx); // Not in public API
void luajr_pushfunc(SEXP fx);

// Load and access Lua modules (module.cpp)
SEXP luajr_loadmodule(SEXP filename, SEXP Lx);
SEXP luajr_moduleget(SEXP module, SEXP keys, SEXP typecheck);
SEXP luajr_moduleset(SEXP module, SEXP keys, SEXP as, SEXP value);

// Run Lua code in parallel (parallel.cpp)
int luajr_parallel_ncores(); // Not in public API
void luajr_parallel_newworkers(lua_State* L, workers_t* w); // Not in public API
void luajr_parallel_closeworkers(workers_t* w); // Not in public API
int luajr_parallel_load_cf(lua_State* L); // Not in public API (lua_CFunction)
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
SEXP luajr_setmode(SEXP debug, SEXP profile, SEXP jit);
SEXP luajr_getmode();
int luajr_indebug();
int luajr_inprofile();
void luajr_flushprofile(lua_State* L);
SEXP luajr_getprofile(SEXP flush);
void luajr_closeprofile(lua_State* L); // Not in public API

// Miscellaneous functions (setup.cpp)
SEXP luajr_makepointer(void* ptr, int tag_code, void (*finalize)(SEXP));
void* luajr_getpointer(SEXP x, int tag_code);
int luajr_handleerror(lua_State* L, int err, const char* what, char* buf); // Not in public API
SEXP luajr_readline(SEXP prompt);   // Not in public API
void luajr_popstop(lua_State* L, int n, const char* fmt, ...); // Not in public API
void luajr_error(lua_State* L, const char* fmt, ...) __attribute__((noreturn));

// LuaJIT internal helpers (local/lj_luajr.c -> luajit/src/lj_luajr.c)
void luajr_internal_pushsexp(lua_State* L, void* x); // Not in public API
void luajr_internal_pushvector(lua_State* L, int sxp_type, void* p, void* s, double n, double c); // Not in public API
void luajr_internal_pushenvironment(lua_State* L, void* s); // Not in public API
void luajr_internal_pushrfunction(lua_State* L, void* s); // Not in public API
ptrdiff_t luajr_internal_tosexp(lua_State* L, int index, void** out_s); // Not in public API
int luajr_internal_topointer(lua_State* L, int index, void** out_p); // Not in public API
void luajr_internal_tablesize(lua_State* L, int index, uint32_t* asize, uint32_t* hsize); // Not in public API
int luajr_internal_inpcall(lua_State* L); // Not in public API

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
    // For luajr_fcreate, luajr_pushfunc, and luajr_tosexp with functions
    LUAJR_REGFUNC_CODE = 0x7CA12E6F,

    // For luajr_open and luajr_getstate's use of external pointers
    LUAJR_STATE_CODE = 0x7CA57A7E,

    // For luajr_module
    LUAJR_MODULE_CODE = 0x7CA1110D
};


#define CheckSEXP(x, type)         if (TYPEOF(x) != type)                        { Rf_error("%s expects %s to be of type %s", __func__, #x, Rf_type2char(type)); }
#define CheckSEXPLen(x, type, len) if (TYPEOF(x) != type || Rf_length(x) != len) { Rf_error("%s expects %s to be of length %d and type %s", __func__, #x, len, Rf_type2char(type)); }

#include "../inst/include/luajr_const.h"
