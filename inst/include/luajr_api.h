#ifndef LUAJR_API_H
#define LUAJR_API_H

// R
#include <R.h>
#include <Rinternals.h>

// Lua and LuaJIT APIs
#include "luajr_lua.h"
#include "luajr_lauxlib.h"
#include "luajr_lualib.h"
#include "luajr_luajit.h"

// luajr API functions
// TODO this is easy to break if these do not match API funcs defined elsewhere.
// TODO update here, and in luajr_api.h, all the funcs we want to expose to users; make all these funcs extern "C"; make the rest static.
extern void (*luajr_pass)(lua_State* L, SEXP args, const char* acode);
extern SEXP (*luajr_return)(lua_State* L, int nret);
extern void (*luajr_pushsexp)(lua_State* L, SEXP x, char as);
extern SEXP (*luajr_tosexp)(lua_State* L, int index);
extern SEXP (*luajr_open)();
extern lua_State* (*luajr_getstate)(SEXP Lx);

#endif // LUAJR_API_H
