// [[Rcpp::plugins(cpp11)]]

#include <Rcpp.h>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "luajit_rolling.h"
}

// Globals
extern lua_State* L0;       // The shared global Lua state
extern SEXP RObjRetSymbol;  // Cached lookup symbol for robj_ret

// Internal functions
void R_pass_to_Lua(lua_State* L, Rcpp::List args, const char* acode);
SEXP Lua_return_to_R(lua_State* L, int nret);

// C API functions
void luajr_pushsexp(lua_State* L, SEXP x, char as); // Push SEXP to Lua stack
SEXP luajr_tosexp(lua_State* L, int index);         // Get Lua value as SEXP

// R API functions and related functions
SEXP luajr_open();
lua_State* luajr_getstate(SEXP Lxp);

// Lua API functions
extern "C" void CreateReturnMatrix(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);
extern "C" void CreateReturnDataFrame(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);
