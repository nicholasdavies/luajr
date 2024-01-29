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
extern int luajr_return_info;
extern int luajr_return_copy;

// We declare all functions to have C linkage to avoid name mangling and allow
// the use of the package functions from C code. This file (shared.h) is only
// included when building the R package, i.e. from C++, so no #ifdef __cplusplus
// wrapper is needed here.
extern "C" {

// Lua state related functions (state.cpp)
SEXP luajr_locate_dylib(SEXP path);
SEXP luajr_locate_module(SEXP path);
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

// Run Lua code in parallel (parallel.cpp)
SEXP luajr_run_parallel(SEXP func, SEXP n, SEXP threads, SEXP pre);

// Miscellaneous functions (setup.cpp)
SEXP luajr_makepointer(void* ptr, int tag_code, void (*finalize)(SEXP));
void* luajr_getpointer(SEXP x, int tag_code);
void luajr_pcall(lua_State* L, int nargs, int nresults, const char* funcdesc);

} // end of extern "C"

// Type codes, for use with the Lua FFI
enum
{
    LOGICAL_T = 0, INTEGER_T = 1, NUMERIC_T = 2, CHARACTER_T = 3,
    REFERENCE_T = 0, VECTOR_T = 4, LIST_T = 8, NULL_T = 16
};

#define CheckSEXP(x, type, len) if (TYPEOF(x) != type || Rf_length(x) != len) { Rf_error("%s expects argument %s to be a length-%d of type %s", __func__, #x, len, Rf_type2char(type)); }
