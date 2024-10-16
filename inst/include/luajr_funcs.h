// Lua API functions

// lua.h / luajr_lua.h
API_FUNCTION(lua_State *, lua_newstate, lua_Alloc f, void *ud)
API_FUNCTION(void, lua_close, lua_State *L)
API_FUNCTION(lua_State *, lua_newthread, lua_State *L)
API_FUNCTION(lua_CFunction, lua_atpanic, lua_State *L, lua_CFunction panicf)
API_FUNCTION(int, lua_gettop, lua_State *L)
API_FUNCTION(void, lua_settop, lua_State *L, int idx)
API_FUNCTION(void, lua_pushvalue, lua_State *L, int idx)
API_FUNCTION(void, lua_remove, lua_State *L, int idx)
API_FUNCTION(void, lua_insert, lua_State *L, int idx)
API_FUNCTION(void, lua_replace, lua_State *L, int idx)
API_FUNCTION(int, lua_checkstack, lua_State *L, int sz)
API_FUNCTION(void, lua_xmove, lua_State *from, lua_State *to, int n)
API_FUNCTION(int, lua_isnumber, lua_State *L, int idx)
API_FUNCTION(int, lua_isstring, lua_State *L, int idx)
API_FUNCTION(int, lua_iscfunction, lua_State *L, int idx)
API_FUNCTION(int, lua_isuserdata, lua_State *L, int idx)
API_FUNCTION(int, lua_type, lua_State *L, int idx)
API_FUNCTION(const char *, lua_typename, lua_State *L, int tp)
API_FUNCTION(int, lua_equal, lua_State *L, int idx1, int idx2)
API_FUNCTION(int, lua_rawequal, lua_State *L, int idx1, int idx2)
API_FUNCTION(int, lua_lessthan, lua_State *L, int idx1, int idx2)
API_FUNCTION(lua_Number, lua_tonumber, lua_State *L, int idx)
API_FUNCTION(lua_Integer, lua_tointeger, lua_State *L, int idx)
API_FUNCTION(int, lua_toboolean, lua_State *L, int idx)
API_FUNCTION(const char*, lua_tolstring, lua_State *L, int idx, size_t *len)
API_FUNCTION(size_t, lua_objlen, lua_State *L, int idx)
API_FUNCTION(lua_CFunction, lua_tocfunction, lua_State *L, int idx)
API_FUNCTION(void*, lua_touserdata, lua_State *L, int idx)
API_FUNCTION(lua_State*, lua_tothread, lua_State *L, int idx)
API_FUNCTION(const void*, lua_topointer, lua_State *L, int idx)
API_FUNCTION(void, lua_pushnil, lua_State *L)
API_FUNCTION(void, lua_pushnumber, lua_State *L, lua_Number n)
API_FUNCTION(void, lua_pushinteger, lua_State *L, lua_Integer n)
API_FUNCTION(void, lua_pushlstring, lua_State *L, const char *s, size_t l)
API_FUNCTION(void, lua_pushstring, lua_State *L, const char *s)
API_FUNCTION(const char *, lua_pushvfstring, lua_State *L, const char *fmt, va_list argp)
API_FUNCTION(const char *, lua_pushfstring, lua_State *L, const char *fmt, ...)
API_FUNCTION(void, lua_pushcclosure, lua_State *L, lua_CFunction fn, int n)
API_FUNCTION(void, lua_pushboolean, lua_State *L, int b)
API_FUNCTION(void, lua_pushlightuserdata, lua_State *L, void *p)
API_FUNCTION(int, lua_pushthread, lua_State *L)
API_FUNCTION(void, lua_gettable, lua_State *L, int idx)
API_FUNCTION(void, lua_getfield, lua_State *L, int idx, const char *k)
API_FUNCTION(void, lua_rawget, lua_State *L, int idx)
API_FUNCTION(void, lua_rawgeti, lua_State *L, int idx, int n)
API_FUNCTION(void, lua_createtable, lua_State *L, int narr, int nrec)
API_FUNCTION(void *, lua_newuserdata, lua_State *L, size_t sz)
API_FUNCTION(int, lua_getmetatable, lua_State *L, int objindex)
API_FUNCTION(void, lua_getfenv, lua_State *L, int idx)
API_FUNCTION(void, lua_settable, lua_State *L, int idx)
API_FUNCTION(void, lua_setfield, lua_State *L, int idx, const char *k)
API_FUNCTION(void, lua_rawset, lua_State *L, int idx)
API_FUNCTION(void, lua_rawseti, lua_State *L, int idx, int n)
API_FUNCTION(int, lua_setmetatable, lua_State *L, int objindex)
API_FUNCTION(int, lua_setfenv, lua_State *L, int idx)
API_FUNCTION(void, lua_call, lua_State *L, int nargs, int nresults)
API_FUNCTION(int, lua_pcall, lua_State *L, int nargs, int nresults, int errfunc)
API_FUNCTION(int, lua_cpcall, lua_State *L, lua_CFunction func, void *ud)
API_FUNCTION(int, lua_load, lua_State *L, lua_Reader reader, void *dt, const char *chunkname)
API_FUNCTION(int, lua_dump, lua_State *L, lua_Writer writer, void *data)
API_FUNCTION(int, lua_yield, lua_State *L, int nresults)
API_FUNCTION(int, lua_resume, lua_State *L, int narg)
API_FUNCTION(int, lua_status, lua_State *L)
API_FUNCTION(int, lua_gc, lua_State *L, int what, int data)
API_FUNCTION(int, lua_error, lua_State *L)
API_FUNCTION(int, lua_next, lua_State *L, int idx)
API_FUNCTION(void, lua_concat, lua_State *L, int n)
API_FUNCTION(lua_Alloc, lua_getallocf, lua_State *L, void **ud)
API_FUNCTION(void, lua_setallocf, lua_State *L, lua_Alloc f, void *ud)
API_FUNCTION(int, lua_getstack, lua_State *L, int level, lua_Debug *ar)
API_FUNCTION(int, lua_getinfo, lua_State *L, const char *what, lua_Debug *ar)
API_FUNCTION(const char *, lua_getlocal, lua_State *L, const lua_Debug *ar, int n)
API_FUNCTION(const char *, lua_setlocal, lua_State *L, const lua_Debug *ar, int n)
API_FUNCTION(const char *, lua_getupvalue, lua_State *L, int funcindex, int n)
API_FUNCTION(const char *, lua_setupvalue, lua_State *L, int funcindex, int n)
API_FUNCTION(int, lua_sethook, lua_State *L, lua_Hook func, int mask, int count)
API_FUNCTION(lua_Hook, lua_gethook, lua_State *L)
API_FUNCTION(int, lua_gethookmask, lua_State *L)
API_FUNCTION(int, lua_gethookcount, lua_State *L)
API_FUNCTION(void *, lua_upvalueid, lua_State *L, int idx, int n)
API_FUNCTION(void, lua_upvaluejoin, lua_State *L, int idx1, int n1, int idx2, int n2)
API_FUNCTION(int, lua_loadx, lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode)
API_FUNCTION(const lua_Number *, lua_version, lua_State *L)
API_FUNCTION(void, lua_copy, lua_State *L, int fromidx, int toidx)
API_FUNCTION(lua_Number, lua_tonumberx, lua_State *L, int idx, int *isnum)
API_FUNCTION(lua_Integer, lua_tointegerx, lua_State *L, int idx, int *isnum)
API_FUNCTION(int, lua_isyieldable, lua_State *L)

// lauxlib.h / luajr_lauxlib.h
API_FUNCTION(void, luaL_openlib, lua_State *L, const char *libname, const luaL_Reg *l, int nup)
API_FUNCTION(void, luaL_register, lua_State *L, const char *libname, const luaL_Reg *l)
API_FUNCTION(int, luaL_getmetafield, lua_State *L, int obj, const char *e)
API_FUNCTION(int, luaL_callmeta, lua_State *L, int obj, const char *e)
API_FUNCTION(int, luaL_typerror, lua_State *L, int narg, const char *tname)
API_FUNCTION(int, luaL_argerror, lua_State *L, int numarg, const char *extramsg)
API_FUNCTION(const char *, luaL_checklstring, lua_State *L, int numArg, size_t *l)
API_FUNCTION(const char *, luaL_optlstring, lua_State *L, int numArg, const char *def, size_t *l)
API_FUNCTION(lua_Number, luaL_checknumber, lua_State *L, int numArg)
API_FUNCTION(lua_Number, luaL_optnumber, lua_State *L, int nArg, lua_Number def)
API_FUNCTION(lua_Integer, luaL_checkinteger, lua_State *L, int numArg)
API_FUNCTION(lua_Integer, luaL_optinteger, lua_State *L, int nArg, lua_Integer def)
API_FUNCTION(void, luaL_checkstack, lua_State *L, int sz, const char *msg)
API_FUNCTION(void, luaL_checktype, lua_State *L, int narg, int t)
API_FUNCTION(void, luaL_checkany, lua_State *L, int narg)
API_FUNCTION(int, luaL_newmetatable, lua_State *L, const char *tname)
API_FUNCTION(void *, luaL_checkudata, lua_State *L, int ud, const char *tname)
API_FUNCTION(void, luaL_where, lua_State *L, int lvl)
API_FUNCTION(int, luaL_error, lua_State *L, const char *fmt, ...)
API_FUNCTION(int, luaL_checkoption, lua_State *L, int narg, const char *def, const char *const lst[])
API_FUNCTION(int, luaL_ref, lua_State *L, int t)
API_FUNCTION(void, luaL_unref, lua_State *L, int t, int ref)
API_FUNCTION(int, luaL_loadfile, lua_State *L, const char *filename)
API_FUNCTION(int, luaL_loadbuffer, lua_State *L, const char *buff, size_t sz, const char *name)
API_FUNCTION(int, luaL_loadstring, lua_State *L, const char *s)
API_FUNCTION(lua_State *, luaL_newstate, void)
API_FUNCTION(const char *, luaL_gsub, lua_State *L, const char *s, const char *p, const char *r)
API_FUNCTION(const char *, luaL_findtable, lua_State *L, int idx, const char *fname, int szhint)
API_FUNCTION(int, luaL_fileresult, lua_State *L, int stat, const char *fname)
API_FUNCTION(int, luaL_execresult, lua_State *L, int stat)
API_FUNCTION(int, luaL_loadfilex, lua_State *L, const char *filename, const char *mode)
API_FUNCTION(int, luaL_loadbufferx, lua_State *L, const char *buff, size_t sz, const char *name, const char *mode)
API_FUNCTION(void, luaL_traceback, lua_State *L, lua_State *L1, const char *msg, int level)
API_FUNCTION(void, luaL_setfuncs, lua_State *L, const luaL_Reg *l, int nup)
API_FUNCTION(void, luaL_pushmodule, lua_State *L, const char *modname, int sizehint)
API_FUNCTION(void *, luaL_testudata, lua_State *L, int ud, const char *tname)
API_FUNCTION(void, luaL_setmetatable, lua_State *L, const char *tname)
API_FUNCTION(void, luaL_buffinit, lua_State *L, luaL_Buffer *B)
API_FUNCTION(char *, luaL_prepbuffer, luaL_Buffer *B)
API_FUNCTION(void, luaL_addlstring, luaL_Buffer *B, const char *s, size_t l)
API_FUNCTION(void, luaL_addstring, luaL_Buffer *B, const char *s)
API_FUNCTION(void, luaL_addvalue, luaL_Buffer *B)
API_FUNCTION(void, luaL_pushresult, luaL_Buffer *B)

// lualib.h / luajr_lualib.h
API_FUNCTION(int, luaopen_base, lua_State *L)
API_FUNCTION(int, luaopen_math, lua_State *L)
API_FUNCTION(int, luaopen_string, lua_State *L)
API_FUNCTION(int, luaopen_table, lua_State *L)
API_FUNCTION(int, luaopen_io, lua_State *L)
API_FUNCTION(int, luaopen_os, lua_State *L)
API_FUNCTION(int, luaopen_package, lua_State *L)
API_FUNCTION(int, luaopen_debug, lua_State *L)
API_FUNCTION(int, luaopen_bit, lua_State *L)
API_FUNCTION(int, luaopen_jit, lua_State *L)
API_FUNCTION(int, luaopen_ffi, lua_State *L)
API_FUNCTION(int, luaopen_string_buffer, lua_State *L)
API_FUNCTION(void, luaL_openlibs, lua_State *L)

// luajit.h / luajr_luajit.h
API_FUNCTION(int, luaJIT_setmode, lua_State *L, int idx, int mode)
API_FUNCTION(void, luaJIT_profile_start, lua_State *L, const char *mode, luaJIT_profile_callback cb, void *data)
API_FUNCTION(void, luaJIT_profile_stop, lua_State *L)
API_FUNCTION(const char *, luaJIT_profile_dumpstack, lua_State *L, const char *fmt, int depth, size_t *len)

// Specific to luajr
// Declare luajr API functions in src/shared.h, inst/include/luajr.h, and inst/include/luajr_funcs.h.
API_FUNCTION(SEXP, luajr_open, void)
API_FUNCTION(SEXP, luajr_reset, void)
API_FUNCTION(lua_State*, luajr_newstate, void)
API_FUNCTION(lua_State*, luajr_getstate, SEXP Lx)
API_FUNCTION(void, luajr_pushsexp, lua_State* L, SEXP x, char as)
API_FUNCTION(SEXP, luajr_tosexp, lua_State* L, int index)
API_FUNCTION(void, luajr_pass, lua_State* L, SEXP args, const char* acode)
API_FUNCTION(SEXP, luajr_return, lua_State* L, int nret)
API_FUNCTION(SEXP, luajr_run_code, SEXP code, SEXP Lx)
API_FUNCTION(SEXP, luajr_run_file, SEXP filename, SEXP Lx)
API_FUNCTION(SEXP, luajr_func_create, SEXP code, SEXP Lx)
API_FUNCTION(SEXP, luajr_func_call, SEXP fx, SEXP alist, SEXP acode, SEXP Lx)
API_FUNCTION(void, luajr_pushfunc, SEXP fx)
API_FUNCTION(SEXP, luajr_run_parallel, SEXP func, SEXP n, SEXP threads, SEXP pre)
API_FUNCTION(void, luajr_loadstring, lua_State* L, const char* str)
API_FUNCTION(void, luajr_dostring, lua_State* L, const char* str, int tooling)
API_FUNCTION(void, luajr_loadfile, lua_State* L, const char* filename)
API_FUNCTION(void, luajr_dofile, lua_State* L, const char* filename, int tooling)
API_FUNCTION(void, luajr_loadbuffer, lua_State *L, const char *buff, unsigned int sz, const char *name)
API_FUNCTION(int, luajr_pcall, lua_State* L, int nargs, int nresults, const char* what, int tooling)
API_FUNCTION(SEXP, luajr_set_mode, SEXP debug, SEXP profile, SEXP jit)
API_FUNCTION(SEXP, luajr_get_mode, void)
API_FUNCTION(int, luajr_debug_mode, void)
API_FUNCTION(int, luajr_profile_mode, void)
API_FUNCTION(void, luajr_profile_collect, lua_State* L)
API_FUNCTION(SEXP, luajr_profile_data, SEXP flush)
API_FUNCTION(SEXP, luajr_makepointer, void* ptr, int tag_code, void (*finalize)(SEXP))
API_FUNCTION(void*, luajr_getpointer, SEXP x, int tag_code)
