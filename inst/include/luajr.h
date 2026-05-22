#ifndef LUAJR_API_H
#define LUAJR_API_H

struct SEXPREC;
typedef struct SEXPREC* SEXP;

// Lua and LuaJIT APIs
#include "luajr_lua.h"
#include "luajr_lauxlib.h"
#include "luajr_lualib.h"
#include "luajr_luajit.h"
#include "luajr_const.h"

// luajr API functions
// Declare luajr API functions in src/shared.h, inst/include/luajr.h, and inst/include/luajr_funcs.h.
// Also, if the function should be available to the R package, keep current in setup.cpp.
extern SEXP (*luajr_open)();
extern SEXP (*luajr_reset)();
extern lua_State* (*luajr_newstate)();
extern lua_State* (*luajr_getstate)(SEXP Lx);
extern void (*luajr_pushsexp)(lua_State* L, SEXP x, unsigned char as);
extern SEXP (*luajr_tosexp)(lua_State* L, int index);
extern void (*luajr_pass)(lua_State* L, SEXP args, SEXP acode);
extern SEXP (*luajr_return)(lua_State* L, int nret);
extern void (*luajr_xpush)(lua_State* L, int index, lua_State* dst);
extern SEXP (*luajr_runcode)(SEXP code, SEXP Lx);
extern SEXP (*luajr_runfile)(SEXP filename, SEXP Lx);
extern SEXP (*luajr_fcreate)(SEXP func, SEXP Lx);
extern SEXP (*luajr_fcall)(SEXP fx, SEXP alist, SEXP acode, SEXP Lx);
extern void (*luajr_pushfunc)(SEXP fx);
extern SEXP (*luajr_loadmodule)(SEXP filename, SEXP Lx);
extern SEXP (*luajr_moduleget)(SEXP module, SEXP keys, SEXP typecheck);
extern SEXP (*luajr_moduleset)(SEXP module, SEXP keys, SEXP as, SEXP value);
extern void (*luajr_loadstring)(lua_State* L, const char* str);
extern void (*luajr_dostring)(lua_State* L, const char* str, int tooling);
extern void (*luajr_loadfile)(lua_State* L, const char* filename);
extern void (*luajr_dofile)(lua_State* L, const char* filename, int tooling);
extern void (*luajr_loadbuffer)(lua_State *L, const char *buff, unsigned int sz, const char *name);
extern int (*luajr_pcall)(lua_State* L, int nargs, int nresults, const char* what, int tooling);
extern SEXP (*luajr_setmode)(SEXP debug, SEXP profile, SEXP jit);
extern SEXP (*luajr_getmode)();
extern int (*luajr_indebug)();
extern int (*luajr_inprofile)();
extern void (*luajr_flushprofile)(lua_State* L);
extern SEXP (*luajr_getprofile)(SEXP flush);
extern SEXP (*luajr_makepointer)(void* ptr, int tag_code, void (*finalize)(SEXP));
extern void* (*luajr_getpointer)(SEXP x, int tag_code);
extern void (*luajr_error)(lua_State* L, const char* fmt, ...);

#endif // LUAJR_API_H
