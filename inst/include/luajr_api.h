#ifndef LUAJR_API_H
#define LUAJR_API_H

// Rcpp
#include <Rcpp.h>

// Lua and LuaJIT APIs
#include "luajr_lua.h"
#include "luajr_lauxlib.h"
#include "luajr_lualib.h"
#include "luajr_luajit.h"

// luajr API functions
extern void (*R_pass_to_Lua)(lua_State* L, Rcpp::List args); // TODO make second arg a SEXP; then will only need R headers and not Rcpp headers
extern SEXP (*Lua_return_to_R)(lua_State* L, int nret);
extern void (*luajr_pushsexp)(lua_State* L, SEXP x);
extern SEXP (*luajr_tosexp)(lua_State* L, int index);
extern SEXP (*luajr_open)();
extern lua_State* (*luajr_getstate)(SEXP Lxp);
extern void (*CreateReturnMatrix)(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);
extern void (*CreateReturnDataFrame)(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);

#endif // LUAJR_API_H
