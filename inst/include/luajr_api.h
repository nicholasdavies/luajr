#ifndef LUAJR_API_H
#define LUAJR_API_H

struct SEXPREC;
typedef struct SEXPREC* SEXP;

// Lua and LuaJIT APIs
#include "luajr_lua.h"
#include "luajr_lauxlib.h"
#include "luajr_lualib.h"
#include "luajr_luajit.h"

// luajr API functions
// TODO this is easy to break if these do not match API funcs defined elsewhere.
SEXP (*luajr_open)();
lua_State* (*luajr_newstate)();
void (*luajr_reset)();
lua_State* (*luajr_getstate)(SEXP Lx);
void (*luajr_pass)(lua_State* L, SEXP args, const char* acode);
SEXP (*luajr_return)(lua_State* L, int nret);
void (*luajr_pushsexp)(lua_State* L, SEXP x, char as);
SEXP (*luajr_tosexp)(lua_State* L, int index);
SEXP (*luajr_makepointer)(void* ptr, int tag_code, void (*finalize)(SEXP));
void* (*luajr_getpointer)(SEXP x, int tag_code);
void (*luajr_pcall)(lua_State* L, int nargs, int nresults, const char* funcdesc);

#endif // LUAJR_API_H
